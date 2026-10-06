// Screenshots of bank apps, as ML Kit would return them: the visible lines
// in reading order, with no colour and no layout.
//
// The first two fixtures are transcribed from the real screenshots in
// `Budgett_Backend/res_AI_test/`, down to the clipped bottom row. The rest
// are synthetic variants of the same two shapes.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/parsing/screenshot_parser.dart';

final _captured = DateTime(2026, 10, 6, 13, 15);

// img1.png — Bancolombia "Cuenta de Ahorros / Movimientos". Three rows; the
// third is cut off by the bottom bar, its amount only half drawn.
const _bancolombiaList = '''
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
''';

// img2.jpeg — a RappiCuenta confirmation: money moved out of a pocket and
// into the main account. It never left the user's own money.
const _rappiPocket = '''
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
''';

void main() {
  group('a list of movements', () {
    test('reads every row that is fully visible', () {
      final drafts = parseScreenshot(_bancolombiaList, capturedAt: _captured);
      expect(drafts, hasLength(3));
    });

    test('the minus sign makes it an expense', () {
      final draft =
          parseScreenshot(_bancolombiaList, capturedAt: _captured).first;
      expect(draft.amount, 557000);
      expect(draft.kind, MessageKind.purchase);
      expect(draft.kind.transactionType, 'expense');
      expect(draft.merchant, 'PAGO QR MOTOS GP ITAG');
      expect(draft.date, DateTime(2026, 9, 30));
    });

    test('no minus sign makes it money arriving', () {
      final draft =
          parseScreenshot(_bancolombiaList, capturedAt: _captured)[1];
      expect(draft.amount, 720000);
      expect(draft.kind, MessageKind.transferIn);
      expect(draft.kind.transactionType, 'income');
      expect(draft.date, DateTime(2026, 9, 29));
    });

    test('a clipped row asks for the amount instead of inventing one', () {
      // The third row's figure is half drawn. Carrying the row above down
      // would record 720.000 against Falabella, which is worse than a blank.
      final draft =
          parseScreenshot(_bancolombiaList, capturedAt: _captured)[2];
      expect(draft.merchant, 'PAGO PSE BANCO FALABELLA S A');
      expect(draft.amount, isNull);
      expect(draft.isUsable, isFalse);
      expect(draft.warning, contains('cut off'));
    });

    test('the app chrome is not read as a movement', () {
      final drafts = parseScreenshot(_bancolombiaList, capturedAt: _captured);
      final names = drafts.map((d) => d.merchant).join(' ');
      expect(names, isNot(contains('Bolsillos')));
      expect(names, isNot(contains('Consultar')));
      expect(names, isNot(contains('Movimientos')));
    });

    test('rows come back newest first, as shown', () {
      final drafts = parseScreenshot(_bancolombiaList, capturedAt: _captured);
      expect(drafts.first.date.isAfter(drafts[1].date), isTrue);
    });
  });

  group('a single confirmation screen', () {
    test('reads the amount and the headline', () {
      final drafts = parseScreenshot(_rappiPocket, capturedAt: _captured);
      expect(drafts, hasLength(1));
      expect(drafts.single.amount, 3060000);
      expect(drafts.single.merchant, 'Withdraw from bolsillo');
    });

    test('a pocket move is a transfer, never income', () {
      // The money never left the user's hands. Recording it as income would
      // inflate every month a pocket is emptied.
      final draft =
          parseScreenshot(_rappiPocket, capturedAt: _captured).single;
      expect(draft.kind.transactionType, 'transfer');
    });

    test('reads the date from the detail table', () {
      final draft =
          parseScreenshot(_rappiPocket, capturedAt: _captured).single;
      expect(draft.date, DateTime(2026, 10, 5));
    });

    test('the transaction number is not mistaken for an amount', () {
      final draft =
          parseScreenshot(_rappiPocket, capturedAt: _captured).single;
      expect(draft.amount, isNot(7598344));
    });
  });

  group('other shapes of the same two screens', () {
    test('an explicit plus sign is money arriving', () {
      const text = '''
05 OCT 2026
NOMINA RUNNI SAS
COP +\$ 1.610.834,00
04 OCT 2026
PAGO TARJETA
COP -\$ 250.000,00
''';
      final drafts = parseScreenshot(text, capturedAt: _captured);
      expect(drafts.first.kind, MessageKind.transferIn);
      expect(drafts[1].kind.transactionType, 'expense');
    });

    test('a cash withdrawal is told from a card purchase', () {
      const text = '''
03 OCT 2026
RETIRO CAJERO AUTOMATICO
COP -\$ 300.000,00
02 OCT 2026
COMPRA EXITO ENVIGADO
COP -\$ 85.400,00
''';
      final drafts = parseScreenshot(text, capturedAt: _captured);
      expect(drafts.first.kind, MessageKind.withdrawal);
      expect(drafts[1].kind, MessageKind.purchase);
    });

    test('a numeric date column is read as well as a textual one', () {
      const text = '''
05/10/2026
PAGO QR PANADERIA
COP -\$ 12.000,00
04/10/2026
TRANSFERENCIA RECIBIDA
COP \$ 90.000,00
''';
      final drafts = parseScreenshot(text, capturedAt: _captured);
      expect(drafts.first.date, DateTime(2026, 10, 5));
      expect(drafts[1].date, DateTime(2026, 10, 4));
    });

    test('a date with no year is read against the day of the screenshot', () {
      const text = '''
30 SEPT
PAGO QR MOTOS GP ITAG
COP -\$ 557.000,00
29 SEPT
TRANSFERENCIA CTA SUC VIRTUAL
COP \$ 720.000,00
''';
      final drafts = parseScreenshot(text, capturedAt: _captured);
      expect(drafts.first.date.year, 2026);
      expect(drafts.first.date.month, 9);
    });

    test('a screenshot with nothing readable returns nothing', () {
      expect(parseScreenshot('Movimientos\nBolsillos', capturedAt: _captured),
          isEmpty);
      expect(parseScreenshot('', capturedAt: _captured), isEmpty);
    });

    test('a pocket deposit is a transfer too, not an expense', () {
      const text = '''
RappiCuenta
Deposit to bolsillo
\$500.000
Approved
Date
2026-10-05 09:12:00
Type of transaction
Pocket deposit
''';
      final draft = parseScreenshot(text, capturedAt: _captured).single;
      expect(draft.kind.transactionType, 'transfer');
      expect(draft.amount, 500000);
    });
  });

  group('what the user sees', () {
    test('every draft keeps the text it was read from', () {
      for (final draft
          in parseScreenshot(_bancolombiaList, capturedAt: _captured)) {
        expect(draft.rawText, contains('MOTOS GP ITAG'));
      }
    });

    test('a complete row is confident, a clipped one is not', () {
      final drafts = parseScreenshot(_bancolombiaList, capturedAt: _captured);
      expect(drafts.first.confidence, greaterThan(drafts[2].confidence));
    });
  });
}
