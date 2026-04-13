import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
import '../widgets/high_yield_interest_dialog.dart';
import '../widgets/edit_holding_dialog.dart';
import '../widgets/buy_sell_holding_dialog.dart';
import '../widgets/update_prices_dialog.dart';
import '../widgets/cdt_collect_dialog.dart';
import '../widgets/investment_holding_card.dart';

// Co-located provider for this account's transactions (mirrors credit_card_details_screen)
final _invTxProvider = FutureProvider.family.autoDispose<List<Transaction>, String>(
  (ref, accountId) async {
    final repo = ref.read(financeRepositoryProvider);
    return repo.getTransactionsForAccount(accountId, limit: 50);
  },
);

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
    final txAsync = ref.watch(_invTxProvider(accountId));
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
      body: holdingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
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
    final invType = details?.investmentType ?? InvestmentType.highYield;
    final totalValue = InvestmentCalculator.computeTotalValue(
      account,
      holdings,
      fxRate: fxRate,
    );
    final pnl = InvestmentCalculator.computePnl(holdings);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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

          const SizedBox(height: 24),

          // ── Type-specific content ──────────────────────────────────────
          if (invType == InvestmentType.highYield) ...[
            _HighYieldSection(account: account, details: details),
          ] else if (invType == InvestmentType.cdt) ...[
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
                  itemBuilder: (context, i) => _TxTile(tx: txs[i]),
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
        padding: const EdgeInsets.all(20),
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
              const SizedBox(height: 12),
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

// ── High-yield section ────────────────────────────────────────────────────────

class _HighYieldSection extends ConsumerWidget {
  final Account account;
  final InvestmentDetails? details;

  const _HighYieldSection({required this.account, required this.details});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (details == null) return const SizedBox.shrink();

    final apyRate = details!.apyRate ?? 0;
    final apy = apyRate * 100;
    final annual =
        InvestmentCalculator.projectedAnnualIncome(account.balance, apyRate);
    final daily =
        InvestmentCalculator.highYieldDailyIncome(account.balance, apyRate);
    final fromDate = details!.lastInterestDate;
    final accrued = fromDate != null
        ? InvestmentCalculator.highYieldAccruedInterest(
            account.balance, apyRate, fromDate)
        : null;

    return Column(
      children: [
        // ── Stats row ──────────────────────────────────────────────────
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
                        label: 'APY',
                        value: '${apy.toStringAsFixed(2)}% E.A.',
                        color: Colors.green.shade600,
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        label: 'Daily Earnings',
                        value: CurrencyFormatter.format(daily),
                        color: Colors.green.shade600,
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        label: 'Annual Est.',
                        value: CurrencyFormatter.format(annual),
                      ),
                    ),
                  ],
                ),

                // ── Accrued interest row (only when tracking date is set) ──
                if (accrued != null) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _StatItem(
                          label: 'Accrued Interest',
                          value: CurrencyFormatter.format(accrued),
                          color: Colors.green.shade600,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Since',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.55),
                              ),
                            ),
                            Text(
                              DateFormat('MMM d, y').format(fromDate!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${DateTime.now().difference(fromDate).inDays} days',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // ── Record Interest button / Set start date prompt ─────────────
        const SizedBox(height: 8),
        if (fromDate != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => HighYieldInterestDialog(
                    account: account,
                    details: details!,
                  ),
                ).then((recorded) {
                  if (recorded == true) {
                    ref.invalidate(accountsProvider);
                    ref.invalidate(recentTransactionsProvider);
                  }
                });
              },
              child: const Text('Record Interest'),
            ),
          )
        else
          _SetStartDateBanner(account: account, details: details!),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Shown when [lastInterestDate] is null — prompts the user to set a start date
/// so the app can begin tracking accrued interest.
class _SetStartDateBanner extends ConsumerWidget {
  final Account account;
  final InvestmentDetails details;

  const _SetStartDateBanner({required this.account, required this.details});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
      elevation: 0,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer
                    .withOpacity(0.7)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Set a start date to begin tracking daily accrued interest.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer
                      .withOpacity(0.8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked == null || !context.mounted) return;
                try {
                  final dateStr =
                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                  await ref
                      .read(financeRepositoryProvider)
                      .rawUpdateInvestmentDetails(details.id,
                          {'last_interest_date': dateStr});
                  ref.invalidate(accountsProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Set date'),
            ),
          ],
        ),
      ),
    );
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

class _HoldingsList extends ConsumerWidget {
  final Account account;
  final List<InvestmentHolding> holdings;

  const _HoldingsList({required this.account, required this.holdings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Positions',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Row(
              children: [
                if (holdings.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => UpdatePricesDialog(
                          accountId: account.id,
                          holdings: holdings,
                        ),
                      );
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Update Prices'),
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
        const SizedBox(height: 8),
        if (holdings.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No positions yet. Tap "Add" to get started.'),
            ),
          )
        else
          ...holdings.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
              )),
      ],
    );
  }
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

class _TxTile extends StatelessWidget {
  final Transaction tx;

  const _TxTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = tx.type == 'income';
    final color = isIncome ? Colors.green.shade600 : theme.colorScheme.error;
    final sign = isIncome ? '+' : '-';

    return ListTile(
      dense: true,
      title: Text(
        tx.description ?? tx.type,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        DateFormat('MMM d, y').format(tx.date),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6)),
      ),
      trailing: Text(
        '$sign${CurrencyFormatter.format(tx.amount, currency: tx.currency)}',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
