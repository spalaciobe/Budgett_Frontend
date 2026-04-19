import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/core/responsive.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/widgets/create_category_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/edit_budget_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/budget_comparison_widget.dart';
import 'package:budgett_frontend/presentation/widgets/edit_category_dialog.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/category_spending.dart';
import 'package:fl_chart/fl_chart.dart';

final budgetDateProvider = StateProvider.autoDispose<DateTime>((ref) => DateTime.now());

Color _parseColor(String colorStr) {
  try {
    return Color(int.parse(colorStr));
  } catch (_) {
    return Colors.grey;
  }
}

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(budgetDateProvider);
    final budgetsAsync = ref.watch(budgetsProvider((month: selectedDate.month, year: selectedDate.year)));
    final categoriesAsync = ref.watch(categoriesProvider);
    final accumulatedBalancesAsync = ref.watch(categoryAccumulatedBalancesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: () {
                  ref.read(budgetDateProvider.notifier).state = DateTime(
                    selectedDate.year,
                    selectedDate.month - 1,
                  );
                },
              ),
              GestureDetector(
                onTap: () async {
                  final picked = await showDialog<DateTime>(
                    context: context,
                    builder: (context) => _MonthPickerDialog(initialDate: selectedDate),
                  );
                  if (picked != null) {
                    ref.read(budgetDateProvider.notifier).state = picked;
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    '${_getMonthName(selectedDate.month)} ${selectedDate.year}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: () {
                  ref.read(budgetDateProvider.notifier).state = DateTime(
                    selectedDate.year,
                    selectedDate.month + 1,
                  );
                },
              ),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy from previous month',
            onPressed: () async {
              final prevMonth = selectedDate.month == 1 ? 12 : selectedDate.month - 1;
              final prevYear = selectedDate.month == 1 ? selectedDate.year - 1 : selectedDate.year;
              final prevMonthName = _getMonthName(prevMonth);
              final currMonthName = _getMonthName(selectedDate.month);
              final hasCurrent = budgetsAsync.valueOrNull?.isNotEmpty ?? false;

              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Copy Budget'),
                  content: Text(
                    hasCurrent
                        ? 'This will replace budgets for $currMonthName ${selectedDate.year} with those from $prevMonthName $prevYear. Continue?'
                        : 'Copy budgets from $prevMonthName $prevYear to $currMonthName ${selectedDate.year}?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Copy'),
                    ),
                  ],
                ),
              );

              if (confirm != true) return;

              final messenger = ScaffoldMessenger.of(context);
              try {
                final count = await ref.read(financeRepositoryProvider)
                    .copyBudgetsFromPreviousMonth(selectedDate.month, selectedDate.year);
                ref.invalidate(budgetsProvider((month: selectedDate.month, year: selectedDate.year)));
                if (count == 0) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('No budgets in $prevMonthName $prevYear to copy.')),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(content: Text('$count budget${count == 1 ? '' : 's'} copied from $prevMonthName $prevYear.')),
                  );
                }
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(budgetsProvider((month: selectedDate.month, year: selectedDate.year)));
          ref.invalidate(categoriesProvider);
          await Future.wait([
            ref.read(budgetsProvider((month: selectedDate.month, year: selectedDate.year)).future),
            ref.read(categoriesProvider.future),
          ]);
        },
        child: budgetsAsync.when(
          data: (budgets) {
            return categoriesAsync.when(
              data: (categories) {
                if (categories.isEmpty) {
                  return const Center(child: Text('No categories defined.'));
                }

                final categoryMap = {for (var c in categories) c.id: c};

                final totalBudget = budgets.fold<double>(
                  0.0,
                  (sum, budget) {
                    final category = categoryMap[budget.categoryId];
                    if (category?.type == 'income') return sum;
                    return sum + budget.amount;
                  },
                );

                final expectedIncome = budgets.fold<double>(
                  0.0,
                  (sum, budget) {
                    final category = categoryMap[budget.categoryId];
                    if (category?.type == 'income') return sum + budget.amount;
                    return sum;
                  },
                );

                return FutureBuilder<double>(
                  future: ref.read(financeRepositoryProvider).getMonthlyIncome(selectedDate.month, selectedDate.year),
                  builder: (context, incomeSnapshot) {
                    final monthlyIncome = incomeSnapshot.data ?? 0.0;
                    final baseIncome = expectedIncome > 0 ? expectedIncome : monthlyIncome;
                    final availableToAllocate = baseIncome - totalBudget;
                    final allocationPercentage = baseIncome > 0 ? (totalBudget / baseIncome * 100) : 0.0;

                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: Future.wait([
                        ref.read(financeRepositoryProvider).getSpendingByCategory(selectedDate.month, selectedDate.year),
                        ref.read(financeRepositoryProvider).getIncomeByCategory(selectedDate.month, selectedDate.year),
                      ]),
                      builder: (context, snapshots) {
                        final spending = snapshots.data?[0] ?? {};
                        final incomeFlows = snapshots.data?[1] ?? {};
                        final totalSpent = spending.values.fold<double>(0.0, (sum, val) => sum + (val as CategorySpending).total);
                        final budgetAmountsMap = {
                          for (final b in budgets) b.categoryId: b.amount as double,
                        };
                        final sortedCategories = [...categories]..sort((a, b) {
                          final aBudget = budgetAmountsMap[a.id] ?? 0.0;
                          final bBudget = budgetAmountsMap[b.id] ?? 0.0;
                          return bBudget.compareTo(aBudget);
                        });

                        // Split budget/spent totals into expense vs savings so the
                        // Financial Health card can show commitments distinctly.
                        double savingsBudget = 0.0;
                        double savingsContributed = 0.0;
                        for (final cat in categories) {
                          if (cat.type != 'savings') continue;
                          savingsBudget += budgetAmountsMap[cat.id] ?? 0.0;
                          final sc = spending[cat.id];
                          if (sc is CategorySpending) savingsContributed += sc.total;
                        }
                        final expenseBudget = (totalBudget - savingsBudget).clamp(0.0, double.infinity);
                        final expenseSpent = (totalSpent - savingsContributed).clamp(0.0, double.infinity);

                        final savingsCategories = sortedCategories
                            .where((c) => c.type == 'savings')
                            .toList();
                        final nonSavingsCategories = sortedCategories
                            .where((c) => c.type != 'savings')
                            .toList();
                        final accumulated =
                            accumulatedBalancesAsync.valueOrNull ?? const {};

                        Widget buildRow(Category cat) {
                          final budget = budgets.cast<dynamic>().firstWhere(
                            (b) => b.categoryId == cat.id,
                            orElse: () => null,
                          );
                          final actualSpent = cat.type == 'income'
                              ? (incomeFlows[cat.id]?.total ?? 0.0)
                              : (spending[cat.id]?.total ?? 0.0);
                          final budgetAmount = budget?.amount ?? 0.0;

                          final subSpending = cat.type == 'income'
                              ? incomeFlows[cat.id]?.subCategories
                              : spending[cat.id]?.subCategories;

                          return BudgetComparisonWidget(
                            categoryName: cat.name,
                            budgetAmount: budgetAmount,
                            spentAmount: actualSpent,
                            color: cat.color != null
                                ? _parseColor(cat.color!)
                                : null,
                            iconName: cat.icon,
                            isIncome: cat.type == 'income',
                            isSavings: cat.type == 'savings',
                            accumulatedBalance: cat.type == 'savings'
                                ? (accumulated[cat.id] ?? 0.0)
                                : null,
                            subCategories: cat.subCategories,
                            subCategorySpending: subSpending,
                            onEditBudget: () {
                              showDialog(
                                context: context,
                                builder: (context) => EditBudgetDialog(
                                  categoryId: cat.id,
                                  categoryName: cat.name,
                                  month: selectedDate.month,
                                  year: selectedDate.year,
                                  currentAmount: budget?.amount,
                                  categoryType: cat.type,
                                  categoryIcon: cat.icon,
                                  categoryColor: cat.color,
                                ),
                              );
                            },
                            onEditCategory: () {
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    EditCategoryDialog(category: cat),
                              );
                            },
                          );
                        }

                        return Column(
                          children: [
                            _BudgetTopCard(
                              monthlyIncome: monthlyIncome,
                              expectedIncome: expectedIncome,
                              totalBudget: totalBudget,
                              totalSpent: totalSpent,
                              expenseBudget: expenseBudget,
                              expenseSpent: expenseSpent,
                              savingsBudget: savingsBudget,
                              savingsContributed: savingsContributed,
                              allocationPercentage: allocationPercentage,
                              availableToAllocate: availableToAllocate,
                              categories: sortedCategories,
                              spending: spending,
                              budgetAmounts: budgetAmountsMap,
                            ),

                            // Categories list (expense + income, then savings).
                            Expanded(
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                children: [
                                  ...nonSavingsCategories.map(buildRow),
                                  if (savingsCategories.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 16, bottom: 8, left: 4),
                                      child: Row(
                                        children: [
                                          Icon(Icons.savings_outlined,
                                              size: 16,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.7)),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Savings & Sinking Funds',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.75),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...savingsCategories.map(buildRow),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error loading categories: $e')),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const CreateCategoryDialog(),
          );
        },
        child: const Icon(Icons.add),
        tooltip: 'Add Category',
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}

// ─── Top card with Financial Health / Donut toggle ────────────────────────────

class _BudgetTopCard extends StatefulWidget {
  final double monthlyIncome;
  final double expectedIncome;
  final double totalBudget;
  final double totalSpent;
  final double expenseBudget;
  final double expenseSpent;
  final double savingsBudget;
  final double savingsContributed;
  final double allocationPercentage;
  final double availableToAllocate;
  final List<Category> categories;
  final Map<String, dynamic> spending;
  final Map<String, double> budgetAmounts;

  const _BudgetTopCard({
    required this.monthlyIncome,
    required this.expectedIncome,
    required this.totalBudget,
    required this.totalSpent,
    required this.expenseBudget,
    required this.expenseSpent,
    required this.savingsBudget,
    required this.savingsContributed,
    required this.allocationPercentage,
    required this.availableToAllocate,
    required this.categories,
    required this.spending,
    required this.budgetAmounts,
  });

  @override
  State<_BudgetTopCard> createState() => _BudgetTopCardState();
}

class _BudgetTopCardState extends State<_BudgetTopCard> {
  int _view = 0;        // 0 = Financial Health, 1 = Donut
  int _donutMode = 0;   // 0 = Budget distribution, 1 = Spending distribution

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, kSpaceLg, 16, kSpaceLg),
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).cardTheme.color ?? Colors.white,
              Theme.of(context).cardTheme.color?.withOpacity(0.95) ?? Colors.white.withOpacity(0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (context.formFactor != FormFactor.mobile)
                Row(
                  children: [
                    SegmentedButton<int>(
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.bar_chart_outlined, size: 16),
                          label: Text('Financial Health'),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.donut_large_outlined, size: 16),
                          label: Text('Spending'),
                        ),
                      ],
                      selected: {_view},
                      onSelectionChanged: (s) => setState(() => _view = s.first),
                    ),
                    const Spacer(),
                    if (_view == 0)
                      _buildAllocationBadge(context)
                    else if (context.formFactor == FormFactor.desktop)
                      _buildDonutSubToggle(),
                  ],
                )
              else
                Center(
                  child: SegmentedButton<int>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.bar_chart_outlined, size: 16),
                        label: Text('Financial Health'),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.donut_large_outlined, size: 16),
                        label: Text('Spending'),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) => setState(() => _view = s.first),
                  ),
                ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _view == 0
                    ? _buildHealthContent(context)
                    : _buildDonutContent(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllocationBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.allocationPercentage > 100
            ? Colors.red.withOpacity(0.1)
            : Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.allocationPercentage > 100
              ? Colors.red.withOpacity(0.2)
              : Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.allocationPercentage.toStringAsFixed(1)}% Allocated',
            style: TextStyle(
              color: widget.allocationPercentage > 100
                  ? Colors.red
                  : Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.availableToAllocate > 0
                ? 'Remaining: ${CurrencyFormatter.format(widget.availableToAllocate, decimalDigits: 0)}'
                : 'Over: ${CurrencyFormatter.format(widget.availableToAllocate.abs(), decimalDigits: 0)}',
            style: TextStyle(
              color: widget.allocationPercentage > 100
                  ? Colors.red
                  : Theme.of(context).colorScheme.onPrimaryContainer,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthContent(BuildContext context) {
    final isMobile = context.formFactor == FormFactor.mobile;
    return Column(
      key: const ValueKey('health'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (isMobile) ...[
          _buildAllocationBadge(context),
          kGapXl,
        ],
        _FinancialHealthBar(
          income: widget.monthlyIncome,
          expectedIncome: widget.expectedIncome,
          budget: widget.expenseBudget,
          spent: widget.expenseSpent,
          savingsBudget: widget.savingsBudget,
          savingsContributed: widget.savingsContributed,
          incomeColor: const Color(0xFF1ABC9C),
          budgetColor: const Color(0xFF9b59b6),
          spentColor: const Color(0xFFFF6F61),
          savingsColor: const Color(0xFF3498DB),
        ),
        kGapXxl,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              if (widget.expectedIncome > 0)
                _buildSummaryColumn(
                  context,
                  label: 'Expected',
                  amount: widget.expectedIncome,
                  color: const Color(0xFF1ABC9C),
                  isHatched: true,
                ),
              if (widget.monthlyIncome > 0)
                _buildSummaryColumn(
                  context,
                  label: 'Actual',
                  amount: widget.monthlyIncome,
                  color: const Color(0xFF1ABC9C),
                ),
              _buildSummaryColumn(
                context,
                label: 'Budget',
                amount: widget.expenseBudget,
                color: const Color(0xFF9b59b6),
              ),
              _buildSummaryColumn(
                context,
                label: 'Spent',
                amount: widget.expenseSpent,
                color: widget.expenseSpent > widget.expenseBudget
                    ? const Color(0xFFD32F2F)
                    : const Color(0xFFFF6F61),
              ),
              if (widget.savingsBudget > 0 || widget.savingsContributed > 0) ...[
                _buildSummaryColumn(
                  context,
                  label: 'Savings target',
                  amount: widget.savingsBudget,
                  color: const Color(0xFF3498DB),
                  isHatched: true,
                ),
                _buildSummaryColumn(
                  context,
                  label: 'Saved',
                  amount: widget.savingsContributed,
                  color: const Color(0xFF3498DB),
                ),
              ],
            ],
          ),
        ),
        kGapLg,
        Column(
          children: [
            if (widget.totalSpent > widget.totalBudget)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.trending_down, color: Colors.red[400], size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Over budget by ${CurrencyFormatter.format(widget.totalSpent - widget.totalBudget, decimalDigits: 2)}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red[200]),
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.monthlyIncome > 0 && widget.totalSpent > widget.monthlyIncome)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32F2F).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.7)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Spending exceeds actual income by ${CurrencyFormatter.format(widget.totalSpent - widget.monthlyIncome, decimalDigits: 2)}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red[200]),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDonutSubToggle() {
    return SegmentedButton<int>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 11),
        minimumSize: const Size(0, 28),
      ),
      segments: const [
        ButtonSegment(value: 0, label: Text('Budget')),
        ButtonSegment(value: 1, label: Text('Spent')),
      ],
      selected: {_donutMode},
      onSelectionChanged: (s) => setState(() => _donutMode = s.first),
    );
  }

  Widget _buildDonutContent(BuildContext context) {
    final isBudgetMode = _donutMode == 0;
    // Includes both expense and savings categories — savings commitments are
    // part of your monthly outflow and should be visible in the distribution.
    final committableCategories = widget.categories
        .where((c) => c.type == 'expense' || c.type == 'savings')
        .toList();

    // Each mode filters and sizes slices independently
    final visibleCategories = isBudgetMode
        ? committableCategories.where((c) => (widget.budgetAmounts[c.id] ?? 0.0) > 0).toList()
        : committableCategories
            .where((c) => ((widget.spending[c.id] as CategorySpending?)?.total ?? 0.0) > 0)
            .toList();

    final sections = visibleCategories.map((c) {
      final value = isBudgetMode
          ? (widget.budgetAmounts[c.id] ?? 0.0)
          : (widget.spending[c.id] as CategorySpending).total;
      final color = c.color != null ? _parseColor(c.color!) : Colors.grey;
      return PieChartSectionData(value: value, color: color, radius: 44, title: '');
    }).toList();

    final totalRef = sections.fold<double>(0.0, (s, sec) => s + sec.value);
    final centerLabel = isBudgetMode ? 'Budget' : 'Spent';
    final centerAmount = isBudgetMode ? widget.totalBudget : widget.totalSpent;
    final emptyMessage = isBudgetMode ? 'No budgets set yet.' : 'No spending recorded yet.';

    return Column(
      key: ValueKey(_donutMode),
      children: [
        if (context.formFactor != FormFactor.desktop) ...[
          _buildDonutSubToggle(),
          const SizedBox(height: 20),
        ],
        if (visibleCategories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(emptyMessage, style: const TextStyle(color: Colors.grey)),
          )
        else ...[
          SizedBox(
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    centerSpaceRadius: 52,
                    sectionsSpace: 2,
                    sections: sections,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centerLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    Text(
                      CurrencyFormatter.format(centerAmount, decimalDigits: 0),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: visibleCategories.map((c) {
              final value = isBudgetMode
                  ? (widget.budgetAmounts[c.id] ?? 0.0)
                  : (widget.spending[c.id] as CategorySpending).total;
              final pct = totalRef > 0 ? (value / totalRef * 100) : 0.0;
              final color = c.color != null ? _parseColor(c.color!) : Colors.grey;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${c.name}  ${pct.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryColumn(
    BuildContext context, {
    required String label,
    required double amount,
    required Color color,
    bool isHatched = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isHatched)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: color.withOpacity(0.5)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: CustomPaint(
                    painter: _HatchedPainter(color: color.withOpacity(0.5)),
                  ),
                ),
              )
            else
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          CurrencyFormatter.format(amount),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ─── Financial health bar ─────────────────────────────────────────────────────

class _FinancialHealthBar extends StatelessWidget {
  final double income;
  final double expectedIncome;
  /// Expense-only planned; the "Budget" marker lands here.
  final double budget;
  /// Expense-only actual; the "Spent" marker lands here.
  final double spent;
  /// Savings target for the month; rendered as a hatched teal segment
  /// stacked right after [budget] and as a "Target" marker at [budget]+[savingsBudget].
  final double savingsBudget;
  /// Savings contributed this month; rendered as a solid teal segment
  /// stacked right after [spent] and as a "Saved" marker at [spent]+[savingsContributed].
  final double savingsContributed;
  final Color incomeColor;
  final Color budgetColor;
  final Color spentColor;
  final Color savingsColor;

  const _FinancialHealthBar({
    required this.income,
    this.expectedIncome = 0,
    required this.budget,
    required this.spent,
    this.savingsBudget = 0,
    this.savingsContributed = 0,
    required this.incomeColor,
    required this.budgetColor,
    required this.spentColor,
    required this.savingsColor,
  });

  @override
  Widget build(BuildContext context) {
    final double planned = budget + savingsBudget;
    final double committed = spent + savingsContributed;
    if (income == 0 && expectedIncome == 0 && planned == 0 && committed == 0) {
      return Container(
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        final double maxVal = [income, expectedIncome, planned, committed]
            .reduce((a, b) => a > b ? a : b);
        final double scale = maxVal > 0 ? maxWidth / maxVal : 0;

        double clampW(double v) {
          final double w = v * scale;
          if (w.isNaN || w < 0) return 0;
          return w > maxWidth ? maxWidth : w;
        }

        final double incomeWidth = clampW(income);
        final double expectedWidth = clampW(expectedIncome);
        final double budgetWidth = clampW(budget);
        final double spentWidth = clampW(spent);
        final double targetWidth = clampW(planned);
        final double savedWidth = clampW(committed);
        final double savingsTargetSegmentWidth =
            (targetWidth - budgetWidth).clamp(0.0, maxWidth);
        final double savingsSegmentWidth =
            (savedWidth - spentWidth).clamp(0.0, maxWidth);

        // Compare like-with-like: expenses vs expense budget, and total
        // committed vs total planned.
        final bool overExpenseBudget = spent > budget && budget > 0;
        final bool overPlanned = committed > planned && planned > 0;
        final Color effectiveSpentColor =
            overExpenseBudget ? const Color(0xFFD32F2F) : spentColor;
        final Color effectiveSavingsColor =
            overPlanned ? const Color(0xFFD32F2F) : savingsColor;

        const double barHeight = 36.0;
        const double radius = 8.0;
        const double labelWidth = 56.0;
        const double labelRowHeight = 14.0;
        const double labelGap = 4.0;

        BorderRadius rightRadius(double width) {
          final bool fillsEnd = width >= maxWidth - 0.5;
          return BorderRadius.horizontal(
            left: const Radius.circular(radius),
            right: fillsEnd ? const Radius.circular(radius) : Radius.zero,
          );
        }

        double clampLabelLeft(double centerX) {
          final double left = centerX - labelWidth / 2;
          final double maxLeft = maxWidth - labelWidth;
          if (maxLeft <= 0) return 0;
          if (left < 0) return 0;
          if (left > maxLeft) return maxLeft;
          return left;
        }

        final double budgetLabelLeft =
            budget > 0 ? clampLabelLeft(budgetWidth) : 0;
        final double spentLabelLeft =
            spent > 0 ? clampLabelLeft(spentWidth) : 0;
        final double savedLabelLeft =
            savingsContributed > 0 ? clampLabelLeft(savedWidth) : 0;
        final double targetLabelLeft =
            savingsBudget > 0 ? clampLabelLeft(targetWidth) : 0;

        final bool bothLabels = budget > 0 && spent > 0;
        final bool labelsCollide = bothLabels &&
            (budgetLabelLeft - spentLabelLeft).abs() < labelWidth;

        // When labels collide, stack them: Spent on the upper row, Budget on
        // the lower row (closer to the bar). Otherwise both share one row.
        final double labelAreaHeight = labelsCollide
            ? labelRowHeight * 2 + labelGap
            : labelRowHeight + labelGap;

        final double budgetLabelTop = labelsCollide
            ? labelRowHeight + labelGap
            : 0;
        final double spentLabelTop = 0;
        // Saved label sits on the same row as Spent when they're far apart;
        // drops to the budget row if it would overlap spent.
        final bool savedOverlapsSpent = savingsContributed > 0 &&
            spent > 0 &&
            (savedLabelLeft - spentLabelLeft).abs() < labelWidth;
        final double savedLabelTop =
            savedOverlapsSpent ? budgetLabelTop : spentLabelTop;
        // Target label mirrors Saved — same row as Budget when far apart;
        // drops to the Spent row if it would overlap Budget.
        final bool targetOverlapsBudget = savingsBudget > 0 &&
            budget > 0 &&
            (targetLabelLeft - budgetLabelLeft).abs() < labelWidth;
        final double targetLabelTop =
            targetOverlapsBudget ? spentLabelTop : budgetLabelTop;

        return SizedBox(
          height: barHeight + labelAreaHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Spent marker label above the bar.
              if (spent > 0)
                Positioned(
                  left: spentLabelLeft,
                  top: spentLabelTop,
                  width: labelWidth,
                  child: Text(
                    'Spent',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: effectiveSpentColor,
                    ),
                  ),
                ),

              // Budget marker label above the bar.
              if (budget > 0)
                Positioned(
                  left: budgetLabelLeft,
                  top: budgetLabelTop,
                  width: labelWidth,
                  child: Text(
                    'Budget',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: budgetColor,
                    ),
                  ),
                ),

              // Saved marker label above the bar (end of the solid teal segment).
              if (savingsContributed > 0)
                Positioned(
                  left: savedLabelLeft,
                  top: savedLabelTop,
                  width: labelWidth,
                  child: Text(
                    'Saved',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: effectiveSavingsColor,
                    ),
                  ),
                ),

              // Target marker label above the bar (end of the hatched teal segment).
              if (savingsBudget > 0)
                Positioned(
                  left: targetLabelLeft,
                  top: targetLabelTop,
                  width: labelWidth,
                  child: Text(
                    'Target',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: savingsColor,
                    ),
                  ),
                ),

              // Bar body.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: barHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Track background.
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.06),
                        borderRadius: BorderRadius.circular(radius),
                      ),
                    ),

                    // Expected income — hatched fill.
                    if (expectedIncome > 0 && expectedWidth > 0)
                      SizedBox(
                        width: expectedWidth,
                        height: barHeight,
                        child: ClipRRect(
                          borderRadius: rightRadius(expectedWidth),
                          child: CustomPaint(
                            painter: _HatchedPainter(
                              color: incomeColor.withOpacity(0.45),
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),

                    // Actual income — solid fill on top of hatched.
                    if (income > 0 && incomeWidth > 0)
                      Container(
                        width: incomeWidth,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: incomeColor,
                          borderRadius: rightRadius(incomeWidth),
                        ),
                      ),

                    // Budget vertical marker.
                    if (budget > 0)
                      Positioned(
                        left: (budgetWidth - 1).clamp(0, maxWidth - 2),
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: budgetColor),
                      ),

                    // Spent vertical marker (expense spent only).
                    if (spent > 0)
                      Positioned(
                        left: (spentWidth - 1).clamp(0, maxWidth - 2),
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: effectiveSpentColor),
                      ),

                    // Savings target: hatched teal band in the TOP half of the
                    // bar, stacked right after the Budget marker. Mirrors the
                    // solid "Saved" segment below.
                    if (savingsBudget > 0 && savingsTargetSegmentWidth > 0)
                      Positioned(
                        left: budgetWidth,
                        top: 0,
                        height: barHeight * 0.45,
                        width: savingsTargetSegmentWidth,
                        child: ClipRect(
                          child: CustomPaint(
                            painter: _HatchedPainter(
                              color: savingsColor.withOpacity(0.75),
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),

                    // Savings contributed: solid teal band in the BOTTOM half
                    // of the bar, stacked right after the Spent marker.
                    if (savingsContributed > 0 && savingsSegmentWidth > 0)
                      Positioned(
                        left: spentWidth,
                        top: barHeight * 0.55,
                        height: barHeight * 0.45,
                        width: savingsSegmentWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            color: effectiveSavingsColor.withOpacity(0.85),
                            borderRadius: BorderRadius.only(
                              topRight: savedWidth >= maxWidth - 0.5
                                  ? const Radius.circular(radius)
                                  : Radius.zero,
                              bottomRight: savedWidth >= maxWidth - 0.5
                                  ? const Radius.circular(radius)
                                  : Radius.zero,
                            ),
                          ),
                        ),
                      ),

                    // Vertical markers at the end of each teal segment so the
                    // total (expense + savings) is visible at a glance.
                    if (savingsBudget > 0)
                      Positioned(
                        left: (targetWidth - 1).clamp(0, maxWidth - 2),
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: savingsColor),
                      ),
                    if (savingsContributed > 0)
                      Positioned(
                        left: (savedWidth - 1).clamp(0, maxWidth - 2),
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: effectiveSavingsColor),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HatchedPainter extends CustomPainter {
  final Color color;
  _HatchedPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const spacing = 6.0;
    for (double i = -size.height; i < size.width; i += spacing) {
      canvas.drawLine(
        Offset(i, size.height),
        Offset(i + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MonthPickerDialog extends StatefulWidget {
  final DateTime initialDate;
  const _MonthPickerDialog({super.key, required this.initialDate});

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialDate.year;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            onPressed: () => setState(() => _selectedYear--),
          ),
          Text(_selectedYear.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            onPressed: () => setState(() => _selectedYear++),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        height: 300,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.5,
          ),
          itemCount: 12,
          itemBuilder: (context, index) {
            final month = index + 1;
            final isSelected = _selectedYear == widget.initialDate.year && month == widget.initialDate.month;
            return InkWell(
              onTap: () => Navigator.pop(context, DateTime(_selectedYear, month)),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? Theme.of(context).primaryColor : Colors.grey.withOpacity(0.3),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _getMonthName(month),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}
