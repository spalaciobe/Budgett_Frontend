/// Turns a GitHub release body into lines a person can read.
///
/// The update modal used to print the release body verbatim, so it showed
/// `**Full Changelog**: https://github.com/…/compare/v1.0.0+26...v1.0.0+27` —
/// asterisks, a URL nobody can tap, and no actual news. What reaches the
/// screen now is the commit subjects, with the markup and the plumbing
/// removed.
///
/// This is deliberately not a Markdown renderer. Release bodies here are a
/// list of one-line changes; a dependency that can parse tables and images
/// would be a lot of machinery for stripping two asterisks.
library;

/// A link line GitHub appends to every auto-generated body.
final _fullChangelog = RegExp(r'^\s*\*{0,2}full changelog\*{0,2}\s*:',
    caseSensitive: false);

/// "…  by @someone in https://github.com/…/pull/12" — attribution that means
/// nothing to the person being offered an update.
final _attribution = RegExp(r'\s+by\s+@[\w-]+(\s+in\s+\S+)?\s*$');

/// A bare URL left on its own line.
final _bareUrl = RegExp(r'^\s*<?https?://\S+>?\s*$');

/// Leading bullet or heading markers.
final _leadingMarker = RegExp(r'^\s*(?:[-*+]|#{1,6})\s+');

/// Markdown emphasis and code ticks.
final _emphasis = RegExp(r'(\*{1,3}|_{2,3}|`)');

/// Conventional-commit scope: "fix(ui): " → "fix: " reads no better, but the
/// type itself tells someone whether the update is a fix or a feature, so it
/// stays. Only the parenthesised scope goes.
final _scope = RegExp(r'^(\w+)\([^)]*\)(!?):\s*');

/// A heading GitHub always inserts, redundant next to the modal's own
/// "What's new".
final _whatsChanged = RegExp(r"^\s*#*\s*what'?s changed\s*$", caseSensitive: false);

/// Parses [body] into display lines, most important first.
///
/// Returns an empty list when nothing survives — which is the normal case for
/// a release whose body is only the changelog link, and the signal for the UI
/// to leave the section out entirely rather than show an empty box.
List<String> formatReleaseNotes(String? body, {int max = 8}) {
  if (body == null || body.trim().isEmpty) return const [];

  final lines = <String>[];
  for (var raw in body.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    if (_fullChangelog.hasMatch(line)) continue;
    if (_bareUrl.hasMatch(line)) continue;
    if (_whatsChanged.hasMatch(line)) continue;

    line = line.replaceFirst(_leadingMarker, '');
    line = line.replaceAll(_attribution, '');
    line = line.replaceAll(_emphasis, '');
    line = line.replaceFirstMapped(
        _scope, (m) => '${m.group(1)}${m.group(2)}: ');
    line = line.trim();

    // A trailing bare link inside an otherwise useful line.
    line = line.replaceAll(RegExp(r'\s*<?https?://\S+>?\s*$'), '').trim();

    if (line.isEmpty) continue;
    if (lines.contains(line)) continue;
    lines.add(line);
    if (lines.length >= max) break;
  }
  return lines;
}
