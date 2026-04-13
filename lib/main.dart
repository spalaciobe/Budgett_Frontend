import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:budgett_frontend/core/app_constants.dart';
import 'package:budgett_frontend/presentation/navigation/app_router.dart';
import 'package:budgett_frontend/core/app_theme.dart';
import 'package:budgett_frontend/presentation/providers/settings_provider.dart';
import 'package:budgett_frontend/core/services/notification_service.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/data/repositories/bank_repository.dart';

/// Emits the current session whenever auth state changes.
/// Used to gate providers that require authentication.
final _supabaseSessionProvider = StreamProvider<Session?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange
      .map((event) => event.session);
});

final ccAlertSchedulerProvider = FutureProvider<void>((ref) async {
  // Do not touch finance providers until the session is confirmed.
  // This prevents a race condition at startup on Flutter web where
  // Supabase initializes before the stored session is restored.
  final session = ref.watch(_supabaseSessionProvider).valueOrNull;
  if (session == null) return;

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

  await initializeDateFormatting('es_CO');
  await initializeDateFormatting('es');

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
      data: (isDark) => isDark == null ? ThemeMode.system : (isDark ? ThemeMode.dark : ThemeMode.light),
      loading: () => ThemeMode.system,
      error: (_, __) => ThemeMode.system,
    );

    // Invalidate all finance providers whenever the user signs in so they always
    // fetch fresh data for the current session. Without this, providers can
    // return stale cached data from a previous session after logout + re-login,
    // because the ref.invalidate() calls in logout_action.dart fire while the
    // session is still active, causing providers to complete with the old data.
    ref.listen<AsyncValue<Session?>>(_supabaseSessionProvider, (previous, next) {
      final wasSignedOut = previous?.valueOrNull == null;
      final isSignedIn = next.valueOrNull != null;
      if (wasSignedOut && isSignedIn) {
        ref.invalidate(accountsProvider);
        ref.invalidate(recentTransactionsProvider);
        ref.invalidate(categoriesProvider);
        ref.invalidate(goalsProvider);
        ref.invalidate(expenseGroupsProvider);
        ref.invalidate(recurringTransactionsProvider);
        ref.invalidate(budgetsProvider);
        ref.invalidate(yearlySummaryProvider);
      }
    });

    // Watch the scheduler so it runs whenever dependencies change
    ref.watch(ccAlertSchedulerProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Budgett',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
