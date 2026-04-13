import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budgett_frontend/data/repositories/finance_repository.dart';
import 'package:budgett_frontend/data/models/profile_model.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/budget_model.dart';
import 'package:budgett_frontend/data/models/goal_model.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';
import 'package:budgett_frontend/data/models/expense_group_model.dart';
import 'package:budgett_frontend/data/models/investment_holding_model.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(Supabase.instance.client);
});

final recurringTransactionsProvider = FutureProvider<List<RecurringTransaction>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getRecurringTransactions();
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

final expenseGroupsProvider = FutureProvider<List<ExpenseGroup>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getExpenseGroups();
});

final yearlySummaryProvider = FutureProvider.family<List<Map<String, dynamic>>, int>((ref, year) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getYearlySummary(year);
});

final billingCalendarProvider = FutureProvider.family.autoDispose<
    Map<int, ({DateTime cutoff, DateTime payment})>,
    ({String accountId, int year})>((ref, params) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getBillingCalendar(params.accountId, params.year);
});

final profileProvider = FutureProvider<ProfileModel?>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getProfile();
});

final accountHoldingsProvider =
    FutureProvider.family.autoDispose<List<InvestmentHolding>, String>(
        (ref, accountId) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getHoldings(accountId);
});
