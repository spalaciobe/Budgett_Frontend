/// Maps a capture source (Android package name or SMS sender) and the message
/// text itself onto an issuer slug.
///
/// Matching is substring-based on purpose. Package names change between app
/// releases and SMS short codes differ per carrier, so hardcoding exact
/// identifiers would silently stop working. A source can always be pinned
/// manually — `capture_sources.issuer_key` wins over anything guessed here.
library;

import 'text_normalizer.dart';

class Issuer {
  final String key;
  final String displayName;

  /// Substrings looked for inside the Android package name or SMS sender.
  final List<String> sourceHints;

  /// Substrings looked for inside the normalised message title + body.
  final List<String> textHints;

  const Issuer({
    required this.key,
    required this.displayName,
    this.sourceHints = const [],
    this.textHints = const [],
  });
}

/// Order matters: more specific issuers first, because Nequi messages mention
/// Bancolombia and DaviPlata messages mention Davivienda.
const kIssuers = <Issuer>[
  Issuer(
    key: 'nequi',
    displayName: 'Nequi',
    sourceHints: ['nequi'],
    textHints: ['nequi'],
  ),
  Issuer(
    key: 'daviplata',
    displayName: 'DaviPlata',
    sourceHints: ['daviplata'],
    textHints: ['daviplata'],
  ),
  Issuer(
    key: 'bancolombia',
    displayName: 'Bancolombia',
    sourceHints: ['bancolombia', 'todo1'],
    textHints: ['bancolombia'],
  ),
  Issuer(
    key: 'davivienda',
    displayName: 'Davivienda',
    sourceHints: ['davivienda'],
    textHints: ['davivienda'],
  ),
  Issuer(
    key: 'nu',
    displayName: 'Nu',
    sourceHints: ['com.nu.', 'nubank'],
    textHints: ['nu colombia', 'de nu', 'tu nu'],
  ),
  Issuer(
    key: 'bbva',
    displayName: 'BBVA',
    sourceHints: ['bbva'],
    textHints: ['bbva'],
  ),
  Issuer(
    key: 'colpatria',
    displayName: 'Scotiabank Colpatria',
    sourceHints: ['colpatria', 'scotiabank'],
    textHints: ['colpatria', 'scotiabank'],
  ),
  Issuer(
    key: 'falabella',
    displayName: 'Banco Falabella',
    sourceHints: ['falabella'],
    textHints: ['banco falabella'],
  ),
  Issuer(
    key: 'rappi',
    displayName: 'RappiCard',
    sourceHints: ['rappi'],
    textHints: ['rappicard', 'rappi card', 'tu rappicard'],
  ),
];

final Map<String, Issuer> _byKey = {for (final i in kIssuers) i.key: i};

/// Friendly name for an issuer slug, or the slug itself if unknown.
String issuerDisplayName(String? key) =>
    key == null ? '' : (_byKey[key]?.displayName ?? key);

/// Resolves the issuer from the source identifier (package name / SMS sender).
String? issuerFromSourceKey(String sourceKey) {
  final needle = sourceKey.toLowerCase();
  for (final issuer in kIssuers) {
    for (final hint in issuer.sourceHints) {
      if (needle.contains(hint)) return issuer.key;
    }
  }
  return null;
}

/// Resolves the issuer from the message itself. Falls back on this when the
/// sender is an opaque short code.
String? issuerFromText(String title, String body) {
  final haystack = normalizeForMatch('$title $body');
  for (final issuer in kIssuers) {
    for (final hint in issuer.textHints) {
      if (haystack.contains(hint)) return issuer.key;
    }
  }
  return null;
}

/// Best-effort issuer for a capture. [pinned] is the user's choice stored on
/// the source row and always wins.
String? resolveIssuer({
  String? pinned,
  required String sourceKey,
  required String title,
  required String body,
}) {
  if (pinned != null && pinned.isNotEmpty) return pinned;
  return issuerFromSourceKey(sourceKey) ?? issuerFromText(title, body);
}
