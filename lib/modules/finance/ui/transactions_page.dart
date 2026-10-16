import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/database.dart';
import '../../../ui/format.dart';
import '../../../ui/hints.dart';
import '../../../ui/widgets.dart';
import 'common.dart';
import 'entry_editor.dart';
import 'import_page.dart';

/// How a journal entry reads in a list: what it was, against what, and the
/// net effect on the user's money (positive in, negative out, null for moves
/// between their own accounts).
({String title, String subtitle, int amount, bool flow}) describeEntry(
  EntryView v,
  Map<String, Account> accounts,
) {
  String name(String id) => accounts[id]?.name ?? '?';
  final label = v.entry.payee.isNotEmpty ? v.entry.payee : (v.entry.memo.isNotEmpty ? v.entry.memo : null);
  final categories = v.postings.where((p) => accounts[p.accountId]?.isCategory ?? false).toList();
  if (categories.isNotEmpty) {
    final net = -categories.fold(0, (s, p) => s + p.value);
    final own = v.postings
        .where((p) => !(accounts[p.accountId]?.isCategory ?? false))
        .map((p) => name(p.accountId))
        .join(', ');
    final cats = categories.map((p) => name(p.accountId)).join(', ');
    return (title: label ?? cats, subtitle: label == null ? own : '$cats · $own', amount: net, flow: true);
  }
  final moved = v.postings.where((p) => p.value > 0).fold(0, (s, p) => s + p.value);
  final from = v.postings.where((p) => p.value < 0).map((p) => name(p.accountId)).join(', ');
  final to = v.postings.where((p) => p.value > 0).map((p) => name(p.accountId)).join(', ');
  return (title: label ?? 'Transfer', subtitle: '$from → $to', amount: moved, flow: false);
}

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _account;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(accountsProvider).value ?? const <Account>[];
    final accounts = {for (final a in list) a.id: a};
    final entries = ref.watch(entriesProvider((query: _query, accountId: _account)));
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return PageScaffold(
      title: 'Transactions',
      banner: 'page.transactions',
      actions: [
        HintIconButton(
          'nav.import',
          icon: Icons.upload_file,
          label: 'Import statement',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportPage())),
        ),
      ],
      fab: Hint(
        'tx.add',
        child: FloatingActionButton.extended(
          onPressed: () => openEntryEditor(context, accountId: _account),
          icon: const Icon(Icons.add),
          label: const Text('Transaction'),
        ),
      ),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 360,
              child: Hint(
                'tx.search',
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search',
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = v));
                  },
                ),
              ),
            ),
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<String?>(
                initialValue: _account,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All accounts')),
                  for (final a in list.where((a) => a.isReal))
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _account = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncView(
          entries,
          onRetry: () => ref.invalidate(entriesProvider),
          builder: (rows) {
            if (rows.isEmpty) {
              return EmptyState(
                icon: Icons.receipt_long_outlined,
                title: _query.isEmpty ? 'No transactions yet' : 'Nothing matches "$_query"',
                message: _query.isEmpty
                    ? 'Record one with the button below, or import a bank statement.'
                    : null,
              );
            }
            String? lastDate;
            final children = <Widget>[];
            for (final v in rows) {
              if (v.entry.date != lastDate) {
                lastDate = v.entry.date;
                children.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      niceDate(v.entry.date),
                      style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              }
              final d = describeEntry(v, accounts);
              children.add(
                ListTile(
                  title: Text(d.title, overflow: TextOverflow.ellipsis),
                  subtitle: Text(d.subtitle, overflow: TextOverflow.ellipsis),
                  trailing: d.flow
                      ? Amount(d.amount, v.entry.currency, signed: true, flow: true)
                      : Text(money(d.amount, v.entry.currency), style: tabular.copyWith(color: muted)),
                  onTap: () => openEntryEditor(context, existing: v),
                ),
              );
            }
            if (rows.length >= 500) {
              children.add(
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Showing the latest 500. Search or pick an account to narrow it down.'),
                ),
              );
            }
            return Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            );
          },
        ),
      ],
    );
  }
}
