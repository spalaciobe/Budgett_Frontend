/// Amount extraction from Colombian bank messages.
///
/// The hard part is that issuers are inconsistent about separators inside one
/// country: `$45.900,00`, `$45.900`, `COP 1.234.567,89`, `US$10.50`, and
/// occasionally the en_US shape `45,900.00`. [parseAmountToken] resolves the
/// separators from the shape of the token itself instead of assuming a locale.
library;

/// A monetary value found in a message.
class AmountMatch {
  final double value;
  final String currency; // 'COP' | 'USD'

  /// Index in the source string where the match started — lets the caller
  /// extract the merchant from the text that follows the amount.
  final int start;
  final int end;

  const AmountMatch({
    required this.value,
    required this.currency,
    required this.start,
    required this.end,
  });
}

/// Matches an optional currency marker followed by a digit group.
/// Deliberately greedy on separators so `1.234.567,89` is captured whole.
final _amountPattern = RegExp(
  r'(?<marker>US\$|USD|COP|\$)?\s*(?<digits>\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)',
  caseSensitive: false,
);

/// Turns the digit portion of a money token into a double.
///
/// Separator resolution:
///   * both `.` and `,` present → the LAST one is the decimal separator.
///   * only one kind present → it is a decimal separator when it appears once
///     and is followed by 1–2 digits; otherwise every occurrence is a
///     thousands separator (`1.500` is fifteen hundred pesos, not 1.5).
double? parseAmountToken(String token) {
  final digits = token.replaceAll(RegExp(r'[^\d.,]'), '');
  if (digits.isEmpty) return null;

  final lastDot = digits.lastIndexOf('.');
  final lastComma = digits.lastIndexOf(',');

  String cleaned;
  if (lastDot != -1 && lastComma != -1) {
    final decimalSep = lastDot > lastComma ? '.' : ',';
    final groupSep = decimalSep == '.' ? ',' : '.';
    cleaned = digits.replaceAll(groupSep, '').replaceFirst(decimalSep, '.');
  } else if (lastDot != -1 || lastComma != -1) {
    final sep = lastDot != -1 ? '.' : ',';
    final parts = digits.split(sep);
    final tail = parts.last;
    final isDecimal = parts.length == 2 && tail.length <= 2;
    cleaned = isDecimal
        ? '${parts.first}.$tail'
        : digits.replaceAll(sep, '');
  } else {
    cleaned = digits;
  }

  return double.tryParse(cleaned);
}

/// Finds the transaction amount in [text].
///
/// Prefers a value carrying an explicit currency marker (`$`, `COP`, `US$`);
/// among those, the first one wins, because Colombian issuers put the
/// transaction amount before the "saldo disponible" that often follows.
/// Values without a marker are only considered when nothing else matched, and
/// then only if they look like money (≥ 100, or fractional).
AmountMatch? findAmount(String text) {
  final marked = <AmountMatch>[];
  final bare = <AmountMatch>[];

  for (final m in _amountPattern.allMatches(text)) {
    final value = parseAmountToken(m.namedGroup('digits')!);
    if (value == null || value <= 0) continue;

    final marker = m.namedGroup('marker')?.toUpperCase();
    final currency =
        (marker == 'US\$' || marker == 'USD') ? 'USD' : 'COP';
    final match = AmountMatch(
      value: value,
      currency: currency,
      start: m.start,
      end: m.end,
    );

    if (marker != null) {
      marked.add(match);
    } else if (_isPlausibleBareAmount(m.namedGroup('digits')!, value)) {
      bare.add(match);
    }
  }

  if (marked.isNotEmpty) return marked.first;
  if (bare.isNotEmpty) return bare.first;
  return null;
}

/// Whether a number with no currency marker can be read as an amount.
///
/// Bank messages are full of digit runs that are not money: support lines
/// (`018000931987`), reference numbers, account numbers. A bare number only
/// counts when it is in a plausible range and is not a long unbroken run.
bool _isPlausibleBareAmount(String digits, double value) {
  if (value != value.roundToDouble()) return true; // has decimals
  if (value < 100) return false;
  if (value >= 1e9) return false; // beyond any purchase alert
  final digitCount = digits.replaceAll(RegExp(r'[^\d]'), '').length;
  return digitCount <= 9;
}

/// Currency inferred from wording when no symbol is attached to the number.
String inferCurrency(String normalizedText) {
  if (normalizedText.contains('dolar') ||
      normalizedText.contains('usd') ||
      normalizedText.contains('us\$')) {
    return 'USD';
  }
  return 'COP';
}
