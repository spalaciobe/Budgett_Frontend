import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/investment_price_history_model.dart';
import 'finance_provider.dart';
import 'fx_rate_provider.dart';

/// A single position aggregated across every non-high-yield investment account.
class ConsolidatedPosition {
  final String symbol;
  final String displayName;
  final String assetClass;
  final double marketValueCop;
  final double costBasisCop;

  const ConsolidatedPosition({
    required this.symbol,
    required this.displayName,
    required this.assetClass,
    required this.marketValueCop,
    required this.costBasisCop,
  });

  double get pnl => marketValueCop - costBasisCop;
  double get pnlPct =>
      costBasisCop == 0 ? 0 : (pnl / costBasisCop) * 100;
}

/// Total market value contributed by a single investment account.
class ConsolidatedAccountSlice {
  final String accountId;
  final String accountName;
  final double marketValueCop;

  const ConsolidatedAccountSlice({
    required this.accountId,
    required this.accountName,
    required this.marketValueCop,
  });
}

/// Snapshot of every multi-holding investment account's holdings unified
/// in a single base currency (COP).
class ConsolidatedPortfolio {
  final List<ConsolidatedPosition> positions;
  final List<ConsolidatedAccountSlice> byAccount;
  final double totalMarketValueCop;
  final double totalCostBasisCop;
  final bool hasFxConversion;

  const ConsolidatedPortfolio({
    required this.positions,
    required this.byAccount,
    required this.totalMarketValueCop,
    required this.totalCostBasisCop,
    required this.hasFxConversion,
  });

  bool get isEmpty => positions.isEmpty;

  double get totalPnl => totalMarketValueCop - totalCostBasisCop;
  double get totalPnlPct =>
      totalCostBasisCop == 0 ? 0 : (totalPnl / totalCostBasisCop) * 100;
}

/// Aggregates holdings from every `fic | crypto | stock_etf` investment
/// account into a single portfolio view. High-yield and CDT accounts are
/// excluded (they hold no positions). USD holdings are converted to COP
/// using the current TRM; if the rate is unavailable they're included at
/// face value (hasFxConversion stays false).
final consolidatedPortfolioProvider =
    FutureProvider.autoDispose<ConsolidatedPortfolio>((ref) async {
  final accounts = await ref.watch(accountsProvider.future);
  final fxRate = await ref.watch(fxRateProvider.future);

  final investmentAccounts = accounts.where((a) {
    if (a.type != 'investment') return false;
    final d = a.investmentDetails;
    if (d == null) return false;
    return d.investmentType.isMultiHolding;
  }).toList();

  double toCop(double value, String currency) {
    if (currency == 'COP') return value;
    if (currency == 'USD' && fxRate != null) return value * fxRate.rate;
    return value;
  }

  bool anyFxApplied = false;

  final bySymbol = <String, ConsolidatedPosition>{};
  final byAccountMv = <String, double>{};
  final accountNames = <String, String>{};

  for (final acc in investmentAccounts) {
    final holdings = await ref.watch(accountHoldingsProvider(acc.id).future);
    accountNames[acc.id] = acc.name;

    for (final h in holdings) {
      if (h.currency != 'COP' && fxRate != null) {
        anyFxApplied = true;
      }
      final mvCop = toCop(h.marketValue, h.currency);
      final cbCop = toCop(h.costBasis, h.currency);

      byAccountMv[acc.id] = (byAccountMv[acc.id] ?? 0) + mvCop;

      final key = '${h.symbol}|${h.currency}';
      final existing = bySymbol[key];
      if (existing == null) {
        bySymbol[key] = ConsolidatedPosition(
          symbol: h.symbol,
          displayName: h.displayName,
          assetClass: h.assetClass,
          marketValueCop: mvCop,
          costBasisCop: cbCop,
        );
      } else {
        bySymbol[key] = ConsolidatedPosition(
          symbol: existing.symbol,
          displayName: existing.displayName,
          assetClass: existing.assetClass,
          marketValueCop: existing.marketValueCop + mvCop,
          costBasisCop: existing.costBasisCop + cbCop,
        );
      }
    }
  }

  final positions = bySymbol.values.toList()
    ..sort((a, b) => b.marketValueCop.compareTo(a.marketValueCop));

  final byAccount = byAccountMv.entries
      .map((e) => ConsolidatedAccountSlice(
            accountId: e.key,
            accountName: accountNames[e.key] ?? e.key,
            marketValueCop: e.value,
          ))
      .where((s) => s.marketValueCop > 0)
      .toList()
    ..sort((a, b) => b.marketValueCop.compareTo(a.marketValueCop));

  final totalMv = positions.fold<double>(0, (s, p) => s + p.marketValueCop);
  final totalCb = positions.fold<double>(0, (s, p) => s + p.costBasisCop);

  return ConsolidatedPortfolio(
    positions: positions,
    byAccount: byAccount,
    totalMarketValueCop: totalMv,
    totalCostBasisCop: totalCb,
    hasFxConversion: anyFxApplied,
  );
});

