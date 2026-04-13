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
import 'package:budgett_frontend/presentation/widgets/account_card.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/investment_details_model.dart';
import 'package:budgett_frontend/core/utils/investment_calculator.dart';

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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountsProvider);
          ref.invalidate(recentTransactionsProvider);
          await Future.wait([
            ref.read(accountsProvider.future),
            ref.read(recentTransactionsProvider.future),
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                      return AccountCard(
                        account: acc,
                        subtitle: _buildInvestmentSubtitle(context, acc),
                        onTap: () {
                          if (acc.type == 'credit_card') {
                            context.go('/credit-card/${acc.id}');
                          } else if (acc.type == 'investment') {
                            context.go('/investment/${acc.id}');
                          } else {
                            showDialog(
                              context: context,
                              builder: (context) => EditAccountDialog(account: acc),
                            );
                          }
                        },
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

  /// Returns a small informational widget shown beneath the balance on the
  /// account card, specific to investment account types. Returns null for
  /// non-investment accounts (the card handles credit-card USD balance itself).
  Widget? _buildInvestmentSubtitle(BuildContext context, Account acc) {
    if (acc.type != 'investment') return null;
    final details = acc.investmentDetails;
    if (details == null) return null;

    final dimColor =
        Theme.of(context).colorScheme.onSurface.withOpacity(0.55);
    const subtitleStyle = TextStyle(fontSize: 11);

    switch (details.investmentType) {
      case InvestmentType.highYield:
        final apy = details.apyRate;
        if (apy == null) return null;
        return Text(
          '${(apy * 100).toStringAsFixed(2)}% APY',
          style: subtitleStyle.copyWith(color: Colors.green.shade600),
        );

      case InvestmentType.cdt:
        if (InvestmentCalculator.isCdtMatured(details)) {
          return Text(
            'Matured — collect',
            style: subtitleStyle.copyWith(color: Colors.orange.shade700),
          );
        }
        final days = InvestmentCalculator.cdtDaysToMaturity(details);
        return Text(
          'Expires in $days days',
          style: subtitleStyle.copyWith(color: dimColor),
        );

      case InvestmentType.fic:
      case InvestmentType.crypto:
      case InvestmentType.stockEtf:
        return Text(
          details.investmentType.displayName,
          style: subtitleStyle.copyWith(color: dimColor),
        );
    }
  }
}
