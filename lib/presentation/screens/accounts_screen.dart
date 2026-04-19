import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/providers/fx_rate_provider.dart';
import 'package:budgett_frontend/presentation/providers/settings_provider.dart';
import 'package:budgett_frontend/presentation/widgets/add_account_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/edit_account_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/account_card.dart';
import 'package:budgett_frontend/presentation/widgets/savings_interest_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/transaction_tile.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/investment_details_model.dart';
import 'package:budgett_frontend/data/models/investment_holding_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/core/utils/investment_calculator.dart';
import 'package:budgett_frontend/core/responsive.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:budgett_frontend/presentation/screens/credit_card_details_screen.dart';
import 'package:budgett_frontend/presentation/screens/investment_details_screen.dart';

// ── Top-level helpers ─────────────────────────────────────────────────────────

IconData _iconForType(String type) => switch (type) {
      'credit_card' => Icons.credit_card,
      'cash' || 'efectivo' => Icons.money,
      'investment' => Icons.trending_up,
      'savings' || 'ahorro' => Icons.savings,
      _ => Icons.account_balance,
    };

List<Account> _sortAccounts(
  List<Account> accounts,
  AccountSortOption option,
  List<String> customOrder,
) {
  final sorted = [...accounts];
  int cmpName(Account a, Account b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  switch (option) {
    case AccountSortOption.custom:
      final rank = {for (var i = 0; i < customOrder.length; i++) customOrder[i]: i};
      sorted.sort((a, b) {
        final ra = rank[a.id];
        final rb = rank[b.id];
        // Unknown accounts (newly added) fall to the end, alphabetized.
        if (ra == null && rb == null) return cmpName(a, b);
        if (ra == null) return 1;
        if (rb == null) return -1;
        return ra.compareTo(rb);
      });
    case AccountSortOption.nameAsc:
      sorted.sort(cmpName);
    case AccountSortOption.nameDesc:
      sorted.sort((a, b) => cmpName(b, a));
    case AccountSortOption.balanceDesc:
      sorted.sort((a, b) {
        final c = b.balance.compareTo(a.balance);
        return c != 0 ? c : cmpName(a, b);
      });
    case AccountSortOption.balanceAsc:
      sorted.sort((a, b) {
        final c = a.balance.compareTo(b.balance);
        return c != 0 ? c : cmpName(a, b);
      });
    case AccountSortOption.typeAsc:
      sorted.sort((a, b) {
        final c = a.type.compareTo(b.type);
        return c != 0 ? c : cmpName(a, b);
      });
  }
  return sorted;
}

Widget? _investmentGainsSubtitle(
  BuildContext context,
  Account account,
  List<InvestmentHolding> holdings,
  String baseCurrency,
) {
  final details = account.investmentDetails;
  if (details == null) return null;

  final theme = Theme.of(context);
  final dimColor = theme.colorScheme.onSurface.withOpacity(0.45);
  final baseStyle = theme.textTheme.labelSmall;

  switch (details.investmentType) {
    case InvestmentType.cdt:
      if (InvestmentCalculator.isCdtMatured(details)) {
        return Text(
          'Matured — collect',
          style: baseStyle?.copyWith(color: Colors.orange.shade700),
        );
      }
      final accrued = InvestmentCalculator.cdtAccruedInterest(details);
      if (accrued <= 0) return null;
      return Text(
        '+${CurrencyFormatter.format(accrued, decimalDigits: 2)} earned',
        style: baseStyle?.copyWith(color: Colors.green.shade600),
      );

    case InvestmentType.fic:
    case InvestmentType.crypto:
    case InvestmentType.stockEtf:
      final pnl = InvestmentCalculator.computePnl(holdings);
      if (pnl.costBasis == 0) {
        return Text(
          details.investmentType.displayName,
          style: baseStyle?.copyWith(color: dimColor),
        );
      }
      final positive = pnl.pnl >= 0;
      final pnlColor =
          positive ? Colors.green.shade600 : theme.colorScheme.error;
      return Text(
        '${positive ? '+' : ''}${CurrencyFormatter.format(pnl.pnl, currency: baseCurrency)}'
        '  (${positive ? '+' : ''}${pnl.pnlPct.toStringAsFixed(2)}%)',
        style: baseStyle?.copyWith(
          color: pnlColor,
          fontWeight: FontWeight.w600,
        ),
      );
  }
}

Widget _buildAccountIcon(Account account, ThemeData theme, {double size = 36}) {
  final icon = account.icon;
  if (icon != null && icon.startsWith('http')) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.network(
        icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          _iconForType(account.type),
          color: theme.colorScheme.primary,
          size: size * 0.5,
        ),
      ),
    );
  }
  return Icon(_iconForType(account.type),
      color: theme.colorScheme.primary, size: size * 0.5);
}

