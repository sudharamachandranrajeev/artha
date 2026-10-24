import 'package:artha/modules/finance/import/pdf_statement.dart';
import 'package:artha/modules/finance/reports/reports.dart';
import 'package:artha/modules/finance/import/pdf_text.dart';
import 'package:artha/modules/finance/import/statement.dart';
import 'package:artha/db/database.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:artha/modules/finance/import/import_service.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

import 'pdf_fixture.dart';

Future<ParsedStatement> parse(List<List<PdfText>> pages) async =>
    parsePdfStatement(await readPdfLines(buildPdf(pages)));

/// Current account laid out like Barclays: no year on rows, the date shown
/// once per day, a balance only at the end of each day, detail lines under
/// a row.
List<List<PdfText>> barclays({String lastBalance = '1,887.51'}) => [
  [
    at(40, 40, 'Barclays Bank UK PLC', size: 12),
    at(40, 60, 'Mr A Customer'),
    at(320, 60, 'Sort code 20-12-34 Account number 12345678'),
    at(40, 80, 'Your statement 1 October 2026 to 31 October 2026'),
    at(40, 110, 'Start balance'),
    right(250, 110, '£1,000.00'),
    at(40, 122, 'Money in'),
    right(250, 122, '£2,500.00'),
    at(40, 134, 'Money out'),
    right(250, 134, '£1,612.49'),
    at(40, 146, 'End balance'),
    right(250, 146, '£1,887.51'),
    at(40, 180, 'Date'),
    at(90, 180, 'Description'),
    right(400, 180, 'Money out'),
    right(470, 180, 'Money in'),
    right(550, 180, 'Balance'),
    at(40, 195, '1 Oct'),
    at(90, 195, 'Start balance'),
    right(550, 195, '1,000.00'),
    at(40, 210, '1 Oct'),
    at(90, 210, 'Card payment to TESCO STORES 3042'),
    right(400, 210, '42.50'),
    at(90, 221, 'On 30 Sep'),
    at(90, 235, 'Direct debit to BRITISH GAS'),
    right(400, 235, '70.00'),
    right(550, 235, '887.50'),
    at(40, 255, '3 Oct'),
    at(90, 255, 'Bill payment from ACME LTD'),
    at(90, 266, 'Ref: SALARY OCT'),
    right(470, 255, '2,500.00'),
    right(550, 255, '3,387.50'),
  ],
  [
    at(40, 40, 'Barclays Bank UK PLC'),
    at(40, 80, 'Date'),
    at(90, 80, 'Description'),
    right(400, 80, 'Money out'),
    right(470, 80, 'Money in'),
    right(550, 80, 'Balance'),
    at(40, 95, '28 Oct'),
    at(90, 95, 'Standing order to LANDLORD RENT'),
    right(400, 95, '1,499.99'),
    right(550, 95, lastBalance),
    at(40, 115, '31 Oct'),
    at(90, 115, 'End balance'),
    right(550, 115, '1,887.51'),
    at(40, 700, 'Barclays Bank UK PLC. Authorised by the Prudential Regulation Authority.'),
  ],
];

