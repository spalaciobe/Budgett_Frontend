import 'package:flutter/material.dart';

/// Centralized text styles at the app's existing (compact) sizes.
///
/// Migrating inline `TextStyle(fontSize: …)` to these named roles keeps the
/// type scale in one place without changing rendered sizes — Material 3's
/// default TextTheme is larger and would inflate the deliberately compact
/// layout. Color/family are left to inherit (DefaultTextStyle/Theme) just like
/// the inline styles they replace; override per use with `copyWith`.
///
/// Note: Flutter already scales these with the OS text-size setting via
/// `MediaQuery.textScaler`, so this is about consistency/maintainability, not
/// enabling scaling.
class AppText {
  AppText._();

  /// Primary row label, e.g. a transaction description or account name.
  static const tileTitle = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);

  /// Trailing amount on a row.
  static const amount = TextStyle(fontSize: 13, fontWeight: FontWeight.bold);

  /// Headline number, e.g. an account balance.
  static const balance = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);

  /// Secondary line: dates, place, hints (11px).
  static const caption = TextStyle(fontSize: 11);

  /// Small uppercase-ish status pill text. Bumped from 10 -> 11 for legibility.
  static const badge = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);

  /// Mid-weight value text (~12px) used in subtitles.
  static const subtitle = TextStyle(fontSize: 12);

  /// Compact card name/label (e.g. account name on a card).
  static const cardName = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
}
