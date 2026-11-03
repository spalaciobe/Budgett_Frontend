/// Which credit card to use for a purchase today: the one whose bill for it
/// comes due last.
///
/// A purchase the day after a card's cut-off lands in the next cycle and is
/// paid roughly 45 days later; the same purchase the day before is paid in a
/// couple of weeks. Ranking every card by that gap is the whole feature. The
/// cycle math itself stays in [CreditCardCalculator] — this file only orders
/// its answers and shapes them for the home-screen widget.
library;

import 'package:intl/intl.dart';

import '../../data/models/account_model.dart';
import '../../data/models/bank_model.dart';
import 'credit_card_calculator.dart';

/// User-edited billing-calendar entry for an account's billing period, as
/// read from `bank_billing_calendar`.
typedef BillingOverrideLookup = ({DateTime cutoff, DateTime payment})? Function(
    String accountId, int year, int month);

class CardRecommendation {
  final Account account;
  final DateTime cutoff;
  final DateTime payment;

  /// Calendar days from the purchase to the payment due date.
  final int daysToPay;

  const CardRecommendation({
    required this.account,
    required this.cutoff,
    required this.payment,
    required this.daysToPay,
  });
}

/// Why there is nothing to recommend, so the widget can say what to fix.
enum CardRecommendationStatus { ok, noCards, noRules }

/// Every credit card with billing rules, best first.
///
/// Cards without rules, or whose bank is missing from the catalog, are left
/// out: without a cut-off date there is no honest answer for them. Pockets are
/// included when they are credit cards with rules of their own.
List<CardRecommendation> rankCardsForPurchase({
  required List<Account> accounts,
  required List<Bank> banks,
  required DateTime purchaseDate,
  BillingOverrideLookup? overrideLookup,
}) {
  final bankById = {for (final b in banks) b.id: b};
  final results = <CardRecommendation>[];

  for (final account in creditCardAccounts(accounts)) {
    final rules = account.creditCardRules;
    if (rules == null) continue;
    final bank = bankById[rules.bankId];
    if (bank == null) continue;

    final schedule = CreditCardCalculator.scheduleForPurchase(
      purchaseDate,
      rules,
      bank,
      overrideFor: overrideLookup == null
          ? null
          : (y, m) => overrideLookup(account.id, y, m),
    );
    results.add(CardRecommendation(
      account: account,
      cutoff: schedule.cutoff,
      payment: schedule.payment,
      daysToPay:
          CreditCardCalculator.daysBetween(purchaseDate, schedule.payment),
    ));
  }

  results.sort((a, b) {
    final byDays = b.daysToPay.compareTo(a.daysToPay);
    if (byDays != 0) return byDays;
    return a.account.name.toLowerCase().compareTo(b.account.name.toLowerCase());
  });
  return results;
}

/// Credit-card accounts, top-level and pockets alike, each once.
List<Account> creditCardAccounts(List<Account> accounts) {
  final seen = <String>{};
  final out = <Account>[];
  for (final a in [...accounts, for (final a in accounts) ...a.pockets]) {
    if (a.type == 'credit_card' && seen.add(a.id)) out.add(a);
  }
  return out;
}

/// What the home-screen widget shows, precomputed for [days] days from [from].
///
/// The widget runs with no Flutter engine, so it cannot do the cycle math
/// itself — and must not, since [CreditCardCalculator] is the only place that
/// math lives. Instead the app writes one entry per day and the widget picks
/// today's, which keeps it right across a cut-off date even if the app is not
/// opened for weeks. Labels are rendered here so the native side only copies
/// strings into views.
Map<String, dynamic> buildCardWidgetSnapshot({
  required List<Account> accounts,
  required List<Bank> banks,
  required DateTime from,
  int days = 62,
  int maxCards = 3,
  BillingOverrideLookup? overrideLookup,
}) {
  final cards = creditCardAccounts(accounts);
  final dayKey = DateFormat('yyyy-MM-dd');
  final dueLabel = DateFormat('EEE, MMM d', 'en_US');

  final entries = <Map<String, dynamic>>[];
  var status = cards.isEmpty
      ? CardRecommendationStatus.noCards
      : CardRecommendationStatus.noRules;

  if (cards.isNotEmpty) {
    final start = DateTime(from.year, from.month, from.day);
    for (var i = 0; i < days; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      final ranked = rankCardsForPurchase(
        accounts: accounts,
        banks: banks,
        purchaseDate: day,
        overrideLookup: overrideLookup,
      );
      if (ranked.isEmpty) break;
      status = CardRecommendationStatus.ok;
      entries.add({
        'date': dayKey.format(day),
        'cards': [
          for (final r in ranked.take(maxCards))
            {
              'name': r.account.name,
              'daysToPay': r.daysToPay,
              'due': dayKey.format(r.payment),
              'dueLabel': 'Due ${dueLabel.format(r.payment)}',
            },
        ],
      });
    }
  }

  return {
    'version': 1,
    'generatedAt': from.toIso8601String(),
    'status': status.name,
    'days': entries,
  };
}
