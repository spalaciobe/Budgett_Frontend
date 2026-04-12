// ignore_for_file: subtype_of_sealed_class

import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/sub_category_model.dart';
import 'package:budgett_frontend/data/models/budget_model.dart';
import 'package:budgett_frontend/data/models/goal_model.dart';
import 'package:budgett_frontend/data/models/expense_group_model.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';
import 'package:budgett_frontend/data/models/category_spending.dart';
import 'package:budgett_frontend/data/utils/balance_calculator.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

Transaction _tx({
  String id = 'tx-1',
  String accountId = 'acc-1',
  double amount = 100.0,
  String description = 'Test',
  String date = '2026-03-15',
  String type = 'expense',
  String? categoryId,
  String? subCategoryId,
  String? targetAccountId,
  String status = 'cleared',
  String? movementType,
  String? expenseGroupId,
  String currency = 'COP',
  String? targetCurrency,
  double? fxRate,
}) {
  return Transaction.fromJson({
    'id': id,
    'account_id': accountId,
    'amount': amount,
    'description': description,
    'date': date,
    'type': type,
    'category_id': categoryId,
    'sub_category_id': subCategoryId,
    'target_account_id': targetAccountId,
    'status': status,
    'movement_type': movementType,
    'expense_group_id': expenseGroupId,
    'currency': currency,
    'target_currency': targetCurrency,
    'fx_rate': fxRate,
  });
}

// ─── Transaction Model Tests ─────────────────────────────────────────────────

