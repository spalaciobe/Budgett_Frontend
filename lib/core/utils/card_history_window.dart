import '../../data/models/transaction_model.dart';

/// Which transactions a credit-card screen loads.
///
/// Card screens group rows by billing period (`periodo_facturacion`) and show
/// a total per period, so they must load whole periods. A fixed row count
/// (the old `limit: 100`) cuts the oldest visible period in half and shows a
/// wrong total for it. Pre-generated installment cuotas, dated months ahead,
/// make that worse because they take up part of the count.
///
/// The window covers the current month's period and the [periods] - 1 before
/// it, plus every future period.
class CardHistoryWindow {
  static const int defaultPeriods = 6;

  /// Oldest billing period kept, as `YYYY-MM` (inclusive).
  final String firstPeriod;

  /// Oldest `date` to query. It starts before [firstPeriod]'s purchases on
  /// purpose: a period's purchases begin after the previous cutoff, and
  /// statement backfills can carry an earlier date. [keeps] drops the extra
  /// rows that belong to older periods.
  final DateTime fetchFrom;

  /// Rows with no billing period (pending charges, untagged payments) are
  /// kept from this date on.
  final DateTime untaggedFrom;

  const CardHistoryWindow._(this.firstPeriod, this.fetchFrom, this.untaggedFrom);

  factory CardHistoryWindow.from(DateTime now,
      {int periods = defaultPeriods}) {
    assert(periods >= 1);
    final first = DateTime(now.year, now.month - (periods - 1));
    final firstPeriod =
        '${first.year}-${first.month.toString().padLeft(2, '0')}';
    return CardHistoryWindow._(
      firstPeriod,
      DateTime(first.year, first.month - 2),
      DateTime(first.year, first.month - 1),
    );
  }

  bool keeps(Transaction t) {
    final period = t.billingPeriod;
    if (period == null || period.isEmpty) {
      return !t.date.isBefore(untaggedFrom);
    }
    return period.compareTo(firstPeriod) >= 0;
  }
}
