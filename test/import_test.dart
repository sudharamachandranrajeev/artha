import 'dart:io';

import 'package:artha/db/database.dart';
import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:artha/modules/finance/import/csv_statement.dart';
import 'package:artha/modules/finance/import/import_service.dart';
import 'package:artha/modules/finance/import/ofx_qif.dart';
import 'package:artha/modules/finance/import/statement.dart';
import 'package:artha/modules/finance/insights/categorizer.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

ParsedStatement csv(String name) {
  final rows = parseCsv(fixture(name));
  return CsvMapping.guess(rows)!.apply(rows, 2);
}

void main() {
  group('parsers', () {
    test('CSV handles quotes, CRLF and embedded delimiters', () {
      expect(parseCsv('a,"b,c","d ""q"""\r\n1,2,3\r\n'), [
        ['a', 'b,c', 'd "q"'],
        ['1', '2', '3'],
      ]);
      expect(detectDelimiter('a;b;c\n1;2;3'), ';');
    });

    test('Nationwide-style: preamble, paid in/out, newest first', () {
      final st = csv('nationwide.csv');
      expect(st.lines.map((l) => l.date), ['2026-10-01', '2026-10-03', '2026-10-05']);
      expect(st.lines.map((l) => l.amount), [-5000, 100000, -1950]);
      expect(st.openingBalance, 25000);
      expect(st.closingBalance, 118050);
      expect(st.closingDate, '2026-10-05');
      expect(st.warnings, isEmpty);
    });

    test('Monzo-style: signed amount, ids, payee and description', () {
      final st = csv('monzo.csv');
      expect(st.lines.length, 3);
      expect(st.lines.first.payee, 'Pret A Manger');
      expect(st.lines.first.ref, 'tx_0001');
      expect(st.lines.last.amount, 320000);
      expect(st.currency, 'GBP');
    });

    test('header-less CSV is mapped from its content', () {
      final rows = parseCsv('02/10/2026,COFFEE,-3.10,96.90\n01/10/2026,START,100.00,100.00\n');
      final st = CsvMapping.guess(rows)!.apply(rows, 2);
      expect(st.lines.map((l) => l.amount), [10000, -310]);
      expect(st.closingBalance, 9690);
    });

    test('OFX SGML with entities, FITIDs and ledger balance', () {
      final st = parseOfx(fixture('sample.ofx'), 2);
      expect(st.currency, 'GBP');
      expect(st.accountNumber, '12345678');
      expect(st.lines.map((l) => (l.date, l.amount, l.ref)), [
        ('2026-10-02', -2340, '2026100201'),
        ('2026-10-05', 10000, '2026100501'),
      ]);
      expect(st.lines.last.payee, 'M & S REFUND');
      expect((st.closingBalance, st.closingDate), (57660, '2026-10-10'));
    });

    test('QIF detects month-first dates and apostrophe years', () {
      final st = parseQif(fixture('sample.qif'), 2);
      expect(st.lines.map((l) => (l.date, l.amount)), [('2026-10-05', -1200), ('2026-10-15', 150000)]);
      expect(st.lines.last.memo, '#1001');
    });

    test('identical same-day lines get distinct refs', () {
      final l = StatementLine(date: '2026-10-01', amount: -300, payee: 'Coffee');
      final refs = lineRefs([l, l]);
      expect(refs[0], isNot(refs[1]));
      expect(lineRefs([l, l]), refs);
    });
  });

  group('categorizer', () {
    final cat = Categorizer(
      rules: const [CategoryRule('netflix', 'cat.subscriptions')],
      history: const [
        Example('TESCO STORES 3021 LONDON', 'cat.groceries'),
        Example('TESCO STORES 1102', 'cat.groceries'),
        Example('TFL TRAVEL CHARGE', 'cat.transport'),
        Example('ACME LTD SALARY', 'cat.salary'),
      ],
      directionOf: (id) => id == 'cat.salary' ? 'in' : 'out',
    );

    test('rule beats history, history knows merchants', () {
      expect(cat.suggest('NETFLIX.COM', -999)!.categoryId, 'cat.subscriptions');
      final s = cat.suggest('TESCO STORES 9999 LEEDS', -1250)!;
      expect((s.categoryId, s.source), ('cat.groceries', 'history'));
      expect(cat.suggest('TFL CHARGE', -280)!.categoryId, 'cat.transport');
    });

    test('direction filters categories', () {
      expect(cat.suggest('ACME LTD SALARY', 320000)!.categoryId, 'cat.salary');
      expect(cat.suggest('ACME LTD SALARY', -100), isNull);
      expect(cat.suggest('UNKNOWN MERCHANT', -100), isNull);
    });
  });

  group('import into the ledger', () {
    late AppDatabase db;
    late Ledger ledger;
    late ImportService svc;
    late String bank;

    setUp(() async {
      db = await openTestDatabase();
      ledger = Ledger(await Store.open(db));
      await ledger.seedDefaults('GBP');
      svc = ImportService(ledger);
      bank = await ledger.saveAccount(name: 'Nationwide', subtype: 'current', commodityId: 'GBP');
    });
    tearDown(() => db.close());

    test('first import tallies to the statement and re-import adds nothing', () async {
      final plan = await svc.plan(bank, csv('nationwide.csv'));
      expect(plan.openingBalance, 25000);
      expect(plan.openingDate, '2026-09-30');
      final r = await svc.commit(plan);
      expect(r.created, 3);
      final bal = await ledger.balances(asOf: '2026-10-05');
      expect(bal[bank]!.amount, 118050);
      final check = await db.select(db.balanceChecks).getSingle();
      expect((check.amount, check.date), (118050, '2026-10-05'));

      final again = await svc.plan(bank, csv('nationwide.csv'));
      expect(again.count(RowStatus.duplicate), 0); // excluded rows are not counted
      expect(again.rows.every((r) => r.status == RowStatus.duplicate), isTrue);
      expect(again.openingBalance, isNull);
      final r2 = await svc.commit(again);
      expect((r2.created, r2.skipped), (0, 3));
      expect((await ledger.balances())[bank]!.amount, 118050);
    });

    test('a hand-entered transaction is linked, not duplicated', () async {
      await ledger.saveEntry(
        simpleEntry(
          date: '2026-10-04',
          currency: 'GBP',
          accountId: bank,
          categoryId: 'cat.groceries',
          amount: 1950,
        ),
      );
      final plan = await svc.plan(bank, csv('nationwide.csv'));
      final tesco = plan.rows.firstWhere((r) => r.line.amount == -1950);
      expect(tesco.status, RowStatus.matched);
      final r = await svc.commit(plan);
      expect((r.created, r.linked), (2, 1));
    });

    test('a second file covering the same days links instead of duplicating', () async {
      await svc.commit(await svc.plan(bank, csv('nationwide.csv')));
      final before = (await ledger.balances())[bank]!.amount;
      final count = (await db.select(db.entries).get()).length;
      final csvRows = csv('nationwide.csv').lines;
      // The same payments as the PDF prints them: other wording, one dated a day later.
      final pdf = ParsedStatement(
        lines: [
          for (final (i, l) in csvRows.indexed)
            StatementLine(
              date: i == 1 ? addDays(l.date, 1) : l.date,
              amount: l.amount,
              payee: 'PDF ${l.payee}',
            ),
        ],
      );
      final plan = await svc.plan(bank, pdf);
      expect(plan.rows.every((r) => r.status == RowStatus.overlap), isTrue);
      expect(plan.openingBalance, isNull);
      expect((await svc.commit(plan)).linked, csvRows.length);
      expect((await ledger.balances())[bank]!.amount, before);
      expect((await db.select(db.entries).get()).length, count);
      // Now linked, the PDF re-imports as plain duplicates.
      final again = await svc.plan(bank, pdf);
      expect(again.rows.every((r) => r.status == RowStatus.duplicate), isTrue);
    });

    test('overlap prefers the same day and leaves days outside the statement alone', () async {
      StatementLine coffee(String date) => StatementLine(date: date, amount: -300, payee: 'COFFEE');
      await svc.commit(
        await svc.plan(bank, ParsedStatement(lines: [coffee('2026-10-02'), coffee('2026-10-05')])),
      );
      final plan = await svc.plan(
        bank,
        ParsedStatement(
          lines: [
            StatementLine(date: '2026-10-04', amount: -300, payee: 'Coffee shop'),
            StatementLine(date: '2026-10-05', amount: -300, payee: 'Coffee shop'),
            StatementLine(date: '2026-10-06', amount: -300, payee: 'Coffee shop'),
          ],
        ),
      );
      // 10-02 is before this statement starts, so only 10-05 overlaps, on its own day.
      expect([for (final r in plan.rows) r.status], [RowStatus.fresh, RowStatus.overlap, RowStatus.fresh]);
      plan.rows[1].keepSeparate();
      expect((plan.rows[1].status, plan.rows[1].existingEntryId), (RowStatus.fresh, null));
      final r = await svc.commit(plan);
      expect((r.created, r.linked), (3, 0));
    });

    test('both sides of a transfer merge into one entry', () async {
      final savings = await ledger.saveAccount(name: 'Savings', subtype: 'savings', commodityId: 'GBP');
      await svc.commit(
        await svc.plan(
          bank,
          ParsedStatement(
            lines: [StatementLine(date: '2026-10-06', amount: -20000, payee: 'TO SAVINGS')],
          ),
        ),
      );
      final plan = await svc.plan(
        savings,
        ParsedStatement(
          lines: [StatementLine(date: '2026-10-07', amount: 20000, payee: 'FROM CURRENT')],
        ),
      );
      expect(plan.rows.single.status, RowStatus.transfer);
      expect((await svc.commit(plan)).merged, 1);
      final b = await ledger.balances();
      expect(b[savings]!.amount, 20000);
      expect(b[uncategorizedId], isNull);
      final entries = await db.select(db.entries).get();
      expect(entries.length, 1);
      expect(entries.single.importRef!.split(' ').length, 2);
    });

    test('categories learned from history are suggested on the next import', () async {
      await ledger.saveEntry(
        simpleEntry(
          date: '2026-09-01',
          currency: 'GBP',
          accountId: bank,
          categoryId: 'cat.utilities',
          amount: 5000,
          payee: 'OCTOPUS ENERGY',
        ),
      );
      final plan = await svc.plan(bank, csv('nationwide.csv'));
      final octopus = plan.rows.firstWhere((r) => r.line.text.contains('OCTOPUS'));
      expect(octopus.categoryId, 'cat.utilities');
      final salary = plan.rows.firstWhere((r) => r.line.amount > 0);
      expect(salary.categoryId, otherIncomeId);
    });

    test('statement in another currency is refused', () async {
      expect(
        () => svc.plan(bank, ParsedStatement(lines: const [], currency: 'USD')),
        throwsA(isA<StatementFormatException>()),
      );
    });
  });
}
