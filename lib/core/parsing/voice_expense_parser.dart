/// Turns a dictated sentence into a draft expense.
///
/// Built the same way as the message parser and for the same reason: a
/// keyword-and-shape reading beats one regex per phrasing, because people do
/// not say things twice the same way. "Gasté veinte mil en el almuerzo",
/// "almuerzo veinte mil" and "pagué 20.000 de almuerzo" all have to work.
///
/// Spanish first, since that is how this user speaks, with the English verbs
/// alongside so a phone set to English still works.
library;

import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/parsing/spanish_numbers.dart';
import 'package:budgett_frontend/core/parsing/text_normalizer.dart';

/// Verbs that fix the direction of the movement, longest first so "me
/// pagaron" is read before "pague".
const _kindVerbs = <(String, MessageKind)>[
  // Money arriving. These must come first: "me pagaron" contains "pagaron".
  ('me pagaron', MessageKind.transferIn),
  ('me pago', MessageKind.transferIn),
  ('me transfirieron', MessageKind.transferIn),
  ('me consignaron', MessageKind.transferIn),
  ('me enviaron', MessageKind.transferIn),
  ('me llego', MessageKind.transferIn),
  ('me entro', MessageKind.transferIn),
  ('me devolvieron', MessageKind.transferIn),
  ('recibi', MessageKind.transferIn),
  ('cobre', MessageKind.transferIn),
  ('i received', MessageKind.transferIn),
  ('i got paid', MessageKind.transferIn),

  // Money leaving towards a person.
  ('le transferi', MessageKind.transferOut),
  ('le mande', MessageKind.transferOut),
  ('le envie', MessageKind.transferOut),
  ('le preste', MessageKind.transferOut),
  ('transferi', MessageKind.transferOut),
  ('i transferred', MessageKind.transferOut),
  ('i sent', MessageKind.transferOut),

  // Cash out of a machine.
  ('retire', MessageKind.withdrawal),
  ('saque de', MessageKind.withdrawal),
  ('i withdrew', MessageKind.withdrawal),

  // Ordinary spending.
  ('gaste', MessageKind.purchase),
  ('pague', MessageKind.purchase),
  ('compre', MessageKind.purchase),
  ('me costo', MessageKind.purchase),
  ('i spent', MessageKind.purchase),
  ('i paid', MessageKind.purchase),
  ('i bought', MessageKind.purchase),
];

/// Day words, relative to the moment of speaking.
const _dayOffsets = <String, int>{
  'hoy': 0,
  'today': 0,
  'ayer': -1,
  'yesterday': -1,
  'anteayer': -2,
  'antier': -2,
};

/// Introduces what the money was spent on. Ordered so the longer, more
/// specific ones win: "en el" before "en".
const _subjectPrepositions = [
  'en el',
  'en la',
  'en los',
  'en las',
  'de el',
  'del',
  'de la',
  'para el',
  'para la',
  'por el',
  'por la',
  'a la',
  'al',
  'en',
  'de',
  'para',
  'por',
  'a',
  'on',
  'at',
  'for',
  'to',
];

/// Words that never stand alone as what the money was for.
const _subjectStopWords = {
  'pesos', 'peso', 'mil', 'miles', 'millon', 'millones', 'luca', 'lucas',
  'palo', 'palos', 'dolares', 'dolar', 'cop', 'usd', 'plata', 'total',
  'hoy', 'ayer', 'anteayer', 'antier', 'today', 'yesterday',
  'efectivo', 'tarjeta', 'cash', 'card',
};

