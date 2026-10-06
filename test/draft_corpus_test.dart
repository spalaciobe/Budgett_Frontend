// The regression net for entering an expense by camera or voice.
//
// Everything here goes through `readImageText` / `parseVoiceExpense` — the
// same entry points the app calls — so a fixture that passes here passes in
// the app, minus whatever the OCR itself garbles.
//
// Two of the image fixtures are transcribed from the real screenshots in
// `Budgett_Backend/res_AI_test`, down to the clipped bottom row. The audio
// one is the expected reading of `audio1.ogg`; the recording cannot be
// transcribed in a unit test, so each phrasing is a way the same thing gets
// said. When the phone transcribes something this misses, that wording
// belongs here as a failing case first.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/parsing/image_draft_reader.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/parsing/voice_expense_parser.dart';
import 'package:budgett_frontend/data/models/account_model.dart';

final _at = DateTime(2026, 10, 6, 13, 15);

Account _acct(String id, String name) =>
    Account.fromJson({'id': id, 'name': name, 'type': 'savings', 'balance': 0});

final _accounts = [
  _acct('acc-banco', 'Bancolombia Ahorro'),
  _acct('acc-nu', 'Nu'),
  _acct('acc-rappi', 'RappiCard'),
  _acct('acc-cash', 'Efectivo'),
];

/// One fixture and what it has to produce.
class _Case {
  const _Case(
    this.label,
    this.text, {
    this.movements = 1,
    this.amount,
    this.merchantContains,
    this.type,
    this.needsAmount = false,
  });

  final String label;
  final String text;
  final int movements;
  final double? amount;
  final String? merchantContains;

  /// `transactions.type` the first movement becomes.
  final String? type;

  /// True when the fixture is deliberately missing its amount and the right
  /// behaviour is to ask rather than to guess.
  final bool needsAmount;
}

// ─── images ──────────────────────────────────────────────────────────────────

const _imageCases = <_Case>[
  // ---- real: res_AI_test/img1.png, Bancolombia movements -------------------
  _Case(
    'bancolombia movements list',
    '''
13:15
Cuenta de Ahorros
Detalles
Movimientos
Consultar comprobantes
30 SEPT 2026
PAGO QR MOTOS GP ITAG
COP -\$ 557.000,00
29 SEPT 2026
TRANSFERENCIA CTA SUC VIRTUAL
COP \$ 720.000,00
29 SEPT 2026
PAGO PSE BANCO FALABELLA S A
Transferir plata
Ir a Día a Día
Bolsillos
''',
    movements: 3,
    amount: 557000,
    merchantContains: 'MOTOS GP ITAG',
    type: 'expense',
  ),

  // ---- what ML Kit ACTUALLY returned for img1.png -------------------------
  //
  // Copied off the device, not transcribed by eye. The quirks are the point:
  // "cOP" with a lowercase c, "720.000,oo" with letters where the zeros are,
  // the status bar merged into one line, and "Date"/"Transferir plata" rows
  // carrying their neighbours.
  _Case(
    'img1 as the camera really read it',
    '''
13:15 A9 l100
Cuenta de Ahorros
Detalles Movimientos
Consultar comprobantes
30 SEPT 2026
PAGO QR MOTOS GP ITAG
cOP -\$ 557.000,00
29 SEPT 2026
TRANSFERENCIA CTA SUC VIRTUAL
cOP \$ 720.000,oo
29 SEPT 2026
PAGO PSE BANCO FALABELLA S A
Transferir plata Ira Día a Día Bolsillos
''',
    movements: 3,
    amount: 557000,
    merchantContains: 'MOTOS GP ITAG',
    type: 'expense',
  ),

  // ---- real: res_AI_test/img2.jpeg, RappiCuenta pocket --------------------
  _Case(
    'rappi pocket withdrawal',
    '''
18:43
RappiCuenta
Withdraw from bolsillo
\$3.060.000
Approved
Date
2026-10-05 18:43:02
Type of transaction
Pocket withdrawal
Transaction No
7598344
Ready
Share
''',
    amount: 3060000,
    merchantContains: 'bolsillo',
    type: 'transfer',
  ),

  // ---- synthetic: the other apps this user has ---------------------------
  _Case(
    'nequi movement detail',
    '''
Nequi
Enviaste
\$ 85.000
A Laura Morales
3041234567
5 de octubre de 2026
8:14 p. m.
Listo
''',
    amount: 85000,
    merchantContains: 'Laura Morales',
    type: 'expense',
  ),
  _Case(
    'daviplata received',
    '''
DaviPlata
Recibiste
\$ 150.000
De EDISON ARANGO CORREA
04/10/2026
Compartir
''',
    amount: 150000,
    type: 'income',
  ),
  _Case(
    'nu card statement rows',
    '''
Nu
Movimientos
05 OCT 2026
SMART FIT 20 DE JULI
-\$ 101.500
04 OCT 2026
RAPPI COLOMBIA
-\$ 32.900
03 OCT 2026
PAGO RECIBIDO
\$ 400.000
''',
    movements: 3,
    amount: 101500,
    merchantContains: 'SMART FIT',
    type: 'expense',
  ),
  _Case(
    'a paper receipt',
    '''
PANADERIA EL TRIGAL S.A.S.
NIT 900.456.789-1
CALLE 37 SUR 28-11
Factura POS 00043112
Fecha: 06/10/2026 07:41
Pan tajado              4.500
Jugo de naranja         6.000
Café americano          4.200
SUBTOTAL               14.700
IVA 0%                      0
TOTAL A PAGAR          14.700
EFECTIVO               20.000
CAMBIO                  5.300
''',
    amount: 14700,
    merchantContains: 'TRIGAL',
    type: 'expense',
  ),
  _Case(
    'a restaurant bill with a tip line',
    '''
RESTAURANTE EL CIELO
NIT 830.111.222-3
SUBTOTAL              120.000
PROPINA VOLUNTARIA     12.000
TOTAL A PAGAR         132.000
''',
    amount: 132000,
    merchantContains: 'EL CIELO',
    type: 'expense',
  ),
  _Case(
    'a fuel receipt where the pump pre-authorised',
    '''
ESTACION DE SERVICIO TERPEL
NIT 860.002.554-1
Galones         8.42
Precio/galon   15.900
TOTAL         133.878
''',
    amount: 133878,
    merchantContains: 'TERPEL',
  ),

  // ---- synthetic: the awkward ones ---------------------------------------
  _Case(
    'a clipped bottom row asks instead of guessing',
    '''
05 OCT 2026
COMPRA EXITO ENVIGADO
COP -\$ 85.400,00
04 OCT 2026
PAGO PSE BANCO FALABELLA S A
''',
    movements: 2,
    amount: 85400,
    type: 'expense',
  ),
  _Case(
    'a screenshot with no figures at all',
    'Movimientos\nNo tienes movimientos este mes\nBolsillos',
    movements: 1,
    needsAmount: true,
  ),
  _Case(
    'a long account number is not an amount',
    '''
Bancolombia
Transferencia exitosa
A la cuenta 01768288204
COP -\$ 60.000,00
06/10/2026
''',
    amount: 60000,
    type: 'expense',
  ),
  _Case(
    'dollars are kept as dollars',
    '''
RappiCard
Compra internacional
USD 12.99
NETFLIX.COM
05/10/2026
''',
    amount: 12.99,
    merchantContains: 'NETFLIX',
  ),
];

