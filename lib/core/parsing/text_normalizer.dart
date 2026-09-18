/// Text normalisation shared by the message parser, the merchant-alias
/// matcher, and the deduplicator.
///
/// Two different normalisations, on purpose:
///
///   * [normalizeForMatch] — lowercase, unaccented, collapsed. Used to look
///     for keywords ("compra", "retiro", "rechazada") inside a message.
///
///   * [normalizeMerchant] — uppercase, unaccented, stripped of the noise
///     Colombian acquirers append to merchant names (store numbers, city
///     suffixes, POS terminal ids). This is the string stored in
///     `merchant_aliases.pattern`, so it must stay stable: changing it
///     silently invalidates every alias the user has taught the app.
library;

const _accented = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
const _plain = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';

/// Replaces accented characters with their ASCII equivalent.
String stripAccents(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final index = _accented.indexOf(char);
    buffer.write(index == -1 ? char : _plain[index]);
  }
  return buffer.toString();
}

/// Lowercase, unaccented, single-spaced. For keyword detection.
String normalizeForMatch(String input) =>
    stripAccents(input).toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Cities Colombian acquirers append to the merchant field. Kept as a token
/// set so both the suffix strip and [_stripTruncatedCityTail] share one list.
const _cityTokens = {
  'BOGOTA', 'BOG', 'MEDELLIN', 'MED', 'CALI', 'BARRANQUILLA', 'BAQ',
  'CARTAGENA', 'CTG', 'BUCARAMANGA', 'BUC', 'PEREIRA', 'MANIZALES', 'CUCUTA',
  'IBAGUE', 'VILLAVICENCIO', 'NEIVA', 'ARMENIA', 'POPAYAN', 'PASTO',
  'MONTERIA', 'SINCELEJO', 'TUNJA', 'VALLEDUPAR', 'ENVIGADO', 'ITAGUI',
  'BELLO', 'SABANETA', 'SOACHA', 'CHIA', 'CAJICA',
};

/// Trailing city, including the one multi-word name in the list.
///
/// Built by concatenation rather than interpolation so the trailing `$` stays
/// an end-of-string anchor: inside a non-raw Dart string it would have to be
/// written `\$`, which the regex engine reads as a literal dollar sign.
final _citySuffix =
    RegExp(r'\s+(?:SANTA MARTA|' + _cityTokens.join('|') + r')$');

/// Street-type abbreviations. A number right after one of these is an address,
/// not a store code — "ARA CL 100" keeps its 100.
const _streetTokens = {
  'CL', 'CLL', 'CALLE', 'CR', 'CRA', 'CARRERA', 'KR', 'AV', 'AVE', 'AVENIDA',
  'DG', 'DIAGONAL', 'TV', 'TRANSVERSAL', 'AC', 'AK', 'MZ', 'NO',
};

/// Trailing junk acquirers glue onto merchant names.
///
/// Matched against the already-uppercased, accent-free string and only ever
/// removed from the END, so a legitimate name that happens to contain a city
/// word ("BOGOTA BEER COMPANY") survives.
final _trailingNoise = <RegExp>[
  // POS / terminal / store identifiers: "EXITO 1234", "D1 #0012".
  // Four digits or more, or any run introduced by '#'. Three bare digits are
  // left alone because they are usually an address (see [_stripStoreCode]).
  RegExp(r'\s+#\d{2,}$'),
  RegExp(r'\s+\d{4,}$'),
  // City suffixes Colombian acquirers append.
  _citySuffix,
  // Country / currency tails: "… CO", "… COL", "… COP"
  RegExp(r'\s+(CO|COL|COLOMBIA|COP)$'),
  // Leftover separators.
  RegExp(r'[\s\-*.,/#]+$'),
];

/// Canonical merchant key. Uppercase, unaccented, de-noised.
///
/// ```
/// normalizeMerchant('Éxito Super  Cl 80 BOG')  → 'EXITO SUPER CL 80'
/// normalizeMerchant('MERCADOPAGO*SPOTIFY')     → 'MERCADOPAGO SPOTIFY'
/// normalizeMerchant('RAPPI  1234 BOGOTA')      → 'RAPPI'
/// ```
String normalizeMerchant(String input) {
  var out = stripAccents(input).toUpperCase();

  // Payment-aggregator glue characters become spaces so the real brand is
  // readable: "MERCADOPAGO*SPOTIFY" → "MERCADOPAGO SPOTIFY".
  out = out.replaceAll(RegExp(r'[*_|]+'), ' ');
  // Drop anything that is not a letter, digit, space, ampersand or dash.
  out = out.replaceAll(RegExp(r'[^A-Z0-9&\-\s]'), ' ');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();

  // Strip noise repeatedly: "EXITO 1234 BOGOTA" needs two passes.
  var previous = '';
  while (previous != out) {
    previous = out;
    for (final pattern in _trailingNoise) {
      out = out.replaceFirst(pattern, '').trim();
    }
    out = _stripStoreCode(out);
    out = _stripTruncatedCityTail(out);
  }

  return out;
}

/// Drops the orphan letter left when an acquirer truncates the city/branch
/// field: `'NOVAVENTA MEDELLIN C'` → `'NOVAVENTA MEDELLIN'`, which the city
/// rule then reduces to `'NOVAVENTA'` on the next pass.
///
/// Only stripped when the token before it is a known city, so a name that
/// genuinely ends in a letter ('PLAN B', 'VITAMINA C') survives. This matters
/// beyond cosmetics: the result is the alias key, so leaving the tail in would
/// make the same shop in another city a separate rule the user has to teach
/// all over again.
String _stripTruncatedCityTail(String input) {
  final match = RegExp(r'^(.*?)\s+([A-Z]+)\s+[A-Z]$').firstMatch(input);
  if (match == null) return input;
  if (!_cityTokens.contains(match.group(2))) return input;
  return '${match.group(1)} ${match.group(2)}';
}

/// Removes a trailing 2–3 digit store code, unless it follows a street
/// abbreviation — in which case it is a house number and part of the name.
String _stripStoreCode(String input) {
  final match = RegExp(r'^(.*?)\s+(\d{2,3})$').firstMatch(input);
  if (match == null) return input;
  final head = match.group(1)!;
  final lastWord = head.split(' ').last;
  if (_streetTokens.contains(lastWord)) return input;
  return head;
}

/// Title-cased version of a merchant key, used as the default friendly name
/// the first time a merchant is seen: `'EXITO SUPER CL 80'` → `'Exito Super Cl 80'`.
String prettifyMerchant(String merchantKey) {
  if (merchantKey.isEmpty) return merchantKey;
  return merchantKey
      .split(' ')
      .map((word) {
        if (word.isEmpty) return word;
        // Keep short all-caps tokens as-is (SA, SAS, BBVA, ATM).
        if (word.length <= 3 && !RegExp(r'\d').hasMatch(word)) return word;
        return word[0] + word.substring(1).toLowerCase();
      })
      .join(' ');
}
