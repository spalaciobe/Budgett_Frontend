import '../../data/models/credit_card_rules_model.dart';
import '../../data/models/bank_model.dart';
import 'colombian_calendar.dart';

class CreditCardCalculator {

  /// Adjusts a date based on a specific rule (e.g., 'adelantar_dia_habil_anterior')
  static DateTime adjustDateByRule(DateTime date, String? rule) {
    if (rule == null || ColombianCalendar.isBusinessDay(date)) {
      return date;
    }

    switch (rule) {
      case 'adelantar_dia_habil_anterior':
        return ColombianCalendar.getPreviousBusinessDay(date);
      case 'postergar_dia_habil_siguiente':
        return ColombianCalendar.getNextBusinessDay(date);
      default:
        return date;
    }
  }

  /// Calculates the actual cutoff date for a specific month
  static DateTime calculateCutoffDate(CreditCardRules rules, Bank bank, int year, int month) {
    DateTime calculatedDate;

    if (rules.cutoffType == CutoffType.fixed) {
      // Fixed Date Logic
      int day = rules.nominalCutoffDay!;
      // Handle February and months with less days
      int daysInMonth = DateTime(year, month + 1, 0).day;
      if (day > daysInMonth) {
        day = daysInMonth;
      }
      calculatedDate = DateTime(year, month, day);
      calculatedDate = adjustDateByRule(calculatedDate, bank.adjustmentRuleCutoff);

    } else {
      // Relative Date Logic
      List<DateTime> businessDays = ColombianCalendar.getBusinessDaysInMonth(year, month);
      
      switch (rules.relativeCutoffType) {
        case RelativeCutoffType.lastBusinessDay:
          calculatedDate = businessDays.last;
          break;
        case RelativeCutoffType.secondToLastBusinessDay:
           // Safety check if month has enough business days
          if (businessDays.length >= 2) {
             calculatedDate = businessDays[businessDays.length - 2];
          } else {
             // Fallback to last
             calculatedDate = businessDays.last;
          }
          break;
        case RelativeCutoffType.firstBusinessDay:
          calculatedDate = businessDays.first;
          break;
        default:
          calculatedDate = DateTime(year, month, 28); // Fallback
      }
    }

    return calculatedDate;
  }

  /// Calculates the payment date based on the cutoff date
  static DateTime calculatePaymentDate(
      CreditCardRules rules, Bank bank, DateTime cutoffDate) {
    
    DateTime calculatedDate;

    if (rules.paymentType == PaymentType.fixed) {
      int mes = cutoffDate.month;
      int anio = cutoffDate.year;
      
      if (rules.paymentMonth == 'siguiente') {
        mes++;
        if (mes > 12) {
          mes = 1;
          anio++;
        }
      }

      int day = rules.nominalPaymentDay!;
      int daysInMonth = DateTime(anio, mes + 1, 0).day;
      if (day > daysInMonth) {
        day = daysInMonth;
      }
      
      calculatedDate = DateTime(anio, mes, day);
      calculatedDate = adjustDateByRule(calculatedDate, bank.adjustmentRulePayment);

    } else {
      // Relative Days (e.g., 10 days after cutoff)
      if (rules.paymentOffsetType == OffsetType.calendar) {
        calculatedDate = cutoffDate.add(Duration(days: rules.daysAfterCutoff!));
        calculatedDate = adjustDateByRule(calculatedDate, bank.adjustmentRulePayment);
      } else {
        // Business Days offset
        calculatedDate = cutoffDate;
        for (int i = 0; i < rules.daysAfterCutoff!; i++) {
          calculatedDate = ColombianCalendar.getNextBusinessDay(calculatedDate);
        }
      }
    }
    
    return calculatedDate;
  }

  /// Determines the billing period for a transaction date
  /// Returns a string like "2026-01"
  static String determineBillingPeriod(DateTime transactionDate, CreditCardRules rules, Bank bank) {
    // 1. Calculate cutoff for the transaction month
    DateTime cutoffThisMonth = calculateCutoffDate(rules, bank, transactionDate.year, transactionDate.month);

    // 2. If transaction is before or on cutoff, it belongs to this month's period
    if (transactionDate.isBefore(cutoffThisMonth) || transactionDate.isAtSameMomentAs(cutoffThisMonth)) {
       return "${transactionDate.year}-${transactionDate.month.toString().padLeft(2, '0')}";
    } else {
       // 3. Otherwise it belongs to next month's period
       DateTime nextMonthProp = DateTime(transactionDate.year, transactionDate.month + 1);
       return "${nextMonthProp.year}-${nextMonthProp.month.toString().padLeft(2, '0')}";
    }
  }

  /// Cut-off and payment-due dates for a purchase made on [purchaseDate].
  ///
  /// Same cycle assignment as [determineBillingPeriod] (a purchase on the
  /// cut-off day still belongs to that cycle), but compared by calendar day:
  /// a purchase at 15:00 on the cut-off day is not "after" a cut-off stored as
  /// midnight.
  ///
  /// [overrideFor] supplies the user-edited `bank_billing_calendar` entry for a
  /// billing period, when there is one; it wins over the computed dates, as it
  /// does for payment reminders.
  static ({DateTime cutoff, DateTime payment}) scheduleForPurchase(
    DateTime purchaseDate,
    CreditCardRules rules,
    Bank bank, {
    ({DateTime cutoff, DateTime payment})? Function(int year, int month)?
        overrideFor,
  }) {
    final day = _dateOnly(purchaseDate);
    DateTime cutoffFor(int y, int m) =>
        overrideFor?.call(y, m)?.cutoff ?? calculateCutoffDate(rules, bank, y, m);

    var year = day.year;
    var month = day.month;
    var cutoff = cutoffFor(year, month);
    if (day.isAfter(_dateOnly(cutoff))) {
      final next = DateTime(year, month + 1);
      year = next.year;
      month = next.month;
      cutoff = cutoffFor(year, month);
    }

    final payment = overrideFor?.call(year, month)?.payment ??
        calculatePaymentDate(rules, bank, cutoff);
    return (cutoff: _dateOnly(cutoff), payment: _dateOnly(payment));
  }

  /// Whole calendar days from [from] to [to], ignoring the time of day.
  /// Counted in UTC so a DST shift can never turn a day into 23 hours.
  static int daysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The three billing columns a credit-card transaction carries:
  /// `periodo_facturacion`, `fecha_corte_calculada`, `fecha_pago_calculada`.
  ///
  /// Extracted so callers that build a transaction payload without a form —
  /// the message-capture pipeline, for one — derive them from the same place
  /// as the dialogs instead of re-deriving the cycle math.
  static Map<String, dynamic> billingFieldsFor({
    required DateTime date,
    required CreditCardRules rules,
    required Bank bank,
  }) {
    final billingPeriod = determineBillingPeriod(date, rules, bank);
    final parts = billingPeriod.split('-');
    final cutoff = calculateCutoffDate(
        rules, bank, int.parse(parts[0]), int.parse(parts[1]));
    final payment = calculatePaymentDate(rules, bank, cutoff);

    return {
      'periodo_facturacion': billingPeriod,
      'fecha_corte_calculada': cutoff.toIso8601String(),
      'fecha_pago_calculada': payment.toIso8601String(),
    };
  }
}
