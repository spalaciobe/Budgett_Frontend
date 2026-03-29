import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/models/account_model.dart';
import '../../data/models/bank_model.dart';
import '../../data/repositories/bank_repository.dart';
import '../../core/utils/credit_card_calculator.dart';

class CreditCardBillingSimulator extends ConsumerWidget {
  final Account account;
  final DateTime transactionDate;
  final double? amount;

  const CreditCardBillingSimulator({
    super.key,
    required this.account,
    required this.transactionDate,
    this.amount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (account.type != 'credit_card' || account.creditCardRules == null) {
      return const SizedBox();
    }

    final banksAsync = ref.watch(banksFutureProvider);

    return banksAsync.when(
      data: (banks) {
        final bank = banks.firstWhere(
          (b) => b.id == account.creditCardRules!.bankId,
          orElse: () => Bank(id: '0', name: 'Unknown', code: 'UNK'),
        );

        return _buildSimulation(context, bank);
      },
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(8.0),
        child: CircularProgressIndicator(strokeWidth: 2),
      )),
      error: (_, __) => const SizedBox(),
    );
  }

  Widget _buildSimulation(BuildContext context, Bank bank) {
    // 1. Calculate Periods
    final billingPeriod = CreditCardCalculator.determineBillingPeriod(
      transactionDate,
      account.creditCardRules!,
      bank,
    );
    
    final parts = billingPeriod.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    // 2. Calculate Actual Dates
    final cutoffDate = CreditCardCalculator.calculateCutoffDate(
      account.creditCardRules!,
      bank,
      year,
      month,
    );
    
    final paymentDate = CreditCardCalculator.calculatePaymentDate(
      account.creditCardRules!,
      bank,
      cutoffDate,
    );

    // 3. Determine status
    final isAfterCutoff = transactionDate.isAfter(cutoffDate);
    final daysToPayment = paymentDate.difference(DateTime.now()).inDays;

    final dateFormat = DateFormat('dd/MM/yyyy', 'es_CO');

    return Card(
      elevation: 2,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Billing Cycle: $billingPeriod',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // Timeline Visualization
            _buildTimeline(context, transactionDate, cutoffDate, paymentDate),
            
            const SizedBox(height: 16),
            
            // Detailed Dates
            _buildDateRow(context, 'Purchase Date', transactionDate, dateFormat, 
              isHighlighted: true),
            const SizedBox(height: 8),
            _buildDateRow(context, 'Cutoff Date', cutoffDate, dateFormat,
              icon: Icons.content_cut, color: Colors.orange),
            const SizedBox(height: 8),
            _buildDateRow(context, 'Payment Due', paymentDate, dateFormat,
              icon: Icons.event_available, color: Colors.green),
              
            if (daysToPayment > 0 && daysToPayment < 15) ...[
               const SizedBox(height: 12),
               Container(
                 padding: const EdgeInsets.all(8),
                 decoration: BoxDecoration(
                   color: Colors.orange.withOpacity(0.1),
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: Colors.orange.withOpacity(0.3))
                 ),
                 child: Row(
                   children: [
                     const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                     const SizedBox(width: 8),
                     Text('Payment due in $daysToPayment days', 
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12))
                   ],
                 ),
               )
            ]
          ],
        ),
      ),
    );
  }
  
  Widget _buildTimeline(BuildContext context, DateTime purchase, DateTime cutoff, DateTime payment) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
         _buildTimelineNode(context, 'Buy', purchase, true),
         Expanded(child: Container(height: 2, color: Colors.grey.withOpacity(0.3))),
         _buildTimelineNode(context, 'Cutoff', cutoff, false, color: Colors.orange),
         Expanded(child: Container(height: 2, color: Colors.grey.withOpacity(0.3))),
         _buildTimelineNode(context, 'Pay', payment, false, color: Colors.green),
      ],
    );
  }
  
  Widget _buildTimelineNode(BuildContext context, String label, DateTime date, bool isPrimary, {Color? color}) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c,
            border: isPrimary ? Border.all(color: Colors.white, width: 2) : null,
            boxShadow: [
              if(isPrimary) BoxShadow(color: c.withOpacity(0.4), blurRadius: 4, spreadRadius: 2)
            ]
          ),
        ),
        const SizedBox(height: 4),
        Text(DateFormat('d MMM', 'es_CO').format(date), 
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c)),
        Text(label, 
          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildDateRow(BuildContext context, String label, DateTime date, DateFormat fmt, {bool isHighlighted = false, IconData? icon, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
             if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 8)],
             Text(label, style: TextStyle(
               color: isHighlighted ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
               fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
             )),
          ],
        ),
        Text(fmt.format(date), style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
