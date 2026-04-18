import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_spacing.dart';
import '../../core/responsive.dart';
import '../../core/utils/investment_calculator.dart';
import '../../data/models/account_model.dart';
import '../../data/models/investment_details_model.dart';
import '../../data/models/investment_holding_model.dart';
import '../../data/models/fx_rate_model.dart';
import '../../data/models/transaction_model.dart';
import '../providers/finance_provider.dart';
import '../providers/fx_rate_provider.dart';
import '../utils/currency_formatter.dart';
import '../widgets/edit_account_dialog.dart';
import '../widgets/edit_holding_dialog.dart';
import '../widgets/buy_sell_holding_dialog.dart';
import '../widgets/update_prices_dialog.dart';
import '../widgets/cdt_collect_dialog.dart';
import '../widgets/investment_holding_card.dart';
import '../widgets/portfolio_donut_chart.dart';
import '../widgets/transaction_tile.dart';

class InvestmentDetailsScreen extends ConsumerWidget {
  final String accountId;

  const InvestmentDetailsScreen({super.key, required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final account = accounts.cast<Account?>().firstWhere(
          (a) => a?.id == accountId,
          orElse: () => null,
        );

    if (account == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final details = account.investmentDetails;
    final holdingsAsync = ref.watch(accountHoldingsProvider(accountId));
    final txAsync = ref.watch(accountDetailTransactionsProvider(accountId));
    final fxAsync = ref.watch(fxRateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit account settings',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => EditAccountDialog(account: account),
              ).then((_) => ref.invalidate(accountsProvider));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountsProvider);
          ref.invalidate(accountHoldingsProvider(accountId));
          ref.invalidate(accountDetailTransactionsProvider(accountId));
          ref.invalidate(fxRateProvider);
          await Future.wait([
            ref.read(accountsProvider.future),
            ref.read(accountHoldingsProvider(accountId).future),
          ]);
        },
        child: holdingsAsync.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 200),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (e, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 200),
              Center(child: Text('Error: $e')),
            ],
          ),
          data: (holdings) {
            final fxRate = fxAsync.valueOrNull;
            return _Body(
              account: account,
              details: details,
              holdings: holdings,
              txAsync: txAsync,
              fxRate: fxRate,
            );
          },
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final Account account;
  final InvestmentDetails? details;
  final List<InvestmentHolding> holdings;
  final AsyncValue<List<Transaction>> txAsync;
  final FxRate? fxRate;

  const _Body({
    required this.account,
    required this.details,
    required this.holdings,
    required this.txAsync,
    required this.fxRate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invType = details?.investmentType ?? InvestmentType.cdt;
    final totalValue = InvestmentCalculator.computeTotalValue(
      account,
      holdings,
      fxRate: fxRate,
    );
    final pnl = InvestmentCalculator.computePnl(holdings);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: kScreenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Summary header ─────────────────────────────────────────────
          _SummaryHeader(
            account: account,
            details: details,
            totalValue: totalValue,
            pnl: pnl,
            holdings: holdings,
            fxRate: fxRate,
          ),

          const SizedBox(height: 16),

          // ── Type-specific content ──────────────────────────────────────
          if (invType == InvestmentType.cdt) ...[
            _CdtSection(account: account, details: details),
          ] else ...[
            // Multi-holding: FIC, crypto, stock_etf
            _HoldingsList(account: account, holdings: holdings),
          ],

          const SizedBox(height: 24),

          // ── Transaction history ────────────────────────────────────────
          Text('Transaction History',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  )),
          const SizedBox(height: 8),
          txAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (txs) {
              if (txs.isEmpty) {
                return const Text('No transactions yet.');
              }
              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: txs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, i) => TransactionTile(
                    transaction: txs[i],
                    perspectiveAccountId: account.id,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Summary header ────────────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  final Account account;
  final InvestmentDetails? details;
  final InvestmentTotalValue totalValue;
  final InvestmentPnl pnl;
  final List<InvestmentHolding> holdings;
  final FxRate? fxRate;

  const _SummaryHeader({
    required this.account,
    required this.details,
    required this.totalValue,
    required this.pnl,
    required this.holdings,
    required this.fxRate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseCurrency = details?.baseCurrency ?? 'COP';
    final isApprox = totalValue.isApprox;
    final hasHoldings = holdings.isNotEmpty;

    // Stale indicator
    final isStale = fxRate?.isStale ?? false;

    // Price freshness
    DateTime? oldestPrice;
    for (final h in holdings) {
      if (h.priceUpdatedAt != null) {
        if (oldestPrice == null ||
            h.priceUpdatedAt!.isBefore(oldestPrice)) {
          oldestPrice = h.priceUpdatedAt;
        }
      }
    }

    final pnlPositive = pnl.pnl >= 0;
    final pnlColor =
        pnlPositive ? Colors.green.shade600 : theme.colorScheme.error;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Total Value',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    )),
                if (isApprox) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message:
                        'Approximate — based on TRM${isStale ? " (stale)" : ""}',
                    child: Chip(
                      label: const Text('≈'),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: isStale
                          ? Colors.orange.withOpacity(0.2)
                          : theme.colorScheme.primaryContainer
                              .withOpacity(0.5),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              CurrencyFormatter.format(totalValue.total,
                  currency: baseCurrency),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (isApprox && baseCurrency == 'USD') ...[
              const SizedBox(height: 2),
              Text(
                CurrencyFormatter.formatApprox(totalValue.totalCop,
                    currency: 'COP'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],

            // P&L (only when there are multi-holding positions)
            if (hasHoldings && pnl.costBasis != 0) ...[
              kGapLg,
              Row(
                children: [
                  Icon(
                    pnlPositive
                        ? Icons.trending_up
                        : Icons.trending_down,
                    size: 16,
                    color: pnlColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${pnlPositive ? '+' : ''}${CurrencyFormatter.format(pnl.pnl, currency: baseCurrency)}  '
                    '(${pnlPositive ? '+' : ''}${pnl.pnlPct.toStringAsFixed(2)}%)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: pnlColor, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],

            // Price age
            if (oldestPrice != null) ...[
              const SizedBox(height: 8),
              Text(
                'Prices updated ${_timeAgo(oldestPrice)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}


// ── CDT section ───────────────────────────────────────────────────────────────

class _CdtSection extends ConsumerWidget {
  final Account account;
  final InvestmentDetails? details;

  const _CdtSection({required this.account, required this.details});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (details == null) return const SizedBox.shrink();

    final daysLeft = InvestmentCalculator.cdtDaysToMaturity(details!);
    final matured = InvestmentCalculator.isCdtMatured(details!);
    final projectedValue =
        InvestmentCalculator.projectCdtMaturityValue(details!);
    final accrued = InvestmentCalculator.cdtAccruedInterest(details!);
    final rate = (details!.interestRate ?? 0) * 100;

    return Column(
      children: [
        Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        label: 'Principal',
                        value: CurrencyFormatter.format(
                            details!.principal ?? 0),
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        label: 'Rate',
                        value: '${rate.toStringAsFixed(2)}% E.A.',
                        color: Colors.green.shade600,
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        label: matured ? 'Status' : 'Days Left',
                        value: matured ? 'Matured' : '$daysLeft days',
                        color: matured ? Colors.orange : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        label: 'Accrued Interest',
                        value: CurrencyFormatter.format(accrued),
                        color: Colors.green.shade600,
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        label: 'Value at Maturity',
                        value: CurrencyFormatter.format(projectedValue),
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (matured || daysLeft <= 0) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => CdtCollectDialog(account: account),
                );
              },
              icon: const Icon(Icons.account_balance_wallet),
              label: const Text('Collect CDT'),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Holdings list ─────────────────────────────────────────────────────────────

class _HoldingsList extends ConsumerStatefulWidget {
  final Account account;
  final List<InvestmentHolding> holdings;

  const _HoldingsList({required this.account, required this.holdings});

  @override
  ConsumerState<_HoldingsList> createState() => _HoldingsListState();
}

class _HoldingsListState extends ConsumerState<_HoldingsList> {
  int _viewMode = 0; // 0 = positions, 1 = donut

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final holdings = widget.holdings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (context.formFactor == FormFactor.mobile) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (holdings.isNotEmpty)
                _UpdatePricesButton(
                  accountId: account.id,
                  holdings: holdings,
                ),
              FilledButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) =>
                        EditHoldingDialog(accountId: account.id),
                  );
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (holdings.isNotEmpty)
            Center(
              child: SegmentedButton<int>(
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                  minimumSize: const Size(0, 32),
                ),
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('Positions'),
                    icon: Icon(Icons.view_module, size: 16),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('Portfolio'),
                    icon: Icon(Icons.donut_large, size: 16),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (s) => setState(() => _viewMode = s.first),
              ),
            )
          else
            Center(
              child: Text('Positions',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
        ] else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (holdings.isNotEmpty)
                SegmentedButton<int>(
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                    minimumSize: const Size(0, 32),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Positions'),
                      icon: Icon(Icons.view_module, size: 16),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Portfolio'),
                      icon: Icon(Icons.donut_large, size: 16),
                    ),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (s) => setState(() => _viewMode = s.first),
                )
              else
                Text('Positions',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  if (holdings.isNotEmpty)
                    _UpdatePricesButton(
                      accountId: account.id,
                      holdings: holdings,
                    ),
                  FilledButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) =>
                            EditHoldingDialog(accountId: account.id),
                      );
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ],
          ),
        const SizedBox(height: 12),
        if (holdings.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No positions yet. Tap "Add" to get started.'),
            ),
          )
        else if (_viewMode == 1)
          _buildDonut(context, account, holdings)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = context.formFactor == FormFactor.mobile ? 1 : 3;
              const spacing = 8.0;
              final itemWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: holdings.map((h) => SizedBox(
                  width: itemWidth,
                  child: InvestmentHoldingCard(
                    holding: h,
                    onBuy: () {
                      showDialog(
                        context: context,
                        builder: (_) => BuySellHoldingDialog(
                          accountId: account.id,
                          holding: h,
                          isBuy: true,
                        ),
                      );
                    },
                    onSell: () {
                      showDialog(
                        context: context,
                        builder: (_) => BuySellHoldingDialog(
                          accountId: account.id,
                          holding: h,
                          isBuy: false,
                        ),
                      );
                    },
                    onEdit: () {
                      showDialog(
                        context: context,
                        builder: (_) => EditHoldingDialog(
                          accountId: account.id,
                          holding: h,
                        ),
                      );
                    },
                    onDelete: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete Position?'),
                          content: Text(
                              'Delete ${h.symbol}? Transaction history will be preserved.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                      if (confirmed == true) {
                        await ref
                            .read(financeRepositoryProvider)
                            .deleteHolding(h.id);
                        ref.invalidate(accountHoldingsProvider(account.id));
                      }
                    },
                  ),
                )).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDonut(
    BuildContext context,
    Account account,
    List<InvestmentHolding> holdings,
  ) {
    final baseCurrency = account.investmentDetails?.baseCurrency ?? 'COP';

    // Group holdings by symbol+currency so buying the same asset twice
    // shows as a single slice even if the user created two rows.
    final grouped = <String, _SymbolSlice>{};
    for (final h in holdings) {
      if (h.marketValue <= 0) continue;
      final key = '${h.symbol}|${h.currency}';
      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = _SymbolSlice(
          label: h.displayName,
          marketValue: h.marketValue,
          costBasis: h.costBasis,
          currency: h.currency,
        );
      } else {
        grouped[key] = _SymbolSlice(
          label: existing.label,
          marketValue: existing.marketValue + h.marketValue,
          costBasis: existing.costBasis + h.costBasis,
          currency: existing.currency,
        );
      }
    }

    final sorted = grouped.values.toList()
      ..sort((a, b) => b.marketValue.compareTo(a.marketValue));

    final slices = <PortfolioSlice>[];
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      final pnlPct = s.costBasis == 0
          ? 0.0
          : ((s.marketValue - s.costBasis) / s.costBasis) * 100;
      final pnlLabel = s.costBasis == 0
          ? null
          : '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(1)}%';
      slices.add(PortfolioSlice(
        label: s.label,
        value: s.marketValue,
        color: PortfolioPalette.colorFor(i),
        trailing: pnlLabel,
      ));
    }

    final total = sorted.fold<double>(0, (sum, s) => sum + s.marketValue);
    final centerValue =
        CurrencyFormatter.format(total, currency: baseCurrency);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: PortfolioDonutChart(
          slices: slices,
          centerLabel: 'Holdings',
          centerValue: centerValue,
        ),
      ),
    );
  }
}

class _SymbolSlice {
  final String label;
  final double marketValue;
  final double costBasis;
  final String currency;

  const _SymbolSlice({
    required this.label,
    required this.marketValue,
    required this.costBasis,
    required this.currency,
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatItem({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
            )),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Embeddable body for the master/detail split view ─────────────────────────

/// Renders the full investment-detail content without a Scaffold / AppBar.
/// Use this inside AccountsScreen's right panel.
class InvestmentDetailsBody extends ConsumerWidget {
  final String accountId;

  const InvestmentDetailsBody({super.key, required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final account = accounts.cast<Account?>().firstWhere(
          (a) => a?.id == accountId,
          orElse: () => null,
        );

    if (account == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final details = account.investmentDetails;
    final holdingsAsync = ref.watch(accountHoldingsProvider(accountId));
    final txAsync = ref.watch(accountDetailTransactionsProvider(accountId));
    final fxAsync = ref.watch(fxRateProvider);

    return holdingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (holdings) => _Body(
        account: account,
        details: details,
        holdings: holdings,
        txAsync: txAsync,
        fxRate: fxAsync.valueOrNull,
      ),
    );
  }
}

// ── Update Prices button ──────────────────────────────────────────────────────

enum _UpdatePricesAction { auto, manual }

/// Split-menu button for updating prices on all holdings in an account.
///
/// Tapping opens a popup with two options:
///   - Fetch from market: calls the `update-prices` Edge Function (CoinGecko
///     for crypto, Yahoo Finance for stocks/ETFs, datos.gov.co for FICs).
///   - Enter manually: opens [UpdatePricesDialog] to type prices by hand.
///
/// Auto-fetch is also offered as a fallback via a snackbar action when the
/// edge function skips holdings or errors out.
class _UpdatePricesButton extends ConsumerStatefulWidget {
  final String accountId;
  final List<InvestmentHolding> holdings;

  const _UpdatePricesButton({
    required this.accountId,
    required this.holdings,
  });

  @override
  ConsumerState<_UpdatePricesButton> createState() =>
      _UpdatePricesButtonState();
}

class _UpdatePricesButtonState extends ConsumerState<_UpdatePricesButton> {
  bool _isLoading = false;

  void _openManualDialog() {
    showDialog(
      context: context,
      builder: (_) => UpdatePricesDialog(
        accountId: widget.accountId,
        holdings: widget.holdings,
      ),
    );
  }

  Future<void> _autoFetch() async {
    setState(() => _isLoading = true);
    try {
      final result = await ref
          .read(financeRepositoryProvider)
          .fetchMarketPrices(widget.accountId);
      ref.invalidate(accountHoldingsProvider(widget.accountId));
      if (!mounted) return;

      final updated = result.updatedCount;
      final skipped = result.skipped;
      final messenger = ScaffoldMessenger.of(context);
      if (updated == 0 && skipped.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No holdings to update')),
        );
      } else if (skipped.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text('Updated $updated holding${updated == 1 ? '' : 's'}')),
        );
      } else {
        final symbols = skipped.map((s) => s.symbol).join(', ');
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text('Updated $updated, skipped: $symbols'),
            action: SnackBarAction(
              label: 'Edit manually',
              onPressed: _openManualDialog,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch prices: $e'),
          action: SnackBarAction(
            label: 'Edit manually',
            onPressed: _openManualDialog,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<_UpdatePricesAction>(
      enabled: !_isLoading,
      tooltip: 'Update prices',
      position: PopupMenuPosition.under,
      onSelected: (action) {
        switch (action) {
          case _UpdatePricesAction.auto:
            _autoFetch();
            break;
          case _UpdatePricesAction.manual:
            _openManualDialog();
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _UpdatePricesAction.auto,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_download_outlined, size: 18),
              SizedBox(width: 10),
              Text('Fetch from market'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _UpdatePricesAction.manual,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 10),
              Text('Enter manually…'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.refresh, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'Update Prices',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            Icon(Icons.arrow_drop_down,
                size: 18, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
