import 'dart:convert';

import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../db/database.dart';
import '../insights/catalogue.dart';
import '../insights/insights.dart';

Status _status(Fact f) => switch ((jsonDecode(f.data) as Map)['severity']) {
  'good' => Status.good,
  'warn' => Status.warning,
  'action' => Status.serious,
  _ => Status.info,
};

/// One insight or remembered fact, with feedback buttons.
class FactTile extends ConsumerWidget {
  const FactTile(this.fact, {super.key, this.compact = false});
  final Fact fact;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = fact.state == 'user' ? Status.info : _status(fact);
    final user = fact.state == 'user';
    Future<void> feedback(bool useful) =>
        guarded(context, () => ref.mutate((s) => KnowledgeBase(s.ledger).feedback(fact.id, useful: useful)));
    return ListTile(
      leading: Icon(user ? Icons.bookmark_outline : status.icon, color: user ? null : status.color),
      title: Text(fact.title),
      subtitle: fact.body.isEmpty
          ? null
          : Text(fact.body, maxLines: compact ? 2 : null, overflow: compact ? TextOverflow.ellipsis : null),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!user && fact.state != 'confirmed')
            HintIconButton(
              'insights.useful',
              icon: Icons.thumb_up_outlined,
              label: 'Useful',
              onPressed: () => feedback(true),
            ),
          HintIconButton(
            'insights.dismiss',
            icon: Icons.close,
            label: user ? 'Forget' : 'Dismiss',
            onPressed: () => feedback(false),
          ),
        ],
      ),
    );
  }
}

class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  bool _ukOnly = true;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(insightsProvider);
    final base = ref.watch(setupProvider).value ?? 'GBP';
    return PageScaffold(
      title: 'Insights',
      banner: 'page.insights',
      actions: [
        HintIconButton(
          'insights.remember',
          icon: Icons.bookmark_add_outlined,
          label: 'Tell Artha something',
          onPressed: () => _remember(base),
        ),
      ],
      children: [
        AsyncView(
          data,
          onRetry: () => ref.invalidate(insightsProvider),
          builder: (d) {
            final m = d.metrics;
            final user = d.facts.where((f) => f.state == 'user').toList();
            final auto = d.facts.where((f) => f.state != 'user').toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TileGrid(
                  minWidth: 180,
                  children: [
                    KpiTile(
                      label: 'Monthly income',
                      icon: Icons.south_west,
                      value: money(m.monthlyIncome, base),
                      caption: 'Average of recent full months',
                    ),
                    KpiTile(
                      label: 'Monthly spending',
                      icon: Icons.north_east,
                      value: money(m.monthlySpend, base),
                      caption: 'Essentials ${money(m.monthlyEssential, base)}',
                    ),
                    KpiTile(
                      label: 'Card utilisation',
                      icon: Icons.credit_card,
                      value: m.creditUtilisation == null ? '–' : percent(m.creditUtilisation!),
                      caption: 'Of card limits set on accounts',
                      status: m.creditUtilisation == null
                          ? null
                          : m.creditUtilisation! <= 0.3
                          ? (color: Status.good.color, icon: Status.good.icon)
                          : (color: Status.warning.color, icon: Status.warning.icon),
                    ),
                    KpiTile(
                      label: 'Debt to income',
                      icon: Icons.balance,
                      value: m.debtToIncome == null ? '–' : percent(m.debtToIncome!, digits: 0),
                      caption: 'Debt as a share of yearly income',
                    ),
                  ],
                ),
                if (m.isaUsed != null)
                  SectionCard(
                    title: 'ISA allowance ${UkAllowances.taxYear}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LinearProgressIndicator(
                          value: (m.isaUsed! / UkAllowances.isa).clamp(0, 1),
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${money(m.isaUsed!, 'GBP')} of ${money(UkAllowances.isa, 'GBP')} used; '
                          '${money((UkAllowances.isa - m.isaUsed!).clamp(0, UkAllowances.isa), 'GBP')} left '
                          'until 5 April.',
                        ),
                      ],
                    ),
                  ),
                SectionCard(
                  title: 'What Artha noticed',
                  padding: const EdgeInsets.only(bottom: 8),
                  child: auto.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nothing yet. Insights appear as transactions build up.'),
                        )
                      : Column(children: [for (final f in auto) FactTile(f)]),
                ),
                if (user.isNotEmpty)
                  SectionCard(
                    title: 'What you told Artha',
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(children: [for (final f in user) FactTile(f)]),
                  ),
                if (d.recurring.isNotEmpty)
                  SectionCard(
                    title: 'Regular payments',
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        for (final r in d.recurring)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.repeat),
                            title: Text(r.label, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${r.cadence.name} · next about ${niceDate(r.nextDate)}'),
                            trailing: Amount(r.amount, base, signed: true, flow: true),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        _explore(),
      ],
    );
  }

  Widget _explore() {
    final options = investmentOptions
        .where((o) => !_ukOnly || o.region == 'any' || o.region == 'GB')
        .toList();
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'Explore ways to save and invest',
      hint: 'insights.explore',
      trailing: FilterChip(
        label: const Text('UK'),
        selected: _ukOnly,
        onSelected: (v) => setState(() => _ukOnly = v),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatusLabel(
            Status.info,
            'General information, not financial advice. Rules and allowances change; check them, '
            'and consider a regulated adviser for personal advice.',
          ),
          const SizedBox(height: 8),
          for (final o in options)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              title: Text(o.name),
              subtitle: Row(
                children: [
                  for (var i = 1; i <= 7; i++)
                    Container(
                      width: 10,
                      height: 6,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: i <= o.risk ? scheme.primary : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Flexible(child: Text('Risk ${o.risk}/7 · ${o.access}', overflow: TextOverflow.ellipsis)),
                ],
              ),
              childrenPadding: const EdgeInsets.only(bottom: 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(o.summary), const SizedBox(height: 6), StatusLabel(Status.warning, o.watchOut)],
            ),
        ],
      ),
    );
  }

  Future<void> _remember(String base) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final amount = TextEditingController();
    var kind = 'goal';
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Tell Artha something'),
          content: SizedBox(
            width: 400,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'goal', label: Text('Goal')),
                      ButtonSegment(value: 'upcoming', label: Text('Coming cost')),
                      ButtonSegment(value: 'preference', label: Text('Preference')),
                    ],
                    selected: {kind},
                    onSelectionChanged: (s) => setState(() => kind = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: title,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: switch (kind) {
                        'goal' => 'Goal, e.g. House deposit by 2029',
                        'upcoming' => 'Cost, e.g. Car service in March',
                        _ => 'Preference, e.g. No crypto',
                      },
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Say what it is' : null,
                  ),
                  if (kind != 'preference') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Amount ($base, optional)'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty || parseMinor(v!, currencyInfo(base).scale) != null
                          ? null
                          : 'Not an amount',
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: body,
                    decoration: const InputDecoration(labelText: 'Details (optional)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final minor = parseMinor(amount.text, currencyInfo(base).scale);
    await guarded(
      context,
      () => ref.mutate(
        (s) => KnowledgeBase(s.ledger).remember(
          kind,
          title.text.trim(),
          body: body.text.trim(),
          data: {'amount': ?minor, if (minor != null) 'currency': base},
        ),
      ),
    );
  }
}
