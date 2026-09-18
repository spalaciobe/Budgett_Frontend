// Deduplication is the part of the capture pipeline that can silently lose an
// expense, so these tests pin down both directions: copies of one payment must
// collapse, and two genuinely separate payments must not.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/utils/capture_dedup.dart';

final _base = DateTime(2026, 9, 17, 15, 44);

DedupCandidate _candidate({
  String id = 'new',
  double amount = 45900,
  String currency = 'COP',
  String? merchantKey = 'EXITO SUPER CL 80',
  String? cardLast4 = '1234',
  String? issuerKey = 'bancolombia',
  DateTime? occurredAt,
  bool dayPrecisionOnly = false,
}) =>
    DedupCandidate(
      id: id,
      amount: amount,
      currency: currency,
      merchantKey: merchantKey,
      cardLast4: cardLast4,
      issuerKey: issuerKey,
      occurredAt: occurredAt ?? _base,
      dayPrecisionOnly: dayPrecisionOnly,
    );

void main() {
  group('merchantsMatch', () {
    test('accepts a truncated prefix of the same name', () {
      expect(merchantsMatch('EXITO', 'EXITO SUPER CL 80'), isTrue);
    });

    test('rejects a short prefix that could be another brand', () {
      // "ARA" must not swallow "ARARAT".
      expect(merchantsMatch('ARA', 'ARARAT'), isFalse);
    });

    test('requires a whole-word boundary', () {
      expect(merchantsMatch('RAPPI', 'RAPPIPAY'), isFalse);
      expect(merchantsMatch('RAPPI', 'RAPPI PAY'), isTrue);
    });

    test('a missing key never matches', () {
      expect(merchantsMatch(null, 'EXITO'), isFalse);
      expect(merchantsMatch('', 'EXITO'), isFalse);
    });
  });

  group('findDuplicateCapture', () {
    test('same card and amount minutes apart is conclusive', () {
      // The classic case: push notification, then the SMS.
      final existing = [
        _candidate(
          id: 'push',
          merchantKey: 'EXITO SUPER CL 80',
          occurredAt: _base,
        ),
      ];
      final verdict = findDuplicateCapture(
        _candidate(id: 'sms', occurredAt: _base.add(const Duration(minutes: 3))),
        existing,
      );

      expect(verdict, isNotNull);
      expect(verdict!.matchId, 'push');
      expect(verdict.isConclusive, isTrue);
      expect(verdict.reason, DuplicateReason.sameCardAndAmount);
    });

    test('same merchant and amount is conclusive without a card', () {
      final existing = [_candidate(id: 'push', cardLast4: null)];
      final verdict = findDuplicateCapture(
        _candidate(
          id: 'wallet',
          cardLast4: null,
          issuerKey: 'rappi',
          occurredAt: _base.add(const Duration(minutes: 2)),
        ),
        existing,
      );

      expect(verdict!.reason, DuplicateReason.sameMerchantAndAmount);
      expect(verdict.isConclusive, isTrue);
    });

    test('same bank and amount with no merchant is only a warning', () {
      // Enough to flag, not enough to hide the message.
      final existing = [_candidate(id: 'push', merchantKey: null, cardLast4: null)];
      final verdict = findDuplicateCapture(
        _candidate(
          id: 'sms',
          merchantKey: 'EXITO',
          cardLast4: null,
          occurredAt: _base.add(const Duration(minutes: 1)),
        ),
        existing,
      );

      expect(verdict!.reason, DuplicateReason.sameIssuerAndAmount);
      expect(verdict.isConclusive, isFalse);
    });

    test('outside the window is a separate payment', () {
      final existing = [_candidate(id: 'earlier')];
      final verdict = findDuplicateCapture(
        _candidate(id: 'later', occurredAt: _base.add(const Duration(hours: 3))),
        existing,
      );
      expect(verdict, isNull);
    });

    test('a different amount is a separate payment', () {
      final existing = [_candidate(id: 'first', amount: 45900)];
      expect(
        findDuplicateCapture(_candidate(id: 'second', amount: 46900), existing),
        isNull,
      );
    });

    test('tolerates a one-peso rounding difference between sources', () {
      final existing = [_candidate(id: 'push', amount: 45900)];
      final verdict = findDuplicateCapture(
          _candidate(id: 'sms', amount: 45899), existing);
      expect(verdict!.isConclusive, isTrue);
    });

    test('the same amount in another currency is not a duplicate', () {
      final existing = [_candidate(id: 'cop', amount: 50, currency: 'COP')];
      expect(
        findDuplicateCapture(
            _candidate(id: 'usd', amount: 50, currency: 'USD'), existing),
        isNull,
      );
    });

    test('different cards at the same merchant and amount are distinct', () {
      // Two people paying the same bill on two cards, same minute.
      final existing = [
        _candidate(id: 'mine', cardLast4: '1111', merchantKey: null),
      ];
      final verdict = findDuplicateCapture(
        _candidate(id: 'theirs', cardLast4: '2222', merchantKey: null),
        existing,
      );
      // No card match, no merchant match — only the issuer warning applies.
      expect(verdict?.isConclusive ?? false, isFalse);
    });

    test('never matches itself', () {
      final self = _candidate(id: 'same');
      expect(findDuplicateCapture(self, [self]), isNull);
    });

    test('honours a custom window', () {
      final existing = [_candidate(id: 'push')];
      final twentyMinutesLater =
          _candidate(id: 'sms', occurredAt: _base.add(const Duration(minutes: 20)));

      expect(findDuplicateCapture(twentyMinutesLater, existing), isNull);
      expect(
        findDuplicateCapture(twentyMinutesLater, existing,
            window: const Duration(minutes: 30)),
        isNotNull,
      );
    });
  });

  group('findTransactionCollision', () {
    test('flags an expense already typed in by hand that day', () {
      // Only the day is known for a manual row, so the window widens to 24h.
      final manual = _candidate(
        id: 'tx',
        occurredAt: DateTime(2026, 9, 17),
        merchantKey: null,
        cardLast4: null,
        issuerKey: null,
        dayPrecisionOnly: true,
      );

      final verdict = findTransactionCollision(_candidate(), [manual]);
      expect(verdict, isNotNull);
      expect(verdict!.matchId, 'tx');
      // Two identical coffees in one day are legitimate, so never conclusive.
      expect(verdict.isConclusive, isFalse);
    });

    test('names the merchant when both sides agree on it', () {
      final manual = _candidate(
        id: 'tx',
        occurredAt: DateTime(2026, 9, 17),
        cardLast4: null,
        dayPrecisionOnly: true,
      );
      final verdict = findTransactionCollision(_candidate(), [manual]);
      expect(verdict!.reason, DuplicateReason.sameMerchantAndAmount);
    });

    test('a different amount on the same day does not collide', () {
      final manual = _candidate(
        id: 'tx',
        amount: 12000,
        occurredAt: DateTime(2026, 9, 17),
        dayPrecisionOnly: true,
      );
      expect(findTransactionCollision(_candidate(), [manual]), isNull);
    });
  });

  group('dedupHash', () {
    test('is time-free, so copies minutes apart share it', () {
      final a = dedupHash(
          amount: 45900, merchantKey: 'EXITO', cardLast4: '1234');
      final b = dedupHash(
          amount: 45900, merchantKey: 'EXITO', cardLast4: '1234');
      expect(a, b);
    });

    test('separates amount, card and merchant', () {
      expect(
        dedupHash(amount: 45900, merchantKey: 'EXITO', cardLast4: '1234'),
        isNot(dedupHash(amount: 45900, merchantKey: 'EXITO', cardLast4: '9999')),
      );
      expect(
        dedupHash(amount: 45900, merchantKey: 'EXITO'),
        isNot(dedupHash(amount: 45901, merchantKey: 'EXITO')),
      );
    });
  });
}
