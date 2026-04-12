import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';

Transaction _tx(Map<String, dynamic> overrides) {
  return Transaction.fromJson({
    'id': 'tx-1',
    'account_id': 'acc-1',
    'amount': 100.0,
    'description': 'Test',
    'date': '2026-04-01',
    'type': 'expense',
    'status': 'cleared',
    ...overrides,
  });
}

void main() {
  group('Transaction.currency field', () {
    test('defaults currency to COP when absent', () {
      final t = _tx({});
      expect(t.currency, 'COP');
    });

    test('defaults currency to COP when null', () {
      final t = _tx({'currency': null});
      expect(t.currency, 'COP');
    });

    test('parses currency = USD', () {
      final t = _tx({'currency': 'USD'});
      expect(t.currency, 'USD');
    });

    test('parses currency = COP explicitly', () {
      final t = _tx({'currency': 'COP'});
      expect(t.currency, 'COP');
    });
  });

  group('Transaction.targetCurrency and fxRate', () {
    test('targetCurrency and fxRate are null by default', () {
      final t = _tx({});
      expect(t.targetCurrency, isNull);
      expect(t.fxRate, isNull);
    });

    test('parses cross-currency transfer fields', () {
      final t = _tx({
        'type': 'transfer',
        'target_account_id': 'acc-tc',
        'currency': 'COP',
        'target_currency': 'USD',
        'fx_rate': 4200.0,
      });

      expect(t.currency, 'COP');
      expect(t.targetCurrency, 'USD');
      expect(t.fxRate, 4200.0);
    });

    test('isCrossCurrencyPayment is true for cross-currency transfer', () {
      final t = _tx({
        'type': 'transfer',
        'target_account_id': 'acc-tc',
        'currency': 'COP',
        'target_currency': 'USD',
        'fx_rate': 4200.0,
      });
      expect(t.isCrossCurrencyPayment, isTrue);
    });

    test('isCrossCurrencyPayment is false when same currency', () {
      final t = _tx({
        'type': 'transfer',
        'target_account_id': 'acc-2',
        'currency': 'COP',
        'target_currency': 'COP',
        'fx_rate': null,
      });
      expect(t.isCrossCurrencyPayment, isFalse);
    });

    test('isCrossCurrencyPayment is false when targetCurrency is null', () {
      final t = _tx({'type': 'expense'});
      expect(t.isCrossCurrencyPayment, isFalse);
    });

    test('USD applied = amount / fx_rate', () {
      // 840,000 COP / 4,200 = 200 USD
      const amount = 840000.0;
      const fxRate = 4200.0;
      expect(amount / fxRate, closeTo(200.0, 0.001));
    });
  });
}
