import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../portfolio/portfolio.dart';
import 'accounts_page.dart';
import 'charts.dart';
import 'common.dart';
import 'entry_editor.dart';

class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage> {
  final _newMoney = TextEditingController();
  Map<String, int>? _split;

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider);
    final targets = ref.watch(targetsProvider).value ?? const {};
    return PageScaffold(
      title: 'Portfolio',
      banner: 'page.portfolio',
      actions: [
        HintIconButton(
          'portfolio.trade',
          icon: Icons.swap_vert,
          label: 'Record trade',
          onPressed: () => openEntryEditor(context, kind: TxKind.buy),
        ),
      ],
      children: [
        AsyncView(
          portfolio,
          onRetry: () => ref.invalidate(portfolioProvider),
          builder: (p) {
            if (p.positions.isEmpty) {
              return Card(
                child: EmptyState(
                  icon: Icons.pie_chart_outline,
                  title: 'Nothing to show yet',
                  message: 'Add savings, ISAs, brokerage cash or single holdings on the Accounts page.',
                  actions: [
                    FilledButton.icon(
                      onPressed: () => editAccount(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Add account'),
                    ),
                  ],
                ),
              );
            }
            final base = p.base;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TileGrid(
                  children: [
                    KpiTile(
                      label: 'Total',
                      icon: Icons.account_balance_outlined,
                      value: money(p.total, base),
                    ),
                    KpiTile(
                      label: 'Invested',
                      icon: Icons.trending_up,
                      value: money(p.invested, base),
                      caption: p.totalCost == 0 ? null : 'Cost ${money(p.totalCost, base)}',
                    ),
                    KpiTile(
                      label: 'Unrealised gain',
                      icon: Icons.show_chart,
                      value: money(p.unrealisedGain, base, signed: true),
                      caption: p.totalCost == 0 ? null : percent(p.unrealisedGain / p.totalCost),
                    ),
                    KpiTile(
                      label: 'Diversification',
                      icon: Icons.scatter_plot_outlined,
                      value: '${p.effectiveHoldings.toStringAsFixed(1)} holdings',
                      caption: 'Behaves like this many equal positions',
                    ),
                  ],
                ),
                if (p.missingRates.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: StatusLabel(
                      Status.warning,
                      'No price or rate yet for ${codesOf(ref.watch(commoditiesProvider).value ?? const {}, p.missingRates)}; '
                      'they count as zero.',
                    ),
                  ),
                SectionCard(
                  title: 'Allocation',
                  trailing: TextButton.icon(
                    onPressed: () => _editTargets(context, targets),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(targets.isEmpty ? 'Set targets' : 'Targets'),
                  ),
                  child: AllocationBar(p.byClass, base, targets: targets),
                ),
                if (targets.isNotEmpty) _driftCard(p, targets),
                if (targets.isNotEmpty) _newMoneyCard(p, targets),
                _positionsCard(p),
                if (p.byCurrency.length > 1)
                  SectionCard(
                    title: 'Currency exposure',
                    child: Column(
                      children: [
                        for (final e
                            in p.byCurrency.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                SizedBox(width: 56, child: Text(e.key)),
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: p.total == 0 ? 0 : e.value / p.total,
                                    minHeight: 8,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    p.total == 0 ? '' : percent(e.value / p.total),
                                    textAlign: TextAlign.end,
                                    style: tabular,
                                  ),
                                ),
                              ],
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

  Widget _driftCard(Portfolio p, Map<String, int> targets) {
    final drift = p.drift(targets);
    final trades = p.rebalance(targets);
    return SectionCard(
      title: 'Drift from targets',
      hint: 'portfolio.drift',
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (final d in drift)
            ListTile(
              dense: true,
              leading: Icon(
                d.outOfBand ? Status.warning.icon : Status.good.icon,
                color: d.outOfBand ? Status.warning.color : Status.good.color,
              ),
              title: Text(assetClasses[d.assetClass] ?? d.assetClass),
              subtitle: Text('Now ${basisPoints(d.currentBp)} · target ${basisPoints(d.targetBp)}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${d.driftBp > 0 ? '+' : ''}${basisPoints(d.driftBp)}', style: tabular),
                  if ((trades[d.assetClass] ?? 0) != 0)
                    Text(
                      '${trades[d.assetClass]! > 0 ? 'Buy' : 'Sell'} ${money(trades[d.assetClass]!.abs(), p.base)}',
                      style: tabular.copyWith(fontSize: 12),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _newMoneyCard(Portfolio p, Map<String, int> targets) {
    final scale = currencyInfo(p.base).scale;
    return SectionCard(
      title: 'Invest new money',
      hint: 'portfolio.newMoney',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newMoney,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Amount (${p.base})'),
                  onSubmitted: (_) => _allocate(p, targets, scale),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(onPressed: () => _allocate(p, targets, scale), child: const Text('Split')),
            ],
          ),
          if (_split != null) ...[
            const SizedBox(height: 12),
            for (final e in _split!.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: ChartColors.of(context).forClass(e.key),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(assetClasses[e.key] ?? e.key)),
                    Text(money(e.value, p.base), style: tabular),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _allocate(Portfolio p, Map<String, int> targets, int scale) {
    final amount = parseMinor(_newMoney.text, scale);
    setState(() => _split = amount == null || amount <= 0 ? null : p.allocateNewMoney(targets, amount));
  }

  Widget _positionsCard(Portfolio p) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final sorted = [...p.positions]..sort((a, b) => (b.value ?? 0).compareTo(a.value ?? 0));
    return SectionCard(
      title: 'Positions',
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (final pos in sorted)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: ChartColors.of(context).forClass(pos.assetClass),
                radius: 6,
              ),
              title: Text(
                pos.commodity.isCurrency ? pos.account.name : '${pos.commodity.code} · ${pos.account.name}',
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  assetClasses[pos.assetClass] ?? pos.assetClass,
                  if (!pos.commodity.isCurrency) '${units(pos.units, pos.commodity.scale)} units',
                  if (pos.priceDate != null) 'priced ${niceDate(pos.priceDate!)}',
                ].join(' · '),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(pos.value == null ? 'No price' : money(pos.value!, p.base), style: tabular),
                      if (pos.gain != null)
                        Text(
                          '${money(pos.gain!, p.base, signed: true)}'
                          '${pos.gainRatio == null ? '' : ' (${percent(pos.gainRatio!)})'}',
                          style: tabular.copyWith(fontSize: 12, color: muted),
                        ),
                    ],
                  ),
                  if (!pos.commodity.isCurrency)
                    HintIconButton(
                      'portfolio.price',
                      icon: Icons.price_change_outlined,
                      label: 'Update price',
                      onPressed: () => _price(pos),
                    ),
                ],
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AccountDetailPage(pos.account.id)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _price(Position pos) async {
    final c = pos.commodity;
    final quote = c.quoteCurrency ?? ref.read(setupProvider).value ?? 'GBP';
    final price = TextEditingController();
    var date = today();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Price of ${c.code}'),
          content: SizedBox(
            width: 340,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: price,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Price of one unit ($quote)'),
                    validator: (v) {
                      final r = Rate.tryParse((v ?? '').replaceAll(',', ''));
                      return r == null || r.num <= BigInt.zero ? 'Enter a price above zero' : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DateField(value: date, onChanged: (v) => setState(() => date = v)),
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
    final rate = Rate.parse(price.text.replaceAll(',', ''));
    await guarded(context, () => ref.mutate((s) => s.ledger.savePrice(c.id, quote, date, rate)));
  }

  Future<void> _editTargets(BuildContext context, Map<String, int> current) async {
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => _TargetsDialog(current),
    );
    if (result == null || !context.mounted) return;
    await guarded(context, () => ref.mutate((s) => s.ledger.saveTargets(result)));
  }
}

/// Picks a risk profile as a starting point, then adjusts each class.
class _TargetsDialog extends StatefulWidget {
  const _TargetsDialog(this.current);
  final Map<String, int> current;

  @override
  State<_TargetsDialog> createState() => _TargetsDialogState();
}

class _TargetsDialogState extends State<_TargetsDialog> {
  late Map<String, int> _bp = {for (final c in assetClasses.keys) c: widget.current[c] ?? 0};

  int get _sum => _bp.values.fold(0, (s, v) => s + v);

  @override
  Widget build(BuildContext context) {
    final colors = ChartColors.of(context);
    return AlertDialog(
      title: const Text('Target allocation'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Hint(
                'portfolio.profile',
                child: Text('Start from a profile', style: Theme.of(context).textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in riskProfiles)
                    Tooltip(
                      message: r.description,
                      child: ActionChip(
                        label: Text(r.label),
                        onPressed: () =>
                            setState(() => _bp = {for (final c in assetClasses.keys) c: r.targets[c] ?? 0}),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              for (final c in assetClasses.keys)
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors.forClass(c),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 110, child: Text(assetClasses[c]!)),
                    Expanded(
                      child: Slider(
                        value: _bp[c]! / 100,
                        max: 100,
                        divisions: 100,
                        label: basisPoints(_bp[c]!),
                        onChanged: (v) => setState(() => _bp[c] = (v * 100).round()),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(basisPoints(_bp[c]!), textAlign: TextAlign.end, style: tabular),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              _sum == 10000
                  ? StatusLabel(Status.good, 'Adds up to 100%')
                  : StatusLabel(Status.warning, 'Adds up to ${basisPoints(_sum)}; it must be 100%'),
              const SizedBox(height: 8),
              Text(
                'A starting point, not advice. Match it to how long you can leave the money and how '
                'much of a fall you could sit through.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _sum == 10000
              ? () => Navigator.pop(context, Map.of(_bp)..removeWhere((_, v) => v == 0))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
