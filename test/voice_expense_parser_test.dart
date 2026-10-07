// Phrases as they would actually be dictated, in Spanish, with the verb and
// the amount in whatever order they come out.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/parsing/voice_expense_parser.dart';
import 'package:budgett_frontend/data/models/account_model.dart';

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

  _sample();


  group('the sentence the phone actually transcribed', () {
    // Verbatim, once the Spanish pack was installed.
    const spoken =
        'Mariana me envió un pago de un préstamo por \$200,000 a bancolombia';

    ExpenseDraft read() =>
        parseVoiceExpense(spoken, now: _now, accounts: _accounts);

    test('"un" is an article, not the number one', () {
      // It had been read as 1, which then became 1.000 by the
      // under-a-thousand rule, and the scan stopped at the first word.
      expect(read().amount, 200000);
    });

    test('"me envió" is money arriving', () {
      expect(read().kind.transactionType, 'income');
    });

    test('the person is the name and the reason is the description', () {
      final draft = read();
      expect(draft.merchant, 'Mariana');
      expect(draft.description, 'Pago de un prestamo');
    });

    test('the named account is selected', () {
      expect(read().accountId, 'acc-banco');
    });
  });

  group('who is named', () {
    test('a sentence that starts with the verb names nobody', () {
      final draft =
          parseVoiceExpense('me pagaron dos millones', now: _now);
      expect(draft.merchant, isNull);
      expect(draft.amount, 2000000);
    });

    test('a name after the verb still works', () {
      final draft = parseVoiceExpense('le transferi cincuenta mil a Mariana',
          now: _now);
      expect(draft.merchant, 'Mariana');
    });

    test('a spending sentence keeps its description', () {
      final draft =
          parseVoiceExpense('gaste veinte mil en el almuerzo', now: _now);
      expect(draft.merchant, isNull);
      expect(draft.description, 'Almuerzo');
    });
  });

  group('currency', () {
    test('pesos unless dollars are said', () {
      expect(_parse('gaste veinte mil').currency, 'COP');
      expect(_parse('gaste veinte dolares').currency, 'USD');
    });
  });
}

// ─── the real sample ─────────────────────────────────────────────────────────
//
// Budgett_Backend/res_AI_test/audio1.ogg, which has to come out as:
//   Income · 200.000 · "Pago de prestamo Mariana Hernandez" · Bancolombia
//
// The recording itself cannot be transcribed on this machine, so each case
// below is a way the same thing gets said. If the phone transcribes it some
// other way, that wording belongs here as a failing case first.

Account _acct(String id, String name) =>
    Account.fromJson({'id': id, 'name': name, 'type': 'savings', 'balance': 0});

final _accounts = [
  _acct('acc-banco', 'Bancolombia Ahorro'),
  _acct('acc-nu', 'Nu'),
  _acct('acc-cash', 'Efectivo'),
];

void _sample() {
  group('the recorded sample', () {
    ExpenseDraft read(String spoken) =>
        parseVoiceExpense(spoken, now: _now, accounts: _accounts);

    const phrasings = [
      'me pagaron doscientos mil de pago de prestamo Mariana Hernandez a Bancolombia',
      'ingreso de doscientos mil pesos pago de prestamo Mariana Hernandez Bancolombia',
      'recibi doscientos mil por pago de prestamo Mariana Hernandez en Bancolombia',
    ];

    test('reads it as money arriving, however it is phrased', () {
      for (final spoken in phrasings) {
        expect(read(spoken).kind.transactionType, 'income', reason: spoken);
      }
    });

    test('reads the amount', () {
      for (final spoken in phrasings) {
        expect(read(spoken).amount, 200000, reason: spoken);
      }
    });

    test('picks the account that was named', () {
      for (final spoken in phrasings) {
        expect(read(spoken).accountId, 'acc-banco', reason: spoken);
      }
    });

    test('keeps the whole reason, not the first few words', () {
      // "Pago de prestamo Mariana Hernandez" is five words; a four-word cap
      // dropped the surname.
      final merchant = read(phrasings.first).merchant;
      expect(merchant, contains('Prestamo'));
      expect(merchant, contains('Hernandez'));
    });
  });

  group('naming an account out loud', () {
    test('an account nobody named stays blank', () {
      expect(
        parseVoiceExpense('gaste veinte mil en el almuerzo',
                now: _now, accounts: _accounts)
            .accountId,
        isNull,
      );
    });

    test('an ambiguous name is left for the user to pick', () {
      // Two accounts carry "Bancolombia"; guessing puts real money against
      // the wrong balance.
      final ambiguous = [
        _acct('acc-a', 'Bancolombia Ahorro'),
        _acct('acc-b', 'Amex Oro Bancolombia'),
      ];
      expect(
        parseVoiceExpense('gaste veinte mil en Bancolombia',
                now: _now, accounts: ambiguous)
            .accountId,
        isNull,
      );
    });

    test('a generic word does not match an account', () {
      // "Efectivo" as an account name is one thing; "cuenta" is not.
      expect(
        parseVoiceExpense('gaste veinte mil de la cuenta',
                now: _now, accounts: _accounts)
            .accountId,
        isNull,
      );
    });

    test('"en efectivo" picks the Efectivo account', () {
      // Generic as a word, exact as an account name in this app.
      expect(
        parseVoiceExpense('pague veinte mil en efectivo',
                now: _now, accounts: _accounts)
            .accountId,
        'acc-cash',
      );
    });

    test('but "cuenta" still matches nothing', () {
      expect(
        parseVoiceExpense('gaste veinte mil de la cuenta de ahorros',
                now: _now, accounts: _accounts)
            .accountId,
        isNull,
      );
    });

    test('a distinctive name matches', () {
      expect(
        parseVoiceExpense('pague treinta mil con Nu',
                now: _now, accounts: _accounts)
            .accountId,
        'acc-nu',
      );
    });
  });
}
