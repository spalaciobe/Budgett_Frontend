import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/utils/error_messages.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/core/app_theme.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/widgets/add_transaction_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/edit_transaction_dialog.dart';
import 'package:budgett_frontend/core/app_text.dart';
import 'package:budgett_frontend/presentation/widgets/page_body.dart';
import 'package:budgett_frontend/presentation/widgets/skeleton.dart';
import 'package:budgett_frontend/presentation/providers/message_capture_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import '../widgets/screen_title.dart';
import 'capture_inbox_screen.dart';
import 'package:budgett_frontend/core/app_palette.dart';

String _formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final now = DateTime.now();
  if (date.year == now.year) {
    return '${months[date.month - 1]} ${date.day}';
  }
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _buildDetails(
  Transaction t,
  Map<String, String> accountMap,
  Map<String, String> categoryMap, {
  bool hasIcon = false,
}) {
  final accountName = accountMap[t.accountId] ?? '';
  if (t.type == 'transfer') {
    final target =
        t.targetAccountId != null ? accountMap[t.targetAccountId!] : null;
    return target != null ? '$accountName → $target' : accountName;
  }
  final catName = t.subCategoryId != null
      ? categoryMap[t.subCategoryId!]
      : (t.categoryId != null ? categoryMap[t.categoryId!] : null);
  if (catName == null || catName.isEmpty) return accountName;
  // With the account's logo right there, its name is the part of this line
  // worth losing — keeping both made every row truncate mid-word.
  return hasIcon ? catName : '$accountName  ·  $catName';
}

/// The month's headline: what's left, and how much of the income it took.
///
/// This is the screen's entry point, and the only element on Home allowed to
/// shout. It used to be three equal-weight metrics in a row, which meant Home
/// opened with nothing to look at first — every figure was 17px and none of
/// them answered "am I fine this month?".
///
/// The bar is not decoration: it is spent-over-income, so the answer is
/// legible before any number is read. Income and spent stay underneath as the
/// supporting detail they are.
class _MonthSummaryCard extends ConsumerWidget {
  const _MonthSummaryCard();

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final async = ref.watch(homeMonthSummaryProvider);

    if (async.isLoading && !async.hasValue) return const SkeletonHeroCard();

    final data = async.valueOrNull;
    final income = data?.income ?? 0.0;
    final spent = data?.spent ?? 0.0;
    final net = income - spent;
    final overspent = net < 0;

    // Share of income already spent. With no income recorded yet, any spending
    // is the whole of it.
    final ratio = income > 0
        ? (spent / income).clamp(0.0, 1.0)
        : (spent > 0 ? 1.0 : 0.0);
    final percent = (ratio * 100).round();

    // The card *is* the accent, the way the reference apps do it: a saturated
    // block holding the figure, with ink dark enough to read on it. An accent
    // used only as a thin trim on a dark screen reads as a detail; used as a
    // surface it becomes the thing the screen is about.
    final palette = context.palette;
    final onBlock = palette.onBrand;
    final netColor = overspent ? context.negative : onBlock;

