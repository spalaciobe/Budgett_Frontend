import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/core/utils/credit_card_calculator.dart';
import 'package:budgett_frontend/core/utils/colombian_calendar.dart';
import 'package:budgett_frontend/data/models/credit_card_rules_model.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';

/// Helper to create a Bank with optional adjustment rules.
Bank _makeBank({
  String code = 'BANCOLOMBIA',
  String? adjustmentRuleCutoff,
  String? adjustmentRulePayment,
}) {
  return Bank(
    id: 'bank-1',
    name: 'Test Bank',
    code: code,
    adjustmentRuleCutoff: adjustmentRuleCutoff,
    adjustmentRulePayment: adjustmentRulePayment,
  );
}

void main() {
  group('CreditCardCalculator.calculateCutoffDate', () {
    test('fixed cutoff returns the exact day', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.fixed,
        nominalCutoffDay: 15,
        paymentType: PaymentType.fixed,
      );
      final bank = _makeBank();

      final cutoff = CreditCardCalculator.calculateCutoffDate(rules, bank, 2026, 3);
      expect(cutoff.day, 15);
      expect(cutoff.month, 3);
      expect(cutoff.year, 2026);
    });

    test('fixed cutoff clamps day when month is shorter (Feb 28)', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.fixed,
        nominalCutoffDay: 31,
        paymentType: PaymentType.fixed,
      );
      final bank = _makeBank();

      // Feb 2026 has 28 days
      final cutoff = CreditCardCalculator.calculateCutoffDate(rules, bank, 2026, 2);
      expect(cutoff.day, 28);
      expect(cutoff.month, 2);
    });

    test('fixed cutoff clamps day for 30-day month', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.fixed,
        nominalCutoffDay: 31,
        paymentType: PaymentType.fixed,
      );
      final bank = _makeBank();

      final cutoff = CreditCardCalculator.calculateCutoffDate(rules, bank, 2026, 4);
      expect(cutoff.day, 30);
      expect(cutoff.month, 4);
    });

    test('fixed cutoff with holiday adjustment moves to previous business day', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.fixed,
        nominalCutoffDay: 1,
        paymentType: PaymentType.fixed,
      );
      // Jan 1 is a fixed holiday in Colombia
      final bank = _makeBank(adjustmentRuleCutoff: 'adelantar_dia_habil_anterior');

      final cutoff = CreditCardCalculator.calculateCutoffDate(rules, bank, 2026, 1);
      // Jan 1 is holiday → should be moved to previous business day (Dec 31, 2025 is Wed)
      expect(cutoff.isBefore(DateTime(2026, 1, 1)), isTrue);
      expect(ColombianCalendar.isBusinessDay(cutoff), isTrue);
    });

    test('relative cutoff secondToLastBusinessDay', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.relative,
        relativeCutoffType: RelativeCutoffType.secondToLastBusinessDay,
        paymentType: PaymentType.fixed,
      );
      final bank = _makeBank();

      final cutoff = CreditCardCalculator.calculateCutoffDate(rules, bank, 2026, 3);
      final businessDays = ColombianCalendar.getBusinessDaysInMonth(2026, 3);
      expect(cutoff, businessDays[businessDays.length - 2]);
    });

    test('relative cutoff lastBusinessDay', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.relative,
        relativeCutoffType: RelativeCutoffType.lastBusinessDay,
        paymentType: PaymentType.fixed,
      );
      final bank = _makeBank();

      final cutoff = CreditCardCalculator.calculateCutoffDate(rules, bank, 2026, 6);
      final businessDays = ColombianCalendar.getBusinessDaysInMonth(2026, 6);
      expect(cutoff, businessDays.last);
    });
  });

  group('CreditCardCalculator.calculatePaymentDate', () {
    test('fixed payment in next month', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.fixed,
        nominalCutoffDay: 15,
        paymentType: PaymentType.fixed,
        nominalPaymentDay: 5,
        paymentMonth: 'siguiente',
      );
      final bank = _makeBank();

      final cutoff = DateTime(2026, 3, 15);
      final payment = CreditCardCalculator.calculatePaymentDate(rules, bank, cutoff);
      expect(payment.month, 4);
      expect(payment.day, 5);
      expect(payment.year, 2026);
    });

    test('fixed payment wraps year (December cutoff → January payment)', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.fixed,
        nominalCutoffDay: 15,
        paymentType: PaymentType.fixed,
        nominalPaymentDay: 10,
        paymentMonth: 'siguiente',
      );
      final bank = _makeBank();

      final cutoff = DateTime(2026, 12, 15);
      final payment = CreditCardCalculator.calculatePaymentDate(rules, bank, cutoff);
      expect(payment.month, 1);
      expect(payment.year, 2027);
      expect(payment.day, 10);
    });

    test('relative days (calendar) after cutoff', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.relative,
        relativeCutoffType: RelativeCutoffType.secondToLastBusinessDay,
        paymentType: PaymentType.relativeDays,
        daysAfterCutoff: 10,
        paymentOffsetType: OffsetType.calendar,
      );
      final bank = _makeBank();

      final cutoff = DateTime(2026, 3, 30);
      final payment = CreditCardCalculator.calculatePaymentDate(rules, bank, cutoff);
      expect(payment, DateTime(2026, 4, 9));
    });

    test('relative days (business) after cutoff', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.relative,
        relativeCutoffType: RelativeCutoffType.secondToLastBusinessDay,
        paymentType: PaymentType.relativeDays,
        daysAfterCutoff: 5,
        paymentOffsetType: OffsetType.business,
      );
      final bank = _makeBank();

      final cutoff = DateTime(2026, 3, 30); // Monday
      final payment = CreditCardCalculator.calculatePaymentDate(rules, bank, cutoff);

      // 5 business days from March 30 (Mon):
      // Mar 31(Tue), Apr 1(Wed), Apr 2(Thu), Apr 3(Fri)... check for holidays
      expect(ColombianCalendar.isBusinessDay(payment), isTrue);
      // Payment must be strictly after cutoff
      expect(payment.isAfter(cutoff), isTrue);
    });

    test('fixed payment day clamped in short month (Feb)', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.fixed,
        nominalCutoffDay: 15,
        paymentType: PaymentType.fixed,
        nominalPaymentDay: 30,
        paymentMonth: 'siguiente',
      );
      final bank = _makeBank();

      // January cutoff → payment in February
      final cutoff = DateTime(2026, 1, 15);
      final payment = CreditCardCalculator.calculatePaymentDate(rules, bank, cutoff);
      expect(payment.month, 2);
      expect(payment.day, 28); // Feb 2026 has 28 days
    });

    test('payment with holiday adjustment moves to next business day', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.fixed,
        nominalCutoffDay: 15,
        paymentType: PaymentType.fixed,
        nominalPaymentDay: 1,
        paymentMonth: 'siguiente',
      );
      // May 1 is Labor Day (holiday) in Colombia
      final bank = _makeBank(adjustmentRulePayment: 'postergar_dia_habil_siguiente');

      final cutoff = DateTime(2026, 4, 15);
      final payment = CreditCardCalculator.calculatePaymentDate(rules, bank, cutoff);
      // May 1 is holiday → should be moved to next business day
      expect(payment.isAfter(DateTime(2026, 5, 1)) || payment.isAtSameMomentAs(DateTime(2026, 5, 1)), isTrue);
      expect(ColombianCalendar.isBusinessDay(payment), isTrue);
    });
  });

  group('Edge cases', () {
    test('Feb in leap year has 29 days', () {
      final rules = CreditCardRules(
        id: 'r1',
        accountId: 'a1',
        bankId: 'bank-1',
        cutoffType: CutoffType.fixed,
        nominalCutoffDay: 31,
        paymentType: PaymentType.fixed,
      );
      final bank = _makeBank();

      // 2028 is a leap year
      final cutoff = CreditCardCalculator.calculateCutoffDate(rules, bank, 2028, 2);
      expect(cutoff.day, 29);
      expect(cutoff.month, 2);
    });

    test('adjustDateByRule returns same date if already business day', () {
      // Pick a known weekday that's not a holiday
      final date = DateTime(2026, 3, 18); // Wednesday
      expect(ColombianCalendar.isBusinessDay(date), isTrue);
      final result = CreditCardCalculator.adjustDateByRule(date, 'adelantar_dia_habil_anterior');
      expect(result, date);
    });

    test('adjustDateByRule with null rule returns original date', () {
      final date = DateTime(2026, 1, 1); // Holiday
      final result = CreditCardCalculator.adjustDateByRule(date, null);
      expect(result, date);
    });
  });
}
