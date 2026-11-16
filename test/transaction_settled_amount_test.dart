import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _payment({
  double amount = 310_357.18,
  String currency = 'COP',
  String? targetCurrency,
  double? fxRate,
}) =>
    Transaction(
      id: 'p',
      accountId: 'savings',
      targetAccountId: 'card',
      amount: amount,
      description: 'Credit card payment',
      date: DateTime(2026, 11, 15),
      type: 'transfer',
      currency: currency,
      targetCurrency: targetCurrency,
      fxRate: fxRate,
    );

void main() {
  test('a COP payment of a USD debt settles in USD', () {
    final t = _payment(targetCurrency: 'USD', fxRate: 3165.6179);
    expect(t.settledCurrency, 'USD');
    expect(t.settledAmount, closeTo(98.04, 0.005));
  });

  test('a same-currency payment settles its own amount', () {
    final t = _payment(amount: 3_138_518);
    expect(t.settledCurrency, 'COP');
    expect(t.settledAmount, 3_138_518);
  });

  test('a missing rate falls back to the raw amount', () {
    final t = _payment(targetCurrency: 'USD');
    expect(t.settledCurrency, 'USD');
    expect(t.settledAmount, 310_357.18);
  });
}
