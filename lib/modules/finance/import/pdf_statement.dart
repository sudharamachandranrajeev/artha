/// Bank statements as PDFs: finds the transaction table from its column
/// headings, reads each row by position, and checks the result against the
/// statement's own running balance and totals. A statement is only marked
/// verified when every figure it prints agrees with the rows read.
library;

import 'package:brahma_core/brahma_core.dart';

import 'pdf_text.dart';
import 'statement.dart';

/// UK banks and card issuers, longest names first so "Bank of Scotland"
/// beats "Scotland" style partial hits.
const ukBanks = [
  'Bank of Scotland',
  'Royal Bank of Scotland',
  'Co-operative Bank',
  'American Express',
  'Nationwide',
  'First Direct',
  'Virgin Money',
  'Metro Bank',
  'Santander',
  'Barclaycard',
  'Barclays',
  'Starling',
  'Lloyds',
  'Halifax',
  'NatWest',
  'Revolut',
  'Monzo',
  'Chase',
  'HSBC',
  'TSB',
  'Ulster Bank',
  'Danske',
  'Tide',
];

enum _Col { date, description, out, inn, amount, balance }

const _labels = <_Col, List<String>>{
  _Col.out: ['paid out', 'money out', 'payments out', 'withdrawals', 'withdrawn', 'debits', 'debit', 'out'],
  _Col.inn: ['paid in', 'money in', 'payments in', 'deposits', 'credits', 'credit', 'in'],
  _Col.balance: ['balance'],
  _Col.amount: ['amount'],
  _Col.description: ['description', 'details', 'transaction', 'particulars', 'payee', 'merchant'],
  _Col.date: ['date'],
};

// Words that sit in heading rows beside the labels, such as Lloyds' "Card
// Ending | Date of transaction | Date entered | Description | Amount £".
const _headingFiller = {
  'card',
  'ending',
  'of',
  'entered',
  'posted',
  'transaction',
  'reference',
  'ref',
  'type',
};

class _Column {
  _Column(this.kind, this.left, this.right);
  final _Col kind;
  final double left;
  final double right;
  double get centre => (left + right) / 2;
}

final _money = RegExp(
  r'^\(?([-+]?)£?\$?€?(\d{1,3}(?:,\d{3})*|\d+)\.(\d{2})\)?(CR|DR|OD|-)?$',
  caseSensitive: false,
);
// HSBC marks overdrawn balances with a lone D.
final _marker = RegExp(r'^(CR|DR|OD|D)$', caseSensitive: false);

