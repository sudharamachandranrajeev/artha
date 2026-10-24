import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../insights/catalogue.dart';
import '../insights/risk.dart';
import '../portfolio/portfolio.dart' show assetClasses;
import 'assistant_page.dart';

Status statusOf(String severity) => switch (severity) {
  'good' => Status.good,
  'warn' => Status.warning,
  'action' => Status.serious,
  _ => Status.info,
};

/// Risk profile, checks, stress tests and the safest order to use money.
class RiskPage extends ConsumerWidget {
  const RiskPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(setupProvider).value ?? 'GBP';
    final cpi = ref.watch(worldProvider).value?.market.cpi;
    return PageScaffold(
      title: 'Risk and safest plan',
      banner: 'page.risk',
      actions: [
        IconButton(
          tooltip: 'Ask Artha',
          icon: const Icon(Icons.forum_outlined),
          onPressed: () => openAssistant(context),
        ),
      ],
      children: [
        AsyncView(
          ref.watch(situationProvider),
          onRetry: () => ref.invalidate(situationProvider),
          builder: (s) => AsyncView(
            ref.watch(riskAnswersProvider),
            builder: (answers) {
              final risk = assessRisk(s, answers);
              final checks = riskChecks(s, cpi: cpi);
              final plan = buildPlan(s, risk);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _profile(context, ref, risk, answers),
                  SectionCard(
                    title: 'Safest plan for you',
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(children: [for (final step in plan) _step(context, step, base)]),
                  ),
                  SectionCard(
                    title: 'Risk checks',
                    padding: const EdgeInsets.only(bottom: 8),
                    child: checks.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Nothing to check yet. Add accounts and a few months of transactions.',
                            ),
                          )
                        : Column(
                            children: [
                              for (final c in checks)
                                ListTile(
                                  leading: Icon(statusOf(c.severity).icon, color: statusOf(c.severity).color),
                                  title: Text(c.title),
                                  subtitle: Text(c.body),
                                  trailing: c.ask == null
                                      ? null
                                      : IconButton(
                                          tooltip: 'Ask Artha',
                                          icon: const Icon(Icons.forum_outlined),
                                          onPressed: () => openAssistant(context, question: c.ask),
                                        ),
                                ),
                            ],
                          ),
                  ),
                  SectionCard(
                    title: 'If things go wrong',
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        for (final t in stressTests(s))
                          ListTile(
                            leading: Icon(statusOf(t.severity).icon, color: statusOf(t.severity).color),
                            title: Text(t.title),
                            subtitle: Text(t.body),
                          ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'General information worked out from your own records, not regulated financial advice. '
                      'Safer options still carry some risk: rates change, protection has limits and past returns '
                      'do not predict future ones. For big decisions use MoneyHelper (free) or a regulated adviser.',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _profile(BuildContext context, WidgetRef ref, RiskAssessment risk, Map<String, int> answers) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'Your risk level',
      hint: 'risk.profile',
      trailing: TextButton(
        onPressed: () => _quiz(context, ref, answers),
        child: Text(risk.attitude == null ? 'Answer 4 questions' : 'Retake'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(risk.label, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Expanded(
                  child: Container(
                    height: 8,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: i <= risk.level ? scheme.primary : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            risk.attitude == null
                ? 'Based on your finances only (${risk.capacity}/5). Answer four questions to add what you are '
                      'comfortable with.'
                : 'Comfort ${risk.attitude}/5, what your finances can take ${risk.capacity}/5. The lower '
                      'one sets the level.',
          ),
          for (final l in risk.limits)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Status.warning.icon, size: 16, color: Status.warning.color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(l)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text('Mix to aim for: ${risk.profile.label}. ${risk.profile.description}'),
          Text(
            [
              for (final e in risk.profile.targets.entries)
                '${e.value ~/ 100}% ${assetClasses[e.key] ?? e.key}',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, PlanStep step, String base) {
    final (icon, color) = switch (step.state) {
      'done' => (Icons.check_circle, Status.good.color),
      'now' => (Icons.play_circle_fill, Theme.of(context).colorScheme.primary),
      'ongoing' => (Icons.autorenew, Status.info.color),
      _ => (Icons.radio_button_unchecked, Status.info.color),
    };
    final options = [for (final id in step.options) optionById(id)];
    return ExpansionTile(
      leading: Icon(icon, color: color),
      initiallyExpanded: step.state == 'now',
      title: Text(step.title),
      subtitle: Text(switch (step.state) {
        'done' => 'Done',
        'now' => step.gap == null ? 'Do this now' : 'Do this now · ${money(step.gap!, base)} to go',
        'ongoing' => 'Ongoing',
        _ => step.gap == null ? 'Next' : 'Next · ${money(step.gap!, base)}',
      }),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(step.body),
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Text('${o.risk}/7', style: Theme.of(context).textTheme.labelMedium),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: o.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (currentRate(o.id) case final r?) TextSpan(text: ' · $r'),
                        TextSpan(text: '\n${o.watchOut}'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (options.any((o) => currentRate(o.id) != null))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              UkRates.stale(today())
                  ? 'Rates checked ${niceDate(UkRates.asOf)}; they may be out of date.'
                  : 'Rates checked ${niceDate(UkRates.asOf)}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (step.ask != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => openAssistant(context, question: step.ask),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: const Text('Ask Artha about this'),
            ),
          ),
      ],
    );
  }

  Future<void> _quiz(BuildContext context, WidgetRef ref, Map<String, int> current) async {
    final picked = {...current};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('How much risk is right for you?'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final q in riskQuestions) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(q.text, style: Theme.of(context).textTheme.titleSmall),
                    ),
                    RadioGroup<int>(
                      groupValue: picked[q.id],
                      onChanged: (v) => setState(() => picked[q.id] = v!),
                      child: Column(
                        children: [
                          for (final (i, o) in q.options.indexed)
                            RadioListTile<int>(dense: true, value: i, title: Text(o)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: riskQuestions.every((q) => picked.containsKey(q.id))
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await guarded(context, () => ref.mutate((s) => s.ledger.setPref(riskAnswersKey, picked)));
  }
}
