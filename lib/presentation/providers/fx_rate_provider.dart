import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/fx_rate_service.dart';
import '../../data/models/fx_rate_model.dart';

final fxRateServiceProvider = Provider<FxRateService>((ref) {
  return FxRateService(Supabase.instance.client);
});

/// Current TRM (USD→COP). Auto-refreshes once per session.
/// Marked autoDispose so it re-fetches when re-entered from cold state.
final fxRateProvider = FutureProvider.autoDispose<FxRate?>((ref) async {
  try {
    return await ref.read(fxRateServiceProvider).getCurrentTrm();
  } catch (_) {
    return null; // Callers should treat null as "unavailable"
  }
});
