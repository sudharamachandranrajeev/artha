import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'accounts_page.dart';
import 'charts.dart';
import 'common.dart';
import 'import_page.dart';
import 'insights_page.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);
    final insights = ref.watch(insightsProvider);
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final hasAccounts = accounts.any((a) => a.isReal);
    return PageScaffold(
      title: 'Dashboard',
      banner: 'page.dashboard',
      children: [
        AsyncView(
          data,
          onRetry: () => ref.invalidate(reportsProvider),
          builder: (d) {
            final missing = d.sheet.missingRates;
            final m = insights.value?.metrics;
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
                TileGrid(
                  minWidth: 160,
                  children: [
                    KpiTile(
                      label: 'Net worth',
                      icon: Icons.account_balance_outlined,
                      hint: 'kpi.networth',
                      value: money(d.sheet.netWorth, cur),
                      caption: d.trend.length >= 2
                          ? '${money(d.sheet.netWorth - d.trend[d.trend.length - 2].netWorth, cur, signed: true)} vs last month'
                          : null,
                    ),
                    KpiTile(
                      label: 'Available cash',
                      icon: Icons.savings_outlined,
                      hint: 'kpi.liquid',
                      value: m == null ? '…' : money(m.liquid, cur),
                    ),
                    KpiTile(
                      label: 'Debt',
                      icon: Icons.credit_card,
                      hint: 'kpi.debt',
                      value: money(d.sheet.totalLiabilities, cur),
                    ),
                    KpiTile(
                      label: 'Savings rate',
                      icon: Icons.percent,
                      hint: 'kpi.savings',
                      value: m?.savingsRate == null ? '–' : percent(m!.savingsRate!),
                      caption: m?.savingsRate == null ? 'Needs a full month of income' : null,
                      status: switch (m?.savingsRate) {
                        null => null,
                        final r when r >= 0.2 => (color: Status.good.color, icon: Status.good.icon),
                        final r when r >= 0 => (color: Status.warning.color, icon: Status.warning.icon),
                        _ => (color: Status.critical.color, icon: Status.critical.icon),
                      },
                    ),
                    KpiTile(
                      label: 'Emergency fund',
                      icon: Icons.health_and_safety_outlined,
                      hint: 'kpi.emergency',
                      value: m?.emergencyMonths == null
                          ? '–'
                          : '${m!.emergencyMonths!.toStringAsFixed(1)} months',
                      caption: switch (m?.emergencyMonths) {
                        null => 'Needs spending history',
                        final v when v >= 6 => 'Comfortable',
                        final v when v >= 3 => 'Adequate',
                        _ => 'Below 3 months',
                      },
                      status: switch (m?.emergencyMonths) {
                        null => null,
                        final v when v >= 3 => (color: Status.good.color, icon: Status.good.icon),
                        _ => (color: Status.warning.color, icon: Status.warning.icon),
                      },
                    ),
                  ],
                ),
                LayoutBuilder(
                  builder: (context, c) {
                    final worth = SectionCard(
                      title: 'Net worth',
                      hint: 'chart.networth',
                      child: NetWorthChart(d.trend, cur),
                    );
                    final flowCard = SectionCard(
                      title: 'Income and spending',
                      hint: 'chart.flows',
                      child: hasFlows
                          ? FlowsChart(flows, cur)
                          : const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No income or spending recorded in the last 12 months.'),
                            ),
                    );
                    if (c.maxWidth < 900) return Column(children: [worth, flowCard]);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: worth),
                        const SizedBox(width: 16),
                        Expanded(child: flowCard),
                      ],
                    );
                  },
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
                AsyncView(
                  insights,
                  builder: (i) => i.facts.isEmpty
                      ? const SizedBox.shrink()
                      : SectionCard(
                          title: 'Needs attention',
                          hint: 'card.attention',
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            children: [for (final f in i.facts.take(3)) FactTile(f, compact: true)],
                          ),
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
}
