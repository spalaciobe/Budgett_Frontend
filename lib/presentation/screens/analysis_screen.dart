import 'package:flutter/material.dart';
import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/core/responsive.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/providers/portfolio_provider.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import 'package:budgett_frontend/presentation/widgets/portfolio_donut_chart.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  int _selectedYear = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Analysis'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.bar_chart), text: 'Cash flow'),
              Tab(icon: Icon(Icons.pie_chart_outline), text: 'Portfolio'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildCashFlowTab(),
            _buildPortfolioTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildCashFlowTab() {
    final historyAsync = ref.watch(yearlySummaryProvider(_selectedYear));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(yearlySummaryProvider(_selectedYear));
        await ref.read(yearlySummaryProvider(_selectedYear).future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kScreenPadding,
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
            kGapXl,

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
            kGapXl,
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, size: 12, color: Colors.green), SizedBox(width: 4), Text('Income'),
                SizedBox(width: 16),
                Icon(Icons.circle, size: 12, color: Colors.red), SizedBox(width: 4), Text('Expense'),
              ],
            ),
            kGapXxl,
            
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
                            const Text('Annual Summary — COP', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Income'),
                                Text(CurrencyFormatter.format(totalInc), style: const TextStyle(color: Colors.green)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Expenses'),
                                Text(CurrencyFormatter.format(totalExp), style: const TextStyle(color: Colors.red)),
                              ],
                            ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Savings Rate'),
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
                                  const Text('Annual Summary — USD', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                  const Text('Total Income USD'),
                                  Text(CurrencyFormatter.format(totalIncUsd, currency: 'USD'),
                                      style: const TextStyle(color: Colors.green)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total Expenses USD'),
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

  Widget _buildPortfolioTab() {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(consolidatedPortfolioProvider);
        ref.invalidate(accountsProvider);
        await ref.read(consolidatedPortfolioProvider.future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kScreenPadding,
        child: const _ConsolidatedPortfolioSection(),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Consolidated portfolio section
// ──────────────────────────────────────────────────────────────────────────────

class _ConsolidatedPortfolioSection extends ConsumerWidget {
  const _ConsolidatedPortfolioSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAny = ref.watch(hasAnyPortfolioAccountProvider);
    if (!hasAny) return const _PortfolioEmptyState();

    final portfolioAsync = ref.watch(consolidatedPortfolioProvider);

    return portfolioAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Error loading portfolio: $e'),
      ),
      data: (p) {
        if (p.isEmpty) return const _PortfolioEmptyState();
        return _PortfolioContent(portfolio: p);
      },
    );
  }
}

class _PortfolioEmptyState extends StatelessWidget {
  const _PortfolioEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.pie_chart_outline,
            size: 48,
            color: theme.colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No positions to show',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add FIC, crypto or stock investment accounts\nto see your consolidated portfolio here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioContent extends StatelessWidget {
  final ConsolidatedPortfolio portfolio;

  const _PortfolioContent({required this.portfolio});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = context.formFactor != FormFactor.mobile;

    final totalPnl = portfolio.totalPnl;
    final pnlPositive = totalPnl >= 0;
    final pnlColor =
        pnlPositive ? Colors.green.shade600 : theme.colorScheme.error;

    final positionsCard = _buildPositionsCard(context);
    final accountsCard = _buildAccountsCard(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.pie_chart_outline, size: 20),
            const SizedBox(width: 8),
            Text(
              'Consolidated portfolio',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (portfolio.hasFxConversion) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'USD holdings converted to COP using the current TRM',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('≈', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Summary card: total + P&L
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total value',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyFormatter.format(
                          portfolio.totalMarketValueCop,
                        ),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (portfolio.totalCostBasisCop > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'P&L',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                      const SizedBox(height: 2),
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
                            '${pnlPositive ? '+' : ''}${CurrencyFormatter.format(totalPnl)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: pnlColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${pnlPositive ? '+' : ''}${portfolio.totalPnlPct.toStringAsFixed(2)}%',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: pnlColor),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Two pie charts
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: positionsCard),
              const SizedBox(width: 12),
              Expanded(child: accountsCard),
            ],
          )
        else
          Column(
            children: [
              positionsCard,
              const SizedBox(height: 12),
              accountsCard,
            ],
          ),
      ],
    );
  }

  Widget _buildPositionsCard(BuildContext context) {
    final theme = Theme.of(context);

    final slices = <PortfolioSlice>[];
    for (var i = 0; i < portfolio.positions.length; i++) {
      final p = portfolio.positions[i];
      final pnlLabel = p.costBasisCop == 0
          ? null
          : '${p.pnlPct >= 0 ? '+' : ''}${p.pnlPct.toStringAsFixed(1)}%';
      slices.add(PortfolioSlice(
        label: p.displayName,
        value: p.marketValueCop,
        color: PortfolioPalette.colorFor(i),
        trailing: pnlLabel,
      ));
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'By position',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            PortfolioDonutChart(
              slices: slices,
              centerLabel: 'Positions',
              centerValue: CurrencyFormatter.format(
                portfolio.totalMarketValueCop,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountsCard(BuildContext context) {
    final theme = Theme.of(context);

    final slices = <PortfolioSlice>[];
    for (var i = 0; i < portfolio.byAccount.length; i++) {
      final a = portfolio.byAccount[i];
      slices.add(PortfolioSlice(
        label: a.accountName,
        value: a.marketValueCop,
        color: PortfolioPalette.colorFor(i),
      ));
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'By account',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            PortfolioDonutChart(
              slices: slices,
              centerLabel: 'Accounts',
              centerValue: CurrencyFormatter.format(
                portfolio.totalMarketValueCop,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
