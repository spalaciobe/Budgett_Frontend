// Built from this user's actual recurring list and the captures that matched
// it. Two dismissed messages — Suramericana at 91,983 and SMART FIT at
// 101,500 — line up with an active recurring to the peso, and auto-posting
// either would have recorded the expense twice.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/utils/recurring_match.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';

RecurringTransaction _recurring({
  required String description,
  required double amount,
  String type = 'expense',
  bool isActive = true,
}) =>
    RecurringTransaction.fromJson({
      'id': description,
      'description': description,
      'amount': amount,
      'type': type,
      'frequency': 'monthly',
      'next_run_date': '2026-11-01',
      'is_active': isActive,
    });

final _list = [
  _recurring(description: 'Health Insurance SURA', amount: 91983),
  _recurring(description: 'Gym - Smart Fit', amount: 101500),
  _recurring(description: 'Spotify Familiar', amount: 30500),
  _recurring(description: 'Runni paycheck', amount: 1610834, type: 'income'),
];

void main() {
  group('findRecurringMatch', () {
    test('matches the gym on amount and name', () {
      final match = findRecurringMatch(
        amount: 101500,
        transactionType: 'expense',
        merchantKey: 'SMART FIT 20 DE JULI',
        recurring: _list,
      );

      expect(match, isNotNull);
      expect(match!.label, 'Gym - Smart Fit');
      expect(match.nameAlsoMatches, isTrue);
    });

    test('matches the insurer through a shared prefix', () {
      // "SURA" against "SURAMERICANA": the recurring uses the short name.
      final match = findRecurringMatch(
        amount: 91983,
        transactionType: 'expense',
        merchantKey: 'SURAMERICANA DE SEGUROS DE VIDA',
        recurring: _list,
      );

      expect(match!.label, 'Health Insurance SURA');
      expect(match.nameAlsoMatches, isTrue);
    });

    test('the amount alone still matches, but more weakly', () {
      final match = findRecurringMatch(
        amount: 30500,
        transactionType: 'expense',
        merchantKey: 'UNRELATED SHOP',
        recurring: _list,
      );

      expect(match!.label, 'Spotify Familiar');
      // Worth surfacing, not worth treating as certain.
      expect(match.nameAlsoMatches, isFalse);
    });

    test('direction has to agree', () {
      // The paycheck is income; an expense of the same figure is not it.
      expect(
        findRecurringMatch(
          amount: 1610834,
          transactionType: 'expense',
          merchantKey: 'ALGO',
          recurring: _list,
        ),
        isNull,
      );
    });

    test('a different amount is a different charge', () {
      expect(
        findRecurringMatch(
          amount: 101499,
          transactionType: 'expense',
          merchantKey: 'SMART FIT 20 DE JULI',
          recurring: _list,
        ),
        isNotNull, // within the one-peso tolerance
      );
      expect(
        findRecurringMatch(
          amount: 95000,
          transactionType: 'expense',
          merchantKey: 'SMART FIT 20 DE JULI',
          recurring: _list,
        ),
        isNull,
      );
    });

    test('an inactive recurring never matches', () {
      final paused = [
        _recurring(
            description: 'Gym - Smart Fit', amount: 101500, isActive: false),
      ];
      expect(
        findRecurringMatch(
          amount: 101500,
          transactionType: 'expense',
          merchantKey: 'SMART FIT',
          recurring: paused,
        ),
        isNull,
      );
    });

    test('generic words cannot pair unrelated names', () {
      // "Monthly Investment Trii" and "PAGO DE LA TIENDA" share only filler.
      final list = [
        _recurring(description: 'Monthly Investment Trii', amount: 750000),
      ];
      final match = findRecurringMatch(
        amount: 750000,
        transactionType: 'expense',
        merchantKey: 'PAGO DE LA TIENDA',
        recurring: list,
      );
      expect(match!.nameAlsoMatches, isFalse);
    });
  });
}
