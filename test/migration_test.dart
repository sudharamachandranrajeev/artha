import 'dart:io';

import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('a version 1 database gains the review flag, rename rules and recurrings, keeping its data', () async {
    final file = File('${(await Directory.systemTemp.createTemp('artha')).path}/t.db');
    var db = await openTestDatabase(file: file);
    var ledger = Ledger(await Store.open(db));
    await ledger.seedDefaults('GBP');
    final bank = await ledger.saveAccount(name: 'Bank', subtype: 'current', commodityId: 'GBP');
    final id = await ledger.saveEntry(
      simpleEntry(
        date: '2026-10-01',
        currency: 'GBP',
        accountId: bank,
        categoryId: 'cat.groceries',
        amount: 500,
        payee: 'TESCO',
      ),
    );
    await ledger.saveRule(pattern: 'tesco', accountId: 'cat.groceries');
    // Back to the version 1 shape.
    await db.customStatement('ALTER TABLE entries DROP COLUMN reviewed');
    await db.customStatement('ALTER TABLE rules DROP COLUMN payee');
    await db.customStatement('DROP TABLE recurrings');
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();

    db = await openTestDatabase(file: file);
    ledger = Ledger(await Store.open(db));
    final e = await (db.select(db.entries)..where((x) => x.id.equals(id))).getSingle();
    expect((e.payee, e.reviewed), ('TESCO', true));
    final r = (await ledger.rules()).single;
    expect((r.pattern, r.accountId, r.payee), ('tesco', 'cat.groceries', null));
    expect(await db.select(db.recurrings).get(), isEmpty);
    expect((await ledger.balances())[bank]!.amount, -500);
    await db.close();
  });
}
