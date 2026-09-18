import 'package:flutter/material.dart';

/// The app's type system.
///
/// Two families, each with one job:
///
/// * **Open Sans** (bundled, static weights) carries every word: labels,
///   descriptions, buttons, hints. It is neutral on purpose — prose in a
///   finance app should not compete with the numbers.
/// * **Space Grotesk** (bundled, variable `wght` axis) carries every *figure*:
///   amounts, balances, percentages, and screen titles. It has `tnum`
///   (tabular figures), so a column of amounts lines its digits up instead of
///   drifting — the single most visible difference between an app that looks
///   built for money and one that doesn't.
///
/// Two rules that are easy to get wrong:
///
/// 1. Space Grotesk is a **variable** font declared once in `pubspec.yaml`, so
///    weight is selected with [FontVariation] (`wght`), never `fontWeight`.
///    Passing `fontWeight` would make Flutter synthesise a fake bold on top of
///    the already-varied outline.
/// 2. Anything that renders a currency value must use a `money*` role (or
///    [AppText.tabular]) so the figures stay tabular. A raw
///    `TextStyle(fontSize: …)` silently drops back to proportional digits.
///
/// The scale is a ~1.2 modular progression (11 · 12 · 13 · 14 · 17 · 22 · 28 ·
/// 36) instead of the previous 11–18 flat band, so a screen has a clear
/// entry point: one number dominates, everything else recedes.
///
/// **No `height` on the Open Sans roles.** Its own metrics need 1.362em
/// (ascent 1.069 + descent 0.293); anything lower crops the bottom of the
/// glyphs, and since this app truncates with `TextOverflow.fade`, the crop
/// renders as a soft fade across the foot of the text — which is how titles
/// with descenders ("World cup pool", "Tablet Payment") ended up looking
/// half-erased while their neighbours were fine. Vertical rhythm is set with
/// padding, not by squeezing the line box.
class AppText {
  AppText._();

  // Space Grotesk needs 1.276em and Open Sans 1.362em for a full glyph box.
  // Figures are boxed at 1.2 because digits sit on the baseline; prose gets
  // no forced height at all.
  static const String bodyFamily = 'OpenSans';
  static const String figureFamily = 'SpaceGrotesk';

  /// Tabular figures: fixed-width digits so stacked amounts align.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static List<FontVariation> _wght(double w) => [FontVariation('wght', w)];

  // ── Figures (Space Grotesk) ────────────────────────────────────────────────

  /// The figure a summary card leads with. Smaller than [moneyHero]: a card
  /// that sits above a list has to leave the list visible.
  static final balanceHero = TextStyle(
    fontFamily: figureFamily,
    fontSize: 26,
    height: 1.2,
    letterSpacing: -1.0,
    fontFeatures: _tabular,
    fontVariations: _wght(700),
  );

  /// The one number that owns a screen of its own: net worth, a total.
  static final moneyHero = TextStyle(
    fontFamily: figureFamily,
    fontSize: 36,
    height: 1.2,
    letterSpacing: -1.2,
    fontFeatures: _tabular,
    fontVariations: _wght(700),
  );

  /// A headline number inside a card: an account balance, a goal total.
  static final balance = TextStyle(
    fontFamily: figureFamily,
    fontSize: 22,
    height: 1.2,
    letterSpacing: -0.6,
    fontFeatures: _tabular,
    fontVariations: _wght(700),
  );

  /// A secondary number: a metric in a summary row, a subtotal.
  static final moneyMedium = TextStyle(
    fontFamily: figureFamily,
    fontSize: 17,
    height: 1.2,
    letterSpacing: -0.3,
    fontFeatures: _tabular,
    fontVariations: _wght(600),
  );

  /// Trailing amount on a list row.
  static final amount = TextStyle(
    fontFamily: figureFamily,
    fontSize: 14,
    height: 1.25,
    letterSpacing: -0.1,
    fontFeatures: _tabular,
    fontVariations: _wght(600),
  );

  /// A small figure that supports another: "of $2.000.000", a rate, a count.
  static final amountSmall = TextStyle(
    fontFamily: figureFamily,
    fontSize: 12,
    height: 1.25,
    fontFeatures: _tabular,
    fontVariations: _wght(500),
  );

  /// Screen title in the AppBar. Uses the figure family so the header and the
  /// numbers below it read as one voice.
  static final screenTitle = TextStyle(
    fontFamily: figureFamily,
    fontSize: 28,
    height: 1.2,
    letterSpacing: -0.9,
    fontVariations: _wght(700),
  );

  /// Group heading inside a screen ("This month", an account section).
  static final sectionTitle = TextStyle(
    fontFamily: figureFamily,
    fontSize: 17,
    height: 1.2,
    letterSpacing: -0.3,
    fontVariations: _wght(600),
  );

  // ── Words (Open Sans) ─────────────────────────────────────────────────────

  /// Primary row label: a transaction description, an account name.
  static const tileTitle = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  /// Compact card name/label.
  static const cardName = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// Mid-weight value text used in subtitles.
  static const subtitle = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 13,
  );

  /// Secondary line: dates, place, hints.
  static const caption = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12,
  );

  /// Status pill text.
  static const badge = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Field label above an input, or a metric's caption.
  static const label = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  // ── Helper ────────────────────────────────────────────────────────────────

  /// Turns any style into one with tabular figures in the figure family.
  /// For the rare spot that needs a size the roles above don't cover.
  static TextStyle tabular(double size, {double weight = 600}) => TextStyle(
        fontFamily: figureFamily,
        fontSize: size,
        fontFeatures: _tabular,
        fontVariations: _wght(weight),
      );
}
