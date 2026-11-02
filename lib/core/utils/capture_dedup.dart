/// Deduplication for captured messages.
///
/// The same payment routinely reaches the phone two or three times: the bank's
/// push notification, the bank's SMS, and sometimes a wallet app on top
/// (Nequi mirrors Bancolombia, RappiCard mirrors the purchase). Android also
/// re-posts a notification when its text is updated, which arrives as a fresh
/// capture.
///
/// Time cannot go into a hash — the copies land seconds to minutes apart — so
/// matching is a windowed comparison instead: identical amount, close in time,
/// plus at least one corroborating signal (same card, same merchant, the
/// same issuer when one copy omitted the merchant, or a merchant's receipt
/// whose sender names the card issuer or merchant of the charge).
///
/// The bias is deliberately towards NOT declaring a duplicate. A false
/// positive silently swallows a real expense; a false negative shows up as two
/// rows in the inbox that the user dismisses in one tap.
library;

/// Minimal shape needed to compare two movements, whether they came from a
/// message or from an already-recorded transaction.
class DedupCandidate {
  final String id;
  final double amount;
  final String currency;

  /// Normalised merchant key (see `normalizeMerchant`).
  final String? merchantKey;
  final String? cardLast4;
  final String? issuerKey;
  final DateTime occurredAt;

  /// Who sent the message — the notification title, which for an email is
  /// the sender's display name ("Recibos de Rappi"). Lets a merchant's own
  /// receipt be tied to the card charge it accompanies.
  final String? senderText;

  /// True when the timestamp is only accurate to the day — the case for
  /// transactions whose `occurred_at` is null and only `date` is known.
  final bool dayPrecisionOnly;

  const DedupCandidate({
    required this.id,
    required this.amount,
    required this.occurredAt,
    this.currency = 'COP',
    this.merchantKey,
    this.cardLast4,
    this.issuerKey,
    this.senderText,
    this.dayPrecisionOnly = false,
  });
}

enum DuplicateReason {
  /// Same card and amount within the window — the strongest signal.
  sameCardAndAmount,

  /// Same merchant and amount within the window.
  sameMerchantAndAmount,

  /// Same issuer and amount within the window, with one side missing the
  /// merchant. Weaker, but the common push-vs-SMS shape.
  sameIssuerAndAmount,

  /// A merchant's own receipt and the card charge for it: one side carries a
  /// card and the other does not, and the receipt's sender names the card's
  /// issuer or merchant — "Recibos de Rappi" next to a RappiCard charge.
  receiptForCardCharge,

  /// An amount already recorded on the same day by a transaction that did not
  /// come from this capture pipeline (typed by hand, most likely).
  existingTransactionSameDay;

  String get label => switch (this) {
        DuplicateReason.sameCardAndAmount => 'Same card and amount',
        DuplicateReason.sameMerchantAndAmount => 'Same merchant and amount',
        DuplicateReason.sameIssuerAndAmount => 'Same bank and amount',
        DuplicateReason.receiptForCardCharge =>
          'Receipt for the same card charge',
        DuplicateReason.existingTransactionSameDay =>
          'An expense with this amount is already recorded today',
      };
}

class DuplicateVerdict {
  /// Id of the thing the candidate duplicates.
  final String matchId;
  final DuplicateReason reason;

  /// True when the match is solid enough to file the capture away as a
  /// duplicate without asking. False means "warn, but let the user decide".
  final bool isConclusive;

  const DuplicateVerdict({
    required this.matchId,
    required this.reason,
    required this.isConclusive,
  });
}

/// Default tolerance between two copies of the same payment.
const kDefaultDedupWindow = Duration(minutes: 10);

/// Window for a merchant's receipt against its card charge. A delivery order
/// carries two instants — placed and delivered, 24 minutes apart on a real
/// Rappi receipt — and the card may be charged at either.
const kReceiptDedupWindow = Duration(hours: 2);

/// Amounts are compared with a one-peso tolerance: issuers sometimes round the
/// figure differently between the push and the SMS.
const _amountTolerance = 1.0;

bool _amountsMatch(DedupCandidate a, DedupCandidate b) =>
    a.currency == b.currency && (a.amount - b.amount).abs() <= _amountTolerance;

bool _withinWindow(DedupCandidate a, DedupCandidate b, Duration window) {
  final effective = (a.dayPrecisionOnly || b.dayPrecisionOnly)
      ? const Duration(hours: 24)
      : window;
  return a.occurredAt.difference(b.occurredAt).abs() <= effective;
}

/// Coarse, time-free key. Stored on the row so the server-side lookup can
/// narrow candidates before the windowed comparison runs in Dart.
String dedupHash(
    {required double amount,
    String currency = 'COP',
    String? merchantKey,
    String? cardLast4}) {
  final cents = (amount * 100).round();
  return [
    currency,
    cents,
    cardLast4 ?? '-',
    merchantKey ?? '-',
  ].join('|');
}

/// True when two merchant keys refer to the same place.
///
/// Containment counts because issuers truncate at different lengths: one sends
/// `EXITO`, another `EXITO SUPER CL 80`. Containment is only trusted when the
/// shorter key is at least 4 characters, so `ARA` does not swallow `ARARAT`.
bool merchantsMatch(String? a, String? b) {
  if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  if (shorter.length < 4) return false;
  // Require the shorter key to be a whole-word prefix of the longer one.
  return longer == shorter || longer.startsWith('$shorter ');
}