/// A money token: its value in pence and whether it is marked as a debit
/// ("-", "DR", "OD", brackets) or credit ("CR").
({int value, bool? credit})? _amount(String s, int scale) {
  final m = _money.firstMatch(s.replaceAll('£ ', '£'));
  if (m == null || scale != 2) return null;
  final value = int.parse(m.group(2)!.replaceAll(',', '')) * 100 + int.parse(m.group(3)!);
  final mark = (m.group(4) ?? '').toUpperCase();
  bool? credit;
  if (m.group(1) == '-' || mark == '-' || mark == 'DR' || mark == 'OD' || s.startsWith('(')) credit = false;
  if (mark == 'CR' || m.group(1) == '+') credit = true;
  return (value: value, credit: credit);
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

int? _monthOf(String s) {
  const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  final i = s.length >= 3 ? months.indexOf(s.substring(0, 3).toLowerCase()) : -1;
  return i < 0 ? null : i + 1;
}

/// A date at the start of [words]: "01 Oct 2026", "1 Oct 26", "1 Oct",
/// "01Oct26", "01/10/2026". Returns how many words it used.
({int day, int month, int? year, int used})? _dateAt(List<String> words) {
  if (words.isEmpty) return null;
  final w0 = words[0];
  var m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$').firstMatch(w0);
  if (m != null) return (day: int.parse(m[1]!), month: int.parse(m[2]!), year: _fullYear(m[3]!), used: 1);
  m = RegExp(r'^(\d{1,2})([A-Za-z]{3,9})(\d{2,4})?$').firstMatch(w0);
  if (m != null && _monthOf(m[2]!) != null) {
    return (
      day: int.parse(m[1]!),
      month: _monthOf(m[2]!)!,
      year: m[3] == null ? null : _fullYear(m[3]!),
      used: 1,
    );
  }
  final d = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?$').firstMatch(w0);
  if (d != null && words.length > 1) {
    final mon = RegExp(r'^[A-Za-z]{3,9}\.?$').hasMatch(words[1]) ? _monthOf(words[1]) : null;
    if (mon != null) {
      var y = words.length > 2 ? RegExp(r'^(\d{2}|\d{4})$').firstMatch(words[2]) : null;
      // "15 JUNE 15 JUNE" is two dates, not a date in 2015.
      if (y != null && words.length > 3 && _monthOf(words[3]) != null) y = null;
      return (
        day: int.parse(d[1]!),
        month: mon,
        year: y == null ? null : _fullYear(y[1]!),
        used: y == null ? 2 : 3,
      );
    }
  }
  return null;
}

int _fullYear(String y) => y.length == 2 ? 2000 + int.parse(y) : int.parse(y);

final _longDate = RegExp(r'(\d{1,2})(?:st|nd|rd|th)? ([A-Za-z]{3,9}),? (\d{4})');

String? _isoOf(int y, int m, int d) {
  final s = '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  return isValidIsoDate(s) ? s : null;
}

/// What a PDF statement says about itself, beyond its rows.
class _Summary {
  String? institution, sortCode, accountNumber, cardLast4, periodStart, periodEnd, currency;
  bool isCard = false;
  int? opening, closing, totalIn, totalOut;
}

const _openingWords = [
  'balance brought forward',
  'brought forward',
  'opening balance',
  'start balance',
  'previous balance',
  'balance from previous statement',
];
const _closingWords = [
  'balance carried forward',
  'carried forward',
  'closing balance',
  'end balance',
  'new balance',
];
const _inWords = [
  'total paid in',
  'total money in',
  'money in',
  'paid in',
  'total credits',
  'total deposits',
  'payments in',
];
const _outWords = [
  'total paid out',
  'total money out',
  'money out',
  'paid out',
  'total debits',
  'total withdrawals',
  'payments out',
];

bool _has(String norm, List<String> phrases) => phrases.any((p) => RegExp('(^| )$p( |\$)').hasMatch(norm));

_Summary _summarise(List<PdfLine> lines, Set<PdfLine> rows, int scale) {
  final s = _Summary();
  final all = lines.map((l) => l.text).join('\n');
  final lower = all.toLowerCase();
  for (final b in ukBanks) {
    if (RegExp('\\b${RegExp.escape(b.toLowerCase())}\\b').hasMatch(lower)) {
      s.institution = b;
      break;
    }
  }
  s.isCard = lower.contains('credit limit') || lower.contains('minimum payment');
  final sort =
      RegExp(
        r'sort\s*code[:\s]*(\d{2})\s*[- ]\s*(\d{2})\s*[- ]\s*(\d{2})',
        caseSensitive: false,
      ).firstMatch(all) ??
      RegExp(r'\b(\d{2})-(\d{2})-(\d{2})\b').firstMatch(all);
  if (sort != null) s.sortCode = '${sort[1]}-${sort[2]}-${sort[3]}';
  final acc =
      RegExp(r'account\s*(?:number|no\.?|num)[:\s]*(\d{8})\b', caseSensitive: false).firstMatch(all) ??
      (sort == null ? null : RegExp(r'\b(\d{8})\b').firstMatch(all.substring(sort.start)));
  if (acc != null) s.accountNumber = acc[1];
  final card =
      RegExp(
        r'(?:card\s*(?:number|ending(?:\s*in)?)[:\s]*)(?:[*xX•\d]{4}[\s-]*){0,3}(\d{4})\b',
        caseSensitive: false,
      ).firstMatch(all) ??
      RegExp(r'(?:[*xX•]{4}[\s-]*){2,3}(\d{4})\b').firstMatch(all) ??
      // "4670 62** **** 2413": masked groups mixed with digits.
      RegExp(r'\b(?=[\d\s]*[*xX•])(?:[\d*xX•]{4}[\s-]){3}(\d{4})\b').firstMatch(all);
  if (card != null) s.cardLast4 = card[1];
  if (all.contains('£') || all.contains('GBP')) {
    s.currency = 'GBP';
  } else if (all.contains('€') || all.contains('EUR')) {
    s.currency = 'EUR';
  }
  // Statement period: the latest full date written next to "to" or a dash.
  final period = RegExp(
    r'(\d{1,2}(?:st|nd|rd|th)? [A-Za-z]{3,9},? \d{4})\s*(?:to|-|–|until)\s*(\d{1,2}(?:st|nd|rd|th)? [A-Za-z]{3,9},? \d{4})',
    caseSensitive: false,
  ).firstMatch(all);
  if (period != null) {
    String? iso(String text) {
      final m = _longDate.firstMatch(text)!;
      final mon = _monthOf(m[2]!);
      return mon == null ? null : _isoOf(int.parse(m[3]!), mon, int.parse(m[1]!));
    }

    s.periodStart = iso(period[1]!);
    s.periodEnd = iso(period[2]!);
  } else {
    // Card statements print only their date: "Statement date 21 June 2026",
    // or the date alone under a line about the statement.
    for (var i = 0; i < lines.length && s.periodEnd == null; i++) {
      final norm = _norm(lines[i].text);
      final m = _longDate.firstMatch(lines[i].text);
      if (m == null) continue;
      final alone = m.group(0) == lines[i].text.trim();
      final near = [
        for (var j = i - 2; j < i; j++)
          if (j >= 0) _norm(lines[j].text),
      ];
      if (norm.contains('statement date') || (alone && near.any((n) => n.contains('statement')))) {
        final mon = _monthOf(m[2]!);
        if (mon != null) s.periodEnd = _isoOf(int.parse(m[3]!), mon, int.parse(m[1]!));
      }
    }
  }
  // Summary figures: a phrase followed by an amount on the same line.
  for (final l in lines) {
    final norm = _norm(l.text);
    // Inside a table only totals and forward balances are summary figures,
    // so "CASH PAID IN" on a row is never read as a total.
    if (rows.contains(l) &&
        !(_has(norm, _openingWords) || _has(norm, _closingWords) || norm.startsWith('total'))) {
      continue;
    }
    final amounts = <({int value, bool? credit})>[];
    for (var i = 0; i < l.words.length; i++) {
      final v = _amount(l.words[i].text, scale);
      if (v == null) continue;
      final next = i + 1 < l.words.length ? l.words[i + 1].text : '';
      amounts.add(_marker.hasMatch(next) ? (value: v.value, credit: next.toUpperCase() == 'CR') : v);
    }
    if (amounts.isEmpty) continue;
    final v = amounts.last;
    final signed = v.credit == false ? -v.value : v.value;
    if (s.opening == null && _has(norm, _openingWords)) s.opening = signed;
    if (_has(norm, _closingWords)) s.closing = signed;
    if (s.totalIn == null && _has(norm, _inWords) && !_has(norm, _outWords)) s.totalIn = v.value;
    if (s.totalOut == null && _has(norm, _outWords) && !_has(norm, _inWords)) s.totalOut = v.value;
  }
  return s;
}

/// The column headings of a transaction table, when [line] is one.
List<_Column>? _header(PdfLine line) {
  final words = line.words;
  final norms = [for (final w in words) _norm(w.text)];
  final cols = <_Column>[];
  final used = <int>{};
  for (final MapEntry(key: kind, value: labels) in _labels.entries) {
    for (final label in labels) {
      final parts = label.split(' ');
      for (var i = 0; i + parts.length <= words.length; i++) {
        if (used.contains(i)) continue;
        var ok = true;
        for (var j = 0; j < parts.length; j++) {
          if (norms[i + j] != parts[j]) ok = false;
        }
        if (!ok) continue;
        // A bare "in"/"out" counts only as a heading of its own.
        if (parts.length == 1 && (label == 'in' || label == 'out') && words.length > 8) continue;
        for (var j = 0; j < parts.length; j++) {
          used.add(i + j);
        }
        cols.add(_Column(kind, words[i].left, words[i + parts.length - 1].right));
        break;
      }
      if (cols.any((c) => c.kind == kind)) break;
    }
  }
  final kinds = cols.map((c) => c.kind).toSet();
  final money = kinds.intersection({_Col.out, _Col.inn, _Col.amount});
  if (!kinds.contains(_Col.date) || money.isEmpty) return null;
  // Most of the heading line should be headings, not a sentence that happens
  // to say "date" and "balance".
  final filler = [
    for (var i = 0; i < words.length; i++)
      if (!used.contains(i) && (norms[i].isEmpty || _headingFiller.contains(norms[i]))) i,
  ];
  if ((used.length + filler.length) * 2 < words.length) return null;
  return cols..sort((a, b) => a.left.compareTo(b.left));
}

class _Row {
  _Row(this.page, this.top, this.bottom);
  final int page;
  final double top;
  double bottom;
  String? date;
  final text = <String>[];
  final amounts = <_Col, ({int value, bool? credit})>{};
  bool get hasMoney =>
      amounts.containsKey(_Col.out) || amounts.containsKey(_Col.inn) || amounts.containsKey(_Col.amount);
}

/// Parses a PDF statement's lines. Throws [StatementFormatException] when no
/// transaction table can be found.
ParsedStatement parsePdfStatement(List<PdfLine> lines, {int scale = 2}) {
  if (scale != 2) throw StatementFormatException('PDF statements are read in currencies with pence or cents');
  // Lines under a table heading on the same page.
  final tableRows = <PdfLine>{};
  int? headerPage;
  for (final l in lines) {
    if (_header(l) != null) {
      headerPage = l.page;
    } else if (headerPage == l.page) {
      tableRows.add(l);
    }
  }
  final s = _summarise(lines, tableRows, scale);
  final warnings = <String>[];

  // Rows, page by page, below each page's table heading.
  final rows = <_Row>[];
  final pending = <({PdfLine line, String? date, List<String> text})>[];
  List<_Column>? cols;
  int? page;
  String? lastDate;
  ({int y, int m, int d})? yearHint;
  if (s.periodEnd != null) {
    final p = s.periodEnd!.split('-').map(int.parse).toList();
    yearHint = (y: p[0], m: p[1], d: p[2]);
  }

  String? resolve(({int day, int month, int? year, int used}) d) {
    var y = d.year;
    if (y == null) {
      if (yearHint == null) return null;
      y = yearHint.y;
      // A statement ending in January lists December rows from the year before.
      if (d.month > yearHint.m + 1) y--;
    }
    return _isoOf(y, d.month, d.day);
  }

  void flushPending({_Row? next}) {
    if (pending.isEmpty) return;
    final prev = rows.isEmpty ? null : rows.last;
    // Lines between two rows belong to whichever they sit closer to, unless
    // they open with a date (a new row's first line).
    final startsRow = pending.first.date != null;
    final gapPrev = prev == null || prev.page != pending.first.line.page
        ? double.infinity
        : pending.first.line.top - prev.bottom;
    final gapNext = next == null ? double.infinity : next.top - pending.last.line.words.first.bottom;
    final toNext = next != null && (startsRow || gapNext <= gapPrev);
    if (toNext) {
      next.text.insertAll(0, [for (final p in pending) ...p.text]);
      next.date ??= pending.first.date;
    } else if (prev != null && !startsRow) {
      prev.text.addAll([for (final p in pending) ...p.text]);
    }
    pending.clear();
  }

  for (final line in lines) {
    if (line.page != page) {
      flushPending();
      page = line.page;
      cols = null;
    }
    final h = _header(line);
    if (h != null) {
      flushPending();
      cols = h;
      continue;
    }
    final c = cols;
    if (c == null) continue;
    final moneyCols = c.where((x) => x.kind != _Col.date && x.kind != _Col.description).toList();
    final firstMoneyLeft = moneyCols.map((x) => x.left).reduce((a, b) => a < b ? a : b);
    final descCol = c.where((x) => x.kind == _Col.description).firstOrNull;
    final dateCol = c.firstWhere((x) => x.kind == _Col.date);
    final dateLimit = descCol != null && descCol.left > dateCol.left ? descCol.left - 1 : dateCol.right + 40;

    // Words in the date column, then money by column, the rest is text.
    final words = line.words;
    // Columns left of the date (a card's last digits) are not part of a row.
    final dateStart = dateCol.left - 8;
    final dateWords = [
      for (final w in words)
        if (w.left >= dateStart && w.left < dateLimit) w.text,
    ];
    final date = _dateAt(dateWords);
    // A second date (when the bank entered it) is not description text.
    final second = date == null ? null : _dateAt(dateWords.sublist(date.used));
    final skip = date == null ? 0 : date.used + (second?.used ?? 0);
    final amounts = <_Col, ({int value, bool? credit})>{};
    final text = <String>[];
    var skipped = 0;
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.right < dateStart) continue;
      if (skipped < skip && w.left < dateLimit) {
        skipped++;
        continue;
      }
      var a = w.right > firstMoneyLeft - 30 ? _amount(w.text, scale) : null;
      if (a != null && i + 1 < words.length && _marker.hasMatch(words[i + 1].text)) {
        final mark = words[i + 1].text.toUpperCase();
        a = (value: a.value, credit: mark == 'CR');
        i++;
      }
      if (a == null) {
        text.add(w.text);
        continue;
      }
      final centre = (w.left + w.right) / 2;
      double dist(_Column k) =>
          [((w.right - k.right).abs()), (centre - k.centre).abs()].reduce((x, y) => x < y ? x : y);
      final col = moneyCols.reduce((x, y) => dist(x) <= dist(y) ? x : y);
      if (amounts.containsKey(col.kind)) {
        throw StatementFormatException('Two amounts fall in one column on page ${line.page}: "${line.text}"');
      }
      amounts[col.kind] = a;
    }
    final iso = date == null ? null : resolve(date);
    if (date != null && iso == null) {
      throw StatementFormatException('Cannot tell the year of "${dateWords.take(date.used).join(' ')}"');
    }
    final norm = _norm(text.join(' '));
    // The whole line, as "New balance" can start left of the date column.
    final whole = _norm(line.text);
    final closes = _has(whole, _closingWords);
    final special = _has(whole, _openingWords) || closes || whole.startsWith('total');
    if (amounts.isEmpty) {
      if (special || norm.isEmpty) continue;
      if (iso != null) flushPending();
      pending.add((line: line, date: iso, text: [text.join(' ')]));
      continue;
    }
    if (special) {
      // Brought/carried forward rows and totals are not transactions; their
      // figures were read in the summary pass.
      flushPending();
      if (iso != null) lastDate = iso;
      // The table ends at its closing balance; notes below are not rows.
      if (closes) cols = null;
      continue;
    }
    final row = _Row(line.page, line.top, line.words.first.bottom)..date = iso;
    row.amounts.addAll(amounts);
    if (text.isNotEmpty) row.text.add(text.join(' '));
    if (!row.hasMoney) {
      // A balance on its own line closes the previous row's day.
      if (rows.isNotEmpty && rows.last.amounts[_Col.balance] == null && amounts[_Col.balance] != null) {
        rows.last.amounts[_Col.balance] = amounts[_Col.balance]!;
      }
      continue;
    }
    flushPending(next: row);
    row.date ??= lastDate;
    if (row.date == null) {
      throw StatementFormatException('A transaction on page ${line.page} has no date: "${line.text}"');
    }
    lastDate = row.date;
    rows.add(row);
  }
  flushPending();
  if (rows.isEmpty) {
    throw StatementFormatException(
      'No transaction table found. Artha looks for a heading row with Date and Paid in/out or Amount columns.',
    );
  }

  // Signs. Cards show purchases as positive debt; the ledger books them as
  // money out of the card account.
  final card = s.isCard;
  int? balanceOf(_Row r) {
    final b = r.amounts[_Col.balance];
    if (b == null) return null;
    if (card) return b.credit == true ? b.value : -b.value;
    return b.credit == false ? -b.value : b.value;
  }

  // Without a balance column order does not matter to the totals, and some
  // cards (Lloyds) list payments before purchases, so sort by date, keeping
  // printed order within a day.
  final noBalances = rows.every((r) => r.amounts[_Col.balance] == null);
  final ordered = noBalances
      ? ([for (var i = 0; i < rows.length; i++) (i, rows[i])]..sort(
              (a, b) =>
                  a.$2.date!.compareTo(b.$2.date!) != 0 ? a.$2.date!.compareTo(b.$2.date!) : a.$1 - b.$1,
            ))
            .map((e) => e.$2)
            .toList()
      : rows.length > 1 && rows.first.date!.compareTo(rows.last.date!) > 0
      ? rows.reversed.toList()
      : rows;
  final out = <StatementLine>[];
  int? running = s.opening == null ? null : (card ? -s.opening! : s.opening!);
  final unsignedAt = <int>[];
  for (final r in ordered) {
    final o = r.amounts[_Col.out], i = r.amounts[_Col.inn], a = r.amounts[_Col.amount];
    int amount;
    if (o != null || i != null) {
      amount = (i?.value ?? 0) - (o?.value ?? 0);
    } else if (a!.credit != null) {
      amount = a.credit! ? a.value : -a.value;
    } else {
      // Unsigned single amount: the running balance decides, else cards are
      // purchases and accounts are payments out.
      final bal = balanceOf(r);
      if (running != null && bal != null && running + a.value == bal && running - a.value != bal) {
        amount = a.value;
      } else if (running != null && bal != null && running - a.value == bal) {
        amount = -a.value;
      } else {
        amount = -a.value;
        if (!card) unsignedAt.add(out.length);
      }
    }
    final bal = balanceOf(r);
    if (running != null) running += amount;
    if (bal != null) running = bal;
    out.add(
      StatementLine(
        date: r.date!,
        amount: amount,
        payee: r.text.isEmpty ? '' : r.text.first,
        memo: r.text.skip(1).join(' '),
        balance: bal,
        currency: s.currency,
      ),
    );
  }

  final opening = s.opening == null ? null : (card ? -s.opening! : s.opening!);
  final closing = s.closing == null ? null : (card ? -s.closing! : s.closing!);
  final (checks, problems) = verifyStatement(
    out,
    opening: opening,
    closing: closing,
    totalIn: s.totalIn,
    totalOut: s.totalOut,
  );
  if (unsignedAt.isNotEmpty) {
    problems.add('${unsignedAt.length} amount(s) have no sign and no balance to settle it');
  }
  final derivedOpening = opening ?? _openingFromBalances(out);
  final start = s.periodStart != null && s.periodStart!.compareTo(out.first.date) <= 0
      ? s.periodStart!
      : out.first.date;
  final openingDate = addDays(start, -1);
  final closingDate = s.periodEnd != null && s.periodEnd!.compareTo(out.last.date) >= 0
      ? s.periodEnd!
      : out.last.date;
  final closingBalance = closing ?? out.last.balance;
  return ParsedStatement(
    lines: out,
    currency: s.currency,
    // A card statement's sort code and account number are where to send
    // payments, not the card itself.
    accountNumber: card && s.cardLast4 != null ? s.cardLast4 : s.accountNumber ?? s.cardLast4,
    sortCode: card && s.cardLast4 != null ? null : s.sortCode,
    institution: s.institution,
    isCard: card,
    openingBalance: derivedOpening,
    openingDate: openingDate,
    closingBalance: closingBalance,
    closingDate: closingDate,
    warnings: warnings,
    checks: checks,
    problems: problems,
    checkpoints: [
      if (derivedOpening != null) (date: openingDate, balance: derivedOpening),
      if (closingBalance != null) (date: closingDate, balance: closingBalance),
    ],
  );
}

