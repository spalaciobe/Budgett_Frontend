import 'package:fl_chart/fl_chart.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/data/models/transaction_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/budget_model.dart';

class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(recentTransactionsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    
    // Get current month and year for budget
    final now = DateTime.now();
    final budgetsAsync = ref.watch(budgetsProvider((month: now.month, year: now.year)));

    return Scaffold(
      appBar: AppBar(title: const Text('Financial Analysis')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Two donut charts side by side
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                
                if (isWide) {
                  // Side by side layout for wide screens
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildSpendingSection(context, transactionsAsync, categoriesAsync),
                      ),
                      const SizedBox(width: 32),
                      Expanded(
                        child: _buildBudgetSection(context, budgetsAsync, categoriesAsync),
                      ),
                    ],
                  );
                } else {
                  // Stacked layout for narrow screens
                  return Column(
                    children: [
                      _buildSpendingSection(context, transactionsAsync, categoriesAsync),
                      const SizedBox(height: 32),
                      _buildBudgetSection(context, budgetsAsync, categoriesAsync),
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpendingSection(
    BuildContext context,
    AsyncValue<List<Transaction>> transactionsAsync,
    AsyncValue<List<Category>> categoriesAsync,
  ) {
    return Column(
      children: [
        Text('Spending by Category', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        SizedBox(
          height: 300,
          child: transactionsAsync.when(
            data: (transactions) {
              return categoriesAsync.when(
                data: (categories) => _buildSpendingPieChart(transactions, categories),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Text('Error: $e'),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Text('Error: $e'),
          ),
        ),
      ],
    );
  }

  Widget _buildBudgetSection(
    BuildContext context,
    AsyncValue<List<Budget>> budgetsAsync,
    AsyncValue<List<Category>> categoriesAsync,
  ) {
    return Column(
      children: [
        Text('Budget by Category', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        SizedBox(
          height: 300,
          child: budgetsAsync.when(
            data: (budgets) {
              return categoriesAsync.when(
                data: (categories) => _buildBudgetPieChart(budgets, categories),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Text('Error: $e'),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Text('Error: $e'),
          ),
        ),
      ],
    );
  }

  Widget _buildSpendingPieChart(List<Transaction> transactions, List<Category> categories) {
    if (transactions.isEmpty) return const Center(child: Text('No data available'));

    // Filter expenses only
    final expenses = transactions.where((t) => t.type == 'expense').toList();
    if (expenses.isEmpty) return const Center(child: Text('No expenses to analyze'));

    // Group by category
    final Map<String, double> categoryTotals = {};
    for (var t in expenses) {
      if (t.categoryId != null) {
        categoryTotals.update(t.categoryId!, (val) => val + t.amount, ifAbsent: () => t.amount);
      } else {
        categoryTotals.update('Uncategorized', (val) => val + t.amount, ifAbsent: () => t.amount);
      }
    }

    // Create sections
    final List<PieChartSectionData> sections = categoryTotals.entries.map((entry) {
      final category = categories.firstWhere(
        (c) => c.id == entry.key, 
        orElse: () => Category(id: 'unknown', name: 'Other', type: 'expense', color: '0xFF808080')
      );
      
      final color = category.color != null ? Color(int.tryParse(category.color!) ?? 0xFF808080) : Colors.grey;

      return PieChartSectionData(
        color: color,
        value: entry.value,
        title: '${category.name}\n${CurrencyFormatter.format(entry.value)}',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }

  Widget _buildBudgetPieChart(List<Budget> budgets, List<Category> categories) {
    if (budgets.isEmpty) return const Center(child: Text('No budget data available'));

    // Group by category (only expense categories)
    final Map<String, double> categoryBudgets = {};
    for (var budget in budgets) {
      if (budget.categoryId != null) {
        // Find the category to check its type
        final category = categories.firstWhere(
          (c) => c.id == budget.categoryId,
          orElse: () => Category(id: 'unknown', name: 'Other', type: 'expense', color: '0xFF808080')
        );
        
        // Only include expense categories
        if (category.type == 'expense') {
          categoryBudgets.update(
            budget.categoryId!, 
            (val) => val + budget.amount, 
            ifAbsent: () => budget.amount
          );
        }
      }
    }

    if (categoryBudgets.isEmpty) return const Center(child: Text('No budget allocations'));

    // Create sections
    final List<PieChartSectionData> sections = categoryBudgets.entries.map((entry) {
      final category = categories.firstWhere(
        (c) => c.id == entry.key, 
        orElse: () => Category(id: 'unknown', name: 'Other', type: 'expense', color: '0xFF808080')
      );
      
      final color = category.color != null ? Color(int.tryParse(category.color!) ?? 0xFF808080) : Colors.grey;

      return PieChartSectionData(
        color: color,
        value: entry.value,
        title: '${category.name}\n${CurrencyFormatter.format(entry.value)}',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }
}