// ── Accounts Screen ───────────────────────────────────────────────────────────

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  String? _selectedAccountId;

  void _onReorder(List<Account> sorted, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = [...sorted];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    ref
        .read(accountCustomOrderProvider.notifier)
        .setOrder(reordered.map((a) => a.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final sortOption =
        ref.watch(accountSortProvider).valueOrNull ?? AccountSortOption.custom;
    final customOrder =
        ref.watch(accountCustomOrderProvider).valueOrNull ?? const <String>[];
    final isDesktop = context.formFactor != FormFactor.mobile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          PopupMenuButton<AccountSortOption>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort accounts',
            initialValue: sortOption,
            onSelected: (value) =>
                ref.read(accountSortProvider.notifier).setSort(value),
            itemBuilder: (context) => [
              for (final option in AccountSortOption.values)
                PopupMenuItem(
                  value: option,
                  child: Row(
                    children: [
                      Icon(
                        Icons.check,
                        size: 18,
                        color: option == sortOption
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                      const SizedBox(width: 8),
                      Text(option.label),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: accountsAsync.when(
        data: (accounts) {
          final sorted = _sortAccounts(accounts, sortOption, customOrder);
          final reorderable = sortOption == AccountSortOption.custom;
          return isDesktop
              ? _buildDesktopLayout(sorted, reorderable: reorderable)
              : _buildMobileList(sorted, reorderable: reorderable);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const AddAccountDialog(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  // ── Mobile: unchanged column layout ──────────────────────────────────────

  Widget _buildMobileList(List<Account> accounts, {required bool reorderable}) {
    if (accounts.isEmpty) {
      return const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('No accounts yet. Add one!'),
          ),
        ),
      );
    }
    Future<void> onRefresh() async {
      ref.invalidate(accountsProvider);
      await ref.read(accountsProvider.future);
    }

    if (reorderable) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ReorderableListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kScreenPadding,
          itemCount: accounts.length,
          onReorder: (oldIndex, newIndex) =>
              _onReorder(accounts, oldIndex, newIndex),
          itemBuilder: (_, i) => Padding(
            key: ValueKey(accounts[i].id),
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildMobileCard(accounts[i]),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kScreenPadding,
        child: Column(
          children: [
            for (int i = 0; i < accounts.length; i++) ...[
              _buildMobileCard(accounts[i]),
              if (i < accounts.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCard(Account acc) {
    void onTap() {
      if (acc.type == 'credit_card') {
        context.push('/credit-card/${acc.id}');
      } else if (acc.type == 'investment') {
        context.push('/investment/${acc.id}');
      } else {
        context.push('/account/${acc.id}');
      }
    }

    if (acc.type == 'investment') {
      return _InvestmentAccountCard(account: acc, tileLayout: true, onTap: onTap);
    }
    return AccountCard(account: acc, tileLayout: true, onTap: onTap);
  }

  // ── Desktop: master / detail ──────────────────────────────────────────────

  Widget _buildDesktopLayout(List<Account> accounts, {required bool reorderable}) {
    if (accounts.isEmpty) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No accounts yet.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const AddAccountDialog(),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add account'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Auto-select first account if nothing is selected or selection was deleted.
    final exists = accounts.any((a) => a.id == _selectedAccountId);
    if (!exists) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedAccountId = accounts.first.id);
      });
    }

    final selected =
        exists ? accounts.firstWhere((a) => a.id == _selectedAccountId) : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel: account list
        Container(
          width: 280,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(accountsProvider);
              await ref.read(accountsProvider.future);
            },
            child: reorderable
                ? ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    itemCount: accounts.length,
                    onReorder: (oldIndex, newIndex) =>
                        _onReorder(accounts, oldIndex, newIndex),
                    itemBuilder: (_, i) => Padding(
                      key: ValueKey(accounts[i].id),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _AccountListItem(
                        account: accounts[i],
                        isSelected: accounts[i].id == _selectedAccountId,
                        onTap: () => setState(
                            () => _selectedAccountId = accounts[i].id),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    itemCount: accounts.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _AccountListItem(
                        account: accounts[i],
                        isSelected: accounts[i].id == _selectedAccountId,
                        onTap: () => setState(
                            () => _selectedAccountId = accounts[i].id),
                      ),
                    ),
                  ),
          ),
        ),
        // Right panel: detail
        Expanded(
          child: selected != null
              ? _AccountDetailPanel(
                  key: ValueKey(selected.id),
                  account: selected,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Desktop left-panel list item ──────────────────────────────────────────────

class _AccountListItem extends ConsumerWidget {
  final Account account;
  final bool isSelected;
  final VoidCallback onTap;

  const _AccountListItem({
    required this.account,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    String balance;
    Widget? balanceSubtitle;
    if (account.type == 'investment') {
      final holdings =
          ref.watch(accountHoldingsProvider(account.id)).valueOrNull ?? [];
      final fxRate = ref.watch(fxRateProvider).valueOrNull;
      final tv = InvestmentCalculator.computeTotalValue(account, holdings,
          fxRate: fxRate);
      final currency = account.investmentDetails?.baseCurrency ?? 'COP';
      balance = currency == 'USD'
          ? CurrencyFormatter.format(tv.total, currency: 'USD')
          : CurrencyFormatter.format(tv.total, decimalDigits: 2);
      balanceSubtitle =
          _investmentGainsSubtitle(context, account, holdings, currency);
    } else if (account.type == 'credit_card' && account.balanceUsd != 0) {
      balance = CurrencyFormatter.format(account.balance, decimalDigits: 2);
      balanceSubtitle = Text(
        CurrencyFormatter.format(account.balanceUsd, currency: 'USD'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.45),
        ),
      );
    } else if (account.isSavingsParent && account.pockets.isNotEmpty) {
      balance = CurrencyFormatter.format(
          account.totalBalanceWithPockets,
          decimalDigits: 2);
      final pocketLabel = account.pockets.length == 1 ? 'pocket' : 'pockets';
      balanceSubtitle = Text(
        '${account.pockets.length} $pocketLabel · '
        '${CurrencyFormatter.format(account.pocketsBalance, decimalDigits: 2)} stored',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.45),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      balance = CurrencyFormatter.format(account.balance, decimalDigits: 2);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Selection indicator bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 3,
                height: 38,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Account icon
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                    child: _buildAccountIcon(account, theme, size: 38)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      balance,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                    if (balanceSubtitle != null) balanceSubtitle,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Desktop right-panel detail ────────────────────────────────────────────────

class _AccountDetailPanel extends ConsumerWidget {
  final Account account;

  const _AccountDetailPanel({required this.account, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Credit cards and investments: show the full detail body from their
    // respective screens, with only a thin header above it.
    if (account.type == 'credit_card') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader(context, theme),
          const Divider(height: 1),
          Expanded(child: CreditCardDetailsBody(accountId: account.id)),
        ],
      );
    }

    if (account.type == 'investment') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader(context, theme),
          const Divider(height: 1),
          Expanded(child: InvestmentDetailsBody(accountId: account.id)),
        ],
      );
    }

    // Other account types (savings, checking, cash): compact header + transactions.
    // Shared provider includes incoming transfers and pocket transactions for
    // savings parents.
    final txns =
        ref.watch(accountDetailTransactionsProvider(account.id)).valueOrNull ??
            [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme, null),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildActionRow(context),
                if (account.interestDetails != null) ...[
                  const SizedBox(height: 16),
                  _SavingsInterestCard(account: account),
                ],
                if (account.isSavingsParent) ...[
                  const SizedBox(height: 16),
                  _PocketList(account: account),
                ],
                const SizedBox(height: 24),
                _buildTransactionsSection(context, theme, txns),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Thin header used above the full-detail body for CC and investment accounts.
  Widget _buildPanelHeader(BuildContext context, ThemeData theme) {
    final typeLabel = switch (account.type) {
      'credit_card' => 'Credit Card',
      'savings' || 'ahorro' => 'Savings',
      'corriente' => 'Checking',
      'cash' || 'efectivo' => 'Cash',
      'investment' => 'Investment',
      _ => account.type,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: _buildAccountIcon(account, theme, size: 40)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    typeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit account',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EditAccountDialog(account: account),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme, InvestmentTotalValue? totalValue) {
    String balanceText;
    Widget? subBalance;

    if (account.type == 'investment' && totalValue != null) {
      final currency = account.investmentDetails?.baseCurrency ?? 'COP';
      balanceText = currency == 'USD'
          ? CurrencyFormatter.format(totalValue.total, currency: 'USD')
          : CurrencyFormatter.format(totalValue.total, decimalDigits: 2);
    } else if (account.type == 'credit_card') {
      balanceText = CurrencyFormatter.format(account.balance, decimalDigits: 2);
      if (account.balanceUsd != 0) {
        subBalance = Text(
          CurrencyFormatter.format(account.balanceUsd, currency: 'USD'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.5)),
        );
      }
    } else if (account.isSavingsParent && account.pockets.isNotEmpty) {
      balanceText = CurrencyFormatter.format(
          account.totalBalanceWithPockets,
          decimalDigits: 2);
      subBalance = Text(
        '${CurrencyFormatter.format(account.balance, decimalDigits: 2)} own · '
        '${CurrencyFormatter.format(account.pocketsBalance, decimalDigits: 2)} in pockets',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.55)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      balanceText = CurrencyFormatter.format(account.balance, decimalDigits: 2);
    }

    final typeLabel = switch (account.type) {
      'credit_card' => 'Credit Card',
      'savings' || 'ahorro' => 'Savings',
      'corriente' => 'Checking',
      'cash' || 'efectivo' => 'Cash',
      'investment' => 'Investment',
      _ => account.type,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Large icon
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(child: _buildAccountIcon(account, theme, size: 52)),
          ),
          const SizedBox(width: 16),
          // Name + type badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    typeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Balance (right-aligned)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                balanceText,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (subBalance != null) subBalance,
            ],
          ),
        ],
      ),
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────

  Widget _buildActionRow(BuildContext context) {
    final hasDetail =
        account.type == 'credit_card' || account.type == 'investment';
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => EditAccountDialog(account: account),
          ),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Edit'),
        ),
        if (hasDetail)
          FilledButton.icon(
            onPressed: () => context.push(
              account.type == 'credit_card'
                  ? '/credit-card/${account.id}'
                  : '/investment/${account.id}',
            ),
            icon: const Icon(Icons.open_in_full, size: 16),
            label: Text(account.type == 'credit_card'
                ? 'Card details'
                : 'Portfolio'),
          ),
      ],
    );
  }

  // ── Recent transactions ───────────────────────────────────────────────────

  Widget _buildTransactionsSection(
      BuildContext context, ThemeData theme, List<Transaction> txns) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent transactions',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (txns.isEmpty)
          Text(
            'No recent transactions',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          )
        else
          ...txns.map((t) => TransactionTile(
                transaction: t,
                perspectiveAccountId: account.id,
              )),
      ],
    );
  }

}

