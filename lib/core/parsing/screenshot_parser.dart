/// Reads a screenshot of a bank app into drafts.
///
/// This is a different problem from a receipt, and the more common one: the
/// quickest way to record something the app missed is to screenshot the
/// movements list. Two shapes turn up.
///
///   * A **list**, where one image holds several movements, each a date, a
///     description and an amount — and where the bottom row is usually cut
///     off by the screen edge.
///   * A **confirmation**, one movement with a headline, a big amount and a
///     label/value table underneath.
///
/// Direction comes from the minus sign, not from the colour. Bancolombia
/// prints "COP -$ 557.000,00" in red and "COP $ 720.000,00" in green, and OCR
/// returns no colour at all — but it does return the sign, which says the
/// same thing and survives a grayscale screenshot.
///
/// A row whose amount was clipped is returned with no amount and a warning.
/// Inferring it from the row above would be inventing a number, and a wrong
/// amount is worse than an empty field the user fills in.
library;

import 'package:budgett_frontend/core/parsing/amount_parser.dart';
import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/parsing/text_normalizer.dart';

/// Spanish and English month names, abbreviated as the apps print them.
const _months = <String, int>{
  'ene': 1,
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'abr': 4,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'ago': 8,
  'aug': 8,
  'sep': 9,
  'set': 9,
  'oct': 10,
  'nov': 11,
  'dic': 12,
  'dec': 12,
};

/// "30 SEPT 2026", "5 oct", "30 de septiembre de 2026".
final _textualDate =
    RegExp(r'^(\d{1,2})\s*(?:de\s+)?([a-zA-Z]{3,10})\.?\s*(?:de\s+)?(\d{4})?$');

/// "2026-10-05", "05/10/2026".
final _numericDate =
    RegExp(r'(\d{4})-(\d{2})-(\d{2})|(\d{1,2})/(\d{1,2})/(\d{2,4})');

/// Buttons, tabs and headings the app draws around the movements. Matched as
/// a prefix, because they are whole lines with nothing worth keeping on them.
final _chrome = RegExp(
    r'^(detalles|movimientos|consultar comprobantes|transferir plata|'
    r'ir a dia a dia|bolsillos|ready|share|listo|compartir|aprobado|approved|'
    r'cuenta de ahorros|cuenta corriente|saldo|disponible|available|'
    r'\d{1,2}:\d{2}|volver|back)\b');

/// Labels in a detail table, which carry their value beside them.
///
/// These must match the WHOLE line. Reading order now joins a label to its
/// value — "Date 2026-10-05 18:43:02" arrives as one line — so dropping
/// anything that merely starts with "Date" threw the date away with it, and
/// a RappiCuenta movement from the 5th was filed on the 6th.
final _detailLabel = RegExp(
    r'^(date|fecha|hora|time|transaction no|numero de transaccion|'
    r'type of transaction|tipo de transaccion|referencia|reference)$');

/// The phone's own status bar, which OCR reads along with everything else.
///
/// The clock already falls out through [_chrome]; the battery does not. A
/// real screenshot came back with a movement of \$100 taken from the "100"
/// beside the battery icon. Anything that is only a short bare number, a
/// percentage or a signal reading is the phone talking about itself.
final _statusBar = RegExp(
    r'^(\d{1,3}\s*%?|\d{1,2}:\d{2}\s*(a\.?m\.?|p\.?m\.?)?|'
    r'[0-9]{1,2}g|lte|wifi|wi-fi)$',
    caseSensitive: false);

/// Words that make a movement a shuffle between the user's own accounts
/// rather than money entering or leaving their finances.
final _ownTransfer =
    RegExp(r'\b(bolsillo|bolsillos|pocket|alcancia|ahorro programado|'
        r'entre cuentas|a mi cuenta|mis cuentas|own account)\b');

/// Reads every movement visible in [text].
///
/// Returns them in the order they appear, so the newest row of a statement
/// comes first — the same order the user is looking at.
List<ExpenseDraft> parseScreenshot(String text, {DateTime? capturedAt}) {
  final at = capturedAt ?? DateTime.now();
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .where((l) => !_chrome.hasMatch(normalizeForMatch(l)))
      .where((l) => !_detailLabel.hasMatch(normalizeForMatch(l)))
      .where((l) => !_statusBar.hasMatch(normalizeForMatch(l)))
      .toList();

  final rows = _splitIntoRows(lines, at);
  if (rows.length >= 2) {
    // A minus on ANY row means this screen marks direction with signs, so a
    // row without one is money arriving. If no row has a sign the app is not
    // using them, and the direction of every row is genuinely unknown —
    // which is worth saying rather than guessing at.
    final usesSigns =
        rows.any((row) => _readSignedAmount(row.lines)?.negative == true);
    return rows.map((row) => _draftFromRow(row, text, at, usesSigns)).toList();
  }

  // One movement, or none that looked like a list: read the whole image as a
  // single confirmation screen.
  final single = _parseConfirmation(lines, text, at);
  return single == null ? const [] : [single];
}

