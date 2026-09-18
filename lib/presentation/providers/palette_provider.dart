import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_palette.dart';

/// The palette the app is painted in, remembered across launches.
///
/// It lives here rather than as a constant because these palettes are
/// concepts: judging one takes a few days of real use, and shipping a build
/// per candidate makes that impossible. Switching is instant and local — no
/// account setting, no server round-trip.
class PaletteController extends Notifier<AppPalette> {
  static const _key = 'app_palette';

  @override
  AppPalette build() {
    _restore();
    return AppPalette.lime;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored != null) state = AppPalette.byName(stored);
  }

  Future<void> select(AppPalette palette) async {
    state = palette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, palette.name);
  }
}

final paletteProvider =
    NotifierProvider<PaletteController, AppPalette>(PaletteController.new);
