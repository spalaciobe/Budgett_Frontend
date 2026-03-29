import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budgett_frontend/presentation/screens/home_screen.dart';
import 'package:budgett_frontend/presentation/screens/auth/login_screen.dart';
import 'package:budgett_frontend/presentation/screens/budget_screen.dart';
import 'package:budgett_frontend/presentation/screens/goals_screen.dart';
import 'package:budgett_frontend/presentation/screens/analysis_screen.dart';
import 'package:budgett_frontend/presentation/screens/main_scaffold.dart';
import 'package:budgett_frontend/presentation/screens/recurring_transactions_screen.dart';
import 'package:budgett_frontend/presentation/screens/expense_groups_screen.dart';
import 'package:budgett_frontend/presentation/screens/settings_screen.dart';
import 'package:budgett_frontend/presentation/screens/onboarding/bank_onboarding_screen.dart';

const _kOnboardingCompletedKey = 'onboarding_banks_completed';

/// AppRouter with bank-onboarding gate.
///
/// Redirect logic:
///   not authenticated           → /login
///   authenticated + at /login   → /
///   at /onboarding              → no redirect (let it render)
///   authenticated + onboarding not done → /onboarding
///   otherwise                   → no redirect
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // ── Auth ──────────────────────────────────────────────────────────────
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    // ── Onboarding ────────────────────────────────────────────────────────
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const BankOnboardingScreen(),
    ),

    // ── Main app shell ────────────────────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) {
        return SelectionArea(child: MainScaffold(child: child));
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/budget',
          builder: (context, state) => const BudgetScreen(),
        ),
        GoRoute(
          path: '/goals',
          builder: (context, state) => const GoalsScreen(),
        ),
        GoRoute(
          path: '/analysis',
          builder: (context, state) => const AnalysisScreen(),
        ),
        GoRoute(
          path: '/recurring',
          builder: (context, state) => const RecurringTransactionsScreen(),
        ),
        GoRoute(
          path: '/expense-groups',
          builder: (context, state) => const ExpenseGroupsScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
  ],
  redirect: (context, state) async {
    final session = Supabase.instance.client.auth.currentSession;
    final path = state.uri.path;

    // 1. Not authenticated → login
    if (session == null) {
      return path == '/login' ? null : '/login';
    }

    // 2. Authenticated but landed on login → home
    if (path == '/login') return '/';

    // 3. Already on onboarding → don't redirect (let it complete)
    if (path == '/onboarding') return null;

    // 4. Check if onboarding was completed
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool(_kOnboardingCompletedKey) ?? false;
    if (!onboardingDone) return '/onboarding';

    return null;
  },
);
