import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

Future<void> performLogout(WidgetRef ref, BuildContext context) async {
  ref.invalidate(accountsProvider);
  ref.invalidate(recentTransactionsProvider);
  ref.invalidate(categoriesProvider);
  ref.invalidate(goalsProvider);
  ref.invalidate(budgetsProvider);
  ref.invalidate(expenseGroupsProvider);
  ref.invalidate(yearlySummaryProvider);
  ref.invalidate(recurringTransactionsProvider);
  await Supabase.instance.client.auth.signOut();
  if (context.mounted) context.go('/login');
}
