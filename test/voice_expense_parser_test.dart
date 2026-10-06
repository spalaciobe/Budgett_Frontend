// Phrases as they would actually be dictated, in Spanish, with the verb and
// the amount in whatever order they come out.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/parsing/voice_expense_parser.dart';

final _now = DateTime(2026, 10, 6, 13, 30);

ExpenseDraft _parse(String spoken) => parseVoiceExpense(spoken, now: _now);

void main() {
  group('what happened', () {
    test('spending is the default reading', () {
      final draft = _parse('gaste veinte mil en el almuerzo');
      expect(draft.kind, MessageKind.purchase);
      expect(draft.amount, 20000);
      expect(draft.description, 'Almuerzo');
    });

    test('money arriving is told apart from money leaving', () {
      expect(_parse('me pagaron dos millones').kind, MessageKind.transferIn);
      expect(_parse('recibi cien mil').kind, MessageKind.transferIn);
      expect(
          _parse('le transferi cincuenta mil a Juan').kind,
          MessageKind.transferOut);
    });

    test('"me pagaron" is not read as "pagué"', () {
      // The incoming verbs have to be tested first or this is an expense.
      final draft = _parse('me pagaron un millon quinientos mil');
      expect(draft.kind, MessageKind.transferIn);
      expect(draft.amount, 1500000);
    });

    test('cash out of a machine', () {
      expect(_parse('retire doscientos mil').kind, MessageKind.withdrawal);
    });

    test('English works too', () {
      final draft = _parse('i spent 45.900 on lunch');
      expect(draft.kind, MessageKind.purchase);
      expect(draft.amount, 45900);
    });
  });

  group('what it was for', () {
    test('reads the subject after the amount', () {
      expect(_parse('pague cuarenta mil de taxi').description, 'Taxi');
      expect(_parse('gaste treinta mil en mercado').description, 'Mercado');
      expect(_parse('compre quince mil en el cafe').description, 'Cafe');
    });

    test('a transfer counterparty is a merchant, not a description', () {
      // A person's name is worth remembering a rule against; "el almuerzo"
      // is not.
      final draft = _parse('le transferi cincuenta mil a Mariana');
      expect(draft.merchant, 'Mariana');
      expect(draft.description, isNull);
    });

    test('does not mistake the currency word for the subject', () {
      expect(_parse('gaste veinte mil pesos').description, isNull);
    });

    test('keeps a short phrase whole', () {
      expect(
        _parse('gaste ochenta mil en el mercado del barrio').description,
        'Mercado Del Barrio',
      );
    });
  });

  group('when', () {
    test('defaults to now', () {
      expect(_parse('gaste veinte mil').date, _now);
    });

    test('understands yesterday', () {
      final draft = _parse('ayer gaste treinta mil en el almuerzo');
      expect(draft.date.day, 5);
      expect(draft.date.month, 10);
    });

    test('understands the day before', () {
      expect(_parse('antier pague cincuenta mil').date.day, 4);
    });
  });

  group('how sure', () {
    test('a complete sentence scores well', () {
      final draft = _parse('gaste veinte mil en el almuerzo');
      expect(draft.confidence, greaterThanOrEqualTo(kDraftReviewThreshold));
      expect(draft.warning, isNull);
      expect(draft.isUsable, isTrue);
    });

    test('no amount means the UI has to ask', () {
      final draft = _parse('gaste en el almuerzo');
      expect(draft.amount, isNull);
      expect(draft.isUsable, isFalse);
      expect(draft.warning, isNotNull);
    });

    test('keeps what was said, so a wrong number can be traced', () {
      expect(_parse('gaste veinte mil').rawText, 'gaste veinte mil');
    });
  });

  group('currency', () {
    test('pesos unless dollars are said', () {
      expect(_parse('gaste veinte mil').currency, 'COP');
      expect(_parse('gaste veinte dolares').currency, 'USD');
    });
  });
}
