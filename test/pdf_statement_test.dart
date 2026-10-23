import 'package:artha/modules/finance/import/pdf_statement.dart';
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
    setUp(() async {
      db = await openTestDatabase();
      ledger = Ledger(await Store.open(db));
      await ledger.setUp('GBP');
    });
    tearDown(() => db.close());

    test('an unknown statement creates its account; the next one is recognised', () async {
      final service = ImportService(ledger);
      final st = await parse(barclays());
      expect(await service.matchAccounts(st), isEmpty);
      final plan = await service.planFor(service.newAccountFor(st, 'GBP'), st, create: true);
      final result = await service.commit(plan);
      expect(result.created, 4);

      final account = (await db.select(db.accounts).get()).singleWhere((a) => a.id == plan.account.id);
      expect(account.name, 'Barclays current ••5678');
      expect(account.subtype, 'current');
      expect(account.number, '20-12-34 12345678');
      expect(account.institution, 'Barclays');
      // Opening balance plus every row lands on the statement's end balance.
      expect((await ledger.balances())[account.id]!.amount, 188751);

      final again = await parse(barclays());
      final matches = await service.matchAccounts(again);
      expect(matches.map((a) => a.id), [account.id]);
      final replan = await service.plan(account.id, again);
      expect(replan.rows.every((r) => r.status == RowStatus.duplicate), isTrue);
      expect(replan.openingBalance, isNull);
    });

    test('a statement that does not add up is never committed', () async {
      final service = ImportService(ledger);
      final st = await parse(barclays(lastBalance: '1,877.51'));
      final plan = await service.planFor(service.newAccountFor(st, 'GBP'), st, create: true);
      await expectLater(service.commit(plan), throwsA(isA<StatementFormatException>()));
      expect((await db.select(db.accounts).get()).where((a) => a.subtype == 'current'), isEmpty);
    });
  });
}
