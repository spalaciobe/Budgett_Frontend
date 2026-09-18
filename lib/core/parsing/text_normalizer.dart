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
  RegExp(r'\s+(BOGOTA|BOG|MEDELLIN|MED|CALI|BARRANQUILLA|BAQ|CARTAGENA|CTG|'
      r'BUCARAMANGA|BUC|PEREIRA|MANIZALES|CUCUTA|IBAGUE|VILLAVICENCIO|'
      r'SANTA MARTA|NEIVA|ARMENIA|POPAYAN|PASTO|MONTERIA|SINCELEJO|TUNJA|'
      r'VALLEDUPAR|ENVIGADO|ITAGUI|BELLO|SABANETA|SOACHA|CHIA|CAJICA)$'),
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
  }

  return out;
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
