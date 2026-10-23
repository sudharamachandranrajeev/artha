import 'dart:io';

import 'package:artha/db/database.dart';
import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
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

  test('seeding is idempotent and stamped below real writes', () async {
    await ledger.seedDefaults('GBP');
    final cats = await (db.select(db.accounts)..where((a) => a.id.like('cat.%'))).get();
    expect(cats.length, greaterThan(30));
    expect(cats.every((c) => c.hlc.startsWith('0000')), isTrue);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('seeds follow the synced seed currency, never the base currency', () async {
    final bank = await ledger.saveAccount(name: 'Monzo', subtype: 'current', commodityId: 'GBP');
    await ledger.saveEntry(
      simpleEntry(
        date: '2026-10-01',
        currency: 'GBP',
        accountId: bank,
        categoryId: 'cat.groceries',
        amount: 500,
      ),
    );
    await ledger.setUp('GBP');
    await ledger.setPref(basePrefKey, 'EUR');
    await ledger.setUp('EUR');
    Future<String> currencyOf(String id) async =>
        (await (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle()).commodityId;
    expect(await ledger.pref<String?>(seedCurrencyKey, null), 'GBP');
    expect(await currencyOf('cat.salary'), 'GBP');

    // A device that seeded in another currency before sync told it otherwise:
    // unused seeds switch, used ones keep their currency.
    await ledger.seedDefaults('USD');
    expect(await currencyOf('cat.salary'), 'USD');
    expect(await currencyOf('cat.groceries'), 'GBP');
  });

  test('budgets apply to expense categories and zero removes them', () async {
    await ledger.saveBudget('cat.groceries', 30000);
    expect(await ledger.budgets(), {'cat.groceries': 30000});
    await expectLater(ledger.saveBudget('cat.salary', 100), throwsA(isA<LedgerException>()));
    await expectLater(ledger.saveBudget('cat.groceries', -1), throwsA(isA<LedgerException>()));
    await ledger.saveBudget('cat.groceries', 0);
    expect(await ledger.budgets(), isEmpty);
  });

  test('balanced entries post, unbalanced ones are refused', () async {
    final bank = await ledger.saveAccount(name: 'Monzo', subtype: 'current', commodityId: 'GBP');
    await ledger.saveEntry(
      simpleEntry(
        date: '2026-10-01',
        currency: 'GBP',
        accountId: bank,
        categoryId: 'cat.groceries',
        amount: 4250,
      ),
    );
    expect(
      () => ledger.saveEntry(
        EntryInput(
          date: '2026-10-01',
          currency: 'GBP',
          postings: [PostingInput.cash(bank, -100), const PostingInput.cash('cat.groceries', 99)],
        ),
      ),
      throwsA(isA<LedgerException>()),
    );
    // Category lines are always in the entry currency, never converted.
    final usd = await ledger.saveAccount(name: 'Chase', subtype: 'current', commodityId: 'USD');
    expect(
      () => ledger.saveEntry(
        EntryInput(
          date: '2026-10-01',
          currency: 'USD',
          postings: [PostingInput.cash(usd, -100), const PostingInput('cat.groceries', 79, 100)],
        ),
      ),
      throwsA(isA<LedgerException>()),
    );
    final b = await ledger.balances();
    expect(b[bank]!.amount, -4250);
    expect(b['cat.groceries']!.amount, 4250);
    // Every write is queued for sync exactly once per row.
    final outbox = await db.select(db.outbox).get();
    expect(outbox.map((o) => o.entity).toSet(), {'accounts', 'entries'});
  });

  test('cross-currency transfer keeps both sides exact', () async {
    final gbp = await ledger.saveAccount(name: 'GBP', subtype: 'current', commodityId: 'GBP');
    final inr = await ledger.saveAccount(name: 'NRE', subtype: 'savings', commodityId: 'INR');
    await ledger.saveEntry(
      transferEntry(
        date: '2026-10-02',
        currency: 'GBP',
        fromId: gbp,
        toId: inr,
        fromAmount: 10000,
        toAmount: 1051230,
      ),
    );
    final b = await ledger.balances();
    expect(b[gbp]!.amount, -10000);
    expect(b[inr]!.amount, 1051230);
    expect(b[inr]!.value, 10000);
  });

  test('buy then sell books a pooled-cost gain', () async {
    final isa = await ledger.saveAccount(name: 'ISA cash', subtype: 'isa_stocks', commodityId: 'GBP');
    final sec = await ledger.createSecurity(
      code: 'VWRL',
      name: 'FTSE All-World',
      quoteCurrency: 'GBP',
      assetClass: 'equity',
    );
    final hold = await ledger.saveAccount(name: 'VWRL', subtype: 'security', commodityId: sec, parentId: isa);
    await ledger.saveEntry(
      buyEntry(
        date: '2026-01-05',
        currency: 'GBP',
        cashAccountId: isa,
        holdingAccountId: hold,
        units: 10000000,
        cost: 100000,
      ),
    );
    await ledger.saveEntry(
      buyEntry(
        date: '2026-02-05',
        currency: 'GBP',
        cashAccountId: isa,
        holdingAccountId: hold,
        units: 10000000,
        cost: 120000,
      ),
    );
    final pool = (await ledger.balances())[hold]!;
    final basis = pooledCost(pool.amount, pool.value, 5000000);
    expect(basis, 55000);
    await ledger.saveEntry(
      sellEntry(
        date: '2026-03-05',
        currency: 'GBP',
        cashAccountId: isa,
        holdingAccountId: hold,
        gainsAccountId: gainsId,
        units: 5000000,
        proceeds: 70000,
        costBasis: basis,
      ),
    );
    final b = await ledger.balances();
    expect(b[hold]!.amount, 15000000);
    expect(b[hold]!.value, 165000);
    expect(b[gainsId]!.amount, -15000);
  });

  test('deleting an entry removes its postings and tombstones it', () async {
    final bank = await ledger.saveAccount(name: 'Cash', subtype: 'cash', commodityId: 'GBP');
    final id = await ledger.saveEntry(
      simpleEntry(
        date: '2026-10-01',
        currency: 'GBP',
        accountId: bank,
        categoryId: 'cat.eating_out',
        amount: 900,
      ),
    );
    await ledger.deleteEntry(id);
    expect((await ledger.balances())[bank], isNull);
    final row = await (db.select(db.entries)..where((e) => e.id.equals(id))).getSingle();
    expect(row.deleted, isTrue);
    await expectLater(ledger.deleteAccount(bank), completes);
  });

  test('database file is encrypted and needs the right key', () async {
    final dir = await Directory.systemTemp.createTemp('artha');
    final file = File('${dir.path}/enc.db');
    final a = await openTestDatabase(file: file);
    await Ledger(await Store.open(a)).seedDefaults('GBP');
    await a.close();
    final header = String.fromCharCodes((await file.readAsBytes()).take(15));
    expect(header, isNot('SQLite format 3'));
    final wrong = await openTestDatabase(file: file, key: 'ff' * 32);
    await expectLater(wrong.select(wrong.accounts).get(), throwsA(anything));
    await wrong.close();
    final right = await openTestDatabase(file: file);
    expect(await right.select(right.accounts).get(), isNotEmpty);
    await right.close();
  });
}
