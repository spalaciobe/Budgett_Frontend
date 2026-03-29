import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter/services.dart';

void main() {
  group('CurrencyFormatter.format (es_CO)', () {
    test('formats whole number with dot thousands separator', () {
      final result = CurrencyFormatter.format(1200000);
      // es_CO uses dots for thousands: $1.200.000
      expect(result, contains('1.200.000'));
    });

    test('formats small amount', () {
      final result = CurrencyFormatter.format(5000);
      expect(result, contains('5.000'));
    });

    test('includes $ symbol by default', () {
      final result = CurrencyFormatter.format(1200000);
      expect(result, startsWith('\$'));
    });

    test('omits symbol when includeSymbol=false', () {
      final result = CurrencyFormatter.format(1200000, includeSymbol: false);
      expect(result, isNot(contains('\$')));
    });

    test('zero amount', () {
      final result = CurrencyFormatter.format(0);
      expect(result, contains('0'));
    });

    test('negative amount', () {
      final result = CurrencyFormatter.format(-50000);
      expect(result, contains('50.000'));
    });

    test('large amount', () {
      final result = CurrencyFormatter.format(10000000000);
      expect(result, contains('10.000.000.000'));
    });
  });

  group('CurrencyFormatter.parse (es_CO)', () {
    test('parses plain number string', () {
      expect(CurrencyFormatter.parse('1200000'), 1200000.0);
    });

    test('parses number with dots as thousands separators (es_CO format)', () {
      // After stripping non-digit non-comma chars: "1200000"
      expect(CurrencyFormatter.parse('1.200.000'), 1200000.0);
    });

    test('parses number with comma as decimal separator', () {
      expect(CurrencyFormatter.parse('1.200,50'), closeTo(1200.50, 0.001));
    });

    test('returns 0 for empty string', () {
      expect(CurrencyFormatter.parse(''), 0.0);
    });

    test('returns 0 for non-numeric string', () {
      expect(CurrencyFormatter.parse('abc'), 0.0);
    });

    test('parses zero', () {
      expect(CurrencyFormatter.parse('0'), 0.0);
    });
  });

  group('CurrencyInputFormatter', () {
    final formatter = CurrencyInputFormatter();

    TextEditingValue applyFormat(String text) {
      return formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        TextEditingValue(text: text),
      );
    }

    test('empty input returns empty', () {
      final result = applyFormat('');
      expect(result.text, '');
    });

    test('formats 1000 as 1.000 (es_CO)', () {
      final result = applyFormat('1000');
      expect(result.text, '1.000');
    });

    test('formats 1200000 as 1.200.000', () {
      final result = applyFormat('1200000');
      expect(result.text, '1.200.000');
    });

    test('strips non-digit chars before formatting', () {
      final result = applyFormat('1,200,000');
      // commas are stripped, 1200000 → 1.200.000
      expect(result.text, '1.200.000');
    });

    test('strips dollar sign input', () {
      final result = applyFormat('\$5000');
      expect(result.text, '5.000');
    });

    test('cursor placed at end', () {
      final result = applyFormat('1200000');
      expect(result.selection.baseOffset, result.text.length);
    });

    test('single digit stays as-is', () {
      final result = applyFormat('5');
      expect(result.text, '5');
    });

    test('handles all-non-digit input', () {
      final result = applyFormat('...---');
      expect(result.text, '');
    });
  });
}
