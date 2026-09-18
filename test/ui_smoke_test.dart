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
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budgett_frontend/core/app_palette.dart';
import 'package:budgett_frontend/core/app_theme.dart';
import 'package:budgett_frontend/core/services/capture_ingest_service.dart';
import 'package:budgett_frontend/core/services/message_capture_service.dart';
import 'package:budgett_frontend/core/services/update_checker_service.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/budget_model.dart';
import 'package:budgett_frontend/data/models/capture_source_model.dart';
import 'package:budgett_frontend/data/models/captured_message_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/category_spending.dart';
import 'package:budgett_frontend/data/models/expense_group_model.dart';
import 'package:budgett_frontend/data/models/goal_model.dart';
import 'package:budgett_frontend/data/models/investment_holding_model.dart';
import 'package:budgett_frontend/data/models/investment_purchase_event_model.dart';
import 'package:budgett_frontend/data/models/investment_price_history_model.dart';
import 'package:budgett_frontend/data/models/merchant_alias_model.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/repositories/finance_repository.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/providers/message_capture_provider.dart';
import 'package:budgett_frontend/presentation/providers/settings_provider.dart';
import 'package:budgett_frontend/presentation/screens/capture_inbox_screen.dart';
import 'package:budgett_frontend/presentation/screens/capture_settings_screen.dart';
import 'package:budgett_frontend/presentation/screens/categories_screen.dart';
import 'package:budgett_frontend/presentation/screens/expense_groups_screen.dart';
import 'package:budgett_frontend/presentation/screens/goals_screen.dart';
import 'package:budgett_frontend/presentation/screens/home_screen.dart';
import 'package:budgett_frontend/presentation/screens/credit_card_details_screen.dart';
import 'package:budgett_frontend/presentation/screens/accounts_screen.dart';
import 'package:budgett_frontend/presentation/screens/investment_details_screen.dart';
import 'package:budgett_frontend/presentation/screens/plan_screen.dart';
import 'package:budgett_frontend/presentation/screens/more_screen.dart';
import 'package:budgett_frontend/presentation/screens/budget_screen.dart';
import 'package:budgett_frontend/presentation/screens/recurring_transactions_screen.dart';
import 'package:budgett_frontend/data/models/sub_category_model.dart';
import 'package:budgett_frontend/presentation/widgets/account_card.dart';
import 'package:budgett_frontend/presentation/widgets/budget_comparison_widget.dart';
import 'package:budgett_frontend/presentation/widgets/investment_holding_card.dart';
import 'package:budgett_frontend/presentation/widgets/portfolio_donut_chart.dart';
import 'package:budgett_frontend/presentation/widgets/review_capture_sheet.dart';
import 'package:budgett_frontend/presentation/widgets/transaction_tile.dart';
import 'package:budgett_frontend/presentation/widgets/add_transaction_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/edit_transaction_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/update_available_dialog.dart';
import 'package:budgett_frontend/data/repositories/message_capture_repository.dart';

// Each case is (label, size, dark). The theme matters: until now this
// harness rendered every screen with a bare `MaterialApp()`, i.e. Flutter's
// default Material 3 baseline (the lilac background in older screenshots) —
// so the PNGs never showed Budgett's own surfaces, and reviewing colour or
// contrast in them was meaningless. Dark mode gets a pass of its own because
// the two themes are where this app diverged most.
/// (label, size, dark, textScale).
///
/// The text scale matters as much as the width: a phone reports ~390dp
/// whatever the owner's font-size setting, and rows that fit at 1.0 overflow
/// at 1.3. A 3.4px overflow reported from a real device was invisible here
/// until this axis existed.
const _breakpoints = <(String, Size, bool, double)>[
  ('mobile', Size(390, 844), false, 1.0),
  ('desktop', Size(1440, 900), false, 1.0),
  // A real monitor, not a small laptop. Layouts that look merely airy at
  // 1440 are half-empty here, and a capped body shows it.
  ('wide', Size(1920, 1080), false, 1.0),
  ('mobile_dark', Size(390, 844), true, 1.0),
  ('mobile_large_text', Size(390, 844), false, 1.3),
];

