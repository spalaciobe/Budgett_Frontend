/// Uses the local model to read what the rules could not.
///
/// A backup, never the engine. `receipt_parser`, `screenshot_parser` and
/// `voice_expense_parser` run first and are right on everything they were
/// built from; this runs only when one of them comes back unsure, and even
/// then it may only FILL IN fields the rules left blank — it never overwrites
/// a figure a rule read off a labelled total.
///
/// That rule is the whole design. A 2B model quantised to four bits will
/// cheerfully produce a plausible number that is not on the receipt, and a
/// wrong amount recorded silently is worse than an empty field. So the model
/// gets the last word on nothing.
library;

import 'dart:convert';

import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/services/local_llm_service.dart';

/// What the model is asked for, and nothing else.
///
/// Four things this has to get right, each from how a small quantised model
/// actually behaves:
///
///   * **Two examples, and one of them empty.** Given a single complete
///     example the model copies that shape and fills every field, inventing
///     an amount for text that has none. The empty example is what makes
///     "it is not here" a legal answer.
///   * **The separator rule, stated outright.** "45.900" is forty-five
///     thousand nine hundred in Colombia. A model trained mostly on English
///     reads it as forty-five point nine and answers 45.9.
///   * **Which figure.** A receipt prints a subtotal, a tax line, the cash
///     handed over and the change. Left to itself the model picks the
///     largest, which is almost always the cash.
///   * **One line of context per shape.** A till roll, a list of movements
///     and a spoken sentence are different enough that naming which one it
///     is costs a few tokens and saves a wrong reading.
///
/// Still short. Every token of prompt is time the user spends watching a
/// spinner, and the budget is 256 tokens of answer.
String buildExtractionPrompt(String text, {DraftSource? source}) {
  final context = switch (source) {
    DraftSource.receipt =>
      'This is text read off a receipt or a bank app screen.',
    DraftSource.voice => 'This is a sentence someone spoke about a payment.',
    null => 'This is text about a payment.',
  };

  return '''
$context Extract the payment. Answer with JSON only, no explanation.

Rules:
- Use only what is written. If a field is not there, answer null.
- Never invent or estimate an amount.
- "." and "," are thousands separators: 45.900 means 45900, not 45.9.
- The amount is the total actually paid: not a line item, not the subtotal,
  not the tax, not the cash handed over, not the change.
- A minus sign before the amount means money left; otherwise it arrived.

Fields: amount (number or null), currency ("COP" or "USD"),
merchant (who was paid, or null), date ("YYYY-MM-DD" or null),
direction ("out" or "in").

Example 1
Text: LA LLAMITA S.A.S. / SUBTOTAL 42.500 / TOTAL A PAGAR 45.900 / EFECTIVO 50.000 / Fecha 05/10/2026
Answer: {"amount":45900,"currency":"COP","merchant":"LA LLAMITA S.A.S.","date":"2026-10-05","direction":"out"}

Example 2
Text: Gracias por su compra, vuelva pronto
Answer: {"amount":null,"currency":"COP","merchant":null,"date":null,"direction":"out"}

Text: $text
Answer:''';
}

/// Reads the model's answer into the fields it managed to state.
///
/// Returns null when nothing usable came back, which is the common case for
/// a small model and is not treated as an error.
({
  double? amount,
  String? currency,
  String? merchant,
  DateTime? date,
  bool? moneyOut,
})? parseModelAnswer(String answer) {
  final json = _firstJsonObject(answer);
  if (json == null) return null;

  Map<String, dynamic> decoded;
  try {
    final value = jsonDecode(json);
    if (value is! Map<String, dynamic>) return null;
    decoded = value;
  } catch (_) {
    return null;
  }

  final direction = (decoded['direction'] as Object?)?.toString().toLowerCase();

  return (
    amount: _asAmount(decoded['amount']),
    currency: _asCurrency(decoded['currency']),
    merchant: _asText(decoded['merchant']),
    date: _asDate(decoded['date']),
    moneyOut: direction == 'out'
        ? true
        : direction == 'in'
            ? false
            : null,
  );
}

