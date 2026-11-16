import '../../data/models/bank_model.dart';
import '../../data/models/credit_card_rules_model.dart';
import '../../data/models/transaction_model.dart';
import 'credit_card_calculator.dart';

/// Where prepaid installment cuotas land: the billing period they move into
/// and that period's cutoff / payment dates.
class InstallmentCloseTarget {
  final String period;
  final DateTime cutoffDate;
  final DateTime paymentDate;

  const InstallmentCloseTarget({
    required this.period,
    required this.cutoffDate,
    required this.paymentDate,
  });

  /// The cycle [period] with its dates computed from the card's rules.
  factory InstallmentCloseTarget.forPeriod(
      String period, CreditCardRules rules, Bank bank) {
    final parts = period.split('-');
    final cutoff = CreditCardCalculator.calculateCutoffDate(
        rules, bank, int.parse(parts[0]), int.parse(parts[1]));
    return InstallmentCloseTarget(
      period: period,
      cutoffDate: cutoff,
      paymentDate: CreditCardCalculator.calculatePaymentDate(rules, bank, cutoff),
    );
  }
}

/// Paying installment cuotas ahead of time ("prepaying" a purchase).
///
/// Installment children are created up front, one per future billing period,
/// usually with status `paid` — so they already count in the card balance.
/// When the user pays the whole debt early, those future cuotas must leave
/// their future periods (the bank will not bill them any more) without
/// touching the balance a second time. Cuotas still `pending` do not count
/// in the balance yet, so their amount has to be added to the payment.
class InstallmentPrepay {
  InstallmentPrepay._();

  /// Cuotas on [cardId] in [currency] that a payment made on [paymentDate]
  /// can still settle: pending ones, and any cuota whose own charge date
  /// (its cycle's cutoff) is after the payment date, i.e. not billed yet.
  static List<Transaction> closable(
    Iterable<Transaction> txs, {
    required String cardId,
    required String currency,
    required DateTime paymentDate,
  }) {
    final day = DateTime(paymentDate.year, paymentDate.month, paymentDate.day);
    return txs
        .where((t) =>
            t.parentTransactionId != null &&
            !t.isInstallmentParent &&
            t.accountId == cardId &&
            t.currency == currency &&
            (t.status == 'pending' || t.date.isAfter(day)))
        .toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.description.compareTo(b.description);
      });
  }

  /// What closing [closed] adds to the card debt: only the pending cuotas,
  /// because paid ones are already part of the balance.
  static double uncountedTotal(Iterable<Transaction> closed) => closed
      .where((t) => t.status == 'pending')
      .fold<double>(0.0, (s, t) => s + t.amount);

  /// What closing [closed] adds to the [period] statement total: every cuota
  /// that is not already in that period.
  static double addedToPeriod(Iterable<Transaction> closed, String period) =>
      closed
          .where((t) => t.billingPeriod != period)
          .fold<double>(0.0, (s, t) => s + t.amount);

  /// The statement a prepayment made on [paymentDate] belongs to: the last
  /// cycle already cut. Its "total payment" is what includes the deferred
  /// balance of installment purchases.
  static String lastClosedPeriod(
      DateTime paymentDate, CreditCardRules rules, Bank bank) {
    final open =
        CreditCardCalculator.determineBillingPeriod(paymentDate, rules, bank);
    final parts = open.split('-');
    final previous = DateTime(int.parse(parts[0]), int.parse(parts[1]) - 1);
    return '${previous.year}-${previous.month.toString().padLeft(2, '0')}';
  }
}
