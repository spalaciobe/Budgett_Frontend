import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import '../../data/models/account_model.dart';
import '../../data/models/bank_model.dart';
import '../utils/credit_card_calculator.dart';

class CreditCardPaymentNotificationService {
  static final CreditCardPaymentNotificationService _instance =
      CreditCardPaymentNotificationService._internal();

  factory CreditCardPaymentNotificationService() => _instance;

  CreditCardPaymentNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(initSettings);

    // Request permissions on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Computes the notification date: paymentDate minus [daysBefore] days at 9:00 AM.
  /// Returns null if the resulting date is in the past.
  static DateTime? computeNotificationDate(
      DateTime paymentDate, int daysBefore) {
    final notificationDate =
        DateTime(paymentDate.year, paymentDate.month, paymentDate.day, 9, 0)
            .subtract(Duration(days: daysBefore));

    if (notificationDate.isBefore(DateTime.now())) {
      return null;
    }

    return notificationDate;
  }

  Future<void> schedulePaymentAlerts(
    List<Account> accounts,
    List<Bank> banks,
    int daysBeforeNotify,
  ) async {
    await cancelAll();

    final now = DateTime.now();
    final bankMap = {for (final b in banks) b.id: b};

    for (final account in accounts) {
      if (account.type != 'credit_card' || account.creditCardRules == null) {
        continue;
      }

      final rules = account.creditCardRules!;
      final bank = bankMap[rules.bankId];
      if (bank == null) continue;

      // Calculate cutoff for current month, then payment date
      final cutoffDate = CreditCardCalculator.calculateCutoffDate(
          rules, bank, now.year, now.month);
      var paymentDate =
          CreditCardCalculator.calculatePaymentDate(rules, bank, cutoffDate);

      // If payment date is in the past, try next month
      if (paymentDate.isBefore(now)) {
        final nextMonth = DateTime(now.year, now.month + 1);
        final nextCutoff = CreditCardCalculator.calculateCutoffDate(
            rules, bank, nextMonth.year, nextMonth.month);
        paymentDate =
            CreditCardCalculator.calculatePaymentDate(rules, bank, nextCutoff);
      }

      final notificationDate =
          computeNotificationDate(paymentDate, daysBeforeNotify);
      if (notificationDate == null) continue;

      final notificationId = account.id.hashCode.abs() % 2147483647;

      await _plugin.zonedSchedule(
        notificationId,
        'Pago de tarjeta de crédito',
        'Tu tarjeta ${account.name} vence en $daysBeforeNotify días',
        tz.TZDateTime.from(notificationDate, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'cc_payment_alerts',
            'Alertas de pago de tarjeta',
            channelDescription:
                'Notificaciones de fechas de pago de tarjetas de crédito',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
