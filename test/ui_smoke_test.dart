// UI smoke test — renders parametrised widgets AND full screens at multiple
// breakpoints and dumps a PNG to test/screenshots/. Run with
// `flutter test test/ui_smoke_test.dart`.
//
// Why: analyze + unit tests pass, but they don't catch broken layouts. The
// harness gives a low-cost way to verify visual changes without a device.
//
// To add a widget/screen: add a `_Target` to `_targets` below. If it consumes
// Riverpod providers, supply `overrides:` with mocks (see screen targets).
//
// Note: real I/O (PNG writes, RenderRepaintBoundary.toImage) MUST be wrapped
// in `tester.runAsync` because testWidgets uses a fake-time zone where
// awaiting real-world async would deadlock.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budgett_frontend/core/services/update_checker_service.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/budget_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/expense_group_model.dart';
import 'package:budgett_frontend/data/models/goal_model.dart';
import 'package:budgett_frontend/data/models/investment_holding_model.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/repositories/finance_repository.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/screens/categories_screen.dart';
import 'package:budgett_frontend/presentation/screens/expense_groups_screen.dart';
import 'package:budgett_frontend/presentation/screens/goals_screen.dart';
import 'package:budgett_frontend/presentation/screens/home_screen.dart';
import 'package:budgett_frontend/presentation/screens/recurring_transactions_screen.dart';
import 'package:budgett_frontend/presentation/widgets/account_card.dart';
import 'package:budgett_frontend/presentation/widgets/investment_holding_card.dart';
import 'package:budgett_frontend/presentation/widgets/portfolio_donut_chart.dart';
import 'package:budgett_frontend/presentation/widgets/transaction_tile.dart';
import 'package:budgett_frontend/presentation/widgets/update_available_dialog.dart';

const _breakpoints = <(String, Size)>[
  ('mobile', Size(390, 844)),
  ('desktop', Size(1440, 900)),
];

// ─── fixture builders ─────────────────────────────────────────────────────────

Account _account({
  String id = 'acc',
  String name = 'Bancolombia Ahorro',
  String type = 'savings',
  double balance = 2_500_000,
  double balanceUsd = 0,
  double creditLimit = 0,
}) =>
    Account.fromJson({
      'id': id,
      'name': name,
      'type': type,
      'balance': balance,
      'balance_usd': balanceUsd,
      'credit_limit': creditLimit,
    });

Transaction _tx({
  String id = 'tx',
  String description = 'Mercado',
  String type = 'expense',
  double amount = 250_000,
  String status = 'cleared',
  String date = '2026-04-15',
  String? place,
  String accountId = 'acc',
}) =>
    Transaction.fromJson({
      'id': id,
      'account_id': accountId,
      'amount': amount,
      'description': description,
      'date': date,
      'type': type,
      'status': status,
      if (place != null) 'place': place,
    });

InvestmentHolding _holding({
  String symbol = 'BTC',
  String assetClass = 'crypto',
  String currency = 'USD',
  double qty = 0.05,
  double avgCost = 50000,
  double price = 65000,
}) =>
    InvestmentHolding.fromJson({
      'id': 'h',
      'user_id': 'u',
      'account_id': 'acc',
      'symbol': symbol,
      'asset_class': assetClass,
      'currency': currency,
      'quantity': qty,
      'avg_cost': avgCost,
      'current_price': price,
      'is_cash_equivalent': false,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-04-01T00:00:00Z',
    });

// ─── fake repository (mirrors patterns used in finance_provider_test.dart) ────

class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeFinanceRepository extends FinanceRepository {
  _FakeFinanceRepository() : super(_FakeSupabaseClient());

  static final _accounts = [
    _account(id: 'acc-1', name: 'Bancolombia Ahorro', balance: 2_500_000),
    _account(
      id: 'acc-2',
      name: 'Visa Bancolombia',
      type: 'credit_card',
      balance: -480_000,
      creditLimit: 5_000_000,
    ),
    _account(
      id: 'acc-3',
      name: 'Tyba CDT',
      type: 'investment',
      balance: 1_200_000,
    ),
  ];

