import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/models/account_model.dart';
import '../../data/models/bank_model.dart';
import '../../data/repositories/bank_repository.dart';
import '../../core/utils/credit_card_calculator.dart';

class CreditCardBillingSubtitle extends ConsumerWidget {
  final Account account;
  final DateTime transactionDate;

  const CreditCardBillingSubtitle({
    super.key,
    required this.account,
    required this.transactionDate,
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

        final billingPeriod = CreditCardCalculator.determineBillingPeriod(
          transactionDate,
          account.creditCardRules!,
          bank,
        );
        final parts = billingPeriod.split('-');
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final label = DateFormat('MMMM yyyy', 'es_CO')
            .format(DateTime(year, month));

        return Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: Text(
            'Billing Cycle: $label',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        );
      },
      loading: () => const SizedBox(),
      error: (_, __) => const SizedBox(),
    );
  }
}

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

    // Start of this cycle = day after previous month's cutoff
    int prevMonth = month - 1;
    int prevYear = year;
    if (prevMonth < 1) {
      prevMonth = 12;
      prevYear = year - 1;
    }
    final prevCutoff = CreditCardCalculator.calculateCutoffDate(
      account.creditCardRules!,
      bank,
      prevYear,
      prevMonth,
    );
    final cycleStart = prevCutoff.add(const Duration(days: 1));

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _buildTimeline(context, cycleStart, transactionDate, cutoffDate, paymentDate),
            ),
            
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
                     Expanded(
                       child: Text(
                         'Payment due in $daysToPayment days',
                         style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                         overflow: TextOverflow.ellipsis,
                       ),
                     ),
                   ],
                 ),
               )
            ]
          ],
        ),
      ),
    );
  }
  
  Widget _buildTimeline(BuildContext context, DateTime cycleStart, DateTime today, DateTime cutoff, DateTime payment) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final width = constraints.maxWidth;
        final totalMs = payment.difference(cycleStart).inMilliseconds;

        double cutoffRatio = 0.5;
        if (totalMs > 0) {
          cutoffRatio =
              (cutoff.difference(cycleStart).inMilliseconds / totalMs).clamp(0.0, 1.0);
        }

        // Force "today" to be shown between cycle start and cutoff.
        double todayRatio;
        if (today.isBefore(cycleStart)) {
          todayRatio = 0.0;
        } else if (today.isAfter(cutoff)) {
          todayRatio = cutoffRatio;
        } else if (totalMs > 0) {
          todayRatio =
              (today.difference(cycleStart).inMilliseconds / totalMs).clamp(0.0, cutoffRatio);
        } else {
          todayRatio = 0.0;
        }

        final primary = Theme.of(context).colorScheme.primary;

        // Detect label collision with Start or Cutoff and stagger "Today" above the line.
        const collisionPx = 50.0;
        final todayPx = todayRatio * width;
        final cutoffPx = cutoffRatio * width;
        final todayAbove = todayPx < collisionPx || (cutoffPx - todayPx).abs() < collisionPx;

        const lineTop = 46.0;

        return SizedBox(
          height: 92,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: lineTop,
                child: Container(height: 2, color: Colors.grey.withOpacity(0.3)),
              ),
              _buildTimelineNode(context, width, 0.0, 'Start', cycleStart, color: primary, lineTop: lineTop),
              _buildTimelineNode(context, width, todayRatio, 'Today', today, color: primary, isPrimary: true, above: todayAbove, lineTop: lineTop),
              _buildTimelineNode(context, width, cutoffRatio, 'Cutoff', cutoff, color: Colors.orange, lineTop: lineTop),
              _buildTimelineNode(context, width, 1.0, 'Pay', payment, color: Colors.green, lineTop: lineTop),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimelineNode(
    BuildContext context,
    double width,
    double ratio,
    String label,
    DateTime date, {
    required Color color,
    required double lineTop,
    bool isPrimary = false,
    bool above = false,
  }) {
    const nodeWidth = 80.0;
    const dotSize = 12.0;
    final left = (ratio * width) - (nodeWidth / 2);

    final dot = Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: isPrimary ? Border.all(color: Colors.white, width: 2) : null,
        boxShadow: [
          if (isPrimary)
            BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, spreadRadius: 2),
        ],
      ),
    );
    final dateText = Text(
      DateFormat('d MMM', 'es_CO').format(date),
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
    );
    final labelText = Text(
      label,
      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );

    if (above) {
      return Positioned(
        left: left,
        top: 0,
        width: nodeWidth,
        height: lineTop + dotSize / 2 + 1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            labelText,
            dateText,
            const SizedBox(height: 4),
            dot,
          ],
        ),
      );
    }

    return Positioned(
      left: left,
      top: lineTop - dotSize / 2 + 1,
      width: nodeWidth,
      child: Column(
        children: [
          dot,
          const SizedBox(height: 4),
          dateText,
          labelText,
        ],
      ),
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
