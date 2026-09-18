import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budgett_frontend/core/parsing/text_normalizer.dart';
import 'package:budgett_frontend/core/utils/capture_dedup.dart';
import 'package:budgett_frontend/data/models/capture_source_model.dart';
import 'package:budgett_frontend/data/models/captured_message_model.dart';
import 'package:budgett_frontend/data/models/merchant_alias_model.dart';

/// Supabase access for the message-capture feature: sources, the alias memory,
/// the card map, and the captured-message inbox.
///
/// Mirrors [FinanceRepository]: this is the only layer that talks to Supabase
/// for these tables, and reads retry once on the JWT clock-skew error because
/// ingestion runs immediately after the app reaches the foreground.
class MessageCaptureRepository {
  final SupabaseClient _client;

  MessageCaptureRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  bool _isTransientNetworkError(Object e) {
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('ClientException');
  }

  Future<T> _withRetry<T>(Future<T> Function() fn, String errorContext) async {
    int attempts = 0;
    while (true) {
      try {
        return await fn();
      } on PostgrestException catch (e) {
        if (attempts < 1 &&
            (e.message.contains('JWT issued at future') ||
                e.code == 'PGRST303')) {
          attempts++;
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        throw Exception('$errorContext: $e');
      } catch (e) {
        if (attempts < 1 && _isTransientNetworkError(e)) {
          attempts++;
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        throw Exception('$errorContext: $e');
      }
    }
  }

  // ─── capture sources ───────────────────────────────────────────────────────

  Future<List<CaptureSource>> getSources() => _withRetry(() async {
        final List<dynamic> data = await _client
            .from('capture_sources')
            .select()
            .eq('user_id', _userId)
            .order('last_seen_at', ascending: false, nullsFirst: false);
        return data
            .map((json) =>
                CaptureSource.fromJson(json as Map<String, dynamic>))
            .toList();
      }, 'Error fetching capture sources');

  /// Records that [sourceKey] just sent a message, creating the source row the
  /// first time we see it. Never overwrites the user's `display_name`.
  ///
  /// Returns the up-to-date row so the caller can read `issuer_key`,
  /// `default_account_id` and `is_enabled` without a second round trip.
  Future<CaptureSource> registerSource({
    required String channel,
    required String sourceKey,
    String? detectedName,
    String? issuerKey,
    DateTime? seenAt,
  }) async {
    final now = (seenAt ?? DateTime.now()).toUtc().toIso8601String();

    final existing = await _client
        .from('capture_sources')
        .select()
        .eq('user_id', _userId)
        .eq('channel', channel)
        .eq('source_key', sourceKey)
        .maybeSingle();

    if (existing == null) {
      final inserted = await _client
          .from('capture_sources')
          .insert({
            'user_id': _userId,
            'channel': channel,
            'source_key': sourceKey,
            'detected_name': detectedName,
            'issuer_key': issuerKey,
            'message_count': 1,
            'last_seen_at': now,
          })
          .select()
          .single();
      return CaptureSource.fromJson(inserted);
    }

    final patch = <String, dynamic>{
      'message_count': ((existing['message_count'] as int?) ?? 0) + 1,
      'last_seen_at': now,
    };
    // Fill in gaps only — the user's own edits stay untouched.
    if (existing['detected_name'] == null && detectedName != null) {
      patch['detected_name'] = detectedName;
    }
    if (existing['issuer_key'] == null && issuerKey != null) {
      patch['issuer_key'] = issuerKey;
    }

    final updated = await _client
        .from('capture_sources')
        .update(patch)
        .eq('id', existing['id'] as String)
        .select()
        .single();
    return CaptureSource.fromJson(updated);
  }

  /// Applies a user edit to a source: the name override, the pinned issuer,
  /// the default account, or the on/off switch.
  Future<void> updateSource(String id, Map<String, dynamic> data) async {
    await _client
        .from('capture_sources')
        .update(data)
        .eq('id', id)
        .eq('user_id', _userId);
  }

  Future<void> deleteSource(String id) async {
    await _client
        .from('capture_sources')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId);
  }

  // ─── merchant aliases (the learning memory) ────────────────────────────────

  Future<List<MerchantAlias>> getAliases() => _withRetry(() async {
        final List<dynamic> data = await _client
            .from('merchant_aliases')
            .select()
            .eq('user_id', _userId)
            .order('priority')
            .order('pattern');
        return data
            .map((json) =>
                MerchantAlias.fromJson(json as Map<String, dynamic>))
            .toList();
      }, 'Error fetching merchant aliases');

  /// Creates or replaces the alias for [pattern].
  ///
  /// Upserting on `(user_id, match_type, pattern)` means teaching the same
  /// merchant twice updates the rule instead of piling up duplicates.
  Future<MerchantAlias> upsertAlias({
    required String pattern,
    required String displayName,
    String matchType = 'exact',
    String? categoryId,
    String? subCategoryId,
    String? expenseGroupId,
    String? accountId,
    String? movementType,
    bool autoPost = true,
    int priority = 100,
  }) async {
    final row = await _client
        .from('merchant_aliases')
        .upsert({
          'user_id': _userId,
          'match_type': matchType,
          'pattern': pattern,
          'display_name': displayName,
          'category_id': categoryId,
          'sub_category_id': subCategoryId,
          'expense_group_id': expenseGroupId,
          'account_id': accountId,
          'movement_type': movementType,
          'auto_post': autoPost,
          'priority': priority,
        }, onConflict: 'user_id,match_type,pattern')
        .select()
        .single();
    return MerchantAlias.fromJson(row);
  }

  Future<void> updateAlias(String id, Map<String, dynamic> data) async {
    await _client
        .from('merchant_aliases')
        .update(data)
        .eq('id', id)
        .eq('user_id', _userId);
  }

  Future<void> deleteAlias(String id) async {
    await _client
        .from('merchant_aliases')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId);
  }

