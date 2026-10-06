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
/// Deliberately terse: a small model follows a short instruction with one
/// example far better than a long explanation, and every token of prompt is
/// time the user spends looking at a spinner.
String buildExtractionPrompt(String text) => '''
Extract the payment from this text. Answer with JSON only, no explanation.

Fields:
"amount": number, no thousands separators, null if not stated
"currency": "COP" or "USD"
"merchant": who was paid, or null
"date": "YYYY-MM-DD" or null
"direction": "out" if money left, "in" if money arrived

Example answer:
{"amount":45900,"currency":"COP","merchant":"LA LLAMITA","date":"2026-10-05","direction":"out"}

Text:
$text

JSON:''';

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
  // A draft the rules read confidently is left alone: running the model would
  // cost seconds and could only make it worse.
  if (draft.confidence >= kDraftReviewThreshold && draft.isUsable) {
    return draft;
  }

  final String answer;
  try {
    answer = await llm.generate(
      buildExtractionPrompt(textOverride ?? draft.rawText),
    );
  } on LocalLlmUnavailable {
    return draft;
  } catch (_) {
    return draft;
  }

  final read = parseModelAnswer(answer);
  if (read == null) return draft;

  // Only blanks. An amount the rules took from a line that said "TOTAL A
  // PAGAR" is better evidence than anything a 2B model infers.
  final amount = draft.amount ?? read.amount;
  final merchant = draft.merchant ?? read.merchant;
  final filledSomething =
      (draft.amount == null && read.amount != null) ||
          (draft.merchant == null && read.merchant != null);

  if (!filledSomething) return draft;

  return draft.copyWith(
    amount: amount,
    currency: draft.amount == null ? read.currency ?? draft.currency : null,
    merchant: merchant,
    kind: draft.amount == null && read.moneyOut == false
        ? MessageKind.transferIn
        : null,
    // Capped below the threshold on purpose: a draft the model had to rescue
    // stays marked as needing a look, however sure the model sounded.
    confidence: 0.55,
    warning: 'Read by the on-device model — check the amount',
  );
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
