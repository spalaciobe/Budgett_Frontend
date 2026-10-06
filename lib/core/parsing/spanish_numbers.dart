/// Reads amounts the way people say them out loud.
///
/// Speech recognition returns "veinte mil" or "cuarenta y cinco mil
/// quinientos", not "20000" — and in Colombia nobody says the digits. Without
/// this, dictating an expense would mean reading numerals aloud, which is
/// slower than typing them and defeats the point.
///
/// Deliberately narrow: it understands amounts, not arbitrary arithmetic.
/// Anything it cannot read returns null so the caller can fall back to the
/// digits the recogniser did transcribe.
library;

import 'package:budgett_frontend/core/parsing/text_normalizer.dart';

const _units = <String, int>{
  'cero': 0, 'un': 1, 'uno': 1, 'una': 1, 'dos': 2, 'tres': 3, 'cuatro': 4,
  'cinco': 5, 'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9, 'diez': 10,
  'once': 11, 'doce': 12, 'trece': 13, 'catorce': 14, 'quince': 15,
  'dieciseis': 16, 'diecisiete': 17, 'dieciocho': 18, 'diecinueve': 19,
  'veinte': 20, 'veintiuno': 21, 'veintiun': 21, 'veintidos': 22,
  'veintitres': 23, 'veinticuatro': 24, 'veinticinco': 25, 'veintiseis': 26,
  'veintisiete': 27, 'veintiocho': 28, 'veintinueve': 29,
  'treinta': 30, 'cuarenta': 40, 'cincuenta': 50, 'sesenta': 60,
  'setenta': 70, 'ochenta': 80, 'noventa': 90,
};

const _hundreds = <String, int>{
  'cien': 100, 'ciento': 100, 'doscientos': 200, 'doscientas': 200,
  'trescientos': 300, 'trescientas': 300, 'cuatrocientos': 400,
  'cuatrocientas': 400, 'quinientos': 500, 'quinientas': 500,
  'seiscientos': 600, 'seiscientas': 600, 'setecientos': 700,
  'setecientas': 700, 'ochocientos': 800, 'ochocientas': 800,
  'novecientos': 900, 'novecientas': 900,
};

/// Words that scale whatever came before them.
const _multipliers = <String, int>{
  'mil': 1000,
  'miles': 1000,
  'millon': 1000000,
  'millones': 1000000,
  // "20 lucas" is how a Colombian says twenty thousand pesos.
  'luca': 1000,
  'lucas': 1000,
  'palo': 1000000,
  'palos': 1000000,
};

/// Words that may appear inside a spoken number without changing it.
const _filler = {'y', 'de', 'con'};

/// Reads the first spoken amount in [text], or null if there is none.
///
/// Handles the shapes people actually use: "veinte mil", "cuarenta y cinco
/// mil quinientos", "dos millones", "ciento veinte mil", "20 mil", "15 lucas"
/// and a bare "treinta".
double? parseSpokenAmount(String text) {
  final words = normalizeForMatch(text)
      .replaceAll(RegExp(r'[^a-z0-9\s.,]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  // `total` accumulates finished groups ("dos millones" once "millones" is
  // seen); `group` is the number being built up before a multiplier applies.
  var total = 0.0;
  var group = 0.0;
  var sawAnything = false;
  var sawDigits = false;

  for (var i = 0; i < words.length; i++) {
    final word = words[i];

    final digits = _asPlainNumber(word);
    if (digits != null) {
      // A number with its own separators is already written out — "45.900"
      // means forty-five thousand nine hundred, not forty-five point nine.
      // Only a bare integer can be scaled by a following "mil".
      if (sawAnything && group == 0 && total > 0) break;
      group += digits;
      sawAnything = true;
      sawDigits = true;
      continue;
    }

    if (_units.containsKey(word)) {
      group += _units[word]!;
      sawAnything = true;
      continue;
    }
    if (_hundreds.containsKey(word)) {
      group += _hundreds[word]!;
      sawAnything = true;
      continue;
    }

    final scale = _multipliers[word];
    if (scale != null) {
      // "mil pesos" with nothing before it is one thousand, not zero.
      total += (group == 0 ? 1 : group) * scale;
      group = 0;
      sawAnything = true;
      continue;
    }

    if (_filler.contains(word)) {
      // Only filler INSIDE a number. "y" before anything is just a word.
      if (!sawAnything) continue;
      continue;
    }

    // Any other word ends the number — but only once one has started, so
    // leading words like "gaste" are skipped rather than stopping us.
    if (sawAnything) break;
  }

  final value = total + group;
  if (!sawAnything || value <= 0) return null;

  // A bare spoken figure under a thousand is almost always thousands of
  // pesos: "gasté veinte" is twenty thousand, never twenty pesos, in a
  // country where a coffee costs three thousand. Digits are left alone —
  // someone who said "20.000" meant it, and someone who typed 20 may not.
  if (!sawDigits && value < 1000 && value == value.roundToDouble()) {
    return value * 1000;
  }
  return value;
}

/// A numeral written with Colombian separators, as a plain value.
double? _asPlainNumber(String word) {
  if (!RegExp(r'^\d').hasMatch(word)) return null;
  final cleaned = word.replaceAll(RegExp(r'[^\d.,]'), '');
  if (cleaned.isEmpty) return null;

  // "45.900" and "45,900" are both forty-five thousand nine hundred here;
  // only a trailing two-digit group after the LAST separator is decimals.
  final match = RegExp(r'^(.*)[.,](\d{1,2})$').firstMatch(cleaned);
  if (match != null && match.group(1)!.contains(RegExp(r'[.,]'))) {
    final whole = match.group(1)!.replaceAll(RegExp(r'[.,]'), '');
    return double.tryParse('$whole.${match.group(2)}');
  }
  return double.tryParse(cleaned.replaceAll(RegExp(r'[.,]'), ''));
}