void main() {
  group('Transaction.fromJson', () {
    test('parses all required fields', () {
      final t = _tx(
        id: 'abc',
        accountId: 'acc-42',
        amount: 250000.0,
        description: 'Mercado',
        date: '2026-01-10',
        type: 'expense',
      );

      expect(t.id, 'abc');
      expect(t.accountId, 'acc-42');
      expect(t.amount, 250000.0);
      expect(t.description, 'Mercado');
      expect(t.date, DateTime(2026, 1, 10));
      expect(t.type, 'expense');
      expect(t.status, 'cleared');
    });

    test('defaults description to empty string when null', () {
      final t = Transaction.fromJson({
        'id': 'x',
        'account_id': 'acc-1',
        'amount': 50,
        'description': null,
        'date': '2026-01-01',
        'type': 'income',
        'status': 'cleared',
      });
      expect(t.description, '');
    });

    test('defaults status to cleared when null', () {
      final t = Transaction.fromJson({
        'id': 'x',
        'account_id': 'acc-1',
        'amount': 50,
        'description': 'X',
        'date': '2026-01-01',
        'type': 'income',
        // status omitted
      });
      expect(t.status, 'cleared');
    });

    test('parses optional nullable fields correctly', () {
      final t = _tx(
        categoryId: 'cat-1',
        subCategoryId: 'sub-1',
        expenseGroupId: 'grp-1',
        movementType: 'variable',
      );
      expect(t.categoryId, 'cat-1');
      expect(t.subCategoryId, 'sub-1');
      expect(t.expenseGroupId, 'grp-1');
      expect(t.movementType, 'variable');
    });

    test('parses credit-card fields', () {
      final t = Transaction.fromJson({
        'id': 'cc-tx',
        'account_id': 'acc-cc',
        'amount': 150000,
        'description': 'Compra TC',
        'date': '2026-03-20',
        'type': 'expense',
        'status': 'pending',
        'periodo_facturacion': '2026-03',
        'fecha_corte_calculada': '2026-03-25',
        'fecha_pago_calculada': '2026-04-07',
      });
      expect(t.billingPeriod, '2026-03');
      expect(t.calculatedCutoffDate, DateTime(2026, 3, 25));
      expect(t.calculatedPaymentDate, DateTime(2026, 4, 7));
    });

    test('amount as int is coerced to double', () {
      final t = Transaction.fromJson({
        'id': 'x',
        'account_id': 'acc-1',
        'amount': 10, // int in JSON
        'description': 'X',
        'date': '2026-01-01',
        'type': 'expense',
        'status': 'cleared',
      });
      expect(t.amount, isA<double>());
      expect(t.amount, 10.0);
    });

    test('zero amount is valid', () {
      final t = _tx(amount: 0.0);
      expect(t.amount, 0.0);
    });

    test('very large COP amount parses correctly', () {
      final t = _tx(amount: 99999999.99);
      expect(t.amount, 99999999.99);
    });
  });

  // ─── Account Model Tests ─────────────────────────────────────────────────

  group('Account.fromJson', () {
    test('parses all fields', () {
      final a = Account.fromJson({
        'id': 'acc-1',
        'name': 'Bancolombia Ahorro',
        'type': 'savings',
        'balance': 1500000.0,
        'credit_limit': 0,
        'balance_usd': 0,
        'credit_limit_usd': 0,
        'closing_day': null,
        'payment_due_day': null,
        'icon': 'account_balance',
      });

      expect(a.id, 'acc-1');
      expect(a.name, 'Bancolombia Ahorro');
      expect(a.type, 'savings');
      expect(a.balance, 1500000.0);
      expect(a.creditLimit, 0.0);
    });

    test('parses credit card with closing/payment days', () {
      final a = Account.fromJson({
        'id': 'acc-cc',
        'name': 'Nubank CC',
        'type': 'credit_card',
        'balance': -350000.0,
        'credit_limit': 2000000,
        'balance_usd': 0,
        'credit_limit_usd': 0,
        'closing_day': 25,
        'payment_due_day': 7,
        'icon': null,
      });

      expect(a.closingDay, 25);
      expect(a.paymentDueDay, 7);
      expect(a.creditLimit, 2000000.0);
    });

    test('balance can be negative (credit card debt)', () {
      final a = Account.fromJson({
        'id': 'acc-debt',
        'name': 'TC Deuda',
        'type': 'credit_card',
        'balance': -500000.0,
        'credit_limit': 0,
      });
      expect(a.balance, -500000.0);
    });

    test('balance zero is valid', () {
      final a = Account.fromJson({
        'id': 'acc-zero',
        'name': 'Cuenta cero',
        'type': 'checking',
        'balance': 0,
        'credit_limit': 0,
      });
      expect(a.balance, 0.0);
    });

    test('credit_limit defaults to 0 when null', () {
      final a = Account.fromJson({
        'id': 'acc-x',
        'name': 'X',
        'type': 'savings',
        'balance': 100,
        // credit_limit missing
      });
      expect(a.creditLimit, 0.0);
    });
  });

  // ─── Category Model Tests ─────────────────────────────────────────────────

  group('Category.fromJson', () {
    test('parses income category', () {
      final c = Category.fromJson({
        'id': 'cat-1',
        'name': 'Salario',
        'type': 'income',
        'icon': 'work',
        'color': '#4CAF50',
        'sub_categories': [],
      });

      expect(c.id, 'cat-1');
      expect(c.type, 'income');
      expect(c.color, '#4CAF50');
      expect(c.subCategories, isEmpty);
    });

    test('parses category with sub_categories', () {
      final c = Category.fromJson({
        'id': 'cat-2',
        'name': 'Comida',
        'type': 'expense',
        'icon': 'restaurant',
        'color': null,
        'sub_categories': [
          {'id': 'sub-1', 'name': 'Restaurante', 'category_id': 'cat-2'},
          {'id': 'sub-2', 'name': 'Supermercado', 'category_id': 'cat-2'},
        ],
      });

      expect(c.subCategories, hasLength(2));
      expect(c.subCategories!.first.name, 'Restaurante');
    });

    test('null sub_categories becomes empty list', () {
      final c = Category.fromJson({
        'id': 'cat-3',
        'name': 'Transporte',
        'type': 'expense',
        'icon': null,
        'color': null,
        'sub_categories': null,
      });
      expect(c.subCategories, isEmpty);
    });

    test('toJson includes expected keys', () {
      final c = Category.fromJson({
        'id': 'cat-4',
        'name': 'Salud',
        'type': 'expense',
        'icon': 'local_hospital',
        'color': '#E53935',
        'sub_categories': [],
      });
      final json = c.toJson();
      expect(json['name'], 'Salud');
      expect(json['type'], 'expense');
      expect(json['icon'], 'local_hospital');
    });
  });

  // ─── Budget Model Tests ───────────────────────────────────────────────────

  group('Budget.fromJson', () {
    test('parses correctly', () {
      final b = Budget.fromJson({
        'id': 'bud-1',
        'category_id': 'cat-1',
        'amount': 800000.0,
        'month': 3,
        'year': 2026,
      });

      expect(b.id, 'bud-1');
      expect(b.amount, 800000.0);
      expect(b.month, 3);
      expect(b.year, 2026);
    });

    test('toJson round-trip preserves values', () {
      final b = Budget.fromJson({
        'id': 'bud-2',
        'category_id': 'cat-2',
        'amount': 500000.0,
        'month': 12,
        'year': 2025,
      });
      final j = b.toJson();
      expect(j['amount'], 500000.0);
      expect(j['month'], 12);
      expect(j['year'], 2025);
    });

    test('zero budget is valid', () {
      final b = Budget.fromJson({
        'id': 'bud-0',
        'category_id': 'cat-1',
        'amount': 0,
        'month': 1,
        'year': 2026,
      });
      expect(b.amount, 0.0);
    });
  });

  // ─── Goal Model Tests ─────────────────────────────────────────────────────

  group('Goal.fromJson', () {
    test('parses correctly', () {
      final g = Goal.fromJson({
        'id': 'goal-1',
        'name': 'Fondo de emergencia',
        'target_amount': 10000000.0,
        'current_amount': 2500000.0,
        'deadline': '2026-12-31',
        'icon_name': 'savings',
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(g.name, 'Fondo de emergencia');
      expect(g.targetAmount, 10000000.0);
      expect(g.currentAmount, 2500000.0);
      expect(g.deadline, DateTime(2026, 12, 31));
    });

    test('current_amount defaults to 0 when null', () {
      final g = Goal.fromJson({
        'id': 'goal-2',
        'name': 'Viaje',
        'target_amount': 5000000.0,
        'current_amount': null,
        'deadline': null,
        'icon_name': null,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(g.currentAmount, 0.0);
    });

    test('toJson round-trip', () {
      final g = Goal.fromJson({
        'id': 'goal-3',
        'name': 'Laptop',
        'target_amount': 3000000.0,
        'current_amount': 1000000.0,
        'deadline': null,
        'icon_name': 'laptop',
        'created_at': '2026-02-01T00:00:00Z',
      });
      final j = g.toJson();
      expect(j['name'], 'Laptop');
      expect(j['target_amount'], 3000000.0);
      expect(j['current_amount'], 1000000.0);
    });
  });

  // ─── ExpenseGroup Model Tests ─────────────────────────────────────────────

  group('ExpenseGroup.fromJson', () {
    test('parses correctly', () {
      final eg = ExpenseGroup.fromJson({
        'id': 'grp-1',
        'name': 'Quincena de marzo',
        'month': 3,
        'year': 2026,
        'budget_amount': 1500000.0,
        'icon': 'calendar_month',
      });

      expect(eg.name, 'Quincena de marzo');
      expect(eg.month, 3);
      expect(eg.year, 2026);
      expect(eg.budgetAmount, 1500000.0);
    });

    test('budget_amount defaults to 0 when null', () {
      final eg = ExpenseGroup.fromJson({
        'id': 'grp-2',
        'name': 'Sin presupuesto',
        'month': 1,
        'year': 2026,
        'budget_amount': null,
      });
      expect(eg.budgetAmount, 0.0);
    });
  });

  // ─── RecurringTransaction Model Tests ────────────────────────────────────

  group('RecurringTransaction.fromJson', () {
    test('parses correctly', () {
      final rt = RecurringTransaction.fromJson({
        'id': 'rt-1',
        'description': 'Netflix',
        'amount': 49900.0,
        'category_id': 'cat-ent',
        'account_id': 'acc-tc',
        'type': 'expense',
        'frequency': 'monthly',
        'next_run_date': '2026-04-01',
        'last_run_date': '2026-03-01',
        'is_active': true,
      });

      expect(rt.description, 'Netflix');
      expect(rt.amount, 49900.0);
      expect(rt.frequency, 'monthly');
      expect(rt.nextRunDate, DateTime(2026, 4, 1));
      expect(rt.lastRunDate, DateTime(2026, 3, 1));
      expect(rt.isActive, true);
    });

    test('last_run_date null is allowed', () {
      final rt = RecurringTransaction.fromJson({
        'id': 'rt-2',
        'description': 'Arriendo',
        'amount': 900000.0,
        'type': 'expense',
        'frequency': 'monthly',
        'next_run_date': '2026-04-05',
        'last_run_date': null,
        'is_active': true,
      });
      expect(rt.lastRunDate, isNull);
    });

    test('defaults is_active to true when null', () {
      final rt = RecurringTransaction.fromJson({
        'id': 'rt-3',
        'description': 'Test',
        'amount': 1000.0,
        'type': 'expense',
        'frequency': 'weekly',
        'next_run_date': '2026-04-01',
        // is_active omitted
      });
      expect(rt.isActive, true);
    });

    test('toJson omits id (insert-safe)', () {
      final rt = RecurringTransaction.fromJson({
        'id': 'rt-4',
        'description': 'Gym',
        'amount': 85000.0,
        'type': 'expense',
        'frequency': 'monthly',
        'next_run_date': '2026-04-10',
        'is_active': true,
      });
      final json = rt.toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json['description'], 'Gym');
      expect(json['frequency'], 'monthly');
    });
  });

  // ─── CategorySpending Tests ───────────────────────────────────────────────

  group('CategorySpending', () {
    test('initializes with zero total and empty subCategories', () {
      final cs = CategorySpending();
      expect(cs.total, 0.0);
      expect(cs.subCategories, isEmpty);
    });

    test('can accumulate sub-category amounts', () {
      final cs = CategorySpending();
      cs.total += 300000;
      cs.subCategories['sub-1'] = 200000;
      cs.subCategories['sub-2'] = 100000;

      expect(cs.total, 300000);
      expect(cs.subCategories['sub-1'], 200000);
      expect(cs.subCategories.length, 2);
    });

    test('handles single sub-category', () {
      final cs = CategorySpending(total: 50000, subCategories: {'sub-a': 50000});
      expect(cs.total, 50000);
      expect(cs.subCategories['sub-a'], 50000);
    });
  });

  // ─── SubCategory Model Tests ──────────────────────────────────────────────

  group('SubCategory.fromJson', () {
    test('parses correctly', () {
      final sc = SubCategory.fromJson({
        'id': 'sub-1',
        'name': 'Restaurante',
        'category_id': 'cat-food',
      });
      expect(sc.id, 'sub-1');
      expect(sc.name, 'Restaurante');
      expect(sc.categoryId, 'cat-food');
    });
  });

  // ─── BalanceCalculator Tests ──────────────────────────────────────────────

  group('BalanceCalculator.netBalance', () {
    test('returns 0 for empty list', () {
      expect(BalanceCalculator.netBalance([]), 0.0);
    });

    test('calculates income − expenses', () {
      final txs = [
        _tx(amount: 3000000, type: 'income'),
        _tx(amount: 1200000, type: 'expense'),
        _tx(amount: 500000, type: 'expense'),
      ];
      expect(BalanceCalculator.netBalance(txs), 1300000);
    });

    test('ignores transfer type', () {
      final txs = [
        _tx(amount: 1000000, type: 'income'),
        _tx(amount: 200000, type: 'transfer'),
      ];
      expect(BalanceCalculator.netBalance(txs), 1000000);
    });

    test('returns negative when expenses exceed income', () {
      final txs = [
        _tx(amount: 100000, type: 'income'),
        _tx(amount: 500000, type: 'expense'),
      ];
      expect(BalanceCalculator.netBalance(txs), -400000);
    });

    test('zero amount transactions do not affect balance', () {
      final txs = [
        _tx(amount: 0.0, type: 'income'),
        _tx(amount: 0.0, type: 'expense'),
      ];
      expect(BalanceCalculator.netBalance(txs), 0.0);
    });
  });

  group('BalanceCalculator.totalIncome', () {
    test('sums only income', () {
      final txs = [
        _tx(amount: 2000000, type: 'income'),
        _tx(amount: 500000, type: 'income'),
        _tx(amount: 300000, type: 'expense'),
      ];
      expect(BalanceCalculator.totalIncome(txs), 2500000);
    });

    test('returns 0 when no income', () {
      final txs = [_tx(amount: 500000, type: 'expense')];
      expect(BalanceCalculator.totalIncome(txs), 0.0);
    });
  });

  group('BalanceCalculator.totalExpenses', () {
    test('sums only expenses', () {
      final txs = [
        _tx(amount: 200000, type: 'expense'),
        _tx(amount: 50000, type: 'expense'),
        _tx(amount: 2000000, type: 'income'),
      ];
      expect(BalanceCalculator.totalExpenses(txs), 250000);
    });

    test('returns 0 when no expenses', () {
      final txs = [_tx(amount: 2000000, type: 'income')];
      expect(BalanceCalculator.totalExpenses(txs), 0.0);
    });
  });

  group('BalanceCalculator.filterByDateRange', () {
    final txs = [
      _tx(id: 'jan', date: '2026-01-15'),
      _tx(id: 'feb', date: '2026-02-01'),
      _tx(id: 'mar', date: '2026-03-31'),
    ];

    test('filters inclusive on both ends', () {
      final result = BalanceCalculator.filterByDateRange(
        txs,
        DateTime(2026, 1, 15),
        DateTime(2026, 2, 1),
      );
      expect(result.map((t) => t.id).toList(), containsAll(['jan', 'feb']));
      expect(result.length, 2);
    });

    test('excludes transactions outside range', () {
      final result = BalanceCalculator.filterByDateRange(
        txs,
        DateTime(2026, 2, 1),
        DateTime(2026, 2, 28),
      );
      expect(result.length, 1);
      expect(result.first.id, 'feb');
    });

    test('returns empty for out-of-bounds range', () {
      final result = BalanceCalculator.filterByDateRange(
        txs,
        DateTime(2025, 1, 1),
        DateTime(2025, 12, 31),
      );
      expect(result, isEmpty);
    });

    test('single-day range works (from == to)', () {
      final result = BalanceCalculator.filterByDateRange(
        txs,
        DateTime(2026, 1, 15),
        DateTime(2026, 1, 15),
      );
      expect(result.length, 1);
      expect(result.first.id, 'jan');
    });
  });

  group('BalanceCalculator.filterByMonth', () {
    final txs = [
      _tx(id: 'mar-1', date: '2026-03-01'),
      _tx(id: 'mar-2', date: '2026-03-15'),
      _tx(id: 'apr', date: '2026-04-01'),
      _tx(id: 'prev-year', date: '2025-03-01'),
    ];

    test('returns only transactions for the given month+year', () {
      final result = BalanceCalculator.filterByMonth(txs, 3, 2026);
      expect(result.length, 2);
      expect(result.every((t) => t.date.month == 3 && t.date.year == 2026), isTrue);
    });

    test('excludes same month in different year', () {
      final result = BalanceCalculator.filterByMonth(txs, 3, 2025);
      expect(result.length, 1);
      expect(result.first.id, 'prev-year');
    });

    test('returns empty when no transactions in month', () {
      final result = BalanceCalculator.filterByMonth(txs, 6, 2026);
      expect(result, isEmpty);
    });
  });

  group('BalanceCalculator.filterByCategory', () {
    final txs = [
      _tx(id: 'food-1', categoryId: 'cat-food'),
      _tx(id: 'food-2', categoryId: 'cat-food'),
      _tx(id: 'transport', categoryId: 'cat-transport'),
      _tx(id: 'no-cat', categoryId: null),
    ];

    test('returns only transactions for given category', () {
      final result = BalanceCalculator.filterByCategory(txs, 'cat-food');
      expect(result.length, 2);
      expect(result.every((t) => t.categoryId == 'cat-food'), isTrue);
    });

    test('returns empty when category has no transactions', () {
      final result = BalanceCalculator.filterByCategory(txs, 'cat-health');
      expect(result, isEmpty);
    });

    test('null category transactions are excluded', () {
      final result = BalanceCalculator.filterByCategory(txs, 'cat-food');
      expect(result.any((t) => t.categoryId == null), isFalse);
    });
  });

  group('BalanceCalculator.filterByAccount', () {
    final txs = [
      _tx(id: 'a1', accountId: 'acc-savings'),
      _tx(id: 'a2', accountId: 'acc-savings'),
      _tx(id: 'a3', accountId: 'acc-cc'),
    ];

    test('filters by account ID', () {
      final result = BalanceCalculator.filterByAccount(txs, 'acc-savings');
      expect(result.length, 2);
    });

    test('returns empty for unknown account', () {
      final result = BalanceCalculator.filterByAccount(txs, 'acc-unknown');
      expect(result, isEmpty);
    });
  });

  group('BalanceCalculator.spendingByCategory', () {
    final txs = [
      _tx(id: 'f1', amount: 80000, type: 'expense', categoryId: 'cat-food'),
      _tx(id: 'f2', amount: 120000, type: 'expense', categoryId: 'cat-food'),
      _tx(id: 't1', amount: 50000, type: 'expense', categoryId: 'cat-transport'),
      _tx(id: 'i1', amount: 3000000, type: 'income', categoryId: 'cat-salary'),
      _tx(id: 'no-cat', amount: 10000, type: 'expense', categoryId: null),
    ];

    test('groups expenses by category ID', () {
      final result = BalanceCalculator.spendingByCategory(txs);
      expect(result['cat-food'], 200000);
      expect(result['cat-transport'], 50000);
    });

    test('excludes income from expense spending', () {
      final result = BalanceCalculator.spendingByCategory(txs);
      expect(result.containsKey('cat-salary'), isFalse);
    });

    test('excludes transactions without category', () {
      final result = BalanceCalculator.spendingByCategory(txs);
      expect(result.containsKey(null), isFalse);
    });

    test('can aggregate income by category with type override', () {
      final result = BalanceCalculator.spendingByCategory(txs, type: 'income');
      expect(result['cat-salary'], 3000000);
    });

    test('returns empty map when no matching transactions', () {
      final result = BalanceCalculator.spendingByCategory([], type: 'expense');
      expect(result, isEmpty);
    });
  });

  group('BalanceCalculator.savingsRate', () {
    test('returns correct savings rate', () {
      final txs = [
        _tx(amount: 5000000, type: 'income'),
        _tx(amount: 3000000, type: 'expense'),
      ];
      // (5M - 3M) / 5M = 0.4
      expect(BalanceCalculator.savingsRate(txs), closeTo(0.4, 0.001));
    });

    test('returns 0 when income is 0 (avoids division by zero)', () {
      final txs = [_tx(amount: 100000, type: 'expense')];
      expect(BalanceCalculator.savingsRate(txs), 0.0);
    });

    test('returns 1.0 when there are no expenses', () {
      final txs = [_tx(amount: 3000000, type: 'income')];
      expect(BalanceCalculator.savingsRate(txs), closeTo(1.0, 0.001));
    });

    test('returns negative rate when expenses exceed income', () {
      final txs = [
        _tx(amount: 1000000, type: 'income'),
        _tx(amount: 2000000, type: 'expense'),
      ];
      // (1M - 2M) / 1M = -1.0
      expect(BalanceCalculator.savingsRate(txs), closeTo(-1.0, 0.001));
    });

    test('returns 0 for empty list', () {
      expect(BalanceCalculator.savingsRate([]), 0.0);
    });
  });

  group('BalanceCalculator.yearlySummary', () {
    test('returns 12 entries', () {
      final result = BalanceCalculator.yearlySummary([], 2026);
      expect(result.length, 12);
    });

    test('correctly accumulates monthly income and expenses', () {
      final txs = [
        _tx(id: 'jan-income', amount: 5000000, type: 'income', date: '2026-01-15'),
        _tx(id: 'jan-expense', amount: 2000000, type: 'expense', date: '2026-01-20'),
        _tx(id: 'mar-income', amount: 5000000, type: 'income', date: '2026-03-05'),
      ];
      final result = BalanceCalculator.yearlySummary(txs, 2026);
      final jan = result.firstWhere((r) => r['month'] == 1);
      final mar = result.firstWhere((r) => r['month'] == 3);
      final feb = result.firstWhere((r) => r['month'] == 2);

      expect(jan['income'], 5000000.0);
      expect(jan['expense'], 2000000.0);
      expect(mar['income'], 5000000.0);
      expect(feb['income'], 0.0);
      expect(feb['expense'], 0.0);
    });

    test('ignores transactions from other years', () {
      final txs = [
        _tx(id: 'other-year', amount: 999999, type: 'income', date: '2025-01-01'),
      ];
      final result = BalanceCalculator.yearlySummary(txs, 2026);
      final jan = result.firstWhere((r) => r['month'] == 1);
      expect(jan['income'], 0.0);
    });

    test('ignores transfers', () {
      final txs = [
        _tx(id: 'transfer', amount: 500000, type: 'transfer', date: '2026-06-15'),
      ];
      final result = BalanceCalculator.yearlySummary(txs, 2026);
      final jun = result.firstWhere((r) => r['month'] == 6);
      expect(jun['income'], 0.0);
      expect(jun['expense'], 0.0);
    });

    test('month numbers are 1-indexed', () {
      final result = BalanceCalculator.yearlySummary([], 2026);
      final months = result.map((r) => r['month'] as int).toList();
      expect(months, containsAll([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]));
    });
  });

  // ─── FinanceRepository: balance aggregation helpers (inline logic) ─────────

  group('FinanceRepository inline balance aggregation', () {
    // These tests reproduce the fold logic used in getMonthlyIncome /
    // getTotalBudgeted directly, ensuring it works with edge-case data.

    test('getMonthlyIncome fold: returns 0 for empty result', () {
      final List<Map<String, dynamic>> result = [];
      final total = result.fold<double>(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());
      expect(total, 0.0);
    });

    test('getMonthlyIncome fold: sums correctly', () {
      final List<Map<String, dynamic>> result = [
        {'amount': 3000000},
        {'amount': 500000.50},
      ];
      final total = result.fold<double>(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());
      expect(total, closeTo(3500000.50, 0.01));
    });

    test('getTotalBudgeted fold: sums multiple budget amounts', () {
      final List<Map<String, dynamic>> result = [
        {'amount': 800000},
        {'amount': 200000},
        {'amount': 500000},
      ];
      final total = result.fold<double>(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());
      expect(total, 1500000.0);
    });

    test('amounts as int are correctly cast to double in fold', () {
      final List<Map<String, dynamic>> result = [
        {'amount': 1000}, // int, not double
      ];
      final total = result.fold<double>(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());
      expect(total, isA<double>());
      expect(total, 1000.0);
    });
  });

  // ─── Repository date-range query string helpers ───────────────────────────

  group('Date range query string helpers (used in repo filters)', () {
    // Reproduces the string-formatting logic used in getMonthlyIncome
    String startDate(int month, int year) =>
        '$year-${month.toString().padLeft(2, '0')}-01';

    String endDate(int month, int year) => month == 12
        ? '${year + 1}-01-01'
        : '$year-${(month + 1).toString().padLeft(2, '0')}-01';

    test('January start date formatted correctly', () {
      expect(startDate(1, 2026), '2026-01-01');
    });

    test('December end date rolls over to next year', () {
      expect(endDate(12, 2026), '2027-01-01');
    });

    test('November end date is correct', () {
      expect(endDate(11, 2026), '2026-12-01');
    });

    test('single-digit months are zero-padded', () {
      for (int m = 1; m <= 9; m++) {
        expect(startDate(m, 2026), startsWith('2026-0$m'));
      }
    });

    test('double-digit months are not padded', () {
      expect(startDate(10, 2026), '2026-10-01');
      expect(startDate(11, 2026), '2026-11-01');
      expect(startDate(12, 2026), '2026-12-01');
    });

    test('start and end dates are always consecutive months', () {
      for (int m = 1; m <= 11; m++) {
        final start = DateTime.parse(startDate(m, 2026));
        final end = DateTime.parse(endDate(m, 2026));
        expect(end.isAfter(start), isTrue);
        // endDate is exclusive (same as lt query), so distance is ~1 month
        expect(end.month - start.month, 1);
      }
    });
  });
}