    return Card(
      color: overspent ? null : palette.brand,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        side: BorderSide(
          color: overspent
              ? Theme.of(context).colorScheme.outlineVariant
              : palette.brand,
        ),
      ),
      child: Padding(
        // Tighter than kHeroCardPadding: this card is a summary, and at 20px
        // padding around a 36px figure it was eating a third of the phone.
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_months[now.month - 1]} ${now.year}',
              style: AppText.label.copyWith(
                color: overspent
                    ? context.muted
                    : onBlock.withValues(alpha: 0.65),
              ),
            ),
            kGapSm,
            // The verdict sits beside the figure instead of under it: one
            // line saved is ~20% of this card's height, and the two belong
            // together anyway ("$136.633 over your income").
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    CurrencyFormatter.format(net.abs()),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: AppText.balanceHero.copyWith(color: netColor),
                  ),
                ),
                const SizedBox(width: kSpaceLg),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      overspent ? 'over your income' : 'left this month',
                      style: AppText.caption.copyWith(
                        color: overspent
                            ? context.muted
                            : onBlock.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                    ),
                  ),
                ),
              ],
            ),
            kGapLg,
            _SpendBar(ratio: ratio, overspent: overspent, onBlock: onBlock),
            kGapMd,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Income',
                    amount: income,
                    color: overspent ? theme.colorScheme.onSurface : onBlock,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '$percent% spent',
                    amount: spent,
                    color: overspent ? theme.colorScheme.onSurface : onBlock,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpendBar extends StatelessWidget {
  final double ratio;
  final bool overspent;

  /// Ink for the lime block; null when the card falls back to a plain surface.
  final Color? onBlock;

  const _SpendBar({
    required this.ratio,
    required this.overspent,
    this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    final ink = onBlock ?? context.muted;
    final track = overspent
        ? context.muted.withValues(alpha: 0.18)
        : ink.withValues(alpha: 0.22);
    final fill = overspent ? context.negative : ink;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          Container(height: 7, color: track),
          FractionallySizedBox(
            widthFactor: ratio,
            child: Container(height: 7, color: fill),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool alignEnd;

  const _Metric({
    required this.label,
    required this.amount,
    required this.color,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.caption.copyWith(color: color.withValues(alpha: 0.65)),
        ),
        kGapXs,
        Text(
          CurrencyFormatter.format(amount),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: AppText.moneyMedium.copyWith(color: color),
        ),
      ],
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _searchOpen = false;
  bool _filtersOpen = false;
  final Set<String> _filterTypes = {};
  final Set<String> _filterAccountIds = {};
  DateTimeRange? _filterDateRange;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _filterTypes.isNotEmpty ||
      _filterAccountIds.isNotEmpty ||
      _filterDateRange != null;

  List<Transaction> _applyFilters(List<Transaction> all) {
    return all.where((t) {
      if (_searchQuery.isNotEmpty &&
          !t.description.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_filterTypes.isNotEmpty && !_filterTypes.contains(t.type)) {
        return false;
      }
      if (_filterAccountIds.isNotEmpty &&
          !_filterAccountIds.contains(t.accountId)) {
        return false;
      }
      if (_filterDateRange != null) {
        final d = t.date.toLocal();
        final start = _filterDateRange!.start;
        final end = DateTime(
          _filterDateRange!.end.year,
          _filterDateRange!.end.month,
          _filterDateRange!.end.day,
          23, 59, 59,
        );
        if (d.isBefore(start) || d.isAfter(end)) return false;
      }
      return true;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _searchOpen = false;
      _filterTypes.clear();
      _filterAccountIds.clear();
      _filterDateRange = null;
    });
  }

  Future<void> _pickDateRange() async {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _filterDateRange,
      builder: isDesktop
          ? (context, child) => Dialog(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 520,
                    maxHeight: 600,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: child,
                  ),
                ),
              )
          : null,
    );
    if (picked != null) setState(() => _filterDateRange = picked);
  }

  void _showTypePicker(BuildContext context) {
    const options = [
      ('Income', 'income'),
      ('Expense', 'expense'),
      ('Transfer', 'transfer'),
    ];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _SheetHandle(),
              const SizedBox(height: 4),
              const ListTile(
                title: Text('Transaction type',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const Divider(height: 1),
              for (final (label, value) in options)
                CheckboxListTile(
                  title: Text(label),
                  value: _filterTypes.contains(value),
                  onChanged: (on) {
                    setState(() {
                      if (on == true) {
                        _filterTypes.add(value);
                      } else {
                        _filterTypes.remove(value);
                      }
                    });
                    setLocal(() {});
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountPicker(BuildContext context, List<Account> accounts) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _SheetHandle(),
              const SizedBox(height: 4),
              const ListTile(
                title: Text('Account',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: accounts.length,
                  itemBuilder: (_, i) {
                    final a = accounts[i];
                    final iconUrl =
                        (a.icon != null && a.icon!.startsWith('http'))
                            ? a.icon!
                            : null;
                    return CheckboxListTile(
                      secondary: iconUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                iconUrl,
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.account_balance_wallet_outlined),
                              ),
                            )
                          : const Icon(Icons.account_balance_wallet_outlined),
                      title: Text(a.name),
                      value: _filterAccountIds.contains(a.id),
                      onChanged: (on) {
                        setState(() {
                          if (on == true) {
                            _filterAccountIds.add(a.id);
                          } else {
                            _filterAccountIds.remove(a.id);
                          }
                        });
                        setLocal(() {});
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? cs.onSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? cs.onSurface
                  : cs.outline.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? cs.surface : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(recentTransactionsProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final accounts = accountsAsync.valueOrNull ?? [];
    final accountMap = <String, String>{};
    final accountIconMap = <String, String?>{};
    String? httpIcon(String? icon) =>
        (icon != null && icon.startsWith('http')) ? icon : null;
    for (final a in accounts) {
      accountMap[a.id] = a.name;
      accountIconMap[a.id] = httpIcon(a.icon);
      for (final p in a.pockets) {
        accountMap[p.id] = '${a.name} · ${p.name}';
        accountIconMap[p.id] = httpIcon(p.icon) ?? httpIcon(a.icon);
      }
    }
    final categoryMap = <String, String>{};
    for (final cat in categoriesAsync.valueOrNull ?? []) {
      categoryMap[cat.id] = cat.name;
      for (final sc in cat.subCategories ?? []) {
        categoryMap[sc.id] = sc.name;
      }
    }

    final typeLabel = switch (_filterTypes.length) {
      0 => 'Type',
      1 => _filterTypes.first[0].toUpperCase() +
          _filterTypes.first.substring(1),
      _ => '${_filterTypes.length} types',
    };

    final accountLabel = switch (_filterAccountIds.length) {
      0 => 'Account',
      1 => accountMap[_filterAccountIds.first] ?? 'Account',
      _ => '${_filterAccountIds.length} accounts',
    };

    final dateLabel = _filterDateRange != null
        ? '${_formatDate(_filterDateRange!.start)} – ${_formatDate(_filterDateRange!.end)}'
        : 'Date';

    final pendingCount = ref.watch(pendingCaptureCountProvider).valueOrNull ?? 0;

    // Two tabs, not two destinations. A captured message *is* a transaction
    // that hasn't been confirmed yet, so it belongs beside the confirmed ones.
    // It used to live under "More", two taps from the list it describes, and
    // needed a badge there *and* a banner here before anyone noticed it.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
      appBar: AppBar(
        title: ScreenTitle('Transactions'),
        actions: [
          // Search was a fixed 56px row above the list. On a phone the header
          // (title, tabs, month summary, search, filter chips) left room for
          // four transactions — so the field now opens from here and takes no
          // space until it is asked for.
          IconButton(
            tooltip: _searchOpen ? 'Close search' : 'Search transactions',
            icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _searchController.clear();
                _searchQuery = '';
              }
            }),
          ),
          // Same bargain as search: the filter chips were a permanent row for
          // something rarely on. The dot says filters are active without
          // having to show them.
          IconButton(
            tooltip: _filtersOpen ? 'Hide filters' : 'Filter transactions',
            icon: Badge(
              isLabelVisible: _hasActiveFilters,
              smallSize: 7,
              child: Icon(
                  _filtersOpen ? Icons.filter_list_off : Icons.filter_list),
            ),
            onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
          ),
        ],
        bottom: TabBar(
          // Not scrollable: with exactly two tabs, left-aligning them leaves
          // two thirds of the bar empty and the pair reads as misplaced.
          // Full width also makes each one a much bigger tap target.
          tabs: [
            const Tab(text: 'All'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('To review'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: kSpaceMd),
                    Badge(label: Text('$pendingCount')),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(recentTransactionsProvider);
          await ref.read(recentTransactionsProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kScreenPaddingWithFab,
          // The list is two columns (description, amount), so it gets a
          // ceiling rather than the whole viewport. The first attempt capped
          // it at 1000, which on a 1920 monitor left ~800px of nothing to the
          // right of the summary. The pane widths below spend that width
          // instead: tabular figures keep a wider row readable, because the
          // amounts still line up in a column.
          child: PageBody(
            child: TwoPaneLayout(
              asideWidth: 420,
              aside: const _MonthSummaryCard(),
              main: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search bar — only while it is in use.
              if (_searchOpen || _searchQuery.isNotEmpty) ...[
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 8),
              ],
              // Filter chips row — while open, or while something is filtered.
              if (_filtersOpen || _hasActiveFilters)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Type filter
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildFilterChip(
                        label: typeLabel,
                        selected: _filterTypes.isNotEmpty,
                        onTap: () => _showTypePicker(context),
                      ),
                    ),
                    // Account filter
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildFilterChip(
                        label: accountLabel,
                        selected: _filterAccountIds.isNotEmpty,
                        onTap: () => _showAccountPicker(context, accounts),
                      ),
                    ),
                    // Date filter
                    _buildFilterChip(
                      label: dateLabel,
                      selected: _filterDateRange != null,
                      onTap: () async {
                        if (_filterDateRange != null) {
                          setState(() => _filterDateRange = null);
                        } else {
                          await _pickDateRange();
                        }
                      },
                    ),
                    // Clear filters
                    if (_hasActiveFilters) ...[
                      const SizedBox(width: 6),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _clearFilters,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              kGapLg,
              // Transactions list
              transactionsAsync.when(
                data: (transactions) {
                  final filtered = _applyFilters(transactions);
                  if (filtered.isEmpty) {
                    // An empty screen is an invitation to act, so each case
                    // says what to do next rather than only what is missing.
                    return _EmptyTransactions(
                      filtered: _hasActiveFilters,
                      onClearFilters: _clearFilters,
                    );
                  }
                  final rows = _buildRows(filtered);
                  return Card(
                    // No elevation override: the card theme's hairline is the
                    // app's one structural device, and a drop shadow here made
                    // this the only raised surface in the app.
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, indent: 56, endIndent: 14),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is _HomeRowGroup) {
                          return _InstallmentGroupTile(
                            children: row.children,
                            accountMap: accountMap,
                            accountIconMap: accountIconMap,
                            categoryMap: categoryMap,
                          );
                        }
                        final t = (row as _HomeRowSingle).transaction;
                        return _TransactionListTile(
                          transaction: t,
                          accountMap: accountMap,
                          accountIconMap: accountIconMap,
                          categoryMap: categoryMap,
                        );
                      },
                    ),
                  );
                },
                loading: () => const SkeletonList(
                  rows: 7,
                  padding: EdgeInsets.symmetric(vertical: kSpaceXl),
                ),
                error: (err, stack) => _LoadError(message: friendlyError(err)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
          CaptureList(
            provider: pendingCapturesProvider,
            emptyTitle: 'Nothing to review',
            emptyBody: 'Card purchases captured from your bank notifications '
                'show up here when they need a decision.',
            onRefresh: () async {
              ref.invalidate(pendingCapturesProvider);
              await ref.read(pendingCapturesProvider.future);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const AddTransactionDialog(),
        ),
        child: const Icon(Icons.add),
      ),
      ),
    );
  }

  /// Folds installment children sharing a [parent_transaction_id] into a
  /// single [_HomeRowGroup]. If only one cuota survives the active filters,
  /// it is rendered as a regular [_HomeRowSingle] so the group header
  /// doesn't look misleading. Group sort date is the earliest cuota date
  /// (the next due payment) — this keeps the row near today's activity
  /// instead of pinning it to the latest future cycle.
  List<_HomeRow> _buildRows(List<Transaction> filtered) {
    final groups = <String, List<Transaction>>{};
    final singles = <Transaction>[];
    for (final t in filtered) {
      final parentId = t.parentTransactionId;
      if (parentId != null && t.isInstallmentChild) {
        groups.putIfAbsent(parentId, () => []).add(t);
      } else {
        singles.add(t);
      }
    }

    final rows = <_HomeRow>[];
    for (final t in singles) {
      rows.add(_HomeRowSingle(t, t.date));
    }
    for (final entry in groups.entries) {
      final children = entry.value;
      if (children.length <= 1) {
        for (final c in children) {
          rows.add(_HomeRowSingle(c, c.date));
        }
        continue;
      }
      children.sort((a, b) =>
          (a.installmentNumber ?? 0).compareTo(b.installmentNumber ?? 0));
      final earliest =
          children.map((c) => c.date).reduce((a, b) => a.isBefore(b) ? a : b);
      rows.add(_HomeRowGroup(children, earliest));
    }

    rows.sort((a, b) => b.sortDate.compareTo(a.sortDate));
    return rows;
  }

}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: context.muted.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _TransferDetails extends StatelessWidget {
  /// Prefixed to the route, so a transfer row is two lines like every other.
  final String date;
  final String? sourceIcon;
  final String sourceName;
  final String? targetIcon;
  final String targetName;

  const _TransferDetails({
    required this.date,
    required this.sourceIcon,
    required this.sourceName,
    required this.targetIcon,
    required this.targetName,
  });

  Widget _buildIcon(String? url) {
    if (url == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Image.network(
          url,
          width: 12,
          height: 12,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    );
    // Two account names plus a date never fit beside an amount, so both ends
    // were cut mid-word ("Bancolombi → RappiCuent"). Both accounts already
    // show their logo here, and on a transfer the destination is the part
    // that answers "where did it go" — so only that one keeps its name.
    return Row(
      children: [
        Text('$date  ·  ', style: textStyle),
        _buildIcon(sourceIcon),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('→', style: textStyle),
        ),
        _buildIcon(targetIcon),
        Flexible(
          child: Text(
            targetName,
            maxLines: 1,
            // Ellipsis, not fade: when a name does have to be cut, three dots
            // say so. A fade just dissolves the last letters and reads like a
            // rendering fault — which is how it kept being reported.
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ─── Row model: a single transaction OR a folded installment group ────────────

sealed class _HomeRow {
  DateTime get sortDate;
}

class _HomeRowSingle extends _HomeRow {
  final Transaction transaction;
  @override
  final DateTime sortDate;
  _HomeRowSingle(this.transaction, this.sortDate);
}

class _HomeRowGroup extends _HomeRow {
  final List<Transaction> children; // sorted by installmentNumber asc
  @override
  final DateTime sortDate;
  _HomeRowGroup(this.children, this.sortDate);
}

// ─── Single-transaction tile (extracted from the old inline itemBuilder) ──────

class _TransactionListTile extends StatelessWidget {
  final Transaction transaction;
  final Map<String, String> accountMap;
  final Map<String, String?> accountIconMap;
  final Map<String, String> categoryMap;

  const _TransactionListTile({
    required this.transaction,
    required this.accountMap,
    required this.accountIconMap,
    required this.categoryMap,
  });

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final isPending = t.status == 'pending';
    final isExpense = t.type == 'expense';
    final isTransfer = t.type == 'transfer';

    final typeColor = isPending
        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)
        : isTransfer
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : isExpense
                ? Theme.of(context).colorScheme.error
                : context.semantic.positive;

    final icon = isTransfer
        ? Icons.sync_alt
        : isExpense
            ? Icons.arrow_downward
            : Icons.arrow_upward;

    final accountIcon = accountIconMap[t.accountId];
    final details = _buildDetails(t, accountMap, categoryMap,
        hasIcon: accountIcon != null);
    final targetAccountIcon = isTransfer && t.targetAccountId != null
        ? accountIconMap[t.targetAccountId!]
        : null;
    final sourceAccountName = accountMap[t.accountId] ?? '';
    final targetAccountName = isTransfer && t.targetAccountId != null
        ? (accountMap[t.targetAccountId!] ?? '')
        : '';

    String? movementLabel;
    if (!isTransfer && t.movementType != null) {
      movementLabel = switch (t.movementType) {
        'fixed' => 'Fixed',
        'variable' => 'Variable',
        'savings' => 'Savings',
        'reimbursement' => 'Reimbursement',
        _ => null,
      };
    }

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      onTap: () {
        if (t.type == 'swap') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Swap transactions can\'t be edited directly — delete and re-create from the investment account.',
              ),
            ),
          );
          return;
        }
        showDialog(
          context: context,
          builder: (_) => EditTransactionDialog(transaction: t),
        );
      },
      leading: CircleAvatar(
        backgroundColor: typeColor.withValues(alpha: 0.12),
        child: Icon(icon, color: typeColor, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              t.description,
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                decoration:
                    isPending ? TextDecoration.lineThrough : null,
                color: isPending ? context.muted : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${isTransfer ? '' : (isExpense ? '−' : '+')}${CurrencyFormatter.format(t.amount)}',
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  color: typeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (t.currency == 'USD')
                Text(
                  'USD',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isTransfer && t.targetAccountId != null)
            _TransferDetails(
              date: _formatDate(t.date.toLocal()),
              sourceIcon: accountIcon,
              sourceName: sourceAccountName,
              targetIcon: targetAccountIcon,
              targetName: targetAccountName,
            )
          else if (details.isNotEmpty)
            Row(
              children: [
                if (accountIcon != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Image.network(
                      accountIcon,
                      width: 12,
                      height: 12,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    '${_formatDate(t.date.toLocal())}  ·  $details',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            )
          else
            Text(
              _formatDate(t.date.toLocal()),
              style: AppText.caption.copyWith(color: context.muted),
            ),
          // Only "Pending" earns a line of its own. The movement type
          // (fixed / variable / savings) was shown on every row and cost one,
          // for a classification this app's owner doesn't use.
          if (isPending) ...[
            kGapXs,
            _Badge(label: 'Pending', color: context.semantic.warning),
          ],
        ],
      ),
      isThreeLine: true,
    );
  }
}

// ─── Folded installment group tile ────────────────────────────────────────────
//
// Collapsed header summarises the whole purchase (base description, account,
// category, total cuotas, next-due date, per-cuota amount). Expanded body
// inlines the same TransactionListTile for each cuota so editing/status
// behaviour is identical to the ungrouped path.

class _InstallmentGroupTile extends StatefulWidget {
  final List<Transaction> children; // sorted by installmentNumber asc
  final Map<String, String> accountMap;
  final Map<String, String?> accountIconMap;
  final Map<String, String> categoryMap;

  const _InstallmentGroupTile({
    required this.children,
    required this.accountMap,
    required this.accountIconMap,
    required this.categoryMap,
  });

  @override
  State<_InstallmentGroupTile> createState() =>
      _InstallmentGroupTileState();
}

class _InstallmentGroupTileState extends State<_InstallmentGroupTile> {
  bool _expanded = false;

  static final _suffixRegex = RegExp(r'\s*-\s*Inst\.\s*\d+/\d+\s*$');

  String get _baseDescription {
    final first = widget.children.first.description;
    return first.replaceAll(_suffixRegex, '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sample = widget.children.first;
    final numCuotas = sample.numCuotas ?? widget.children.length;
    final accountName = widget.accountMap[sample.accountId] ?? '';
    final categoryName = sample.subCategoryId != null
        ? widget.categoryMap[sample.subCategoryId!]
        : (sample.categoryId != null
            ? widget.categoryMap[sample.categoryId!]
            : null);
    final accountIcon = widget.accountIconMap[sample.accountId];
    final cleared = widget.children
        .where((c) => c.status == 'paid' || c.status == 'cleared')
        .length;
    final pending = widget.children
        .where((c) => c.status == 'pending')
        .toList();
    final nextDue = pending.isNotEmpty
        ? pending.map((c) => c.date).reduce((a, b) => a.isBefore(b) ? a : b)
        : widget.children
            .map((c) => c.date)
            .reduce((a, b) => a.isBefore(b) ? a : b);
    final perCuota = sample.amount;
    final total = widget.children.fold<double>(0, (s, c) => s + c.amount);
    final isUsd = sample.currency == 'USD';
    final color = theme.colorScheme.error;

    final detailLine = [
      accountName,
      if (categoryName != null && categoryName.isNotEmpty) categoryName,
    ].join('  ·  ');

    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          onTap: () => setState(() => _expanded = !_expanded),
          leading: Stack(
            alignment: Alignment.bottomRight,
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(Icons.layers_outlined, color: color, size: 20),
              ),
              Positioned(
                right: -4,
                bottom: -2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: color.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '$cleared/$numCuotas',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  _baseDescription,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '−${CurrencyFormatter.format(perCuota)}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '× $numCuotas · ${CurrencyFormatter.format(total)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (detailLine.isNotEmpty)
                Row(
                  children: [
                    if (accountIcon != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Image.network(
                          accountIcon,
                          width: 12,
                          height: 12,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        detailLine,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    pending.isNotEmpty
                        ? 'Next ${_formatDate(nextDue.toLocal())}'
                        : 'Paid · ${_formatDate(nextDue.toLocal())}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Badge(
                    label: 'Installments',
                    color: theme.colorScheme.primary,
                  ),
                  if (isUsd) ...[
                    const SizedBox(width: 6),
                    _Badge(label: 'USD', color: context.brand),
                  ],
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ],
          ),
          isThreeLine: true,
        ),
        if (_expanded)
          Container(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.025),
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              children: [
                for (final c in widget.children) ...[
                  _TransactionListTile(
                    transaction: c,
                    accountMap: widget.accountMap,
                    accountIconMap: widget.accountIconMap,
                    categoryMap: widget.categoryMap,
                  ),
                  if (c != widget.children.last)
                    const Divider(height: 1, indent: 72, endIndent: 16),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Empty list, with a way out of it.
///
/// "No recent transactions." named the absence and left the person there. Each
/// case now offers the action that resolves it.
class _EmptyTransactions extends StatelessWidget {
  /// Whether the list is empty because filters hid everything.
  final bool filtered;
  final VoidCallback onClearFilters;

  const _EmptyTransactions({
    required this.filtered,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
            child: Column(
              children: [
                Icon(
                  filtered ? Icons.filter_alt_off_outlined : Icons.receipt_long,
                  size: 40,
                  color: context.muted,
                ),
                kGapXl,
                Text(
                  filtered
                      ? 'No transactions match these filters'
                      : 'No transactions yet',
                  textAlign: TextAlign.center,
                  style: AppText.sectionTitle,
                ),
                kGapSm,
                Text(
                  filtered
                      ? 'Widen the date range or clear the filters to see everything again.'
                      : 'Add one with the + button, or turn on message capture to record card purchases automatically.',
                  textAlign: TextAlign.center,
                  style: AppText.subtitle.copyWith(color: context.muted),
                ),
                if (filtered) ...[
                  kGapSection,
                  OutlinedButton.icon(
                    onPressed: onClearFilters,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Clear filters'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A load failure that stays inside the card it replaces, instead of a bare
/// line of red text at the edge of the screen.
class _LoadError extends StatelessWidget {
  final String message;

  const _LoadError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: kCardPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: context.negative),
            const SizedBox(width: kSpaceXl),
            Expanded(
              child: Text(
                message,
                style: AppText.subtitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

