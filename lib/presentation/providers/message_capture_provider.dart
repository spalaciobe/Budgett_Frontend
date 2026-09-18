import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budgett_frontend/core/services/capture_ingest_service.dart';
import 'package:budgett_frontend/core/services/message_capture_service.dart';
import 'package:budgett_frontend/data/models/capture_source_model.dart';
import 'package:budgett_frontend/data/models/captured_message_model.dart';
import 'package:budgett_frontend/data/models/merchant_alias_model.dart';
import 'package:budgett_frontend/data/repositories/bank_repository.dart';
import 'package:budgett_frontend/data/repositories/message_capture_repository.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/providers/settings_provider.dart';

/// Single [MessageCaptureRepository] for the whole app, mirroring
/// `financeRepositoryProvider`.
final messageCaptureRepositoryProvider =
    Provider<MessageCaptureRepository>((ref) {
  return MessageCaptureRepository(Supabase.instance.client);
});

final messageCaptureServiceProvider = Provider<MessageCaptureService>((ref) {
  return MessageCaptureService();
});

/// Platform permission + configuration state. Refreshed explicitly after the
/// user returns from system settings, since Android gives no callback for
/// notification access being granted.
final captureStatusProvider = FutureProvider<CaptureStatus>((ref) async {
  return ref.watch(messageCaptureServiceProvider).getStatus();
});

final captureSourcesProvider =
    FutureProvider<List<CaptureSource>>((ref) async {
  final repository = ref.watch(messageCaptureRepositoryProvider);
  return repository.getSources();
});

final merchantAliasesProvider =
    FutureProvider<List<MerchantAlias>>((ref) async {
  final repository = ref.watch(messageCaptureRepositoryProvider);
  return repository.getAliases();
});

/// Messages waiting for the user's decision.
final pendingCapturesProvider =
    FutureProvider<List<CapturedMessage>>((ref) async {
  final repository = ref.watch(messageCaptureRepositoryProvider);
  return repository.getCaptures(statuses: const ['pending']);
});

/// Recently processed messages — posted, deduplicated or dismissed — shown in
/// the inbox's history tab so an auto-posted expense is always traceable.
final captureHistoryProvider =
    FutureProvider<List<CapturedMessage>>((ref) async {
  final repository = ref.watch(messageCaptureRepositoryProvider);
  return repository.getCaptures(
    statuses: const ['posted', 'duplicate', 'dismissed'],
    limit: 60,
  );
});

/// Badge count for the navigation entry.
final pendingCaptureCountProvider = FutureProvider<int>((ref) async {
  final pending = await ref.watch(pendingCapturesProvider.future);
  return pending.length;
});

final captureIngestServiceProvider = Provider<CaptureIngestService>((ref) {
  return CaptureIngestService(
    captureRepo: ref.watch(messageCaptureRepositoryProvider),
    financeRepo: ref.watch(financeRepositoryProvider),
    platform: ref.watch(messageCaptureServiceProvider),
  );
});

/// Runs ingestion and refreshes everything the new rows touch.
///
/// Exposed as a notifier rather than a plain function so the UI can show a
/// spinner and so overlapping runs are impossible — draining the native queue
/// twice concurrently would process the same messages in both passes.
class CaptureIngestController extends AsyncNotifier<CaptureIngestResult?> {
  /// Synchronous on purpose. With `async` the notifier stays uninitialised
  /// until its future resolves, and the `state = AsyncLoading()` in [run]
  /// throws "Tried to update the state of an uninitialized provider". That
  /// assignment sits before the try block, so the error vanished into an
  /// unobserved future and ingestion silently never ran: a captured purchase
  /// stayed in the native queue with nothing in the app to show for it.
  @override
  FutureOr<CaptureIngestResult?> build() => null;

  bool _running = false;

  /// Drains and processes the queue. Returns null when a run was already in
  /// flight or the platform cannot capture.
  Future<CaptureIngestResult?> run() async {
    if (_running) return null;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;

    final service = ref.read(messageCaptureServiceProvider);
    if (!service.isSupported) return null;

    _running = true;
    try {
      state =
          const AsyncLoading<CaptureIngestResult?>().copyWithPrevious(state);
      final accounts = await ref.read(accountsProvider.future);
      final banks = await ref.read(banksFutureProvider.future);
      final settings = await ref.read(captureSettingsProvider.future);

      // Bounded: ingestion reverse-geocodes over the network, and an await
      // that never returns would leave this notifier in AsyncLoading for the
      // rest of the session — which is what kept the inbox's sync icon
      // spinning. Failing here is recoverable; a stuck state is not.
      final result = await ref
          .read(captureIngestServiceProvider)
          .ingest(
            accounts: accounts,
            banks: banks,
            settings: settings,
          )
          .timeout(const Duration(seconds: 90));

      if (result.inserted > 0) {
        ref.invalidate(pendingCapturesProvider);
        ref.invalidate(captureHistoryProvider);
        ref.invalidate(captureSourcesProvider);
        // Auto-posted rows changed balances and the transaction list.
        if (result.posted > 0) {
          ref.invalidate(recentTransactionsProvider);
          ref.invalidate(accountsProvider);
        }
      }
      ref.invalidate(captureStatusProvider);

      state = AsyncData(result);
      return result;
    } catch (e, stack) {
      debugPrint('Capture ingestion failed: $e');
      state = AsyncError(e, stack);
      return null;
    } finally {
      _running = false;
    }
  }
}

final captureIngestControllerProvider =
    AsyncNotifierProvider<CaptureIngestController, CaptureIngestResult?>(
        CaptureIngestController.new);
