import 'dart:math' as math;
import '../../data/models/credit_card_rules_model.dart';
import '../../data/models/bank_model.dart';
import 'credit_card_calculator.dart';

/// Represents one installment ("cuota") in a payment schedule.
class InstallmentScheduleEntry {
  final int number;
  final String billingPeriod; // "YYYY-MM"
  final DateTime cutoffDate;
  final DateTime paymentDate;
  /// The date stored on the child transaction row. Set to [cutoffDate] so
  /// the row sorts naturally within its billing cycle.
  final DateTime chargeDate;
  final double amount;

  const InstallmentScheduleEntry({
    required this.number,
    required this.billingPeriod,
    required this.cutoffDate,
    required this.paymentDate,
    required this.chargeDate,
    required this.amount,
  });
}

class InstallmentCalculator {
  /// Computes the fixed monthly payment for an installment purchase.
  ///
  /// When [monthlyRate] == 0 (or negative), uses simple equal division.
  /// When [monthlyRate] > 0, uses French (constant-payment) amortization:
  ///   A = P × r / (1 − (1 + r)^−n)
  static double calculateMonthlyPayment(
    double principal,
    double monthlyRate,
    int numCuotas,
  ) {
    if (numCuotas <= 0) return principal;
    if (monthlyRate <= 0) return principal / numCuotas;
    final r = monthlyRate;
    final n = numCuotas;
    return principal * r / (1 - math.pow(1 + r, -n));
  }

  /// Generates the full installment schedule for a purchase.
  ///
  /// Each entry's [billingPeriod] is the parent's billing period advanced by
  /// i months (i = 0..numCuotas−1). Cutoff and payment dates are computed
  /// via [CreditCardCalculator] — no math is duplicated here.
  ///
  /// Rounding: cuotas 1..N−1 are rounded to 2 decimals; the last cuota
  /// gets the residual so the sum equals the true mathematical total.
  static List<InstallmentScheduleEntry> generateSchedule({
    required DateTime purchaseDate,
    required CreditCardRules rules,
    required Bank bank,
    required int numCuotas,
    required bool hasInterest,
    required double monthlyRate,
    required double principal,
  }) {
    final basePeriod = CreditCardCalculator.determineBillingPeriod(
        purchaseDate, rules, bank);
    final parts = basePeriod.split('-');
    final baseYear = int.parse(parts[0]);
    final baseMonth = int.parse(parts[1]);

    final effectiveRate = hasInterest ? monthlyRate : 0.0;
    final rawPayment =
        calculateMonthlyPayment(principal, effectiveRate, numCuotas);
    // Mathematical total before any rounding (used for residual on last cuota).
    final mathTotal = rawPayment * numCuotas;

    final entries = <InstallmentScheduleEntry>[];
    double runningTotal = 0.0;

    for (int i = 0; i < numCuotas; i++) {
      final (year, month) = _addMonths(baseYear, baseMonth, i);
      final billingPeriod = '$year-${month.toString().padLeft(2, '0')}';
      final cutoff =
          CreditCardCalculator.calculateCutoffDate(rules, bank, year, month);
      final payment =
          CreditCardCalculator.calculatePaymentDate(rules, bank, cutoff);

      final double amount;
      if (i == numCuotas - 1) {
        // Last cuota absorbs rounding residual.
        amount = _round2(mathTotal - runningTotal);
      } else {
        amount = _round2(rawPayment);
        runningTotal += amount;
      }

      entries.add(InstallmentScheduleEntry(
        number: i + 1,
        billingPeriod: billingPeriod,
        cutoffDate: cutoff,
        paymentDate: payment,
        chargeDate: cutoff,
        amount: amount,
      ));
    }

    return entries;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static (int year, int month) _addMonths(
      int baseYear, int baseMonth, int offset) {
    int totalMonths = (baseYear * 12 + (baseMonth - 1)) + offset;
    final year = totalMonths ~/ 12;
    final month = (totalMonths % 12) + 1;
    return (year, month);
  }

  static double _round2(double value) =>
      double.parse(value.toStringAsFixed(2));
}
