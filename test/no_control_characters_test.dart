// A regex with a stray control character in it never matches and never
// complains. One got into `screenshot_parser.dart` — a literal backspace
// where `\b` was meant — and the only symptom was a rule that quietly did
// nothing, which took a round trip through the phone to find.
//
// Source files are text. Nothing in them should be a control character
// except tab, newline and carriage return.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no source file carries a stray control character', () {
    final offenders = <String>[];

    for (final directory in ['lib', 'test']) {
      final dir = Directory(directory);
      if (!dir.existsSync()) continue;

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final content = entity.readAsStringSync();
        for (var i = 0; i < content.length; i++) {
          final code = content.codeUnitAt(i);
          final allowed = code == 0x09 || code == 0x0A || code == 0x0D;
          if (code < 0x20 && !allowed) {
            offenders.add(
              '${entity.path}: U+${code.toRadixString(16).padLeft(4, '0')} '
              'at offset $i',
            );
            break;
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'A control character in source is almost always an escape '
            'that was written literally:\n${offenders.join('\n')}');
  });
}
