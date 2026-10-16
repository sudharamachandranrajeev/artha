import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/money/currencies.dart';
import '../../../ui/format.dart';
import '../../../ui/theme.dart';
import '../../../ui/widgets.dart';
import '../portfolio/portfolio.dart';
import '../reports/reports.dart';

TextStyle _axisText(BuildContext context, ChartColors c) =>
    TextStyle(color: c.axis, fontSize: 11).merge(tabular);

double _major(int minor, String code) => minor / math.pow(10, currencyInfo(code).scale);

/// Step that gives about four grid lines, rounded to 1, 2 or 5 x 10^n.
double _niceStep(double range) {
  if (range <= 0) return 1;
  final raw = range / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / mag;
  return (f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10))) * mag;
}

FlTitlesData _titles(
  BuildContext context,
  ChartColors c, {
  required String Function(double) left,
  required String Function(int) bottom,
  required int count,
  required double step,
}) {
  final every = math.max(1, (count / 6).ceil());
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 56,
        interval: step,
        getTitlesWidget: (v, meta) => SideTitleWidget(
          meta: meta,
          child: Text(left(v), style: _axisText(context, c)),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 28,
        interval: 1,
        getTitlesWidget: (v, meta) {
          final i = v.round();
          if (i != v || i < 0 || i >= count || (count - 1 - i) % every != 0) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            child: Text(bottom(i), style: _axisText(context, c)),
          );
        },
      ),
    ),
  );
}

/// Net worth at each month end. One series, so no legend: the card title
/// names it.
class NetWorthChart extends StatelessWidget {
  const NetWorthChart(this.points, this.base, {super.key});
  final List<NetWorthPoint> points;
  final String base;

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ys = [for (final p in points) _major(p.netWorth, base)];
    final lo = math.min(0.0, ys.reduce(math.min)), hi = math.max(0.0, ys.reduce(math.max));
    final step = _niceStep(hi - lo);
    final scale = math.pow(10, currencyInfo(base).scale);
    final line = c.series[0];
    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: (lo / step).floor() * step,
          maxY: math.max((hi / step).ceil() * step, step),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: step,
            getDrawingHorizontalLine: (_) => FlLine(color: c.grid, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: _titles(
            context,
            c,
            left: (v) => money((v * scale).round(), base, compact: true),
            bottom: (i) => monthLabel(points[i].date.substring(0, 7)),
            count: points.length,
            step: step,
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${niceDate(points[s.x.round()].date)}\n'
                    '${money(points[s.x.round()].netWorth, base)}',
                    TextStyle(color: scheme.onInverseSurface).merge(tabular),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
              color: line,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(show: points.length <= 2),
              belowBarData: BarAreaData(show: true, color: line.withValues(alpha: 0.10)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Income and spending per month side by side; two series, so a legend.
class FlowsChart extends StatelessWidget {
  const FlowsChart(this.flows, this.base, {super.key});
  final List<MonthFlow> flows;
  final String base;

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final income = c.series[0], spend = c.series[1];
    final hi = flows.fold(
      0.0,
      (m, f) => math.max(m, math.max(_major(f.income, base), _major(f.expenses, base))),
    );
    final step = _niceStep(hi);
    final scale = math.pow(10, currencyInfo(base).scale);
    final width = flows.length > 8 ? 7.0 : 12.0;
    BarChartRodData rod(double y, Color color) => BarChartRodData(
      toY: y,
      color: color,
      width: width,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 16, children: [_LegendItem(income, 'Income'), _LegendItem(spend, 'Spending')]),
        const SizedBox(height: 12),
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              maxY: math.max((hi / step).ceil() * step, step),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) => FlLine(color: c.grid, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: _titles(
                context,
                c,
                left: (v) => money((v * scale).round(), base, compact: true),
                bottom: (i) => monthLabel(flows[i].month),
                count: flows.length,
                step: step,
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => scheme.inverseSurface,
                  getTooltipItem: (group, _, rod, rodIndex) {
                    final f = flows[group.x];
                    return BarTooltipItem(
                      rodIndex == 0
                          ? '${monthLabel(f.month, year: true)}\nIncome ${money(f.income, base)}'
                          : 'Spending ${money(f.expenses, base)}\n'
                                'Net ${money(f.net, base, signed: true)}',
                      TextStyle(color: scheme.onInverseSurface, fontSize: 12).merge(tabular),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < flows.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      rod(_major(flows[i].income, base), income),
                      rod(_major(flows[i].expenses, base), spend),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// Share of each asset class as one stacked bar, with a legend table below
/// that carries the names and numbers (identity never by colour alone).
class AllocationBar extends StatelessWidget {
  const AllocationBar(this.byClass, this.base, {super.key, this.targets = const {}});
  final Map<String, int> byClass;
  final String base;

  /// Target basis points per class, shown in the legend when set.
  final Map<String, int> targets;

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.of(context);
    final surface = Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface;
    final total = byClass.values.fold(0, (s, v) => s + v);
    final classes = [
      for (final k in ChartColors.classOrder)
        if ((byClass[k] ?? 0) > 0 || (targets[k] ?? 0) > 0) k,
    ];
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 20,
              child: Row(
                children: [
                  for (final k in classes)
                    if ((byClass[k] ?? 0) > 0)
                      Expanded(
                        flex: math.max(1, (byClass[k]! * 1000 / total).round()),
                        child: Tooltip(
                          message: '${assetClasses[k]}: ${percent(byClass[k]! / total)}',
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.forClass(k),
                              border: Border(right: BorderSide(color: surface, width: 2)),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        for (final k in classes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: c.forClass(k), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(assetClasses[k] ?? k)),
                Text(total > 0 ? percent((byClass[k] ?? 0) / total) : '–', style: tabular),
                if (targets.isNotEmpty)
                  SizedBox(
                    width: 96,
                    child: Text(
                      'target ${basisPoints(targets[k] ?? 0)}',
                      textAlign: TextAlign.end,
                      style: tabular.copyWith(color: muted, fontSize: 12),
                    ),
                  ),
                SizedBox(
                  width: 110,
                  child: Text(
                    money(byClass[k] ?? 0, base),
                    textAlign: TextAlign.end,
                    style: tabular.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
