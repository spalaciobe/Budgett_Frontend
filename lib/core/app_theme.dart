import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_spacing.dart';
import 'app_text.dart';

/// The app's colour and component theme.
///
/// ## One accent, four meanings
///
/// The palette used to carry five accents (teal, lime, peach, lavender, red)
/// with no agreed job, and the two themes disagreed about them: `secondary`
/// was lavender in light and lime in dark, so the same widget changed hue when
/// you flipped the theme. Every colour now has exactly one meaning, identical
/// in both themes:
///
/// | Role | Colour | Means |
/// |---|---|---|
/// | `primary` | teal | the brand; actions, selection, focus |
/// | `secondary` | lavender | transfers (money moving between your own accounts) |
/// | `tertiary` | peach | goals and informational highlights |
/// | `error` | red | expenses, negatives, destructive actions |
/// | `semantic.positive` | green | income, gains |
/// | `semantic.warning` | orange | pending, near-limit |
///
/// The lime `#CEF7A0` was dropped: it had no meaning left once the table above
/// existed, and it was what made dark mode's icons read as a different app.
///
/// ## Surfaces have edges
///
/// Light mode used to paint white cards on a `#F8F9FA` background with
/// `elevation: 0` and no border — a contrast ratio of about 1.03:1, so card
/// boundaries were invisible and screens lost their structure. Cards now sit
/// on a slightly deeper, faintly teal-tinted background *and* carry a hairline
/// border, in both themes. That hairline is the app's structural device: it
/// says "this is one object", and it is the only decoration a card gets.
class AppTheme {
  /// The palette every theme below is built from.
  ///
  /// Swappable so alternatives can be compared without editing the dozen
  /// places the brand colour appears. Changing this one line changes the app.
  static AppPalette palette = AppPalette.teal;

  static Color get _primary => palette.brand;
  static Color get _onPrimary => palette.onBrand;
  static Color get _lavender => palette.transfer;
  static Color get _peach => palette.highlight;
  static Color get _error => palette.negative;

  static Color get _lightBackground => palette.lightBackground;
  static Color get _lightSurface => palette.lightSurface;
  static Color get _lightSurfaceVariant => palette.lightSurfaceVariant;
  static Color get _lightOutline => palette.lightOutline;
  static Color get _lightOnSurface => palette.lightOnSurface;
  static Color get _lightOnSurfaceVariant => palette.lightOnSurfaceVariant;

  static Color get _darkBackground => palette.darkBackground;
  static Color get _darkSurface => palette.darkSurface;
  static Color get _darkSurfaceVariant => palette.darkSurfaceVariant;
  static Color get _darkOutline => palette.darkOutline;
  static Color get _darkOnSurface => palette.darkOnSurface;
  static Color get _darkOnSurfaceVariant => palette.darkOnSurfaceVariant;

  /// One step tighter than Material's default, where it used to be two.
  /// `VisualDensity.compact` (-2) plus 11px body text made rows physically
  /// hard to hit and visually hard to separate.
  static const VisualDensity _density =
      VisualDensity(horizontal: -1, vertical: -1);

  // ── Text theme ────────────────────────────────────────────────────────────