// ─── statement list ──────────────────────────────────────────────────────────

class _Row {
  final DateTime? date;
  final List<String> lines;
  _Row(this.date, this.lines);
}

/// Groups lines into movements, each beginning at a date line.
List<_Row> _splitIntoRows(List<String> lines, DateTime at) {
  final rows = <_Row>[];
  _Row? current;

  for (final line in lines) {
    final date = _readDate(line, at);
    // A date ON ITS OWN starts a row. A date inside a longer line is part of
    // that line's content, not a heading.
    if (date != null && _isDateOnly(line)) {
      current = _Row(date, []);
      rows.add(current);
      continue;
    }
    current?.lines.add(line);
  }
  return rows.where((r) => r.lines.isNotEmpty).toList();
}

ExpenseDraft _draftFromRow(
    _Row row, String rawText, DateTime at, bool usesSigns) {
  final raw = _readSignedAmount(row.lines);
  final amount = raw == null
      ? null
      : _SignedAmount(raw.value, raw.negative ?? (usesSigns ? false : null));
  final description = row.lines
      .firstWhere((l) => findAmount(l) == null, orElse: () => '')
      .trim();

  final kind = _kindFor(
    description: description,
    negative: amount?.negative,
  );

  var confidence = 0.3;
  if (amount != null) confidence += 0.35;
  if (amount?.negative != null) confidence += 0.1;
  if (description.isNotEmpty) confidence += 0.15;
  if (row.date != null) confidence += 0.1;

  return ExpenseDraft(
    source: DraftSource.receipt,
    amount: amount?.value,
    merchant: description.isEmpty ? null : _clean(description),
    kind: kind,
    date: row.date ?? at,
    confidence: confidence.clamp(0.0, 1.0),
    rawText: rawText.trim(),
    warning: amount == null
        ? 'This row was cut off — enter the amount'
        : amount.negative == null
            ? 'Could not tell whether this was money in or out'
            : null,
  );
}

// ─── single confirmation screen ──────────────────────────────────────────────

ExpenseDraft? _parseConfirmation(
    List<String> lines, String rawText, DateTime at) {
  final amount = _readSignedAmount(lines);
  if (amount == null) return null;

  // The headline sits above the amount — "Withdraw from bolsillo" — so the
  // last text line before the figure is the description.
  final amountIndex = lines.indexWhere((l) => findAmount(l) != null);
  // Nequi and DaviPlata put the verb above the figure and the person BELOW
  // it — "Enviaste / \$85.000 / A Laura Morales" — so a name introduced by
  // "a" or "de" after the amount wins over the headline, which would
  // otherwise file every Nequi transfer under the word "Enviaste".
  final below = _counterpartyAfterAmount(lines, amountIndex);

  final headline = below ??
      lines
          .take(amountIndex < 0 ? lines.length : amountIndex)
          .where((l) => findAmount(l) == null)
          .where((l) => l.trim().length > 3)
          .lastOrNull;

  final date = lines
      .map((l) => _readDate(l, at))
      .firstWhere((d) => d != null, orElse: () => null);

  // Decided from the WHOLE screen, not from the name: "Enviaste" sits above
  // the figure and "A Laura Morales" below it, and the name is the better
  // merchant while the verb is the only thing that says which way the money
  // went.
  final kind = _kindFor(
    description: lines.join(' '),
    negative: amount.negative,
  );

  var confidence = 0.4;
  if (headline != null) confidence += 0.2;
  if (date != null) confidence += 0.15;
  if (amount.negative != null) confidence += 0.1;

  return ExpenseDraft(
    source: DraftSource.receipt,
    amount: amount.value,
    merchant: headline == null ? null : _clean(headline),
    kind: kind,
    date: date ?? at,
    confidence: confidence.clamp(0.0, 1.0),
    rawText: rawText.trim(),
  );
}

// ─── shared reading ──────────────────────────────────────────────────────────

class _SignedAmount {
  final double value;

  /// True for money out, false for money in, null when nothing said which.
  final bool? negative;
  const _SignedAmount(this.value, this.negative);
}

/// The movement's amount, with its direction when the sign is visible.
/// Lines whose number identifies something rather than costing something.
/// A Colombian invoice leads with a nine-digit NIT, and a confirmation screen
/// ends with a transaction number.
final _identifierLine = RegExp(
    r'(nit|c\.?c\.?|rut|cedula|resolucion|autorizacion|cufe|'
    r'transaction\s*no|numero\s*de\s*transaccion|referencia|ref|'
    r'telefono|tel|celular|cel|factura|pedido|orden)',
    caseSensitive: false);

