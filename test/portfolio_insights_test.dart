import 'package:artha/db/database.dart';
import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:artha/modules/finance/fx/price_book.dart';
import 'package:artha/modules/finance/insights/catalogue.dart';
import 'package:artha/modules/finance/insights/insights.dart';
import 'package:artha/modules/finance/portfolio/portfolio.dart';
import 'package:artha/modules/finance/reports/reports.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late AppDatabase db;
  late Ledger ledger;

  setUp(() async {
    db = await openTestDatabase();
    ledger = Ledger(await Store.open(db));
    await ledger.seedDefaults('GBP');
  });
  tearDown(() => db.close());

  Future<void> book(String date, String acc, String cat, int amount, [String payee = '']) => ledger.saveEntry(
    simpleEntry(date: date, currency: 'GBP', accountId: acc, categoryId: cat, amount: amount, payee: payee),
  );

  test('apportion splits exactly', () {
    expect(apportion(100, {'a': 1, 'b': 1, 'c': 1}), {'a': 34, 'b': 33, 'c': 33});
    expect(apportion(-100, {'a': 1, 'b': 1, 'c': 1}).values.fold(0, (s, v) => s + v), -100);
    expect(apportion(0, {'a': 1}), isEmpty);
  });

  group('portfolio', () {
    late Portfolio p;
    const balanced = {'equity': 6000, 'bond': 3000, 'cash': 1000};

    setUp(() async {
      final bank = await ledger.saveAccount(name: 'Current', subtype: 'current', commodityId: 'GBP');
      final isa = await ledger.saveAccount(name: 'ISA', subtype: 'isa_stocks', commodityId: 'GBP');
      final bonds = await ledger.saveAccount(name: 'Gilts', subtype: 'bonds', commodityId: 'GBP');
      final fund = await ledger.createSecurity(
        code: 'vwrl',
        name: 'Global All-Cap',
        quoteCurrency: 'GBP',
        assetClass: 'equity',
      );
      final holding = await ledger.saveAccount(
        name: 'Global All-Cap',
        subtype: 'security',
        commodityId: fund,
        parentId: isa,
      );
      await book('2026-01-01', bank, openingBalancesId, -1000000);
      await ledger.saveEntry(
        transferEntry(date: '2026-01-02', currency: 'GBP', fromId: bank, toId: isa, fromAmount: 600000),
      );
      await ledger.saveEntry(
        transferEntry(date: '2026-01-02', currency: 'GBP', fromId: bank, toId: bonds, fromAmount: 100000),
      );
      await ledger.saveEntry(
        buyEntry(
          date: '2026-01-03',
          currency: 'GBP',
          cashAccountId: isa,
          holdingAccountId: holding,
          units: 100000000,
          cost: 500000,
        ),
      );
      final prices = await PriceBook.load(db)
        ..add(fund, 'GBP', '2026-10-10', Rate.parse('55'));
      p = await Portfolio.load(db, prices, base: 'GBP', asOf: '2026-10-15');
    });

    test('values holdings, cost and gain', () {
      expect(p.total, 1050000);
      final fund = p.positions.first;
      expect((fund.assetClass, fund.value, fund.cost, fund.gain), ('equity', 550000, 500000, 50000));
      expect(fund.priceDate, '2026-10-10');
      expect(p.byClass, {'equity': 550000, 'cash': 400000, 'bond': 100000});
      expect(p.byCurrency, {'GBP': 1050000});
      expect(p.effectiveHoldings, closeTo(2.67, 0.01));
    });

    test('drift, rebalance and new money', () {
      final drift = {for (final d in p.drift(balanced)) d.assetClass: d};
      expect(drift['cash']!.driftBp, 2810);
      expect(drift['bond']!.outOfBand, isTrue);
      expect(p.rebalance(balanced), {'equity': 80000, 'bond': 215000, 'cash': -295000});
      expect(p.allocateNewMoney(balanced, 100000), {'equity': 36364, 'bond': 63636});
      // Once gaps are closed, the surplus follows the targets.
      expect(p.allocateNewMoney(balanced, 5000000).values.fold(0, (s, v) => s + v), 5000000);
    });
  });

  group('patterns', () {
    test('recurring payments: steady ones found, irregular and lapsed ones not', () {
      final txns = [
        for (final m in ['06', '07', '08', '09', '10'])
          Txn('2026-$m-03', 'NETFLIX.COM', -1099, 'cat.subscriptions'),
        for (final d in ['2026-08-01', '2026-08-04', '2026-09-20', '2026-10-01'])
          Txn(d, 'PUREGYM DAY PASS', -800, 'cat.health'),
        for (final m in ['01', '02', '03', '04'])
          Txn('2026-$m-10', 'OLD MAGAZINE', -500, 'cat.subscriptions'),
      ];
      final r = detectRecurring(txns, '2026-10-15');
      expect(r.map((x) => (x.label, x.cadence, x.amount, x.nextDate)), [
        ('NETFLIX.COM', Cadence.monthly, -1099, '2026-11-03'),
      ]);
    });

    test('anomalies need history and a real jump', () {
      final spend = {
        'cat.groceries': {'2026-06': 30000, '2026-07': 31000, '2026-08': 29000, '2026-10': 60000},
        'cat.eating_out': {'2026-06': 10000, '2026-07': 11000, '2026-08': 9000, '2026-10': 12000},
        'cat.travel': {'2026-08': 1000, '2026-10': 90000},
      };
      expect(detectAnomalies(spend, '2026-10').map((a) => (a.categoryId, a.usual)), [
        ('cat.groceries', 30000),
      ]);
    });

    test('UK tax year boundaries', () {
      expect(ukTaxYearStart('2026-04-05'), '2025-04-06');
      expect(ukTaxYearStart('2026-04-06'), '2026-04-06');
    });
  });

  group('insights and knowledge base', () {
    late InsightEngine engine;

    setUp(() async {
      final bank = await ledger.saveAccount(name: 'Current', subtype: 'current', commodityId: 'GBP');
      final card = await ledger.saveAccount(
        name: 'Card',
        subtype: 'credit_card',
        commodityId: 'GBP',
        meta: {'creditLimit': 100000, 'interestRate': 24.9},
      );
      for (var m = 4; m <= 10; m++) {
        final ym = '2026-${m.toString().padLeft(2, '0')}';
        await book('$ym-01', bank, 'cat.salary', -300000, 'ACME PAYROLL');
        await book('$ym-02', bank, 'cat.housing', 120000, 'LANDLORD RENT');
        await book('$ym-03', bank, 'cat.subscriptions', 1099, 'NETFLIX');
        await book('$ym-10', bank, 'cat.groceries', 30000, 'TESCO STORES');
        await book('$ym-11', bank, 'cat.remittance', 140000, 'FAMILY SUPPORT');
      }
      await book('2026-10-05', card, 'cat.eating_out', 50000, 'DISHOOM');
      final reports = await Reports.load(db, 'GBP');
      final portfolio = await Portfolio.load(db, reports.prices, base: 'GBP', asOf: '2026-10-15');
      engine = InsightEngine(db, reports, portfolio, '2026-10-15');
    });

    test('metrics describe financial health', () async {
      final m = await engine.metrics();
      expect((m.monthlyIncome, m.monthlySpend, m.monthlyEssential), (300000, 291099, 150000));
      expect(m.savingsRate, closeTo(0.0297, 0.0001));
      expect(m.emergencyMonths, closeTo(62307 / 150000, 0.0001));
      expect(m.creditUtilisation, 0.5);
      expect(m.isaUsed, isNull);
    });

    test('insights cover habits, health and debt', () async {
      final kinds = (await engine.generate()).map((i) => i.kind).toList();
      expect(kinds.where((k) => k == 'recurring').length, 4);
      expect(
        kinds,
        containsAll([
          'income_pattern',
          'emergency_fund',
          'savings_rate',
          'credit_utilisation',
          'expensive_debt',
        ]),
      );
    });

    test('dismissed facts stay dismissed and stale ones retire', () async {
      final kb = KnowledgeBase(ledger);
      await kb.apply(await engine.generate());
      final ranked = await kb.ranked();
      expect(ranked.first.kind, 'emergency_fund');
      await kb.feedback('health/emergency_fund', useful: false);
      await kb.apply(await engine.generate());
      expect((await kb.ranked()).map((f) => f.id), isNot(contains('health/emergency_fund')));
      final note = await kb.remember('goal', 'House deposit by 2029');
      await kb.apply([]);
      final left = await kb.facts();
      expect(left.map((f) => f.id).toSet(), {'health/emergency_fund', note});
    });
  });

  test('every catalogue option names a known asset class', () {
    for (final o in investmentOptions) {
      expect(assetClasses.keys, contains(o.assetClass), reason: o.id);
      expect(o.risk, inInclusiveRange(1, 7));
    }
    expect(isValidIsoDate(addDays(ukTaxYearStart('2026-10-15'), 364)), isTrue);
  });
}
