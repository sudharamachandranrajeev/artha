import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../insights/catalogue.dart';
import '../insights/risk.dart';
import '../insights/world.dart';
import 'assistant_page.dart';

/// "The world this week": live Bank Rate and inflation, tips that fit the
/// user's situation and the headlines that matter to them, each with a way
/// to ask for more.
class WorldCard extends ConsumerStatefulWidget {
  const WorldCard({super.key, required this.situation});
  final Situation situation;

  @override
  ConsumerState<WorldCard> createState() => _WorldCardState();
}

class _WorldCardState extends ConsumerState<WorldCard> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Fetches when the last download is old and the setting allows it.
    Future.microtask(() => ref.read(worldAutoProvider.future)).ignore();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final ok = await guarded(context, () async {
      await refreshWorld(ref.read(sessionProvider));
      ref.invalidate(worldProvider);
    });
    if (mounted) setState(() => _loading = false);
    if (ok && mounted) {
      final failed = ref.read(worldProvider).value?.failed ?? const [];
      if (failed.isNotEmpty) showError(context, WorldException('Could not read: ${failed.join(', ')}.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final world = ref.watch(worldProvider).value ?? WorldData.empty;
    final s = widget.situation;
    final day = ref.watch(todayProvider);
    final tips = quickTips(s, world.market, day);
    final news = rankNews(
      world.news,
      newsInterests(
        saves: s.holdings.any((h) => h.isCash),
        invests: s.invested > 0,
        mortgage: s.has('mortgage'),
        borrows: s.debts.isNotEmpty,
        pension: s.has('pension'),
      ),
      day,
    );
    final m = world.market;
    final fetched = DateTime.tryParse(world.fetched)?.toLocal();
    return SectionCard(
      title: 'The world this week',
      hint: 'insights.world',
      padding: const EdgeInsets.only(bottom: 8),
      trailing: _loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!m.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TileGrid(
                minWidth: 180,
                children: [
                  if (m.bankRate != null)
                    KpiTile(
                      label: 'Bank Rate',
                      icon: Icons.account_balance,
                      value: '${m.bankRate!.toStringAsFixed(2)}%',
                      caption: m.bankRateDate == null
                          ? 'Bank of England'
                          : 'Since ${niceDate(m.bankRateDate!)}',
                    ),
                  if (m.cpi != null)
                    KpiTile(
                      label: 'Inflation (CPI)',
                      icon: Icons.trending_up,
                      value: '${m.cpi!.toStringAsFixed(1)}%',
                      caption: 'Year to ${m.cpiMonth ?? ''}, ONS',
                    ),
                ],
              ),
            ),
          if (m.isEmpty && news.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                world.fetched.isEmpty
                    ? 'Nothing fetched yet. Refresh to load the latest rates and headlines, or turn on automatic '
                          'updates in Settings.'
                    : 'Could not reach the sources. Try again later.',
              ),
            ),
          if (tips.isNotEmpty) ...[
            const _Heading('Quick tips'),
            for (final t in tips)
              ExpansionTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(t.title),
                subtitle: t.source == null ? null : Text(t.source!),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.body),
                  if (t.ask != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => openAssistant(context, question: t.ask),
                        icon: const Icon(Icons.forum_outlined, size: 18),
                        label: const Text('Ask Artha'),
                      ),
                    ),
                ],
              ),
          ],
          if (news.isNotEmpty) ...[
            const _Heading('Headlines for you'),
            for (final n in news)
              ListTile(
                dense: true,
                leading: const Icon(Icons.article_outlined),
                title: Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${n.source} · ${niceDate(n.date)}${n.summary.isEmpty ? '' : '\n${n.summary}'}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: n.summary.isNotEmpty,
                onTap: () => openLink(n.link),
                trailing: IconButton(
                  tooltip: 'Ask Artha what this means for me',
                  icon: const Icon(Icons.forum_outlined),
                  onPressed: () => openAssistant(
                    context,
                    question:
                        'In plain terms, what does this mean for my money? "${n.title}" (${n.source}, ${n.date})',
                  ),
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              [
                if (fetched != null) 'Updated ${niceDate(isoDate(fetched))}',
                if (world.failed.isNotEmpty) 'could not read ${world.failed.join(', ')}',
                if (s.uk) 'rates catalogue checked ${niceDate(UkRates.asOf)}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
