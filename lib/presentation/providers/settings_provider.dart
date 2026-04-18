import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";

const _keyCurrency = "settings_currency";
const _keyDarkMode = "settings_dark_mode";
const _keyCcNotificationsEnabled = "settings_cc_notifications_enabled";
const _keyCcNotificationsDaysBefore = "settings_cc_notifications_days_before";
const _keyAccountSort = "settings_account_sort";

enum AccountSortOption {
  custom,
  nameAsc,
  nameDesc,
  balanceDesc,
  balanceAsc,
  typeAsc;

  String get label => switch (this) {
        AccountSortOption.custom => "Custom order",
        AccountSortOption.nameAsc => "Name (A–Z)",
        AccountSortOption.nameDesc => "Name (Z–A)",
        AccountSortOption.balanceDesc => "Balance (high to low)",
        AccountSortOption.balanceAsc => "Balance (low to high)",
        AccountSortOption.typeAsc => "Type",
      };
}

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

class ThemeModeNotifier extends AsyncNotifier<bool?> {
  @override
  Future<bool?> build() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keyDarkMode)) return null; // null = seguir sistema
    return prefs.getBool(_keyDarkMode);
  }

  Future<void> setDarkMode(bool isDark) async {
    state = AsyncData(isDark);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, isDark);
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeNotifier, bool?>(ThemeModeNotifier.new);

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

class AccountSortNotifier extends AsyncNotifier<AccountSortOption> {
  @override
  Future<AccountSortOption> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyAccountSort);
    return AccountSortOption.values.firstWhere(
      (o) => o.name == stored,
      orElse: () => AccountSortOption.custom,
    );
  }

  Future<void> setSort(AccountSortOption option) async {
    state = AsyncData(option); // optimistic update
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccountSort, option.name);
  }
}

final accountSortProvider =
    AsyncNotifierProvider<AccountSortNotifier, AccountSortOption>(
        AccountSortNotifier.new);

