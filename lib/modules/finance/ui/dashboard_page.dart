import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../db/database.dart' show Fact;
import '../../../ui/components.dart';
import '../../../ui/theme.dart';
import '../insights/insights.dart' show Metrics, Recurring;
import 'accounts_page.dart';
import 'budgets_page.dart';
import 'charts.dart';
import 'common.dart';
import 'entry_editor.dart';
import 'import_page.dart';
import 'insights_page.dart';

void _openInsights(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const InsightsPage()));

void _openBudgets(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetsPage()));

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);
    final insights = ref.watch(insightsProvider);
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final hasAccounts = accounts.any((a) => a.isReal);
    final budgets = ref.watch(budgetsProvider).value ?? const <BudgetLine>[];
    return PageScaffold(
      title: 'Dashboard',
      banner: 'page.dashboard',
      actions: [
        Hint(
          'tx.add',
          child: CircleActionButton(
            icon: Icons.add,
            tooltip: 'Add transaction',
            onPressed: () => openEntryEditor(context),
          ),
        ),
        Hint(
          'nav.insights',
          child: CircleActionButton(
            icon: Icons.north_east,
            solid: false,
            tooltip: 'Insights',
            onPressed: () => _openInsights(context),
          ),
        ),
      ],
      children: [
        AsyncView(
          data,
          onRetry: () => ref.invalidate(reportsProvider),
          builder: (d) {
            final missing = d.sheet.missingRates;
            final m = insights.value?.metrics;
            final facts = insights.value?.facts ?? const <Fact>[];
            final recurring = insights.value?.recurring ?? const <Recurring>[];
            final cur = ref.watch(setupProvider).value ?? 'GBP';
            if (!hasAccounts) {
              return Card(
                child: EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Start with your accounts',
                  message: 'Add a bank account, card or savings pot, then import a statement or record a few transactions.',
                  actions: [
                    FilledButton.icon(
                      onPressed: () => editAccount(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Add account'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportPage())),
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import statement'),
                    ),
                  ],
                ),
              );
            }
            final flows = d.flows;
            final hasFlows = flows.any((f) => f.income != 0 || f.expenses != 0);
            final income = flows.isEmpty ? 0 : flows.last.income;
            final spend = flows.isEmpty ? 0 : flows.last.expenses;
            final net = income - spend;
            final savedFrac = income > 0 ? (net / income).clamp(0.0, 1.0) : 0.0;
            var streak = 0;
            for (final f in flows.reversed) {
              if (f.income - f.expenses > 0) {
                streak++;
              } else {
                break;
              }
            }
            final up = d.trend.length >= 2 && d.trend.last.netWorth >= d.trend[d.trend.length - 2].netWorth;
            final skin = ArthaSkin.of(context);
            final caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: skin.muted);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.integrity.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: Icon(Status.critical.icon, color: Status.critical.color),
                        title: Text('${d.integrity.length} entries fail the integrity check'),
                        subtitle: const Text('See Reports > Checks. Do not rely on totals until fixed.'),
                      ),
                    ),
                  ),
                HeroHeader(
                  up ? 'You are on top' : 'Steady as you go',
                  up ? 'of your finances' : 'your finances at a glance',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Hint(
                          'kpi.networth',
                          child: Text(
                            'Net worth',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: skin.muted),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          money(d.sheet.netWorth, cur),
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700).merge(tabular),
                        ),
                        if (d.trend.length >= 2)
                          Text(
                            '${money(d.sheet.netWorth - d.trend[d.trend.length - 2].netWorth, cur, signed: true)} vs last month',
                            style: caption,
                          ),
                        const SizedBox(height: 16),
                        Hint('chart.networth', child: NetWorthChart(d.trend, cur)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final tiles = [
                      StatTile(
                        label: 'Income',
                        value: money(income, cur),
                        icon: Icons.north_east,
                        hint: 'chart.flows',
                      ),
                      StatTile(
                        label: 'Spending',
                        value: money(spend, cur),
                        icon: Icons.south_east,
                        hint: 'chart.flows',
                      ),
                    ];
                    if (c.maxWidth < 480) {
                      return Column(
                        children: [
                          for (final t in tiles)
                            Padding(padding: const EdgeInsets.only(bottom: 12), child: t),
                        ],
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: tiles[0]),
                          const SizedBox(width: 12),
                          Expanded(child: tiles[1]),
                        ],
                      ),
                    );
                  },
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Saved this month',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: skin.muted),
                            ),
                            const Spacer(),
                            ProgressLine(value: savedFrac, height: 6, width: 64),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          money(net, cur),
                          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700).merge(tabular),
                        ),
                        Text('out of ${money(income, cur)} income', style: caption),
                        const SizedBox(height: 16),
                        ProgressLine(value: savedFrac, dots: [0.0, 0.5, savedFrac]),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text('Your progress', style: caption),
                            const Spacer(),
                            Text(
                              income > 0 ? percent(net / income) : '–',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700).merge(tabular),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (net > 0) ...[
                  const SizedBox(height: 12),
                  BannerPill(
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department, size: 16, color: Color(0xFFFFFFFF)),
                        Text(
                          ' x$streak',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ],
                    ),
                    child: Text('You saved ${money(net, cur)} this month'),
                  ),
                ],
                SectionHeader(
                  'Your activity',
                  actionLabel: 'See all',
                  onAction: () => _openInsights(context),
                ),
                _activityRow(facts, recurring, cur),
                SectionHeader(
                  'Budgets',
                  actionLabel: budgets.any((b) => b.budget > 0) ? 'Manage' : 'Set up',
                  onAction: () => _openBudgets(context),
                ),
                Hint('card.budgets', child: _budgetsCard(context, ref, budgets, cur)),
                if (recurring.any((r) => r.amount < 0)) ...[
                  SectionHeader('Upcoming bills'),
                  Hint('card.bills', child: _billsCard(context, recurring, ref.watch(todayProvider), cur)),
                ],
                SectionHeader('Your stats'),
                _statsGrid(d, m, cur),
                SectionHeader('Income and spending'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: hasFlows
                        ? FlowsChart(flows, cur)
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No income or spending recorded in the last 12 months.',
                              style: caption,
                            ),
                          ),
                  ),
                ),
                if (missing.isNotEmpty)
                  SectionCard(
                    title: 'Missing exchange rates or prices',
                    hint: 'card.missing',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusLabel(
                          Status.warning,
                          codesOf(ref.watch(commoditiesProvider).value ?? const {}, missing),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Update rates in Settings, or record a price for each holding on the Portfolio page.',
                        ),
                      ],
                    ),
                  ),
                if (d.tally.isNotEmpty)
                  SectionCard(
                    title: 'Statement tally',
                    hint: 'card.tally',
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
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
                              t.tallied
                                  ? 'Agrees with the statement on ${niceDate(t.date)}'
                                  : 'Off by ${money(t.account.natural(t.difference), t.account.commodityId, signed: true)} '
                                        'on ${niceDate(t.date)}',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _budgetsCard(BuildContext context, WidgetRef ref, List<BudgetLine> lines, String cur) {
    final set = lines.where((l) => l.budget > 0).take(4).toList();
    if (set.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: const Text('Set monthly budgets'),
          subtitle: const Text('Pick the categories to keep an eye on.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openBudgets(context),
        ),
      );
    }
    return Card(
      child: Column(
        children: [for (final l in set) BudgetRow(l, cur, onTap: () => editBudget(context, ref, l, cur))],
      ),
    );
  }

  /// The next payment of each recurring bill, soonest first.
  Widget _billsCard(BuildContext context, List<Recurring> recurring, String today, String cur) {
    final bills = recurring.where((r) => r.amount < 0).toList()
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    final muted = ArthaSkin.of(context).muted;
    String due(String date) {
      final d = daysBetween(date, today);
      return d < 0
          ? 'Overdue by ${-d} days'
          : d == 0
          ? 'Due today'
          : d == 1
          ? 'Due tomorrow'
          : 'Due in $d days';
    }

    return Card(
      child: Column(
        children: [
          for (final b in bills.take(5))
            ListTile(
              leading: Icon(Icons.event_repeat, color: muted),
              title: Text(b.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${due(b.nextDate)} · ${niceDate(b.nextDate)} · ${b.cadence.name}'),
              trailing: Text(
                money(b.amount, cur, signed: true),
                style: const TextStyle(fontWeight: FontWeight.w700).merge(tabular),
              ),
            ),
        ],
      ),
    );
  }

  Widget _activityRow(List<Fact> facts, List<Recurring> recurring, String cur) {
    final bills = recurring.where((r) => r.amount < 0).toList();
    final cards = <Widget>[
      if (facts.isNotEmpty)
        _ActivityCard(
          discs: const [(Icons.lightbulb_outline, false)],
          title: facts.first.title,
          caption: facts.first.body,
          onTap: (context) => _openInsights(context),
        ),
      if (bills.isNotEmpty)
        _ActivityCard(
          discs: const [(Icons.receipt_long_outlined, false), (Icons.payments_outlined, true)],
          title: 'Upcoming bills',
          caption: '${bills.length} recurring · ${bills.first.label}',
          value: money(bills.fold(0, (s, r) => s + r.amount), cur),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        if (cards.length == 1 || c.maxWidth < 560) {
          return Column(
            children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: w)],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }

  Widget _statsGrid(DashboardData d, Metrics? m, String cur) {
    final cards = [
      StatsCard(
        label: 'Net worth',
        value: money(d.sheet.netWorth, cur),
        icon: Icons.account_balance_outlined,
        caption: d.trend.length >= 2
            ? '${money(d.sheet.netWorth - d.trend[d.trend.length - 2].netWorth, cur, signed: true)} vs last month'
            : null,
        hint: 'kpi.networth',
      ),
      StatsCard(
        label: 'Available cash',
        value: m == null ? '…' : money(m.liquid, cur),
        icon: Icons.savings_outlined,
        solid: true,
        hint: 'kpi.liquid',
      ),
      StatsCard(
        label: 'Debt',
        value: money(d.sheet.totalLiabilities, cur),
        icon: Icons.credit_card,
        hint: 'kpi.debt',
      ),
      StatsCard(
        label: 'Savings rate',
        value: m?.savingsRate == null ? '–' : percent(m!.savingsRate!),
        icon: Icons.percent,
        caption: m?.savingsRate == null ? 'Needs a full month of income' : null,
        solid: true,
        hint: 'kpi.savings',
      ),
      StatsCard(
        label: 'Emergency fund',
        value: m?.emergencyMonths == null ? '–' : '${m!.emergencyMonths!.toStringAsFixed(1)} months',
        icon: Icons.health_and_safety_outlined,
        caption: switch (m?.emergencyMonths) {
          null => 'Needs spending history',
          final v when v >= 6 => 'Comfortable',
          final v when v >= 3 => 'Adequate',
          _ => 'Below 3 months',
        },
        hint: 'kpi.emergency',
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / 220).floor().clamp(2, 5);
        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final card in cards) SizedBox(width: w, child: card)],
        );
      },
    );
  }
}

/// Mock activity card: overlapping discs, title, caption and a heavy value.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.discs, required this.title, this.caption, this.value, this.onTap});
  final List<(IconData, bool)> discs;
  final String title;
  final String? caption;
  final String? value;
  final void Function(BuildContext)? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(context),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 32,
                width: 32.0 + 22 * (discs.length - 1),
                child: Stack(
                  children: [
                    for (var i = 0; i < discs.length; i++)
                      Positioned(
                        left: i * 22.0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: discs[i].$2 ? scheme.primary : skin.soft,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surface, width: 2),
                          ),
                          child: Icon(
                            discs[i].$1,
                            size: 14,
                            color: discs[i].$2 ? scheme.onPrimary : skin.onSoft,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Text(
                  caption!,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: skin.muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (value != null) ...[
                const SizedBox(height: 8),
                Text(value!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700).merge(tabular)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
