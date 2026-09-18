import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/utils/error_messages.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:budgett_frontend/presentation/widgets/edit_recurring_transaction_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/empty_state.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../core/app_text.dart';
import '../widgets/page_body.dart';
import '../widgets/skeleton.dart';
import '../widgets/screen_title.dart';
import '../../core/utils/date_format.dart';

class RecurringTransactionsScreen extends ConsumerWidget {
  /// When true this screen is a tab inside Plan, which supplies the
  /// AppBar — so it must not draw one of its own.
  final bool embedded;

  const RecurringTransactionsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recurringAsync = ref.watch(recurringTransactionsProvider);

    return Scaffold(
      appBar: embedded ? null : AppBar(title: ScreenTitle('Recurring Transactions')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(recurringTransactionsProvider);
          await ref.read(recurringTransactionsProvider.future);
        },
        child: recurringAsync.when(
          data: (transactions) {
            if (transactions.isEmpty) {
              return const EmptyState(
                icon: Icons.repeat,
                title: 'No recurring transactions yet',
                message: 'Add one when creating a new transaction.',
              );
            }
            return PageBody(
              maxWidth: kColumnMaxWidth,
              child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: transactions.length,
              padding: kScreenPadding,
              separatorBuilder: (context, index) => kGapMd,
            itemBuilder: (context, index) {
              final item = transactions[index];
              return Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => EditRecurringTransactionDialog(transaction: item),
                  ),
                  // Two lines, not four. The old row wrapped the name onto a
                  // second line, then spent two more on "Next: 18/10/2026" and
                  // "Last: 18/09/2026" — a full date twice, mostly digits the
                  // eye has to parse. The next run is what matters and it is
                  // never far away, so it reads as "Monthly · 18 Oct"; the
                  // last run lives in the edit dialog.
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: item.type == 'income'
                        ? context.positive.withValues(alpha: 0.12)
                        : context.negative.withValues(alpha: 0.12),
                    child: Icon(
                      item.type == 'income' ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 16,
                      color: item.type == 'income' ? context.positive : context.negative,
                    ),
                  ),
                  title: Text(
                    item.description,
                    style: AppText.tileTitle,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                  subtitle: Text(
                    '${_capitalize(item.frequency)} · ${formatDayMonth(item.nextRunDate)}',
                    style: AppText.caption.copyWith(color: context.muted),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        CurrencyFormatter.format(item.amount),
                        style: AppText.amount.copyWith(
                          color: item.type == 'income'
                              ? context.positive
                              : context.negative,
                        ),
                      ),
                      PopupMenuButton(
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'generate',
                            child: Row(
                              children: [
                                Icon(Icons.play_arrow, size: 18),
                                SizedBox(width: 8),
                                Text('Generate Now'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: context.negative, size: 18),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: context.negative)),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await showDialog(
                              context: context,
                              builder: (_) => EditRecurringTransactionDialog(transaction: item),
                            );
                          } else if (value == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Stop Recurrence?'),
                                content: const Text('This will delete the recurring rule. Past transactions will remain.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: context.negative),
                                    onPressed: () => Navigator.pop(context, true), 
                                    child: const Text('Delete')
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ref.read(financeRepositoryProvider).deleteRecurringTransaction(item.id);
                              ref.invalidate(recurringTransactionsProvider);
                            }
                          } else if (value == 'generate') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Generate Transaction?'),
                                content: Text('This will create a transaction for "${item.description}" today and advance the next run date.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Generate')),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ref.read(financeRepositoryProvider).generateTransactionFromRecurring(item);
                              ref.invalidate(recurringTransactionsProvider);
                              ref.invalidate(recentTransactionsProvider); // Update home
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction generated!')));
                              }
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          );
        },
          loading: () => const SkeletonCards(),
          error: (e, s) => Center(child: Text(friendlyError(e))),
        ),
      ),
    );
  }

  String _capitalize(String s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
}
