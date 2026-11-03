import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/core/utils/card_recommendation.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';
import 'package:budgett_frontend/data/repositories/bank_repository.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

/// Everything the card ranking needs: the accounts, the bank catalog, and the
/// user-edited billing-calendar entries that override computed dates.
///
/// Shared by the "Best card today" card in the app and the home-screen widget
/// sync, so both rank from the same data.
typedef CardRankingInputs = ({
  List<Account> accounts,
  List<Bank> banks,
  BillingOverrideLookup overrides,
});

final cardRankingInputsProvider =
    FutureProvider<CardRankingInputs>((ref) async {
  final accounts = await ref.watch(accountsProvider.future);
  final banks = await ref.watch(banksFutureProvider.future);

  // Two years covers every billing period a purchase from now — or from any
  // day in the widget's 62-day schedule — can land in.
  final now = DateTime.now();
  final keys = [
    for (final account in creditCardAccounts(accounts))
      if (account.creditCardRules != null)
        for (final year in [now.year, now.year + 1])
          (accountId: account.id, year: year),
  ];
  // Watched before any is awaited, so an edit to one calendar re-runs this.
  final futures = [
    for (final key in keys)
      ref.watch(billingCalendarProvider(key).future).catchError(
          // An unreadable override table must not hide the recommendation;
          // the computed dates are still right for nearly every month.
          (_) => <int, ({DateTime cutoff, DateTime payment})>{}),
  ];
  final calendars = await Future.wait(futures);

  final overrides = <String,
      Map<({int year, int month}), ({DateTime cutoff, DateTime payment})>>{};
  for (var i = 0; i < keys.length; i++) {
    final acctMap = overrides.putIfAbsent(keys[i].accountId, () => {});
    for (final entry in calendars[i].entries) {
      acctMap[(year: keys[i].year, month: entry.key)] = entry.value;
    }
  }

  return (
    accounts: accounts,
    banks: banks,
    overrides: (String id, int y, int m) => overrides[id]?[(year: y, month: m)],
  );
});

/// Credit cards ranked for a purchase made today, best first, plus why the
/// list may be empty.
final cardRecommendationsTodayProvider = FutureProvider<
    ({CardRecommendationStatus status, List<CardRecommendation> ranked})>(
  (ref) async {
    final inputs = await ref.watch(cardRankingInputsProvider.future);
    final ranked = rankCardsForPurchase(
      accounts: inputs.accounts,
      banks: inputs.banks,
      purchaseDate: DateTime.now(),
      overrideLookup: inputs.overrides,
    );
    final status = ranked.isNotEmpty
        ? CardRecommendationStatus.ok
        : creditCardAccounts(inputs.accounts).isEmpty
            ? CardRecommendationStatus.noCards
            : CardRecommendationStatus.noRules;
    return (status: status, ranked: ranked);
  },
);
