import 'dart:convert';

import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../db/database.dart';
import '../domain/accounting.dart';
import '../domain/ledger.dart';
import 'common.dart';

enum TxKind {
  spend('Spending', Icons.north_east),
  income('Income', Icons.south_west),
  transfer('Transfer', Icons.swap_horiz),
  buy('Buy', Icons.add_shopping_cart),
  sell('Sell', Icons.sell_outlined);

  const TxKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

Future<void> openEntryEditor(BuildContext context, {EntryView? existing, String? accountId, TxKind? kind}) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => EntryEditorPage(existing: existing, accountId: accountId, kind: kind),
      ),
    );

Future<void> openEntryById(BuildContext context, WidgetRef ref, String id) async {
  final db = ref.read(sessionProvider).db;
  final e = await (db.select(db.entries)..where((x) => x.id.equals(id))).getSingleOrNull();
  if (e == null || e.deleted) return;
  final postings =
      await (db.select(db.postings)
            ..where((p) => p.entryId.equals(id))
            ..orderBy([(p) => OrderingTerm(expression: p.position)]))
          .get();
  if (context.mounted) await openEntryEditor(context, existing: EntryView(e, postings));
}

/// What an existing entry looks like in the simple forms, or null when only
/// the read-only view can show it (splits, trades).
({TxKind kind, Posting main, Posting other})? simpleShape(
  EntryView v,
  Map<String, Account> accounts,
  Map<String, Commodity> commodities,
) {
  if (v.postings.length != 2) return null;
  final [a, b] = v.postings;
  final aa = accounts[a.accountId], ba = accounts[b.accountId];
  if (aa == null || ba == null) return null;
  bool cur(Account x) => commodities[x.commodityId]?.isCurrency ?? true;
  if (!cur(aa) || !cur(ba)) return null;
  if (aa.isCategory != ba.isCategory) {
    final (main, cat) = aa.isCategory ? (b, a) : (a, b);
    final income = accounts[cat.accountId]!.kind == 'income';
    return (kind: income ? TxKind.income : TxKind.spend, main: main, other: cat);
  }
  if (aa.isReal && ba.isReal) {
    final (from, to) = a.amount <= 0 ? (a, b) : (b, a);
    return (kind: TxKind.transfer, main: from, other: to);
  }
  return null;
}

class EntryEditorPage extends ConsumerStatefulWidget {
  const EntryEditorPage({super.key, this.existing, this.accountId, this.kind});
  final EntryView? existing;
  final String? accountId;
  final TxKind? kind;

  @override
  ConsumerState<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends ConsumerState<EntryEditorPage> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _toAmount = TextEditingController();
  final _units = TextEditingController();
  final _payee = TextEditingController();
  final _memo = TextEditingController();
  TxKind _kind = TxKind.spend;
  String _date = today();
  String? _account, _other, _holding;
  bool _readOnly = false, _busy = false, _loaded = false;

  EntryView? get _existing => widget.existing;

