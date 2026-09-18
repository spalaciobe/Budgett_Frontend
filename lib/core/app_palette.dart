import 'package:flutter/material.dart';

/// The colours a theme is built from, as data.
///
/// Extracted so the palette can be swapped without touching component themes:
/// the FAB, the navigation bar, the chips and the buttons all reach for the
/// brand colour in a dozen places, and comparing two palettes meant editing
/// every one of them.
///
/// Meanings stay fixed whatever the palette — brand for actions, one colour
/// for transfers, one for goals, income green, expense red, pending amber.
/// A palette changes the hues, never what they stand for.
@immutable
class AppPalette {
  final String name;

  /// One line on why this palette looks the way it does.
  final String note;

  // ── Meanings ──────────────────────────────────────────────────────────────
  final Color brand; // actions, selection, focus
  final Color transfer; // money between your own accounts
  final Color highlight; // goals, informational accents
  final Color negative; // expenses, destructive actions
  final Color positiveDark; // income, on a dark surface
  final Color positiveLight; // income, on a light surface
  final Color warningDark; // pending, on a dark surface
  final Color warningLight; // pending, on a light surface

  /// Ink that sits on [brand]. A lime brand needs dark ink; a teal one needs
  /// white, and getting this wrong is the fastest way to make a vivid palette
  /// unreadable.
  final Color onBrand;

  // ── Dark surfaces ─────────────────────────────────────────────────────────
  final Color darkBackground;
  final Color darkSurface;
  final Color darkSurfaceVariant;
  final Color darkOutline;
  final Color darkOnSurface;
  final Color darkOnSurfaceVariant;

  // ── Light surfaces ────────────────────────────────────────────────────────
  final Color lightBackground;
  final Color lightSurface;
  final Color lightSurfaceVariant;
  final Color lightOutline;
  final Color lightOnSurface;
  final Color lightOnSurfaceVariant;

  const AppPalette({
    required this.name,
    required this.note,
    required this.brand,
    required this.onBrand,
    required this.transfer,
    required this.highlight,
    required this.negative,
    required this.positiveDark,
    required this.positiveLight,
    required this.warningDark,
    required this.warningLight,
    required this.darkBackground,
    required this.darkSurface,
    required this.darkSurfaceVariant,
    required this.darkOutline,
    required this.darkOnSurface,
    required this.darkOnSurfaceVariant,
    required this.lightBackground,
    required this.lightSurface,
    required this.lightSurfaceVariant,
    required this.lightOutline,
    required this.lightOnSurface,
    required this.lightOnSurfaceVariant,
  });

  /// What the app ships today: teal brand, near-black surfaces.
  static const teal = AppPalette(
    name: 'Teal',
    note: 'The current app: teal brand on a neutral near-black.',
    brand: Color(0xFF1B998B),
    onBrand: Colors.white,
    transfer: Color(0xFF8D6A9F),
    highlight: Color(0xFFFFBF81),
    negative: Color(0xFFDC3248),
    positiveDark: Color(0xFF66BB6A),
    positiveLight: Color(0xFF2E7D32),
    warningDark: Color(0xFFFFB74D),
    warningLight: Color(0xFFC2410C),
    darkBackground: Color(0xFF121418),
    darkSurface: Color(0xFF1E2229),
    darkSurfaceVariant: Color(0xFF2A2F3A),
    darkOutline: Color(0xFF333A45),
    darkOnSurface: Color(0xFFECEDEE),
    darkOnSurfaceVariant: Color(0xFF9BA4AE),
    lightBackground: Color(0xFFF1F5F4),
    lightSurface: Colors.white,
    lightSurfaceVariant: Color(0xFFE8EDEC),
    lightOutline: Color(0xFFDDE4E2),
    lightOnSurface: Color(0xFF16201E),
    lightOnSurfaceVariant: Color(0xFF5C6764),
  );

  /// Lime as the brand, on surfaces darker than today's.
  ///
  /// The catch this solves: in a finance app green already means income, so a
  /// lime brand and a green "positive" fight each other. Here lime *is* the
  /// positive as well — one green, two jobs that never contradict — and
  /// transfers move to electric violet so they stay distinguishable.
  static const lime = AppPalette(
    name: 'Lime',
    note: 'Lime brand and income share one green; violet carries transfers.',
    brand: Color(0xFFB8FF3C),
    onBrand: Color(0xFF0A0F04),
    transfer: Color(0xFF9B7BFF),
    highlight: Color(0xFFFFD166),
    negative: Color(0xFFFF4D6A),
    positiveDark: Color(0xFFB8FF3C),
    positiveLight: Color(0xFF4A7C00),
    warningDark: Color(0xFFFFC145),
    warningLight: Color(0xFFB45309),
    darkBackground: Color(0xFF080B07),
    darkSurface: Color(0xFF11150F),
    darkSurfaceVariant: Color(0xFF1C2318),
    darkOutline: Color(0xFF2A3324),
    darkOnSurface: Color(0xFFEDF3E8),
    darkOnSurfaceVariant: Color(0xFF9AA694),
    lightBackground: Color(0xFFF4F7EF),
    lightSurface: Colors.white,
    lightSurfaceVariant: Color(0xFFEAEFE2),
    lightOutline: Color(0xFFDCE3D2),
    lightOnSurface: Color(0xFF141A0F),
    lightOnSurfaceVariant: Color(0xFF5E6656),
  );

  /// Lime for actions, but income keeps its own softer green.
  ///
  /// The difference from [lime] is a deliberate test: does a screen read
  /// better when the brand and "money in" are the same green, or when the
  /// brand stays a pure accent and income is quieter? Surfaces are the coolest
  /// of the three, closer to charcoal than to black.
  static const limeSlate = AppPalette(
    name: 'Lime on slate',
    note: 'Lime for actions only; income keeps a separate, softer green.',
    brand: Color(0xFFC6F24E),
    onBrand: Color(0xFF12180A),
    transfer: Color(0xFF7DD3FC),
    highlight: Color(0xFFFDBA74),
    negative: Color(0xFFFB6F84),
    positiveDark: Color(0xFF7BE8A3),
    positiveLight: Color(0xFF2F7A47),
    warningDark: Color(0xFFFCD34D),
    warningLight: Color(0xFFB45309),
    darkBackground: Color(0xFF0A0C10),
    darkSurface: Color(0xFF141821),
    darkSurfaceVariant: Color(0xFF1F2530),
    darkOutline: Color(0xFF2C3440),
    darkOnSurface: Color(0xFFE9EDF2),
    darkOnSurfaceVariant: Color(0xFF94A0AF),
    lightBackground: Color(0xFFF3F5F7),
    lightSurface: Colors.white,
    lightSurfaceVariant: Color(0xFFE9EDF1),
    lightOutline: Color(0xFFDCE2E8),
    lightOnSurface: Color(0xFF131820),
    lightOnSurfaceVariant: Color(0xFF5A6572),
  );

  static const all = [teal, lime, limeSlate];
}
