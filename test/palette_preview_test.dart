// Palette preview — renders the same screens under each AppPalette and dumps
// PNGs to test/screenshots/palette_<name>_<screen>.png.
//
// Not a test of behaviour: it exists so a palette can be judged against real
// screens instead of a row of swatches. A colour that looks striking on its
// own can still bury a balance or wash out a "pending" badge, and that only
// shows up on a screen with figures, badges and a filled button on it.
//
// Run: flutter test test/palette_preview_test.dart


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budgett_frontend/core/app_palette.dart';
import 'package:budgett_frontend/core/app_theme.dart';
import 'package:budgett_frontend/presentation/screens/accounts_screen.dart';
import 'package:budgett_frontend/presentation/screens/home_screen.dart';
import 'package:budgett_frontend/presentation/screens/plan_screen.dart';

import 'ui_smoke_test.dart' show captureBoundary, financeOverrides, loadAppFonts;

const _phone = Size(390, 844);

final _screens = <String, Widget Function()>{
  'transactions': () => const HomeScreen(),
  'accounts': () => const AccountsScreen(),
  'plan': () => const PlanScreen(),
};

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    await initializeDateFormatting('es');
    await initializeDateFormatting('en_US');
    SharedPreferences.setMockInitialValues({});
    await loadAppFonts();
  });

  for (final palette in AppPalette.all) {
    for (final entry in _screens.entries) {
      testWidgets('${palette.name} · ${entry.key}', (tester) async {
        tester.view.physicalSize = _phone;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const captureKey = ValueKey('palette_capture');
        await tester.pumpWidget(
          ProviderScope(
            overrides: financeOverrides(),
            child: MaterialApp(
              // Dark only: this is the mode the palettes are being judged in.
              theme: AppTheme(palette).dark,
              home: RepaintBoundary(
                key: captureKey,
                child: entry.value(),
              ),
            ),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        final slug = palette.name.toLowerCase().replaceAll(' ', '_');
        final out = await captureBoundary(
          tester,
          captureKey,
          'palette_${slug}_${entry.key}',
        );
        expect(out.existsSync(), isTrue);
        expect(out.lengthSync(), greaterThan(0));
      });
    }
  }
}
