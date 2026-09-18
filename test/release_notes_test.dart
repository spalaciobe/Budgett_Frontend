import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/core/services/release_notes.dart';

void main() {
  group('formatReleaseNotes', () {
    test('a body that is only the changelog link yields nothing', () {
      // The exact body every release here has had so far. The modal showed it
      // verbatim, asterisks and all.
      const body =
          '**Full Changelog**: https://github.com/spalaciobe/Budgett_Frontend/compare/v1.0.0+27...v1.0.0+28';
      expect(formatReleaseNotes(body), isEmpty);
    });

    test('strips bullets, emphasis and attribution from generated notes', () {
      const body = '''
## What's Changed
* **fix(ui):** titles that shrink instead of truncating by @spalaciobe in https://github.com/x/y/pull/12
* feat(capture): bounded ingestion

**Full Changelog**: https://github.com/x/y/compare/a...b
''';
      expect(formatReleaseNotes(body), [
        'fix: titles that shrink instead of truncating',
        'feat: bounded ingestion',
      ]);
    });

    test('keeps the commit type but drops the scope', () {
      expect(
        formatReleaseNotes('- fix(ui): one text column in the inbox card'),
        ['fix: one text column in the inbox card'],
      );
      expect(
        formatReleaseNotes('- refactor!: drop the legacy parser'),
        ['refactor!: drop the legacy parser'],
      );
    });

    test('drops duplicates and caps the list', () {
      final body = List.filled(12, '- fix: same thing').join('\n');
      expect(formatReleaseNotes(body), ['fix: same thing']);

      final many =
          List.generate(12, (i) => '- fix: change number $i').join('\n');
      expect(formatReleaseNotes(many, max: 3), hasLength(3));
    });

    test('empty and null bodies are empty', () {
      expect(formatReleaseNotes(null), isEmpty);
      expect(formatReleaseNotes('   \n  \n'), isEmpty);
    });

    test('a plain human-written body survives intact', () {
      expect(
        formatReleaseNotes('Fixes the crash when adding a transfer.'),
        ['Fixes the crash when adding a transfer.'],
      );
    });
  });
}