int? _openingFromBalances(List<StatementLine> lines) {
  var sum = 0;
  for (final l in lines) {
    sum += l.amount;
    if (l.balance != null) return l.balance! - sum;
  }
  return null;
}

/// Checks rows against every figure the statement prints. Returns what
/// agreed and what did not; a statement with no figures to check has no
/// checks at all.
(List<String>, List<String>) verifyStatement(
  List<StatementLine> lines, {
  int? opening,
  int? closing,
  int? totalIn,
  int? totalOut,
}) {
  final checks = <String>[], problems = <String>[];
  final cur = lines.firstOrNull?.currency ?? 'GBP';
  String m(int v) => money(v, cur);
  final start = opening ?? _openingFromBalances(lines);
  final withBalance = lines.where((l) => l.balance != null).length;
  if (start != null && withBalance > 0) {
    var running = start, bad = 0;
    for (final l in lines) {
      running += l.amount;
      if (l.balance != null && l.balance != running) {
        if (bad++ < 3) {
          problems.add(
            'After "${l.text}" on ${l.date} the statement shows ${m(l.balance!)}, the rows add up to ${m(running)}',
          );
        }
        running = l.balance!;
      }
    }
    if (bad > 3) problems.add('…and ${bad - 3} more balance differences');
    if (bad == 0) checks.add('Running balance agrees on all $withBalance balance lines');
  }
  final total = lines.fold(0, (s, l) => s + l.amount);
  if (opening != null && closing != null) {
    if (opening + total == closing) {
      checks.add('Opening ${m(opening)} plus the rows gives the closing ${m(closing)}');
    } else {
      problems.add(
        'Opening ${m(opening)} plus the rows gives ${m(opening + total)}, but the closing balance is ${m(closing)}',
      );
    }
  }
  final ins = lines.where((l) => l.amount > 0).fold(0, (s, l) => s + l.amount);
  final outs = -lines.where((l) => l.amount < 0).fold(0, (s, l) => s + l.amount);
  if (totalIn != null) {
    totalIn == ins
        ? checks.add('Money in totals ${m(totalIn)}')
        : problems.add('Money in adds up to ${m(ins)}, the statement says ${m(totalIn)}');
  }
  if (totalOut != null) {
    totalOut == outs
        ? checks.add('Money out totals ${m(totalOut)}')
        : problems.add('Money out adds up to ${m(outs)}, the statement says ${m(totalOut)}');
  }
  return (checks, problems);
}

