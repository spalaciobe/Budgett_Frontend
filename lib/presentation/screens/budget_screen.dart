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

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final budgetsAsync = ref.watch(budgetsProvider((month: now.month, year: now.year)));
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Budget - ${_getMonthName(now.month)} ${now.year}')),
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
                future: ref.read(financeRepositoryProvider).getMonthlyIncome(now.month, now.year),
                builder: (context, incomeSnapshot) {
                  final monthlyIncome = incomeSnapshot.data ?? 0.0;
                  // Use Expected Income as the base for allocation if set, otherwise fallback to actual income
                  final baseIncome = expectedIncome > 0 ? expectedIncome : monthlyIncome;
                  
                  final availableToAllocate = baseIncome - totalBudget;
                  final allocationPercentage = baseIncome > 0 ? (totalBudget / baseIncome * 100) : 0.0;

                  return FutureBuilder<List<Map<String, double>>>(
                    future: Future.wait([
                      ref.read(financeRepositoryProvider).getSpendingByCategory(now.month, now.year),
                      ref.read(financeRepositoryProvider).getIncomeByCategory(now.month, now.year),
                    ]),
                    builder: (context, snapshots) {
                      final spending = snapshots.data?[0] ?? {};
                      final incomeFlows = snapshots.data?[1] ?? {};
                      final totalSpent = spending.values.fold<double>(0.0, (sum, val) => sum + val);

                      return Column(
                        children: [
                          // Combined Financial Overview Card
                          Card(
                            margin: const EdgeInsets.all(16),
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Financial Health', 
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        )),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: allocationPercentage > 100 
                                              ? Colors.red.withOpacity(0.1)
                                              : Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(20),
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
                                  const SizedBox(height: 32),
                                  
                                  // Custom Horizontal Bar
                                  _FinancialHealthBar(
                                    income: monthlyIncome,
                                    expectedIncome: expectedIncome,
                                    budget: totalBudget,
                                    spent: totalSpent,
                                    incomeColor: const Color(0xFF1ABC9C).withOpacity(0.85),
                                    budgetColor: const Color(0xFF9b59b6).withOpacity(0.85),
                                    spentColor: const Color(0xFFFF6F61).withOpacity(0.85),
                                  ),
                                  
                                  const SizedBox(height: 24),

                                  // Stats Details
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF1ABC9C), shape: BoxShape.circle)),
                                              const SizedBox(width: 4),
                                              Text('Income', style: TextStyle(color: Colors.grey[200], fontSize: 12)),
                                            ],
                                          ),
                                          Text(
                                            expectedIncome > 0 
                                              ? '${CurrencyFormatter.format(monthlyIncome)} / ${CurrencyFormatter.format(expectedIncome)}'
                                              : CurrencyFormatter.format(monthlyIncome),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Row(
                                            children: [
                                              Container(width: 8, height: 8, decoration: BoxDecoration(color: const Color(0xFF9b59b6).withOpacity(0.85), shape: BoxShape.circle)),
                                              const SizedBox(width: 4),
                                              Text('Budgeted', style: TextStyle(color: Colors.grey[200], fontSize: 12)),
                                            ],
                                          ),
                                          Text(CurrencyFormatter.format(totalBudget), style: TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFF9b59b6).withOpacity(0.85), fontSize: 16)),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 8, 
                                                height: 8, 
                                                decoration: BoxDecoration(
                                                  color: totalSpent > totalBudget 
                                                    ? const Color(0xFFD32F2F) 
                                                    : const Color(0xFFFF6F61).withOpacity(0.85), 
                                                  shape: BoxShape.circle
                                                )
                                              ),
                                              const SizedBox(width: 4),
                                              Text('Spent', style: TextStyle(color: Colors.grey[200], fontSize: 12)),
                                            ],
                                          ),
                                          Text(
                                            CurrencyFormatter.format(totalSpent), 
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold, 
                                              color: totalSpent > totalBudget 
                                                ? const Color(0xFFD32F2F) 
                                                : const Color(0xFFFF6F61).withOpacity(0.85), 
                                              fontSize: 16
                                            )
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 20),
                                  
                                  // Messages / Alerts
                                  if (totalSpent > totalBudget) ...[
                                      if (totalSpent > totalBudget)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.trending_down, color: Colors.red[800], size: 16),
                                              const SizedBox(width: 8),
                                              Expanded(child: Text(
                                                'Overspending by ${CurrencyFormatter.format(totalSpent - totalBudget, decimalDigits: 2)}',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red[800]),
                                              )),
                                            ],
                                          ),
                                        ),
                                  ],
                                ],
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
                                    ? (incomeFlows[cat.id] ?? 0.0)
                                    : (spending[cat.id] ?? 0.0);
                                final budgetAmount = budget?.amount ?? 0.0;
                                return BudgetComparisonWidget(
                                  categoryName: cat.name,
                                  budgetAmount: budgetAmount,
                                  spentAmount: actualSpent,
                                  color: cat.color != null ? _parseColor(cat.color!) : null,
                                  iconName: cat.icon,
                                  isIncome: cat.type == 'income',
                                  onEditBudget: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => EditBudgetDialog(
                                        categoryId: cat.id,
                                        categoryName: cat.name,
                                        month: now.month,
                                        year: now.year,
                                        currentAmount: budget?.amount,
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
                  // Budget marker label
                  if (spent > budget)
                    Positioned(
                      left: budgetWidth,
                      bottom: 5,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: const Text(
                          'Budget',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  // Income marker label
                  if (spent > income && income > 0)
                    Positioned(
                      left: incomeWidth,
                      bottom: 5,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: const Text(
                          'Income',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  // Expected Income marker label
                  if (income > expectedIncome && expectedIncome > 0)
                    Positioned(
                      left: expectedIncomeWidth,
                      bottom: 5,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: const Text(
                          'Expected',
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
                  SizedBox(
                    width: budgetWidth,
                    height: 30,
                    child: Stack(
                      children: [
                        Container(
                          width: budgetWidth > incomeWidth && incomeWidth > 0 ? incomeWidth : budgetWidth,
                          decoration: BoxDecoration(
                            color: budgetColor,
                            borderRadius: BorderRadius.horizontal(
                              left: const Radius.circular(8),
                              right: budgetWidth <= incomeWidth ? const Radius.circular(8) : Radius.zero,
                            ),
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

                  // Spent Bar - Always full width, no clipping
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                       width: spentWidth,
                       height: 30,
                       decoration: BoxDecoration(
                         color: effectiveSpentColor,
                         borderRadius: BorderRadius.circular(8),
                       ),
                    ),
                  ),
                  
                  // Dashed line when spent > budget
                  if (spent > budget)
                     Positioned(
                       left: budgetWidth,
                       top: 0,
                       bottom: 0,
                       child: CustomPaint(
                         size: const Size(2, 30),
                         painter: _DashedLinePainter(color: Colors.white),
                       ),
                     ),

                  // Dashed line when spent > income
                  if (spent > income && income > 0)
                     Positioned(
                       left: incomeWidth,
                       top: 0,
                       bottom: 0,
                       child: CustomPaint(
                         size: const Size(2, 30),
                         painter: _DashedLinePainter(color: Colors.white),
                       ),
                     ),

                  // Dashed line for Expected Income if Actual exceeds it
                  if (income > expectedIncome && expectedIncome > 0)
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

