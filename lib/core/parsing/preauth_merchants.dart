/// Merchants whose first message is not the final amount.
///
/// Ride-hailing authorises the fare before the trip and settles afterwards,
/// so the alert that arrives at pickup is a hold, not the charge. The same
/// shape appears at fuel pumps, hotels and car rentals, which block an
/// estimate and release the difference days later.
///
/// Auto-posting those records the wrong number and leaves the user correcting
/// an entry they never chose to make, so the "record future ones
/// automatically" switch starts OFF for them. It is only the default — a user
/// who turns it on for their own reasons keeps it on, both here and in the
/// merchant editor.
library;

/// Distinctive words, matched against a [normalizeMerchant] key. Each is a
/// substring test because acquirers decorate the name: Uber reaches this app
/// as "UBER BV USD-USD COLO", "UBER *TRIP" and "UBER RIDES".
const _preauthorizingTokens = {
  // Ride-hailing.
  'UBER', 'DIDI', 'CABIFY', 'INDRIVE', 'INDRIVER', 'BEAT', 'LYFT',
  // Fuel: the pump authorises a round figure, then charges what was pumped.
  'ESTACION DE SERVICIO', 'TERPEL', 'PRIMAX', 'BIOMAX', 'TEXACO', 'MOBIL',
  // Lodging and rentals hold a deposit on top of the stay.
  'HOTEL', 'HOSTAL', 'AIRBNB', 'BOOKING', 'EXPEDIA', 'DESPEGAR',
  'RENT A CAR', 'RENTACAR', 'HERTZ', 'AVIS', 'LOCALIZA',
};

/// True when this merchant bills before the final amount is known.
///
/// Takes an already-normalised key; returns false for null so a message with
/// no merchant simply follows the ordinary default.
bool chargesInAdvance(String? merchantKey) {
  if (merchantKey == null || merchantKey.isEmpty) return false;
  for (final token in _preauthorizingTokens) {
    if (merchantKey.contains(token)) return true;
  }
  return false;
}

/// One short line explaining the default, for the review sheet. Null when the
/// merchant is an ordinary one and there is nothing to explain.
String? preauthReason(String? merchantKey) => chargesInAdvance(merchantKey)
    ? 'This merchant charges before the final amount is known, so it will '
        'keep asking'
    : null;
