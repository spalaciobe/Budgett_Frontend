import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budgett_frontend/presentation/screens/home_screen.dart';
import 'package:budgett_frontend/presentation/screens/auth/login_screen.dart';
import 'package:budgett_frontend/presentation/screens/budget_screen.dart';
import 'package:budgett_frontend/presentation/screens/goals_screen.dart';
import 'package:budgett_frontend/presentation/screens/analysis_screen.dart';
import 'package:budgett_frontend/presentation/screens/main_scaffold.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) {
        return SelectionArea(
          child: MainScaffold(child: child),
        );
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
      ],
    ),
  ],
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isLoggingIn = state.uri.path == '/login';

    if (session == null && !isLoggingIn) return '/login';
    if (session != null && isLoggingIn) return '/';

    return null;
  },
);
