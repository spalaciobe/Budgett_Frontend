/// How dates are written in this app.
///
/// There were seven formats in play: `dd/MM/yyyy`, `d MMM`, `MMM d`,
/// `d MMM yyyy`, `MMMM yyyy`, `dd/MM/yyyy HH:mm` and three built by hand — so
/// the same screen could show "18 Sep" in one row and "Sep 18" in the next,
/// and a credit-card timeline paired "18 sept" with "15/10/2026".
///
/// Two decisions settle it:
///
/// * **Day before month.** This is a Colombian app; `09/10` is October 9th to
///   half its readers and September 10th to the other half. An abbreviated
///   month name can't be misread.
/// * **The year only when it isn't obvious.** In a list of this month's
///   transactions "18 Sep 2026" is four characters of noise per row.
library;

import 'package:intl/intl.dart';

/// "18 Sep" — for rows and labels inside a period the reader already knows.
String formatDayMonth(DateTime date) => DateFormat('d MMM', 'en').format(date);

/// "18 Sep 2026" — whenever the year carries information: statement dates,
/// deadlines, anything a year or more away.
String formatFullDate(DateTime date) =>
    DateFormat('d MMM yyyy', 'en').format(date);

/// "18 Sep" within the current year, "18 Sep 2026" outside it.
String formatSmartDate(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  return date.year == reference.year
      ? formatDayMonth(date)
      : formatFullDate(date);
}

/// "September 2026" — month headers and period pickers.
String formatMonthYear(DateTime date) =>
    DateFormat('MMMM yyyy', 'en').format(date);

/// "18 Sep, 14:05" — only where the time is part of the fact, such as a
/// captured bank message.
String formatDateTime(DateTime date) =>
    DateFormat('d MMM, HH:mm', 'en').format(date);
