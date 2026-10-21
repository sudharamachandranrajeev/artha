import 'package:brahma_core/brahma_core.dart';

import 'csv_statement.dart' show orderLines;
import 'statement.dart';

/// OFX / QFX, both SGML (OFX 1.x, unclosed tags) and XML (OFX 2.x).
/// Reads transactions, currency, account id and the ledger balance.
ParsedStatement parseOfx(String text, int scale) {
  if (!text.toUpperCase().contains('<OFX>')) {
    throw StatementFormatException('Not an OFX file');
  }
  String? tag(String block, String name) {
    final m = RegExp('<$name>([^<\\r\\n]*)', caseSensitive: false).firstMatch(block);
    final v = m?.group(1)?.trim();
    return v == null || v.isEmpty ? null : _unescape(v);
  }

  int? amount(String? v) =>
      v == null ? null : parseMinor(v, scale) ?? parseMinor(v, scale, decimalSeparator: ',');
  String? date(String? v) => v == null || v.length < 8 ? null : parseDate(v.substring(0, 8), DateOrder.ymd);

  final warnings = <String>[];
  final lines = <StatementLine>[];
  final blocks = RegExp(
    r'<STMTTRN>(.*?)(?=</STMTTRN>|<STMTTRN>|</BANKTRANLIST>)',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(text);
  for (final b in blocks) {
    final body = b.group(1)!;
    final d = date(tag(body, 'DTPOSTED') ?? tag(body, 'DTUSER'));
    final a = amount(tag(body, 'TRNAMT'));
    if (d == null || a == null) {
      warnings.add('Skipped a transaction with ${d == null ? 'no date' : 'no amount'}');
      continue;
    }
    lines.add(
      StatementLine(
        date: d,
        amount: a,
        payee: tag(body, 'NAME') ?? tag(body, 'PAYEE') ?? '',
        memo: tag(body, 'MEMO') ?? '',
        ref: tag(body, 'FITID') ?? '',
      ),
    );
  }
  final ordered = orderLines(lines, warnings);
  final ledger = RegExp(
    r'<LEDGERBAL>(.*?)(?:</LEDGERBAL>|<AVAILBAL>|</STMTRS>|</CCSTMTRS>|$)',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(text)?.group(1);
  final closing = ledger == null ? null : amount(tag(ledger, 'BALAMT'));
  final closingDate = ledger == null ? null : date(tag(ledger, 'DTASOF'));
  return ParsedStatement(
    lines: ordered.lines,
    warnings: warnings,
    currency: tag(text, 'CURDEF')?.toUpperCase(),
    accountNumber: tag(text, 'ACCTID'),
    closingBalance: closing,
    closingDate: closing == null ? ordered.closingDate : (closingDate ?? ordered.closingDate),
  );
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");

/// Quicken Interchange Format. Day/month order is detected over the whole
/// file because QIF never says which it uses.
ParsedStatement parseQif(String text, int scale) {
  final records = <Map<String, String>>[];
  var cur = <String, String>{};
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    if (line.isEmpty || line.startsWith('!')) continue;
    if (line == '^') {
      if (cur.isNotEmpty) records.add(cur);
      cur = {};
      continue;
    }
    final code = line[0];
    // Split transactions (S/E/$) are summarised by their total T line.
    if ('DTUPMNL'.contains(code)) cur.putIfAbsent(code, () => line.substring(1).trim());
  }
  if (cur.isNotEmpty) records.add(cur);
  if (records.isEmpty) throw StatementFormatException('No QIF transactions found');

  final order = detectDateOrder(records.map((r) => r['D'] ?? '')) ?? DateOrder.dmy;
  final warnings = <String>[];
  final lines = <StatementLine>[];
  for (final r in records) {
    final d = parseDate(r['D'] ?? '', order);
    final a = parseMinor(r['T'] ?? r['U'] ?? '', scale);
    if (d == null || a == null) {
      warnings.add('Skipped a record with ${d == null ? 'no date' : 'no amount'}');
      continue;
    }
    // QIF has no transaction id; cheque numbers repeat, so they stay in memo.
    final memo = [r['M'], if (r['N'] != null) '#${r['N']}'].whereType<String>().join(' ');
    lines.add(StatementLine(date: d, amount: a, payee: r['P'] ?? '', memo: memo));
  }
  return orderLines(lines, warnings);
}
