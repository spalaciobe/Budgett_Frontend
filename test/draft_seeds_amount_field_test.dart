// Seeding the amount field goes through the field's own input formatter,
// which only ever ran on typing. Two ways that bit:
//
//   * straight into the controller, and a seeded amount showed as a bare
//     "3060000" beside every hand-typed "$3.060.000";
//   * with a DOT for the decimals, and the COP formatter — which keeps only
//     digits and commas — silently dropped it, turning a 65.545,94 refund
//     into $6.554.594.
//
// Both are invisible until someone reads the figure, so they are pinned here
// against the real formatter rather than a copy of its rules.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';

/// Exactly what the dialog does when a draft fills it in.
String seed(double amount, {String currency = 'COP'}) {
  var raw = amount % 1 == 0
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  if (currency != 'USD') raw = raw.replaceAll('.', ',');

  return CurrencyInputFormatter(currency: currency)
      .formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: raw,
          selection: TextSelection.collapsed(offset: raw.length),
        ),
      )
      .text;
}

void main() {
  group('a seeded COP amount', () {
    test('keeps its cents instead of inflating a hundredfold', () {
      expect(seed(65545.94), '65.545,94');
    });

    test('groups a whole figure the way the app does everywhere else', () {
      expect(seed(3060000), '3.060.000');
      expect(seed(557000), '557.000');
      expect(seed(20000), '20.000');
    });

    test('survives a small figure', () {
      expect(seed(900), '900');
      expect(seed(10000), '10.000');
    });

    test('round-trips back to the number it came from', () {
      // The real guarantee: what the user sees parses back to what was read.
      for (final amount in [65545.94, 3060000.0, 557000.0, 900.0, 2500.5]) {
        expect(CurrencyFormatter.parse(seed(amount)), closeTo(amount, 0.001),
            reason: '$amount did not survive the round trip');
      }
    });
  });

  group('a seeded USD amount', () {
    test('keeps the dot, which is what that formatter wants', () {
      expect(seed(12.99, currency: 'USD'), contains('12.99'));
    });

    test('round-trips as well', () {
      expect(
        CurrencyFormatter.parse(seed(12.99, currency: 'USD'),
            currency: 'USD'),
        closeTo(12.99, 0.001),
      );
    });
  });
}
