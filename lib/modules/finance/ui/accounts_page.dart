import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../db/database.dart';
import '../../../ui/components.dart';
import '../../../ui/theme.dart';
import '../domain/accounting.dart';
import '../domain/ledger.dart';
import '../portfolio/portfolio.dart';
import '../reports/reports.dart';
import 'common.dart';
import 'entry_editor.dart';

/// Base-currency value of each account today (null: no rate).
final _baseValuesProvider = FutureProvider<Map<String, int?>>((ref) async {
  final d = await ref.watch(dashboardProvider.future);
  return {
    for (final l in [...d.sheet.assets, ...d.sheet.liabilities]) l.account.id: l.baseValue,
  };
});

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  bool _categories = false;

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final balances = ref.watch(balancesProvider).value ?? const {};
    final commodities = ref.watch(commoditiesProvider).value ?? const {};
    final baseValues = ref.watch(_baseValuesProvider).value ?? const {};
    final tally = {
      for (final t in ref.watch(dashboardProvider).value?.tally ?? <TallyRow>[]) t.account.id: t,
    };
    final base = ref.watch(setupProvider).value ?? 'GBP';
    return PageScaffold(
      title: 'Accounts',
      banner: 'page.accounts',
      fab: Hint(
        _categories ? 'tx.kind' : 'accounts.add',
        child: FloatingActionButton.extended(
          onPressed: () => _categories ? editCategory(context, ref) : editAccount(context, ref),
          icon: const Icon(Icons.add),
          label: Text(_categories ? 'Category' : 'Account'),
        ),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Accounts'),
                  icon: Icon(Icons.account_balance_outlined),
                ),
                ButtonSegment(value: true, label: Text('Categories'), icon: Icon(Icons.category_outlined)),
              ],
              selected: {_categories},
              onSelectionChanged: (s) => setState(() => _categories = s.first),
            ),
          ),
        ),
        AsyncView(
          accounts,
          onRetry: () => ref.invalidate(accountsProvider),
          builder: (list) {
            if (_categories) return _CategoryList(list.where((a) => a.isCategory).toList());
            final real = list.where((a) => a.isReal).toList();
            if (real.isEmpty) {
              return Card(
                child: EmptyState(
                  icon: Icons.account_balance_outlined,
                  title: 'No accounts yet',
                  message: 'Add current accounts, cards, savings, ISAs, investments, property and loans.',
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
            Widget tile(Account a) {
              final raw = balances[a.id]?.amount ?? 0;
              final c = commodities[a.commodityId];
              final isCurrency = c?.isCurrency ?? true;
              final own = isCurrency
                  ? money(a.natural(raw), a.commodityId)
                  : '${units(raw, scaleOf(commodities, a.commodityId))} ${c?.code ?? ''}';
              final inBase = baseValues[a.id];
              final t = tally[a.id];
              return ListTile(
                leading: CircleAvatar(child: Icon(subtypeIcon(a.subtype), size: 20)),
                title: Row(
                  children: [
                    Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                    if (t != null)
                      Hint(
                        'accounts.balance',
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            t.tallied ? Status.good.icon : Status.serious.icon,
                            size: 16,
                            color: t.tallied ? Status.good.color : Status.serious.color,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Text(
                  [a.type.label, if ((a.institution ?? '').isNotEmpty) a.institution!].join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(own, style: tabular),
                    if ((!isCurrency || a.commodityId != base) && inBase != null)
                      Text(
                        money(a.natural(inBase), base),
                        style: tabular.copyWith(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailPage(a.id))),
              );
            }

            Widget gridTile(Account a, int i) {
              final raw = balances[a.id]?.amount ?? 0;
              final c = commodities[a.commodityId];
              final isCurrency = c?.isCurrency ?? true;
              final own = isCurrency
                  ? money(a.natural(raw), a.commodityId)
                  : '${units(raw, scaleOf(commodities, a.commodityId))} ${c?.code ?? ''}';
              final inBase = baseValues[a.id];
              final t = tally[a.id];
              return _AccountTile(
                account: a,
                own: own,
                inBase: (!isCurrency || a.commodityId != base) && inBase != null
                    ? money(a.natural(inBase), base)
                    : null,
                tallied: t?.tallied,
                hasTally: t != null,
                solid: i.isOdd,
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailPage(a.id))),
              );
            }

            final open = real.where((a) => !a.closed).toList();
            final closed = real.where((a) => a.closed).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in groupLabels.entries)
                  if (open.any((a) => a.type.group == g.key)) ...[
                    SectionHeader(
                      g.value,
                      trailing: Text(
                        money(
                          open
                              .where((a) => a.type.group == g.key)
                              .fold(0, (s, a) => s + a.natural(baseValues[a.id] ?? 0)),
                          base,
                        ),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700).merge(tabular),
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, c) {
                        final list = open.where((a) => a.type.group == g.key).toList();
                        final cols = (c.maxWidth / 190).floor().clamp(1, 4);
                        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (var i = 0; i < list.length; i++)
                              SizedBox(width: w, child: gridTile(list[i], i)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                if (closed.isNotEmpty)
                  Card(
                    child: ExpansionTile(
                      shape: const Border(),
                      title: Hint('accounts.closed', child: Text('Closed (${closed.length})')),
                      children: [for (final a in closed) tile(a)],
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

class _CategoryList extends ConsumerWidget {
  const _CategoryList(this.categories);
  final List<Account> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget section(String title, String kind) => SectionCard(
      title: title,
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (final c in categories.where((c) => c.kind == kind))
            ListTile(
              dense: true,
              leading: Icon(subtypeIcon(kind), size: 20),
              title: Text(c.name),
              subtitle: c.essential ? const Text('Essential') : null,
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: () => editCategory(context, ref, category: c),
            ),
        ],
      ),
    );
    return Column(children: [section('Spending', 'expense'), section('Income', 'income')]);
  }
}

class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage(this.accountId, {super.key});
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountsProvider).value?.where((a) => a.id == accountId).firstOrNull;
    final commodities = ref.watch(commoditiesProvider).value ?? const {};
    final lines = ref.watch(accountLedgerProvider(accountId));
    if (account == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Account not found')),
      );
    }
    final c = commodities[account.commodityId];
    final isCurrency = c?.isCurrency ?? true;
    final scale = scaleOf(commodities, account.commodityId);
    String show(int raw) => isCurrency ? money(account.natural(raw), account.commodityId) : units(raw, scale);
    return PageScaffold(
      title: account.name,
      actions: [
        if (isCurrency)
          HintIconButton(
            'accounts.balance',
            icon: Icons.fact_check_outlined,
            label: 'Record statement balance',
            onPressed: () => _balanceCheck(context, ref, account),
          ),
        IconButton(
          tooltip: 'Edit account',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => editAccount(context, ref, account: account),
        ),
      ],
      fab: account.closed
          ? null
          : FloatingActionButton(
              tooltip: 'Add transaction',
              onPressed: () => openEntryEditor(context, accountId: account.id),
              child: const Icon(Icons.add),
            ),
      children: [
        AsyncView(
          lines,
          onRetry: () => ref.invalidate(accountLedgerProvider(accountId)),
          builder: (lines) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: ArthaSkin.of(context).primaryDeep,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        account.type.label,
                        if ((account.institution ?? '').isNotEmpty) account.institution!,
                        if ((account.number ?? '').isNotEmpty) account.number!,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xB3FFFFFF),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lines.isEmpty ? show(0) : show(lines.first.balance),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFFFFFFF),
                      ).merge(tabular),
                    ),
                    if (!isCurrency)
                      Text(
                        '${c?.name ?? ''} · ${c?.code ?? ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xB3FFFFFF),
                        ),
                      ),
                    if (account.notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        account.notes,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xB3FFFFFF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _StatementTally(account),
              const SizedBox(height: 16),
              if (lines.isEmpty)
                const EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions yet')
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (date, list) in groupByDate(lines, (l) => l.date)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                        child: Text(
                          niceDate(date),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ArthaSkin.of(context).muted,
                          ),
                        ),
                      ),
                      Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final l in list)
                              TxRow(
                                title: l.payee.isNotEmpty
                                    ? l.payee
                                    : (l.memo.isNotEmpty ? l.memo : l.counterparts.join(', ')),
                                subtitle: l.counterparts.join(', '),
                                trailing: Text(
                                  isCurrency
                                      ? money(l.amount, account.commodityId, signed: true)
                                      : units(l.amount, scale),
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700).merge(tabular),
                                ),
                                caption: show(l.balance),
                                onTap: () => openEntryById(context, ref, l.entryId),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Statement balances of one account against the ledger, oldest first.
final accountTallyProvider = FutureProvider.family<List<TallyRow>, String>((ref, id) async {
  final r = await ref.watch(reportsProvider.future);
  return r.accountTally(id);
});

/// Whether the ledger agrees with each statement balance the bank printed. A
/// difference that starts at one statement and carries on afterwards means
/// transactions are missing before it, usually a statement not yet imported.
class _StatementTally extends ConsumerWidget {
  const _StatementTally(this.account);
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(accountTallyProvider(account.id)).value ?? const <TallyRow>[];
    // One check per day is enough to see the pattern: keep each statement end.
    if (rows.length < 2) return const SizedBox.shrink();
    final first = rows.indexWhere((t) => !t.tallied);
    String show(int raw) => money(account.natural(raw), account.commodityId, signed: true);
    final muted = ArthaSkin.of(context).muted;
    final String summary;
    if (first < 0) {
      summary =
          'The ledger agrees with every statement balance, from ${niceDate(rows.first.date)} to ${niceDate(rows.last.date)}.';
    } else if (first == 0) {
      summary =
          'The ledger is out by ${show(rows.first.difference)} at the first statement balance, on ${niceDate(rows.first.date)}. '
          'Transactions before that date are missing or duplicated.';
    } else {
      summary =
          'The ledger agreed up to ${niceDate(rows[first - 1].date)} and is out by ${show(rows[first].difference)} on '
          '${niceDate(rows[first].date)}. Look for a statement or transactions between those dates.';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusLabel(first < 0 ? Status.good : Status.serious, summary),
              const SizedBox(height: 12),
              for (final t in rows.reversed.take(12))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        t.tallied ? Status.good.icon : Status.serious.icon,
                        size: 16,
                        color: t.tallied ? Status.good.color : Status.serious.color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(niceDate(t.date), style: TextStyle(fontSize: 13, color: muted)),
                      ),
                      Text(
                        t.tallied ? show(t.statement) : '${show(t.statement)} · off by ${show(t.difference)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600).merge(tabular),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lines of one account, newest first.
final accountLedgerProvider = FutureProvider.family<List<LedgerLine>, String>((ref, id) async {
  final r = await ref.watch(reportsProvider.future);
  return (await r.accountLedger(id)).reversed.toList();
});

Future<void> _balanceCheck(BuildContext context, WidgetRef ref, Account account) async {
  var date = today();
  final amount = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final scale = currencyInfo(account.commodityId).scale;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Statement balance'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.accountKind == AccountKind.liability
                      ? 'Enter what the statement says you owe.'
                      : 'Enter the closing balance on the statement.',
                ),
                const SizedBox(height: 12),
                DateField(value: date, onChanged: (v) => setState(() => date = v)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(labelText: 'Balance (${account.commodityId})'),
                  validator: (v) => parseMinor(v ?? '', scale) == null ? 'Enter an amount' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final value = account.raw(parseMinor(amount.text, scale)!);
  if (await guarded(
        context,
        () => ref.mutate((s) => s.ledger.saveBalanceCheck(account.id, date, value, note: 'Entered by hand')),
      ) &&
      context.mounted) {
    final d = await ref.read(dashboardProvider.future);
    final t = d.tally.where((t) => t.account.id == account.id).firstOrNull;
    if (t != null && context.mounted) {
      showMessage(
        context,
        t.tallied
            ? 'Ledger agrees with the statement.'
            : 'Ledger differs by ${money(account.natural(t.difference), account.commodityId, signed: true)}. '
                  'Look for missing or duplicate transactions.',
      );
    }
  }
}

/// Mock account tile: icon square, name, own balance and base-currency value.
class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.own,
    this.inBase,
    this.tallied,
    this.hasTally = false,
    this.solid = false,
    required this.onTap,
  });
  final Account account;
  final String own;
  final String? inBase;
  final bool? tallied;
  final bool hasTally;
  final bool solid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconSquare(subtypeIcon(account.subtype), solid: solid),
                  if (hasTally)
                    Hint(
                      'accounts.balance',
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          tallied! ? Status.good.icon : Status.serious.icon,
                          size: 16,
                          color: tallied! ? Status.good.color : Status.serious.color,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                account.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                own,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: skin.muted).merge(tabular),
              ),
              if (inBase != null)
                Text(
                  inBase!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: skin.muted,
                  ).merge(tabular),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Adds or edits one of the user's accounts.
Future<void> editAccount(BuildContext context, WidgetRef ref, {Account? account}) =>
    showDialog(context: context, builder: (_) => _AccountDialog(account));

class _AccountDialog extends ConsumerStatefulWidget {
  const _AccountDialog(this.account);
  final Account? account;

  @override
  ConsumerState<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends ConsumerState<_AccountDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account?.name);
  late final _institution = TextEditingController(text: widget.account?.institution);
  late final _number = TextEditingController(text: widget.account?.number);
  late final _notes = TextEditingController(text: widget.account?.notes);
  final _opening = TextEditingController();
  late final _limit = TextEditingController(
    text: switch (widget.account?.metaMap['creditLimit']) {
      final int v => formatMinor(v, currencyInfo(widget.account!.commodityId).scale),
      _ => '',
    },
  );
  final _code = TextEditingController();
  final _secName = TextEditingController();
  late String _subtype = widget.account?.subtype ?? 'current';
  late String _currency = widget.account?.commodityId ?? ref.read(setupProvider).value ?? 'GBP';
  late String _quote = _currency;
  String _assetClass = 'equity';
  String _openingDate = today();
  late bool _closed = widget.account?.closed ?? false;
  bool _busy = false;

  bool get _isNew => widget.account == null;
  bool get _holding => _subtype == 'security' || _subtype == 'crypto';
  bool get _hasLimit => const {'credit_card', 'overdraft', 'bnpl'}.contains(_subtype);

  @override
  Widget build(BuildContext context) {
    final types = subtypes.where((s) => s.kind == AccountKind.asset || s.kind == AccountKind.liability);
    final scale = currencyInfo(_currency).scale;
    return AlertDialog(
      title: Text(_isNew ? 'New account' : 'Edit account'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: _isNew,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _subtype,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final s in types)
                      DropdownMenuItem(
                        value: s.id,
                        child: Row(
                          children: [
                            Icon(subtypeIcon(s.id), size: 18),
                            const SizedBox(width: 8),
                            Flexible(child: Text(s.label, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                  ],
                  // A holding's commodity is fixed once created.
                  onChanged: !_isNew && (_holding || widget.account!.isCategory)
                      ? null
                      : (v) => setState(() => _subtype = v!),
                ),
                const SizedBox(height: 12),
                if (_holding && _isNew) ...[
                  TextFormField(
                    controller: _code,
                    decoration: InputDecoration(
                      labelText: _subtype == 'crypto' ? 'Coin (e.g. BTC)' : 'Ticker (e.g. VWRP)',
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Needed to price the holding' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _secName,
                    decoration: const InputDecoration(labelText: 'Full name (optional)'),
                  ),
                  const SizedBox(height: 12),
                  CurrencyField(
                    label: 'Priced in',
                    value: _quote,
                    onChanged: (v) => setState(() => _quote = v),
                  ),
                  const SizedBox(height: 12),
                  if (_subtype == 'security')
                    DropdownButtonFormField<String>(
                      initialValue: _assetClass,
                      decoration: const InputDecoration(labelText: 'Asset class'),
                      items: [
                        for (final e in assetClasses.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() => _assetClass = v!),
                    ),
                ] else if (!_holding)
                  _isNew
                      ? CurrencyField(value: _currency, onChanged: (v) => setState(() => _currency = v))
                      : InputDecorator(
                          decoration: const InputDecoration(labelText: 'Currency'),
                          child: Text(_currency),
                        ),
                if (_hasLimit) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _limit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Credit limit (optional)',
                      helperText: 'Lets Artha track how much of the limit is used.',
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) return null;
                      final x = parseMinor(v!, scale);
                      return x == null || x < 0 ? 'Not an amount' : null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _institution,
                  decoration: const InputDecoration(labelText: 'Bank or provider (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _number,
                  decoration: const InputDecoration(
                    labelText: 'Account number (optional)',
                    helperText: 'The last 4 digits are enough to tell accounts apart.',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
                if (_isNew && !_holding) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _opening,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          decoration: InputDecoration(
                            labelText: subtypeOf(_subtype).kind == AccountKind.liability
                                ? 'Owed today (optional)'
                                : 'Balance today (optional)',
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty || parseMinor(v!, scale) != null
                              ? null
                              : 'Not an amount',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DateField(
                          label: 'As of',
                          value: _openingDate,
                          onChanged: (v) => setState(() => _openingDate = v),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!_isNew)
                  Hint(
                    'accounts.closed',
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Closed'),
                      value: _closed,
                      onChanged: (v) => setState(() => _closed = v),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (!_isNew)
          TextButton(
            onPressed: _busy ? null : _delete,
            child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }

  Future<void> _delete() async {
    final a = widget.account!;
    if (!await confirm(
      context,
      title: 'Delete ${a.name}?',
      message: 'Only an account without transactions can be deleted. Close it instead to keep its history.',
      action: 'Delete',
      destructive: true,
    )) {
      return;
    }
    if (!mounted) return;
    if (await guarded(context, () => ref.mutate((s) => s.ledger.deleteAccount(a.id))) && mounted) {
      Navigator.of(context)
        ..pop()
        ..popUntil((r) => r.isFirst);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final a = widget.account;
    final scale = currencyInfo(_currency).scale;
    final opening = _opening.text.trim().isEmpty ? 0 : parseMinor(_opening.text, scale)!;
    final ok = await guarded(
      context,
      () => ref.mutate((s) async {
        var commodity = a?.commodityId ?? _currency;
        if (_isNew && _holding) {
          final code = _code.text.trim().toUpperCase();
          commodity = await s.ledger.createSecurity(
            code: code,
            name: _secName.text.trim().isEmpty ? code : _secName.text.trim(),
            quoteCurrency: _quote,
            assetClass: _subtype == 'crypto' ? 'crypto' : _assetClass,
            scale: _subtype == 'crypto' ? 8 : 6,
          );
        }
        final id = await s.ledger.saveAccount(
          id: a?.id,
          name: _name.text,
          subtype: _subtype,
          commodityId: commodity,
          parentId: a?.parentId,
          institution: _institution.text.trim().isEmpty ? null : _institution.text.trim(),
          number: _number.text.trim().isEmpty ? null : _number.text.trim(),
          notes: _notes.text.trim(),
          closed: _closed,
          meta: {
            ...?a?.metaMap,
            'creditLimit': _hasLimit && _limit.text.trim().isNotEmpty ? parseMinor(_limit.text, scale) : null,
          }..removeWhere((_, v) => v == null),
        );
        if (opening != 0) {
          final raw = naturalSign(subtypeOf(_subtype).kind, opening);
          await s.ledger.saveEntry(
            EntryInput(
              date: _openingDate,
              currency: commodity,
              payee: 'Opening balance',
              postings: [PostingInput.cash(id, raw), PostingInput.cash(openingBalancesId, -raw)],
            ),
          );
        }
      }),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }
}

/// Adds or edits an income or spending category.
Future<void> editCategory(BuildContext context, WidgetRef ref, {Account? category}) async {
  final name = TextEditingController(text: category?.name);
  var kind = category?.kind ?? 'expense';
  var essential = category?.essential ?? false;
  final form = GlobalKey<FormState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(category == null ? 'New category' : 'Edit category'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name' : null,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('Spending')),
                    ButtonSegment(value: 'income', label: Text('Income')),
                  ],
                  selected: {kind},
                  onSelectionChanged: category == null ? (s) => setState(() => kind = s.first) : null,
                ),
                if (kind == 'expense')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Essential'),
                    subtitle: const Text('Counts towards the emergency-fund target.'),
                    value: essential,
                    onChanged: (v) => setState(() => essential = v),
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
  if (ok != true || !context.mounted) return;
  final base = ref.read(setupProvider).value ?? 'GBP';
  await guarded(
    context,
    () => ref.mutate(
      (s) => s.ledger.saveAccount(
        id: category?.id,
        name: name.text,
        subtype: kind,
        commodityId: category?.commodityId ?? base,
        meta: {...?category?.metaMap, 'essential': kind == 'expense' && essential},
      ),
    ),
  );
}
