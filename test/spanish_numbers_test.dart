// How a Colombian actually dictates an amount. Speech recognition never
// returns digits for these, so every one of them has to come back as a number
// or dictating an expense is slower than typing it.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/parsing/spanish_numbers.dart';

void main() {
  group('parseSpokenAmount', () {
    test('reads plain thousands', () {
      expect(parseSpokenAmount('veinte mil'), 20000);
      expect(parseSpokenAmount('cincuenta mil'), 50000);
      expect(parseSpokenAmount('cien mil'), 100000);
    });

    test('reads compound figures', () {
      expect(parseSpokenAmount('cuarenta y cinco mil quinientos'), 45500);
      expect(parseSpokenAmount('ciento veinte mil'), 120000);
      expect(parseSpokenAmount('doscientos treinta mil'), 230000);
      expect(parseSpokenAmount('tres mil quinientos'), 3500);
    });

    test('reads millions', () {
      expect(parseSpokenAmount('dos millones'), 2000000);
      expect(parseSpokenAmount('un millon quinientos mil'), 1500000);
    });

    test('reads the slang', () {
      expect(parseSpokenAmount('veinte lucas'), 20000);
      expect(parseSpokenAmount('quince lucas'), 15000);
      expect(parseSpokenAmount('dos palos'), 2000000);
    });

    test('reads digits the recogniser already transcribed', () {
      expect(parseSpokenAmount('45.900'), 45900);
      expect(parseSpokenAmount('20 mil'), 20000);
      expect(parseSpokenAmount('2.500,50'), 2500.50);
    });

    test('skips the words in front of the number', () {
      expect(parseSpokenAmount('gaste veinte mil en el almuerzo'), 20000);
      expect(parseSpokenAmount('pague cuarenta mil de taxi'), 40000);
      expect(parseSpokenAmount('me costo ciento cincuenta mil'), 150000);
    });

    test('stops at the end of the number', () {
      // "dos" belongs to the sentence, not to the amount.
      expect(parseSpokenAmount('treinta mil en dos cafes'), 30000);
    });

    test('a bare figure under a thousand means thousands', () {
      // Nothing in Colombia costs twenty pesos. "Gasté veinte" is 20,000.
      expect(parseSpokenAmount('gaste veinte'), 20000);
      expect(parseSpokenAmount('cincuenta'), 50000);
    });

    test('but transcribed digits are taken at face value', () {
      // Someone who dictated "20.000" said what they meant.
      expect(parseSpokenAmount('20.000'), 20000);
      expect(parseSpokenAmount('950'), 950);
    });

    group('English, which is what the recogniser falls back to', () {
      test('reads the real dictation that came back from the phone', () {
        // Verbatim: an English recogniser transcribing Spanish speech.
        // "to" is "two", and without it this carried no amount at all.
        expect(
          parseSpokenAmount(
              'Mariana Just Send to Hundred Thousand pesos for a rainboardsment o'),
          200000,
        );
      });

      test('a hundred scales what comes before it', () {
        expect(parseSpokenAmount('two hundred thousand'), 200000);
        expect(parseSpokenAmount('three hundred'), 300000);
        expect(parseSpokenAmount('hundred thousand'), 100000);
      });

      test('reads plain English figures', () {
        expect(parseSpokenAmount('fifty thousand'), 50000);
        expect(parseSpokenAmount('twenty thousand pesos'), 20000);
        expect(parseSpokenAmount('two million'), 2000000);
      });

      test('a mishearing only counts in front of a scale word', () {
        // "Send to Mariana" keeps its preposition.
        expect(parseSpokenAmount('i sent to Mariana'), isNull);
        expect(parseSpokenAmount('i paid for a coffee'), isNull);
      });
    });

    test('returns null when nothing is a number', () {
      expect(parseSpokenAmount('almuerzo en el centro'), isNull);
      expect(parseSpokenAmount(''), isNull);
      expect(parseSpokenAmount('y de con'), isNull);
    });

    test('survives accents and punctuation from the recogniser', () {
      expect(parseSpokenAmount('Gasté veintitrés mil, en el almuerzo.'), 23000);
      expect(parseSpokenAmount('TREINTA MIL'), 30000);
    });
  });
}
