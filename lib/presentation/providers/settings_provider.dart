import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";

const _keyCurrency = "settings_currency";
const _keyDarkMode = "settings_dark_mode";
const _keyCcNotificationsEnabled = "settings_cc_notifications_enabled";
const _keyCcNotificationsDaysBefore = "settings_cc_notifications_days_before";

class CurrencyNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCurrency) ?? "COP";
  }

  Future<void> setCurrency(String currency) async {
    state = AsyncData(currency); // optimistic update — UI responds instantly
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrency, currency);
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
    state = AsyncData(isDark); // optimistic update — theme switches instantly
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, isDark);
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeNotifier, bool>(ThemeModeNotifier.new);

class CcNotificationsEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCcNotificationsEnabled) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled); // optimistic update
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCcNotificationsEnabled, enabled);
  }
}

final ccNotificationsEnabledProvider =
    AsyncNotifierProvider<CcNotificationsEnabledNotifier, bool>(
        CcNotificationsEnabledNotifier.new);

class CcNotificationDaysBeforeNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyCcNotificationsDaysBefore) ?? 3;
  }

  Future<void> setDaysBefore(int days) async {
    state = AsyncData(days); // optimistic update
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCcNotificationsDaysBefore, days);
  }
}

final ccNotificationDaysBeforeProvider =
    AsyncNotifierProvider<CcNotificationDaysBeforeNotifier, int>(
        CcNotificationDaysBeforeNotifier.new);
