// The captured place: how its address reads and where its Maps link points.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/services/message_capture_service.dart';
import 'package:budgett_frontend/core/utils/maps_link.dart';

void main() {
  group('formatStreet', () {
    test('writes the house number the Colombian way', () {
      expect(formatStreet('Calle 20', '43G-12'), 'Calle 20 #43G-12');
    });

    test('collapses the prefixes geocoders put on the number', () {
      expect(formatStreet('Carrera 63', '#25b-15'), 'Carrera 63 #25b-15');
      expect(formatStreet('Carrera 63', 'No. 25b-15'), 'Carrera 63 #25b-15');
    });

    test('does not repeat a number the street already carries', () {
      expect(formatStreet('Carrera 63 25b-15', '25b-15'), 'Carrera 63 25b-15');
    });

    test('keeps the bare street when there is no number', () {
      expect(formatStreet('Calle 20', null), 'Calle 20');
      expect(formatStreet('Calle 20', '  '), 'Calle 20');
    });

    test('is null without a street', () {
      expect(formatStreet(null, '43-12'), isNull);
      expect(formatStreet(' ', '43-12'), isNull);
    });
  });

  group('mapsUri', () {
    test('pins the coordinates, not the address', () {
      final uri = mapsUri(6.2087654321, -75.5678901234);
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/search/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['query'], '6.208765,-75.567890');
    });
  });

  group('accuracyLabel', () {
    test('rounds so it does not claim false precision', () {
      expect(accuracyLabel(12.7), '±15 m');
      expect(accuracyLabel(2), '±5 m');
      expect(accuracyLabel(143), '±140 m');
      expect(accuracyLabel(1850), '±1.9 km');
    });

    test('is null when the platform gave no radius', () {
      expect(accuracyLabel(null), isNull);
      expect(accuracyLabel(0), isNull);
    });
  });
}
