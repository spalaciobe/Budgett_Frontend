import '../../data/models/account_model.dart';
import '../../data/models/investment_details_model.dart';
import '../../data/models/investment_holding_model.dart';
import '../../data/models/fx_rate_model.dart';

/// Result of a total-value computation for an investment account.
class InvestmentTotalValue {
  /// Cash component in [baseCurrency] (accounts.balance / balance_usd).
  final double cash;

  /// Market value of all holdings, converted to [baseCurrency].
  final double marketValue;

  /// Total = cash + marketValue, in [baseCurrency].
  final double total;

  /// COP equivalent of [total]. Equals [total] when baseCurrency == 'COP',
  /// or total × fxRate when baseCurrency == 'USD'.
  final double totalCop;

  /// True when [totalCop] used an fx conversion and should be displayed with ≈.
  final bool isApprox;

  const InvestmentTotalValue({
    required this.cash,
    required this.marketValue,
    required this.total,
    required this.totalCop,
    required this.isApprox,
  });
}

/// Result of a P&L computation across a list of holdings.
class InvestmentPnl {
  /// Total cost basis in the account's base currency.
  final double costBasis;

  /// Current market value in the account's base currency.
  final double marketValue;

  /// Unrealized P&L = marketValue - costBasis.
  final double pnl;

  /// P&L as a percentage of cost basis (0 when costBasis == 0).
  final double pnlPct;

  const InvestmentPnl({
    required this.costBasis,
    required this.marketValue,
    required this.pnl,
    required this.pnlPct,
  });
}

class InvestmentCalculator {
  // ── Total value ────────────────────────────────────────────────────────────

  /// Computes total value for an investment account.
  ///
  /// [fxRate] is used only when holdings or the account itself are in USD and
  /// the base currency requires COP conversion. Pass null to skip conversion
  /// (totalCop will equal total, isApprox = false).
  static InvestmentTotalValue computeTotalValue(
    Account account,
    List<InvestmentHolding> holdings, {
    FxRate? fxRate,
  }) {
    final details = account.investmentDetails;
    final baseCurrency = details?.baseCurrency ?? 'COP';

    // Cash component: use the appropriate balance column
    final cash =
        baseCurrency == 'USD' ? account.balanceUsd : account.balance;

    // Market value: sum of holding market values converted to baseCurrency
    double marketValue = 0.0;
    bool needsFx = false;

    for (final h in holdings) {
      if (h.currency == baseCurrency) {
        marketValue += h.marketValue;
      } else if (h.currency == 'USD' && baseCurrency == 'COP') {
        // Holding is USD, account is COP → convert
        if (fxRate != null) {
          marketValue += h.marketValue * fxRate.rate;
          needsFx = true;
        }
        // If no fx rate, omit the USD holding from the COP total
      } else if (h.currency == 'COP' && baseCurrency == 'USD') {
        // Holding is COP, account is USD → convert
        if (fxRate != null) {
          marketValue += h.marketValue / fxRate.rate;
          needsFx = true;
        }
      }
    }

    final total = cash + marketValue;

    // COP total
    double totalCop;
    bool isApprox;

    if (baseCurrency == 'COP') {
      totalCop = total;
      isApprox = needsFx; // only approx if some USD holding was converted
    } else {
      // baseCurrency == 'USD'
      if (fxRate != null) {
        totalCop = total * fxRate.rate;
        isApprox = true;
      } else {
        totalCop = total; // fallback — caller should show USD only
        isApprox = false;
      }
    }

    return InvestmentTotalValue(
      cash: cash,
      marketValue: marketValue,
      total: total,
      totalCop: totalCop,
      isApprox: isApprox,
    );
  }

  // ── P&L ───────────────────────────────────────────────────────────────────

  /// Aggregates unrealized P&L across all holdings.
  ///
  /// All holdings are expected to share the same [currency] (or conversion is
  /// skipped for simplicity in this MVP). For multi-currency portfolios, call
  /// per-holding unrealizedPnl and convert at the widget layer.
  static InvestmentPnl computePnl(List<InvestmentHolding> holdings) {
    double costBasis = 0.0;
    double marketValue = 0.0;

    for (final h in holdings) {
      costBasis += h.costBasis;
      marketValue += h.marketValue;
    }

    final pnl = marketValue - costBasis;
    final pnlPct = costBasis == 0 ? 0.0 : (pnl / costBasis) * 100.0;

    return InvestmentPnl(
      costBasis: costBasis,
      marketValue: marketValue,
      pnl: pnl,
      pnlPct: pnlPct,
    );
  }

  // ── CDT helpers ───────────────────────────────────────────────────────────

  /// Projects the CDT value at [asOf] date using simple-interest approximation.
  ///
  ///   V(t) = principal × (1 + annualRate × daysElapsed/365)
  ///
  /// Returns the original [principal] if required fields are null.
  static double projectCdtValue(InvestmentDetails details, DateTime asOf) {
    final principal = details.principal;
    final rate = details.interestRate;
    final start = details.startDate;

    if (principal == null || rate == null || start == null) {
      return principal ?? 0.0;
    }

    final daysElapsed = asOf.difference(start).inDays.clamp(0, details.termDays ?? 9999);
    return principal * (1 + rate * daysElapsed / 365);
  }

  /// Projected total value at maturity.
  static double projectCdtMaturityValue(InvestmentDetails details) {
    final maturity = details.maturityDate;
    if (maturity == null) return details.principal ?? 0.0;
    return projectCdtValue(details, maturity);
  }

  /// Accrued interest so far (today).
  static double cdtAccruedInterest(InvestmentDetails details) {
    final today = DateTime.now();
    return projectCdtValue(details, today) - (details.principal ?? 0.0);
  }

  /// Days remaining until maturity. Returns 0 if already matured or maturity
  /// date is unknown.
  static int cdtDaysToMaturity(InvestmentDetails details) {
    final maturity = details.maturityDate;
    if (maturity == null) return 0;
    final diff = maturity.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// True when the CDT has passed its maturity date.
  static bool isCdtMatured(InvestmentDetails details) {
    final maturity = details.maturityDate;
    if (maturity == null) return false;
    return DateTime.now().isAfter(maturity);
  }

  // ── High-yield helpers ───────────────────────────────────────────────────

  /// Projected annual income from a high-yield account balance.
  ///
  ///   income = balance × apyRate
  static double projectedAnnualIncome(double balance, double apyRate) {
    return balance * apyRate;
  }

  /// Monthly income estimate (annual / 12).
  static double projectedMonthlyIncome(double balance, double apyRate) {
    return projectedAnnualIncome(balance, apyRate) / 12;
  }

  // ── avg_cost recalculation on buy ────────────────────────────────────────

  /// Weighted-average cost after buying [buyQty] units at [buyPrice] on top of
  /// an existing position of [currentQty] units at [currentAvgCost].
  static double newAvgCost({
    required double currentQty,
    required double currentAvgCost,
    required double buyQty,
    required double buyPrice,
  }) {
    final totalQty = currentQty + buyQty;
    if (totalQty == 0) return 0;
    return (currentQty * currentAvgCost + buyQty * buyPrice) / totalQty;
  }
}
