import 'package:flutter_riverpod/flutter_riverpod.dart';

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

