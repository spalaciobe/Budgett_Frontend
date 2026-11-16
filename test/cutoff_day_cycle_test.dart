import 'package:budgett_frontend/core/utils/credit_card_calculator.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';
import 'package:budgett_frontend/data/models/credit_card_rules_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Cut-off on the 15th, payment on the 2nd of the next month. Oct 15, 2026 is
// a Thursday, so the October cut-off is exactly that day.
final _rules = CreditCardRules.fromJson({
  'id': 'r',
  'account_id': 'card',
  'banco_id': 'bank',
  'tipo_corte': 'fijo',
  'dia_corte_nominal': 15,
  'tipo_pago': 'fijo',
  'dia_pago_nominal': 2,
  'mes_pago': 'siguiente',
  'tipo_offset_pago': 'calendario',
  'default_installment_rate': 0.0,
});

Bank _bank({bool nextCycle = false}) => Bank(
      id: 'bank',
      name: 'Bank',
      code: 'B',
      adjustmentRuleCutoff: 'postergar_dia_habil_siguiente',
      adjustmentRulePayment: 'postergar_dia_habil_siguiente',
      cutoffDayInNextCycle: nextCycle,
    );

void main() {
  group('cut-off day, bank bills it in the closing cycle (default)', () {
    final bank = _bank();

    test('a purchase typed by hand (midnight) stays in the closing cycle', () {
      expect(
          CreditCardCalculator.determineBillingPeriod(
              DateTime(2026, 10, 15), _rules, bank),
          '2026-10');
    });

    test('a captured purchase at 12:50 stays there too', () {
      // Used to compare as "after" a midnight cut-off and jump a cycle.
      expect(
          CreditCardCalculator.determineBillingPeriod(
              DateTime(2026, 10, 15, 12, 50), _rules, bank),
          '2026-10');
    });

    test('the day after goes to the next cycle', () {
      expect(
          CreditCardCalculator.determineBillingPeriod(
              DateTime(2026, 10, 16), _rules, bank),
          '2026-11');
    });
  });

  group('cut-off day, bank bills it in the next cycle (Bancolombia)', () {
    final bank = _bank(nextCycle: true);

    test('the cut-off day goes to the next cycle, whatever the time', () {
      for (final t in [
        DateTime(2026, 10, 15),
        DateTime(2026, 10, 15, 12, 50),
        DateTime(2026, 10, 15, 23, 59),
      ]) {
        expect(CreditCardCalculator.determineBillingPeriod(t, _rules, bank),
            '2026-11',
            reason: '$t');
      }
    });

    test('the day before stays in the closing cycle', () {
      expect(
          CreditCardCalculator.determineBillingPeriod(
              DateTime(2026, 10, 14, 23, 59), _rules, bank),
          '2026-10');
    });

    test('the payment schedule agrees with the billing period', () {
      final s = CreditCardCalculator.scheduleForPurchase(
          DateTime(2026, 10, 15, 9), _rules, bank);
      // November cut-off: Nov 15 is a Sunday and Nov 16 a holiday.
      expect(s.cutoff, DateTime(2026, 11, 17));
      expect(s.payment, DateTime(2026, 12, 2));
    });

    test('billing fields for a captured purchase land in the next cycle', () {
      final f = CreditCardCalculator.billingFieldsFor(
          date: DateTime(2026, 10, 15, 12, 50), rules: _rules, bank: bank);
      expect(f['periodo_facturacion'], '2026-11');
    });
  });

  test('Bank reads the flag from the catalog, default off', () {
    expect(
        Bank.fromJson({
          'id': 'b',
          'nombre': 'Bancolombia',
          'codigo': 'BANCOLOMBIA',
          'dia_corte_en_siguiente_ciclo': true,
        }).cutoffDayInNextCycle,
        isTrue);
    expect(
        Bank.fromJson({'id': 'b', 'nombre': 'Nu', 'codigo': 'NUBANK'})
            .cutoffDayInNextCycle,
        isFalse);
  });
}
