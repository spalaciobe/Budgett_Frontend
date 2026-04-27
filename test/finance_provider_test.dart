// Tests for Riverpod providers in finance_provider.dart
// Uses manual FinanceRepository subclass to stub data; no Supabase connectivity needed.
//
// Strategy:
//   - Create a FakeFinanceRepository that extends FinanceRepository but overrides
//     every method with deterministic, in-memory implementations.
//   - Override financeRepositoryProvider via ProviderContainer(overrides: []).
//   - Verify each FutureProvider resolves with the expected stub data.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budgett_frontend/data/repositories/finance_repository.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/budget_model.dart';
import 'package:budgett_frontend/data/models/goal_model.dart';
import 'package:budgett_frontend/data/models/expense_group_model.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

// ─── Fake client (never called, just satisfies the constructor) ───────────────

class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeSupabaseClient: ${invocation.memberName} was called unexpectedly');
}

// ─── Stub repository ──────────────────────────────────────────────────────────

class _FakeFinanceRepository extends FinanceRepository {
  _FakeFinanceRepository() : super(_FakeSupabaseClient());

  // ------ stub data ------

  static final _accounts = [
    Account.fromJson({
      'id': 'acc-1',
      'name': 'Bancolombia',
      'type': 'savings',
      'balance': 2000000.0,
      'credit_limit': 0,
    }),
  ];

  static final _transactions = [
    Transaction.fromJson({
      'id': 'tx-1',
      'account_id': 'acc-1',
      'amount': 300000,
      'description': 'Mercado',
      'date': '2026-03-10',
      'type': 'expense',
      'status': 'cleared',
    }),
    Transaction.fromJson({
      'id': 'tx-2',
      'account_id': 'acc-1',
      'amount': 5000000,
      'description': 'Salario',
      'date': '2026-03-01',
      'type': 'income',
      'status': 'cleared',
    }),
  ];

  static final _categories = [
    Category.fromJson({
      'id': 'cat-1',
      'name': 'Comida',
      'type': 'expense',
      'icon': 'restaurant',
      'color': '#FF5722',
      'sub_categories': [],
    }),
  ];

  static final _budgets = [
    Budget.fromJson({
      'id': 'bud-1',
      'category_id': 'cat-1',
      'amount': 800000.0,
      'month': 3,
      'year': 2026,
    }),
  ];

  static final _goals = [
    Goal.fromJson({
      'id': 'goal-1',
      'name': 'Fondo emergencia',
      'target_amount': 10000000.0,
      'current_amount': 2000000.0,
      'deadline': null,
      'icon_name': 'savings',
      'created_at': '2026-01-01T00:00:00Z',
    }),
  ];

  static final _expenseGroups = [
    ExpenseGroup.fromJson({
      'id': 'grp-1',
      'name': 'Primera quincena',
      'start_date': '2026-03-01',
      'end_date': '2026-03-15',
      'budget_amount': 1500000.0,
    }),
    ExpenseGroup.fromJson({
      'id': 'grp-2',
      'name': 'Viaje Cartagena',
      'start_date': '2026-04-25',
      'end_date': '2026-05-03',
      'budget_amount': 2000000.0,
    }),
  ];

  static final _recurringTransactions = [
    RecurringTransaction.fromJson({
      'id': 'rt-1',
      'description': 'Netflix',
      'amount': 49900.0,
      'type': 'expense',
      'frequency': 'monthly',
      'next_run_date': '2026-04-01',
      'is_active': true,
    }),
  ];

  // ------ overrides ------

  @override
  Future<List<Account>> getAccounts() async => _accounts;

  @override
  Future<List<Transaction>> getRecentTransactions() async => _transactions;

  @override
  Future<List<Category>> getCategories() async => _categories;

  @override
  Future<List<Budget>> getBudgets(int month, int year) async =>
      _budgets.where((b) => b.month == month && b.year == year).toList();

  @override
  Future<List<Goal>> getGoals() async => _goals;

  @override
  Future<List<ExpenseGroup>> getExpenseGroups() async => _expenseGroups;

  @override
  Future<List<RecurringTransaction>> getRecurringTransactions() async =>
      _recurringTransactions;

  @override
  Future<List<Map<String, dynamic>>> getYearlySummary(int year) async {
    return List.generate(
      12,
      (i) => {'month': i + 1, 'income': 5000000.0, 'expense': 2500000.0},
    );
  }
}

// ─── Helper ───────────────────────────────────────────────────────────────────

