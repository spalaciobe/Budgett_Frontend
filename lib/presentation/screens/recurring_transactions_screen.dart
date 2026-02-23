import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:intl/intl.dart';

class RecurringTransactionsScreen extends ConsumerWidget {
  const RecurringTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recurringAsync = ref.watch(recurringTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring Transactions')),
      body: recurringAsync.when(
        data: (transactions) {
          if (transactions.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.repeat, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No recurring transactions yet.'),
                  Text('Add one when creating a new transaction.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: transactions.length,
            padding: const EdgeInsets.all(16),
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = transactions[index];
              return Card(
                elevation: 2,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: item.type == 'income' 
                        ? Colors.green.withOpacity(0.1) 
                        : Colors.red.withOpacity(0.1),
                    child: Icon(
                      item.type == 'income' ? Icons.arrow_downward : Icons.arrow_upward,
                      color: item.type == 'income' ? Colors.green : Colors.red,
                    ),
                  ),
                  title: Text(item.description, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_capitalize(item.frequency)} • Next: ${DateFormat.yMMMd().format(item.nextRunDate)}'),
                      if (item.lastRunDate != null)
                        Text('Last run: ${DateFormat.yMMMd().format(item.lastRunDate!)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        CurrencyFormatter.format(item.amount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: item.type == 'income' ? Colors.green : Colors.red,
                        ),
                      ),
                      PopupMenuButton(
                        itemBuilder: (context) => [
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
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red, size: 18),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Stop Recurrence?'),
                                content: const Text('This will delete the recurring rule. Past transactions will remain.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  String _capitalize(String s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
}