/// Fills [draft]'s blanks from the model, leaving everything the rules read
/// exactly as it was.
///
/// Returns the draft unchanged when the model is unavailable or says nothing
/// useful, so a caller never has to handle the failure separately.
Future<ExpenseDraft> completeWithModel(
  ExpenseDraft draft, {
  required LocalLlmService llm,
  String? textOverride,
}) async {
  // The model runs when the rules left something blank, OR when they produced
  // a label that is plainly not a name.
  //
  // The second case is the one this originally missed. "Mariana me envió un
  // pago de un préstamo por $200,000 a bancolombia" gave the right amount,
  // the right direction and the right account — so the draft was confident —
  // and a merchant of "Un Prestamo Por $200,000 A Bancolombia". Gating on
  // confidence alone meant the model never saw the one field it is actually
  // better at.
  final needsHelp = !draft.isUsable ||
      draft.confidence < kDraftReviewThreshold ||
      _labelLooksPoor(draft.merchant) ||
      _labelLooksPoor(draft.description);
  if (!needsHelp) return draft;

  final String answer;
  try {
    answer = await llm.generate(
      buildExtractionPrompt(textOverride ?? draft.rawText,
          source: draft.source),
    );
  } on LocalLlmUnavailable {
    return draft;
  } catch (_) {
    return draft;
  }

  final read = parseModelAnswer(answer);
  if (read == null) return draft;

  // What the model is allowed to touch depends on what a mistake costs.
  //
  // The AMOUNT is the ledger. A figure the rules took off a line that said
  // "TOTAL A PAGAR" is better evidence than anything a four-bit model
  // infers, so the model may only supply one that is missing. Same for the
  // currency, the date and the direction, which all follow the amount.
  //
  // The LABEL is free text. A bad one is visible at a glance and costs
  // nothing to correct, and a garbled phrase is precisely what the rules are
  // worst at and a model is best at. So the model may replace a label that
  // plainly is not a name.
  final amount = draft.amount ?? read.amount;
  final merchant = _labelLooksPoor(draft.merchant)
      ? (read.merchant ?? draft.merchant)
      : (draft.merchant ?? read.merchant);

  final filledAmount = draft.amount == null && read.amount != null;
  final improvedLabel =
      merchant != draft.merchant && (read.merchant?.isNotEmpty ?? false);
  if (!filledAmount && !improvedLabel) return draft;

  return draft.copyWith(
    amount: amount,
    currency: draft.amount == null ? read.currency ?? draft.currency : null,
    merchant: merchant,
    kind: draft.amount == null && read.moneyOut == false
        ? MessageKind.transferIn
        : null,
    // A draft the model had to supply a FIGURE for stays below the threshold,
    // however sure the model sounded. One where it only tidied the label
    // keeps the confidence the rules earned — the number was never in doubt.
    confidence: filledAmount ? 0.55 : draft.confidence,
    warning: filledAmount
        ? 'Read by the on-device model — check the amount'
        : draft.warning,
  );
}

/// True when a label is clearly not the name of who was paid.
///
/// Dictation produces these: the rules take whatever sits after a
/// preposition, which for "un pago de un préstamo por \$200,000 a
/// bancolombia" is the rest of the sentence, amount and all. A name does not
/// contain a currency figure, does not run past a handful of words, and is
/// not a lone article.
bool _labelLooksPoor(String? label) {
  if (label == null) return false;
  final trimmed = label.trim();
  if (trimmed.isEmpty) return true;

  // A figure inside a name means the sentence was swallowed whole.
  if (RegExp(r'[\$]|\b\d{3,}\b').hasMatch(trimmed)) return true;

  final words = trimmed.split(RegExp(r'\s+'));
  if (words.length > 5) return true;

  // Nothing but filler.
  const filler = {
    'un', 'una', 'uno', 'el', 'la', 'los', 'las', 'de', 'del', 'por', 'para',
    'a', 'en', 'the', 'of', 'for', 'to',
  };
  return words.every((w) => filler.contains(w.toLowerCase()));
}

/// The first balanced `{...}` in [answer].
///
/// Small models wrap JSON in prose, in a markdown fence, or both, and will
/// occasionally start a second object after the first. Scanning for a
/// balanced pair is more robust than a regex and cheaper than a parser.
String? _firstJsonObject(String answer) {
  final start = answer.indexOf('{');
  if (start == -1) return null;

  var depth = 0;
  var inString = false;
  var escaped = false;

  for (var i = start; i < answer.length; i++) {
    final char = answer[i];

    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;

    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) return answer.substring(start, i + 1);
    }
  }
  return null;
}

double? _asAmount(Object? value) {
  if (value is num) return value.toDouble() > 0 ? value.toDouble() : null;
  if (value is! String) return null;
  // The model is told not to, but it will sometimes return "45.900" anyway.
  final cleaned = value.replaceAll(RegExp(r'[^\d.,]'), '');
  if (cleaned.isEmpty) return null;
  final match = RegExp(r'^(.*)[.,](\d{1,2})$').firstMatch(cleaned);
  if (match != null && match.group(1)!.contains(RegExp(r'[.,]'))) {
    final whole = match.group(1)!.replaceAll(RegExp(r'[.,]'), '');
    final parsed = double.tryParse('$whole.${match.group(2)}');
    return (parsed ?? 0) > 0 ? parsed : null;
  }
  final parsed = double.tryParse(cleaned.replaceAll(RegExp(r'[.,]'), ''));
  return (parsed ?? 0) > 0 ? parsed : null;
}

String? _asCurrency(Object? value) {
  final text = value?.toString().toUpperCase();
  return (text == 'COP' || text == 'USD') ? text : null;
}

String? _asText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  // A model that could not find a name sometimes answers with the question.
  if (text.length > 60) return null;
  return text;
}

DateTime? _asDate(Object? value) {
  final text = value?.toString();
  if (text == null) return null;
  final match = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
  if (match == null) return null;
  try {
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  } catch (_) {
    return null;
  }
}