/// One month of a current account: [rows] are (day, description, pence out
/// positive or in negative); every row carries the running balance.
List<List<PdfText>> month({
  required String from,
  required String to,
  required int opening,
  required List<(String, String, int)> rows,
  String account = '12345678',
}) {
  String m(int v) {
    final s = (v.abs() / 100).toStringAsFixed(2);
    final whole = s.split('.')[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '$whole.${s.split('.')[1]}';
  }

  var bal = opening;
  var closeIn = 0, closeOut = 0;
  final body = <PdfText>[];
  var y = 215.0;
  for (final (day, text, out) in rows) {
    bal -= out;
    out > 0 ? closeOut += out : closeIn -= out;
    body
      ..add(at(40, y, day))
      ..add(at(90, y, text))
      ..add(right(out > 0 ? 400 : 470, y, m(out)))
      ..add(right(550, y, '${bal < 0 ? '-' : ''}${m(bal)}'));
    y += 15;
  }
  return [
    [
      at(40, 40, 'Barclays Bank UK PLC', size: 12),
      at(320, 60, 'Sort code 20-12-34 Account number $account'),
      at(40, 80, 'Your statement $from to $to'),
      at(40, 110, 'Start balance'),
      right(250, 110, '£${m(opening)}'),
      at(40, 122, 'Money in'),
      right(250, 122, '£${m(closeIn)}'),
      at(40, 134, 'Money out'),
      right(250, 134, '£${m(closeOut)}'),
      at(40, 146, 'End balance'),
      right(250, 146, '£${m(bal)}'),
      at(40, 180, 'Date'),
      at(90, 180, 'Description'),
      right(400, 180, 'Money out'),
      right(470, 180, 'Money in'),
      right(550, 180, 'Balance'),
      ...body,
    ],
  ];
}

final sep = month(
  from: '1 September 2026',
  to: '30 September 2026',
  opening: 50000,
  rows: [('2 Sep', 'RENT', 30000), ('9 Sep', 'SALARY', -200000)],
);
final oct = month(
  from: '1 October 2026',
  to: '31 October 2026',
  opening: 220000,
  rows: [('2 Oct', 'RENT', 30000), ('11 Oct', 'TESCO', 4000), ('25 Oct', 'SALARY', -200000)],
);
final nov = month(
  from: '1 November 2026',
  to: '30 November 2026',
  opening: 386000,
  rows: [('2 Nov', 'RENT', 30000), ('14 Nov', 'ASDA', 6000)],
);

void main() {
  setUpAll(usePdfiumForTests);

  test('reads a Barclays-style statement and verifies every figure', () async {
    final st = await parse(barclays());
    expect(st.institution, 'Barclays');
    expect(st.sortCode, '20-12-34');
    expect(st.accountNumber, '12345678');
    expect(st.currency, 'GBP');
    expect(st.isCard, isFalse);
    expect(
      [for (final l in st.lines) (l.date, l.amount)],
      [('2026-10-01', -4250), ('2026-10-01', -7000), ('2026-10-03', 250000), ('2026-10-28', -149999)],
    );
    expect(st.lines[0].payee, 'Card payment to TESCO STORES 3042');
    expect(st.lines[0].memo, 'On 30 Sep');
    expect(st.lines[2].memo, 'Ref: SALARY OCT');
    expect(st.openingBalance, 100000);
    expect(st.closingBalance, 188751);
    expect(st.closingDate, '2026-10-31');
    expect(st.problems, isEmpty);
    expect(st.checks, hasLength(4));
    expect(st.verified, isTrue);
  });

  test('a misread figure is caught, never imported as verified', () async {
    final st = await parse(barclays(lastBalance: '1,877.51'));
    expect(st.verified, isFalse);
    expect(st.problems.first, contains('LANDLORD RENT'));
  });

  test('reads an HSBC-style statement with details above the amount and an overdraft', () async {
    final st = await parse([
      [
        at(40, 40, 'HSBC UK', size: 12),
        at(40, 60, 'Your Statement 1 September 2026 to 30 September 2026'),
        at(300, 80, 'Sortcode 40-11-22   Account Number 87654321'),
        at(40, 100, 'Opening Balance'),
        right(250, 100, '120.00'),
        at(40, 112, 'Payments In'),
        right(250, 112, '50.00'),
        at(40, 124, 'Payments Out'),
        right(250, 124, '300.00'),
        at(40, 136, 'Closing Balance'),
        right(250, 136, '130.00 D'),
        at(40, 170, 'Date'),
        at(100, 170, 'Payment type and details'),
        right(400, 170, 'Paid out'),
        right(470, 170, 'Paid in'),
        right(550, 170, 'Balance'),
        at(40, 185, '01 Sep 26'),
        at(100, 185, 'BALANCE BROUGHT FORWARD'),
        right(550, 185, '120.00'),
        at(40, 200, '02 Sep 26'),
        at(100, 200, 'DD BRITISH TELECOM'),
        at(100, 211, 'ACCOUNT 99'),
        right(400, 211, '300.00'),
        right(550, 211, '180.00 OD'),
        at(40, 226, '15 Sep 26'),
        at(100, 226, 'CR FRIEND'),
        right(470, 226, '50.00'),
        right(550, 226, '130.00 OD'),
        at(40, 241, '30 Sep 26'),
        at(100, 241, 'BALANCE CARRIED FORWARD'),
        right(550, 241, '130.00 OD'),
      ],
    ]);
    expect(st.institution, 'HSBC');
    expect(st.sortCode, '40-11-22');
    expect(st.accountNumber, '87654321');
    expect(
      [for (final l in st.lines) (l.date, l.amount, l.balance)],
      [('2026-09-02', -30000, -18000), ('2026-09-15', 5000, -13000)],
    );
    expect(st.lines[0].text, 'DD BRITISH TELECOM · ACCOUNT 99');
    expect(st.openingBalance, 12000);
    expect(st.closingBalance, -13000);
    expect(st.verified, isTrue, reason: st.problems.join('\n'));
  });

  test('reads a credit card statement as money owed', () async {
    final st = await parse([
      [
        at(40, 40, 'Barclaycard', size: 12),
        at(40, 60, 'Card ending 4321'),
        at(40, 72, 'Credit limit £5,000.00'),
        at(40, 84, 'Statement period 5 December 2026 to 4 January 2027'),
        at(40, 110, 'Previous balance'),
        right(250, 110, '£300.00'),
        at(40, 122, 'New balance'),
        right(250, 122, '£95.49'),
        at(40, 160, 'Date'),
        at(100, 160, 'Description'),
        right(550, 160, 'Amount'),
        at(40, 175, '20 Dec'),
        at(100, 175, 'AMAZON.CO.UK'),
        right(550, 175, '25.49'),
        at(40, 190, '28 Dec'),
        at(100, 190, 'PAYMENT RECEIVED - THANK YOU'),
        right(530, 190, '250.00'),
        at(535, 190, 'CR'),
        at(40, 205, '2 Jan'),
        at(100, 205, 'TFL TRAVEL'),
        right(550, 205, '20.00'),
      ],
    ]);
    expect(st.isCard, isTrue);
    expect(st.accountNumber, '4321');
    expect(
      [for (final l in st.lines) (l.date, l.amount)],
      [('2026-12-20', -2549), ('2026-12-28', 25000), ('2027-01-02', -2000)],
    );
    expect(st.openingBalance, -30000);
    expect(st.closingBalance, -9549);
    expect(st.verified, isTrue, reason: st.problems.join('\n'));
  });

  test('reads a Lloyds-style card statement: card column, two dates, payments first', () async {
    final st = await parse([
      [
        at(40, 40, 'Lloyds Bank Credit Card', size: 12),
        at(40, 60, 'Visa number 4670 62** **** 2413'),
        at(40, 72, 'Your credit limit £1,000'),
        at(40, 84, 'Your credit card statement'),
        at(40, 96, '21 June 2026'),
        at(40, 108, 'Minimum payment due £5.00'),
        at(40, 120, 'To reach your account by 16 July 2026'),
        at(40, 140, 'Bank Sort Code no: 77-29-00 Bank Account no: 00000000'),
      ],
      [
        at(42, 160, 'Card Ending'),
        at(96, 160, 'Date of transaction'),
        at(186, 160, 'Date entered'),
        at(252, 160, 'Description'),
        at(508, 160, 'Amount £'),
        at(252, 175, 'BALANCE FROM PREVIOUS STATEMENT'),
        right(544, 175, '183.28'),
        at(97, 190, '15 JUNE'),
        at(187, 190, '15 JUNE'),
        at(252, 190, 'DIRECT DEBIT PAYMENT THANK YOU'),
        right(544, 190, '183.28'),
        at(547, 190, 'CR'),
        at(341, 196, '-'),
        at(42, 205, '2413'),
        at(96, 205, '26 MAY'),
        at(186, 205, '26 MAY'),
        at(252, 205, 'Amazon.co.uk'),
        right(544, 205, '16.00'),
        at(42, 220, '2413'),
        at(96, 220, '09 JUNE'),
        at(186, 220, '10 JUNE'),
        at(252, 220, 'Proton Geneva CH'),
        right(544, 220, '10.39'),
        at(43, 240, 'New balance'),
        right(545, 240, '£26.39'),
        at(40, 260, 'If you do not pay off the full amount outstanding, we will allocate your payment'),
        at(40, 272, 'Purchases (Standard) 16.3640 17.65 26.39 0.00 N/A'),
      ],
    ]);
    expect(st.isCard, isTrue);
    expect(st.institution, 'Lloyds');
    // The sort code and account number are Lloyds' own, for payments.
    expect(st.accountNumber, '2413');
    expect(st.sortCode, isNull);
    expect(
      [for (final l in st.lines) (l.date, l.amount, l.payee)],
      [
        ('2026-05-26', -1600, 'Amazon.co.uk'),
        ('2026-06-09', -1039, 'Proton Geneva CH'),
        ('2026-06-15', 18328, 'DIRECT DEBIT PAYMENT THANK YOU'),
      ],
    );
    expect(st.openingDate, '2026-05-25');
    expect(st.closingDate, '2026-06-21');
    expect(st.openingBalance, -18328);
    expect(st.closingBalance, -2639);
    expect(st.verified, isTrue, reason: st.problems.join('\n'));
  });

  test('a PDF without a transaction table is refused', () async {
    expect(
      () async => parse([
        [at(40, 40, 'Annual summary of fees paid'), at(40, 60, 'Total £0.00')],
      ]),
      throwsA(isA<StatementFormatException>()),
    );
  });

  group('importing', () {
    late AppDatabase db;
    late Ledger ledger;
    late ImportService service;
    setUp(() async {
      db = await openTestDatabase();
      ledger = Ledger(await Store.open(db));
      await ledger.setUp('GBP');
      service = ImportService(ledger);
    });
    tearDown(() => db.close());

    /// Imports into the account the statement names, creating it when needed.
    Future<String> import(ParsedStatement st) async {
      final found = await service.matchAccounts(st);
      final plan = found.isEmpty
          ? await service.planFor(service.newAccountFor(st, 'GBP'), st, create: true)
          : await service.plan(found.first.id, st);
      await service.commit(plan);
      return plan.account.id;
    }

    Future<List<bool>> tally(String id) async {
      final r = await Reports.load(db, 'GBP');
      return [for (final t in await r.accountTally(id)) t.tallied];
    }

    test('an unknown statement creates its account; the next one is recognised', () async {
      final st = await parse(barclays());
      expect(await service.matchAccounts(st), isEmpty);
      final id = await import(st);
      final account = (await db.select(db.accounts).get()).singleWhere((a) => a.id == id);
      expect(account.name, 'Barclays current ••5678');
      expect(account.number, '20-12-34 12345678');
      expect((await ledger.balances())[id]!.amount, 188751);
      final again = await parse(barclays());
      expect((await service.matchAccounts(again)).map((a) => a.id), [id]);
      final replan = await service.plan(id, again);
      expect(replan.rows.every((r) => r.status == RowStatus.duplicate), isTrue);
      expect(replan.openingBalance, isNull);
    });

    test('a statement that does not add up is never committed', () async {
      final st = await parse(barclays(lastBalance: '1,877.51'));
      final plan = await service.planFor(service.newAccountFor(st, 'GBP'), st, create: true);
      await expectLater(service.commit(plan), throwsA(isA<StatementFormatException>()));
      expect((await db.select(db.accounts).get()).where((a) => a.subtype == 'current'), isEmpty);
    });

    test('monthly statements imported one by one tally at every statement', () async {
      final id = await import(await parse(oct));
      expect(await import(await parse(nov)), id);
      expect((await ledger.balances())[id]!.amount, 386000 - 36000);
      expect(await tally(id), [true, true, true]);
    });

    test('months in any order end up tallying once the gap is filled', () async {
      final id = await import(await parse(nov));
      expect(await tally(id), [true, true]);
      await import(await parse(sep));
      // September moved the opening balance back; October is still missing.
      expect((await tally(id)).contains(false), isTrue);
      await import(await parse(oct));
      expect(await tally(id), everyElement(isTrue));
      expect((await ledger.balances())[id]!.amount, 350000);
    });

    test('a whole period at once: merged, ordered, gaps reported', () async {
      final all = mergeStatements([await parse(nov), await parse(sep), await parse(oct)]);
      expect(all.problems, isEmpty);
      expect(all.warnings, isEmpty);
      expect(all.lines.first.date.compareTo(all.lines.last.date) < 0, isTrue);
      expect(all.lines, hasLength(7));
      expect(all.openingBalance, 50000);
      expect(all.closingBalance, 350000);
      expect(all.checks.where((c) => c.contains('opens where the one before closed')), hasLength(2));
      final id = await import(all);
      expect(await tally(id), everyElement(isTrue));

      final gap = mergeStatements([await parse(sep), await parse(nov)]);
      expect(gap.warnings.single, contains('No statement for 1 Oct 2026 to 31 Oct 2026'));
    });

    test('statements of different accounts are not merged', () async {
      final other = month(
        from: '1 October 2026',
        to: '31 October 2026',
        opening: 0,
        rows: [('3 Oct', 'X', 100)],
        account: '99999999',
      );
      expect(
        () async => mergeStatements([await parse(oct), await parse(other)]),
        throwsA(isA<StatementFormatException>()),
      );
    });
  });
}
