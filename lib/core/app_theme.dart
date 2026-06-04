import 'package:flutter/material.dart';

class AppTheme {
  // User provided palette
  static const Color _primary = Color(0xFF1B998B); // Teal
  static const Color _secondary = Color(0xFFCEF7A0); // Light Green
  static const Color _tertiary = Color(0xFFFFBF81); // Peach
  static const Color _accent = Color(0xFF8D6A9F); // Lavender
  static const Color _error = Color(0xFFDC3248); // Red
  
  // Custom Dark Palette for Premium Feeel
  static const Color _darkBackground = Color(0xFF121418);
  static const Color _darkSurface = Color(0xFF1E2229);
  static const Color _darkSurfaceVariant = Color(0xFF2A2F3A);

  // Open Sans is bundled in assets/fonts/ — no runtime fetching, fast cold start,
  // works offline, and widget tests don't hang on network calls.
  static const String _fontFamily = 'OpenSans';
  static final TextTheme _textTheme =
      Typography.material2021().black.apply(fontFamily: _fontFamily);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      visualDensity: VisualDensity.compact,
      extensions: const <ThemeExtension<dynamic>>[AppSemanticColors.light],
      colorScheme: const ColorScheme.light(
        primary: _primary,
        onPrimary: Colors.white,
        secondary: _accent,
        onSecondary: Colors.white,
        tertiary: _tertiary,
        error: _error,
        surface: Color(0xFFF8F9FA),
        onSurface: Color(0xFF1A1C1E),
      ),
      textTheme: _textTheme,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 48,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
        margin: EdgeInsets.zero,
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 4,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      dividerTheme: const DividerThemeData(
        space: 8,
        thickness: 1,
      ),
      chipTheme: const ChipThemeData(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: _darkBackground,
      extensions: const <ThemeExtension<dynamic>>[AppSemanticColors.dark],
      colorScheme: const ColorScheme.dark(
        primary: _primary,
        onPrimary: Colors.white,
        secondary: _secondary,
        onSecondary: Color(0xFF0F1115),
        tertiary: _tertiary,
        onTertiary: Color(0xFF0F1115),
        surface: _darkSurface,
        onSurface: Color(0xFFECEDEE),
        surfaceContainerHighest: _darkSurfaceVariant,
        error: _error,
        onError: Colors.white,
      ),
      textTheme: _textTheme.apply(
        bodyColor: const Color(0xFFECEDEE),
        displayColor: const Color(0xFFECEDEE),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        toolbarHeight: 48,
        iconTheme: const IconThemeData(color: Color(0xFFECEDEE)),
        titleTextStyle: TextStyle(
          color: const Color(0xFFECEDEE),
          fontSize: 22,
          fontWeight: FontWeight.bold,
          fontFamily: _textTheme.bodyLarge?.fontFamily,
        ),
      ),
      cardTheme: CardThemeData(
        color: _darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 4,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      dividerTheme: DividerThemeData(
        color: _darkSurfaceVariant,
        space: 8,
        thickness: 1,
      ),
      chipTheme: const ChipThemeData(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurfaceVariant,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        hintStyle: TextStyle(color: Colors.grey.shade500),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      iconTheme: const IconThemeData(
        color: _secondary,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _darkSurface,
        selectedItemColor: _primary,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
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
/// Values are chosen for ~AA contrast against each theme's surface.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color positive;
  final Color warning;

  const AppSemanticColors({required this.positive, required this.warning});

  /// Darker shades that keep contrast on the light surface (near-white).
  static const light = AppSemanticColors(
    positive: Color(0xFF2E7D32), // green 800
    warning: Color(0xFFC2410C), // burnt orange
  );

  /// Lighter shades that keep contrast on the dark surface (#1E2229).
  static const dark = AppSemanticColors(
    positive: Color(0xFF66BB6A), // green 400
    warning: Color(0xFFFFB74D), // orange 300
  );

  @override
  AppSemanticColors copyWith({Color? positive, Color? warning}) =>
      AppSemanticColors(
        positive: positive ?? this.positive,
        warning: warning ?? this.warning,
      );

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      positive: Color.lerp(positive, other.positive, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension AppSemanticColorsX on BuildContext {
  /// Theme-aware semantic finance colors. Falls back to the dark palette if the
  /// extension somehow isn't registered.
  AppSemanticColors get semantic =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.dark;
}
