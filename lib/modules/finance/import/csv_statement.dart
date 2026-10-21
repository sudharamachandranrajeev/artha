import 'dart:convert';

import 'package:brahma_core/brahma_core.dart';

import 'statement.dart';

/// RFC 4180 CSV: quoted fields, doubled quotes, CRLF/LF, any one-char
/// delimiter. Trailing empty lines are dropped.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final d = delimiter ?? detectDelimiter(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && field.isEmpty) {
      quoted = true;
    } else if (c == d) {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  while (rows.isNotEmpty && rows.last.every((f) => f.trim().isEmpty)) {
    rows.removeLast();
  }
  return rows;
}

/// The delimiter that splits the first lines most consistently.
String detectDelimiter(String text) {
  final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).take(20).toList();
  var best = ',';
  var bestScore = -1;
  for (final d in const [',', ';', '\t', '|']) {
    final counts = lines.map((l) => _countOutsideQuotes(l, d)).toList();
    if (counts.isEmpty || counts.last == 0) continue;
    final mode = counts.last;
    final score = counts.where((c) => c == mode).length * 100 + mode;
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return best;
}

int _countOutsideQuotes(String line, String d) {
  var n = 0;
  var q = false;
  for (final c in line.split('')) {
    if (c == '"') q = !q;
    if (!q && c == d) n++;
  }
  return n;
}

/// Which column holds what. Saved per account so the next import of the same
/// bank's file needs no questions.
class CsvMapping {
  CsvMapping({
    required this.headerRow,
    required this.date,
    this.amount,
    this.debit,
    this.credit,
    this.payee,
    this.memo,
    this.ref,
    this.balance,
    this.currency,
    this.dateOrder = DateOrder.dmy,
    this.invert = false,
    this.decimalSeparator = '.',
  });

  /// Index of the header row, or -1 when the file has none.
  int headerRow;
  int date;
  int? amount;
  int? debit;
  int? credit;
  int? payee;
  int? memo;
  int? ref;
  int? balance;
  int? currency;
  DateOrder dateOrder;

  /// Flip signs, for card exports that list spending as positive.
  bool invert;
  String decimalSeparator;

  bool get isValid => amount != null || debit != null || credit != null;

  Map<String, Object?> toJson() => {
    'headerRow': headerRow,
    'date': date,
    'amount': amount,
    'debit': debit,
    'credit': credit,
    'payee': payee,
    'memo': memo,
    'ref': ref,
    'balance': balance,
    'currency': currency,
    'dateOrder': dateOrder.name,
    'invert': invert,
    'decimalSeparator': decimalSeparator,
  };

  factory CsvMapping.fromJson(Map<String, Object?> j) => CsvMapping(
    headerRow: j['headerRow'] as int,
    date: j['date'] as int,
    amount: j['amount'] as int?,
    debit: j['debit'] as int?,
    credit: j['credit'] as int?,
    payee: j['payee'] as int?,
    memo: j['memo'] as int?,
    ref: j['ref'] as int?,
    balance: j['balance'] as int?,
    currency: j['currency'] as int?,
    dateOrder: DateOrder.values.byName(j['dateOrder'] as String? ?? 'dmy'),
    invert: j['invert'] as bool? ?? false,
    decimalSeparator: j['decimalSeparator'] as String? ?? '.',
  );

  /// Guesses a mapping from header names, falling back to the column
  /// contents for header-less files. Returns null if no date column exists.
  static CsvMapping? guess(List<List<String>> rows) {
    if (rows.isEmpty) return null;
    for (var r = 0; r < rows.length && r < 15; r++) {
      final m = _fromHeader(rows, r);
      if (m != null) return m;
    }
    return _fromContent(rows);
  }

  static const _names = {
    'date': [
      'date',
      'transactiondate',
      'posteddate',
      'postingdate',
      'completeddate',
      'bookingdate',
      'valuedate',
      'txndate',
      'startdate',
      'transdate',
    ],
    'amount': [
      'amount',
      'amountgbp',
      'transactionamount',
      'value',
      'amt',
      'netamount',
      'amountinr',
      'amounteur',
      'amountusd',
    ],
    'debit': [
      'debit',
      'debitamount',
      'paidout',
      'moneyout',
      'withdrawal',
      'withdrawals',
      'out',
      'spent',
      'withdrawalamt',
    ],
    'credit': [
      'credit',
      'creditamount',
      'paidin',
      'moneyin',
      'deposit',
      'deposits',
      'in',
      'received',
      'depositamt',
    ],
    'payee': ['name', 'counterparty', 'payee', 'merchant', 'merchantname', 'beneficiary'],
    'memo': [
      'description',
      'transactiondescription',
      'details',
      'narrative',
      'memo',
      'reference',
      'particulars',
      'narration',
      'transactiondetails',
      'remarks',
    ],
    'ref': ['transactionid', 'id', 'fitid', 'referencenumber', 'chqrefno', 'refno'],
    'balance': ['balance', 'runningbalance', 'balancegbp', 'closingbalance', 'availablebalance'],
    'currency': ['currency', 'ccy'],
  };

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

