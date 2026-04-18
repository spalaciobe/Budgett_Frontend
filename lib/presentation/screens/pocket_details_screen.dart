import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_spacing.dart';
import '../../core/utils/investment_calculator.dart';
import '../../data/models/account_model.dart';
import '../../data/models/transaction_model.dart';
import '../providers/finance_provider.dart';
import '../utils/currency_formatter.dart';
import '../widgets/edit_account_dialog.dart';
import '../widgets/savings_interest_dialog.dart';

final _pocketTxProvider =
    FutureProvider.family.autoDispose<List<Transaction>, String>(
  (ref, accountId) async {
    final repo = ref.read(financeRepositoryProvider);
    return repo.getTransactionsForAccount(accountId, limit: 50);
  },
);

/// Dedicated detail screen for a savings pocket. Mirrors the layout of
/// investment_details_screen but scoped to a pocket's interest/transactions.
class PocketDetailsScreen extends ConsumerWidget {
  final String accountId;

  const PocketDetailsScreen({super.key, required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    Account? pocket;
    Account? parent;
    for (final a in accounts) {
      for (final p in a.pockets) {
        if (p.id == accountId) {
          pocket = p;
          parent = a;
          break;
        }
      }
      if (pocket != null) break;
    }

    if (pocket == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final resolvedPocket = pocket;
    final resolvedParent = parent;
    final txAsync = ref.watch(_pocketTxProvider(accountId));

    return Scaffold(
      appBar: AppBar(
        title: Text(resolvedPocket.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit pocket',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => EditAccountDialog(account: resolvedPocket),
              ).then((_) => ref.invalidate(accountsProvider));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountsProvider);
          ref.invalidate(_pocketTxProvider(accountId));
          await ref.read(accountsProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kScreenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BalanceHeader(pocket: resolvedPocket, parent: resolvedParent),
              if (resolvedPocket.interestDetails != null) ...[
                const SizedBox(height: 16),
                _InterestSection(pocket: resolvedPocket),
              ],
              const SizedBox(height: 24),
              Text('Transaction History',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 8),
              txAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
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
                      itemBuilder: (_, i) => _TxTile(tx: txs[i]),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  final Account pocket;
  final Account? parent;
  const _BalanceHeader({required this.pocket, required this.parent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (parent != null)
              Text(
                'Pocket of ${parent!.name}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.55),
                ),
              ),
            Text('Balance',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                )),
            const SizedBox(height: 4),
            Text(
              CurrencyFormatter.format(pocket.balance),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _InterestSection extends ConsumerWidget {
  final Account pocket;
  const _InterestSection({required this.pocket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sid = pocket.interestDetails!;
    final apyRate = sid.apyRate ?? 0;
    final apyPct = apyRate * 100;
    final daily = InvestmentCalculator.savingsDailyIncome(
        pocket.balance, apyRate);
    final annual = InvestmentCalculator.projectedAnnualIncome(
        pocket.balance, apyRate);
    final fromDate = sid.lastInterestDate;
    final segments = sid.periodSegments;
    final accrued = fromDate != null
        ? InvestmentCalculator.savingsAccruedInterestWithSegments(
            segments: segments,
            currentBalance: pocket.balance,
            currentApyRate: apyRate,
            lastInterestDate: fromDate,
          )
        : null;

    return Column(
      children: [
        Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: kCardPadding,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        label: 'APY',
                        value: '${apyPct.toStringAsFixed(2)}% E.A.',
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
                if (accrued != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: kSpaceMd),
                    child: const Divider(height: 1),
                  ),
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
                            Text('Since',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.55),
                                )),
                            Text(
                              DateFormat('MMM d, y').format(fromDate!),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                            Text(
                              '${DateTime.now().difference(fromDate).inDays} days',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.55),
                              ),
                            ),
                            if (segments.isNotEmpty)
                              Text(
                                '${segments.length + 1} sub-period${segments.length + 1 == 1 ? '' : 's'}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
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
        const SizedBox(height: 8),
        if (fromDate != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () async {
                await showDialog(
                  context: context,
                  builder: (_) => SavingsInterestDialog(
                    account: pocket,
                    details: sid,
                  ),
                );
                ref.invalidate(accountsProvider);
                ref.invalidate(recentTransactionsProvider);
                ref.invalidate(_pocketTxProvider(pocket.id));
              },
              child: const Text('Record Interest'),
            ),
          )
        else
          _SetStartDatePrompt(pocket: pocket, detailsId: sid.id),
      ],
    );
  }
}

class _SetStartDatePrompt extends ConsumerWidget {
  final Account pocket;
  final String detailsId;
  const _SetStartDatePrompt({required this.pocket, required this.detailsId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked == null || !context.mounted) return;
                final dateStr =
                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                try {
                  await ref
                      .read(financeRepositoryProvider)
                      .rawUpdateSavingsInterestDetails(
                          detailsId, {'last_interest_date': dateStr});
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

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.55))),
        Text(
          value,
          style: theme.textTheme.titleMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
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
    final isPositive = tx.type == 'income';
    final color = isPositive ? Colors.green.shade600 : theme.colorScheme.error;
    final sign = isPositive ? '+' : '-';
    return ListTile(
      dense: true,
      title: Text(tx.description, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        DateFormat('MMM d, y').format(tx.date),
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        '$sign${CurrencyFormatter.format(tx.amount)}',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
