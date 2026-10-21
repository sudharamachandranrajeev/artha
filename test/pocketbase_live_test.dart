import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'support.dart';

void main() {
  test('plain http only for this machine or a private network', () {
    for (final ok in [
      'https://sync.example.com',
      'https://sync.example.com:8443/pb',
      'http://localhost:8090',
      'http://127.0.0.1:8090',
      'http://192.168.1.5:8090',
      'http://10.0.0.2',
      'http://172.20.1.1',
      'http://100.101.102.103',
      'http://[::1]:8090',
      'http://[fd12::1]',
      'http://nas.local:8090',
    ]) {
      expect(validateServerUrl(ok), isA<Uri>(), reason: ok);
    }
    for (final bad in [
      'http://sync.example.com',
      'http://192.168.1.5.example.com',
      'http://172.32.0.1',
      'http://100.128.0.1',
      'http://8.8.8.8',
      'ftp://192.168.1.5',
      'https://user:pw@sync.example.com',
      'sync.example.com',
      '',
    ]) {
      expect(() => validateServerUrl(bad), throwsA(isA<SyncException>()), reason: bad);
    }
  });

  final server = LiveServer.fromEnvironment();
  final url = server?.url, invite = server?.invite;

  group('live PocketBase', skip: server == null ? LiveServer.skipReason : null, () {
    final run = DateTime.now().microsecondsSinceEpoch;
    final email = 'a$run@artha.test';
    const password = 'correct horse battery';
    late PocketBase admin;
    late Map<String, dynamic> limits;
    late Phone a, b;
    late String recovery;

    setUpAll(() async {
      await server!.relax();
      admin = server.admin;
      limits = server.limits;
      a = await Phone.open();
      b = await Phone.open();
    });

    tearDownAll(() async {
      await server!.restore('$run@artha.test');
      await a.db.close();
      await b.db.close();
    });

    test('the server carries the expected rate limits', () {
      final rules = {
        for (final r in limits['rules'] as List) (r as Map)['label']: (r['maxRequests'], r['duration']),
      };
      expect(limits['enabled'], isTrue);
      expect(rules['*:auth'], (10, 60));
      expect(rules['users:create'], (5, 3600));
    });

    test('reset mail carries a code for the app, not a web link', () async {
      final users = await admin.send<Map<String, dynamic>>('/api/collections/users');
      final body = (users['resetPasswordTemplate'] as Map)['body'] as String;
      expect(body, contains('{TOKEN}'));
      expect(body, isNot(contains('/_/')));
    });

    test('sign-up needs the invite code', () async {
      for (final code in ['', 'not-the-code']) {
        await expectLater(
          a.account.signUp(server: url!, email: email, password: password, invite: code),
          throwsA(isA<SyncException>().having((e) => e.message, 'message', contains('invite'))),
        );
      }
      expect(await a.keys.session(), isNull);
    });

    test('sign-up creates the vault and returns a recovery key once', () async {
      recovery = await a.account.signUp(server: url!, email: email, password: password, invite: invite!);
      expect(recovery, matches(RegExp(r'^([0-9A-Z]{4}-){12}[0-9A-Z]{4}$')));
      final session = (await a.keys.session())!;
      expect(session.values.join(), isNot(contains(password)));
      expect(session.values.join(), isNot(contains(recovery)));

      final vault = (await admin.collection('vaults').getFullList(filter: 'owner = "${session['userId']}"'))
          .single;
      final dek = (await a.keys.dataKey())!;
      expect(vault.getStringValue('wrapped_password'), isNot(contains(String.fromCharCodes(dek))));

      await expectLater(
        b.account.signUp(server: url, email: email, password: password, invite: invite),
        throwsA(isA<SyncException>().having((e) => e.message, 'message', contains('sign in'))),
      );
    });

    test('another device signs in to the same data key', () async {
      await expectLater(
        b.account.signIn(server: url!, email: email, password: 'wrong password!!'),
        throwsA(isA<SyncException>()),
      );
      await b.account.signIn(server: url, email: email.toUpperCase(), password: password);
      expect(await b.keys.dataKey(), await a.keys.dataKey());
      expect((await (await a.remote()).devices()).toSet(), {a.store.deviceId, b.store.deviceId});
    });

    test('changes sync between devices through the server, encrypted', () async {
      final bank = await a.ledger.saveAccount(name: 'Current', subtype: 'current', commodityId: 'GBP');
      await a.ledger.saveEntry(
        simpleEntry(
          date: '2026-10-01',
          currency: 'GBP',
          accountId: bank,
          categoryId: 'cat.groceries',
          amount: 4321,
        ),
      );
      final pushed = (await (await a.engine()).run()).pushed;
      expect(pushed, greaterThanOrEqualTo(2));
      final stored = await admin.collection('changes').getFullList(filter: 'device = "${a.store.deviceId}"');
      expect(stored, isNotEmpty);
      for (final c in stored) {
        expect(c.getStringValue('payload'), isNot(contains('Current')));
      }

      final r = await (await b.engine()).run();
      expect(r.pulled, pushed);
      expect((await b.ledger.balances())[bank]!.amount, -4321);

      // Edit on b, back to a.
      await b.ledger.saveAccount(id: bank, name: 'Joint', subtype: 'current', commodityId: 'GBP');
      await (await b.engine()).run();
      await (await a.engine()).run();
      final row = await (a.db.select(a.db.accounts)..where((x) => x.id.equals(bank))).getSingle();
      expect(row.name, 'Joint');
    });

    test('the e-mail address cannot change: it salts the password key', () async {
      await expectLater(
        (await a.remote()).pb.collection('users').requestEmailChange('new$run@artha.test'),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 400)),
      );
    });

    test('the change log is append-only and slots are unique', () async {
      final remote = await a.remote();
      expect(await remote.push(a.store.deviceId, 1, 'replay'), isFalse);
      expect(await remote.fetch(a.store.deviceId, 1), isNot('replay'));
      final first = (await remote.pb.collection('changes').getList(perPage: 1)).items.single;
      await expectLater(
        remote.pb.collection('changes').update(first.id, body: {'payload': 'x'}),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 403)),
      );
      await expectLater(
        remote.pb.collection('changes').delete(first.id),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 403)),
      );
    });

    test('one account cannot read or write another', () async {
      final c = await Phone.open();
      addTearDown(c.db.close);
      await c.account.signUp(server: url!, email: 'c$run@artha.test', password: password, invite: invite!);
      final mine = await c.remote();
      final aOwner = (await a.keys.session())!['userId']! as String;
      expect(await mine.devices(), [c.store.deviceId]);
      expect(await mine.pull(a.store.deviceId, 0), isEmpty);
      expect(await mine.lastSeq(a.store.deviceId), 0);
      expect((await mine.pb.collection('vaults').getFullList()).length, 1);
      expect((await mine.pb.collection('users').getFullList()).length, 1);
      await expectLater(
        PocketBaseRemote(mine.pb, aOwner).push(a.store.deviceId, 99, 'forged'),
        throwsA(isA<SyncException>()),
      );
      expect(await (await a.remote()).fetch(a.store.deviceId, 99), isNull);
    });

    test('password change re-wraps the key; old password stops working', () async {
      const next = 'staple battery horse';
      await expectLater(
        a.account.changePassword(oldPassword: 'not my password', newPassword: next),
        throwsA(isA<CryptoException>()),
      );
      await a.account.changePassword(oldPassword: password, newPassword: next);
      final dek = await a.keys.dataKey();
      final d = await Phone.open();
      addTearDown(d.db.close);
      await expectLater(
        d.account.signIn(server: url!, email: email, password: password),
        throwsA(isA<SyncException>()),
      );
      await d.account.signIn(server: url, email: email, password: next);
      expect(await d.keys.dataKey(), dek);
      // a keeps syncing with its refreshed session.
      expect(await (await a.engine()).run(), isA<SyncResult>());
    });

    test('after a reset by e-mail the recovery key reopens the vault', () async {
      const reset = 'brand new password 42';
      final owner = (await a.keys.session())!['userId']! as String;
      final dek = await a.keys.dataKey();
      // What confirmPasswordReset does on the server, without needing SMTP.
      final secret = (await VaultCrypto.fromPassword(email, reset)).authSecret;
      await admin.collection('users').update(owner, body: {'password': secret, 'passwordConfirm': secret});

      final e = await Phone.open();
      addTearDown(e.db.close);
      await expectLater(
        e.account.signIn(server: url!, email: email, password: reset),
        throwsA(isA<RecoveryKeyNeeded>()),
      );
      expect(await e.keys.dataKey(), isNull);
      await expectLater(
        e.account.unlockWithRecoveryKey(VaultCrypto.newRecoveryKey()),
        throwsA(isA<CryptoException>()),
      );
      await e.account.unlockWithRecoveryKey(recovery.toLowerCase());
      expect(await e.keys.dataKey(), dek);

      final f = await Phone.open();
      addTearDown(f.db.close);
      await f.account.signIn(server: url, email: email, password: reset);
      expect(await f.keys.dataKey(), dek);
    });

    test('the server rate-limits sign-in attempts', () async {
      final rules = [
        for (final r in limits['rules'] as List)
          if ((r as Map)['label'] == '*:auth') {...r, 'maxRequests': 3, 'duration': 2} else r,
      ];
      await admin.settings.update(
        body: {
          'rateLimits': {...limits, 'rules': rules},
        },
      );
      final pb = PocketBase(url!);
      final statuses = <int>[];
      for (var i = 0; i < 6; i++) {
        try {
          await pb.collection('users').authWithPassword(email, 'x' * 64);
        } on ClientException catch (e) {
          statuses.add(e.statusCode);
        }
      }
      expect(statuses, contains(429));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
  });
}