// ─── fixture builders ─────────────────────────────────────────────────────────

Account _account({
  String id = 'acc',
  String name = 'Bancolombia Ahorro',
  String type = 'savings',
  double balance = 2_500_000,
  double balanceUsd = 0,
  double creditLimit = 0,
  Map<String, dynamic>? investmentDetails,
}) =>
    Account.fromJson({
      'id': id,
      'name': name,
      'type': type,
      'balance': balance,
      'balance_usd': balanceUsd,
      'credit_limit': creditLimit,
      if (investmentDetails != null) 'investment_details': investmentDetails,
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
    // A stock/ETF account, not a CDT: only this layout shows the
    // Update prices / Swap / Add row that overflowed a phone.
    _account(
      id: 'acc-4',
      name: 'Trii',
      type: 'investment',
      balance: 4_804_540,
      investmentDetails: const {
        'id': 'inv-4',
        'account_id': 'acc-4',
        'investment_type': 'stock_etf',
      },
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

  // Two holdings, because the mobile action row only shows all three buttons
  // (Update prices / Swap / Add) at two or more — which is the combination
  // that overflowed a phone by 3.4px.
  static final _holdings = [
    InvestmentHolding.fromJson({
      'id': 'h1',
      'user_id': 'u1',
      'account_id': 'acc-3',
      'created_at': '2026-01-10T00:00:00Z',
      'updated_at': '2026-09-17T00:00:00Z',
      'symbol': 'IUITCO',
      'name': 'iShares S&P 500 Tech',
      'asset_class': 'etf',
      'currency': 'COP',
      'quantity': 7.0,
      'avg_cost': 144_980.0,
      'current_price': 162_000.0,
    }),
    InvestmentHolding.fromJson({
      'id': 'h2',
      'user_id': 'u1',
      'account_id': 'acc-3',
      'created_at': '2026-01-10T00:00:00Z',
      'updated_at': '2026-09-17T00:00:00Z',
      'symbol': 'ICOLCAP',
      'name': 'iShares COLCAP',
      'asset_class': 'etf',
      'currency': 'COP',
      'quantity': 30.0,
      'avg_cost': 22_575.0,
      'current_price': 25_147.0,
    }),
  ];

  @override
  Future<List<InvestmentHolding>> getHoldings(String accountId) async =>
      _holdings;

  // Anything an investment detail screen reaches for. Without these the screen
  // renders "Something went wrong", and a screenshot of an error page catches
  // no layout bugs at all — which is exactly what happened on the first pass.
  @override
  Future<List<Transaction>> getTransactionsForAccounts(
    List<String> accountIds, {
    int limit = 50,
  }) async =>
      _transactions;

  @override
  Future<double> accountFundedTotal(String accountId) async => 5_000_000;

  @override
  Future<List<InvestmentPriceHistory>> getInvestmentPriceHistory(
    String accountId, {
    int days = 30,
  }) async =>
      [];

  @override
  Future<List<InvestmentPurchaseEvent>> getInvestmentPurchaseEvents(
    String accountId,
    List<InvestmentHolding> holdings,
  ) async =>
      [];

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
  @override
  Future<double> getMonthlyIncome(int month, int year) async => 5_000_000;
  @override
  Future<Map<String, CategorySpending>> getSpendingByCategory(
          int month, int year) async =>
      {'cat-1': CategorySpending(total: 320_000)};
  @override
  Future<Map<String, CategorySpending>> getIncomeByCategory(
          int month, int year) async =>
      {'cat-3': CategorySpending(total: 5_000_000)};
  @override
  Future<Map<String, double>> getCategoryAccumulatedBalances() async =>
      const {};
}

List<Override> financeOverrides() => [
      financeRepositoryProvider.overrideWithValue(_FakeFinanceRepository()),
    ];

// -- message-capture fixtures -------------------------------------------------

CapturedMessage _capturedMessage({
  String id = 'cap-1',
  String status = 'pending',
  String parseStatus = 'parsed',
  String channel = 'notification',
  double? amount = 45900,
  String? merchantDisplay = 'Exito',
  String? merchantRaw = 'EXITO SUPER CL 80',
  String? locationLabel = 'Calle 80 #45-12, Bogota',
  String kind = 'purchase',
  String? error,
}) =>
    CapturedMessage.fromJson({
      'id': id,
      'source_id': 'src-1',
      'channel': channel,
      'source_key': 'com.bancolombia.olimpia',
      'title': 'Bancolombia',
      'body': r'Bancolombia le informa Compra por $45.900,00 en '
          'EXITO SUPER CL 80 17/09/2026 15:44. Tarjeta *1234',
      'received_at': '2026-09-17T20:44:00Z',
      'occurred_at': '2026-09-17T20:44:00Z',
      'latitude': 4.6851,
      'longitude': -74.0546,
      'location_label': locationLabel,
      'parse_status': parseStatus,
      'issuer_key': 'bancolombia',
      'merchant_raw': merchantRaw,
      'merchant_display': merchantDisplay,
      'amount': amount,
      'currency': 'COP',
      'card_last4': '1234',
      'kind': kind,
      'confidence': 0.95,
      'status': status,
      'fingerprint': 'fp-$id',
      'error': error,
    });

final _captureSources = [
  CaptureSource.fromJson({
    'id': 'src-1',
    'channel': 'notification',
    'source_key': 'com.bancolombia.olimpia',
    'detected_name': 'Bancolombia',
    'display_name': 'Bancolombia',
    'issuer_key': 'bancolombia',
    'default_account_id': 'acc-1',
    'is_enabled': true,
    'message_count': 42,
    'last_seen_at': '2026-09-17T20:44:00Z',
  }),
  CaptureSource.fromJson({
    'id': 'src-2',
    'channel': 'sms',
    'source_key': '890255',
    'detected_name': '890255',
    'issuer_key': 'bancolombia',
    'is_enabled': true,
    'message_count': 18,
    'last_seen_at': '2026-09-17T20:47:00Z',
  }),
];

final _merchantAliases = [
  MerchantAlias.fromJson({
    'id': 'alias-1',
    'match_type': 'exact',
    'pattern': 'EXITO SUPER CL 80',
    'display_name': 'Exito',
    'category_id': 'cat-1',
    'auto_post': true,
    'priority': 100,
    'hit_count': 12,
  }),
  MerchantAlias.fromJson({
    'id': 'alias-2',
    'match_type': 'contains',
    'pattern': 'RAPPI',
    'display_name': 'Rappi',
    'category_id': 'cat-1',
    'auto_post': false,
    'priority': 90,
    'hit_count': 3,
  }),
];

const _captureStatus = CaptureStatus(
  enabled: true,
  smsEnabled: true,
  locationEnabled: true,
  notificationAccess: true,
  smsPermission: true,
  locationPermission: true,
  backgroundLocationPermission: true,
  queued: 0,
  isSupported: true,
);

/// Capture providers hit Supabase and the platform channel, so every one the
/// new screens read is stubbed out here.
List<Override> _captureOverrides({
  List<CapturedMessage>? pending,
  List<CapturedMessage>? history,
  CaptureStatus status = _captureStatus,
}) =>
    [
      ...financeOverrides(),
      captureStatusProvider.overrideWith((ref) async => status),
      captureSourcesProvider.overrideWith((ref) async => _captureSources),
      merchantAliasesProvider.overrideWith((ref) async => _merchantAliases),
      pendingCapturesProvider
          .overrideWith((ref) async => pending ?? [_capturedMessage()]),
      captureHistoryProvider.overrideWith((ref) async => history ?? const []),
      captureSettingsProvider.overrideWith(_StubCaptureSettings.new),
      messageCaptureRepositoryProvider
          .overrideWithValue(_StubCaptureRepository()),
    ];

/// The merchant sheet counts the movements it would rename before offering to
/// rename them; without this the count would reach Supabase.
class _StubCaptureRepository extends MessageCaptureRepository {
  _StubCaptureRepository() : super(_StubSupabaseClient());

  @override
  Future<int> countRecordedUnder(String name) async => 3;
}

class _StubSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Keeps `captureSettingsProvider` off SharedPreferences so the screenshot is
/// deterministic.
class _StubCaptureSettings extends CaptureSettingsNotifier {
  @override
  Future<CaptureSettings> build() async => const CaptureSettings(
        autoPostEnabled: true,
        minConfidence: 0.8,
        autoPostMaxAmount: 500000,
      );
}

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
  'budget_comparison_over': _Target(() => _wrap(
        BudgetComparisonWidget(
          categoryName: 'Leisure',
          budgetAmount: 500000,
          spentAmount: 820328,
          color: const Color(0xFFE91E63),
          onEditBudget: () {},
          onEditCategory: () {},
          onViewTransactions: () {},
          subCategories: [
            SubCategory.fromJson(
                {'id': 's1', 'category_id': 'c1', 'name': 'Eating out'}),
            SubCategory.fromJson(
                {'id': 's2', 'category_id': 'c1', 'name': 'Delivery'}),
          ],
          subCategorySpending: const {'s1': 525100, 's2': 230000},
        ),
        maxWidth: 440,
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
    overrides: financeOverrides(),
  ),
  // Home when the capture inbox has something waiting: the pill is the only
  // difference, and it has to stay a single row.
  'screen_home_inbox_pending': _Target(
    () => const HomeScreen(),
    overrides: _captureOverrides(
      pending: [
        _capturedMessage(),
        _capturedMessage(id: 'cap-9', amount: 250000, kind: 'transfer_in'),
      ],
    ),
  ),
  'dialog_edit_transaction': _Target(
    () => Scaffold(
      body: EditTransactionDialog(transaction: _tx(accountId: 'acc-1')),
    ),
    overrides: financeOverrides(),
  ),
  // The form people use most, and the one that had fourteen fields on screen
  // at once. Captured collapsed (the default) so the shot shows what someone
  // actually faces when they tap +.
  'dialog_add_transaction': _Target(
    () => const Scaffold(body: AddTransactionDialog()),
    overrides: financeOverrides(),
  ),
  'screen_categories': _Target(
    () => const CategoriesScreen(),
    overrides: financeOverrides(),
  ),
  'screen_goals': _Target(
    () => const GoalsScreen(),
    overrides: financeOverrides(),
  ),
  'screen_expense_groups': _Target(
    () => const ExpenseGroupsScreen(),
    overrides: financeOverrides(),
  ),
  'screen_recurring_transactions': _Target(
    () => const RecurringTransactionsScreen(),
    overrides: financeOverrides(),
  ),
  // Account detail screens were never rendered here, which is how a title
  // collapsed to one letter per line and reached production unseen.
  'screen_credit_card_details': _Target(
    () => const CreditCardDetailsScreen(accountId: 'acc-2'),
    overrides: financeOverrides(),
  ),
  'screen_accounts': _Target(
    () => const AccountsScreen(),
    overrides: financeOverrides(),
  ),
  'screen_investment_details': _Target(
    () => const InvestmentDetailsScreen(accountId: 'acc-4'),
    overrides: financeOverrides(),
  ),
  // The reworked navigation: Plan's four tabs, and what's left in More.
  'screen_plan': _Target(
    () => const PlanScreen(),
    overrides: financeOverrides(),
  ),
  'screen_more': _Target(
    () => const MoreScreen(),
    overrides: financeOverrides(),
  ),
  'screen_budget': _Target(
    () => const BudgetScreen(),
    overrides: financeOverrides(),
  ),
  // -- message capture --
  'capture_card_pending': _Target(
    () => _wrap(CaptureCard(message: _capturedMessage()), maxWidth: 560),
    overrides: _captureOverrides(),
  ),
  'capture_card_duplicate': _Target(
    () => _wrap(
      CaptureCard(
        message: _capturedMessage(
          id: 'cap-2',
          status: 'duplicate',
          channel: 'sms',
          error: 'Same card and amount',
        ),
      ),
      maxWidth: 560,
    ),
    overrides: _captureOverrides(),
  ),
  'capture_card_unparsed': _Target(
    () => _wrap(
      CaptureCard(
        message: _capturedMessage(
          id: 'cap-3',
          parseStatus: 'unparsed',
          amount: null,
          merchantDisplay: null,
          merchantRaw: null,
          locationLabel: null,
        ),
      ),
      maxWidth: 560,
    ),
    overrides: _captureOverrides(),
  ),
  'review_capture_sheet': _Target(
    () => ReviewCaptureSheet(message: _capturedMessage()),
    overrides: _captureOverrides(),
  ),
  'screen_capture_inbox': _Target(
    () => const CaptureInboxScreen(),
    overrides: _captureOverrides(
      pending: [
        _capturedMessage(),
        _capturedMessage(
          id: 'cap-4',
          channel: 'sms',
          amount: 12000,
          merchantDisplay: 'Juan Valdez',
          merchantRaw: 'JUAN VALDEZ CL 93',
          error: 'An expense with this amount is already recorded today',
        ),
      ],
      history: [
        _capturedMessage(id: 'cap-5', status: 'posted', locationLabel: null),
      ],
    ),
  ),
  'screen_capture_inbox_needs_permission': _Target(
    () => const CaptureInboxScreen(),
    overrides: _captureOverrides(
      pending: const [],
      status: const CaptureStatus(
        enabled: true,
        smsEnabled: true,
        locationEnabled: true,
        isSupported: true,
      ),
    ),
  ),
  'screen_capture_settings': _Target(
    () => const CaptureSettingsScreen(),
    overrides: _captureOverrides(),
  ),
  'sheet_edit_merchant': _Target(
    // showModalBottomSheet supplies the Material in the app; here it doesn't.
    () => Material(child: EditMerchantSheet(alias: _merchantAliases.first)),
    overrides: _captureOverrides(),
  ),
};

// ─── harness ──────────────────────────────────────────────────────────────────

/// Registers the bundled fonts with the test binding.
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await load('OpenSans', const [
    'assets/fonts/OpenSans-Regular.ttf',
    'assets/fonts/OpenSans-Medium.ttf',
    'assets/fonts/OpenSans-SemiBold.ttf',
    'assets/fonts/OpenSans-Bold.ttf',
  ]);
  await load('SpaceGrotesk', const [
    'assets/fonts/SpaceGrotesk-Variable.ttf',
  ]);
}

Future<File> captureBoundary(WidgetTester tester, Key key, String name) async {
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
    // Without this every glyph renders as an empty box, which hides exactly
    // the problems (truncation, line wrap, figure alignment) the screenshots
    // exist to catch.
    await loadAppFonts();
  });

  for (final entry in _targets.entries) {
    for (final (label, size, dark, textScale) in _breakpoints) {
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
              theme: dark
                  ? const AppTheme(AppPalette.lime).dark
                  : const AppTheme(AppPalette.lime).light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
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

        final out = await captureBoundary(tester, captureKey, '${entry.key}_$label');
        expect(out.existsSync(), isTrue);
        expect(out.lengthSync(), greaterThan(0));
      });
    }
  }
}