  /// Maps Material's text roles onto [AppText] so a widget that reaches for
  /// `theme.textTheme.titleMedium` lands on the app's scale instead of
  /// Material's larger default. Figures get Space Grotesk, words Open Sans.
  static TextTheme _textTheme(Color onSurface, Color onSurfaceVariant) {
    return TextTheme(
      displayLarge: AppText.moneyHero,
      displayMedium: AppText.moneyHero,
      displaySmall: AppText.screenTitle,
      headlineLarge: AppText.screenTitle,
      headlineMedium: AppText.screenTitle,
      headlineSmall: AppText.balance,
      titleLarge: AppText.screenTitle,
      titleMedium: AppText.sectionTitle,
      titleSmall: AppText.cardName,
      bodyLarge: AppText.tileTitle,
      bodyMedium: AppText.subtitle,
      bodySmall: AppText.caption,
      labelLarge: AppText.cardName,
      labelMedium: AppText.label,
      labelSmall: AppText.badge,
    ).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    ).copyWith(
      bodySmall: AppText.caption.copyWith(color: onSurfaceVariant),
      labelMedium: AppText.label.copyWith(color: onSurfaceVariant),
      labelSmall: AppText.badge.copyWith(color: onSurfaceVariant),
    );
  }

  // ── Shared component themes ───────────────────────────────────────────────

  static CardThemeData _cardTheme(Color surface, Color outline) {
    return CardThemeData(
      elevation: 0,
      color: surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        side: BorderSide(color: outline),
      ),
    );
  }

  static InputDecorationTheme _inputTheme(
    Color fill,
    Color outline,
    Color hint,
  ) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      border: border(outline),
      enabledBorder: border(outline),
      focusedBorder: border(_primary, 2),
      errorBorder: border(_error),
      focusedErrorBorder: border(_error, 2),
      hintStyle: AppText.subtitle.copyWith(color: hint),
      labelStyle: AppText.subtitle.copyWith(color: hint),
      helperStyle: AppText.caption.copyWith(color: hint),
      errorStyle: AppText.caption.copyWith(color: _error),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  /// Note: no `titleTextStyle`/`subtitleTextStyle` here. Setting them to a
  /// colourless [AppText] role stops `ListTile` from applying the theme's
  /// `onSurface` colour, and the title renders in the default light ink —
  /// invisible on a white card. The text theme already maps `bodyLarge` and
  /// `bodySmall` to the same roles *with* a colour, which is what ListTile
  /// falls back to.
  static ListTileThemeData get _listTileTheme => const ListTileThemeData(
        dense: true,
        visualDensity: _density,
        minVerticalPadding: 7,
        contentPadding: EdgeInsets.symmetric(horizontal: 14),
      );

  /// [fullWidth] drives the one property a theme should be careful with:
  /// `minimumSize.width`.
  ///
  /// `ElevatedButton` has always been full-width in this app, and screens rely
  /// on it. `FilledButton` has not: it is the button that sits *inside* rows,
  /// next to a title or at the end of a card. Handing it
  /// `Size(double.infinity, …)` makes it demand the entire row, which starves
  /// whatever shares that row — a sibling `Expanded` collapses to zero and its
  /// text renders one letter per line. Width belongs to the call site: wrap a
  /// button in `SizedBox(width: double.infinity)` when a screen wants it wide.
  static ButtonStyle _buttonStyle({required bool fullWidth}) =>
      ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: _primary,
        foregroundColor: _onPrimary,
        disabledBackgroundColor: _primary.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white70,
        minimumSize: Size(fullWidth ? double.infinity : 0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AppText.cardName.copyWith(fontSize: 15),
      );

  static NavigationBarThemeData _navBarTheme(
    Color surface,
    Color onSurfaceVariant,
  ) {
    return NavigationBarThemeData(
      height: 62,
      backgroundColor: surface,
      indicatorColor: _primary.withValues(alpha: 0.14),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return AppText.badge.copyWith(
          color: selected ? _primary : onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 23,
          color: selected ? _primary : onSurfaceVariant,
        );
      }),
    );
  }

  static NavigationRailThemeData _navRailTheme(
    Color surface,
    Color onSurface,
    Color onSurfaceVariant,
  ) {
    return NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: _primary.withValues(alpha: 0.14),
      selectedIconTheme: IconThemeData(color: _primary, size: 24),
      unselectedIconTheme: IconThemeData(color: onSurfaceVariant, size: 24),
      selectedLabelTextStyle: AppText.badge.copyWith(color: _primary),
      unselectedLabelTextStyle: AppText.badge.copyWith(color: onSurfaceVariant),
    );
  }

  static SegmentedButtonThemeData _segmentedTheme(Color onSurfaceVariant) {
    return SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(AppText.label),
        side: WidgetStatePropertyAll(BorderSide.none),
        visualDensity: _density,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? _primary
                : onSurfaceVariant),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? _primary.withValues(alpha: 0.14)
                : Colors.transparent),
      ),
    );
  }

  // ── Themes ────────────────────────────────────────────────────────────────

  static ThemeData get lightTheme {
    final text = _textTheme(_lightOnSurface, _lightOnSurfaceVariant);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      visualDensity: _density,
      scaffoldBackgroundColor: _lightBackground,
      extensions: <ThemeExtension<dynamic>>[AppSemanticColors.light],
      colorScheme: ColorScheme.light(
        primary: _primary,
        onPrimary: _onPrimary,
        primaryContainer: Color(0xFFD3EBE7),
        onPrimaryContainer: Color(0xFF07322D),
        secondary: _lavender,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFEAE0EF),
        onSecondaryContainer: Color(0xFF2F2136),
        tertiary: _peach,
        onTertiary: Color(0xFF3B2410),
        error: _error,
        onError: Colors.white,
        errorContainer: Color(0xFFFBE0E3),
        onErrorContainer: Color(0xFF5C0B16),
        surface: _lightSurface,
        onSurface: _lightOnSurface,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Color(0xFFF7FAF9),
        surfaceContainer: _lightBackground,
        surfaceContainerHigh: _lightSurfaceVariant,
        surfaceContainerHighest: _lightSurfaceVariant,
        onSurfaceVariant: _lightOnSurfaceVariant,
        outline: Color(0xFF9AA5A2),
        outlineVariant: _lightOutline,
      ),
      textTheme: text,
      iconTheme: IconThemeData(color: _lightOnSurfaceVariant, size: 22),
      primaryIconTheme: IconThemeData(color: _primary),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: _lightOnSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 58,
        titleTextStyle: AppText.screenTitle.copyWith(color: _lightOnSurface),
        iconTheme: IconThemeData(color: _lightOnSurfaceVariant),
      ),
      cardTheme: _cardTheme(_lightSurface, _lightOutline),
      listTileTheme: _listTileTheme,
      dividerTheme: DividerThemeData(
        color: _lightOutline,
        space: 8,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _lightSurfaceVariant,
        selectedColor: _primary.withValues(alpha: 0.16),
        side: BorderSide.none,
        labelStyle: AppText.label.copyWith(color: _lightOnSurface),
        secondaryLabelStyle: AppText.label.copyWith(color: _primary),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      inputDecorationTheme: _inputTheme(
        _lightSurfaceVariant,
        Colors.transparent,
        _lightOnSurfaceVariant,
      ),
      elevatedButtonTheme:
          ElevatedButtonThemeData(style: _buttonStyle(fullWidth: true)),
      filledButtonTheme:
          FilledButtonThemeData(style: _buttonStyle(fullWidth: false)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primary,
          side: BorderSide(color: _lightOutline),
          minimumSize: const Size(0, 44),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: AppText.cardName,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primary,
          textStyle: AppText.cardName,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _primary,
        foregroundColor: _onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 2,
      ),
      navigationBarTheme: _navBarTheme(_lightSurface, _lightOnSurfaceVariant),
      navigationRailTheme: _navRailTheme(
        _lightSurface,
        _lightOnSurface,
        _lightOnSurfaceVariant,
      ),
      segmentedButtonTheme: _segmentedTheme(_lightOnSurfaceVariant),
      dialogTheme: DialogThemeData(
        backgroundColor: _lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _lightOutline),
        ),
        titleTextStyle: AppText.sectionTitle.copyWith(color: _lightOnSurface),
        contentTextStyle: AppText.subtitle.copyWith(color: _lightOnSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF16201E),
        contentTextStyle: AppText.subtitle.copyWith(color: Colors.white),
        actionTextColor: _peach,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF16201E),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: AppText.caption.copyWith(color: Colors.white),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _primary,
        linearMinHeight: 6,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? _primary : null),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: _primary,
        thumbColor: _primary,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: _primary,
        unselectedLabelColor: _lightOnSurfaceVariant,
        labelStyle: AppText.cardName,
        unselectedLabelStyle: AppText.cardName,
        indicatorColor: _primary,
        dividerColor: _lightOutline,
      ),
    );
  }

  static ThemeData get darkTheme {
    final text = _textTheme(_darkOnSurface, _darkOnSurfaceVariant);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      visualDensity: _density,
      scaffoldBackgroundColor: _darkBackground,
      extensions: <ThemeExtension<dynamic>>[AppSemanticColors.dark],
      colorScheme: ColorScheme.dark(
        primary: _primary,
        onPrimary: _onPrimary,
        primaryContainer: Color(0xFF12413B),
        onPrimaryContainer: Color(0xFFB8E7E0),
        secondary: _lavender,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFF392941),
        onSecondaryContainer: Color(0xFFDCC8E6),
        tertiary: _peach,
        onTertiary: Color(0xFF3B2410),
        error: _error,
        onError: Colors.white,
        errorContainer: Color(0xFF4A1119),
        onErrorContainer: Color(0xFFFFCDD3),
        surface: _darkSurface,
        onSurface: _darkOnSurface,
        surfaceContainerLowest: Color(0xFF0E1014),
        surfaceContainerLow: Color(0xFF181C22),
        surfaceContainer: _darkSurface,
        surfaceContainerHigh: _darkSurfaceVariant,
        surfaceContainerHighest: _darkSurfaceVariant,
        onSurfaceVariant: _darkOnSurfaceVariant,
        outline: Color(0xFF6B7581),
        outlineVariant: _darkOutline,
      ),
      textTheme: text,
      // Icons follow the text colour, not an accent. The old theme painted
      // every icon lime here and left them near-black in light mode, which is
      // what made the two themes read as different apps.
      iconTheme: IconThemeData(color: _darkOnSurfaceVariant, size: 22),
      primaryIconTheme: IconThemeData(color: _primary),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: _darkOnSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 58,
        titleTextStyle: AppText.screenTitle.copyWith(color: _darkOnSurface),
        iconTheme: IconThemeData(color: _darkOnSurfaceVariant),
      ),
      cardTheme: _cardTheme(_darkSurface, _darkOutline),
      listTileTheme: _listTileTheme,
      dividerTheme: DividerThemeData(
        color: _darkOutline,
        space: 8,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _darkSurfaceVariant,
        selectedColor: _primary.withValues(alpha: 0.22),
        side: BorderSide.none,
        labelStyle: AppText.label.copyWith(color: _darkOnSurface),
        secondaryLabelStyle: AppText.label.copyWith(color: _primary),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      inputDecorationTheme: _inputTheme(
        _darkSurfaceVariant,
        Colors.transparent,
        _darkOnSurfaceVariant,
      ),
      elevatedButtonTheme:
          ElevatedButtonThemeData(style: _buttonStyle(fullWidth: true)),
      filledButtonTheme:
          FilledButtonThemeData(style: _buttonStyle(fullWidth: false)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primary,
          side: BorderSide(color: _darkOutline),
          minimumSize: const Size(0, 44),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: AppText.cardName,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primary,
          textStyle: AppText.cardName,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _primary,
        foregroundColor: _onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 2,
      ),
      navigationBarTheme: _navBarTheme(_darkSurface, _darkOnSurfaceVariant),
      navigationRailTheme: _navRailTheme(
        _darkSurface,
        _darkOnSurface,
        _darkOnSurfaceVariant,
      ),
      segmentedButtonTheme: _segmentedTheme(_darkOnSurfaceVariant),
      dialogTheme: DialogThemeData(
        backgroundColor: _darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _darkOutline),
        ),
        titleTextStyle: AppText.sectionTitle.copyWith(color: _darkOnSurface),
        contentTextStyle: AppText.subtitle.copyWith(color: _darkOnSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _darkSurfaceVariant,
        contentTextStyle: AppText.subtitle.copyWith(color: _darkOnSurface),
        actionTextColor: _peach,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _darkSurfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: AppText.caption.copyWith(color: _darkOnSurface),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _primary,
        linearMinHeight: 6,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? _primary : null),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: _primary,
        thumbColor: _primary,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: _primary,
        unselectedLabelColor: _darkOnSurfaceVariant,
        labelStyle: AppText.cardName,
        unselectedLabelStyle: AppText.cardName,
        indicatorColor: _primary,
        dividerColor: _darkOutline,
      ),
    );
  }
}

