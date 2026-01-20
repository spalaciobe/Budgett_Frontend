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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final transactionsAsync = ref.watch(recentTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgett Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hello, ${user?.email ?? 'User'}!',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            
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
                  height: 140, // Height for horizontal cards
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: accounts.length,
                    separatorBuilder: (c, i) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final acc = accounts[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => EditAccountDialog(account: acc),
                            );
                          },
                          child: Container(
                            width: 160,
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Icon(_getIconForType(acc.type)),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(acc.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                    Text(CurrencyFormatter.format(acc.balance, decimalDigits: 2), style: Theme.of(context).textTheme.titleMedium),
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
             Text('Recent Transactions', style: Theme.of(context).textTheme.titleLarge),
             const SizedBox(height: 8),
             transactionsAsync.when(
               data: (transactions) {
                 if (transactions.isEmpty) return const Text('No recent transactions.');
                 return Column(
                   children: transactions.map((t) => ListTile(
                     onTap: () {
                       showDialog(
                         context: context,
                         builder: (context) => EditTransactionDialog(transaction: t),
                       );
                     },
                     leading: Icon(
                       t.type == 'expense' ? Icons.arrow_downward : Icons.arrow_upward,
                       color: t.type == 'expense' ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.secondary,
                     ),
                     title: Text(t.description),
                     subtitle: Text(t.date.toLocal().toString().split(' ')[0]),
                     trailing: Text(
                       CurrencyFormatter.format(t.amount, decimalDigits: 2),
                       style: TextStyle(
                         color: t.type == 'expense' ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.secondary,
                         fontWeight: FontWeight.bold
                       ),
                     ),
                   )).toList(),
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
