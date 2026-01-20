import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budgett_frontend/data/repositories/finance_repository.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/budget_model.dart';
import 'package:budgett_frontend/data/models/goal_model.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(Supabase.instance.client);
});

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getAccounts();
});

final recentTransactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getRecentTransactions();
});

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getCategories();
});

final goalsProvider = FutureProvider<List<Goal>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getGoals();
});

// Provider family for fetching budgets by month/year (could be optimized)
final budgetsProvider = FutureProvider.family<List<Budget>, ({int month, int year})>((ref, date) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getBudgets(date.month, date.year);
});
