import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../db/database.dart';
import '../../../ui/theme.dart';
import '../domain/ledger.dart' show uncategorizedId;
import '../insights/categorizer.dart';
import '../insights/insights.dart' show Cadence, Recurring;

/// Bills, subscriptions and regular income: the ones spotted in the history
/// and the ones the user added. Spotted ones can be hidden or taken over
/// (edited), added ones edited or deleted.
class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(setupProvider).value ?? 'GBP';
    final today = ref.watch(todayProvider);
    final hidden = (ref.watch(recurringRowsProvider).value ?? const <RecurringRow>[])
        .where((r) => r.dismissed)
        .toList();
    return PageScaffold(
      title: 'Bills and subscriptions',
      banner: 'page.recurring',
      fab: FloatingActionButton.extended(
        onPressed: () => editRecurring(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Subscription'),
      ),
      children: [
        AsyncView(
          ref.watch(insightsProvider),
          onRetry: () => ref.invalidate(insightsProvider),
          builder: (d) {
            final items = [...d.recurring]..sort((a, b) => a.nextDate.compareTo(b.nextDate));
            final out = items.where((r) => r.amount < 0).toList();
            final income = items.where((r) => r.amount > 0).toList();
            final monthly = out.fold(0, (s, r) => s + r.cadence.perMonth(r.amount));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (items.isEmpty)
                  Card(
                    child: EmptyState(
                      icon: Icons.event_repeat,
                      title: 'Nothing regular yet',
                      message:
                          'Artha spots bills after three steady payments. Add a subscription now and it '
                          'shows in Upcoming bills and the forecast straight away.',
                      actions: [
                        FilledButton.icon(
                          onPressed: () => editRecurring(context, ref),
                          icon: const Icon(Icons.add),
                          label: const Text('Add subscription'),
                        ),
                      ],
                    ),
                  ),
                if (out.isNotEmpty)
                  SectionCard(
                    title: 'Going out · about ${money(-monthly, cur)} a month',
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(children: [for (final r in out) _tile(context, ref, r, cur, today)]),
                  ),
                if (income.isNotEmpty)
                  SectionCard(
                    title: 'Coming in',
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(children: [for (final r in income) _tile(context, ref, r, cur, today)]),
                  ),
                if (hidden.isNotEmpty)
                  SectionCard(
                    title: 'Hidden',
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        for (final h in hidden)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.visibility_off_outlined),
                            title: Text(h.label, overflow: TextOverflow.ellipsis),
                            trailing: TextButton(
                              onPressed: () => guarded(
                                context,
                                () => ref.mutate((s) => s.ledger.unhideRecurring(h.pattern)),
                              ),
                              child: const Text('Show'),
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

  Widget _tile(BuildContext context, WidgetRef ref, Recurring r, String cur, String today) {
    final muted = ArthaSkin.of(context).muted;
    final change = r.priceFrom;
    return ListTile(
      leading: Icon(r.manual ? Icons.push_pin_outlined : Icons.event_repeat, color: muted),
      title: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          '${r.cadence.name} · next ${niceDate(r.nextDate)}',
          if (r.manual) 'added by you' else 'spotted from ${r.count} payments',
          if (change != null && r.lastAmount != null)
            '${r.lastAmount!.abs() > change.abs() ? 'went up' : 'went down'} from ${money(change.abs(), cur)}',
        ].join(' · '),
      ),
      onTap: () => editRecurring(context, ref, item: r),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            money(r.amount, cur, signed: true),
            style: const TextStyle(fontWeight: FontWeight.w700).merge(tabular),
          ),
          if (r.manual)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => guarded(context, () => ref.mutate((s) => s.ledger.deleteRecurring(r.id!))),
            )
          else
            IconButton(
              tooltip: 'Hide: not a regular payment',
              icon: const Icon(Icons.visibility_off_outlined),
              onPressed: () =>
                  guarded(context, () => ref.mutate((s) => s.ledger.hideRecurring(r.key, r.label))),
            ),
        ],
      ),
    );
  }
}