/// Several statements of one account as one, oldest first: their rows in
/// order, every balance they print as a checkpoint, and a check that each
/// statement opens where the one before it closed. A break means a missing
/// statement; it is reported, not refused, because each statement's own rows
/// were already verified.
ParsedStatement mergeStatements(List<ParsedStatement> statements) {
  if (statements.length == 1) return statements.single;
  String key(ParsedStatement s) => [s.sortCode ?? '', s.accountNumber ?? ''].join('/');
  if (statements.map(key).toSet().length > 1 || statements.any((s) => (s.accountNumber ?? '').isEmpty)) {
    throw StatementFormatException(
      'These statements are for different accounts, or one does not show its account number. '
      'Import one account at a time.',
    );
  }
  final sorted = [...statements]..sort((a, b) => a.lines.first.date.compareTo(b.lines.first.date));
  final checks = <String>[], problems = <String>[], warnings = <String>[];
  final cur = sorted.first.currency ?? 'GBP';
  for (var i = 0; i < sorted.length; i++) {
    final s = sorted[i];
    final label =
        '${niceDate(addDays(s.openingDate ?? s.lines.first.date, 1))} to ${niceDate(s.closingDate!)}';
    for (final c in s.checks) {
      checks.add('$label: $c');
    }
    for (final p in s.problems) {
      problems.add('$label: $p');
    }
    warnings.addAll(s.warnings);
    if (i == 0) continue;
    final prev = sorted[i - 1];
    if (prev.closingDate!.compareTo(s.openingDate!) > 0) {
      problems.add(
        'The statements to ${niceDate(prev.closingDate!)} and from ${niceDate(addDays(s.openingDate!, 1))} overlap',
      );
    } else if (prev.closingDate != s.openingDate) {
      warnings.add(
        'No statement for ${niceDate(addDays(prev.closingDate!, 1))} to ${niceDate(s.openingDate!)}; '
        'the account will not tally there until it is imported',
      );
    } else if (prev.closingBalance != null && s.openingBalance != null) {
      prev.closingBalance == s.openingBalance
          ? checks.add(
              'Statement for $label opens where the one before closed (${money(s.openingBalance!, cur)})',
            )
          : warnings.add(
              'The statement for $label opens at ${money(s.openingBalance!, cur)}, '
              'but the one before closed at ${money(prev.closingBalance!, cur)}',
            );
    }
  }
  return ParsedStatement(
    lines: [for (final s in sorted) ...s.lines],
    currency: sorted.first.currency,
    accountNumber: sorted.first.accountNumber,
    sortCode: sorted.first.sortCode,
    institution: sorted.first.institution,
    isCard: sorted.first.isCard,
    openingBalance: sorted.first.openingBalance,
    openingDate: sorted.first.openingDate,
    closingBalance: sorted.last.closingBalance,
    closingDate: sorted.last.closingDate,
    warnings: warnings,
    checks: checks,
    problems: problems,
    checkpoints: [for (final s in sorted) ...s.checkpoints],
  );
}
