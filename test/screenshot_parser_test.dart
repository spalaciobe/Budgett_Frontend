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

  group('what the camera really returns', () {
    // Lifted off the device rather than typed by eye. Reading order now
    // joins a label to its value, which is what the parser has to cope with.
    const realImg1 = '''
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
''';

    test('reads all three rows out of the real text', () {
      final drafts = parseScreenshot(realImg1, capturedAt: _captured);
      expect(drafts, hasLength(3));
      expect(drafts[0].amount, 557000);
      expect(drafts[1].amount, 720000);
      expect(drafts[2].amount, isNull);
    });

    test('"cOP" and ",oo" do not change the figure', () {
      // OCR reads the capital O as a lowercase c and the zeros as letters.
      final drafts = parseScreenshot(realImg1, capturedAt: _captured);
      expect(drafts[1].amount, 720000);
      expect(drafts[1].kind.transactionType, 'income');
    });

    test('a detail label keeps the value beside it', () {
      // Joining a row put "Date" and its value on one line. Dropping
      // anything starting with "Date" threw the date away, and a
      // RappiCuenta movement from the 5th was filed on the 6th.
      const confirmation = '''
RappiCuenta
Withdraw from bolsillo
\$3.060.000
Approved
Date 2026-10-05 18:43:02
Type of transaction Pocket withdrawal
Transaction No 7598344
''';
      final draft = parseScreenshot(confirmation, capturedAt: _captured).single;
      expect(draft.date, DateTime(2026, 10, 5));
      expect(draft.amount, 3060000);
      expect(draft.kind.transactionType, 'transfer');
    });

    test('a bare label on its own line is still dropped', () {
      const split = '''
RappiCuenta
Deposit to bolsillo
\$500.000
Date
2026-10-04 09:00:00
Transaction No
123456
''';
      final draft = parseScreenshot(split, capturedAt: _captured).single;
      expect(draft.date, DateTime(2026, 10, 4));
      expect(draft.amount, 500000);
    });
  });

  group('what the status bar contributes', () {
    test('the battery reading is not a movement', () {
      // A real run filed a \$100 movement taken from the "100" beside the
      // battery icon. The clock already fell out; the battery did not.
      const withStatusBar = '''
15:13
100
30 SEPT 2026
PAGO QR MOTOS GP ITAG
COP -\$ 557.000,00
29 SEPT 2026
TRANSFERENCIA CTA SUC VIRTUAL
COP \$ 720.000,00
''';
      final drafts = parseScreenshot(withStatusBar, capturedAt: _captured);
      expect(drafts, hasLength(2));
      expect(drafts.map((d) => d.amount), isNot(contains(100)));
      expect(drafts.first.amount, 557000);
      expect(drafts[1].amount, 720000);
    });

    test('a percentage or a signal reading is dropped too', () {
      const noisy = '''
96 %
5G
04 OCT 2026
COMPRA EXITO
COP -\$ 85.400,00
03 OCT 2026
NOMINA
COP \$ 900.000,00
''';
      final drafts = parseScreenshot(noisy, capturedAt: _captured);
      expect(drafts, hasLength(2));
      expect(drafts.first.amount, 85400);
    });

    test('a real three-digit amount still survives', () {
      // The guard must not eat a genuine figure that carries a marker.
      const small = '''
05 OCT 2026
PARQUEADERO
COP -\$ 900,00
04 OCT 2026
PROPINA
COP -\$ 500,00
''';
      final drafts = parseScreenshot(small, capturedAt: _captured);
      expect(drafts.first.amount, 900);
      expect(drafts[1].amount, 500);
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