/// Adds a subscription, or edits [item]. Editing a spotted item saves it as
/// the user's own, which then takes the spotted one's place.
Future<void> editRecurring(BuildContext context, WidgetRef ref, {Recurring? item}) async {
  final cur = ref.read(setupProvider).value ?? 'GBP';
  final scale = currencyInfo(cur).scale;
  final accounts = ref.read(accountsProvider).value ?? const <Account>[];
  final spotted = item != null && !item.manual;
  final label = TextEditingController(text: item?.label ?? '');
  // A spotted item's label is the bank's whole description; its first word
  // finds the payments well enough to start from.
  final pattern = TextEditingController(
    text: item == null ? '' : item.pattern ?? Categorizer.tokenize(item.label).firstOrNull ?? item.label,
  );
  final amount = TextEditingController(text: item == null ? '' : units(item.amount.abs(), scale));
  var out = item == null || item.amount < 0;
  var cadence = item?.cadence ?? Cadence.monthly;
  final String today = ref.read(todayProvider);
  var date = item?.nextDate ?? today;
  String? category = item == null || item.categoryId.isEmpty ? null : item.categoryId;
  final form = GlobalKey<FormState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final kind = out ? 'expense' : 'income';
        final categories =
            accounts.where((a) => a.kind == kind && !a.closed && a.id != uncategorizedId).toList()
              ..sort((a, b) => a.name.compareTo(b.name));
        if (!categories.any((c) => c.id == category)) category = null;
        return AlertDialog(
          title: Text(item == null ? 'New subscription' : (spotted ? 'Keep as your own' : 'Edit')),
          content: SizedBox(
            width: 420,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: label,
                      autofocus: item == null,
                      decoration: const InputDecoration(labelText: 'Name', helperText: 'e.g. Netflix'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name' : null,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Money out')),
                        ButtonSegment(value: false, label: Text('Money in')),
                      ],
                      selected: {out},
                      onSelectionChanged: (s) => setState(() => out = s.first),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Amount ($cur)'),
                      validator: (v) {
                        final x = parseMinor((v ?? '').trim(), scale);
                        return x == null || x <= 0 ? 'Not an amount' : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Cadence>(
                      initialValue: cadence,
                      decoration: const InputDecoration(labelText: 'Repeats'),
                      items: [
                        for (final c in Cadence.values)
                          DropdownMenuItem(
                            value: c,
                            child: Text('${c.name[0].toUpperCase()}${c.name.substring(1)}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => cadence = v ?? cadence),
                    ),
                    const SizedBox(height: 12),
                    DateField(
                      value: date,
                      label: 'Next due (or any past due date)',
                      onChanged: (v) => setState(() => date = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category (optional)'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('None')),
                        for (final c in categories)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => category = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: pattern,
                      decoration: const InputDecoration(
                        labelText: 'Statement text (optional)',
                        helperText: 'Finds its payments, e.g. NETFLIX. Empty uses the name.',
                      ),
                      validator: (v) {
                        final p = (v ?? '').trim();
                        return p.isNotEmpty && p.length < 2 ? 'At least two characters' : null;
                      },
                    ),
                  ],
                ),
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
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;
  final minor = parseMinor(amount.text.trim(), scale)!;
  await guarded(
    context,
    () => ref.mutate((s) async {
      await s.ledger.saveRecurring(
        id: item?.id,
        label: label.text,
        pattern: pattern.text,
        amount: out ? -minor : minor,
        cadence: cadence.name,
        anchorDate: date,
        categoryId: category ?? '',
      );
      // The user's version replaces the spotted one, which would otherwise
      // come back if the text no longer covers its description.
      if (spotted) await s.ledger.hideRecurring(item.key, item.label);
    }),
  );
}