  static final _transactions = [
    _tx(id: 't1', description: 'Salario', type: 'income', amount: 5_000_000, date: '2026-04-01'),
    _tx(id: 't2', description: 'Mercado Éxito', amount: 320_000),
    _tx(id: 't3', description: 'Netflix', amount: 49_900, date: '2026-04-05', accountId: 'acc-2'),
    _tx(id: 't4', description: 'Uber', amount: 18_500, date: '2026-04-12', status: 'pending'),
  ];

  static final _categories = [
    Category.fromJson({'id': 'cat-1', 'name': 'Food', 'type': 'expense', 'icon': 'restaurant', 'color': '#FF5722', 'sub_categories': []}),
    Category.fromJson({'id': 'cat-2', 'name': 'Transport', 'type': 'expense', 'icon': 'directions_car', 'color': '#2196F3', 'sub_categories': []}),
    Category.fromJson({'id': 'cat-3', 'name': 'Salary', 'type': 'income', 'icon': 'attach_money', 'color': '#4CAF50', 'sub_categories': []}),
  ];

  static final _budgets = [
    Budget.fromJson({'id': 'b1', 'category_id': 'cat-1', 'amount': 800_000.0, 'month': 4, 'year': 2026}),
    Budget.fromJson({'id': 'b2', 'category_id': 'cat-2', 'amount': 200_000.0, 'month': 4, 'year': 2026}),
  ];

  static final _goals = [
    Goal.fromJson({
      'id': 'g1', 'name': 'Emergency Fund', 'target_amount': 10_000_000.0,
      'current_amount': 4_500_000.0, 'deadline': null, 'icon_name': 'savings',
      'created_at': '2026-01-01T00:00:00Z',
    }),
    Goal.fromJson({
      'id': 'g2', 'name': 'Vacation Cartagena', 'target_amount': 3_000_000.0,
      'current_amount': 800_000.0, 'deadline': '2026-12-15', 'icon_name': 'flight',
      'created_at': '2026-02-01T00:00:00Z',
    }),
  ];

  static final _expenseGroups = [
    ExpenseGroup.fromJson({'id': 'eg1', 'name': 'First half April', 'start_date': '2026-04-01', 'end_date': '2026-04-15', 'budget_amount': 1_500_000.0}),
    ExpenseGroup.fromJson({'id': 'eg2', 'name': 'Cartagena trip', 'start_date': '2026-05-01', 'end_date': '2026-05-08', 'budget_amount': 2_000_000.0}),
  ];

  static final _recurringTransactions = [
    RecurringTransaction.fromJson({'id': 'r1', 'description': 'Netflix', 'amount': 49_900.0, 'type': 'expense', 'frequency': 'monthly', 'next_run_date': '2026-05-01', 'is_active': true}),
    RecurringTransaction.fromJson({'id': 'r2', 'description': 'Spotify', 'amount': 16_900.0, 'type': 'expense', 'frequency': 'monthly', 'next_run_date': '2026-05-05', 'is_active': true}),
  ];

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
  Future<List<Map<String, dynamic>>> getYearlySummary(int year) async =>
      List.generate(12, (i) => {'month': i + 1, 'income': 5_000_000.0, 'expense': 2_500_000.0});
}

List<Override> _financeOverrides() => [
      financeRepositoryProvider.overrideWithValue(_FakeFinanceRepository()),
    ];

// ─── targets ──────────────────────────────────────────────────────────────────

class _Target {
  final Widget Function() builder;
  final List<Override> overrides;
  const _Target(this.builder, {this.overrides = const []});
}

Widget _wrap(Widget child, {double maxWidth = 380}) => Padding(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );

