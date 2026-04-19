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

class AccountCustomOrderNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final repo = ref.watch(financeRepositoryProvider);
    return repo.getAccountSortOrder();
  }

  Future<void> setOrder(List<String> ids) async {
    state = AsyncData(ids); // optimistic — UI responds instantly
    final repo = ref.read(financeRepositoryProvider);
    await repo.setAccountSortOrder(ids);
  }
}

final accountCustomOrderProvider =
    AsyncNotifierProvider<AccountCustomOrderNotifier, List<String>>(
        AccountCustomOrderNotifier.new);

final recentTransactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getRecentTransactions();
});

/// Transactions to show in an account's detail view.
///
/// - Includes transfers where the account is either source or target.
/// - For savings parents, also includes transactions from the account's pockets.
/// - Excludes installment parent rows (children carry the real amounts).
final accountDetailTransactionsProvider = FutureProvider.autoDispose
    .family<List<Transaction>, String>((ref, accountId) async {
  final repo = ref.read(financeRepositoryProvider);
  final accounts = await ref.watch(accountsProvider.future);
  final account = accounts.firstWhere(
    (a) => a.id == accountId,
    orElse: () => throw StateError('Account not found: $accountId'),
  );
  final ids = <String>[account.id, ...account.pockets.map((p) => p.id)];
  return repo.getTransactionsForAccounts(ids, limit: 100);
});

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getCategories();
});

/// Lifetime running balance per savings category (sinking fund).
/// Keyed by category_id. Categories with zero net activity are omitted.
final categoryAccumulatedBalancesProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getCategoryAccumulatedBalances();
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

/// Sum of cash transfers INTO this account — the "funded" headline shown on
/// investment accounts (what the user has actually put in, independent of how
/// that money has since been rotated into positions).
final accountFundedTotalProvider =
    FutureProvider.family.autoDispose<double, String>((ref, accountId) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.accountFundedTotal(accountId);
});
