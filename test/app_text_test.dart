import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/core/app_text.dart';

void main() {
  group('AppText roles', () {
    test('sizes match the app compact scale', () {
      expect(AppText.tileTitle.fontSize, 14);
      expect(AppText.tileTitle.fontWeight, FontWeight.w500);
      expect(AppText.amount.fontSize, 13);
      expect(AppText.amount.fontWeight, FontWeight.bold);
      expect(AppText.balance.fontSize, 18);
      expect(AppText.balance.fontWeight, FontWeight.bold);
      expect(AppText.caption.fontSize, 11);
      expect(AppText.subtitle.fontSize, 12);
      expect(AppText.cardName.fontSize, 13);
      expect(AppText.cardName.fontWeight, FontWeight.w600);
    });

    test('badge text is at least 11px for legibility (was 10)', () {
      expect(AppText.badge.fontSize, greaterThanOrEqualTo(11.0));
    });

    test('roles carry no hardcoded color so they inherit the theme', () {
      expect(AppText.tileTitle.color, isNull);
      expect(AppText.amount.color, isNull);
      expect(AppText.caption.color, isNull);
      expect(AppText.badge.color, isNull);
    });
  });
}