  /// Fills the form from the existing entry once the account list is known.
  void _load(Map<String, Account> accounts, Map<String, Commodity> commodities) {
    _loaded = true;
    _kind = widget.kind ?? TxKind.spend;
    _account = widget.accountId;
    final v = _existing;
    if (v == null) return;
    _date = v.entry.date;
    _payee.text = v.entry.payee;
    _memo.text = v.entry.memo;
    final shape = simpleShape(v, accounts, commodities);
    if (shape == null) {
      _readOnly = true;
      return;
    }
    _kind = shape.kind;
    _account = shape.main.accountId;
    _other = shape.other.accountId;
    final mainAcc = accounts[_account]!;
    final scale = currencyInfo(mainAcc.commodityId).scale;
    switch (_kind) {
      case TxKind.spend:
        _amount.text = formatMinor(-shape.main.amount, scale);
      case TxKind.income:
        _amount.text = formatMinor(shape.main.amount, scale);
      case TxKind.transfer:
        _amount.text = formatMinor(-shape.main.amount, scale);
        _toAmount.text = formatMinor(shape.other.amount, currencyInfo(accounts[_other]!.commodityId).scale);
      case TxKind.buy || TxKind.sell:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(accountsProvider).value;
    final commodities = ref.watch(commoditiesProvider).value;
    if (list == null || commodities == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final accounts = {for (final a in list) a.id: a};
    if (!_loaded) _load(accounts, commodities);
    final title = _existing == null ? 'New transaction' : (_readOnly ? 'Transaction' : 'Edit transaction');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _delete,
            ),
          if (!_readOnly)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _busy ? null : () => _save(accounts, commodities),
                child: const Text('Save'),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _readOnly ? _readOnlyView(accounts, commodities) : _formView(list, accounts, commodities),
          ),
        ),
      ),
    );
  }

  Widget _readOnlyView(Map<String, Account> accounts, Map<String, Commodity> commodities) {
    final v = _existing!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Hint(
          'tx.split',
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.call_split),
              title: Text(v.entry.payee.isEmpty ? 'Entry' : v.entry.payee),
              subtitle: Text('${niceDate(v.entry.date)} · in ${v.entry.currency}'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (final p in v.postings)
                ListTile(
                  title: Text(accounts[p.accountId]?.name ?? 'Missing account'),
                  subtitle: p.memo.isEmpty ? null : Text(p.memo),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        commodities[accounts[p.accountId]?.commodityId]?.isCurrency ?? true
                            ? money(
                                p.amount,
                                accounts[p.accountId]?.commodityId ?? v.entry.currency,
                                signed: true,
                              )
                            : '${units(p.amount, scaleOf(commodities, accounts[p.accountId]!.commodityId))} units',
                        style: tabular,
                      ),
                      if (p.amount != p.value)
                        Text(
                          money(p.value, v.entry.currency, signed: true),
                          style: tabular.copyWith(fontSize: 12),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (v.entry.memo.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(v.entry.memo)),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Entries with more than two lines, and trades, are read-only. Delete and record it again to change it.',
          ),
        ),
      ],
    );
  }

  Widget _formView(List<Account> list, Map<String, Account> accounts, Map<String, Commodity> commodities) {
    bool isCurrency(Account a) => commodities[a.commodityId]?.isCurrency ?? true;
    final cash = list.where((a) => a.isReal && !a.closed && isCurrency(a)).toList();
    final holdings = list.where((a) => a.isReal && !a.closed && !isCurrency(a)).toList();
    final categories = list
        .where((a) => a.kind == (_kind == TxKind.income ? 'income' : 'expense') && !a.closed)
        .toList();
    final main = accounts[_account];
    final other = accounts[_other];
    final cur = main?.commodityId ?? (ref.read(setupProvider).value ?? 'GBP');
    final scale = currencyInfo(cur).scale;
    final crossCurrency =
        _kind == TxKind.transfer && main != null && other != null && main.commodityId != other.commodityId;
    String? amountCheck(String? v) {
      final x = parseMinor(v ?? '', scale);
      if (x == null) return 'Enter an amount';
      if (x == 0) return 'Must not be zero';
      if (_kind != TxKind.spend && x < 0) return 'Must be positive';
      return null;
    }

    final kinds = _existing == null ? TxKind.values : const [TxKind.spend, TxKind.income, TxKind.transfer];
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Hint(
            'tx.kind',
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<TxKind>(
                showSelectedIcon: false,
                segments: [
                  for (final k in kinds)
                    ButtonSegment(value: k, label: Text(k.label), icon: Icon(k.icon, size: 18)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  _other = null;
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DateField(value: _date, onChanged: (v) => setState(() => _date = v)),
          const SizedBox(height: 12),
          AccountField(
            label: switch (_kind) {
              TxKind.spend => 'Paid from',
              TxKind.income => 'Paid into',
              TxKind.transfer => 'From',
              _ => 'Cash account',
            },
            accounts: cash,
            value: _account,
            onChanged: (v) => setState(() => _account = v),
          ),
          const SizedBox(height: 12),
          if (_kind == TxKind.spend || _kind == TxKind.income)
            AccountField(
              label: 'Category',
              accounts: categories,
              value: _other,
              onChanged: (v) => setState(() => _other = v),
            )
          else if (_kind == TxKind.transfer)
            AccountField(
              label: 'To',
              accounts: cash.where((a) => a.id != _account).toList(),
              value: _other,
              onChanged: (v) => setState(() => _other = v),
            )
          else
            AccountField(
              label: 'Holding',
              accounts: holdings,
              value: _holding,
              onChanged: (v) => setState(() => _holding = v),
            ),
          if ((_kind == TxKind.buy || _kind == TxKind.sell) && holdings.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Add a holding first: Accounts > Account > type "Holding (single security)".'),
            ),
          const SizedBox(height: 12),
          if (_kind == TxKind.buy || _kind == TxKind.sell) ...[
            TextFormField(
              controller: _units,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: _kind == TxKind.buy ? 'Units bought' : 'Units sold'),
              validator: (v) {
                final h = accounts[_holding];
                if (h == null) return null;
                final u = parseMinor(v ?? '', scaleOf(commodities, h.commodityId));
                return u == null || u <= 0 ? 'Enter a number of units' : null;
              },
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _amount,
            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: _kind == TxKind.spend),
            decoration: InputDecoration(
              labelText: switch (_kind) {
                TxKind.buy => 'Total cost incl. fees ($cur)',
                TxKind.sell => 'Proceeds after fees ($cur)',
                TxKind.spend => 'Amount ($cur) · negative for a refund',
                _ => 'Amount ($cur)',
              },
            ),
            validator: amountCheck,
          ),
          if (crossCurrency) ...[
            const SizedBox(height: 12),
            Hint(
              'tx.toAmount',
              child: TextFormField(
                controller: _toAmount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Amount received (${other.commodityId})'),
                validator: (v) {
                  final x = parseMinor(v ?? '', currencyInfo(other.commodityId).scale);
                  return x == null || x <= 0 ? 'Enter what arrived' : null;
                },
              ),
            ),
          ],
          if (_kind == TxKind.spend || _kind == TxKind.income) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _payee,
              decoration: InputDecoration(labelText: _kind == TxKind.spend ? 'Payee' : 'Payer'),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _memo,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          if (_kind == TxKind.sell) _sellPreview(accounts, commodities, cur),
        ],
      ),
    );
  }

  Widget _sellPreview(Map<String, Account> accounts, Map<String, Commodity> commodities, String cur) {
    final h = accounts[_holding];
    if (h == null) return const SizedBox.shrink();
    final pool = ref.watch(balancesProvider).value?[h.id];
    final u = parseMinor(_units.text, scaleOf(commodities, h.commodityId));
    final proceeds = parseMinor(_amount.text, currencyInfo(cur).scale);
    if (pool == null || u == null || proceeds == null) return const SizedBox.shrink();
    final basis = pooledCost(pool.amount, pool.value, u);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        'Average cost of these units: ${money(basis, cur)}. '
        'Gain: ${money(proceeds - basis, cur, signed: true)}.',
      ),
    );
  }

  Future<void> _delete() async {
    if (!await confirm(
      context,
      title: 'Delete this transaction?',
      message: 'It is removed from every account it touches, on every synced device.',
      action: 'Delete',
      destructive: true,
    )) {
      return;
    }
    if (!mounted) return;
    if (await guarded(context, () => ref.mutate((s) => s.ledger.deleteEntry(_existing!.entry.id))) &&
        mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _save(Map<String, Account> accounts, Map<String, Commodity> commodities) async {
    if (!_form.currentState!.validate()) return;
    final main = accounts[_account]!;
    final cur = main.commodityId;
    final amount = parseMinor(_amount.text, currencyInfo(cur).scale)!;
    final old = _existing?.entry;
    final tags = old == null ? const <String>[] : (jsonDecode(old.tags) as List).cast<String>();
    EntryInput entry;
    switch (_kind) {
      case TxKind.spend || TxKind.income:
        final out = _kind == TxKind.spend ? amount : -amount;
        entry = EntryInput(
          id: old?.id,
          date: _date,
          currency: cur,
          payee: _payee.text.trim(),
          memo: _memo.text.trim(),
          status: old?.status ?? 'cleared',
          importRef: old?.importRef,
          reviewed: true,
          tags: tags,
          postings: [PostingInput.cash(main.id, -out), PostingInput.cash(_other!, out)],
        );
      case TxKind.transfer:
        final to = accounts[_other]!;
        final toAmount = to.commodityId == cur
            ? amount
            : parseMinor(_toAmount.text, currencyInfo(to.commodityId).scale)!;
        entry = EntryInput(
          id: old?.id,
          date: _date,
          currency: cur,
          payee: old?.payee ?? 'Transfer',
          memo: _memo.text.trim(),
          status: old?.status ?? 'cleared',
          importRef: old?.importRef,
          reviewed: true,
          tags: tags,
          postings: [PostingInput.cash(main.id, -amount), PostingInput(to.id, toAmount, amount)],
        );
      case TxKind.buy:
        final h = accounts[_holding]!;
        entry = buyEntry(
          date: _date,
          currency: cur,
          cashAccountId: main.id,
          holdingAccountId: h.id,
          units: parseMinor(_units.text, scaleOf(commodities, h.commodityId))!,
          cost: amount,
          memo: _memo.text.trim(),
        );
      case TxKind.sell:
        final h = accounts[_holding]!;
        final u = parseMinor(_units.text, scaleOf(commodities, h.commodityId))!;
        final pool = (await ref.read(balancesProvider.future))[h.id];
        if (pool == null || pool.amount < u) {
          if (mounted) showError(context, LedgerException('You hold fewer units than that'));
          return;
        }
        entry = sellEntry(
          date: _date,
          currency: cur,
          cashAccountId: main.id,
          holdingAccountId: h.id,
          gainsAccountId: gainsId,
          units: u,
          proceeds: amount,
          costBasis: pooledCost(pool.amount, pool.value, u),
          memo: _memo.text.trim(),
        );
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final ok = await guarded(context, () => ref.mutate((s) => s.ledger.saveEntry(entry)));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }
}