// ── Investment account card (mobile only) ─────────────────────────────────────

class _InvestmentAccountCard extends ConsumerWidget {
  final Account account;
  final bool tileLayout;
  final VoidCallback onTap;

  const _InvestmentAccountCard({
    required this.account,
    required this.tileLayout,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdingsAsync = ref.watch(accountHoldingsProvider(account.id));
    final fxRate = ref.watch(fxRateProvider).valueOrNull;

    final holdings = holdingsAsync.valueOrNull ?? [];
    final details = account.investmentDetails;
    final baseCurrency = details?.baseCurrency ?? 'COP';

    final totalValue = InvestmentCalculator.computeTotalValue(
      account,
      holdings,
      fxRate: fxRate,
    );

    final balanceDisplay = baseCurrency == 'USD'
        ? CurrencyFormatter.format(totalValue.total, currency: 'USD')
        : CurrencyFormatter.format(totalValue.total, decimalDigits: 2);

    return AccountCard(
      account: account,
      tileLayout: tileLayout,
      balanceText: balanceDisplay,
      subtitle: _buildGainsSubtitle(context, details, holdings, baseCurrency),
      onTap: onTap,
    );
  }

  Widget? _buildGainsSubtitle(
    BuildContext context,
    InvestmentDetails? details,
    List<InvestmentHolding> holdings,
    String baseCurrency,
  ) {
    if (details == null) return null;

    final dimColor =
        Theme.of(context).colorScheme.onSurface.withOpacity(0.55);
    const subtitleStyle = TextStyle(fontSize: 11);

    switch (details.investmentType) {
      case InvestmentType.cdt:
        if (InvestmentCalculator.isCdtMatured(details)) {
          return Text(
            'Matured — collect',
            style: subtitleStyle.copyWith(color: Colors.orange.shade700),
          );
        }
        final accrued = InvestmentCalculator.cdtAccruedInterest(details);
        if (accrued <= 0) return null;
        return Text(
          '+${CurrencyFormatter.format(accrued, decimalDigits: 2)} earned',
          style: subtitleStyle.copyWith(color: Colors.green.shade600),
        );

      case InvestmentType.fic:
      case InvestmentType.crypto:
      case InvestmentType.stockEtf:
        final pnl = InvestmentCalculator.computePnl(holdings);
        if (pnl.costBasis == 0) {
          return Text(
            details.investmentType.displayName,
            style: subtitleStyle.copyWith(color: dimColor),
          );
        }
        final positive = pnl.pnl >= 0;
        final pnlColor = positive
            ? Colors.green.shade600
            : Theme.of(context).colorScheme.error;
        return Text(
          '${positive ? '+' : ''}${CurrencyFormatter.format(pnl.pnl, currency: baseCurrency)}'
          '  (${positive ? '+' : ''}${pnl.pnlPct.toStringAsFixed(2)}%)',
          style: subtitleStyle.copyWith(
            color: pnlColor,
            fontWeight: FontWeight.w600,
          ),
        );
    }
  }
}

// ── Savings interest card + pocket list ───────────────────────────────────────

class _SavingsInterestCard extends ConsumerWidget {
  final Account account;
  const _SavingsInterestCard({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sid = account.interestDetails!;
    final apyPct = (sid.apyRate ?? 0) * 100;
    final daily =
        InvestmentCalculator.savingsDailyIncome(account.balance, sid.apyRate ?? 0);
    final annual =
        InvestmentCalculator.projectedAnnualIncome(account.balance, sid.apyRate ?? 0);
    final accrued = sid.lastInterestDate != null
        ? InvestmentCalculator.savingsAccruedInterestWithSegments(
            segments: sid.periodSegments,
            currentBalance: account.balance,
            currentApyRate: sid.apyRate ?? 0,
            lastInterestDate: sid.lastInterestDate!,
          )
        : null;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: kCardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Interest', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _miniStat(
                    theme,
                    'APY',
                    '${apyPct.toStringAsFixed(2)}% E.A.',
                    Colors.green.shade600,
                  ),
                ),
                Expanded(
                  child: _miniStat(theme, 'Daily',
                      CurrencyFormatter.format(daily), Colors.green.shade600),
                ),
                Expanded(
                  child: _miniStat(theme, 'Annual',
                      CurrencyFormatter.format(annual), null),
                ),
              ],
            ),
            if (accrued != null) ...[
              const SizedBox(height: 8),
              Text(
                '+${CurrencyFormatter.format(accrued)} accrued since '
                '${sid.lastInterestDate!.toIso8601String().split("T")[0]}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => SavingsInterestDialog(
                      account: account,
                      details: sid,
                    ),
                  );
                  ref.invalidate(accountsProvider);
                  ref.invalidate(recentTransactionsProvider);
                },
                child: const Text('Record Interest'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniStat(ThemeData theme, String label, String value, Color? color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.55))),
        Text(
          value,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _PocketList extends ConsumerWidget {
  final Account account;
  const _PocketList({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pockets = account.pockets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Pockets', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add pocket'),
              onPressed: () => _showAddPocketDialog(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (pockets.isEmpty)
          Text(
            'No pockets yet. Add one to allocate part of your balance with its own APY.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
            ),
          )
        else
          Column(
            children: pockets
                .map((p) => _PocketTile(pocket: p))
                .toList(growable: false),
          ),
      ],
    );
  }

  void _showAddPocketDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final apyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Pocket'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Pocket name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: apyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'APY (E.A. %) — optional',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final apyPct = double.tryParse(apyCtrl.text.trim());
              final apyRate = apyPct != null ? apyPct / 100 : null;
              try {
                await ref.read(financeRepositoryProvider).createPocket(
                      parentAccountId: account.id,
                      name: name,
                      apyRate: apyRate,
                      interestPeriod: apyRate != null ? 'monthly' : null,
                      lastInterestDate:
                          apyRate != null ? DateTime.now() : null,
                    );
                ref.invalidate(accountsProvider);
                if (ctx.mounted) Navigator.of(ctx).pop();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _PocketTile extends ConsumerWidget {
  final Account pocket;
  const _PocketTile({required this.pocket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sid = pocket.interestDetails;
    final apyPct = sid?.apyRate != null
        ? '${(sid!.apyRate! * 100).toStringAsFixed(2)}%'
        : null;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(Icons.savings, color: theme.colorScheme.primary),
        title: Text(pocket.name),
        subtitle: apyPct != null
            ? Text('$apyPct APY',
                style: TextStyle(color: Colors.green.shade600, fontSize: 12))
            : null,
        trailing: Text(
          CurrencyFormatter.format(pocket.balance),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        onTap: () => context.push('/pockets/${pocket.id}'),
      ),
    );
  }
}

// ── Mobile account details screen ─────────────────────────────────────────────

/// Full-screen details view for savings, checking, and cash accounts on mobile.
/// Mirrors the desktop master-detail right panel for the same account types.
class AccountDetailsScreen extends ConsumerWidget {
  final String accountId;

  const AccountDetailsScreen({super.key, required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref
        .watch(accountsProvider)
        .valueOrNull
        ?.where((a) => a.id == accountId)
        .firstOrNull;

    if (account == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final txns =
        ref.watch(accountDetailTransactionsProvider(account.id)).valueOrNull ??
            [];

    final balanceText = account.isSavingsParent && account.pockets.isNotEmpty
        ? CurrencyFormatter.format(
            account.totalBalanceWithPockets,
            decimalDigits: 2,
          )
        : CurrencyFormatter.format(account.balance, decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit account',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EditAccountDialog(account: account),
            ).then((_) => ref.invalidate(accountsProvider)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountsProvider);
          ref.invalidate(accountDetailTransactionsProvider(accountId));
          await ref.read(accountsProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kScreenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Balance',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        balanceText,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (account.isSavingsParent &&
                          account.pockets.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${CurrencyFormatter.format(account.balance, decimalDigits: 2)} own · '
                          '${CurrencyFormatter.format(account.pocketsBalance, decimalDigits: 2)} in pockets',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.55),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (account.interestDetails != null) ...[
                const SizedBox(height: 16),
                _SavingsInterestCard(account: account),
              ],
              if (account.isSavingsParent) ...[
                const SizedBox(height: 16),
                _PocketList(account: account),
              ],
              const SizedBox(height: 24),
              Text(
                'Recent transactions',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (txns.isEmpty)
                Text(
                  'No recent transactions',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                )
              else
                ...txns.map((t) => TransactionTile(
                      transaction: t,
                      perspectiveAccountId: account.id,
                    )),
            ],
          ),
        ),
      ),
    );
  }
}