_SignedAmount? _readSignedAmount(List<String> lines) {
  for (final line in lines) {
    if (_identifierLine.hasMatch(normalizeForMatch(line))) continue;
    // A date is not an amount. "06 OCT 2026" was being read as 2.026 pesos
    // whenever the screen held one movement, because the single-movement
    // path searches every line and the year is a plausible figure.
    if (_readDate(line, DateTime.now()) != null && _isDateOnly(line)) continue;

    final amount = findAmount(line);
    if (amount == null) continue;
    // On a bank screen every figure that is money says so — "COP", "$",
    // "USD". A bare number is a date, a reference, a card mask or a
    // quantity, and treating one as an amount is how a year became a
    // transaction.
    if (!amount.hasMarker) continue;

    final before = line.substring(0, amount.start);
    // "-$ 557.000" and "- $557.000" both mean out; a dash used as a separator
    // somewhere earlier in the line does not, so only the text immediately
    // before the figure counts.
    final negative = RegExp(r'[-−–]\s*[\$]?\s*$').hasMatch(before)
        ? true
        : RegExp(r'[+]\s*[\$]?\s*$').hasMatch(before)
            ? false
            : null;
    return _SignedAmount(amount.value, negative);
  }
  return null;
}

/// What kind of movement this row is.
///
/// A pocket or sub-account move is a transfer whichever way it points: the
/// money never leaves the user's hands, and recording it as income would
/// inflate every month it happens in.
MessageKind _kindFor({required String description, required bool? negative}) {
  final normalized = normalizeForMatch(description);
  // Checked before everything else: "Withdraw from bolsillo" contains
  // "withdraw", but it is not cash out of a machine, and "Transferencia entre
  // cuentas" is not money leaving the user's finances.
  if (_ownTransfer.hasMatch(normalized)) return MessageKind.internalTransfer;
  // A confirmation screen states the direction in one word above the figure:
  // "Recibiste", "Enviaste". Checked before the sign, because these screens
  // print no sign at all.
  if (RegExp(r'\b(recibiste|recibido|recibida|te\s+enviaron|'
          r'te\s+consignaron|received|deposit)\b')
      .hasMatch(normalized)) {
    return MessageKind.transferIn;
  }
  if (RegExp(r'\b(enviaste|enviado|enviada|pagaste|transferiste|sent)\b')
      .hasMatch(normalized)) {
    return MessageKind.transferOut;
  }
  if (RegExp(r'\b(retiro|withdraw|cajero|atm)\b').hasMatch(normalized)) {
    return MessageKind.withdrawal;
  }
  if (negative == false) return MessageKind.transferIn;
  if (RegExp(r'\b(transferencia|transfer|envio|pse)\b').hasMatch(normalized)) {
    return MessageKind.transferOut;
  }
  return MessageKind.purchase;
}

bool _isDateOnly(String line) {
  final stripped = line
      .replaceAll(_numericDate, '')
      .replaceAll(RegExp(r'\d{1,2}:\d{2}(:\d{2})?'), '')
      .trim();
  if (stripped.isEmpty) return true;
  return _textualDate.hasMatch(line.trim());
}

/// A date written any of the ways a bank app writes one.
DateTime? _readDate(String line, DateTime at) {
  final textual = _textualDate.firstMatch(line.trim());
  if (textual != null) {
    final month = _months[
        normalizeForMatch(textual.group(2)!).substring(0, 3).toLowerCase()];
    if (month != null) {
      final day = int.parse(textual.group(1)!);
      final year = int.tryParse(textual.group(3) ?? '') ?? at.year;
      if (day >= 1 && day <= 31) return DateTime(year, month, day);
    }
  }

  final numeric = _numericDate.firstMatch(line);
  if (numeric != null) {
    try {
      if (numeric.group(1) != null) {
        return DateTime(
          int.parse(numeric.group(1)!),
          int.parse(numeric.group(2)!),
          int.parse(numeric.group(3)!),
        );
      }
      final year = int.parse(numeric.group(6)!);
      return DateTime(
        year < 100 ? 2000 + year : year,
        int.parse(numeric.group(5)!),
        int.parse(numeric.group(4)!),
      );
    } catch (_) {
      return null;
    }
  }
  return null;
}

String _clean(String line) => line
    .replaceAll(RegExp(r'^[^\w]+|[^\w.)]+$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A person or merchant named just below the amount.
///
/// Only a line that is a name: introduced by "a"/"de"/"para"/"to"/"from", or
/// a bare line in capitals that is not a label, a date or an identifier.
String? _counterpartyAfterAmount(List<String> lines, int amountIndex) {
  if (amountIndex < 0) return null;

  for (final line in lines.skip(amountIndex + 1).take(3)) {
    final trimmed = line.trim();
    if (trimmed.length < 3) continue;
    final normalized = normalizeForMatch(trimmed);
    if (_identifierLine.hasMatch(normalized)) continue;
    if (_readDate(trimmed, DateTime.now()) != null) continue;
    if (findAmount(trimmed) != null) continue;

    final introduced = RegExp(r'^(?:a|de|para|hacia|to|from|for)\s+(.{3,})',
            caseSensitive: false)
        .firstMatch(trimmed);
    if (introduced != null) return _clean(introduced.group(1)!);

    // A bare name, in the capitals these screens use for one.
    if (RegExp(r'^[A-Z0-9][A-Z0-9 .,&*\-]{2,}$').hasMatch(trimmed)) {
      return _clean(trimmed);
    }
  }
  return null;
}
