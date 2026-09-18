import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budgett_frontend/data/models/category_spending.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/repositories/finance_repository.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

/// Counts the reads behind Home's summary card.
class _CountingRepository extends FinanceRepository {
  _CountingRepository() : super(_StubClient());

  int incomeCalls = 0;
  int spendingCalls = 0;

  @override
  Future<List<Transaction>> getRecentTransactions() async => const [];

  @override
  Future<double> getMonthlyIncome(int month, int year) async {
    incomeCalls++;
    return 1_000_000;
  }

  @override
  Future<Map<String, CategorySpending>> getSpendingByCategory(
    int month,
    int year,
  ) async {
    spendingCalls++;
    return {};
  }
}

/// The repository needs a client it never reaches: every method this test
/// touches is overridden above.
class _StubClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('the month summary recomputes when the transaction list changes',
      () async {
    // Home's card showed the figures from before an edit, because every write
    // path invalidates the transaction list and none of them invalidated the
    // summary. The summary depends on the list now, so this holds without any
    // call site having to remember it.
    final repo = _CountingRepository();
    final container = ProviderContainer(
      overrides: [financeRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    // Keep a listener alive: these providers are autoDispose.
    container.listen(homeMonthSummaryProvider, (_, __) {});

    await container.read(homeMonthSummaryProvider.future);
    expect(repo.incomeCalls, 1);
    expect(repo.spendingCalls, 1);

    // What saving a transaction does.
    container.invalidate(recentTransactionsProvider);
    await container.read(homeMonthSummaryProvider.future);

    expect(repo.incomeCalls, 2, reason: 'income was not recomputed');
    expect(repo.spendingCalls, 2, reason: 'spending was not recomputed');
  });
}
