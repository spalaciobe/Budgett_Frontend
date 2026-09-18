import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:budgett_frontend/core/services/capture_ingest_service.dart";

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


// ─── message capture ─────────────────────────────────────────────────────────

const _keyCaptureAutoPost = "settings_capture_auto_post";
const _keyCaptureDedupWindow = "settings_capture_dedup_window_minutes";
const _keyCaptureMinConfidence = "settings_capture_min_confidence";
const _keyCaptureMaxAmount = "settings_capture_auto_post_max_amount";

/// Tuning for the notification/SMS capture pipeline.
///
/// Only the decision thresholds live here. Whether capture is switched on at
/// all, and whether SMS and location are included, is stored natively (the
/// notification listener and SMS receiver read it with no Flutter engine
/// attached), so `captureStatusProvider` is the source of truth for those.
class CaptureSettingsNotifier extends AsyncNotifier<CaptureSettings> {
  @override
  Future<CaptureSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return CaptureSettings(
      autoPostEnabled: prefs.getBool(_keyCaptureAutoPost) ?? true,
      dedupWindow:
          Duration(minutes: prefs.getInt(_keyCaptureDedupWindow) ?? 10),
      minConfidence: prefs.getDouble(_keyCaptureMinConfidence) ?? 0.8,
      autoPostMaxAmount: prefs.getDouble(_keyCaptureMaxAmount) ?? 0,
    );
  }

  Future<void> setAutoPost(bool enabled) async {
    _apply((current) => current.copyWith(autoPostEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCaptureAutoPost, enabled);
  }

  Future<void> setDedupWindowMinutes(int minutes) async {
    _apply((current) =>
        current.copyWith(dedupWindow: Duration(minutes: minutes)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCaptureDedupWindow, minutes);
  }

  Future<void> setMinConfidence(double value) async {
    _apply((current) => current.copyWith(minConfidence: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCaptureMinConfidence, value);
  }

  Future<void> setAutoPostMaxAmount(double value) async {
    _apply((current) => current.copyWith(autoPostMaxAmount: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCaptureMaxAmount, value);
  }

  /// Optimistic update — the UI responds before the write lands, matching the
  /// other notifiers in this file.
  void _apply(CaptureSettings Function(CaptureSettings current) transform) {
    state = AsyncData(transform(state.valueOrNull ?? const CaptureSettings()));
  }
}

final captureSettingsProvider =
    AsyncNotifierProvider<CaptureSettingsNotifier, CaptureSettings>(
        CaptureSettingsNotifier.new);
