import 'dart:convert';

import 'package:artha/core/security/crypto.dart';
import 'package:artha/core/sync/pairing.dart';
import 'package:artha/core/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final secret = List<int>.generate(32, (i) => i * 7 % 256);
  final link = PairingLink(Uri.parse('https://box.tail1234.ts.net'), 'abcdefghij12345', secret);

  group('links', () {
    test('a pairing link survives the round trip, even wrapped by a chat app', () {
      final text = link.toString();
      expect(text, startsWith('artha://pair?'));
      final split = '${text.substring(0, 30)}\n  ${text.substring(30)} ';
      for (final t in [text, split]) {
        final back = ArthaLink.parse(t) as PairingLink;
        expect(back.server, link.server);
        expect(back.id, link.id);
        expect(back.secret, secret);
      }
    });

    test('a setup link carries the server and invite code', () {
      final setup = SetupLink(Uri.parse('http://192.168.1.20:8090'), 'Inv1te-Code_xyz');
      final back = ArthaLink.parse(setup.toString()) as SetupLink;
      expect(back.server.toString(), 'http://192.168.1.20:8090');
      expect(back.invite, 'Inv1te-Code_xyz');
    });

    test('bad links are refused with a reason', () {
      final k = base64Url.encode(secret).replaceAll('=', '');
      for (final (text, reason) in [
        ('https://box.example.com', 'not an Artha link'),
        ('artha://pair?p=abcdefghij12345&k=$k', 'no server'),
        ('artha://pair?s=http://sync.example.com&p=abcdefghij12345&k=$k', 'https://'),
        ('artha://pair?s=https://a.example&p=short&k=$k', 'incomplete'),
        ('artha://pair?s=https://a.example&p=abcdefghij12345&k=${k.substring(4)}', 'incomplete'),
        ('artha://setup?s=https://a.example', 'invite'),
        ('artha://teleport?s=https://a.example', 'Update'),
      ]) {
        expect(
          () => ArthaLink.parse(text),
          throwsA(isA<SyncException>().having((e) => e.message, 'message', contains(reason))),
          reason: text,
        );
      }
    });
  });

  group('pairing crypto', () {
    late JoinTicket ticket;
    late JoinRequest request;
    final grant = PairingGrant(
      email: 'me@example.com',
      userId: 'u123456789abcde',
      secret: 'derived-login-secret',
      dataKey: List<int>.generate(32, (i) => i + 1),
    );

    setUp(() async {
      final keyPair = await PairingCrypto.newKeyPair();
      final pub = (await keyPair.extractPublicKey()).bytes;
      request = JoinRequest(name: 'Pixel 8', platform: 'android', publicKey: pub);
      ticket = JoinTicket(link, keyPair, await PairingCrypto.code(link, pub));
    });

    test('the request opens only with the same link, and both sides agree on the code', () async {
      final sealed = await PairingCrypto.sealRequest(link, request);
      expect(sealed, isNot(contains('Pixel')));
      final got = await PairingCrypto.openRequest(link, sealed);
      expect(got.name, 'Pixel 8');
      expect(got.platform, 'android');
      expect(await PairingCrypto.code(link, got.publicKey), ticket.code);
      expect(ticket.code, matches(RegExp(r'^\d{3} \d{3}$')));

      final other = PairingLink(link.server, link.id, List<int>.filled(32, 9));
      final moved = PairingLink(link.server, 'zzzzzzzzzzzzzzz', secret);
      for (final l in [other, moved]) {
        await expectLater(PairingCrypto.openRequest(l, sealed), throwsA(isA<CryptoException>()));
      }
    });

    test('another key gives another code', () async {
      final stranger = (await (await PairingCrypto.newKeyPair()).extractPublicKey()).bytes;
      expect(await PairingCrypto.code(link, stranger), isNot(ticket.code));
    });

    test('the grant opens only on the device that asked', () async {
      final sealed = await PairingCrypto.sealGrant(link, request.publicKey, grant);
      expect(sealed, isNot(contains('me@example.com')));
      expect(sealed, isNot(contains('derived-login-secret')));
      final got = await PairingCrypto.openGrant(ticket, sealed);
      expect(got.email, grant.email);
      expect(got.userId, grant.userId);
      expect(got.secret, grant.secret);
      expect(got.dataKey, grant.dataKey);

      // Someone who saw the QR code has the link, not the private key.
      final eavesdropper = JoinTicket(link, await PairingCrypto.newKeyPair(), '');
      await expectLater(PairingCrypto.openGrant(eavesdropper, sealed), throwsA(isA<CryptoException>()));

      final outer = jsonDecode(sealed) as Map<String, Object?>;
      final box = base64.decode(outer['box']! as String)..[40] ^= 1;
      final tampered = jsonEncode({...outer, 'box': base64.encode(box)});
      await expectLater(PairingCrypto.openGrant(ticket, tampered), throwsA(isA<CryptoException>()));
    });

    test('a low-order key is refused', () async {
      await expectLater(
        PairingCrypto.sealGrant(link, List<int>.filled(32, 0), grant),
        throwsA(isA<CryptoException>()),
      );
    });
  });
}
