import "package:flutter_test/flutter_test.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:budgett_frontend/core/services/notification_service.dart";
import "package:budgett_frontend/presentation/providers/settings_provider.dart";

void main() {
  group("computeNotificationDate", () {
    test("returns correct date for normal case (3 days before)", () {
      final paymentDate = DateTime.now().add(const Duration(days: 10));
      final result = CreditCardPaymentNotificationService
          .computeNotificationDate(paymentDate, 3);

      expect(result, isNotNull);
      final expected = DateTime(
          paymentDate.year, paymentDate.month, paymentDate.day - 3, 9, 0);
      expect(result!.year, expected.year);
      expect(result.month, expected.month);
      expect(result.day, expected.day);
      expect(result.hour, 9);
      expect(result.minute, 0);
    });

    test("returns null when payment date is in the past", () {
      final paymentDate = DateTime.now().subtract(const Duration(days: 5));
      final result = CreditCardPaymentNotificationService
          .computeNotificationDate(paymentDate, 3);

      expect(result, isNull);
    });

    test("returns null when notification date would be in the past", () {
      // Payment is tomorrow, but we want 3 days before → notification was 2 days ago
      final paymentDate = DateTime.now().add(const Duration(days: 1));
      final result = CreditCardPaymentNotificationService
          .computeNotificationDate(paymentDate, 3);

      expect(result, isNull);
    });

    test("daysBefore=1 works correctly", () {
      final paymentDate = DateTime.now().add(const Duration(days: 5));
      final result = CreditCardPaymentNotificationService
          .computeNotificationDate(paymentDate, 1);

      expect(result, isNotNull);
      final expected = DateTime(
          paymentDate.year, paymentDate.month, paymentDate.day, 9, 0)
          .subtract(const Duration(days: 1));
      expect(result!.year, expected.year);
      expect(result.month, expected.month);
      expect(result.day, expected.day);
    });

    test("daysBefore=30 works correctly", () {
      final paymentDate = DateTime.now().add(const Duration(days: 60));
      final result = CreditCardPaymentNotificationService
          .computeNotificationDate(paymentDate, 30);

      expect(result, isNotNull);
      final expected = DateTime(
          paymentDate.year, paymentDate.month, paymentDate.day, 9, 0)
          .subtract(const Duration(days: 30));
      expect(result!.year, expected.year);
      expect(result.month, expected.month);
      expect(result.day, expected.day);
    });

    test("payment today with daysBefore > 0 returns null (notification is past)", () {
      // Payment is today; any daysBefore > 0 means the notification date is yesterday or earlier
      final now = DateTime.now();
      final paymentDate = DateTime(now.year, now.month, now.day);
      final result = CreditCardPaymentNotificationService
          .computeNotificationDate(paymentDate, 1);

      expect(result, isNull);
    });

    test("end of month boundary: payment on March 1 with daysBefore=3 notifies Feb 26", () {
      // Use a date far in the future to ensure it's not in the past
      final paymentDate = DateTime(2099, 3, 1);
      final result = CreditCardPaymentNotificationService
          .computeNotificationDate(paymentDate, 3);

      expect(result, isNotNull);
      expect(result!.year, 2099);
      expect(result.month, 2);
      expect(result.day, 26);
      expect(result.hour, 9);
    });

    test("end of month boundary: payment on March 1 with daysBefore=1 notifies Feb 28", () {
      final paymentDate = DateTime(2099, 3, 1);
      final result = CreditCardPaymentNotificationService
          .computeNotificationDate(paymentDate, 1);

      expect(result, isNotNull);
      expect(result!.month, 2);
      expect(result.day, 28);
    });

    test("leap year boundary: payment on March 1 2096 with daysBefore=1 notifies Feb 29", () {
      // 2096 is a leap year
      final paymentDate = DateTime(2096, 3, 1);
      final result = CreditCardPaymentNotificationService
          .computeNotificationDate(paymentDate, 1);

      expect(result, isNotNull);
      expect(result!.month, 2);
      expect(result.day, 29);
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

    test("persists enabled state across container instances", () async {
      final container1 = ProviderContainer();
      await container1.read(ccNotificationsEnabledProvider.notifier).setEnabled(false);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final saved = await container2.read(ccNotificationsEnabledProvider.future);
      expect(saved, false);
    });

    test("setEnabled updates state immediately", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(ccNotificationsEnabledProvider.notifier).setEnabled(false);
      expect(container.read(ccNotificationsEnabledProvider).value, false);
    });

    test("can re-enable after disabling", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(ccNotificationsEnabledProvider.notifier).setEnabled(false);
      await container.read(ccNotificationsEnabledProvider.notifier).setEnabled(true);
      expect(container.read(ccNotificationsEnabledProvider).value, true);
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

    test("persists days-before value across container instances", () async {
      final container1 = ProviderContainer();
      await container1.read(ccNotificationDaysBeforeProvider.notifier).setDaysBefore(7);
      container1.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final saved = await container2.read(ccNotificationDaysBeforeProvider.future);
      expect(saved, 7);
    });

    test("setDaysBefore updates state immediately", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(ccNotificationDaysBeforeProvider.notifier).setDaysBefore(10);
      expect(container.read(ccNotificationDaysBeforeProvider).value, 10);
    });

    test("supports boundary value 1", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(ccNotificationDaysBeforeProvider.notifier).setDaysBefore(1);
      expect(container.read(ccNotificationDaysBeforeProvider).value, 1);
    });

    test("supports boundary value 30", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(ccNotificationDaysBeforeProvider.notifier).setDaysBefore(30);
      expect(container.read(ccNotificationDaysBeforeProvider).value, 30);
    });
  });
}
