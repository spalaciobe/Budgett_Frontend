import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CurrencyFormatter {
  /// Formats [amount] according to [currency].
  ///
  /// COP: es_CO locale, '$' prefix, 0 decimal digits (e.g. $1.200.000)
  /// USD: en_US locale, 'US$' prefix, 2 decimal digits (e.g. US$1,200.50)
  static String format(
    double amount, {
    int? decimalDigits,
    bool includeSymbol = true,
    String currency = 'COP',
  }) {
    if (currency == 'USD') {
      final formatter = NumberFormat.currency(
        locale: 'en_US',
        symbol: includeSymbol ? 'US\$' : '',
        decimalDigits: decimalDigits ?? 2,
      );
      return formatter.format(amount).trim();
    } else {
      // Default: COP
      final formatter = NumberFormat.currency(
        locale: 'es_CO',
        symbol: includeSymbol ? '\$' : '',
        decimalDigits: decimalDigits ?? 0,
      );
      return formatter.format(amount).trim();
    }
  }

  /// Parses a formatted currency string back to a double.
  ///
  /// COP: strips dots (thousands) and replaces commas with dots.
  /// USD: strips commas (thousands), handles dot as decimal separator.
  /// Preserves a leading minus sign so negative balances (e.g. credit-card
  /// debt entered as a negative number) round-trip correctly.
  static double parse(String value, {String currency = 'COP'}) {
    final isNegative = value.startsWith('-');
    if (currency == 'USD') {
      // en_US: ',' is thousands sep, '.' is decimal
      final cleaned = value
          .replaceAll(RegExp(r'[^0-9.]'), '')
          .replaceAll(RegExp(r'\.(?=.*\.)'), ''); // keep only last dot
      final result = double.tryParse(cleaned) ?? 0.0;
      return isNegative ? -result : result;
    } else {
      // es_CO: '.' is thousands sep, ',' is decimal
      final cleaned = value
          .replaceAll(RegExp(r'[^0-9,]'), '')
          .replaceAll(',', '.');
      final result = double.tryParse(cleaned) ?? 0.0;
      return isNegative ? -result : result;
    }
  }

  /// Returns the prefix text for a currency, for use in TextFormField.
  static String prefixFor(String currency) =>
      currency == 'USD' ? 'US\$' : '\$';

  /// Formats a holding quantity with [decimals] significant decimal places,
  /// trimming trailing zeros while keeping at least [minDecimals] decimals.
  ///
  /// Example: formatQuantity(0.00534823) → '0.00534823'
  ///          formatQuantity(10.0)        → '10.00'
  static String formatQuantity(
    double amount, {
    int decimals = 8,
    int minDecimals = 2,
  }) {
    final raw = amount.toStringAsFixed(decimals);
    // Trim trailing zeros after the dot but keep at least minDecimals
    final parts = raw.split('.');
    if (parts.length == 1) return raw;
    final intPart = parts[0];
    String fracPart = parts[1];
    // Remove trailing zeros beyond minDecimals
    while (fracPart.length > minDecimals && fracPart.endsWith('0')) {
      fracPart = fracPart.substring(0, fracPart.length - 1);
    }
    return '$intPart.$fracPart';
  }

  /// Formats [amount] in [currency] prefixed with '≈ ' to signal that the
  /// value was derived from an approximate fx conversion.
  static String formatApprox(double amount, {required String currency}) {
    return '≈ ${format(amount, currency: currency)}';
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  final String currency;

  const CurrencyInputFormatter({this.currency = 'COP'});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return TextEditingValue.empty;
    }

    if (currency == 'USD') {
      return _formatUsd(newValue);
    } else {
      return _formatCop(newValue);
    }
  }

  // COP: whole numbers only, es_CO thousands separator (dot)
  TextEditingValue _formatCop(TextEditingValue value) {
    final isNegative = value.text.startsWith('-');
    final digitsOnly = value.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      final text = isNegative ? '-' : '';
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    final formatter = NumberFormat('#,###', 'es_CO');
    final formatted = (isNegative ? '-' : '') + formatter.format(int.parse(digitsOnly));

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  // USD: up to 2 decimal digits, en_US thousands separator (comma)
  TextEditingValue _formatUsd(TextEditingValue value) {
    final isNegative = value.text.startsWith('-');
    // Allow digits and at most one dot
    String raw = value.text.replaceAll(RegExp(r'[^0-9.]'), '');

    // Preserve at most one decimal point
    final dotIndex = raw.indexOf('.');
    if (dotIndex != -1) {
      final afterDot = raw.substring(dotIndex + 1).replaceAll('.', '');
      final truncated = afterDot.length > 2 ? afterDot.substring(0, 2) : afterDot;
      raw = '${raw.substring(0, dotIndex)}.$truncated';
    }

    if (raw.isEmpty) {
      final text = isNegative ? '-' : '';
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    // Format integer part with en_US thousands separator
    final parts = raw.split('.');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final intValue = int.tryParse(intPart) ?? 0;
    final formatter = NumberFormat('#,###', 'en_US');
    final formattedInt = intValue == 0 && intPart.isEmpty
        ? ''
        : formatter.format(intValue);

    final formatted = (isNegative ? '-' : '') +
        (parts.length > 1 ? '$formattedInt.${parts[1]}' : formattedInt);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
