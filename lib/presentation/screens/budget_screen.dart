import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';
import 'package:budgett_frontend/presentation/widgets/create_category_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/edit_budget_dialog.dart';
import 'package:budgett_frontend/presentation/widgets/budget_comparison_widget.dart';
import 'package:budgett_frontend/presentation/widgets/edit_category_dialog.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:budgett_frontend/data/models/category_spending.dart';

final budgetDateProvider = StateProvider.autoDispose<DateTime>((ref) => DateTime.now());

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(budgetDateProvider);
    final budgetsAsync = ref.watch(budgetsProvider((month: selectedDate.month, year: selectedDate.year)));
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      // Drawer is handled by MainScaffold
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
            tooltip: 'Copiar del mes anterior',
            onPressed: () async {
              final prevMonth = selectedDate.month == 1 ? 12 : selectedDate.month - 1;
              final prevYear = selectedDate.month == 1 ? selectedDate.year - 1 : selectedDate.year;
              final prevMonthName = _getMonthName(prevMonth);
              final currMonthName = _getMonthName(selectedDate.month);
              final hasCurrent = budgetsAsync.valueOrNull?.isNotEmpty ?? false;

              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Copiar presupuesto'),
                  content: Text(
                    hasCurrent
                        ? 'Esto reemplazará los presupuestos de $currMonthName ${selectedDate.year} con los de $prevMonthName $prevYear. ¿Continuar?'
                        : '¿Copiar los presupuestos de $prevMonthName $prevYear a $currMonthName ${selectedDate.year}?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Copiar'),
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
                    SnackBar(content: Text('No hay presupuestos en $prevMonthName $prevYear para copiar.')),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(content: Text('$count presupuesto${count == 1 ? '' : 's'} copiado${count == 1 ? '' : 's'} de $prevMonthName $prevYear.')),
                  );
                }
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
          ),
        ],
      ),
      body: budgetsAsync.when(
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
                  if (category?.type == 'income') {
                    return sum;
                  }
                  return sum + budget.amount;
                },
              );

              final expectedIncome = budgets.fold<double>(
                0.0, 
                (sum, budget) {
                   final category = categoryMap[budget.categoryId];
                   if (category?.type == 'income') {
                     return sum + budget.amount;
                   }
                   return sum;
                },
              );

              return FutureBuilder<double>(
                future: ref.read(financeRepositoryProvider).getMonthlyIncome(selectedDate.month, selectedDate.year),
                builder: (context, incomeSnapshot) {
                  final monthlyIncome = incomeSnapshot.data ?? 0.0;
                  // Use Expected Income as the base for allocation if set, otherwise fallback to actual income
                  final baseIncome = expectedIncome > 0 ? expectedIncome : monthlyIncome;
                  
                  final availableToAllocate = baseIncome - totalBudget;
                  final allocationPercentage = baseIncome > 0 ? (totalBudget / baseIncome * 100) : 0.0;
                  
                  // Using dynamic temporarily to fix build error
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: Future.wait([
                      ref.read(financeRepositoryProvider).getSpendingByCategory(selectedDate.month, selectedDate.year),
                      ref.read(financeRepositoryProvider).getIncomeByCategory(selectedDate.month, selectedDate.year),
                    ]),
                    builder: (context, snapshots) {
                      final spending = snapshots.data?[0] ?? {};
                      final incomeFlows = snapshots.data?[1] ?? {};
                      
                      // Calculate total spent
                      final totalSpent = spending.values.fold<double>(0.0, (sum, val) => sum + (val as CategorySpending).total);

                      return Column(
                        children: [
                          Card(
                            margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Financial Health', 
                                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                            letterSpacing: 0.5,
                                          )),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: allocationPercentage > 100 
                                                ? Colors.red.withOpacity(0.1)
                                                : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: allocationPercentage > 100 
                                                  ? Colors.red.withOpacity(0.2)
                                                  : Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                            )
                                          ),
                                        child: Text(
                                          '${allocationPercentage.toStringAsFixed(1)}% Allocated - ${availableToAllocate > 0 ? 'Remaining: ${CurrencyFormatter.format(availableToAllocate, decimalDigits: 2)}' : 'Over: ${CurrencyFormatter.format(availableToAllocate.abs(), decimalDigits: 2)}'}',
                                          style: TextStyle(
                                            color: allocationPercentage > 100 
                                                ? Colors.red 
                                                : Theme.of(context).colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  
                                  // Custom Horizontal Bar
                                  _FinancialHealthBar(
                                    income: monthlyIncome,
                                    expectedIncome: expectedIncome,
                                    budget: totalBudget,
                                    spent: totalSpent,
                                    incomeColor: const Color(0xFF1ABC9C),
                                    budgetColor: const Color(0xFF9b59b6),
                                    spentColor: const Color(0xFFFF6F61),
                                  ),
                                  
                                  const SizedBox(height: 16),


                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          if (expectedIncome > 0)
                                            _buildSummaryColumn(
                                              context,
                                              label: 'Expected',
                                              amount: expectedIncome,
                                              color: const Color(0xFF1ABC9C),
                                              isHatched: true,
                                            ),
                                          if (monthlyIncome > 0)
                                            _buildSummaryColumn(
                                              context,
                                              label: 'Actual',
                                              amount: monthlyIncome,
                                              color: const Color(0xFF1ABC9C),
                                            ),
                                          _buildSummaryColumn(
                                            context,
                                            label: 'Budget',
                                            amount: totalBudget,
                                            color: const Color(0xFF9b59b6),
                                          ),
                                          _buildSummaryColumn(
                                            context,
                                            label: 'Spent',
                                            amount: totalSpent,
                                            color: totalSpent > totalBudget 
                                                ? const Color(0xFFD32F2F) 
                                                : const Color(0xFFFF6F61),
                                          ),
                                        ],
                                      ),
                                    ),
                                  
                                  const SizedBox(height: 12),
                                  
                                  // Messages / Alerts
                                  Column(
                                    children: [
                                      if (totalSpent > totalBudget)
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
                                              Expanded(child: Text(
                                                'Over budget by ${CurrencyFormatter.format(totalSpent - totalBudget, decimalDigits: 2)}',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red[200]),
                                              )),
                                            ],
                                          ),
                                        ),
                                      if (monthlyIncome > 0 && totalSpent > monthlyIncome)
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
                                              Expanded(child: Text(
                                                'Spending exceeds actual income by ${CurrencyFormatter.format(totalSpent - monthlyIncome, decimalDigits: 2)}',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red[200]),
                                              )),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              ),
                            ),
                          ),

                          // Categories List
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: categories.length,
                              itemBuilder: (context, index) {
                                final cat = categories[index];
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
                                  color: cat.color != null ? _parseColor(cat.color!) : null,
                                  iconName: cat.icon,
                                  isIncome: cat.type == 'income',
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
                                      builder: (context) => EditCategoryDialog(
                                        category: cat,
                                      ),
                                    );
                                  },
                                );
                              },
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[month - 1];
  }

  Color _parseColor(String colorStr) {
    try {
      return Color(int.parse(colorStr));
    } catch (_) {
      return Colors.grey;
    }
  }

  Widget _buildSummaryColumn(BuildContext context, {
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
            color: color, // Use the color for the amount to link it visually
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _FinancialHealthBar extends StatelessWidget {
  final double income;
  final double expectedIncome;
  final double budget;
  final double spent;
  final Color incomeColor;
  final Color budgetColor;
  final Color spentColor;

  const _FinancialHealthBar({
    required this.income,
    this.expectedIncome = 0,
    required this.budget,
    required this.spent,
    required this.incomeColor,
    required this.budgetColor,
    required this.spentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (income == 0 && budget == 0 && spent == 0) {
      return Container(
        height: 30,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        // The scale is determined by the maximum of the three values. 
        final double maxVal = [income, expectedIncome, budget, spent].reduce((a, b) => a > b ? a : b);
        final double scale = maxVal > 0 ? maxWidth / maxVal : 0;

        final double incomeWidth = income * scale;
        final double expectedIncomeWidth = expectedIncome * scale;
        final double budgetWidth = budget * scale;
        final double spentWidth = spent * scale;
        
        // Determine if spent exceeds budget (use stronger red)
        final Color effectiveSpentColor = spent > budget ? const Color(0xFFD32F2F) : spentColor;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Labels positioned above the bar
            SizedBox(
              height: 20,
              child: Stack(
                children: [
                  // Budget marker label - only when overspending
                  if (spent > budget && budget > 0)
                    Positioned(
                      left: budgetWidth > maxWidth - 40 ? null : budgetWidth,
                      right: budgetWidth > maxWidth - 40 ? 0 : null,
                      bottom: 5,
                      child: FractionalTranslation(
                        translation: Offset(budgetWidth > maxWidth - 40 ? 0 : -0.5, 0),
                        child: const Text(
                          'Budget',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  // Income marker label - only if income is shown and spent exceeds it
                  if (income > 0 && spent > income)
                    Positioned(
                      left: incomeWidth > maxWidth - 40 ? null : incomeWidth,
                      right: incomeWidth > maxWidth - 40 ? 0 : null,
                      bottom: 5,
                      child: FractionalTranslation(
                        translation: Offset(incomeWidth > maxWidth - 40 ? 0 : -0.5, 0),
                        child: const Text(
                          'Income',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  // Expected Income marker label - only if both are shown and actual exceeds expected
                  if (expectedIncome > 0 && income > 0 && income > expectedIncome)
                    Positioned(
                      left: expectedIncomeWidth,
                      bottom: 5,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: const Text(
                          'Expected income',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // The bar itself
            SizedBox(
              height: 30,
              width: maxWidth,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // 1. Actual Income (The Real Limit)
                  if (income > 0)
                    Container(
                      width: incomeWidth,
                      height: 30,
                      decoration: BoxDecoration(
                        color: incomeColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: incomeColor),
                      ),
                    ),

                  // 0. Expected Income (Planner/Target) - Rendered on top of Actual
                  if (expectedIncome > 0)
                    Container(
                      width: expectedIncomeWidth,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: incomeColor.withOpacity(0.5), 
                          style: BorderStyle.solid, 
                          width: 1.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CustomPaint(
                          painter: _HatchedPainter(color: incomeColor.withOpacity(0.3)),
                          size: Size.infinite,
                        ),
                      ),
                    ),

                  // Budget Bar
                  if (budget > 0)
                    SizedBox(
                      width: budgetWidth,
                      height: 30,
                      child: Stack(
                        children: [
                          Container(
                            width: budgetWidth > incomeWidth && incomeWidth > 0 ? incomeWidth : budgetWidth,
                            decoration: BoxDecoration(
                              color: budgetColor,
                              borderRadius: (incomeWidth == 0 || budgetWidth <= incomeWidth)
                                  ? BorderRadius.circular(8)
                                  : const BorderRadius.horizontal(left: Radius.circular(8)),
                            ),
                          ),
                          if (budgetWidth > incomeWidth && incomeWidth > 0)
                            Positioned(
                              left: incomeWidth,
                              width: budgetWidth - incomeWidth,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                   color: budgetColor.withOpacity(0.1),
                                   borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                                ),
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                                  child: CustomPaint(
                                    painter: _HatchedPainter(color: budgetColor),
                                    size: Size.infinite,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Spent Bar - Always in front, always rounded
                  if (spent > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                         width: spentWidth,
                         decoration: BoxDecoration(
                           color: effectiveSpentColor,
                           borderRadius: BorderRadius.circular(8),
                         ),
                      ),
                    ),
                  
                  // Dashed line for Budget limit - only when overspending
                  if (spent > budget && budget > 0)
                     Positioned(
                       left: budgetWidth,
                       top: 0,
                       bottom: 0,
                       child: CustomPaint(
                         size: const Size(2, 30),
                         painter: _DashedLinePainter(color: Colors.white),
                       ),
                     ),

                  // Dashed line when spent > income - only if income is shown
                  if (income > 0 && spent > income)
                     Positioned(
                       left: incomeWidth,
                       top: 0,
                       bottom: 0,
                       child: CustomPaint(
                         size: const Size(2, 30),
                         painter: _DashedLinePainter(color: Colors.white),
                       ),
                     ),

                  // Dashed line for Expected Income if Actual exceeds it - only if both are shown
                  if (expectedIncome > 0 && income > 0 && income > expectedIncome)
                     Positioned(
                       left: expectedIncomeWidth,
                       top: 0,
                       bottom: 0,
                       child: CustomPaint(
                         size: const Size(2, 30),
                         painter: _DashedLinePainter(color: Colors.white),
                       ),
                     ),
                ],
              ),
            ),
          ],
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
    // Draw diagonal lines
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

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
      
    final dashHeight = 3.0;
    final dashSpace = 2.0;
    double startY = 0;
    
    while (startY < size.height) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashHeight), paint);
      startY += dashHeight + dashSpace;
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[month - 1];
  }
}

