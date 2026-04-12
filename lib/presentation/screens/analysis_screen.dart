import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';

import 'package:budgett_frontend/presentation/widgets/app_drawer.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  int _selectedYear = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(yearlySummaryProvider(_selectedYear));

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(title: const Text('Analysis')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Year Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 16),
                  onPressed: () => setState(() => _selectedYear--),
                ),
                Text('$_selectedYear', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 16),
                  onPressed: () => setState(() => _selectedYear++),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Chart
            SizedBox(
              height: 300,
              child: historyAsync.when(
                data: (data) {
                  if (data.isEmpty) return const Center(child: Text('No data'));
                  
                  // Calculate max for Y axis
                  double maxY = 0;
                  for (var m in data) {
                    if (m['income'] > maxY) maxY = m['income'];
                    if (m['expense'] > maxY) maxY = m['expense'];
                  }
                  if (maxY == 0) maxY = 100;

                  return BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY * 1.2,
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              const months = ['J','F','M','A','M','J','J','A','S','O','N','D'];
                              if (value >= 1 && value <= 12) {
                                return Text(months[value.toInt() - 1], style: const TextStyle(fontSize: 10));
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barGroups: data.map((d) {
                        return BarChartGroupData(
                          x: d['month'],
                          barRods: [
                            BarChartRodData(
                              toY: (d['income'] as num).toDouble(),
                              color: Colors.green,
                              width: 8,
                            ),
                            BarChartRodData(
                              toY: (d['expense'] as num).toDouble(),
                              color: Colors.red,
                              width: 8,
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e,s) => Center(child: Text('Error: $e')),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, size: 12, color: Colors.green), SizedBox(width: 4), Text('Income'),
                SizedBox(width: 16),
                Icon(Icons.circle, size: 12, color: Colors.red), SizedBox(width: 4), Text('Expense'),
              ],
            ),
            const SizedBox(height: 32),
            
            // Savings Rate Table
            historyAsync.when(
              data: (data) {
                double totalInc = 0;
                double totalExp = 0;
                double totalIncUsd = 0;
                double totalExpUsd = 0;
                for (var d in data) {
                  totalInc += (d['income'] as num?)?.toDouble() ?? 0.0;
                  totalExp += (d['expense'] as num?)?.toDouble() ?? 0.0;
                  totalIncUsd += (d['income_usd'] as num?)?.toDouble() ?? 0.0;
                  totalExpUsd += (d['expense_usd'] as num?)?.toDouble() ?? 0.0;
                }
                final rate = totalInc > 0 ? ((totalInc - totalExp) / totalInc * 100) : 0.0;
                final hasUsd = totalIncUsd > 0 || totalExpUsd > 0;

                return Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text('Resumen anual — COP', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total ingresos'),
                                Text(CurrencyFormatter.format(totalInc), style: const TextStyle(color: Colors.green)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total gastos'),
                                Text(CurrencyFormatter.format(totalExp), style: const TextStyle(color: Colors.red)),
                              ],
                            ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Tasa de ahorro'),
                                Text('${rate.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (hasUsd) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Text('Resumen anual — USD', style: TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text('USD',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
                                        )),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total ingresos USD'),
                                  Text(CurrencyFormatter.format(totalIncUsd, currency: 'USD'),
                                      style: const TextStyle(color: Colors.green)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total gastos USD'),
                                  Text(CurrencyFormatter.format(totalExpUsd, currency: 'USD'),
                                      style: const TextStyle(color: Colors.red)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const SizedBox(),
              error: (_,__) => const SizedBox(),
            ),
          ],
        ),
      ),
    );
  }
}
