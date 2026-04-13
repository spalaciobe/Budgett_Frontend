import "package:flutter_test/flutter_test.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:budgett_frontend/presentation/providers/settings_provider.dart";

void main() {
  group("CurrencyNotifier", () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test("defaults to COP when no saved value", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final result = await container.read(currencyProvider.future);
      expect(result, "COP");
    });

    test("persists currency across container instances", () async {
      final container1 = ProviderContainer();
      await container1.read(currencyProvider.notifier).setCurrency("USD");
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final saved = await container2.read(currencyProvider.future);
      expect(saved, "USD");
    });

    test("setCurrency updates state immediately (optimistic)", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Wait for initial build
      await container.read(currencyProvider.future);
      // setCurrency updates state before prefs write completes
      final future = container.read(currencyProvider.notifier).setCurrency("EUR");
      // State should be updated immediately (before awaiting)
      expect(container.read(currencyProvider).value, "EUR");
      await future;
      expect(container.read(currencyProvider).value, "EUR");
    });

    test("supports all valid currencies", () async {
      final currencies = ["USD", "EUR", "GBP", "JPY", "COP", "MXN"];
      for (final c in currencies) {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(currencyProvider.notifier).setCurrency(c);
        expect(container.read(currencyProvider).value, c);
      }
    });
  });

  group("ThemeModeNotifier", () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test("defaults to null (follow system) when no saved value", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final result = await container.read(themeModeProvider.future);
      expect(result, null);
    });

    test("persists dark mode across container instances", () async {
      final container1 = ProviderContainer();
      await container1.read(themeModeProvider.notifier).setDarkMode(true);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final saved = await container2.read(themeModeProvider.future);
      expect(saved, true);
    });

    test("setDarkMode false persists light mode", () async {
      SharedPreferences.setMockInitialValues({"settings_dark_mode": true});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).setDarkMode(false);
      expect(container.read(themeModeProvider).value, false);
    });

    test("setDarkMode updates state immediately (optimistic)", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Wait for initial build
      await container.read(themeModeProvider.future);
      // Optimistic update: state should be set before prefs write
      final future = container.read(themeModeProvider.notifier).setDarkMode(true);
      expect(container.read(themeModeProvider).value, true);
      await future;
      expect(container.read(themeModeProvider).value, true);
    });

    test("toggle dark→light updates state immediately", () async {
      SharedPreferences.setMockInitialValues({"settings_dark_mode": true});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.future);
      final future = container.read(themeModeProvider.notifier).setDarkMode(false);
      expect(container.read(themeModeProvider).value, false);
      await future;
      expect(container.read(themeModeProvider).value, false);
    });
  });

  group("CcNotificationsEnabledNotifier", () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test("defaults to true when no saved value", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final result = await container.read(ccNotificationsEnabledProvider.future);
      expect(result, true);
    });

    test("setEnabled updates state immediately (optimistic)", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(ccNotificationsEnabledProvider.future);
      final future =
          container.read(ccNotificationsEnabledProvider.notifier).setEnabled(false);
      expect(container.read(ccNotificationsEnabledProvider).value, false);
      await future;
    });

    test("persists across containers", () async {
      final container1 = ProviderContainer();
      await container1.read(ccNotificationsEnabledProvider.notifier).setEnabled(false);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      expect(await container2.read(ccNotificationsEnabledProvider.future), false);
    });
  });

  group("CcNotificationDaysBeforeNotifier", () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test("defaults to 3 when no saved value", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final result = await container.read(ccNotificationDaysBeforeProvider.future);
      expect(result, 3);
    });

    test("setDaysBefore updates state immediately (optimistic)", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(ccNotificationDaysBeforeProvider.future);
      final future =
          container.read(ccNotificationDaysBeforeProvider.notifier).setDaysBefore(7);
      expect(container.read(ccNotificationDaysBeforeProvider).value, 7);
      await future;
    });

    test("edge case: days = 1 (minimum)", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(ccNotificationDaysBeforeProvider.notifier).setDaysBefore(1);
      expect(container.read(ccNotificationDaysBeforeProvider).value, 1);
    });

    test("edge case: days = 30 (maximum)", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(ccNotificationDaysBeforeProvider.notifier).setDaysBefore(30);
      expect(container.read(ccNotificationDaysBeforeProvider).value, 30);
    });

    test("persists across containers", () async {
      final container1 = ProviderContainer();
      await container1.read(ccNotificationDaysBeforeProvider.notifier).setDaysBefore(14);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      expect(await container2.read(ccNotificationDaysBeforeProvider.future), 14);
    });
  });
}
