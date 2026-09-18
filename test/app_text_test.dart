import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/core/app_text.dart';

void main() {
  group('AppText roles', () {
    test('the scale keeps a real step between roles', () {
      // Every figure used to land between 11 and 18px, so no number could
      // dominate a screen. These assertions lock in the gap, not the exact
      // numbers: the hero has to outrank a balance, which outranks a row.
      expect(AppText.moneyHero.fontSize!,
          greaterThan(AppText.balance.fontSize!));
      expect(AppText.balance.fontSize!,
          greaterThan(AppText.moneyMedium.fontSize!));
      expect(AppText.moneyMedium.fontSize!,
          greaterThan(AppText.amount.fontSize!));
      expect(AppText.amount.fontSize!,
          greaterThan(AppText.amountSmall.fontSize!));
      expect(AppText.moneyHero.fontSize! / AppText.amount.fontSize!,
          greaterThanOrEqualTo(2.0));
    });

    test('body roles stay in the legible band', () {
      expect(AppText.tileTitle.fontSize, 14);
      expect(AppText.tileTitle.fontWeight, FontWeight.w500);
      expect(AppText.cardName.fontWeight, FontWeight.w600);
      expect(AppText.subtitle.fontSize, 13);
      expect(AppText.caption.fontSize, 12);
      // Nothing in the UI may drop below 11px.
      for (final style in [
        AppText.tileTitle,
        AppText.cardName,
        AppText.subtitle,
        AppText.caption,
        AppText.badge,
        AppText.label,
      ]) {
        expect(style.fontSize!, greaterThanOrEqualTo(11.0));
      }
    });

    test('every money role has tabular figures so amounts align', () {
      for (final style in [
        AppText.moneyHero,
        AppText.balance,
        AppText.moneyMedium,
        AppText.amount,
        AppText.amountSmall,
        AppText.tabular(15),
      ]) {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'a currency value rendered with this role would drift',
        );
        expect(style.fontFamily, AppText.figureFamily);
      }
    });

    test('figure roles select weight by variation, never fontWeight', () {
      // Space Grotesk is a variable font declared once in pubspec.yaml.
      // Setting fontWeight as well would synthesise a fake bold on top of the
      // varied outline.
      for (final style in [
        AppText.moneyHero,
        AppText.balance,
        AppText.moneyMedium,
        AppText.amount,
        AppText.screenTitle,
        AppText.sectionTitle,
      ]) {
        expect(style.fontWeight, isNull);
        expect(style.fontVariations, isNotEmpty);
        expect(style.fontVariations!.first.axis, 'wght');
      }
    });

    test('word roles use the body family', () {
      for (final style in [
        AppText.tileTitle,
        AppText.cardName,
        AppText.subtitle,
        AppText.caption,
        AppText.badge,
        AppText.label,
      ]) {
        expect(style.fontFamily, AppText.bodyFamily);
      }
    });

    test('roles carry no hardcoded color so they inherit the theme', () {
      for (final style in [
        AppText.tileTitle,
        AppText.amount,
        AppText.caption,
        AppText.badge,
        AppText.balance,
        AppText.moneyHero,
      ]) {
        expect(style.color, isNull);
      }
    });
  });
}
