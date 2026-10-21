import 'package:brahma_core/brahma_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'support.dart';

/// Device pairing against a real server: the rules in
/// server/pb_migrations/1792200000_artha_pairing.js and the protocol in
/// lib/core/sync/pairing.dart.
void main() {
  final server = LiveServer.fromEnvironment();

  group('live pairing', skip: server == null ? LiveServer.skipReason : null, () {
    final run = DateTime.now().microsecondsSinceEpoch;
    const password = 'correct horse battery';
    late Phone a, stranger;
    final opened = <Phone>[];

    Future<Phone> phone(String name) async {
      final p = await Phone.open(name: name);
      opened.add(p);
      return p;
    }

    Matcher status(int code) => throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', code));
    final closed = throwsA(isA<PairingClosed>());

    setUpAll(() async {
      await server!.relax();
      a = await phone('Laptop');
      await a.account.signUp(
        server: server.url,
        email: 'a$run@artha.test',
        password: password,
        invite: server.invite,
      );
      stranger = await phone('Other');
      await stranger.account.signUp(
        server: server.url,
        email: 's$run@artha.test',
        password: password,
        invite: server.invite,
      );
    });

    tearDownAll(() async {
      await server!.restore('$run@artha.test');
      for (final p in opened) {
        await p.db.close();
      }
    });

    test('a new device joins with the link alone and syncs', () async {
      final bank = await a.ledger.saveAccount(name: 'Current', subtype: 'current', commodityId: 'GBP');
      await (await a.engine()).run();

      final link = await a.account.offerPairing();
      expect(await a.account.pairingRequest(link), isNull);

      final b = await phone('Pixel 8');
      final ticket = await b.account.requestJoin(BrahmaLink.parse('$link') as PairingLink);
      expect(await b.account.joinGrant(ticket), isNull, reason: 'not approved yet');

      final request = (await a.account.pairingRequest(link))!;
      expect(request.name, 'Pixel 8');
      expect(request.platform, 'test');
      expect(await PairingCrypto.code(link, request.publicKey), ticket.code);

      await a.account.approvePairing(link, request);
      expect(await a.account.pairingFinished(link), isFalse);
      // The server holds only ciphertext.
      final record = await server!.admin.collection('pairings').getOne(link.id);
      expect(record.getStringValue('request'), isNot(contains('Pixel')));
      expect(record.getStringValue('response'), isNot(contains('a$run')));

      final grant = (await b.account.joinGrant(ticket))!;
      expect(grant.email, 'a$run@artha.test');

      await b.account.join(ticket, grant);
      expect(await a.account.pairingFinished(link), isTrue);
      expect(await b.keys.dataKey(), await a.keys.dataKey());
      final devices = await server.admin
          .collection('devices')
          .getFullList(filter: 'device = "${b.store.deviceId}"');
      expect(devices.single.getStringValue('name'), isEmpty, reason: 'the name travels sealed only');

      await (await b.engine()).run();
      final row = await (b.db.select(b.db.accounts)..where((x) => x.id.equals(bank))).getSingle();
      expect(row.name, 'Current');
    });

    test('a link takes one request; the request cannot be replaced', () async {
      final link = await a.account.offerPairing();
      await (await phone('First')).account.requestJoin(link);
      await expectLater((await phone('Second')).account.requestJoin(link), closed);
      final pairings = (await a.remote()).pb.collection('pairings');
      await expectLater(pairings.update(link.id, body: {'request': 'x'}), status(404));
      expect((await a.account.pairingRequest(link))!.name, 'First');
      await a.account.cancelPairing(link);
    });

    test('cancelling tells the waiting device', () async {
      final link = await a.account.offerPairing();
      final waiting = await phone('Waiting');
      final ticket = await waiting.account.requestJoin(link);
      await a.account.cancelPairing(link);
      await a.account.cancelPairing(link);
      await expectLater(waiting.account.joinGrant(ticket), closed);
      expect(await a.account.pairingFinished(link), isTrue);
    });

    test('an expired link is dead', () async {
      final link = await a.account.offerPairing();
      final created = await server!.admin.collection('pairings').getOne(link.id);
      final expires = DateTime.parse(created.getStringValue('expires'));
      final now = DateTime.now().toUtc();
      expect(expires.difference(now).inMinutes, inInclusiveRange(9, 10));
      await server.admin
          .collection('pairings')
          .update(link.id, body: {'expires': now.subtract(const Duration(seconds: 1)).toIso8601String()});
      await expectLater((await phone('Late')).account.requestJoin(link), closed);
      await expectLater(a.account.pairingRequest(link), closed);
      await a.account.cancelPairing(link);
    });

    test('the server rules hold', () async {
      final pb = (await a.remote()).pb;
      final pairings = pb.collection('pairings');
      final anonymous = PocketBase(server!.url).collection('pairings');
      final ownerId = pb.authStore.record!.id;

      // Nobody lists them, and an anonymous client cannot open one.
      await expectLater(anonymous.getList(), status(403));
      await expectLater(pairings.getList(), status(403));
      await expectLater(anonymous.create(body: {'owner': ownerId}), status(400));

      // Only the server sets the expiry and starting values.
      await expectLater(
        pairings.create(body: {'owner': ownerId, 'expires': '2099-01-01 00:00:00.000Z'}),
        status(400),
      );
      await expectLater(pairings.create(body: {'owner': ownerId, 'request': 'x'}), status(400));
      final strangerId = (await stranger.remote()).pb.authStore.record!.id;
      await expectLater(pairings.create(body: {'owner': strangerId}), status(400));

      final link = await a.account.offerPairing();
      // No answer before a request, and a request sets nothing else.
      await expectLater(pairings.update(link.id, body: {'response': 'x'}), status(404));
      await expectLater(
        anonymous.update(link.id, body: {'request': 'x', 'expires': '2099-01-01'}),
        status(404),
      );
      await expectLater(anonymous.update(link.id, body: {'request': 'x', 'owner': strangerId}), status(404));
      await (await phone('Asker')).account.requestJoin(link);

      // Another account can neither answer nor withdraw it; the asker cannot answer itself.
      final other = (await stranger.remote()).pb.collection('pairings');
      await expectLater(other.update(link.id, body: {'response': 'x'}), status(404));
      await expectLater(other.delete(link.id), status(404));
      await expectLater(anonymous.update(link.id, body: {'response': 'x'}), status(404));
      await expectLater(anonymous.delete(link.id), status(404));

      // The owner answers once.
      await pairings.update(link.id, body: {'response': 'x'});
      await expectLater(pairings.update(link.id, body: {'response': 'y'}), status(404));
      await a.account.cancelPairing(link);
    });

    test('a device that already syncs cannot join another account', () async {
      final link = await stranger.account.offerPairing();
      await expectLater(a.account.requestJoin(link), throwsA(isA<SyncException>()));
      await stranger.account.cancelPairing(link);
    });
  });
}