ProviderContainer _makeContainer() {
  final fake = _FakeFinanceRepository();
  return ProviderContainer(
    overrides: [
      financeRepositoryProvider.overrideWithValue(fake),
    ],
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('accountsProvider', () {
    test('resolves with stub accounts', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(accountsProvider.future);
      expect(result, hasLength(1));
      expect(result.first.name, 'Bancolombia');
    });

    test('result is an AsyncData after resolution', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(accountsProvider.future);
      expect(container.read(accountsProvider), isA<AsyncData<List<Account>>>());
    });
  });

  group('recentTransactionsProvider', () {
    test('resolves with stub transactions', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(recentTransactionsProvider.future);
      expect(result, hasLength(2));
      expect(result.any((t) => t.type == 'income'), isTrue);
      expect(result.any((t) => t.type == 'expense'), isTrue);
    });

    test('transactions have expected descriptions', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(recentTransactionsProvider.future);
      final descriptions = result.map((t) => t.description).toList();
      expect(descriptions, containsAll(['Mercado', 'Salario']));
    });
  });

  group('categoriesProvider', () {
    test('resolves with stub categories', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(categoriesProvider.future);
      expect(result, hasLength(1));
      expect(result.first.name, 'Comida');
      expect(result.first.type, 'expense');
    });
  });

  group('goalsProvider', () {
    test('resolves with stub goals', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(goalsProvider.future);
      expect(result, hasLength(1));
      expect(result.first.name, 'Fondo emergencia');
      expect(result.first.targetAmount, 10000000.0);
    });
  });

  group('recurringTransactionsProvider', () {
    test('resolves with stub recurring transactions', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(recurringTransactionsProvider.future);
      expect(result, hasLength(1));
      expect(result.first.description, 'Netflix');
      expect(result.first.frequency, 'monthly');
    });
  });

  group('budgetsProvider (family)', () {
    test('resolves with budgets for matching month/year', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(
        budgetsProvider((month: 3, year: 2026)).future,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 800000.0);
    });

    test('returns empty list for non-matching month', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(
        budgetsProvider((month: 6, year: 2026)).future,
      );
      expect(result, isEmpty);
    });

    test('different family parameters create separate provider instances', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final march = await container.read(budgetsProvider((month: 3, year: 2026)).future);
      final april = await container.read(budgetsProvider((month: 4, year: 2026)).future);

      expect(march, hasLength(1));
      expect(april, isEmpty);
    });
  });

  group('expenseGroupsProvider', () {
    test('resolves with all expense groups', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(expenseGroupsProvider.future);
      expect(result, hasLength(2));
      expect(result.first.name, 'Primera quincena');
    });

    test('groups can span multiple months', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(expenseGroupsProvider.future);
      final trip = result.last;
      expect(trip.name, 'Viaje Cartagena');
      expect(trip.startDate.month, 4);
      expect(trip.endDate!.month, 5);
    });
  });

  group('yearlySummaryProvider (family)', () {
    test('resolves with 12 monthly entries', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(yearlySummaryProvider(2026).future);
      expect(result, hasLength(12));
    });

    test('each entry has month, income, expense keys', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(yearlySummaryProvider(2026).future);
      for (final entry in result) {
        expect(entry.containsKey('month'), isTrue);
        expect(entry.containsKey('income'), isTrue);
        expect(entry.containsKey('expense'), isTrue);
      }
    });

    test('month numbers are 1..12', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(yearlySummaryProvider(2026).future);
      final months = result.map((e) => e['month'] as int).toList();
      expect(months, containsAll([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]));
    });

    test('different years produce independent provider instances', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      // Both are valid since the stub always returns the same shape; the key
      // test is that two separate reads don't interfere.
      final y2026 = await container.read(yearlySummaryProvider(2026).future);
      final y2025 = await container.read(yearlySummaryProvider(2025).future);
      expect(y2026.length, y2025.length); // both return 12 from stub
    });
  });

  // ─── Error handling ───────────────────────────────────────────────────────

  group('Provider error handling', () {
    test('accountsProvider emits AsyncError when repo throws', () async {
      final throwingRepo = _ThrowingFinanceRepository();
      final container = ProviderContainer(
        overrides: [
          financeRepositoryProvider.overrideWithValue(throwingRepo),
        ],
      );
      addTearDown(container.dispose);

      // Wait for provider to fail
      await expectLater(
        container.read(accountsProvider.future),
        throwsException,
      );

      final state = container.read(accountsProvider);
      expect(state, isA<AsyncError<List<Account>>>());
    });

    test('recentTransactionsProvider emits AsyncError when repo throws', () async {
      final throwingRepo = _ThrowingFinanceRepository();
      final container = ProviderContainer(
        overrides: [
          financeRepositoryProvider.overrideWithValue(throwingRepo),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(recentTransactionsProvider.future),
        throwsException,
      );
    });
  });
}

// ─── Helper stub that always throws ──────────────────────────────────────────

class _ThrowingFinanceRepository extends FinanceRepository {
  _ThrowingFinanceRepository() : super(_FakeSupabaseClient());

  @override
  Future<List<Account>> getAccounts() async =>
      throw Exception('Simulated Supabase error');

  @override
  Future<List<Transaction>> getRecentTransactions() async =>
      throw Exception('Simulated Supabase error');

  @override
  Future<List<Category>> getCategories() async =>
      throw Exception('Simulated Supabase error');

  @override
  Future<List<Budget>> getBudgets(int month, int year) async =>
      throw Exception('Simulated Supabase error');

  @override
  Future<List<Goal>> getGoals() async =>
      throw Exception('Simulated Supabase error');

  @override
  Future<List<ExpenseGroup>> getExpenseGroups() async =>
      throw Exception('Simulated Supabase error');

  @override
  Future<List<RecurringTransaction>> getRecurringTransactions() async =>
      throw Exception('Simulated Supabase error');

  @override
  Future<List<Map<String, dynamic>>> getYearlySummary(int year) async =>
      throw Exception('Simulated Supabase error');
}
