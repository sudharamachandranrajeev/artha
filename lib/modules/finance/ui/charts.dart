import 'dart:math' as math;

import 'package:brahma_core/brahma_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme.dart';
import '../insights/forecast.dart';
import '../portfolio/portfolio.dart';
import '../reports/reports.dart';

TextStyle _axisText(BuildContext context, Color color) =>
    TextStyle(color: color, fontSize: 11).merge(tabular);

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
  Color axis, {
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
          child: Text(left(v), style: _axisText(context, axis)),
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
            child: Text(bottom(i), style: _axisText(context, axis)),
          );
        },
      ),
    ),
  );
}

/// Dashed hairline horizontals, the reference mock's grid.
FlGridData _grid(Color track, double step) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: step,
  getDrawingHorizontalLine: (_) => FlLine(color: track, strokeWidth: 1, dashArray: const [4, 6]),
);

const _chartLeft = 56.0;
const _chartBottom = 28.0;
const _chartRight = 8.0;

/// Net worth at each month end. One series, so no legend: the card title
/// names it. The marked point carries a pill badge, as in the reference.
class NetWorthChart extends StatefulWidget {
  const NetWorthChart(this.points, this.base, {super.key});
  final List<NetWorthPoint> points;
  final String base;

  @override
  State<NetWorthChart> createState() => _NetWorthChartState();
}

class _NetWorthChartState extends State<NetWorthChart> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final scheme = Theme.of(context).colorScheme;
    final points = widget.points;
    final ys = [for (final p in points) _major(p.netWorth, widget.base)];
    final lo = math.min(0.0, ys.reduce(math.min)), hi = math.max(0.0, ys.reduce(math.max));
    final step = _niceStep(hi - lo);
    final minY = (lo / step).floor() * step;
    final maxY = math.max((hi / step).ceil() * step, step);
    final scale = math.pow(10, currencyInfo(widget.base).scale);
    final line = skin.series[0];
    final idx = (_touched ?? points.length - 1).clamp(0, points.length - 1);
    return SizedBox(
      height: 240,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotW = math.max(1.0, constraints.maxWidth - _chartLeft - _chartRight);
          final plotH = 240.0 - _chartBottom;
          final x = points.length == 1
              ? _chartLeft + plotW / 2
              : _chartLeft + (idx / (points.length - 1)) * plotW;
          final yFrac = maxY == minY ? 1.0 : ((ys[idx] - minY) / (maxY - minY)).clamp(0.0, 1.0);
          final y = (1 - yFrac) * plotH;
          return Stack(
            children: [
              LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: _grid(skin.track, step),
                  borderData: FlBorderData(show: false),
                  titlesData: _titles(
                    context,
                    skin.faint,
                    left: (v) => money((v * scale).round(), widget.base, compact: true),
                    bottom: (i) => monthLabel(points[i].date.substring(0, 7)),
                    count: points.length,
                    step: step,
                  ),
                  extraLinesData: ExtraLinesData(
                    verticalLines: [
                      VerticalLine(
                        x: idx.toDouble(),
                        color: line.withValues(alpha: 0.55),
                        strokeWidth: 1,
                        dashArray: const [4, 4],
                      ),
                    ],
                  ),
                  lineTouchData: LineTouchData(
                    touchCallback: (event, response) {
                      final spots = response?.lineBarSpots;
                      if (spots == null || spots.isEmpty) return;
                      final i = spots.first.x.round().clamp(0, points.length - 1);
                      if (i != _touched) setState(() => _touched = i);
                    },
                    getTouchedSpotIndicator: (bar, spots) => [
                      for (final _ in spots)
                        const TouchedSpotIndicatorData(
                          FlLine(color: Colors.transparent, strokeWidth: 0),
                          FlDotData(show: false),
                        ),
                    ],
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => const Color(0x00000000),
                      tooltipPadding: EdgeInsets.zero,
                      getTooltipItems: (spots) => [
                        for (final _ in spots) LineTooltipItem('', const TextStyle(fontSize: 0)),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
                      color: line,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, i) => i == idx
                            ? FlDotCirclePainter(
                                color: scheme.surface,
                                strokeWidth: 2.5,
                                strokeColor: line,
                                radius: 4.5,
                              )
                            : FlDotCirclePainter(
                                color: const Color(0x00000000),
                                strokeWidth: 0,
                                strokeColor: const Color(0x00000000),
                                radius: 0,
                              ),
                      ),
                      belowBarData: BarAreaData(show: true, color: line.withValues(alpha: 0.10)),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: (x - 30).clamp(0.0, math.max(0.0, constraints.maxWidth - 60)),
                top: (y - 36).clamp(0.0, 240.0 - 30),
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      money(points[idx].netWorth, widget.base, compact: true),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFFFFFF),
                      ).merge(tabular),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Income and spending per month side by side; two series, so a legend.
/// Expected liquid money day by day. Below zero the line turns the warning
/// colour and a solid zero line shows where the money runs out.
class ForecastChart extends StatelessWidget {
  const ForecastChart(this.forecast, this.base, {super.key});
  final CashForecast forecast;
  final String base;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final f = forecast;
    final ys = [_major(f.opening, base), for (final b in f.balances) _major(b, base)];
    final lo = math.min(0.0, ys.reduce(math.min)), hi = math.max(0.0, ys.reduce(math.max));
    final step = _niceStep(hi - lo);
    final minY = (lo / step).floor() * step;
    final maxY = math.max((hi / step).ceil() * step, step);
    final scale = math.pow(10, currencyInfo(base).scale);
    final short = lo < 0;
    final line = short ? Status.warning.color : skin.series[0];
    String day(int i) {
      final d = i == 0 ? f.today : f.dateAt(i - 1);
      return '${int.parse(d.substring(8))} ${monthLabel(d.substring(0, 7))}';
    }

    // Day labels are wider than month ones; keep the last inside the card.
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            minY: minY,
            maxY: maxY,
            gridData: _grid(skin.track, step),
            borderData: FlBorderData(show: false),
            titlesData: _titles(
              context,
              skin.faint,
              left: (v) => money((v * scale).round(), base, compact: true),
              bottom: day,
              count: ys.length,
              step: step,
            ),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                if (short)
                  HorizontalLine(y: 0, color: Status.warning.color.withValues(alpha: 0.6), strokeWidth: 1),
              ],
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${day(s.x.round())}\n${money((s.y * scale).round(), base)}',
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFFFFFF)),
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
                color: line,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: line.withValues(alpha: 0.10)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FlowsChart extends StatelessWidget {
  const FlowsChart(this.flows, this.base, {super.key});
  final List<MonthFlow> flows;
  final String base;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final scheme = Theme.of(context).colorScheme;
    final income = skin.series[0], spend = skin.series[1];
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
              gridData: _grid(skin.track, step),
              borderData: FlBorderData(show: false),
              titlesData: _titles(
                context,
                skin.faint,
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
    final muted = ArthaSkin.of(context).muted;
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
