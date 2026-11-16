import 'package:budgett_frontend/core/utils/installment_prepay.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';
import 'package:budgett_frontend/data/models/credit_card_rules_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Bancolombia-style card: cut on the 15th, pay on the 2nd of next month,
// both moved to the next business day.
final _rules = CreditCardRules.fromJson({
  'id': 'r',
  'account_id': 'card',
  'banco_id': 'bco',
  'tipo_corte': 'fijo',
  'dia_corte_nominal': 15,
  'tipo_pago': 'fijo',
  'dia_pago_nominal': 2,
  'mes_pago': 'siguiente',
  'tipo_offset_pago': 'calendario',
  'default_installment_rate': 0.0,
});
final _bank = Bank.fromJson({
  'id': 'bco',
  'nombre': 'Bancolombia',
  'codigo': 'BANCOLOMBIA',
  'regla_ajuste_corte': 'postergar_dia_habil_siguiente',
  'regla_ajuste_pago': 'postergar_dia_habil_siguiente',
  'tipo_offset_default': 'calendario',
  'permite_cambio_fecha': false,
  'activo': true,
});

Transaction _cuota(
  String id,
  String date,
  String period, {
  String status = 'paid',
  double amount = 100,
  String currency = 'COP',
  String accountId = 'card',
  String? parent = 'p1',
}) =>
    Transaction(
      id: id,
      accountId: accountId,
      amount: amount,
      description: 'Air fryer - Inst. $id',
      date: DateTime.parse(date),
      type: 'expense',
      status: status,
      currency: currency,
      billingPeriod: period,
      parentTransactionId: parent,
    );

void main() {
  final paymentDate = DateTime(2026, 10, 31);
  final txs = [
    _cuota('1', '2026-10-15', '2026-10'), // already billed
    _cuota('2', '2026-11-17', '2026-11'), // future, already counted
    _cuota('3', '2026-12-15', '2026-12'),
    _cuota('pend', '2026-09-15', '2026-09', status: 'pending'),
    _cuota('usd', '2026-11-17', '2026-11', currency: 'USD'),
    _cuota('other-card', '2026-11-17', '2026-11', accountId: 'other'),
    _cuota('plain', '2026-11-17', '2026-11', parent: null),
  ];

  group('InstallmentPrepay.closable', () {
    test('lists unbilled cuotas even when already paid, plus pending ones',
        () {
      final ids = InstallmentPrepay.closable(txs,
              cardId: 'card', currency: 'COP', paymentDate: paymentDate)
          .map((t) => t.id)
          .toList();
      expect(ids, ['pend', '2', '3']);
    });

    test('a cuota billed on the payment day is no longer closable', () {
      final ids = InstallmentPrepay.closable(txs,
              cardId: 'card',
              currency: 'COP',
              paymentDate: DateTime(2026, 11, 17, 18, 30))
          .map((t) => t.id);
      expect(ids, isNot(contains('2')));
      expect(ids, contains('3'));
    });
  });

  group('amounts', () {
    final closed = [txs[1], txs[2], txs[3]]; // 2, 3, pend

    test('only pending cuotas add to the card debt', () {
      expect(InstallmentPrepay.uncountedTotal(closed), 100);
    });

    test('every cuota outside the statement adds to its total', () {
      expect(InstallmentPrepay.addedToPeriod(closed, '2026-10'), 300);
      expect(InstallmentPrepay.addedToPeriod(closed, '2026-11'), 200);
    });
  });

  group('InstallmentPrepay.lastClosedPeriod', () {
    test('after the October cut, prepayments land in October', () {
      expect(InstallmentPrepay.lastClosedPeriod(paymentDate, _rules, _bank),
          '2026-10');
    });

    test('rolls back over the year', () {
      expect(
          InstallmentPrepay.lastClosedPeriod(
              DateTime(2027, 1, 3), _rules, _bank),
          '2026-12');
    });
  });

  test('close target carries the cycle dates', () {
    final target = InstallmentCloseTarget.forPeriod('2026-11', _rules, _bank);
    // Nov 15, 2026 is a Sunday and Nov 16 a holiday.
    expect(target.cutoffDate, DateTime(2026, 11, 17));
    expect(target.paymentDate, DateTime(2026, 12, 2));
  });
}
