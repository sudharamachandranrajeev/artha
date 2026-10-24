import 'dart:convert';
import 'dart:typed_data';

import 'package:brahma_core/brahma_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../db/database.dart';
import '../domain/accounting.dart';
import '../import/csv_statement.dart';
import '../import/import_service.dart';
import '../import/ofx_qif.dart';
import '../import/pdf_statement.dart';
import '../import/pdf_text.dart';
import '../import/statement.dart';
import 'accounts_page.dart';
import 'common.dart';

/// Larger files are almost certainly not a bank statement.
const _maxBytes = 20 * 1024 * 1024;

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  String? _accountId;
  String? _fileName, _text, _ext;

  /// A PDF statement once read; the account can change without reading again.
  ParsedStatement? _pdf;

  /// How the account was chosen for a PDF: recognised, or new.
  String? _recognised;

  /// The user confirmed a statement that prints no figures to check against.
  bool _confirmed = false;
  List<List<String>>? _csv;
  CsvMapping? _mapping;
  ImportPlan? _plan;
  ImportResult? _result;
  bool _busy = false;

  String get _prefKey => 'import.csv.$_accountId';

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose statements (select several PDFs to import a whole period)',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'csv', 'txt', 'ofx', 'qfx', 'qif'],
    );
    if (picked.isEmpty || !mounted) return;
    final files = <(PlatformFile, Uint8List)>[];
    for (final f in picked) {
      final size = await f.length();
      final bytes = size != null && size > _maxBytes ? null : await f.readAsBytes();
      if (!mounted) return;
      if (bytes == null || bytes.length > _maxBytes) {
        return showError(context, StatementFormatException('${f.name} is over 20 MB; it is not a statement'));
      }
      files.add((f, bytes));
    }
    bool isPdf((PlatformFile, Uint8List) x) =>
        (x.$1.extension ?? '').toLowerCase() == 'pdf' ||
        (x.$2.length > 4 && latin1.decode(x.$2.sublist(0, 5)) == '%PDF-');
    if (files.length > 1 && !files.every(isPdf)) {
      return showError(
        context,
        StatementFormatException('Select several PDF statements, or one CSV, OFX or QIF file'),
      );
    }
    final (f, bytes) = files.first;
    final ext = (f.extension ?? '').replaceFirst('.', '').toLowerCase();
    if (isPdf(files.first)) {
      setState(() {
        _fileName = files.length == 1 ? f.name : '${files.length} PDF statements';
        _ext = 'pdf';
        _text = null;
        _csv = null;
        _mapping = null;
        _plan = null;
        _result = null;
        _pdf = null;
        _recognised = null;
        _confirmed = false;
        _busy = true;
      });
      await guarded(context, () async {
        final parsed = <ParsedStatement>[];
        for (final (file, data) in files) {
          try {
            final st = parsePdfStatement(await readPdfLines(data));
            if (st.lines.isEmpty) throw StatementFormatException('No transactions found');
            parsed.add(st);
          } on StatementFormatException catch (e) {
            throw StatementFormatException(files.length == 1 ? e.message : '${file.name}: ${e.message}');
          }
        }
        final st = mergeStatements(parsed);
        setState(() => _pdf = st);
        await _planPdf(recognise: true);
      });
      if (mounted) setState(() => _busy = false);
      return;
    }
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // Some banks still export Windows-1252; keep what decodes.
      text = latin1.decode(bytes);
    }
    if (text.startsWith('﻿')) text = text.substring(1);
    setState(() {
      _fileName = f.name;
      _ext = ext;
      _pdf = null;
      _recognised = null;
      _text = text;
      _csv = null;
      _mapping = null;
      _plan = null;
      _result = null;
    });
    await _read();
  }

  /// Parses the file: CSV shows the column mapping first; OFX/QIF go straight
  /// to the review.
  Future<void> _read() async {
    final text = _text, accountId = _accountId;
    if (text == null || accountId == null) return;
    final scale = currencyInfo(_account!.commodityId).scale;
    await guarded(context, () async {
      if (_ext == 'ofx' || _ext == 'qfx' || text.toUpperCase().contains('<OFX>')) {
        await _review(parseOfx(text, scale));
      } else if (_ext == 'qif' || text.trimLeft().startsWith('!Type')) {
        await _review(parseQif(text, scale));
      } else {
        final rows = parseCsv(text);
        final saved = await ref.read(sessionProvider).ledger.pref<Map<String, Object?>?>(_prefKey, null);
        var mapping = saved == null ? null : CsvMapping.fromJson(saved);
        final width = rows.fold(0, (w, r) => r.length > w ? r.length : w);
        if (mapping == null || mapping.date >= width || mapping.headerRow >= rows.length) {
          mapping = CsvMapping.guess(rows);
        }
        if (mapping == null) {
          throw StatementFormatException('Could not find a date column. Is this a bank statement?');
        }
        setState(() {
          _csv = rows;
          _mapping = mapping;
        });
      }
    });
  }

  Future<void> _applyCsv() async {
    final m = _mapping!;
    if (!m.isValid) {
      return showError(
        context,
        StatementFormatException('Choose an amount column, or debit and credit columns'),
      );
    }
    final ok = await guarded(context, () async {
      final st = m.apply(_csv!, currencyInfo(_account!.commodityId).scale);
      await _review(st);
    });
    // Remember the mapping for this account, on every device.
    if (ok) await ref.read(sessionProvider).ledger.setPref(_prefKey, m.toJson());
  }

  /// Plans a read PDF into the chosen account, or with [recognise] into the
  /// account its numbers name, or a new one when none does.
  Future<void> _planPdf({bool recognise = false}) async {
    final st = _pdf!;
    final service = ImportService(ref.read(sessionProvider).ledger);
    if (recognise) {
      final matches = await service.matchAccounts(st);
      if (matches.isNotEmpty) {
        _accountId = matches.first.id;
        _recognised = 'Recognised as ${matches.first.name} from its account number.';
      } else {
        final base = ref.read(setupProvider).value ?? 'GBP';
        final plan = await service.planFor(service.newAccountFor(st, base), st, create: true);
        setState(() {
          _accountId = null;
          _recognised = null;
          _plan = plan;
        });
        return;
      }
    }
    final plan = await service.plan(_accountId!, st);
    setState(() => _plan = plan);
  }

  Future<void> _review(ParsedStatement st) async {
    if (st.lines.isEmpty) throw StatementFormatException('No transactions found in the file');
    final plan = await ImportService(ref.read(sessionProvider).ledger).plan(_accountId!, st);
    setState(() => _plan = plan);
  }

  Future<void> _commit() async {
    setState(() => _busy = true);
    await guarded(context, () async {
      final r = await ref.mutate((s) => ImportService(s.ledger).commit(_plan!));
      setState(() {
        _accountId = _plan!.account.id;
        _result = r;
      });
    });
    if (mounted) setState(() => _busy = false);
  }

  Account? get _account => ref.read(accountsProvider).value?.where((a) => a.id == _accountId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(accountsProvider).value ?? const <Account>[];
    final commodities = ref.watch(commoditiesProvider).value ?? const {};
    final targets = list
        .where((a) => a.isReal && !a.closed && (commodities[a.commodityId]?.isCurrency ?? true))
        .toList();
    return PageScaffold(
      title: 'Import statement',
      banner: 'page.import',
      children: [
        SectionCard(
          title: '1 · Account and file',
          hint: 'import.pick',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (targets.isEmpty)
                Row(
                  children: [
                    const Expanded(child: Text('Add the account this statement belongs to first.')),
                    FilledButton.tonal(
                      onPressed: () => editAccount(context, ref),
                      child: const Text('Add account'),
                    ),
                  ],
                )
              else
                AccountField(
                  accounts: targets,
                  value: _accountId,
                  onChanged: (v) => setState(() {
                    _accountId = v;
                    _plan = null;
                    _result = null;
                    _recognised = null;
                    if (_pdf != null && v != null) {
                      guarded(context, _planPdf);
                    } else if (_text != null) {
                      _read();
                    }
                  }),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Choose file'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _fileName ?? 'PDF, CSV, OFX, QFX or QIF',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              if (_busy && _pdf == null && _ext == 'pdf')
                const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              if (_recognised != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: StatusLabel(Status.good, _recognised!),
                ),
              if (_text != null && _accountId == null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: StatusLabel(Status.info, 'Choose the account this file belongs to.'),
                ),
            ],
          ),
        ),
        if (_csv != null && _mapping != null && _result == null) _mappingCard(),
        if (_plan != null && _result == null) _reviewCard(list),
        if (_result != null) _resultCard(),
      ],
    );
  }

  Widget _mappingCard() {
    final rows = _csv!, m = _mapping!;
    final width = rows.fold(0, (w, r) => r.length > w ? r.length : w);
    final header = m.headerRow >= 0 && m.headerRow < rows.length ? rows[m.headerRow] : const <String>[];
    String colName(int i) =>
        i < header.length && header[i].trim().isNotEmpty ? header[i].trim() : 'Column ${i + 1}';
    final data = rows.skip(m.headerRow + 1).take(5).toList();
    Widget column(String label, int? value, void Function(int?) set, {bool optional = true}) => SizedBox(
      width: 200,
      child: DropdownButtonFormField<int?>(
        key: ValueKey('$label/$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          if (optional) const DropdownMenuItem(value: null, child: Text('—')),
          for (var i = 0; i < width; i++)
            DropdownMenuItem(
              value: i,
              child: Text(colName(i), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() {
          set(v);
          _plan = null;
        }),
      ),
    );
    return SectionCard(
      title: '2 · Columns',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Check that Artha read the columns right. It remembers this for the account.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              column('Date', m.date, (v) => m.date = v ?? m.date, optional: false),
              column('Amount', m.amount, (v) => m.amount = v),
              column('Money out', m.debit, (v) => m.debit = v),
              column('Money in', m.credit, (v) => m.credit = v),
              column('Payee / description', m.payee, (v) => m.payee = v),
              column('Reference / memo', m.memo, (v) => m.memo = v),
              column('Balance', m.balance, (v) => m.balance = v),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<DateOrder>(
                  initialValue: m.dateOrder,
                  decoration: const InputDecoration(labelText: 'Date format'),
                  items: const [
                    DropdownMenuItem(value: DateOrder.dmy, child: Text('Day/Month/Year')),
                    DropdownMenuItem(value: DateOrder.mdy, child: Text('Month/Day/Year')),
                    DropdownMenuItem(value: DateOrder.ymd, child: Text('Year-Month-Day')),
                  ],
                  onChanged: (v) => setState(() => m.dateOrder = v!),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: m.decimalSeparator,
                  decoration: const InputDecoration(labelText: 'Decimal mark'),
                  items: const [
                    DropdownMenuItem(value: '.', child: Text('1,234.56')),
                    DropdownMenuItem(value: ',', child: Text('1.234,56')),
                  ],
                  onChanged: (v) => setState(() => m.decimalSeparator = v!),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Spending is listed as positive'),
            subtitle: const Text('Some card exports do this. Turn on to flip the signs.'),
            value: m.invert,
            onChanged: (v) => setState(() => m.invert = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: [for (var i = 0; i < width; i++) DataColumn(label: Text(colName(i)))],
              rows: [
                for (final r in data)
                  DataRow(
                    cells: [
                      for (var i = 0; i < width; i++)
                        DataCell(Text(i < r.length ? r[i] : '', overflow: TextOverflow.ellipsis)),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _busy ? null : _applyCsv, child: const Text('Read statement')),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(List<Account> list) {
    final p = _plan!;
    final cur = p.currency;
    final categories = list.where((a) => a.isCategory && !a.closed).toList()
      ..sort((a, b) => a.kind == b.kind ? a.name.compareTo(b.name) : b.kind.compareTo(a.kind));
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final toCreate = p.count(RowStatus.fresh) + p.count(RowStatus.matched) + p.count(RowStatus.transfer);
    final isPdf = _pdf != null;
    // A PDF imports only when its own figures agree with the rows read, or,
    // when it prints none, once the user has checked it.
    final blocked = isPdf && (p.statement.problems.isNotEmpty || (!p.statement.verified && !_confirmed));
    (Status, String) label(RowStatus s) => switch (s) {
      RowStatus.fresh => (Status.info, 'New'),
      RowStatus.duplicate => (Status.warning, 'Already imported'),
      RowStatus.matched => (Status.good, 'Matches an entry'),
      RowStatus.transfer => (Status.good, 'Other side of a transfer'),
    };
    return SectionCard(
      title: '${_csv == null ? 2 : 3} · Review',
      hint: 'import.status',
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p.createsAccount) _newAccountPanel(p),
          if (isPdf) _checksPanel(p.statement),
          for (final c in p.conflicts)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: StatusLabel(Status.warning, 'Balance differs from one already recorded. $c'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${p.count(RowStatus.fresh)} new')),
                Chip(label: Text('${p.count(RowStatus.matched)} matched')),
                Chip(label: Text('${p.count(RowStatus.transfer)} transfers')),
                Chip(
                  label: Text('${p.rows.where((r) => r.status == RowStatus.duplicate).length} duplicates'),
                ),
                Chip(label: Text('Net ${money(p.statement.total, cur, signed: true)}')),
              ],
            ),
          ),
          for (final w in p.statement.warnings)
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: StatusLabel(Status.warning, w)),
          if (p.openingBalance != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: StatusLabel(
                Status.info,
                'Opening balance ${money(p.openingBalance!, cur)} on ${niceDate(p.openingDate!)} will be added.',
              ),
            ),
          if (p.statement.closingBalance != null && p.statement.closingDate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: StatusLabel(
                Status.info,
                'Closing balance ${money(p.statement.closingBalance!, cur)} on '
                '${niceDate(p.statement.closingDate!)} is recorded to tally against.',
              ),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          for (final r in p.rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                children: [
                  Checkbox(
                    value: r.include && r.status != RowStatus.duplicate,
                    onChanged: r.status == RowStatus.duplicate ? null : (v) => setState(() => r.include = v!),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text(niceDate(r.line.date), style: tabular.copyWith(fontSize: 13)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.line.text, overflow: TextOverflow.ellipsis),
                        StatusLabel(label(r.status).$1, label(r.status).$2),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: r.status == RowStatus.fresh
                        ? Hint(
                            'import.category',
                            child: DropdownButton<String>(
                              value: categories.any((c) => c.id == r.categoryId) ? r.categoryId : null,
                              isExpanded: true,
                              underline: const SizedBox.shrink(),
                              hint: const Text('Category'),
                              items: [
                                for (final c in categories)
                                  DropdownMenuItem(
                                    value: c.id,
                                    child: Text(
                                      '${c.name}${r.suggestion?.categoryId == c.id ? ' ✓' : ''}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) => setState(() => r.categoryId = v!),
                            ),
                          )
                        : Text('—', style: TextStyle(color: muted)),
                  ),
                  SizedBox(
                    width: 110,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Amount(r.line.amount, cur, signed: true, flow: true),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => setState(() => _plan = null), child: const Text('Back')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy || blocked || toCreate == 0 && p.openingBalance == null ? null : _commit,
                  icon: const Icon(Icons.done),
                  label: Text(p.createsAccount ? 'Create account and import $toCreate' : 'Import $toCreate'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _newAccountPanel(ImportPlan p) {
    final a = p.account;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatusLabel(Status.info, 'No account has this statement\'s number yet, so Artha will create one.'),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey(a.id),
            initialValue: a.name,
            decoration: InputDecoration(
              labelText: 'New account name',
              helperText: [subtypeOf(a.subtype).label, a.commodityId, ?a.number].join(' · '),
            ),
            onChanged: (v) {
              if (v.trim().isEmpty) return;
              _plan =
                  ImportPlan(
                      account: a.copyWith(name: v.trim()),
                      currency: p.currency,
                      statement: p.statement,
                      rows: p.rows,
                      createsAccount: true,
                    )
                    ..openingBalance = p.openingBalance
                    ..openingDate = p.openingDate;
            },
          ),
        ],
      ),
    );
  }

  /// What the statement's own figures say about the rows read from it.
  Widget _checksPanel(ParsedStatement st) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in st.checks) StatusLabel(Status.good, c),
        for (final pr in st.problems) StatusLabel(Status.critical, pr),
        if (st.problems.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Artha read rows that do not add up to the statement\'s own figures, so it will not import '
              'them. Use the bank\'s CSV or OFX download for this account instead.',
            ),
          )
        else if (st.checks.isEmpty)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v!),
            title: const Text(
              'This statement prints no balances to check against. I have compared the rows.',
            ),
          ),
      ],
    ),
  );

  Widget _resultCard() {
    final r = _result!;
    return Card(
      child: EmptyState(
        icon: Icons.task_alt,
        title: 'Imported',
        message:
            '${r.created} added, ${r.linked} linked to existing entries, ${r.merged} merged with transfers, '
            '${r.skipped} skipped.',
        actions: [
          FilledButton.tonal(
            onPressed: () => setState(() {
              _pdf = null;
              _recognised = null;
              _confirmed = false;
              _text = null;
              _fileName = null;
              _csv = null;
              _mapping = null;
              _plan = null;
              _result = null;
            }),
            child: const Text('Import another'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailPage(_accountId!))),
            child: const Text('Open account'),
          ),
        ],
      ),
    );
  }
}
