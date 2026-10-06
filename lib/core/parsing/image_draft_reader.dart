/// Decides which reading an image gets.
///
/// Kept apart from the provider so the choice is testable without a platform
/// channel: the corpus runs the real dispatch rather than a copy of it.
///
/// A photo of a bank app is far more common than a photo of a paper receipt —
/// the quickest way to record something the app missed is to screenshot the
/// movements list — so the screenshot reading goes first. The other way round
/// a statement list collapses into one wrong total, because a receipt reader
/// looks for the single biggest labelled figure and a list has several.
library;

import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/parsing/receipt_parser.dart';
import 'package:budgett_frontend/core/parsing/screenshot_parser.dart';

/// Marks of a till roll: a total label, or the fiscal furniture a Colombian
/// invoice is required to print.
final _receiptMarks = RegExp(
    r'\b(total\s+a\s+pagar|gran\s+total|subtotal|sub\s+total|'
    r'nit|r[eé]gimen|resoluci[oó]n|factura\s+(de\s+venta|pos|electr)|'
    r'cufe|iva\s+\d|impoconsumo|cambio|efectivo\s+\$)',
    caseSensitive: false);

/// Reads OCR [text] into every movement it holds.
List<ExpenseDraft> readImageText(String text, {DateTime? capturedAt}) {
  if (text.trim().isEmpty) return const [];
  final at = capturedAt ?? DateTime.now();

  // A receipt is read as a receipt even though it also carries a date line.
  // Without this the confirmation-screen reader claims it and returns the
  // first figure on the page, which on a Colombian invoice is the NIT — a
  // nine-digit tax id filed as a nine-hundred-million-peso lunch.
  if (_receiptMarks.hasMatch(text)) {
    final receipt = parseReceipt(text, capturedAt: at);
    if (receipt.isUsable) return [receipt];
  }

  final fromScreen = parseScreenshot(text, capturedAt: at);
  if (fromScreen.any((d) => d.isUsable)) return fromScreen;

  // Nothing that looked like a movements list or a confirmation screen: read
  // it as a till roll instead.
  final receipt = parseReceipt(text, capturedAt: at);
  if (receipt.isUsable) return [receipt];

  // Neither reading found an amount. Prefer whatever did find a name, so the
  // user is filling in one field rather than typing the whole thing.
  if (fromScreen.isNotEmpty) return fromScreen;
  return [receipt];
}
