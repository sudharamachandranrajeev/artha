import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../insights/catalogue.dart' show ukTaxYearStart;
import '../reports/reports.dart';
import 'common.dart';
import 'entry_editor.dart';

final _incomeProvider = FutureProvider.family<IncomeStatement, ({String from, String to})>((ref, p) async {
  final r = await ref.watch(reportsProvider.future);
  return r.incomeStatement(p.from, p.to);
});

final _trialProvider = FutureProvider<TrialBalance>((ref) async {
  final r = await ref.watch(reportsProvider.future);
  return r.trialBalance(ref.watch(todayProvider));
});

/// Periods the income statement offers, as (label, from, to).
List<(String, String, String)> _periods(String day) {
  final taxStart = ukTaxYearStart(day);
  return [
    ('This month', monthStart(day), day),
    ('Last month', monthStart(addMonths(monthStart(day), -1)), addDays(monthStart(day), -1)),
    ('Year to date', '${day.substring(0, 4)}-01-01', day),
    ('UK tax year', taxStart, day),
    ('Last 12 months', addDays(addMonths(day, -12), 1), day),
  ];
}

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  int _period = 0;

  @override
  Widget build(BuildContext context) {
    final base = ref.watch(setupProvider).value ?? 'GBP';
    Widget tab(List<Widget> children) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        Readable(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [const HintBanner('page.reports'), ...children],
          ),
        ),
      ],
    );
    return DefaultTabController(
      length: 4,
      child: PageScaffold(
        title: 'Reports',
        bottom: const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Balance sheet'),
            Tab(text: 'Income statement'),
            Tab(text: 'Trial balance'),
            Tab(text: 'Checks'),
          ],
        ),
        body: TabBarView(
          children: [
            tab([_balanceSheet(base)]),
            tab([_incomeStatement(base)]),
            tab([_trialBalance()]),
            tab([_checks()]),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int amount, String cur, {bool bold = false, String? sub, VoidCallback? onTap}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.w600) : null;
    return ListTile(
      visualDensity: VisualDensity.compact,
      onTap: onTap,
      title: Text(label, style: style),
      subtitle: sub == null ? null : Text(sub),
      trailing: Text(money(amount, cur), style: tabular.merge(style)),
    );
  }

  Widget _balanceSheet(String base) => AsyncView(
    ref.watch(dashboardProvider),
    onRetry: () => ref.invalidate(reportsProvider),
    builder: (d) {
      final s = d.sheet;
      final commodities = ref.watch(commoditiesProvider).value ?? const {};
      String? sub(BalanceLine l) => l.account.commodityId == base || l.baseValue != null
          ? null
          : 'No rate for ${codesOf(commodities, [l.account.commodityId])}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('As at ${niceDate(s.asOf)}, in $base', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Assets',
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                for (final l in s.assets) _row(l.account.name, l.baseValue ?? 0, base, sub: sub(l)),
                const Divider(),
                _row('Total assets', s.totalAssets, base, bold: true),
              ],
            ),
          ),
          SectionCard(
            title: 'Liabilities',
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                for (final l in s.liabilities) _row(l.account.name, -(l.baseValue ?? 0), base, sub: sub(l)),
                const Divider(),
                _row('Total liabilities', s.totalLiabilities, base, bold: true),
              ],
            ),
          ),
          SectionCard(
            title: 'Equity',
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                _row('Opening balances', s.contributed, base),
                _row('Retained earnings', s.earnings, base, sub: 'All income less all spending'),
                _row('Revaluation', s.revaluation, base, sub: 'Exchange-rate and market moves'),
                const Divider(),
                _row('Net worth', s.netWorth, base, bold: true),
              ],
            ),
          ),
          if (s.missingRates.isNotEmpty)
            StatusLabel(
              Status.warning,
              'Left out for want of a rate or price: ${codesOf(commodities, s.missingRates)}',
            ),
        ],
      );
    },
  );

  Widget _incomeStatement(String base) {
    final periods = _periods(ref.watch(todayProvider));
    final (_, from, to) = periods[_period];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Hint(
          'reports.period',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < periods.length; i++)
                ChoiceChip(
                  label: Text(periods[i].$1),
                  selected: _period == i,
                  onSelected: (_) => setState(() => _period = i),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AsyncView(
          ref.watch(_incomeProvider((from: from, to: to))),
          builder: (s) {
            Widget lines(String title, List<PnlLine> ls, int total) => SectionCard(
              title: title,
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  if (ls.isEmpty) const ListTile(dense: true, title: Text('None')),
                  for (final l in ls)
                    _row(l.account.name, l.amount, base, sub: total > 0 ? percent(l.amount / total) : null),
                  const Divider(),
                  _row('Total', total, base, bold: true),
                ],
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${niceDate(s.from)} – ${niceDate(s.to)}, in $base',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                lines('Income', s.income, s.totalIncome),
                lines('Spending', s.expenses, s.totalExpenses),
                Card(
                  child: ListTile(
                    title: const Text('Net income', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: s.totalIncome > 0
                        ? Text('Saved ${percent(s.net / s.totalIncome)} of income')
                        : null,
                    trailing: Amount(s.net, base, signed: true, flow: true),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _trialBalance() => AsyncView(
    ref.watch(_trialProvider),
    onRetry: () => ref.invalidate(_trialProvider),
    builder: (tb) {
      if (tb.rows.isEmpty) return const EmptyState(icon: Icons.balance, title: 'Nothing posted yet');
      final currencies = tb.currencies.toList()..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in currencies)
            SectionCard(
              title: 'In $c',
              trailing: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: tb.debits(c) == tb.credits(c)
                    ? StatusLabel(Status.good, 'Balanced')
                    : StatusLabel(Status.critical, 'Off by ${money(tb.debits(c) - tb.credits(c), c)}'),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(label: Text('Account')),
                    DataColumn(label: Text('Debit'), numeric: true),
                    DataColumn(label: Text('Credit'), numeric: true),
                  ],
                  rows: [
                    for (final r in tb.rows.where((r) => r.currency == c))
                      DataRow(
                        cells: [
                          DataCell(Text(r.account.name)),
                          DataCell(Text(r.debit == 0 ? '' : money(r.debit, c), style: tabular)),
                          DataCell(Text(r.credit == 0 ? '' : money(r.credit, c), style: tabular)),
                        ],
                      ),
                    DataRow(
                      cells: [
                        const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(money(tb.debits(c), c), style: tabular)),
                        DataCell(Text(money(tb.credits(c), c), style: tabular)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _checks() => AsyncView(
    ref.watch(dashboardProvider),
    builder: (d) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Integrity',
          hint: 'reports.integrity',
          child: d.integrity.isEmpty
              ? StatusLabel(Status.good, 'Every entry balances and points at a real account.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatusLabel(Status.critical, '${d.integrity.length} entries fail the check'),
                    for (final id in d.integrity)
                      ListTile(dense: true, title: Text(id), onTap: () => openEntryById(context, ref, id)),
                  ],
                ),
        ),
        SectionCard(
          title: 'Statement tally',
          hint: 'card.tally',
          child: d.tally.isEmpty
              ? const Text('Record a statement balance on an account, or import a statement with one.')
              : Column(
                  children: [
                    for (final t in d.tally)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          t.tallied ? Status.good.icon : Status.serious.icon,
                          color: t.tallied ? Status.good.color : Status.serious.color,
                        ),
                        title: Text(t.account.name),
                        subtitle: Text(
                          'Statement ${money(t.account.natural(t.statement), t.account.commodityId)} · '
                          'ledger ${money(t.account.natural(t.ledger), t.account.commodityId)} on ${niceDate(t.date)}',
                        ),
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}
