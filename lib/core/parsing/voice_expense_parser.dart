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
import 'package:budgett_frontend/core/parsing/spoken_account_match.dart';
import 'package:budgett_frontend/core/parsing/text_normalizer.dart';
import 'package:budgett_frontend/data/models/account_model.dart';

/// Verbs that fix the direction of the movement, longest first so "me
/// pagaron" is read before "pague".
const _kindVerbs = <(String, MessageKind)>[
  // Money arriving. These must come first: "me pagaron" contains "pagaron".
  ('me pagaron', MessageKind.transferIn),
  ('me pago', MessageKind.transferIn),
  ('me transfirieron', MessageKind.transferIn),
  ('me consignaron', MessageKind.transferIn),
  ('me enviaron', MessageKind.transferIn),
  // Singular, which is how it comes out when one person sent it: "Mariana me
  // envió un pago de un préstamo".
  ('me envio', MessageKind.transferIn),
  ('me mando', MessageKind.transferIn),
  ('me transfirio', MessageKind.transferIn),
  ('me consigno', MessageKind.transferIn),
  ('me devolvio', MessageKind.transferIn),
  ('me abono', MessageKind.transferIn),
  ('me presto', MessageKind.transferIn),
  ('me llego', MessageKind.transferIn),
  ('me entro', MessageKind.transferIn),
  ('me devolvieron', MessageKind.transferIn),
  ('recibi', MessageKind.transferIn),
  ('cobre', MessageKind.transferIn),
  // Said as a noun rather than a verb: "ingreso de doscientos mil", which is
  // how someone dictating from a list of movements phrases it.
  ('ingreso de', MessageKind.transferIn),
  ('ingreso', MessageKind.transferIn),
  ('entrada de', MessageKind.transferIn),
  ('abono de', MessageKind.transferIn),
  ('income', MessageKind.transferIn),
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
ExpenseDraft parseVoiceExpense(
  String spoken, {
  DateTime? now,
  /// The user's accounts, so "… a Bancolombia" picks one. Left empty when
  /// the caller has none to hand; the field then simply stays blank.
  List<Account> accounts = const [],
}) {
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
  final accountId =
      accounts.isEmpty ? null : matchSpokenAccount(spoken, accounts);
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
        ? (_leadingName(spoken, verbEnd) ?? subject)
        : null,
    description: kind == MessageKind.transferOut ||
            kind == MessageKind.transferIn
        // When the sender was named, the reason is still worth keeping; it
        // just belongs in the description rather than in the name.
        ? (_leadingName(spoken, verbEnd) == null ? null : subject)
        : subject,
    kind: kind ?? MessageKind.purchase,
    accountId: accountId,
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
  // What the money was FOR often sits between the verb and the figure, not
  // after it: "me envió un pago de un préstamo por \$200,000 a bancolombia".
  // Looking only after the amount took "a bancolombia" — the account — and
  // threw the reason away.
  final between = _subjectBeforeAmount(normalized, searchFrom);
  if (between != null) return between;

  // Start after the number, so "en" inside "veinte" cannot match and the
  // preposition found is the one introducing the subject.
  final amountEnd = _endOfAmount(normalized, searchFrom);
  final tail = amountEnd < normalized.length
      ? normalized.substring(amountEnd)
      : normalized.substring(searchFrom.clamp(0, normalized.length));

  // Whichever preposition comes first IN THE SENTENCE, not first in the
  // list. "recibí X por pago de prestamo Mariana Hernandez en Bancolombia"
  // carries both "por" and "en"; taking the list order picked "en
  // Bancolombia" and threw the reason away.
  //
  // The list order still decides between two that start at the same place,
  // which is what keeps "en el" ahead of "en".
  final ordered = [..._subjectPrepositions];
  final starts = <String, int>{};
  for (final preposition in ordered) {
    final at = RegExp('(?:^|\\s)${RegExp.escape(preposition)}\\s+')
        .firstMatch(tail)
        ?.start;
    if (at != null) starts[preposition] = at;
  }
  ordered.sort((a, b) {
    final byPosition = (starts[a] ?? 1 << 30).compareTo(starts[b] ?? 1 << 30);
    return byPosition != 0
        ? byPosition
        : _subjectPrepositions
            .indexOf(a)
            .compareTo(_subjectPrepositions.indexOf(b));
  });

  for (final preposition in ordered) {
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

    // Six words covers what a person actually says — "pago de prestamo
    // Mariana Hernandez" is five — while still cutting off a recogniser that
    // has run on into the next sentence.
    final subject = words.take(6).join(' ');
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

/// The reason, when it sits between the verb and the figure.
///
/// Returns null unless there is something there worth keeping, so the
/// ordinary "gasté veinte mil en el almuerzo" — where the gap is empty —
/// falls through to the search after the amount.
String? _subjectBeforeAmount(String normalized, int verbEnd) {
  final figure = RegExp(r'(?:\$|cop|usd)?\s*\d|' + _spokenNumberWord)
      .firstMatch(normalized.substring(verbEnd));
  if (figure == null) return null;

  final region = normalized.substring(verbEnd, verbEnd + figure.start);
  final words = region
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .where((w) => !_subjectStopWords.contains(w))
      .toList();

  // Trim the articles and prepositions off both ends; they introduce the
  // phrase rather than belong to it.
  while (words.isNotEmpty && _phraseEdgeWords.contains(words.first)) {
    words.removeAt(0);
  }
  while (words.isNotEmpty && _phraseEdgeWords.contains(words.last)) {
    words.removeLast();
  }

  // One word of substance at least, and never a run-on.
  if (words.where((w) => w.length >= 4).isEmpty) return null;
  if (words.length > 5) return null;

  return _sentenceCase(words.join(' '));
}

/// Articles and prepositions that top and tail a phrase without being part
/// of it.
const _phraseEdgeWords = {
  'un', 'una', 'uno', 'el', 'la', 'los', 'las', 'de', 'del', 'por', 'para',
  'a', 'al', 'en', 'con', 'the', 'of', 'for', 'to', 'on', 'at',
};

/// The first word of a spoken number, used to find where the figure starts.
const _spokenNumberWord =
    r'\b(?:cero|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|'
    r'trece|catorce|quince|dieci\w+|veinti\w+|veinte|treinta|cuarenta|'
    r'cincuenta|sesenta|setenta|ochenta|noventa|cien|ciento|\w*cientos|'
    r'\w*cientas|mil|millon|millones|lucas?|palos?|one|two|three|four|five|'
    r'six|seven|eight|nine|ten|twenty|thirty|forty|fifty|hundred|thousand|'
    r'million)\b';

/// Capitalises the first letter only. A dictated reason is a phrase, not a
/// name, and "Pago De Un Prestamo" reads like a headline.
String _sentenceCase(String input) =>
    input.isEmpty ? input : '${input[0].toUpperCase()}${input.substring(1)}';

/// A person named before the verb: "Mariana me envió un pago…".
///
/// Only from the ORIGINAL text, because capitalisation is the whole signal
/// and the normalised copy has none. Returns null when the sentence starts
/// with the verb, which is the usual shape — "me pagaron dos millones" names
/// nobody.
String? _leadingName(String spoken, int verbEnd) {
  if (verbEnd == 0) return null;

  final words = spoken.trim().split(RegExp(r'\s+'));
  if (words.isEmpty) return null;

  const notNames = {
    'me', 'mi', 'yo', 'le', 'les', 'la', 'el', 'un', 'una', 'hoy', 'ayer',
    'antier', 'anteayer', 'i', 'my', 'the', 'a', 'an', 'today', 'yesterday',
  };

  final taken = <String>[];
  for (final word in words.take(3)) {
    final clean = word.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    if (clean.isEmpty) break;
    if (notNames.contains(clean.toLowerCase())) break;
    // A name is capitalised and is not the verb.
    if (!RegExp(r'^[A-ZÁÉÍÓÚÑÜ]').hasMatch(clean)) break;
    taken.add(clean);
  }

  return taken.isEmpty ? null : taken.join(' ');
}
