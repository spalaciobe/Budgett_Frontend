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

    test("setCurrency updates state immediately", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(currencyProvider.notifier).setCurrency("EUR");
      final val = container.read(currencyProvider).value;
      expect(val, "EUR");
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

    test("defaults to false (light mode) when no saved value", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final result = await container.read(themeModeProvider.future);
      expect(result, false);
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

    test("setDarkMode updates state immediately", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).setDarkMode(true);
      expect(container.read(themeModeProvider).value, true);
    });
  });
}
