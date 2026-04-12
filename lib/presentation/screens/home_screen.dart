import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:budgett_frontend/presentation/widgets/add_transaction_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/add_account_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/edit_transaction_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/edit_account_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/app_drawer.dart';

import 'package:budgett_frontend/presentation/screens/recurring_transactions_screen.dart';
import 'package:budgett_frontend/presentation/screens/expense_groups_screen.dart';
import 'package:budgett_frontend/presentation/screens/settings_screen.dart';
import 'package:budgett_frontend/presentation/screens/analysis_screen.dart';
import 'package:budgett_frontend/presentation/screens/credit_card_details_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final transactionsAsync = ref.watch(recentTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgett'),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      // Drawer is handled by MainScaffold
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            // ACCOUNTS SECTION
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Your Accounts', style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const AddAccountDialog(),
                    );
                  }, 
                  icon: Icon(Icons.add_circle, color: Theme.of(context).colorScheme.primary)
                ),
              ],
            ),
            const SizedBox(height: 8),
            accountsAsync.when(
              data: (accounts) {
                if (accounts.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No accounts yet. Add one!'),
                    ),
                  );
                }
                return SizedBox(
                  height: 150, 
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: accounts.length,
                    separatorBuilder: (c, i) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final acc = accounts[index];
                      return Card(
                        elevation: 4,
                        shadowColor: Colors.black12,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        child: InkWell(
                          onTap: () {
                            if (acc.type == 'credit_card') {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => CreditCardDetailsScreen(account: acc),
                                ),
                              );
                            } else {
                              showDialog(
                                context: context,
                                builder: (context) => EditAccountDialog(account: acc),
                              );
                            }
                          },
                          child: Container(
                            width: 170,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Theme.of(context).colorScheme.surface,
                                  Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(_getIconForType(acc.type), color: Theme.of(context).colorScheme.primary),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      acc.name, 
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600, 
                                        color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                                        fontSize: 13
                                      ), 
                                      overflow: TextOverflow.ellipsis
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      CurrencyFormatter.format(acc.balance, decimalDigits: 2),
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      )
                                    ),
                                    if (acc.type == 'credit_card' && acc.balanceUsd != 0) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        CurrencyFormatter.format(acc.balanceUsd, currency: 'USD'),
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Text('Error: $err'),
            ),

            const SizedBox(height: 32),

            // RECENT TRANSACTIONS SECTION
             Text('Recent Transactions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
             const SizedBox(height: 12),
             transactionsAsync.when(
               data: (transactions) {
                 if (transactions.isEmpty) return const Text('No recent transactions.');
                 return Card(
                   elevation: 2,
                   shadowColor: Colors.black12,
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                   child: ListView.separated(
                     padding: EdgeInsets.zero,
                     shrinkWrap: true,
                     physics: const NeverScrollableScrollPhysics(),
                     itemCount: transactions.length,
                     separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                     itemBuilder: (context, index) {
                       final t = transactions[index];
                       return ListTile(
                         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                         onTap: () {
                           showDialog(
                             context: context,
                             builder: (context) => EditTransactionDialog(transaction: t),
                           );
                         },
                         leading: CircleAvatar(
                           backgroundColor: (t.type == 'expense' 
                               ? Theme.of(context).colorScheme.error 
                               : Theme.of(context).colorScheme.secondary).withOpacity(0.1),
                           child: Icon(
                             t.type == 'expense' ? Icons.arrow_downward : Icons.arrow_upward,
                             color: t.type == 'expense' ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.secondary,
                             size: 20,
                           ),
                         ),
                         title: Text(
                           t.description,
                           style: TextStyle(
                             fontWeight: FontWeight.w600,
                             decoration: t.status == 'pending' ? TextDecoration.lineThrough : null, // Optional: strikethrough or grey
                             color: t.status == 'pending' ? Colors.grey : null,
                           ),
                         ),
                         subtitle: Row(
                           children: [
                             if (t.status == 'pending') ...[
                               const Icon(Icons.pending_actions, size: 14, color: Colors.orange),
                               const SizedBox(width: 4),
                               const Text('Pending  •  ', style: TextStyle(fontSize: 12, color: Colors.orange)),
                             ],
                             Text(t.date.toLocal().toString().split(' ')[0], style: const TextStyle(fontSize: 12)),
                           ],
                         ),
                         trailing: Text(
                           CurrencyFormatter.format(t.amount, decimalDigits: 2),
                           style: TextStyle(
                             color: t.status == 'pending' 
                                 ? Colors.grey 
                                 : (t.type == 'expense' ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.secondary),
                             fontWeight: FontWeight.bold,
                             fontSize: 15
                           ),
                         ),
                       );
                     },
                   ),
                 );
               },
               loading: () => const LinearProgressIndicator(),
               error: (err, stack) => Text('Error: $err'),
             ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddTransactionDialog(),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'credit_card': return Icons.credit_card;
      case 'cash': return Icons.money;
      case 'investment': return Icons.trending_up;
      case 'savings': return Icons.savings;
      default: return Icons.account_balance;
    }
  }
}
