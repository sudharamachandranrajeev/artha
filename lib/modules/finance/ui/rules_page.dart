import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../db/database.dart';
import '../domain/ledger.dart';
import 'common.dart';

/// Categorisation rules: text to look for and the category it files into.
/// Imports try them first, in order; they can also sort what is already
/// uncategorised.
class RulesPage extends ConsumerWidget {
  const RulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = {for (final a in ref.watch(accountsProvider).value ?? const <Account>[]) a.id: a};
    return PageScaffold(
      title: 'Categorisation rules',
      banner: 'page.rules',
      actions: [
        IconButton(
          tooltip: 'Sort uncategorised entries with these rules',
          icon: const Icon(Icons.auto_fix_high_outlined),
          onPressed: () => _apply(context, ref),
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed: () => editRule(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add rule'),
      ),
      children: [
        AsyncView(
          ref.watch(rulesProvider),
          onRetry: () => ref.invalidate(rulesProvider),
          builder: (rules) => rules.isEmpty
              ? Card(
                  child: EmptyState(
                    icon: Icons.rule_outlined,
                    title: 'No rules yet',
                    message:
                        'Add one such as “TESCO” → Groceries and every import files matching rows there.',
                    actions: [
                      FilledButton.icon(
                        onPressed: () => editRule(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Add rule'),
                      ),
                    ],
                  ),
                )
              : Card(
                  child: Column(
                    children: [
                      for (final (i, r) in rules.indexed)
                        ListTile(
                          title: Text('“${r.pattern}”'),
                          subtitle: Text(accounts[r.accountId]?.name ?? 'Missing category'),
                          onTap: () => editRule(context, ref, rule: r),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Try earlier',
                                icon: const Icon(Icons.arrow_upward),
                                onPressed: i == 0
                                    ? null
                                    : () => guarded(
                                        context,
                                        () => ref.mutate((s) => s.ledger.moveRule(r.id, -1)),
                                      ),
                              ),
                              IconButton(
                                tooltip: 'Try later',
                                icon: const Icon(Icons.arrow_downward),
                                onPressed: i == rules.length - 1
                                    ? null
                                    : () => guarded(
                                        context,
                                        () => ref.mutate((s) => s.ledger.moveRule(r.id, 1)),
                                      ),
                              ),
                              IconButton(
                                tooltip: 'Delete rule',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    guarded(context, () => ref.mutate((s) => s.ledger.deleteRule(r.id))),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    var changed = 0;
    final ok = await guarded(context, () async => changed = await ref.mutate((s) => s.ledger.applyRules()));
    if (ok && context.mounted) {
      showMessage(
        context,
        changed == 0
            ? 'No uncategorised entries match a rule'
            : 'Sorted $changed ${changed == 1 ? 'entry' : 'entries'} into categories',
      );
    }
  }
}

/// Adds a rule, or edits [rule]. [pattern] prefills a new one.
Future<void> editRule(BuildContext context, WidgetRef ref, {Rule? rule, String? pattern}) async {
  final categories =
      (ref.read(accountsProvider).value ?? const <Account>[])
          .where((a) => a.isCategory && !a.closed && a.id != uncategorizedId)
          .toList()
        ..sort((a, b) => a.kind == b.kind ? a.name.compareTo(b.name) : a.kind.compareTo(b.kind));
  final text = TextEditingController(text: rule?.pattern ?? pattern ?? '');
  var category = rule?.accountId;
  final form = GlobalKey<FormState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(rule == null ? 'New rule' : 'Edit rule'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: text,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'When the description contains',
                  helperText: 'Any case, e.g. TESCO or NETFLIX',
                ),
                validator: (v) => (v ?? '').trim().length < 2 ? 'At least two characters' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: categories.any((c) => c.id == category) ? category : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'File it under'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => category = v),
                validator: (v) => v == null ? 'Pick a category' : null,
              ),
            ],
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
  if (ok != true || !context.mounted) return;
  await guarded(
    context,
    () => ref.mutate((s) => s.ledger.saveRule(id: rule?.id, pattern: text.text, accountId: category!)),
  );
}