final _targets = <String, _Target>{
  // ─── widgets ──
  'update_available_dialog': _Target(() => const UpdateAvailableDialog(
        info: UpdateInfo(
          latestVersionName: '1.2.0',
          latestBuildNumber: 17,
          currentVersionName: '1.0.0',
          currentBuildNumber: 5,
          apkUrl: 'https://example.invalid/app.apk',
          releaseNotes: 'Fixes:\n- Speed up budget loading\n- Fix CC alerts',
        ),
      )),
  'account_card_savings': _Target(() => _wrap(
        AccountCard(account: _account(), onTap: () {}, tileLayout: true),
      )),
  'account_card_credit': _Target(() => _wrap(
        AccountCard(
          account: _account(name: 'Visa Bancolombia', type: 'credit_card', balance: -480_000, creditLimit: 5_000_000),
          onTap: () {},
          tileLayout: true,
        ),
      )),
  'account_card_investment_compact': _Target(() => _wrap(
        AccountCard(account: _account(name: 'Tyba CDT', type: 'investment', balance: 1_200_000), onTap: () {}),
        maxWidth: 220,
      )),
  'transaction_tile_expense': _Target(() => _wrap(
        Material(child: TransactionTile(transaction: _tx(), onTap: () {})),
      )),
  'transaction_tile_income': _Target(() => _wrap(
        Material(child: TransactionTile(
          transaction: _tx(description: 'Salario', type: 'income', amount: 5_000_000),
          onTap: () {},
        )),
      )),
  'transaction_tile_pending': _Target(() => _wrap(
        Material(child: TransactionTile(
          transaction: _tx(description: 'Mercado', status: 'pending', place: 'Éxito Calle 80'),
          onTap: () {},
        )),
      )),
  'investment_holding_gain': _Target(() => _wrap(
        InvestmentHoldingCard(holding: _holding(), onBuy: () {}, onSell: () {}, onEdit: () {}, onDelete: () {}),
      )),
  'investment_holding_loss': _Target(() => _wrap(
        InvestmentHoldingCard(
          holding: _holding(symbol: 'AAPL', assetClass: 'stock_etf', avgCost: 200, price: 175, qty: 12),
          onBuy: () {}, onSell: () {}, onEdit: () {}, onDelete: () {},
        ),
      )),
  'portfolio_donut_chart': _Target(() => _wrap(
        const PortfolioDonutChart(
          centerLabel: 'Total',
          centerValue: r'$ 12.4M',
          slices: [
            PortfolioSlice(label: 'CDT', value: 5_000_000, color: Color(0xFF1B998B)),
            PortfolioSlice(label: 'Stocks', value: 4_200_000, color: Color(0xFF8D6A9F)),
            PortfolioSlice(label: 'Crypto', value: 2_500_000, color: Color(0xFFFFBF81)),
            PortfolioSlice(label: 'Cash', value: 700_000, color: Color(0xFFCEF7A0)),
          ],
        ),
        maxWidth: 360,
      )),

  // ─── screens (need provider overrides) ──
  'screen_home': _Target(
    () => const HomeScreen(),
    overrides: _financeOverrides(),
  ),
  'screen_categories': _Target(
    () => const CategoriesScreen(),
    overrides: _financeOverrides(),
  ),
  'screen_goals': _Target(
    () => const GoalsScreen(),
    overrides: _financeOverrides(),
  ),
  'screen_expense_groups': _Target(
    () => const ExpenseGroupsScreen(),
    overrides: _financeOverrides(),
  ),
  'screen_recurring_transactions': _Target(
    () => const RecurringTransactionsScreen(),
    overrides: _financeOverrides(),
  ),
};

// ─── harness ──────────────────────────────────────────────────────────────────

Future<File> _capture(WidgetTester tester, Key key, String name) async {
  final element = tester.element(find.byKey(key));
  final boundary = element.renderObject! as RenderRepaintBoundary;
  final out = File('test/screenshots/$name.png');
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
  });
  return out;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    await initializeDateFormatting('es');
    await initializeDateFormatting('en_US');
    SharedPreferences.setMockInitialValues({});
  });

  for (final entry in _targets.entries) {
    for (final (label, size) in _breakpoints) {
      testWidgets('${entry.key} @ $label', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const captureKey = ValueKey('ui_smoke_capture');
        await tester.pumpWidget(
          ProviderScope(
            overrides: entry.value.overrides,
            child: MaterialApp(
              home: RepaintBoundary(
                key: captureKey,
                child: entry.value.builder(),
              ),
            ),
          ),
        );
        // Pump several frames so async providers resolve their futures.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        final out = await _capture(tester, captureKey, '${entry.key}_$label');
        expect(out.existsSync(), isTrue);
        expect(out.lengthSync(), greaterThan(0));
      });
    }
  }
}