/// Reads [spoken] into a draft.
///
/// [now] is the moment of speaking, which is what "ayer" is relative to.
ExpenseDraft parseVoiceExpense(String spoken, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final normalized = normalizeForMatch(spoken);

  MessageKind? kind;
  var verbEnd = 0;
  for (final (verb, candidate) in _kindVerbs) {
    final index = normalized.indexOf(verb);
    if (index != -1) {
      kind = candidate;
      verbEnd = index + verb.length;
      break;
    }
  }

  final amount = parseSpokenAmount(spoken);
  final currency = _looksLikeDollars(normalized) ? 'USD' : 'COP';
  final date = _resolveDay(normalized, at);
  final subject = _findSubject(normalized, verbEnd);

  // A verb and an amount is a complete thought; either one missing means the
  // UI has a blank to fill, so say so rather than presenting a tidy draft.
  var confidence = 0.3;
  if (amount != null) confidence += 0.35;
  if (kind != null) confidence += 0.2;
  if (subject != null) confidence += 0.15;

  return ExpenseDraft(
    source: DraftSource.voice,
    amount: amount,
    currency: currency,
    // What someone says out loud is almost always the occasion, not a shop
    // name — "el almuerzo", "el taxi". So it becomes the description, and
    // only a transfer's counterparty is treated as a merchant, since that is
    // a name worth remembering a rule against.
    merchant: kind == MessageKind.transferOut || kind == MessageKind.transferIn
        ? subject
        : null,
    description: kind == MessageKind.transferOut ||
            kind == MessageKind.transferIn
        ? null
        : subject,
    kind: kind ?? MessageKind.purchase,
    date: date,
    confidence: confidence.clamp(0.0, 1.0),
    rawText: spoken.trim(),
    warning: amount == null ? 'No amount heard — enter it below' : null,
  );
}

bool _looksLikeDollars(String normalized) =>
    RegExp(r'\b(dolar|dolares|usd|dollars?)\b').hasMatch(normalized);

DateTime _resolveDay(String normalized, DateTime at) {
  for (final entry in _dayOffsets.entries) {
    if (RegExp('\\b${entry.key}\\b').hasMatch(normalized)) {
      final day = at.add(Duration(days: entry.value));
      return DateTime(day.year, day.month, day.day, at.hour, at.minute);
    }
  }
  return at;
}

/// What the money was for: the words after the preposition that follows the
/// amount.
String? _findSubject(String normalized, int searchFrom) {
  // Start after the number, so "en" inside "veinte" cannot match and the
  // preposition found is the one introducing the subject.
  final amountEnd = _endOfAmount(normalized, searchFrom);
  final tail = amountEnd < normalized.length
      ? normalized.substring(amountEnd)
      : normalized.substring(searchFrom.clamp(0, normalized.length));

  for (final preposition in _subjectPrepositions) {
    final match =
        RegExp('(?:^|\\s)${RegExp.escape(preposition)}\\s+(.+)').firstMatch(tail);
    if (match == null) continue;

    final words = match
        .group(1)!
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .takeWhile((w) => !_subjectStopWords.contains(w))
        .toList();
    if (words.isEmpty) continue;

    // Four words is a phrase, not a label; more than that and the recogniser
    // has run on into the next sentence.
    final subject = words.take(4).join(' ');
    return _titleCase(subject);
  }
  return null;
}

/// Where the spoken amount ends, so the subject search starts past it.
int _endOfAmount(String normalized, int from) {
  final amountWords = RegExp(
      r'\b(cero|un|uno|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|'
      r'once|doce|trece|catorce|quince|dieci\w+|veinti\w+|veinte|treinta|'
      r'cuarenta|cincuenta|sesenta|setenta|ochenta|noventa|cien|ciento|'
      r'\w*cientos|\w*cientas|mil|miles|millon|millones|luca|lucas|palo|palos|'
      r'pesos|peso|dolares|dolar|y|\d[\d.,]*)\b');

  var end = from;
  for (final match in amountWords.allMatches(normalized)) {
    if (match.start < from) continue;
    // Only extend through a contiguous run of number words; a gap means the
    // number finished and this is a later word that happens to match.
    if (match.start > end + 1) break;
    end = match.end;
  }
  return end;
}

String _titleCase(String input) => input
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
