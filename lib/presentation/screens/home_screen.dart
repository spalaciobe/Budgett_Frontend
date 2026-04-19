import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/widgets/add_transaction_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/edit_transaction_dialog.dart';

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
  Map<String, String> categoryMap,
) {
  final accountName = accountMap[t.accountId] ?? '';
  if (t.type == 'transfer') {
    final target =
        t.targetAccountId != null ? accountMap[t.targetAccountId!] : null;
    return target != null ? '$accountName → $target' : accountName;
  }
  final catName = t.subCategoryId != null
      ? categoryMap[t.subCategoryId!]
      : (t.categoryId != null ? categoryMap[t.categoryId!] : null);
  if (catName != null && catName.isNotEmpty) return '$accountName  ·  $catName';
  return accountName;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(recentTransactionsProvider);
          await ref.read(recentTransactionsProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kScreenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent Transactions',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Search bar
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
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 8),
              // Filter chips row
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
              const SizedBox(height: 12),
              // Transactions list
              transactionsAsync.when(
                data: (transactions) {
                  final filtered = _applyFilters(transactions);
                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          _hasActiveFilters
                              ? 'No transactions match your filters.'
                              : 'No recent transactions.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.5),
                          ),
                        ),
                      ),
                    );
                  }
                  return Card(
                    elevation: 2,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, indent: 72, endIndent: 16),
                      itemBuilder: (context, index) {
                        final t = filtered[index];
                        final isPending = t.status == 'pending';
                        final isExpense = t.type == 'expense';
                        final isTransfer = t.type == 'transfer';

                        final typeColor = isPending
                            ? Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4)
                            : isExpense
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.secondary;

                        final icon = isTransfer
                            ? Icons.sync_alt
                            : isExpense
                                ? Icons.arrow_downward
                                : Icons.arrow_upward;

                        final details =
                            _buildDetails(t, accountMap, categoryMap);
                        final accountIcon = accountIconMap[t.accountId];
                        final targetAccountIcon = isTransfer &&
                                t.targetAccountId != null
                            ? accountIconMap[t.targetAccountId!]
                            : null;
                        final sourceAccountName =
                            accountMap[t.accountId] ?? '';
                        final targetAccountName = isTransfer &&
                                t.targetAccountId != null
                            ? (accountMap[t.targetAccountId!] ?? '')
                            : '';

                        String? movementLabel;
                        if (!isTransfer && t.movementType != null) {
                          movementLabel = switch (t.movementType) {
                            'fixed' => 'Fixed',
                            'variable' => 'Variable',
                            'savings' => 'Savings',
                            _ => null,
                          };
                        }

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 3),
                          onTap: () {
                            // Swap legs are part of a linked pair — editing a
                            // single leg through the generic dialog would
                            // corrupt the other leg and mismatch holding
                            // qty_delta. To change a swap the user should
                            // delete and re-create it from the investment
                            // screen.
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
                              builder: (_) =>
                                  EditTransactionDialog(transaction: t),
                            );
                          },
                          leading: CircleAvatar(
                            backgroundColor: typeColor.withOpacity(0.12),
                            child: Icon(icon, color: typeColor, size: 20),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    decoration: isPending
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: isPending ? Colors.grey : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${isExpense ? '−' : '+'}${CurrencyFormatter.format(t.amount, decimalDigits: 0)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                                            .withOpacity(0.5),
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
                                        details,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.6),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 1),
                              Row(
                                children: [
                                  Text(
                                    _formatDate(t.date.toLocal()),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.45),
                                    ),
                                  ),
                                  if (isPending) ...[
                                    const SizedBox(width: 6),
                                    _Badge(
                                        label: 'Pending',
                                        color: Colors.orange),
                                  ],
                                  if (movementLabel != null) ...[
                                    const SizedBox(width: 6),
                                    _Badge(
                                      label: movementLabel,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (err, stack) => Text('Error: $err'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const AddTransactionDialog(),
        ),
        child: const Icon(Icons.add),
      ),
    );
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
          color: Colors.grey.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _TransferDetails extends StatelessWidget {
  final String? sourceIcon;
  final String sourceName;
  final String? targetIcon;
  final String targetName;

  const _TransferDetails({
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
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
    );
    return Row(
      children: [
        _buildIcon(sourceIcon),
        Flexible(
          child: Text(
            sourceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('→', style: textStyle),
        ),
        _buildIcon(targetIcon),
        Flexible(
          child: Text(
            targetName,
            maxLines: 1,
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
        color: color.withOpacity(0.15),
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
