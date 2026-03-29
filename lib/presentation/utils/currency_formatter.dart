import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CurrencyFormatter {
  /// Formats a double value as COP currency with thousands separators.
  /// Output example: $1.200.000 (no decimals by default, as COP doesn't use them)
  static String format(double amount, {int decimalDigits = 0, bool includeSymbol = true}) {
    final formatter = NumberFormat.currency(
      locale: 'es_CO',
      symbol: includeSymbol ? '\$' : '',
      decimalDigits: decimalDigits,
    );
    return formatter.format(amount).trim();
  }

  static double parse(String value) {
    // es_CO uses '.' as thousands separator and ',' as decimal separator
    // Remove thousands separators (dots) and replace decimal comma with dot
    final cleaned = value
        .replaceAll(RegExp(r'[^0-9,]'), '')
        .replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0.0;
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // In COP inputs we work with whole numbers only (no decimal cents)
    // Strip everything except digits
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Format with es_CO thousands separator (dot)
    final formatter = NumberFormat('#,###', 'es_CO');
    final formatted = formatter.format(int.parse(digitsOnly));

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
