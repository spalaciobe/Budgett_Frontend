import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../providers/portfolio_provider.dart';
import '../utils/currency_formatter.dart';

/// A line chart of a total value over time (e.g. the summed value of every
/// position in an account or the whole portfolio). Reused by the investment
/// detail "All assets" view and the Analysis → Portfolio tab.
class PortfolioValueChart extends StatelessWidget {
  final List<PortfolioValuePoint> points;
  final String currency;
  final double height;

  /// Buy-date markers (date + what was bought) shown as vertical lines + chips.
  /// Mapped to the nearest point on the series.
  final List<PortfolioValueMarker> markers;

  const PortfolioValueChart({
    super.key,
    required this.points,
    this.currency = 'COP',
    this.height = 260,
    this.markers = const [],
  });

  /// Index of the first point on/after [date], clamped to the series bounds.
  int? _eventIndex(DateTime date) {
    if (points.isEmpty) return null;
    final target = DateTime(date.year, date.month, date.day);
    for (var i = 0; i < points.length; i++) {
      final d = points[i].date;
      final day = DateTime(d.year, d.month, d.day);
      if (!day.isBefore(target)) return i;
    }
    return points.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No history yet.')),
      );
    }

    final values = points.map((p) => p.value).toList();
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final padding =
        ((maxValue - minValue).abs() * 0.12).clamp(1.0, double.infinity);
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), values[i]),
    ];

    // One vertical line per unique buy day; chips keep per-purchase detail.
    final markerDays = <DateTime>{
      for (final m in markers) DateTime(m.date.year, m.date.month, m.date.day),
    }.toList()
      ..sort();
    final verticalLines = <VerticalLine>[
      for (final day in markerDays)
        if (_eventIndex(day) != null)
          VerticalLine(
            x: _eventIndex(day)!.toDouble(),
            color: theme.colorScheme.tertiary,
            strokeWidth: 1.4,
            dashArray: const [5, 4],
          ),
    ];
    final sortedMarkers = [...markers]
      ..sort((a, b) => a.date.compareTo(b.date));

    final chartBox = SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: minValue - padding,
          maxY: maxValue + padding,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.dividerColor.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: theme.dividerColor),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 76,
                getTitlesWidget: (value, meta) => Text(
                  CurrencyFormatter.compact(value, currency: currency),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: points.length <= 2
                    ? 1
                    : ((points.length - 1) / 2).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  final d = points[index].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${d.month}/${d.day}',
                      style: theme.textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) => touched.map((spot) {
                final index = spot.x.round();
                final d = points[index].date;
                final date =
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                return LineTooltipItem(
                  '$date\n${CurrencyFormatter.format(spot.y, currency: currency)}',
                  theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                  ),
                );
              }).toList(),
            ),
          ),
          extraLinesData: ExtraLinesData(verticalLines: verticalLines),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: points.length > 2,
              barWidth: 3,
              color: theme.colorScheme.primary,
              belowBarData: BarAreaData(
                show: true,
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
              ),
              dotData: FlDotData(show: points.length <= 12),
            ),
          ],
        ),
      ),
    );

    if (sortedMarkers.isEmpty) return chartBox;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chartBox,
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: sortedMarkers.map((m) {
            final d = m.date;
            final dateStr =
                '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            final text = m.label.isEmpty ? dateStr : '${m.label} · $dateStr';
            return Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.add_shopping_cart, size: 16),
              label: Text(text),
            );
          }).toList(),
        ),
      ],
    );
  }
}
