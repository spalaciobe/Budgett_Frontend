import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/core/app_text.dart';
import 'package:budgett_frontend/core/parsing/issuer_registry.dart';
import 'package:budgett_frontend/core/services/message_capture_service.dart';
import 'package:budgett_frontend/core/utils/error_messages.dart';
import 'package:budgett_frontend/data/models/captured_message_model.dart';
import 'package:budgett_frontend/presentation/providers/message_capture_provider.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:budgett_frontend/presentation/widgets/empty_state.dart';
import 'package:budgett_frontend/presentation/widgets/review_capture_sheet.dart';

/// The review queue for captured bank messages.
///
/// "To review" holds everything the pipeline would not record on its own —
/// a merchant it has not been taught yet, an account it could not resolve, a
/// possible duplicate. "History" is the audit trail: every message that was
/// recorded, deduplicated or dismissed, so an auto-posted expense can always
/// be traced back to the text that produced it.
class CaptureInboxScreen extends ConsumerWidget {
  const CaptureInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(captureStatusProvider);
    final ingestState = ref.watch(captureIngestControllerProvider);
    final isSyncing = ingestState.isLoading;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Expense Inbox'),
          actions: [
            IconButton(
              tooltip: 'Check for new messages',
              onPressed: isSyncing ? null : () => _sync(context, ref),
              icon: isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
            IconButton(
              tooltip: 'Capture settings',
              onPressed: () => context.push('/capture-settings'),
              icon: const Icon(Icons.tune),
            ),
          ],
          bottom: const TabBar(
            // Scrollable so two tabs stay compact and left-aligned on a
            // desktop-width window instead of stretching to the edges.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'To review'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: Column(
          children: [
            statusAsync.when(
              data: (status) => _StatusBanner(status: status),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _CaptureList(
                    provider: pendingCapturesProvider,
                    emptyTitle: 'Nothing to review',
                    emptyBody:
                        'Captured messages that need a decision show up here.',
                    onRefresh: () => _sync(context, ref),
                  ),
                  _CaptureList(
                    provider: captureHistoryProvider,
                    emptyTitle: 'No history yet',
                    emptyBody:
                        'Recorded, duplicate and dismissed messages are kept here.',
                    onRefresh: () => _sync(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    final result =
        await ref.read(captureIngestControllerProvider.notifier).run();
    ref.invalidate(pendingCapturesProvider);
    ref.invalidate(captureHistoryProvider);
    if (!context.mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.summary)),
      );
    }
  }
}

/// Explains what is missing when capture cannot actually run, rather than
/// showing an empty list that looks like "no expenses".
class _StatusBanner extends StatelessWidget {
  final CaptureStatus status;

  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!status.isSupported) {
      return _banner(
        theme,
        Icons.phone_android,
        'Message capture runs on Android only. '
            'Expenses recorded on your phone still sync here.',
        isError: false,
      );
    }
    if (!status.enabled) {
      return _banner(
        theme,
        Icons.pause_circle_outline,
        'Capture is off. Turn it on in capture settings.',
        isError: true,
      );
    }
    final missing = status.missingGrants;
    if (missing.isNotEmpty) {
      return _banner(
        theme,
        Icons.lock_outline,
        'Still needed: ${missing.join(', ')}.',
        isError: true,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _banner(ThemeData theme, IconData icon, String text,
      {required bool isError}) {
    final background = isError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = isError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: kSpaceXl),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: kSpaceXl),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureList extends ConsumerWidget {
  final ProviderListenable<AsyncValue<List<CapturedMessage>>> provider;
  final String emptyTitle;
  final String emptyBody;
  final Future<void> Function() onRefresh;

  const _CaptureList({
    required this.provider,
    required this.emptyTitle,
    required this.emptyBody,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: kScreenPadding,
          child: Text(
            friendlyError(error, action: 'load captured messages'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (messages) {
        if (messages.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: EmptyState(
              icon: Icons.move_to_inbox_outlined,
              title: emptyTitle,
              message: emptyBody,
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: Center(
            child: ConstrainedBox(
              // Keeps the cards readable on a desktop-width window.
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: kScreenPadding,
                itemCount: messages.length,
                itemBuilder: (context, index) =>
                    CaptureCard(message: messages[index]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One captured message: what it says, where it came from, and what happened
/// to it.
class CaptureCard extends ConsumerWidget {
  final CapturedMessage message;

  const CaptureCard({super.key, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sources = ref.watch(captureSourcesProvider).valueOrNull ?? const [];
    final source =
        sources.where((s) => s.id == message.sourceId).firstOrNull;
    final sourceName = source?.effectiveName ?? message.sourceKey;

    final amountLabel = message.amount == null
        ? '—'
        : CurrencyFormatter.format(
            message.amount!,
            currency: message.currency ?? 'COP',
            decimalDigits: 0,
          );

    final subtitleParts = <String>[
      sourceName,
      if (message.issuerKey != null &&
          issuerDisplayName(message.issuerKey) != sourceName)
        issuerDisplayName(message.issuerKey!),
      if (message.cardLast4 != null) '•${message.cardLast4}',
      DateFormat('dd/MM HH:mm', 'en').format(message.occurredAt),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: kSpaceXl),
      child: Padding(
        padding: kCardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  message.channel == 'sms'
                      ? Icons.sms_outlined
                      : Icons.notifications_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: kSpaceXl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.headline,
                        style: AppText.tileTitle,
                        maxLines: 2,
                        overflow: TextOverflow.fade,
                      ),
                      kGapSm,
                      Text(
                        subtitleParts.join(' · '),
                        style: AppText.caption
                            .copyWith(color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.fade,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: kSpaceLg),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(amountLabel, style: AppText.amount),
                    if (message.kind != null) ...[
                      kGapXs,
                      Text(
                        message.kind!.label,
                        style: AppText.badge
                            .copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (message.locationLabel != null) ...[
              kGapLg,
              Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: kSpaceMd),
                  Expanded(
                    child: Text(
                      message.locationLabel!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ],
              ),
            ],
            if (message.parseStatus == 'unparsed') ...[
              kGapLg,
              Text(
                message.body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.fade,
              ),
            ],
            if (message.error != null) ...[
              kGapLg,
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: theme.colorScheme.error),
                  const SizedBox(width: kSpaceMd),
                  Expanded(
                    child: Text(
                      message.error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
            kGapLg,
            _buildActions(context, ref, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, WidgetRef ref, ThemeData theme) {
    if (message.isPending) {
      // Wrap, not Row: at the narrowest phone width the two buttons would
      // otherwise overflow the card.
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: kSpaceLg,
        runSpacing: kSpaceSm,
        children: [
          TextButton(
            onPressed: () => _setStatus(context, ref, 'dismissed'),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => ReviewCaptureSheet(message: message),
            ),
            child: const Text('Review'),
          ),
        ],
      );
    }

    return Wrap(
      spacing: kSpaceXl,
      runSpacing: kSpaceSm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _statusChip(theme),
        // A wrong duplicate call must be recoverable: sending it back to the
        // review queue is the undo.
        if (message.isDuplicate || message.status == 'dismissed')
          TextButton(
            onPressed: () => _setStatus(context, ref, 'pending'),
            child: const Text('Move to review'),
          ),
      ],
    );
  }

  Widget _statusChip(ThemeData theme) {
    final (label, color) = switch (message.status) {
      'posted' => ('Recorded', theme.colorScheme.primary),
      'duplicate' => ('Duplicate', theme.colorScheme.tertiary),
      'dismissed' => ('Dismissed', theme.colorScheme.outline),
      'failed' => ('Failed', theme.colorScheme.error),
      _ => (message.status, theme.colorScheme.outline),
    };

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: kSpaceXl, vertical: kSpaceSm),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: AppText.badge.copyWith(color: color)),
    );
  }

  Future<void> _setStatus(
      BuildContext context, WidgetRef ref, String status) async {
    try {
      await ref
          .read(messageCaptureRepositoryProvider)
          .updateCapture(message.id, {'status': status});
      ref.invalidate(pendingCapturesProvider);
      ref.invalidate(captureHistoryProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'update captured message')),
        ),
      );
    }
  }
}
