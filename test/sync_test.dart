import 'package:artha/app/session.dart' show arthaIdentity;
import 'package:artha/db/database.dart';
import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The server as the engine sees it: an append-only log per device.
class FakeRemote implements SyncRemote {
  final log = <String, Map<int, String>>{};
  bool loseNextReply = false;
  final hidden = <int>{};

  @override
  Future<bool> push(String device, int seq, String payload) async {
    final m = log.putIfAbsent(device, () => {});
    if (m.containsKey(seq)) return false;
    m[seq] = payload;
    if (loseNextReply) {
      loseNextReply = false;
      throw SyncException('connection dropped');
    }
    return true;
  }

  @override
  Future<String?> fetch(String device, int seq) async => log[device]?[seq];

  @override
  Future<int> lastSeq(String device) async =>
      (log[device]?.keys ?? <int>[]).fold<int>(0, (a, b) => a > b ? a : b);

  @override
  Future<List<String>> devices() async => log.keys.toList();

  @override
  Future<List<RemoteChange>> pull(String device, int afterSeq, {int limit = 50}) async {
    final m = log[device] ?? {};
    return [
      for (final s in m.keys.toList()..sort())
        if (s > afterSeq && !hidden.contains(s)) RemoteChange(s, m[s]!),
    ].take(limit).toList();
  }
}

class Device {
  Device._(this.db, this.ledger, this.engine);
  final AppDatabase db;
  final Ledger ledger;
  final SyncEngine engine;

  static Future<Device> open(FakeRemote remote, List<int> dek) async {
    final db = await openTestDatabase();
    final store = await Store.open(db);
    final ledger = Ledger(store);
    await ledger.seedDefaults('GBP');
    return Device._(db, ledger, SyncEngine(store, remote, dek, 'owner1'));
  }

  Future<int> outbox() async => (await db.select(db.outbox).get()).length;
}

