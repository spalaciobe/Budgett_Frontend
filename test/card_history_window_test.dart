import 'package:budgett_frontend/core/utils/card_history_window.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx(String date, String? period, {String type = 'expense'}) =>
    Transaction(
      id: '$date-$period',
      accountId: 'card',
      amount: 1,
      description: 'x',
      date: DateTime.parse(date),
      type: type,
      billingPeriod: period,
    );

void main() {
  group('CardHistoryWindow', () {
    final window = CardHistoryWindow.from(DateTime(2026, 11, 15));

    test('covers the current month and the five before it', () {
      expect(window.firstPeriod, '2026-06');
    });

    test('fetches from two months before the first period', () {
      expect(window.fetchFrom, DateTime(2026, 4, 1));
    });

    test('keeps every row of the first period, even backfilled dates', () {
      // A period's purchases start after the previous cutoff (mid-May).
      expect(window.keeps(_tx('2026-05-16', '2026-06')), isTrue);
      expect(window.keeps(_tx('2026-05-02', '2026-06')), isTrue);
    });

    test('drops rows of older periods that the margin pulled in', () {
      expect(window.keeps(_tx('2026-05-10', '2026-05')), isFalse);
    });

    test('keeps future installment cuotas', () {
      expect(window.keeps(_tx('2027-09-15', '2027-09')), isTrue);
    });

    test('keeps untagged rows only from the month before the first period',
        () {
      expect(window.keeps(_tx('2026-05-20', null, type: 'transfer')), isTrue);
      expect(window.keeps(_tx('2026-04-20', null, type: 'transfer')), isFalse);
    });

    test('rolls over the year', () {
      final jan = CardHistoryWindow.from(DateTime(2027, 1, 3));
      expect(jan.firstPeriod, '2026-08');
      expect(jan.fetchFrom, DateTime(2026, 6, 1));
    });
  });
}
