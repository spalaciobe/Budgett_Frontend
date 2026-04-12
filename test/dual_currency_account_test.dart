import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/data/models/account_model.dart';

void main() {
  group('Account dual-currency fields', () {
    test('parses balance_usd and credit_limit_usd from JSON', () {
      final a = Account.fromJson({
        'id': 'acc-tc',
        'name': 'Amex Gold',
        'type': 'credit_card',
        'balance': -500000.0,
        'credit_limit': 5000000,
        'balance_usd': -200.0,
        'credit_limit_usd': 2000.0,
      });

      expect(a.balanceUsd, -200.0);
      expect(a.creditLimitUsd, 2000.0);
    });

    test('defaults balance_usd to 0 when absent', () {
      final a = Account.fromJson({
        'id': 'acc-1',
        'name': 'Ahorro',
        'type': 'savings',
        'balance': 1000000.0,
        'credit_limit': 0,
      });

      expect(a.balanceUsd, 0.0);
      expect(a.creditLimitUsd, 0.0);
    });

    test('defaults balance_usd to 0 when null', () {
      final a = Account.fromJson({
        'id': 'acc-2',
        'name': 'TC',
        'type': 'credit_card',
        'balance': -100000.0,
        'credit_limit': 1000000,
        'balance_usd': null,
        'credit_limit_usd': null,
      });

      expect(a.balanceUsd, 0.0);
      expect(a.creditLimitUsd, 0.0);
    });

    test('available USD = creditLimitUsd + balanceUsd (negative debt)', () {
      final a = Account.fromJson({
        'id': 'acc-tc',
        'name': 'TC',
        'type': 'credit_card',
        'balance': -300000.0,
        'credit_limit': 3000000,
        'balance_usd': -200.0,
        'credit_limit_usd': 2000.0,
      });

      // Available USD = 2000 + (-200) = 1800
      expect(a.creditLimitUsd + a.balanceUsd, closeTo(1800.0, 0.001));
    });

    test('balance_usd zero means no USD debt', () {
      final a = Account.fromJson({
        'id': 'acc-tc',
        'name': 'TC',
        'type': 'credit_card',
        'balance': -50000.0,
        'credit_limit': 500000,
        'balance_usd': 0,
        'credit_limit_usd': 1000.0,
      });

      expect(a.balanceUsd, 0.0);
      expect(a.balanceUsd != 0, isFalse);
    });
  });
}
