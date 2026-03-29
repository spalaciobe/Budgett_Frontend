import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budgett_frontend/core/app_constants.dart';
import 'package:budgett_frontend/presentation/navigation/app_router.dart';
import 'package:budgett_frontend/core/app_theme.dart';
import 'package:budgett_frontend/presentation/providers/settings_provider.dart';
import 'package:budgett_frontend/core/services/notification_service.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/data/repositories/bank_repository.dart';

final ccAlertSchedulerProvider = FutureProvider<void>((ref) async {
  final accountsAsync = ref.watch(accountsProvider);
  final enabledAsync = ref.watch(ccNotificationsEnabledProvider);
  final daysBeforeAsync = ref.watch(ccNotificationDaysBeforeProvider);

  final accounts = accountsAsync.valueOrNull;
  final enabled = enabledAsync.valueOrNull;
  final daysBefore = daysBeforeAsync.valueOrNull;

  if (accounts == null || enabled == null || daysBefore == null) return;

  final service = CreditCardPaymentNotificationService();

  if (!enabled) {
    await service.cancelAll();
    return;
  }

  final banksAsync = ref.watch(banksFutureProvider);
  final banks = banksAsync.valueOrNull;
  if (banks == null) return;

  await service.schedulePaymentAlerts(accounts, banks, daysBefore);
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  await CreditCardPaymentNotificationService().initialize();

  runApp(const ProviderScope(child: BudgettApp()));
}

class BudgettApp extends ConsumerWidget {
  const BudgettApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeModeAsync = ref.watch(themeModeProvider);
    final themeMode = themeModeAsync.when(
      data: (isDark) => isDark ? ThemeMode.dark : ThemeMode.light,
      loading: () => ThemeMode.system,
      error: (_, __) => ThemeMode.system,
    );

    // Watch the scheduler so it runs whenever dependencies change
    ref.watch(ccAlertSchedulerProvider);

    return MaterialApp.router(
      title: 'Budgett',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