/// Semantic finance colors that aren't part of Material's [ColorScheme].
///
/// "Positive" (income / gains) and "warning" (pending / near-limit) need a
/// single, theme-aware source of truth so the same concept isn't painted with
/// a different raw `Colors.green`/`Colors.orange` on every screen. "Negative"
/// already maps cleanly to [ColorScheme.error], so it's not duplicated here.
/// [muted] is the fourth: the grey for de-emphasised text and disabled rows,
/// which used to be a raw `Colors.grey` in ~35 places and therefore ignored
/// the theme entirely.
/// Values are chosen for ~AA contrast against each theme's surface.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color positive;
  final Color warning;
  final Color muted;

  const AppSemanticColors({
    required this.positive,
    required this.warning,
    required this.muted,
  });

  /// Darker shades that keep contrast on the light surface (white).
  static final light = AppSemanticColors(
    positive: AppTheme.palette.positiveLight,
    warning: AppTheme.palette.warningLight,
    muted: AppTheme.palette.lightOnSurfaceVariant,
  );

  /// Lighter shades that keep contrast on the dark surface.
  static final dark = AppSemanticColors(
    positive: AppTheme.palette.positiveDark,
    warning: AppTheme.palette.warningDark,
    muted: AppTheme.palette.darkOnSurfaceVariant,
  );

  @override
  AppSemanticColors copyWith({Color? positive, Color? warning, Color? muted}) =>
      AppSemanticColors(
        positive: positive ?? this.positive,
        warning: warning ?? this.warning,
        muted: muted ?? this.muted,
      );

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      positive: Color.lerp(positive, other.positive, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension AppSemanticColorsX on BuildContext {
  /// Theme-aware semantic finance colors. Falls back to the dark palette if the
  /// extension somehow isn't registered.
  AppSemanticColors get semantic =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.dark;

  // Shorthands for the five colours that carry meaning in this app. They exist
  // so that painting a number the right colour is shorter than reaching for a
  // raw `Colors.green` — the reason ~146 raw Material colours had accumulated
  // across the UI, each one ignoring the theme it was painted in.

  /// Income, gains, money coming in.
  Color get positive => semantic.positive;

  /// Expenses, losses, money going out, destructive actions.
  Color get negative => Theme.of(this).colorScheme.error;

  /// Pending, near-limit, needs attention but isn't wrong yet.
  Color get warning => semantic.warning;

  /// De-emphasised text, disabled rows, inactive icons.
  Color get muted => semantic.muted;

  /// The brand accent: actions, selection, informational highlights.
  Color get brand => Theme.of(this).colorScheme.primary;
}
