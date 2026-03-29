import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";

const _keyCurrency = "settings_currency";
const _keyDarkMode = "settings_dark_mode";

class CurrencyNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCurrency) ?? "COP";
  }

  Future<void> setCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrency, currency);
    state = AsyncData(currency);
  }
}

final currencyProvider = AsyncNotifierProvider<CurrencyNotifier, String>(CurrencyNotifier.new);

class ThemeModeNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDarkMode) ?? false;
  }

  Future<void> setDarkMode(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, isDark);
    state = AsyncData(isDark);
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeNotifier, bool>(ThemeModeNotifier.new);