  static CsvMapping? _fromHeader(List<List<String>> rows, int r) {
    final cells = rows[r].map(_norm).toList();
    int? find(String key) {
      for (final n in _names[key]!) {
        final i = cells.indexOf(n);
        if (i >= 0) return i;
      }
      return null;
    }

    final date = find('date');
    final amount = find('amount');
    final debit = find('debit');
    final credit = find('credit');
    if (date == null || (amount == null && debit == null && credit == null)) return null;
    var payee = find('payee');
    var memo = find('memo');
    if (payee == null && memo == null) {
      // Fall back to the widest text column.
      memo = _widestText(rows.skip(r + 1), exclude: {date, ?amount, ?debit, ?credit});
    }
    if (payee == memo) payee = null;
    final dates = rows.skip(r + 1).map((row) => date < row.length ? row[date] : '');
    return CsvMapping(
      headerRow: r,
      date: date,
      amount: amount,
      debit: amount == null ? debit : null,
      credit: amount == null ? credit : null,
      payee: payee,
      memo: memo,
      ref: find('ref'),
      balance: find('balance'),
      currency: find('currency'),
      dateOrder: detectDateOrder(dates) ?? DateOrder.dmy,
      decimalSeparator: _guessDecimal(rows.skip(r + 1), amount ?? debit ?? credit!),
    );
  }

  static CsvMapping? _fromContent(List<List<String>> rows) {
    final width = rows.map((r) => r.length).fold(0, (a, b) => a > b ? a : b);
    int? date;
    final numeric = <int>[];
    for (var c = 0; c < width; c++) {
      final col = rows.map((r) => c < r.length ? r[c].trim() : '').where((v) => v.isNotEmpty).toList();
      if (col.isEmpty) continue;
      if (date == null && detectDateOrder(col) != null) {
        date = c;
      } else if (col.every((v) => parseMinor(v, 4) != null)) {
        numeric.add(c);
      }
    }
    if (date == null || numeric.isEmpty) return null;
    final dates = rows.map((r) => r[date!]);
    return CsvMapping(
      headerRow: -1,
      date: date,
      amount: numeric.first,
      balance: numeric.length > 1 ? numeric.last : null,
      memo: _widestText(rows, exclude: {date, ...numeric}),
      dateOrder: detectDateOrder(dates) ?? DateOrder.dmy,
    );
  }

  static int? _widestText(Iterable<List<String>> rows, {required Set<int> exclude}) {
    final width = <int, int>{};
    for (final r in rows.take(50)) {
      for (var c = 0; c < r.length; c++) {
        if (exclude.contains(c) || parseMinor(r[c], 4) != null) continue;
        width[c] = (width[c] ?? 0) + r[c].trim().length;
      }
    }
    if (width.isEmpty) return null;
    return width.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static String _guessDecimal(Iterable<List<String>> rows, int col) {
    var comma = 0, dot = 0;
    for (final r in rows.take(100)) {
      if (col >= r.length) continue;
      final v = r[col].trim();
      if (RegExp(r',\d{2}$').hasMatch(v)) comma++;
      if (RegExp(r'\.\d{1,2}$').hasMatch(v)) dot++;
    }
    return comma > dot ? ',' : '.';
  }

  /// Applies the mapping. Lines are returned oldest first; when a balance
  /// column exists it fixes the order and yields opening/closing balances.
  ParsedStatement apply(List<List<String>> rows, int scale) {
    final warnings = <String>[];
    final lines = <StatementLine>[];
    String cell(List<String> r, int? i) => i != null && i < r.length ? r[i].trim() : '';
    int? money(String v) => v.isEmpty ? null : parseMinor(v, scale, decimalSeparator: decimalSeparator);

    for (var i = headerRow + 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.every((f) => f.trim().isEmpty)) continue;
      final day = parseDate(cell(r, date), dateOrder);
      int? amount;
      if (this.amount != null) {
        amount = money(cell(r, this.amount));
      } else {
        final out = money(cell(r, debit));
        final inn = money(cell(r, credit));
        if (out != null || inn != null) amount = (inn ?? 0).abs() - (out ?? 0).abs();
      }
      if (day == null || amount == null) {
        warnings.add('Row ${i + 1} skipped: ${day == null ? 'unreadable date' : 'no amount'}');
        continue;
      }
      if (invert) amount = -amount;
      lines.add(
        StatementLine(
          date: day,
          amount: amount,
          payee: cell(r, payee),
          memo: cell(r, memo),
          ref: cell(r, ref),
          balance: money(cell(r, balance)),
          currency: cell(r, currency).isEmpty ? null : cell(r, currency).toUpperCase(),
        ),
      );
    }
    return orderLines(lines, warnings);
  }
}

/// Puts lines oldest first and derives opening/closing balances from a
/// running-balance column when present (checking it adds up).
ParsedStatement orderLines(List<StatementLine> lines, List<String> warnings) {
  if (lines.isEmpty) return ParsedStatement(lines: lines, warnings: warnings);
  final withBal = lines.every((l) => l.balance != null);
  var ordered = lines;
  if (withBal && lines.length > 1) {
    var asc = 0, desc = 0;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].balance == lines[i - 1].balance! + lines[i].amount) asc++;
      if (lines[i - 1].balance == lines[i].balance! + lines[i - 1].amount) desc++;
    }
    if (desc > asc) ordered = lines.reversed.toList();
    final good = desc > asc ? desc : asc;
    if (good < lines.length - 1) {
      warnings.add('Running balance does not add up on ${lines.length - 1 - good} line(s)');
    }
  } else if (lines.first.date.compareTo(lines.last.date) > 0) {
    ordered = lines.reversed.toList();
  }
  // Stable sort by date keeps the bank's order within a day.
  final indexed = ordered.asMap().entries.toList()
    ..sort((a, b) {
      final c = a.value.date.compareTo(b.value.date);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  ordered = indexed.map((e) => e.value).toList();
  return ParsedStatement(
    lines: ordered,
    warnings: warnings,
    currency: ordered.first.currency,
    openingBalance: withBal ? ordered.first.balance! - ordered.first.amount : null,
    closingBalance: withBal ? ordered.last.balance : null,
    closingDate: ordered.last.date,
  );
}
