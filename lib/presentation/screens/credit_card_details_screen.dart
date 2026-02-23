import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/models/account_model.dart';
import '../../data/models/transaction_model.dart';
import '../../presentation/providers/finance_provider.dart';
import '../../presentation/utils/currency_formatter.dart';
import '../../presentation/widgets/credit_card_billing_simulator.dart';
import '../../presentation/widgets/edit_account_dialog.dart';

// Provider to fetch transactions for a specific account
final accountTransactionsProvider = FutureProvider.family.autoDispose<List<Transaction>, String>((ref, accountId) async {
  final repo = ref.read(financeRepositoryProvider);
  return repo.getTransactionsForAccount(accountId, limit: 100);
});

class CreditCardDetailsScreen extends ConsumerWidget {
  final Account account;

  const CreditCardDetailsScreen({super.key, required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch transactions for this account
    final transactionsAsync = ref.watch(accountTransactionsProvider(account.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
               showDialog(
                context: context,
                builder: (context) => EditAccountDialog(account: account),
              ).then((_) {
                 // Refresh account data if needed (usually handled by provider stream/updates)
                 ref.invalidate(accountsProvider); // Global refresh to be safe
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Current Status Simulator (Projected for TODAY)
            Text('Current Billing Status', 
                 style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            CreditCardBillingSimulator(
              account: account,
              transactionDate: DateTime.now(),
            ),
            
            const SizedBox(height: 24),
            
            // 2. Account Stats
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context, 
                    'Available', 
                    account.creditLimit > 0 ? account.creditLimit + account.balance : 0, // Balance is usually negative for debt
                    Colors.green
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    context, 
                    'Used', 
                    account.balance.abs(), 
                    Colors.red
                  ),
                ),
              ],
            ),
             const SizedBox(height: 24),
            
            // 3. Transactions / Extracts List
            Text('Recent Transactions', 
                 style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            
            transactionsAsync.when(
              data: (transactions) {
                if (transactions.isEmpty) return const Text('No transactions found.');
                
                // Group by Billing Period
                final Map<String, List<Transaction>> grouped = {};
                for (var t in transactions) {
                  final period = t.billingPeriod ?? 'Unassigned';
                  grouped.putIfAbsent(period, () => []).add(t);
                }
                
                // Sort keys descending (newest period first)
                final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

                return Column(
                  children: sortedKeys.asMap().entries.map((entry) {
                    final index = entry.key;
                    final period = entry.value;
                    final periodTransactions = grouped[period]!;
                    final total = periodTransactions.fold(0.0, (sum, t) => sum + t.amount);
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1,
                      child: ExpansionTile(
                         initiallyExpanded: index == 0, // Expand first one
                         shape: const Border(), // Remove default borders
                         title: Text(
                           _formatPeriod(period),
                           style: const TextStyle(fontWeight: FontWeight.bold),
                         ),
                         subtitle: Text(
                           'Total: ${CurrencyFormatter.format(total)}',
                           style: TextStyle(
                             color: Theme.of(context).colorScheme.primary,
                             fontWeight: FontWeight.w600
                           ),
                         ),
                         children: periodTransactions.map((t) {
                           return ListTile(
                             contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                             leading: CircleAvatar(
                                radius: 4,
                                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                             ),
                             title: Text(t.description, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                             trailing: Text(
                               CurrencyFormatter.format(t.amount),
                               style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                             ),
                             subtitle: Text(DateFormat.MMMd().format(t.date), style: const TextStyle(fontSize: 11)),
                           );
                         }).toList(),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Text('Error: $e'),
            )
          ],
        ),
      ),
    );
  }

  String _formatPeriod(String period) {
    if (period == 'Unassigned') return period;
    try {
      // Expect YYYY-MM
      final parts = period.split('-');
      if (parts.length == 2) {
        final date = DateTime(int.parse(parts[0]), int.parse(parts[1]));
        return DateFormat('MMMM yyyy').format(date);
      }
    } catch (_) {}
    return period;
  }


  Widget _buildStatCard(BuildContext context, String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), 
               style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(CurrencyFormatter.format(amount), 
               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