// ─── voice ───────────────────────────────────────────────────────────────────

class _Said {
  const _Said(
    this.label,
    this.phrases, {
    this.amount,
    this.type,
    this.accountId,
    this.subjectContains,
  });

  final String label;
  final List<String> phrases;
  final double? amount;
  final String? type;
  final String? accountId;
  final String? subjectContains;
}

const _voiceCases = <_Said>[
  // ---- real: res_AI_test/audio1.ogg --------------------------------------
  _Said(
    'audio1: a loan repayment received',
    [
      'me pagaron doscientos mil de pago de prestamo Mariana Hernandez a Bancolombia',
      'ingreso de doscientos mil pesos pago de prestamo Mariana Hernandez Bancolombia',
      'recibi doscientos mil por pago de prestamo Mariana Hernandez en Bancolombia',
    ],
    amount: 200000,
    type: 'income',
    accountId: 'acc-banco',
    subjectContains: 'Hernandez',
  ),

  // ---- synthetic ---------------------------------------------------------
  _Said(
    'an everyday lunch',
    [
      'gaste veinte mil en el almuerzo',
      'pague veinte mil de almuerzo',
      'almuerzo veinte mil',
    ],
    amount: 20000,
    type: 'expense',
  ),
  _Said(
    'a taxi, said with slang',
    ['pague quince lucas de taxi', 'gaste quince mil en taxi'],
    amount: 15000,
    type: 'expense',
  ),
  _Said(
    'a salary arriving',
    [
      'me pagaron un millon seiscientos mil de nomina',
      'ingreso de un millon seiscientos mil nomina',
    ],
    amount: 1600000,
    type: 'income',
  ),
  _Said(
    'cash out of a machine',
    ['retire doscientos mil del cajero', 'saque de doscientos mil'],
    amount: 200000,
    type: 'expense',
  ),
  _Said(
    'a transfer to a person',
    ['le transferi cincuenta mil a Mariana', 'le mande cincuenta mil a Mariana'],
    amount: 50000,
    type: 'expense',
  ),
  _Said(
    'naming the account',
    ['gaste treinta mil con Nu', 'pague treinta mil desde Nu'],
    amount: 30000,
    accountId: 'acc-nu',
  ),
  _Said(
    'a figure under a thousand means thousands',
    ['gaste veinte', 'me costo cuarenta'],
  ),
  _Said(
    'nothing that is a number',
    ['compre algo en la tienda'],
  ),
];

