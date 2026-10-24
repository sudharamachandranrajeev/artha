import 'dart:async';

import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../db/database.dart';
import '../domain/ledger.dart';
import '../../../ui/components.dart';
import '../../../ui/theme.dart';
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
  const TransactionsPage({super.key, this.review = false});

  /// Open on the review queue.
  final bool review;

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _account;

  /// Showing only the entries that wait for review.
  late bool _review = widget.review;
  final _selected = <String>{};

  /// Keyboard position in the review list.
  int _cursor = 0;
  List<EntryView> _rows = const [];
  final _keys = <String, GlobalKey>{};
  final _focus = FocusNode(debugLabel: 'review');

  @override
  void initState() {
    super.initState();
    // The keyboard cursor only shows while the list has focus.
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setReview(bool on) => setState(() {
    _review = on;
    _selected.clear();
    _cursor = 0;
    if (on) _focus.requestFocus();
  });

  Future<void> _markReviewed(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final ok = await guarded(context, () => ref.mutate((s) => s.ledger.setReviewed(list)));
    if (ok && mounted) setState(() => _selected.removeAll(list));
  }

  Future<void> _setCategory(List<Account> accounts) async {
    final ids = _selected.toList();
    final categories = accounts.where((a) => a.isCategory && !a.closed && a.id != uncategorizedId).toList()
      ..sort((a, b) => a.kind == b.kind ? a.name.compareTo(b.name) : a.kind.compareTo(b.kind));
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('File ${ids.length} under'),
        children: [
          for (final c in categories)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, c.id), child: Text(c.name)),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    var changed = 0;
    final ok = await guarded(
      context,
      () async => changed = await ref.mutate((s) => s.ledger.recategorise(ids, picked)),
    );
    if (!ok || !mounted) return;
    setState(_selected.clear);
    final left = ids.length - changed;
    showMessage(
      context,
      left == 0
          ? 'Filed $changed ${changed == 1 ? 'entry' : 'entries'}'
          : 'Filed $changed; $left left alone (transfers and splits change in the editor)',
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!_review || _rows.isEmpty || e is KeyUpEvent) return KeyEventResult.ignored;
    final at = _cursor.clamp(0, _rows.length - 1);
    final current = _rows[at].entry.id;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowUp:
        final next = (at + (e.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(
          0,
          _rows.length - 1,
        );
        setState(() => _cursor = next);
        final box = _keys[_rows[next].entry.id]?.currentContext;
        if (box != null) {
          Scrollable.ensureVisible(box, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
        }
      case LogicalKeyboardKey.keyR when e is KeyDownEvent:
        // The list shrinks, so the cursor lands on the next one.
        _markReviewed([current]);
      case LogicalKeyboardKey.space when e is KeyDownEvent:
        setState(() => _selected.contains(current) ? _selected.remove(current) : _selected.add(current));
      case LogicalKeyboardKey.enter when e is KeyDownEvent:
        openEntryEditor(context, existing: _rows[at]);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(accountsProvider).value ?? const <Account>[];
    final accounts = {for (final a in list) a.id: a};
    final entries = ref.watch(entriesProvider((query: _query, accountId: _account, review: _review)));
    final toReview = ref.watch(reviewCountProvider).value ?? 0;
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
            if (toReview > 0 || _review)
              Hint(
                'tx.review',
                child: FilterChip(
                  avatar: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text('To review ($toReview)'),
                  selected: _review,
                  onSelected: _setReview,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncView(
          entries,
          onRetry: () => ref.invalidate(entriesProvider),
          builder: (rows) {
            _rows = rows;
            if (rows.isEmpty && _review) {
              return EmptyState(
                icon: Icons.task_alt,
                title: 'All reviewed',
                message: 'New imports land here until you have looked at them.',
                actions: [OutlinedButton(onPressed: () => _setReview(false), child: const Text('Show all'))],
              );
            }
            if (rows.isEmpty) {
              return EmptyState(
                icon: Icons.receipt_long_outlined,
                title: _query.isEmpty ? 'No transactions yet' : 'Nothing matches "$_query"',
                message: _query.isEmpty
                    ? 'Record one with the button below, or import a bank statement.'
                    : null,
              );
            }
            final skin = ArthaSkin.of(context);
            final ids = {for (final v in rows) v.entry.id};
            _selected.retainAll(ids);
            _keys.removeWhere((id, _) => !ids.contains(id));
            final index = {for (final (i, v) in rows.indexed) v.entry.id: i};
            final column = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_review) _reviewBar(rows, list),
                for (final (date, list) in groupByDate(rows, (v) => v.entry.date)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                    child: Text(
                      niceDate(date),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: skin.muted),
                    ),
                  ),
                  Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final v in list) _txRow(v, accounts, index[v.entry.id]!)],
                    ),
                  ),
                ],
                if (rows.length >= 500)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Showing the latest 500. Search or pick an account to narrow it down.',
                      style: TextStyle(color: skin.muted),
                    ),
                  ),
              ],
            );
            return _review
                ? Focus(focusNode: _focus, autofocus: true, onKeyEvent: _onKey, child: column)
                : column;
          },
        ),
      ],
    );
  }

  Widget _reviewBar(List<EntryView> rows, List<Account> accounts) {
    final all = _selected.length == rows.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Checkbox(
              tristate: true,
              value: _selected.isEmpty ? false : (all ? true : null),
              onChanged: (_) => setState(() {
                if (all) {
                  _selected.clear();
                } else {
                  _selected.addAll(rows.map((v) => v.entry.id));
                }
              }),
            ),
            Text(_selected.isEmpty ? 'Select entries' : '${_selected.length} selected'),
            FilledButton.tonalIcon(
              onPressed: _selected.isEmpty ? null : () => _setCategory(accounts),
              icon: const Icon(Icons.category_outlined),
              label: const Text('Set category'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  _markReviewed(_selected.isEmpty ? rows.map((v) => v.entry.id) : [..._selected]),
              icon: const Icon(Icons.done_all),
              label: Text(_selected.isEmpty ? 'Mark all reviewed' : 'Mark reviewed'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _txRow(EntryView v, Map<String, Account> accounts, int index) {
    final d = describeEntry(v, accounts);
    final id = v.entry.id;
    final row = TxRow(
      leading: _review
          ? Checkbox(
              value: _selected.contains(id),
              onChanged: (on) => setState(() => on == true ? _selected.add(id) : _selected.remove(id)),
            )
          : null,
      title: d.title,
      subtitle: d.subtitle,
      trailing: d.flow
          ? Amount(
              d.amount,
              v.entry.currency,
              signed: true,
              flow: true,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            )
          : Text(
              money(d.amount, v.entry.currency),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700).merge(tabular),
            ),
      caption: d.flow ? (d.amount > 0 ? 'Income' : 'Spending') : 'Transfer',
      onTap: () => openEntryEditor(context, existing: v),
    );
    if (!_review) return row;
    return Container(
      key: _keys.putIfAbsent(id, GlobalKey.new),
      decoration: BoxDecoration(
        color: index == _cursor.clamp(0, _rows.length - 1) && _focus.hasFocus
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: row,
    );
  }
}
