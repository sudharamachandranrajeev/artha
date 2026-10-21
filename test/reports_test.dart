import 'dart:convert';

import 'package:artha/db/database.dart';
import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:artha/modules/finance/fx/fx_service.dart';
import 'package:artha/modules/finance/fx/price_book.dart';
import 'package:artha/modules/finance/reports/reports.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support.dart';

void main() {
  group('dates', () {
    test('calendar maths ignores daylight saving', () {
      expect(addDays('2026-03-30', -1), '2026-03-29');
      expect(addDays('2026-10-25', 1), '2026-10-26');
      expect(daysBetween('2026-03-28', '2026-03-30'), 2);
      expect(addMonths('2026-01-31', 1), '2026-02-28');
      expect(addMonths('2026-03-15', -3), '2025-12-15');
      expect(monthEnd('2028-02-10'), '2028-02-29');
      expect(isValidIsoDate('2026-02-31'), isFalse);
      expect(isValidIsoDate('2026-2-3'), isFalse);
      expect(isValidIsoDate('2026-12-31'), isTrue);
    });
  });

  group('price book', () {
    PriceBook book() => PriceBook({'GBP': 2, 'USD': 2, 'EUR': 2, 'JPY': 0, 'FUND': 6})
      ..add('EUR', 'GBP', '2026-10-01', Rate.parse('0.85'))
      ..add('EUR', 'USD', '2026-10-01', Rate.parse('1.10'))
      ..add('EUR', 'JPY', '2026-10-01', Rate.parse('160'))
      ..add('FUND', 'USD', '2026-10-02', Rate.parse('12.5'));

    test('direct, inverse and cross rates', () {
      final b = book();
      expect(b.rate('EUR', 'GBP', '2026-10-05'), Rate.parse('0.85'));
      expect(b.rate('GBP', 'EUR', '2026-10-05'), Rate.parse('0.85').inverse());
      expect(b.rate('USD', 'GBP', '2026-10-05'), Rate.parse('0.85') * Rate.parse('1.10').inverse());
      expect(b.convert(10000, 'USD', 'JPY', '2026-10-05'), 14545); // 100 USD -> 14,545 JPY
      // 2 fund units at 12.50 USD -> GBP through EUR.
      expect(b.convert(2000000, 'FUND', 'GBP', '2026-10-05'), 1932);
    });

    test('no rate before the first price, none for unknown commodities', () {
      expect(book().rate('USD', 'GBP', '2026-09-30'), isNull);
      expect(book().convert(100, 'GBP', 'XYZ', '2026-10-05'), isNull);
      expect(book().convert(100, 'GBP', 'GBP', '2000-01-01'), 100);
    });

    test('a fresh chain beats a stale direct rate', () {
      final b = book()..add('USD', 'GBP', '2026-09-10', Rate.parse('0.79'));
      expect(b.quote('USD', 'GBP', '2026-09-30'), (rate: Rate.parse('0.79'), date: '2026-09-10'));
      expect(b.quote('USD', 'GBP', '2026-10-05')!.date, '2026-10-01');
    });
  });

  group('FX service', () {
    late AppDatabase db;
    late Ledger ledger;
    setUp(() async {
      db = await openTestDatabase();
      ledger = Ledger(await Store.open(db));
      await ledger.seedDefaults('GBP');
      final usd = await ledger.saveAccount(name: 'Dollar', subtype: 'current', commodityId: 'USD');
      await ledger.saveEntry(
        simpleEntry(
          date: '2026-10-01',
          currency: 'USD',
          accountId: usd,
          categoryId: otherIncomeId,
          amount: -500,
        ),
      );
    });
    tearDown(() => db.close());

    String body(List<(String, String, num)> rates) => jsonEncode([
      for (final (d, q, r) in rates) {'date': d, 'base': 'EUR', 'quote': q, 'rate': r},
    ]);

    test('fetches only what is missing and stores exact rates', () async {
      final asked = <Uri>[];
      var reply = body([
        ('2026-10-01', 'GBP', 0.85433),
        ('2026-10-01', 'USD', 1.1327),
        ('2026-10-01', 'JPY', 160),
      ]);
      final fx = FxService(
        ledger,
        client: MockClient((req) async {
          asked.add(req.url);
          return http.Response(reply, 200);
        }),
      );
      expect(await fx.refresh(baseCurrency: 'GBP', today: '2026-10-02'), 2);
      expect(asked.single.host, 'api.frankfurter.dev');
      expect(asked.single.queryParameters, {
        'from': '2026-10-01',
        'to': '2026-10-02',
        'base': 'EUR',
        'quotes': 'GBP,USD',
        'providers': 'ECB',
      });
      final gbp = await (db.select(db.prices)..where((p) => p.quote.equals('GBP'))).getSingle();
      expect((gbp.rate, gbp.source, gbp.commodityId), ('0.85433', 'ecb', 'EUR'));

      reply = body([
        ('2026-10-01', 'GBP', 0.85433),
        ('2026-10-02', 'GBP', 0.853),
        ('2026-10-02', 'USD', 1.13),
      ]);
      expect(await fx.refresh(baseCurrency: 'GBP', today: '2026-10-02'), 2);
      expect(asked.last.queryParameters['from'], '2026-10-02');
      expect(await fx.refresh(baseCurrency: 'GBP', today: '2026-10-02'), 0);
      expect(asked.length, 2);
      final book = await PriceBook.load(db);
      expect(book.convert(10000, 'USD', 'GBP', '2026-10-02'), 7549);
    });

    test('rejects malformed or unexpected data', () {
      expect(() => FxService.parseRates('<html>', {'GBP'}), throwsA(isA<FxException>()));
      expect(() => FxService.parseRates('{"rates":{}}', {'GBP'}), throwsA(isA<FxException>()));
      expect(
        () => FxService.parseRates('[{"date":"2026-10-01","base":"USD","quote":"GBP","rate":0.7}]', {'GBP'}),
        throwsA(isA<FxException>()),
      );
      expect(
        () => FxService.parseRates('[{"date":"2026-10-01","base":"EUR","quote":"GBP","rate":-1}]', {'GBP'}),
        throwsA(isA<FxException>()),
      );
      expect(() => FxService(ledger, endpoint: 'http://example.com'), throwsArgumentError);
    });

    test('server errors surface as FxException', () async {
      final fx = FxService(ledger, client: MockClient((_) async => http.Response('busy', 503)));
      expect(fx.refresh(baseCurrency: 'GBP', today: '2026-10-02'), throwsA(isA<FxException>()));
    });
  });

  group('reports', () {
    late AppDatabase db;
    late Ledger ledger;
    late String bank, usd, card;

    setUp(() async {
      db = await openTestDatabase();
      ledger = Ledger(await Store.open(db));
      await ledger.seedDefaults('GBP');
      bank = await ledger.saveAccount(name: 'Current', subtype: 'current', commodityId: 'GBP');
      usd = await ledger.saveAccount(name: 'Dollar', subtype: 'current', commodityId: 'USD');
      card = await ledger.saveAccount(name: 'Card', subtype: 'credit_card', commodityId: 'GBP');
      Future<void> spend(String date, String acc, String cat, int amount) => ledger.saveEntry(
        simpleEntry(date: date, currency: 'GBP', accountId: acc, categoryId: cat, amount: amount),
      );
      await spend('2026-08-31', bank, openingBalancesId, -100000);
      await spend('2026-09-01', bank, 'cat.salary', -300000);
      await spend('2026-09-02', bank, 'cat.housing', 120000);
      await spend('2026-09-03', card, 'cat.eating_out', 5000);
      await ledger.saveEntry(
        transferEntry(
          date: '2026-09-10',
          currency: 'GBP',
          fromId: bank,
          toId: usd,
          fromAmount: 79000,
          toAmount: 100000,
        ),
      );
      await spend('2026-10-01', bank, 'cat.salary', -300000);
      for (final (q, r) in [('GBP', '0.85'), ('USD', '1.10')]) {
        await db
            .into(db.prices)
            .insert(
              PricesCompanion.insert(
                id: 'ecb/EUR/$q/2026-10-01',
                commodityId: 'EUR',
                quote: q,
                date: '2026-10-01',
                rate: r,
                source: 'ecb',
              ),
            );
      }
      await ledger.ensureCurrency('EUR');
    });
    tearDown(() => db.close());

    test('balance sheet balances through equity and revaluation', () async {
      final r = await Reports.load(db, 'GBP');
      final bs = await r.balanceSheet('2026-10-15');
      expect(bs.assets.map((l) => (l.account.name, l.amount, l.baseValue)), [
        ('Current', 501000, 501000),
        ('Dollar', 100000, 77273),
      ]);
      expect(bs.liabilities.single.baseValue, -5000);
      expect((bs.totalAssets, bs.totalLiabilities, bs.netWorth), (578273, 5000, 573273));
      expect((bs.contributed, bs.earnings, bs.revaluation), (100000, 475000, -1727));
      expect(bs.missingRates, isEmpty);

      // Before the ECB rates exist, the transfer's own rate values the dollars.
      final sept = await r.balanceSheet('2026-09-30');
      expect((sept.netWorth, sept.revaluation), (275000, 0));
    });

    test('trial balance: debits equal credits per currency', () async {
      final tb = await (await Reports.load(db, 'GBP')).trialBalance('2026-10-15');
      expect(tb.currencies, {'GBP'});
      expect(tb.debits('GBP'), tb.credits('GBP'));
      expect(tb.balanced, isTrue);
      expect(tb.rows.firstWhere((x) => x.account.id == 'cat.salary').credit, 600000);
    });

    test('income statement, monthly flows and net worth trend', () async {
      final r = await Reports.load(db, 'GBP');
      final pnl = await r.incomeStatement('2026-09-01', '2026-09-30');
      expect(pnl.income.map((l) => (l.account.id, l.amount)), [('cat.salary', 300000)]);
      expect(pnl.expenses.map((l) => (l.account.id, l.amount)), [
        ('cat.housing', 120000),
        ('cat.eating_out', 5000),
      ]);
      expect(pnl.net, 175000);

      final flows = await r.monthlyFlows('2026-10-15', months: 2);
      expect(flows.map((m) => (m.month, m.income, m.expenses, m.essential)), [
        ('2026-09', 300000, 125000, 120000),
        ('2026-10', 300000, 0, 0),
      ]);
      expect(flows.first.savingsRate, closeTo(0.5833, 0.0001));

      final trend = await r.netWorthTrend('2026-10-15', months: 3);
      expect(trend.map((p) => (p.date, p.netWorth)), [
        ('2026-08-31', 100000),
        ('2026-09-30', 275000),
        ('2026-10-15', 573273),
      ]);
    });

    test('categories hold each entry in its own currency', () async {
      // \$50 of groceries and a \$100 opening balance, both in a GBP-seeded book.
      await ledger.saveEntry(
        simpleEntry(
          date: '2026-10-02',
          currency: 'USD',
          accountId: usd,
          categoryId: 'cat.groceries',
          amount: 5000,
        ),
      );
      await ledger.saveEntry(
        simpleEntry(
          date: '2026-10-02',
          currency: 'USD',
          accountId: usd,
          categoryId: openingBalancesId,
          amount: -10000,
        ),
      );
      final r = await Reports.load(db, 'GBP');
      final pnl = await r.incomeStatement('2026-10-01', '2026-10-31');
      // 50 USD at 0.85 / 1.10 = 38.64 GBP, not 50 GBP.
      expect(pnl.expenses.map((l) => (l.account.id, l.amount)), [('cat.groceries', 3864)]);
      expect(pnl.missingRates, isEmpty);
      final bs = await r.balanceSheet('2026-10-15');
      expect(bs.contributed, 100000 + 7727);
      expect(await r.integrityProblems(), isEmpty);
    });

    test('account ledger keeps a running balance', () async {
      final r = await Reports.load(db, 'GBP');
      final all = await r.accountLedger(bank);
      expect(all.map((l) => l.balance), [100000, 400000, 280000, 201000, 501000]);
      final part = await r.accountLedger(bank, from: '2026-09-05');
      expect(part.map((l) => (l.amount, l.balance)), [(-79000, 201000), (300000, 501000)]);
      expect(part.first.counterparts, ['Dollar']);
    });

    test('tally compares the newest statement balance with the ledger', () async {
      Future<void> check(String acc, String date, int amount) => ledger.store.save(
        db.balanceChecks,
        BalanceChecksCompanion.insert(id: '$acc@$date', accountId: acc, date: date, amount: amount),
        '$acc@$date',
      );
      await check(bank, '2026-09-02', 1);
      await check(bank, '2026-10-01', 501000);
      await check(card, '2026-10-01', -5100);
      final t = {for (final x in await (await Reports.load(db, 'GBP')).tally()) x.account.id: x};
      expect(t[bank]!.tallied, isTrue);
      expect((t[card]!.tallied, t[card]!.difference), (false, 100));
    });

    test('integrity check finds damaged entries', () async {
      final r = await Reports.load(db, 'GBP');
      expect(await r.integrityProblems(), isEmpty);
      await db
          .into(db.entries)
          .insert(EntriesCompanion.insert(id: 'bad', date: '2026-10-02', currency: 'GBP'));
      await ledger.writePostings('bad', [
        PostingInput.cash(bank, 100),
        PostingInput.cash('cat.groceries', -99),
      ]);
      expect(await r.integrityProblems(), ['bad']);
      expect((await r.trialBalance('2026-10-15')).balanced, isFalse);

      // A category line converted on its own breaks the currency rule.
      await db
          .into(db.entries)
          .insert(EntriesCompanion.insert(id: 'fx', date: '2026-10-02', currency: 'USD'));
      await ledger.writePostings('fx', [
        PostingInput.cash(usd, -100),
        const PostingInput('cat.groceries', 79, 100),
      ]);
      expect(await r.integrityProblems(), unorderedEquals(['bad', 'fx']));
    });
  });
}