void main() {
  group('crypto', () {
    test('password keys are deterministic per account and never the password', () async {
      final a = await VaultCrypto.fromPassword('Me@Example.com ', 'correct horse battery');
      final b = await VaultCrypto.fromPassword('me@example.com', 'correct horse battery');
      final c = await VaultCrypto.fromPassword('other@example.com', 'correct horse battery');
      expect(a.authSecret, b.authSecret);
      expect(a.authSecret, isNot(c.authSecret));
      expect(a.authSecret, hasLength(64));
      expect(
        await a.kek.extractBytes(),
        isNot(await (await VaultCrypto.recoveryKek(VaultCrypto.newRecoveryKey())).extractBytes()),
      );
      expect(() => VaultCrypto.fromPassword('me@example.com', 'short'), throwsA(isA<CryptoException>()));
    });

    test('data key wraps under password and recovery key', () async {
      final keys = await VaultCrypto.fromPassword('me@example.com', 'correct horse battery');
      final dek = VaultCrypto.newDataKey();
      final wrapped = await VaultCrypto.wrapKey(dek, keys.kek, 'password');
      expect(await VaultCrypto.unwrapKey(wrapped, keys.kek, 'password'), dek);
      expect(() => VaultCrypto.unwrapKey(wrapped, keys.kek, 'recovery'), throwsA(isA<CryptoException>()));

      final recovery = VaultCrypto.newRecoveryKey();
      expect(recovery, matches(RegExp(r'^([0-9A-HJKMNP-TV-Z]{4}-){12}[0-9A-HJKMNP-TV-Z]{4}$')));
      final rw = await VaultCrypto.wrapKey(dek, await VaultCrypto.recoveryKek(recovery), 'recovery');
      final typed = recovery.toLowerCase().replaceAll('-', ' ');
      expect(await VaultCrypto.unwrapKey(rw, await VaultCrypto.recoveryKek(typed), 'recovery'), dek);
      expect(() => VaultCrypto.recoveryKek('not-a-key'), throwsA(isA<CryptoException>()));
    });

    test('sealed changes are bound to their slot and detect tampering', () async {
      final dek = VaultCrypto.newDataKey();
      final sealed = await VaultCrypto.seal({'x': 1}, dek, 'a|1');
      expect(await VaultCrypto.open(sealed, dek, 'a|1'), {'x': 1});
      expect(() => VaultCrypto.open(sealed, dek, 'a|2'), throwsA(isA<CryptoException>()));
      final bytes = sealed.codeUnits.toList();
      bytes[40] = bytes[40] == 65 ? 66 : 65;
      expect(
        () => VaultCrypto.open(String.fromCharCodes(bytes), dek, 'a|1'),
        throwsA(isA<CryptoException>()),
      );
      expect(
        () => VaultCrypto.open(sealed, VaultCrypto.newDataKey(), 'a|1'),
        throwsA(isA<CryptoException>()),
      );
    });

    test('key vault keeps one database key', () async {
      final vault = KeyVault(MemorySecretStore(), arthaIdentity);
      final k = await vault.databaseKey();
      expect(k, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await vault.databaseKey(), k);
    });
  });

  group('sync', () {
    late FakeRemote remote;
    late Device a, b;
    final dek = VaultCrypto.newDataKey();

    setUp(() async {
      remote = FakeRemote();
      a = await Device.open(remote, dek);
      b = await Device.open(remote, dek);
    });
    tearDown(() async {
      await a.db.close();
      await b.db.close();
    });

    test('changes travel encrypted and arrive whole', () async {
      final bank = await a.ledger.saveAccount(name: 'Current', subtype: 'current', commodityId: 'GBP');
      await a.ledger.saveEntry(
        simpleEntry(
          date: '2026-10-01',
          currency: 'GBP',
          accountId: bank,
          categoryId: 'cat.groceries',
          amount: 1234,
        ),
      );
      final r = await a.engine.run();
      expect(r.pushed, greaterThanOrEqualTo(2));
      expect(await a.outbox(), 0);
      expect(remote.log.values.single.values.single, isNot(contains('Current')));

      expect((await b.engine.run()).pulled, r.pushed);
      final balances = await b.ledger.balances();
      expect(balances[bank]!.amount, -1234);
      expect(balances['cat.groceries']!.amount, 1234);
      // Applying remote rows does not queue them to be sent back.
      expect(await b.outbox(), 0);
    });

    test('concurrent edits converge on the newest write', () async {
      final id = await a.ledger.saveAccount(name: 'Savings', subtype: 'savings', commodityId: 'GBP');
      await a.engine.run();
      await b.engine.run();
      await a.ledger.saveAccount(id: id, name: 'Old name', subtype: 'savings', commodityId: 'GBP');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b.ledger.saveAccount(id: id, name: 'New name', subtype: 'savings', commodityId: 'GBP');
      await a.engine.run();
      await b.engine.run();
      await a.engine.run();
      Future<String> name(Device d) async =>
          (await (d.db.select(d.db.accounts)..where((x) => x.id.equals(id))).getSingle()).name;
      expect(await name(a), 'New name');
      expect(await name(b), 'New name');
    });

    test('deletions sync as tombstones, postings follow their entry', () async {
      final bank = await a.ledger.saveAccount(name: 'Current', subtype: 'current', commodityId: 'GBP');
      final e = await a.ledger.saveEntry(
        simpleEntry(
          date: '2026-10-01',
          currency: 'GBP',
          accountId: bank,
          categoryId: 'cat.groceries',
          amount: 500,
        ),
      );
      await a.engine.run();
      await b.engine.run();
      await b.ledger.deleteEntry(e);
      await b.engine.run();
      await a.engine.run();
      expect((await a.ledger.balances())[bank], isNull);
    });

    test('a lost reply does not lose or duplicate the batch', () async {
      await a.ledger.saveAccount(name: 'One', subtype: 'cash', commodityId: 'GBP');
      remote.loseNextReply = true;
      expect(a.engine.push(), throwsA(isA<SyncException>()));
      await Future<void>.delayed(Duration.zero);
      expect(await a.outbox(), 1);
      await a.engine.push();
      expect(await a.outbox(), 0);
      expect(remote.log.values.single.keys, [1]);
    });

    test('a restored device never overwrites its own history', () async {
      await a.ledger.saveAccount(name: 'One', subtype: 'cash', commodityId: 'GBP');
      await a.engine.push();
      await a.db.setLocalSetting('sync.seq', '0');
      await a.db.setLocalSetting('sync.sent', '0');
      await a.ledger.saveAccount(name: 'Two', subtype: 'cash', commodityId: 'GBP');
      await a.engine.push();
      expect(remote.log.values.single.keys, [1, 2]);
      await b.engine.pull();
      final names = (await b.db.select(b.db.accounts).get()).map((x) => x.name);
      expect(names, containsAll(['One', 'Two']));
    });

    test('a gap in the log stops that device stream until it fills', () async {
      await a.ledger.saveAccount(name: 'One', subtype: 'cash', commodityId: 'GBP');
      await a.engine.push();
      await a.ledger.saveAccount(name: 'Two', subtype: 'cash', commodityId: 'GBP');
      await a.engine.push();
      remote.hidden.add(1);
      expect(await b.engine.pull(), 0);
      remote.hidden.clear();
      expect(await b.engine.pull(), 2);
    });

    test('a forged or moved change is rejected', () async {
      await a.ledger.saveAccount(name: 'One', subtype: 'cash', commodityId: 'GBP');
      await a.engine.push();
      final log = remote.log.values.single;
      log[2] = log[1]!; // replayed into another slot
      await b.engine.pull().then((_) {}, onError: (_) {});
      expect(b.engine.pull(), throwsA(isA<CryptoException>()));
    });
  });
}
