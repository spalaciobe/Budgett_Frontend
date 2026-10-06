/// Matches an account the user named out loud against the ones they have.
///
/// People say the bank, not the account: "doscientos mil a Bancolombia", when
/// the account is called "Bancolombia Ahorro". So the match is on words, not
/// on the whole string.
///
/// Ambiguity returns nothing. Someone with "Bancolombia Ahorro" and "Amex Oro
/// Bancolombia" who says "Bancolombia" could mean either, and guessing puts
/// real money against the wrong balance — an empty account field costs one
/// tap, the wrong one costs a correction in two places.
library;

import 'package:budgett_frontend/core/parsing/text_normalizer.dart';
import 'package:budgett_frontend/data/models/account_model.dart';

/// Words in account names that identify no account on their own.
const _genericAccountWords = {
  'CUENTA', 'AHORRO', 'AHORROS', 'CORRIENTE', 'DEBITO', 'CREDITO',
  'TARJETA', 'EFECTIVO', 'CASH', 'ACCOUNT', 'SAVINGS', 'CARD', 'MI', 'DE',
  'LA', 'EL', 'MY', 'THE', 'USD', 'COP',
};

/// The id of the one account [spoken] can mean, or null.
String? matchSpokenAccount(String spoken, List<Account> accounts) {
  // Two characters, because "Nu" is a bank here. Short filler cannot match
  // anything anyway: the account side drops its own generic words, so a
  // spoken "de" would have to meet an account literally named "De".
  final words = normalizeMerchant(spoken)
      .split(RegExp(r'[^A-Z0-9]+'))
      .where((w) => w.length >= 2)
      .toSet();
  if (words.isEmpty) return null;

  final hits = <String>{};
  for (final account in accounts) {
    final nameWords = normalizeMerchant(account.name)
        .split(RegExp(r'[^A-Z0-9]+'))
        .where((w) => w.length >= 2 && !_genericAccountWords.contains(w))
        .toSet();
    if (nameWords.isEmpty) continue;
    if (nameWords.any(words.contains)) hits.add(account.id);
  }

  // Exactly one, or the user has to say which.
  return hits.length == 1 ? hits.single : null;
}