/// A single point in a total-value-over-time series.
class PortfolioValuePoint {
  final DateTime date;
  final double value;
  const PortfolioValuePoint({required this.date, required this.value});
}

/// A buy-date marker for a value chart: the date and what was bought.
class PortfolioValueMarker {
  final DateTime date;
  final String label;
  const PortfolioValueMarker({required this.date, required this.label});
}

/// Builds a daily total-value series from per-holding price history.
///
/// Each holding's value is forward-filled across the union of all dates so the
/// total stays continuous on days where only some holdings have a data point
/// (crypto trades on weekends, stocks/FICs don't). [convert] maps a holding's
/// `(value, currency)` into the target/base currency.
List<PortfolioValuePoint> buildTotalValueSeries(
  List<InvestmentPriceHistory> rows,
  double Function(double value, String currency) convert,
) {
  if (rows.isEmpty) return const [];

  final byHolding = <String, SplayTreeMap<DateTime, double>>{};
  final allDates = SplayTreeSet<DateTime>();
  for (final r in rows) {
    final d = DateTime(r.marketDate.year, r.marketDate.month, r.marketDate.day);
    allDates.add(d);
    final series = byHolding.putIfAbsent(r.holdingId, () => SplayTreeMap());
    // Last write wins if several sources exist for the same day.
    series[d] = convert(r.positionValue, r.currency);
  }

  final result = <PortfolioValuePoint>[];
  for (final date in allDates) {
    final next = date.add(const Duration(days: 1));
    var sum = 0.0;
    for (final series in byHolding.values) {
      final key = series.lastKeyBefore(next); // greatest key <= date
      if (key != null) sum += series[key]!;
    }
    result.add(PortfolioValuePoint(date: date, value: sum));
  }
  return result;
}

/// Total value over time for every multi-holding investment account, in COP.
class ConsolidatedPortfolioHistory {
  final List<PortfolioValuePoint> points;
  final bool hasFxConversion;

  const ConsolidatedPortfolioHistory({
    required this.points,
    required this.hasFxConversion,
  });

  bool get isEmpty => points.isEmpty;
}

/// All `investment_price_history` rows for the current user (RLS-scoped),
/// across every account, for the last year.
final allInvestmentPriceHistoryProvider =
    FutureProvider.autoDispose<List<InvestmentPriceHistory>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.getAllInvestmentPriceHistory();
});

/// Daily consolidated portfolio value (COP) across all multi-holding accounts.
/// USD holdings are converted at the current TRM (same rule as
/// [consolidatedPortfolioProvider]).
final consolidatedPortfolioHistoryProvider =
    FutureProvider.autoDispose<ConsolidatedPortfolioHistory>((ref) async {
  final accounts = await ref.watch(accountsProvider.future);
  final fxRate = await ref.watch(fxRateProvider.future);
  final history = await ref.watch(allInvestmentPriceHistoryProvider.future);

  final accountIds = accounts
      .where((a) =>
          a.type == 'investment' &&
          (a.investmentDetails?.investmentType.isMultiHolding ?? false))
      .map((a) => a.id)
      .toSet();

  final rows =
      history.where((r) => accountIds.contains(r.accountId)).toList();

  var anyFx = false;
  double convert(double value, String currency) {
    if (currency == 'COP') return value;
    if (currency == 'USD' && fxRate != null) {
      anyFx = true;
      return value * fxRate.rate;
    }
    return value;
  }

  final points = buildTotalValueSeries(rows, convert);
  return ConsolidatedPortfolioHistory(points: points, hasFxConversion: anyFx);
});

/// Buy-date markers (date + symbol) across every multi-holding investment
/// account, for the consolidated value chart.
final consolidatedPortfolioMarkersProvider =
    FutureProvider.autoDispose<List<PortfolioValueMarker>>((ref) async {
  final accounts = await ref.watch(accountsProvider.future);
  final investmentAccounts = accounts.where((a) =>
      a.type == 'investment' &&
      (a.investmentDetails?.investmentType.isMultiHolding ?? false));

  final markers = <PortfolioValueMarker>[];
  for (final acc in investmentAccounts) {
    final holdings = await ref.watch(accountHoldingsProvider(acc.id).future);
    final events =
        await ref.watch(investmentPurchaseEventsProvider(acc.id).future);
    final labelById = {for (final h in holdings) h.id: h.displayName};
    for (final e in events) {
      markers.add(PortfolioValueMarker(
        date: e.date,
        label: labelById[e.holdingId] ?? '',
      ));
    }
  }
  return markers;
});

/// Convenience: is there any non-high-yield investment account at all?
/// Used to hide the analysis portfolio section when the user only holds
/// high-yield / CDT accounts (or no investments).
final hasAnyPortfolioAccountProvider = Provider.autoDispose<bool>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull;
  if (accounts == null) return false;
  return accounts.any((a) {
    if (a.type != 'investment') return false;
    final d = a.investmentDetails;
    if (d == null) return false;
    return d.investmentType.isMultiHolding;
  });
});

