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

class RecurringTransactionsScreen extends ConsumerWidget {
  const RecurringTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recurringAsync = ref.watch(recurringTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring Transactions')),
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
              separatorBuilder: (context, index) => kGapLg,
            itemBuilder: (context, index) {
              final item = transactions[index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => EditRecurringTransactionDialog(transaction: item),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: item.type == 'income' 
                        ? context.positive.withValues(alpha: 0.1) 
                        : context.negative.withValues(alpha: 0.1),
                    child: Icon(
                      item.type == 'income' ? Icons.arrow_downward : Icons.arrow_upward,
                      color: item.type == 'income' ? context.positive : context.negative,
                    ),
                  ),
                  title: Text(item.description, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_capitalize(item.frequency)} • Next: ${DateFormat('dd/MM/yyyy').format(item.nextRunDate)}'),
                      if (item.lastRunDate != null)
                        Text('Last: ${DateFormat('dd/MM/yyyy').format(item.lastRunDate!)}', style: AppText.badge.copyWith(color: context.muted)),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        CurrencyFormatter.format(item.amount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: item.type == 'income' ? context.positive : context.negative,
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
