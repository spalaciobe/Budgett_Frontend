/// Recognises a captured message as an instance of a recurring transaction.
///
/// This matters beyond convenience: the recurring engine already generates a
/// transaction for each cycle, so auto-posting the bank's alert for the same
/// charge records it twice. Two of this user's dismissed captures —
/// "Transacción aprobada en Suramericana" at 91,983 and "SMART FIT 20 DE
/// JULI" at 101,500 — match an active recurring to the peso.
library;

import 'package:budgett_frontend/core/parsing/text_normalizer.dart';
import 'package:budgett_frontend/data/models/recurring_transaction_model.dart';

class RecurringMatch {
  final RecurringTransaction recurring;

  /// True when the names agree as well as the amount. A name match makes it
  /// near-certain; the amount alone is a strong hint worth surfacing but not
  /// worth acting on unasked.
  final bool nameAlsoMatches;

  const RecurringMatch({
    required this.recurring,
    required this.nameAlsoMatches,
  });

  String get label => recurring.description;
}

/// Recurring amounts are fixed, so the amount is the primary signal; a peso of
/// slack absorbs rounding between sources.
const _amountTolerance = 1.0;

/// Finds the active recurring transaction this movement looks like.
///
/// Requires an exact-ish amount and the same direction. Returns null rather
/// than guessing: the cost of a false match is an expense the user has to
/// re-enter, and these only ever gate automation, never replace a decision.
RecurringMatch? findRecurringMatch({
  required double? amount,
  required String? transactionType,
  required String? merchantKey,
  required List<RecurringTransaction> recurring,
}) {
  if (amount == null || transactionType == null) return null;

  RecurringMatch? weaker;

  for (final candidate in recurring) {
    if (!candidate.isActive) continue;
    if (candidate.type != transactionType) continue;
    if ((candidate.amount - amount).abs() > _amountTolerance) continue;

    if (_namesAgree(candidate.description, merchantKey)) {
      return RecurringMatch(recurring: candidate, nameAlsoMatches: true);
    }
    weaker ??= RecurringMatch(recurring: candidate, nameAlsoMatches: false);
  }

  return weaker;
}

/// True when the two names share a distinctive word.
///
/// "Gym - Smart Fit" against "SMART FIT 20 DE JULI", and "Health Insurance
/// SURA" against "SURAMERICANA DE SEGUROS", both have to agree, so the test
/// is a shared token with prefix tolerance rather than equality. Short and
/// generic words are skipped so "DE", "LA" or "PAGO" cannot pair unrelated
/// names.
bool _namesAgree(String recurringName, String? merchantKey) {
  if (merchantKey == null || merchantKey.isEmpty) return false;

  final left = _distinctiveTokens(normalizeMerchant(recurringName));
  final right = _distinctiveTokens(merchantKey);
  if (left.isEmpty || right.isEmpty) return false;

  for (final a in left) {
    for (final b in right) {
      if (a == b) return true;
      // Four characters, because the real pair this has to catch is "SURA"
      // inside "SURAMERICANA DE SEGUROS". Three would let "CAS", "SAN" or
      // "COL" pair half of Colombia.
      if (a.length >= 4 && b.startsWith(a)) return true;
      if (b.length >= 4 && a.startsWith(b)) return true;
    }
  }
  return false;
}

const _genericWords = {
  'DE', 'DEL', 'LA', 'EL', 'LOS', 'LAS', 'Y', 'A', 'EN', 'POR', 'PARA',
  'PAGO', 'COMPRA', 'MONTHLY', 'PLUS', 'CARD', 'FEE', 'POCKET', 'SAS', 'SA',
};

Set<String> _distinctiveTokens(String name) => name
    .split(RegExp(r'[^A-Z0-9]+'))
    .where((token) => token.length >= 3 && !_genericWords.contains(token))
    .toSet();
