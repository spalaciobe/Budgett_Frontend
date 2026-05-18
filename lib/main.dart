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
import 'package:budgett_frontend/core/services/update_checker_service.dart';
import 'package:budgett_frontend/presentation/providers/update_provider.dart';
import 'package:budgett_frontend/presentation/widgets/update_available_dialog.dart';
import 'package:budgett_frontend/data/repositories/bank_repository.dart';

/// Emits the current session whenever auth state changes.
/// Used to gate providers that require authentication.
final _supabaseSessionProvider = StreamProvider<Session?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange
      .map((event) => event.session);
});

/// Runs once per signed-in session: every recurring transaction whose
/// `next_run_date` has passed emits one pending transaction per missed cycle
/// (stamped with the scheduled date), then advances `next_run_date` past today.
/// On generation, finance providers are invalidated so the UI shows the new
/// rows without a manual refresh.
final recurringAutoGenProvider = FutureProvider<void>((ref) async {
  final session = ref.watch(_supabaseSessionProvider).valueOrNull;
  if (session == null) return;

  final repo = ref.read(financeRepositoryProvider);
  final count = await repo.processRecurringDue();
  if (count > 0) {
    ref.invalidate(recurringTransactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(accountsProvider);
  }
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

  // Pull billing-calendar overrides for every credit-card account so payment
  // reminders fire on the user-edited date when one exists. Watching these
  // providers also makes the scheduler re-run automatically whenever an
  // override is added, edited, or removed.
  final now = DateTime.now();
  final ccAccountIds = accounts
      .where((a) => a.type == 'credit_card' && a.creditCardRules != null)
      .map((a) => a.id)
      .toList();
  final Map<String, Map<({int year, int month}),
      ({DateTime cutoff, DateTime payment})>> overrides = {};
  for (final id in ccAccountIds) {
    for (final year in [now.year, now.year + 1]) {
      final cal = ref
          .watch(billingCalendarProvider((accountId: id, year: year)))
          .valueOrNull;
      if (cal == null) continue;
      final acctMap = overrides.putIfAbsent(id, () => {});
      for (final entry in cal.entries) {
        acctMap[(year: year, month: entry.key)] = entry.value;
      }
    }
  }

  await service.schedulePaymentAlerts(
    accounts,
    banks,
    daysBefore,
    overrideLookup: (id, y, m) => overrides[id]?[(year: y, month: m)],
  );
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
    // Catch-up overdue recurring transactions once per session.
    ref.watch(recurringAutoGenProvider);

    // Show an update modal once a session if a newer APK is available on
    // GitHub Releases. Resolves to null on non-Android, when up-to-date, or
    // when the user already dismissed this build.
    ref.listen<AsyncValue<UpdateInfo?>>(pendingUpdateProvider, (_, next) {
      final info = next.valueOrNull;
      if (info == null) return;
      final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
      if (navContext == null) return;
      showDialog(
        context: navContext,
        barrierDismissible: false,
        builder: (_) => UpdateAvailableDialog(info: info),
      );
    });
    ref.watch(pendingUpdateProvider);

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
