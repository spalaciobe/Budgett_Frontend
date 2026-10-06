/// Reads a photographed receipt into a draft expense.
///
/// Works on whatever the on-device OCR returns, which is lines of text in
/// roughly reading order with no structure attached. Three things have to
/// come out of that: who was paid, how much, and when.
///
/// The total is the hard one. A Colombian receipt prints several figures that
/// all look like money — unit prices, SUBTOTAL, IVA, "CAMBIO", "EFECTIVO" —
/// and picking the largest is wrong, because the cash tendered is usually
/// bigger than the bill. So the label is read, not the size.
library;

import 'package:budgett_frontend/core/parsing/amount_parser.dart';
import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/parsing/expense_message_parser.dart';
import 'package:budgett_frontend/core/parsing/text_normalizer.dart';

/// Total labels, best first. "A pagar" beats a bare "total" because a receipt
/// that prints both means the second one.
const _totalLabels = [
  'total a pagar',
  'total pagado',
  'valor a pagar',
  'neto a pagar',
  'total factura',
  'total venta',
  'importe total',
  'gran total',
  'total',
  'amount due',
  'grand total',
];

/// Labels whose figure is never the bill, however much it looks like one.
const _notTheTotal = [
  'subtotal',
  'sub total',
  'base gravable',
  'iva',
  'impoconsumo',
  'propina',
  'descuento',
  'cambio',
  'su cambio',
  'vueltas',
  'efectivo',
  'recibido',
  'entregado',
  'change',
  'cash',
  'tendered',
];

/// Suffixes that mark a line as a company name rather than an address.
final _companySuffix = RegExp(
    r'\b(s\.?a\.?s\.?|ltda|s\.?a\.?|e\.?u\.?|s\.?c\.?a\.?|'
    r'inc|llc|corp|co)\b\.?$');

/// Lines at the top that are never the merchant.
final _notAName = RegExp(
    r'^(nit|c\.?c\.?|rut|tel|telefono|cel|celular|direccion|dir|calle|cra|'
    r'carrera|avenida|av|diagonal|transversal|factura|recibo|resolucion|'
    r'regimen|fecha|hora|caja|cajero|mesa|orden|ticket|www\.|http)',
    caseSensitive: false);

/// Reads OCR [text] from a receipt into a draft.
///
/// [capturedAt] is when the photo was taken, used when the receipt's own date
/// is unreadable — which is common, since the date is often the faintest
/// print on a thermal receipt.
ExpenseDraft parseReceipt(String text, {DateTime? capturedAt}) {
  final at = capturedAt ?? DateTime.now();
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final total = _findTotal(lines);
  final merchant = _findMerchant(lines);
  final date = findOccurredAt(text, at) ?? at;

  var confidence = 0.25;
  if (total != null) confidence += 0.35;
  // A labelled total is the difference between reading the receipt and
  // guessing at it.
  if (total != null && total.labelled) confidence += 0.15;
  if (merchant != null) confidence += 0.2;

  return ExpenseDraft(
    source: DraftSource.receipt,
    amount: total?.value,
    merchant: merchant,
    date: date,
    confidence: confidence.clamp(0.0, 1.0),
    rawText: text.trim(),
    warning: total == null
        ? 'No total found — enter the amount below'
        : total.labelled
            ? null
            : 'No total line found; using the largest amount on the receipt',
  );
}

class _Total {
  final double value;

  /// True when the figure came from a line that said what it was.
  final bool labelled;

  const _Total(this.value, {required this.labelled});
}

_Total? _findTotal(List<String> lines) {
  // A label and its figure are usually on one line, but a narrow receipt
  // wraps them, so the next line is checked too.
  for (final label in _totalLabels) {
    for (var i = 0; i < lines.length; i++) {
      final normalized = normalizeForMatch(lines[i]);
      if (!normalized.contains(label)) continue;
      if (_notTheTotal.any((bad) => normalized.contains(bad))) continue;

      final onThisLine = findAmount(lines[i]);
      if (onThisLine != null) {
        return _Total(onThisLine.value, labelled: true);
      }
      if (i + 1 < lines.length) {
        final onNext = findAmount(lines[i + 1]);
        if (onNext != null) return _Total(onNext.value, labelled: true);
      }
    }
  }

  // Nothing said "total". The largest figure is the usual fallback, but only
  // after dropping the lines that are known not to be the bill — without that
  // the cash handed over wins on almost every receipt.
  double? largest;
  for (final line in lines) {
    final normalized = normalizeForMatch(line);
    if (_notTheTotal.any((bad) => normalized.contains(bad))) continue;
    final amount = findAmount(line);
    if (amount == null) continue;
    if (largest == null || amount.value > largest) largest = amount.value;
  }
  return largest == null ? null : _Total(largest, labelled: false);
}

/// The merchant, taken from the top of the receipt.
///
/// A company suffix anywhere in the first lines is decisive. Otherwise the
/// first line that is not an address, a phone number or a document heading is
/// as good as it gets — which is right far more often than not, because a
/// receipt leads with the shop's name.
String? _findMerchant(List<String> lines) {
  final head = lines.take(8).toList();

  for (final line in head) {
    if (_notAName.hasMatch(normalizeForMatch(line))) continue;
    if (_companySuffix.hasMatch(normalizeForMatch(line))) return _clean(line);
  }

  for (final line in head) {
    final normalized = normalizeForMatch(line);
    if (_notAName.hasMatch(normalized)) continue;
    // A line that is mostly digits is a NIT, a phone or a barcode.
    final letters = normalized.replaceAll(RegExp(r'[^a-z]'), '').length;
    if (letters < 3) continue;
    if (letters < normalized.replaceAll(RegExp(r'[^0-9]'), '').length) {
      continue;
    }
    return _clean(line);
  }
  return null;
}

/// Trims the punctuation OCR leaves on the ends without touching the name.
String _clean(String line) => line
    .replaceAll(RegExp(r'^[^\w]+|[^\w.]+$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