  /// Bumps usage stats after an alias drove a posting. Best-effort: a failure
  /// here must never fail the expense that was just recorded.
  Future<void> touchAlias(String id, int currentHitCount) async {
    try {
      await _client
          .from('merchant_aliases')
          .update({
            'hit_count': currentHitCount + 1,
            'last_used_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .eq('user_id', _userId);
    } catch (_) {
      // Statistics only.
    }
  }

  // ─── card → account map ────────────────────────────────────────────────────

  /// Learned "last 4 digits → account" mappings, keyed `issuer|last4`.
  /// An empty issuer (`|1234`) means the mapping applies to any bank.
  Future<Map<String, String>> getCardMappings() => _withRetry(() async {
        final List<dynamic> data = await _client
            .from('capture_card_map')
            .select()
            .eq('user_id', _userId);
        final out = <String, String>{};
        for (final row in data) {
          final map = row as Map<String, dynamic>;
          final issuer = map['issuer_key'] as String? ?? '';
          final last4 = map['last4'] as String;
          out['$issuer|$last4'] = map['account_id'] as String;
        }
        return out;
      }, 'Error fetching card mappings');

  /// [issuerKey] null is stored as '' — see the column comment in the
  /// migration for why the column is NOT NULL.
  Future<void> upsertCardMapping({
    String? issuerKey,
    required String last4,
    required String accountId,
  }) async {
    await _client.from('capture_card_map').upsert({
      'user_id': _userId,
      'issuer_key': issuerKey ?? '',
      'last4': last4,
      'account_id': accountId,
    }, onConflict: 'user_id,issuer_key,last4');
  }

  // ─── captured messages ─────────────────────────────────────────────────────

  Future<List<CapturedMessage>> getCaptures({
    List<String> statuses = const ['pending'],
    int limit = 100,
  }) =>
      _withRetry(() async {
        final List<dynamic> data = await _client
            .from('captured_messages')
            .select()
            .eq('user_id', _userId)
            .inFilter('status', statuses)
            .order('received_at', ascending: false)
            .limit(limit);
        return data
            .map((json) =>
                CapturedMessage.fromJson(json as Map<String, dynamic>))
            .toList();
      }, 'Error fetching captured messages');

  Future<int> pendingCount() => _withRetry(() async {
        final List<dynamic> rows = await _client
            .from('captured_messages')
            .select('id')
            .eq('user_id', _userId)
            .eq('status', 'pending');
        return rows.length;
      }, 'Error counting pending captures');

  /// Fingerprints already stored, so the drain step can skip captures that
  /// were ingested on a previous run.
  Future<Set<String>> knownFingerprints({int lookbackDays = 7}) =>
      _withRetry(() async {
        final since = DateTime.now()
            .subtract(Duration(days: lookbackDays))
            .toUtc()
            .toIso8601String();
        final List<dynamic> data = await _client
            .from('captured_messages')
            .select('fingerprint')
            .eq('user_id', _userId)
            .gte('received_at', since);
        return data
            .map((row) => (row as Map<String, dynamic>)['fingerprint'] as String)
            .toSet();
      }, 'Error fetching capture fingerprints');

  Future<CapturedMessage> insertCapture(Map<String, dynamic> data) async {
    final row = await _client
        .from('captured_messages')
        .insert({...data, 'user_id': _userId})
        .select()
        .single();
    return CapturedMessage.fromJson(row);
  }

  Future<void> updateCapture(String id, Map<String, dynamic> data) async {
    await _client
        .from('captured_messages')
        .update(data)
        .eq('id', id)
        .eq('user_id', _userId);
  }

  Future<void> deleteCapture(String id) async {
    await _client
        .from('captured_messages')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId);
  }

  // ─── dedup lookups ─────────────────────────────────────────────────────────

  /// Captures received around [around] that could be other copies of the same
  /// payment. Narrowed by day rather than by the dedup window so a message
  /// that crosses midnight still finds its sibling.
  Future<List<CapturedMessage>> capturesNear(DateTime around,
          {Duration span = const Duration(hours: 6)}) =>
      _withRetry(() async {
        final from = around.subtract(span).toUtc().toIso8601String();
        final to = around.add(span).toUtc().toIso8601String();
        final List<dynamic> data = await _client
            .from('captured_messages')
            .select()
            .eq('user_id', _userId)
            .inFilter('status', ['pending', 'posted'])
            .gte('received_at', from)
            .lte('received_at', to);
        return data
            .map((json) =>
                CapturedMessage.fromJson(json as Map<String, dynamic>))
            .toList();
      }, 'Error fetching nearby captures');

  /// Transactions already recorded on [day] with an amount close to [amount].
  /// Used to spot a collision with a manually entered expense.
  ///
  /// Rows that came from this pipeline are excluded — they are handled by the
  /// capture-level dedup, and counting them here would flag every auto-posted
  /// expense as a collision with itself.
  Future<List<DedupCandidate>> transactionsNear({
    required DateTime day,
    required double amount,
    required String currency,
  }) =>
      _withRetry(() async {
        final dayStr = DateTime(day.year, day.month, day.day)
            .toIso8601String()
            .split('T')[0];
        final List<dynamic> data = await _client
            .from('transactions')
            .select(
                'id, amount, currency, description, place, date, occurred_at, captured_message_id')
            .eq('user_id', _userId)
            .eq('date', dayStr)
            .gte('amount', amount - 1)
            .lte('amount', amount + 1);

        return data
            .map((row) => row as Map<String, dynamic>)
            .where((row) => row['captured_message_id'] == null)
            .where((row) => (row['currency'] as String? ?? 'COP') == currency)
            .map((row) {
          final occurredAt = row['occurred_at'] != null
              ? DateTime.parse(row['occurred_at'] as String).toLocal()
              : DateTime.parse(row['date'] as String);
          // `place` is the merchant when the row came from a capture or the
          // user filled it in; `description` is the next best guess.
          final label = (row['place'] as String?)?.trim().isNotEmpty == true
              ? row['place'] as String
              : (row['description'] as String? ?? '');
          return DedupCandidate(
            id: row['id'] as String,
            amount: (row['amount'] as num).toDouble(),
            currency: row['currency'] as String? ?? 'COP',
            merchantKey:
                label.isEmpty ? null : normalizeMerchant(label),
            occurredAt: occurredAt,
            dayPrecisionOnly: row['occurred_at'] == null,
          );
        }).toList();
      }, 'Error fetching nearby transactions');
}