/// Words of a sender name worth matching on: four letters or more, so "de"
/// and "la" never tie two messages together.
Set<String> _senderWords(String? sender) => sender == null
    ? const {}
    : sender
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9áéíóúñü]+'))
        .where((w) => w.length >= 4)
        .toSet();

/// True when [sender] names the issuer or the merchant of [charge] — the
/// merchant counts by its first word, the brand ("RAPPI" of "RAPPI COLOMBIA").
bool senderNames(String? sender, DedupCandidate charge) {
  final words = _senderWords(sender);
  if (words.isEmpty) return false;
  final issuer = charge.issuerKey?.toLowerCase();
  if (issuer != null && words.contains(issuer)) return true;
  final brand = charge.merchantKey?.toLowerCase().split(' ').first;
  return brand != null && brand.length >= 4 && words.contains(brand);
}

/// True when [receipt] is a merchant's receipt for the card charge [charge].
/// Only the side WITHOUT a card can be the receipt: two card messages with
/// different cards are two payments, whatever the sender says. And it must
/// not come from the charge's own bank — a bank's push without the card next
/// to its SMS with it stays the weaker [DuplicateReason.sameIssuerAndAmount].
bool isReceiptForCharge(DedupCandidate receipt, DedupCandidate charge) =>
    receipt.cardLast4 == null &&
    charge.cardLast4 != null &&
    (receipt.issuerKey == null || receipt.issuerKey != charge.issuerKey) &&
    senderNames(receipt.senderText, charge);

/// Looks for an earlier capture that [candidate] duplicates.
///
/// [existing] should already be narrowed to the same user and a sensible date
/// range; the function does the precise work. Returns null when the candidate
/// looks new.
DuplicateVerdict? findDuplicateCapture(
  DedupCandidate candidate,
  List<DedupCandidate> existing, {
  Duration window = kDefaultDedupWindow,
}) {
  DuplicateVerdict? weaker;

  for (final other in existing) {
    if (other.id == candidate.id) continue;
    if (!_amountsMatch(candidate, other)) continue;
    if (!_withinWindow(candidate, other, window)) {
      // Only the receipt signal is trusted beyond the ordinary window.
      final receiptWindow =
          window > kReceiptDedupWindow ? window : kReceiptDedupWindow;
      if (_withinWindow(candidate, other, receiptWindow) &&
          (isReceiptForCharge(candidate, other) ||
              isReceiptForCharge(other, candidate))) {
        return DuplicateVerdict(
          matchId: other.id,
          reason: DuplicateReason.receiptForCardCharge,
          isConclusive: true,
        );
      }
      continue;
    }

    final sameCard = candidate.cardLast4 != null &&
        candidate.cardLast4 == other.cardLast4;
    if (sameCard) {
      return DuplicateVerdict(
        matchId: other.id,
        reason: DuplicateReason.sameCardAndAmount,
        isConclusive: true,
      );
    }

    if (merchantsMatch(candidate.merchantKey, other.merchantKey)) {
      return DuplicateVerdict(
        matchId: other.id,
        reason: DuplicateReason.sameMerchantAndAmount,
        isConclusive: true,
      );
    }

    // Conclusive: the receipt names the shop it came from, which never
    // matches the card's merchant text, so nothing else ties the two — and
    // they are the same purchase by construction.
    if (isReceiptForCharge(candidate, other) ||
        isReceiptForCharge(other, candidate)) {
      return DuplicateVerdict(
        matchId: other.id,
        reason: DuplicateReason.receiptForCardCharge,
        isConclusive: true,
      );
    }

    // One side has no merchant: same bank + same amount + same minute is very
    // likely the same payment, but not certain enough to hide it outright.
    final oneMerchantMissing =
        candidate.merchantKey == null || other.merchantKey == null;
    final sameIssuer = candidate.issuerKey != null &&
        candidate.issuerKey == other.issuerKey;
    if (oneMerchantMissing && sameIssuer) {
      weaker ??= DuplicateVerdict(
        matchId: other.id,
        reason: DuplicateReason.sameIssuerAndAmount,
        isConclusive: false,
      );
    }
  }

  return weaker;
}

/// Looks for an already-recorded transaction that would collide with
/// [candidate] — typically one the user typed by hand before the message
/// arrived.
///
/// Never conclusive: two identical coffees on the same day are legitimate.
/// The verdict blocks auto-posting and surfaces a warning in the inbox.
DuplicateVerdict? findTransactionCollision(
  DedupCandidate candidate,
  List<DedupCandidate> transactions, {
  Duration window = kDefaultDedupWindow,
}) {
  for (final tx in transactions) {
    if (!_amountsMatch(candidate, tx)) continue;
    if (!_withinWindow(candidate, tx, window)) continue;
    return DuplicateVerdict(
      matchId: tx.id,
      reason: merchantsMatch(candidate.merchantKey, tx.merchantKey)
          ? DuplicateReason.sameMerchantAndAmount
          : DuplicateReason.existingTransactionSameDay,
      isConclusive: false,
    );
  }
  return null;
}
