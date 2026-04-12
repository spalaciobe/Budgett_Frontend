import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
import 'package:budgett_frontend/presentation/screens/categories_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // ── Auth ──────────────────────────────────────────────────────────────
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
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
        GoRoute(
          path: '/categories',
          builder: (context, state) => const CategoriesScreen(),
        ),
      ],
    ),
  ],
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final path = state.uri.path;

    if (session == null) {
      return path == '/login' ? null : '/login';
    }

    if (path == '/login') return '/';

    return null;
  },
);
