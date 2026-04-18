import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// A single slice in a portfolio donut chart.
class PortfolioSlice {
  final String label;
  final double value;
  final Color color;
  final String? trailing;

  const PortfolioSlice({
    required this.label,
    required this.value,
    required this.color,
    this.trailing,
  });
}

/// Donut chart with a centered total and a labeled legend underneath.
class PortfolioDonutChart extends StatelessWidget {
  final List<PortfolioSlice> slices;
  final String centerLabel;
  final String centerValue;
  final double chartHeight;

  const PortfolioDonutChart({
    super.key,
    required this.slices,
    required this.centerLabel,
    required this.centerValue,
    this.chartHeight = 180,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold<double>(0, (s, x) => s + x.value);

    if (total <= 0 || slices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No data to show',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ),
      );
    }

    final sections = slices
        .map((s) => PieChartSectionData(
              value: s.value,
              color: s.color,
              radius: 42,
              title: '',
            ))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: chartHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 56,
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
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    centerValue,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Column(
          children: slices.map((s) {
            final pct = total > 0 ? (s.value / total * 100) : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.label,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (s.trailing != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      s.trailing!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    '${pct.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Deterministic color palette for portfolio slices.
class PortfolioPalette {
  static const List<Color> colors = [
    Color(0xFF4F46E5),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
    Color(0xFF84CC16),
    Color(0xFF06B6D4),
    Color(0xFFA855F7),
  ];

  static Color colorFor(int index) => colors[index % colors.length];
}