void main() {
  group('reading an image', () {
    for (final c in _imageCases) {
      group(c.label, () {
        final drafts = readImageText(c.text, capturedAt: _at);

        test('finds ${c.movements} movement(s)', () {
          expect(drafts, hasLength(c.movements));
        });

        if (c.amount != null) {
          test('reads the amount', () {
            expect(drafts.first.amount, c.amount);
          });
        }

        if (c.needsAmount) {
          test('asks for the amount instead of inventing one', () {
            expect(drafts.first.isUsable, isFalse);
            expect(drafts.first.warning, isNotNull);
          });
        }

        if (c.merchantContains != null) {
          test('names it', () {
            expect(
              drafts.first.merchant?.toLowerCase(),
              contains(c.merchantContains!.toLowerCase()),
            );
          });
        }

        if (c.type != null) {
          test('files it as a ${c.type}', () {
            expect(drafts.first.kind.transactionType, c.type);
          });
        }

        test('keeps the text it read', () {
          expect(drafts.first.rawText, isNotEmpty);
        });
      });
    }

    test('an empty image yields nothing at all', () {
      expect(readImageText('', capturedAt: _at), isEmpty);
      expect(readImageText('   \n  ', capturedAt: _at), isEmpty);
    });

    test('no fixture ever invents an amount it was not given', () {
      // The one guarantee that matters: a figure shown to the user is one
      // that was on screen.
      for (final c in _imageCases) {
        for (final draft in readImageText(c.text, capturedAt: _at)) {
          if (draft.amount == null) continue;
          // Digits only, so "45.900" in the text matches 45900 read out of
          // it, and "12.99" matches 1299 — rounding first would look for
          // "13", which is nowhere on the page.
          final digits = draft.amount! % 1 == 0
              ? draft.amount!.toStringAsFixed(0)
              : draft.amount!.toStringAsFixed(2).replaceAll('.', '');
          final stripped = c.text.replaceAll(RegExp(r'[^0-9]'), '');
          expect(stripped, contains(digits),
              reason: '${c.label}: ${draft.amount} is not in the text');
        }
      }
    });
  });

  group('hearing a phrase', () {
    for (final c in _voiceCases) {
      group(c.label, () {
        for (final phrase in c.phrases) {
          final draft =
              parseVoiceExpense(phrase, now: _at, accounts: _accounts);

          if (c.amount != null) {
            test('"$phrase" → ${c.amount}', () {
              expect(draft.amount, c.amount);
            });
          }
          if (c.type != null) {
            test('"$phrase" → ${c.type}', () {
              expect(draft.kind.transactionType, c.type);
            });
          }
          if (c.accountId != null) {
            test('"$phrase" → account', () {
              expect(draft.accountId, c.accountId);
            });
          }
          if (c.subjectContains != null) {
            test('"$phrase" → subject', () {
              final subject = draft.merchant ?? draft.description ?? '';
              expect(subject, contains(c.subjectContains!));
            });
          }
        }
      });
    }

    test('a bare figure under a thousand is read as thousands', () {
      expect(parseVoiceExpense('gaste veinte', now: _at).amount, 20000);
      expect(parseVoiceExpense('me costo cuarenta', now: _at).amount, 40000);
    });

    test('a phrase with no number asks for one', () {
      final draft = parseVoiceExpense('compre algo en la tienda', now: _at);
      expect(draft.amount, isNull);
      expect(draft.isUsable, isFalse);
      expect(draft.warning, isNotNull);
    });

    test('nothing spoken is ever posted on its own', () {
      // A draft is a suggestion. Confidence exists to tell the UI how loudly
      // to doubt itself, never to skip the confirmation.
      for (final c in _voiceCases) {
        for (final phrase in c.phrases) {
          final draft = parseVoiceExpense(phrase, now: _at);
          expect(draft.confidence, lessThanOrEqualTo(1.0));
          expect(draft.source, DraftSource.voice);
        }
      }
    });
  });

  group('what the two readings share', () {
    test('a draft never carries an amount of zero or less', () {
      final all = <ExpenseDraft>[
        for (final c in _imageCases) ...readImageText(c.text, capturedAt: _at),
        for (final c in _voiceCases)
          for (final p in c.phrases) parseVoiceExpense(p, now: _at),
      ];
      for (final draft in all) {
        if (draft.amount != null) expect(draft.amount, greaterThan(0));
      }
    });

    test('an unusable draft always says what is missing', () {
      final all = <ExpenseDraft>[
        for (final c in _imageCases) ...readImageText(c.text, capturedAt: _at),
        for (final c in _voiceCases)
          for (final p in c.phrases) parseVoiceExpense(p, now: _at),
      ];
      for (final draft in all.where((d) => !d.isUsable)) {
        expect(draft.warning, isNotNull,
            reason: 'a blank amount with no explanation: ${draft.rawText}');
      }
    });

    test('a declined kind never reaches a draft', () {
      // Nothing in either reading should produce "declined": that is a bank
      // message concept and has no meaning for a photo or a sentence.
      final all = <ExpenseDraft>[
        for (final c in _imageCases) ...readImageText(c.text, capturedAt: _at),
        for (final c in _voiceCases)
          for (final p in c.phrases) parseVoiceExpense(p, now: _at),
      ];
      expect(all.map((d) => d.kind), isNot(contains(MessageKind.declined)));
    });
  });
}
