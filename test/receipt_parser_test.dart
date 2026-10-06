// Receipts in the shape Colombian shops print them, as OCR would return
// them: lines in reading order, nothing else.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/parsing/receipt_parser.dart';

final _captured = DateTime(2026, 10, 6, 19, 5);

// A real invoice email from this user's inbox, reshaped as a receipt photo.
const _llamita = '''
LA LLAMITA S.A.S.
Nit 901377511-9
CR 48 32 B SUR 139 LC 403
Tel 3016042484
Factura de Venta MN 12279
Fecha: 05/10/2026 14:23
2 x Almuerzo ejecutivo      \$36.000
1 x Jugo natural            \$ 6.500
SUBTOTAL                    \$42.500
IVA 8%                      \$ 3.400
TOTAL A PAGAR               \$45.900
EFECTIVO                    \$50.000
CAMBIO                      \$ 4.100
Gracias por su compra
''';

const _supermarket = '''
D1 SABANETA
NIT 900.123.456-7
CALLE 75 SUR 45-12
Leche entera 1L          4.800
Pan tajado               3.200
Huevos AA x12           12.700
TOTAL                   20.700
''';

// Thermal print where the total label did not survive the camera.
const _noTotalLabel = '''
PANADERIA EL TRIGAL
Croissant        3.500
Cafe americano   4.200
                 7.700
''';

void main() {
  group('the total', () {
    test('reads the labelled total, not the subtotal', () {
      final draft = parseReceipt(_llamita, capturedAt: _captured);
      expect(draft.amount, 45900);
      expect(draft.warning, isNull);
    });

    test('ignores the cash tendered, which is bigger than the bill', () {
      // 50.000 is the largest figure on the receipt and is not the total.
      final draft = parseReceipt(_llamita, capturedAt: _captured);
      expect(draft.amount, isNot(50000));
    });

    test('reads a bare TOTAL line', () {
      expect(parseReceipt(_supermarket, capturedAt: _captured).amount, 20700);
    });

    test('falls back to the largest figure and says so', () {
      final draft = parseReceipt(_noTotalLabel, capturedAt: _captured);
      expect(draft.amount, 7700);
      expect(draft.warning, contains('largest'));
    });

    test('a receipt with no figures asks for the amount', () {
      final draft = parseReceipt('TIENDA\nGracias', capturedAt: _captured);
      expect(draft.amount, isNull);
      expect(draft.isUsable, isFalse);
      expect(draft.warning, contains('enter the amount'));
    });
  });

  group('the merchant', () {
    test('prefers the line carrying the company suffix', () {
      expect(
        parseReceipt(_llamita, capturedAt: _captured).merchant,
        'LA LLAMITA S.A.S.',
      );
    });

    test('takes the top line when there is no suffix', () {
      expect(
        parseReceipt(_supermarket, capturedAt: _captured).merchant,
        'D1 SABANETA',
      );
    });

    test('skips the NIT, the address and the phone', () {
      const headedByNit = '''
NIT 900.123.456-7
CALLE 10 # 43-21
Tel 3001234567
CAFE QUINDIO
TOTAL 12.000
''';
      expect(
        parseReceipt(headedByNit, capturedAt: _captured).merchant,
        'CAFE QUINDIO',
      );
    });
  });

  group('the date', () {
    test('reads the receipt own date', () {
      final draft = parseReceipt(_llamita, capturedAt: _captured);
      expect(draft.date.year, 2026);
      expect(draft.date.month, 10);
      expect(draft.date.day, 5);
    });

    test('falls back to when the photo was taken', () {
      final draft = parseReceipt(_supermarket, capturedAt: _captured);
      expect(draft.date, _captured);
    });
  });

  group('how sure', () {
    test('a complete receipt reads as usable', () {
      final draft = parseReceipt(_llamita, capturedAt: _captured);
      expect(draft.isUsable, isTrue);
      expect(draft.confidence, greaterThan(0.8));
    });

    test('an unlabelled total scores lower than a labelled one', () {
      final labelled = parseReceipt(_supermarket, capturedAt: _captured);
      final guessed = parseReceipt(_noTotalLabel, capturedAt: _captured);
      expect(guessed.confidence, lessThan(labelled.confidence));
    });

    test('keeps the text it read, so a wrong number can be traced', () {
      final draft = parseReceipt(_supermarket, capturedAt: _captured);
      expect(draft.rawText, contains('D1 SABANETA'));
    });
  });
}
