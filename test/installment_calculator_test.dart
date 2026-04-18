import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/core/utils/installment_calculator.dart';
import 'package:budgett_frontend/data/models/credit_card_rules_model.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';

// Minimal CreditCardRules with a fixed cutoff on day 20, payment day 5 next month.
CreditCardRules _fixedRules() => CreditCardRules(
      id: 'test',
      accountId: 'acc1',
      bankId: 'bank1',
      cutoffType: CutoffType.fixed,
      nominalCutoffDay: 20,
      paymentType: PaymentType.fixed,
      nominalPaymentDay: 5,
      paymentMonth: 'siguiente',
    );

// Bank with no adjustment rules (dates are not shifted).
Bank _noAdjBank() => Bank(id: 'bank1', name: 'Test', code: 'TST');

void main() {
  group('InstallmentCalculator.calculateMonthlyPayment', () {
    test('interest-free: divides principal equally', () {
      final payment =
          InstallmentCalculator.calculateMonthlyPayment(1200000, 0, 12);
      expect(payment, closeTo(100000.0, 0.01));
    });

    test('interest-free: 3 cuotas of 300,000 from 900,000', () {
      final payment =
          InstallmentCalculator.calculateMonthlyPayment(900000, 0, 3);
      expect(payment, closeTo(300000.0, 0.01));
    });

    test('French amortization: 2% monthly, 12 cuotas, 1,200,000 principal', () {
      // A = P * r / (1 - (1 + r)^-n)
      //   P=1,200,000  r=0.02  n=12
      //   (1.02)^12 ≈ 1.26824179
      //   A ≈ 1,200,000 * 0.02 * 1.26824179 / 0.26824179 ≈ 113,471.52
      final payment =
          InstallmentCalculator.calculateMonthlyPayment(1200000, 0.02, 12);
      expect(payment, closeTo(113471.52, 1.0));
    });

    test('single cuota with rate: French amort returns P*(1+r)', () {
      // n=1: A = P * r / (1 - (1+r)^-1) = P * r / (r/(1+r)) = P*(1+r)
      final payment =
          InstallmentCalculator.calculateMonthlyPayment(500000, 0.03, 1);
      expect(payment, closeTo(515000.0, 0.01));
    });
  });

  group('InstallmentCalculator.generateSchedule — interest-free', () {
    final rules = _fixedRules();
    final bank = _noAdjBank();

    test('3 cuotas: purchase before cutoff → periods M, M+1, M+2', () {
      // April 10 is before the cutoff on April 20.
      final purchaseDate = DateTime(2026, 4, 10);
      final entries = InstallmentCalculator.generateSchedule(
        purchaseDate: purchaseDate,
        rules: rules,
        bank: bank,
        numCuotas: 3,
        hasInterest: false,
        monthlyRate: 0,
        principal: 300000,
      );

      expect(entries.length, 3);
      expect(entries[0].billingPeriod, '2026-04');
      expect(entries[1].billingPeriod, '2026-05');
      expect(entries[2].billingPeriod, '2026-06');
      expect(entries[0].number, 1);
      expect(entries[2].number, 3);
    });

    test('3 cuotas: purchase after cutoff → periods M+1, M+2, M+3', () {
      // April 25 is after the cutoff on April 20.
      final purchaseDate = DateTime(2026, 4, 25);
      final entries = InstallmentCalculator.generateSchedule(
        purchaseDate: purchaseDate,
        rules: rules,
        bank: bank,
        numCuotas: 3,
        hasInterest: false,
        monthlyRate: 0,
        principal: 300000,
      );

      expect(entries[0].billingPeriod, '2026-05');
      expect(entries[1].billingPeriod, '2026-06');
      expect(entries[2].billingPeriod, '2026-07');
    });

    test('equal amounts for all cuotas (divisible principal)', () {
      final entries = InstallmentCalculator.generateSchedule(
        purchaseDate: DateTime(2026, 4, 10),
        rules: rules,
        bank: bank,
        numCuotas: 3,
        hasInterest: false,
        monthlyRate: 0,
        principal: 300000,
      );

      expect(entries[0].amount, 100000.0);
      expect(entries[1].amount, 100000.0);
      expect(entries[2].amount, 100000.0);
    });

    test('rounding residual goes to last cuota (non-divisible principal)', () {
      // 100,000 / 3 = 33,333.33... each → last gets residual
      final entries = InstallmentCalculator.generateSchedule(
        purchaseDate: DateTime(2026, 4, 10),
        rules: rules,
        bank: bank,
        numCuotas: 3,
        hasInterest: false,
        monthlyRate: 0,
        principal: 100000,
      );

      final total = entries.fold(0.0, (s, e) => s + e.amount);
      expect(total, closeTo(100000.0, 0.01));
      // First two are rounded down
      expect(entries[0].amount, 33333.33);
      expect(entries[1].amount, 33333.33);
      // Last absorbs the residual
      expect(entries[2].amount, closeTo(33333.34, 0.01));
    });

    test('chargeDate equals cutoffDate', () {
      final entries = InstallmentCalculator.generateSchedule(
        purchaseDate: DateTime(2026, 4, 10),
        rules: rules,
        bank: bank,
        numCuotas: 2,
        hasInterest: false,
        monthlyRate: 0,
        principal: 200000,
      );

      for (final e in entries) {
        expect(e.chargeDate, e.cutoffDate);
      }
    });
  });

  group('InstallmentCalculator.generateSchedule — with interest', () {
    final rules = _fixedRules();
    final bank = _noAdjBank();

    test('12 cuotas at 2%: sum of amounts exceeds principal', () {
      final entries = InstallmentCalculator.generateSchedule(
        purchaseDate: DateTime(2026, 4, 10),
        rules: rules,
        bank: bank,
        numCuotas: 12,
        hasInterest: true,
        monthlyRate: 0.02,
        principal: 1200000,
      );

      final total = entries.fold(0.0, (s, e) => s + e.amount);
      // Each payment ≈ 113,491 → total ≈ 1,361,896 > 1,200,000
      expect(total, greaterThan(1200000));
      expect(entries.length, 12);
    });

    test('payment date is after cutoff date', () {
      final entries = InstallmentCalculator.generateSchedule(
        purchaseDate: DateTime(2026, 4, 10),
        rules: rules,
        bank: bank,
        numCuotas: 3,
        hasInterest: true,
        monthlyRate: 0.015,
        principal: 600000,
      );

      for (final e in entries) {
        expect(e.paymentDate.isAfter(e.cutoffDate), isTrue);
      }
    });
  });

  group('InstallmentCalculator.generateSchedule — year wrapping', () {
    test('48 cuotas from November wrap across multiple years', () {
      final rules = _fixedRules();
      final bank = _noAdjBank();
      final purchaseDate = DateTime(2026, 11, 5); // Nov 5 < cutoff day 20

      final entries = InstallmentCalculator.generateSchedule(
        purchaseDate: purchaseDate,
        rules: rules,
        bank: bank,
        numCuotas: 48,
        hasInterest: false,
        monthlyRate: 0,
        principal: 4800000,
      );

      expect(entries.length, 48);
      expect(entries.first.billingPeriod, '2026-11');
      expect(entries.last.billingPeriod, '2030-10');
      // All billing periods must be unique
      final periods = entries.map((e) => e.billingPeriod).toSet();
      expect(periods.length, 48);
    });
  });
}
