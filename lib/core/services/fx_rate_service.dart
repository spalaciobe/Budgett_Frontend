import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/fx_rate_model.dart';

/// Fetches and caches the Colombian TRM (Tasa Representativa del Mercado).
///
/// Source: datos.gov.co public API — no authentication required.
/// The rate is cached in the `fx_rates` Supabase table (shared across users).
/// If the network is unavailable the last known rate is returned marked as stale.
class FxRateService {
  final SupabaseClient _supabase;
  final http.Client _httpClient;

  static const _apiUrl =
      'https://www.datos.gov.co/resource/32sa-8pi3.json'
      '?\$order=vigenciadesde DESC&\$limit=1';

  static const _base = 'USD';
  static const _quote = 'COP';
  static const _timeoutSeconds = 8;

  FxRateService(this._supabase, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Returns today's TRM. Fetches from the API if not yet cached for today.
  /// Falls back to the most recent cached rate (marked [FxRate.isStale]) on
  /// network failure.
  Future<FxRate> getCurrentTrm() async {
    final today = _today();

    // 1. Check Supabase cache for today
    final cached = await _fetchCached(asOfDate: today);
    if (cached != null) return cached;

    // 2. Try live API
    try {
      final liveRate = await _fetchFromApi();
      if (liveRate != null) {
        await _upsertToCache(liveRate);
        return liveRate;
      }
    } catch (_) {
      // Network failure — fall through to stale fallback
    }

    // 3. Stale fallback: most recent available rate
    final stale = await _fetchCached(mostRecent: true);
    if (stale != null) return stale.copyWith(isStale: true);

    throw Exception('FxRateService: no TRM available (no cache, no network).');
  }

  // ── private helpers ──────────────────────────────────────────────────────

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<FxRate?> _fetchCached({String? asOfDate, bool mostRecent = false}) async {
    try {
      var query = _supabase
          .from('fx_rates')
          .select()
          .eq('base', _base)
          .eq('quote', _quote);

      if (asOfDate != null) {
        query = query.eq('as_of_date', asOfDate);
      }

      final result = await query
          .order('as_of_date', ascending: false)
          .limit(1);

      final rows = result as List<dynamic>;
      if (rows.isEmpty) return null;
      return FxRate.fromJson(rows.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<FxRate?> _fetchFromApi() async {
    final response = await _httpClient
        .get(Uri.parse(_apiUrl))
        .timeout(const Duration(seconds: _timeoutSeconds));

    if (response.statusCode != 200) return null;

    final List<dynamic> json = jsonDecode(response.body);
    if (json.isEmpty) return null;

    return parseApiEntry(json.first as Map<String, dynamic>);
  }

  /// Parses a single entry from the datos.gov.co TRM API response.
  ///
  /// Exposed as a static method so it can be unit-tested independently
  /// of the Supabase cache layer.
  static FxRate? parseApiEntry(Map<String, dynamic> entry) {
    final rateStr = entry['valor'] as String?;
    final dateStr = entry['vigenciadesde'] as String?;
    if (rateStr == null || dateStr == null) return null;

    final rate = double.tryParse(rateStr);
    if (rate == null) return null;

    // Parse ISO date (may include time component)
    final asOfDate = DateTime.parse(dateStr);
    final asOfDateStr =
        '${asOfDate.year}-${asOfDate.month.toString().padLeft(2, '0')}-${asOfDate.day.toString().padLeft(2, '0')}';

    return FxRate(
      id: '',
      base: 'USD',
      quote: 'COP',
      rate: rate,
      asOfDate: DateTime.parse(asOfDateStr),
      source: 'datos.gov.co',
      fetchedAt: DateTime.now(),
    );
  }

  Future<void> _upsertToCache(FxRate rate) async {
    final asOfDateStr =
        '${rate.asOfDate.year}-${rate.asOfDate.month.toString().padLeft(2, '0')}-${rate.asOfDate.day.toString().padLeft(2, '0')}';

    await _supabase.from('fx_rates').upsert(
      {
        'base': rate.base,
        'quote': rate.quote,
        'rate': rate.rate,
        'as_of_date': asOfDateStr,
        'source': rate.source,
        'fetched_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'base,quote,as_of_date',
    );
  }
}

extension _FxRateCopy on FxRate {
  FxRate copyWith({bool? isStale}) => FxRate(
        id: id,
        base: base,
        quote: quote,
        rate: rate,
        asOfDate: asOfDate,
        source: source,
        fetchedAt: fetchedAt,
        isStale: isStale ?? this.isStale,
      );
}
