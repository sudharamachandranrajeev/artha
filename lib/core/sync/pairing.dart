import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../security/crypto.dart';
import 'pocketbase_remote.dart' show validateServerUrl;
import 'sync_engine.dart' show SyncException;

/// Links that set up sync without typing, shown as QR codes or pasted:
///
/// * `artha://setup?s=<server>&i=<invite>`: printed by the server, to create
///   the first account.
/// * `artha://pair?s=<server>&p=<record>&k=<secret>`: shown by a signed-in
///   device so another one can join it (see [PairingCrypto]).
sealed class ArthaLink {
  const ArthaLink(this.server);
  final Uri server;

  /// Reads a link from pasted text or a scanned code. Line breaks and spaces
  /// that chat apps add are ignored.
  static ArthaLink parse(String text) {
    final uri = Uri.tryParse(text.replaceAll(RegExp(r'\s'), ''));
    if (uri == null || uri.scheme != 'artha') {
      throw SyncException('That is not an Artha link. It starts with artha://');
    }
    final q = uri.queryParameters;
    final server = q['s'];
    if (server == null) throw SyncException('That link has no server address');
    switch (uri.host) {
      case 'setup':
        final invite = q['i'] ?? '';
        if (invite.isEmpty) throw SyncException('That setup link has no invite code');
        return SetupLink(validateServerUrl(server), invite);
      case 'pair':
        final id = q['p'] ?? '';
        final secret = _unbase64Url(q['k'] ?? '');
        if (!RegExp(r'^[a-z0-9]{15}$').hasMatch(id) || secret == null || secret.length != 32) {
          throw SyncException('That pairing link is incomplete. Copy the whole link again');
        }
        return PairingLink(validateServerUrl(server), id, secret);
    }
    throw SyncException('This version of Artha does not know that link. Update it and try again');
  }
}

final class SetupLink extends ArthaLink {
  const SetupLink(super.server, this.invite);
  final String invite;

  @override
  String toString() =>
      Uri(scheme: 'artha', host: 'setup', queryParameters: {'s': '$server', 'i': invite}).toString();
}

final class PairingLink extends ArthaLink {
  const PairingLink(super.server, this.id, this.secret);

  /// The pairing record on the server.
  final String id;

  /// 32 random bytes the server never sees.
  final List<int> secret;

  @override
  String toString() => Uri(
    scheme: 'artha',
    host: 'pair',
    queryParameters: {'s': '$server', 'p': id, 'k': base64Url.encode(secret).replaceAll('=', '')},
  ).toString();
}

/// What a new device sends: who it is and the public key to answer to.
class JoinRequest {
  const JoinRequest({required this.name, required this.platform, required this.publicKey});
  final String name;
  final String platform;
  final List<int> publicKey;
}

/// What the old device answers with: everything a signed-in device keeps.
class PairingGrant {
  const PairingGrant({
    required this.email,
    required this.userId,
    required this.secret,
    required this.dataKey,
  });
  final String email;
  final String userId;

  /// The server login secret derived from the password (never the password).
  final String secret;
  final List<int> dataKey;
}

/// The new device's side of a pairing in progress.
class JoinTicket {
  const JoinTicket(this.link, this.keyPair, this.code);
  final PairingLink link;
  final SimpleKeyPair keyPair;

  /// Must match the code on the other device.
  final String code;
}

/// Device pairing: a signed-in device lets a new one join without typing.
///
/// 1. The old device opens a pairing record (10 minutes, one request) and
///    shows its [PairingLink] as a QR code.
/// 2. The new device makes an X25519 key pair and writes its name and public
///    key into the record, sealed under a key derived from the link secret:
///    the server can neither read nor forge the request.
/// 3. Both show a 6-digit [code] from the secret and that public key; the
///    user checks they match and approves on the old device, which can see
///    the requesting device's name.
/// 4. The old device seals the account keys to the new device's public key
///    (X25519 with a fresh key, HKDF salted with the link secret) and writes
///    them into the record. Someone who only saw the QR code cannot open
///    them: they lack the new device's private key.
/// 5. The new device opens them, shows which account it is joining, signs in
///    and deletes the record.
class PairingCrypto {
  static final _x25519 = X25519();
  static const _version = 'artha/v1';

  static Future<SimpleKeyPair> newKeyPair() => _x25519.newKeyPair();

  static Future<String> sealRequest(PairingLink link, JoinRequest r) async => VaultCrypto.sealJson(
    {'name': r.name, 'platform': r.platform, 'key': base64.encode(r.publicKey)},
    await _requestKey(link),
    '$_version|pair|request|${link.id}',
  );

  static Future<JoinRequest> openRequest(PairingLink link, String sealed) async {
    const error = 'The join request did not come from this pairing code';
    final json = await VaultCrypto.openJson(
      sealed,
      await _requestKey(link),
      '$_version|pair|request|${link.id}',
      error,
    );
    try {
      final m = json! as Map<String, Object?>;
      final key = base64.decode(m['key']! as String);
      if (key.length != 32) throw const FormatException();
      return JoinRequest(
        name: _clip(m['name'] as String? ?? ''),
        platform: _clip(m['platform'] as String? ?? ''),
        publicKey: key,
      );
    } on Object {
      throw CryptoException(error);
    }
  }

  /// Six digits both devices show, e.g. "482 913". They match only when the
  /// approving device received this exact public key.
  static Future<String> code(PairingLink link, List<int> publicKey) async {
    final h = (await Sha256().hash([...utf8.encode('$_version|pair|code|'), ...link.secret, ...publicKey]))
        .bytes;
    final n = ((h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]) % 1000000;
    final s = n.toString().padLeft(6, '0');
    return '${s.substring(0, 3)} ${s.substring(3)}';
  }

  static Future<String> sealGrant(PairingLink link, List<int> recipient, PairingGrant g) async {
    final mine = await _x25519.newKeyPair();
    final mineKey = (await mine.extractPublicKey()).bytes;
    final key = await _grantKey(link, mine, recipient, mineKey, recipient);
    final box = await VaultCrypto.sealJson(
      {'email': g.email, 'userId': g.userId, 'secret': g.secret, 'dek': base64.encode(g.dataKey)},
      key,
      '$_version|pair|grant|${link.id}',
    );
    return jsonEncode({'key': base64.encode(mineKey), 'box': box});
  }

  static Future<PairingGrant> openGrant(JoinTicket t, String sealed) async {
    const error = 'The keys from the other device could not be opened';
    try {
      final outer = jsonDecode(sealed) as Map<String, Object?>;
      final sender = base64.decode(outer['key']! as String);
      final mineKey = (await t.keyPair.extractPublicKey()).bytes;
      final key = await _grantKey(t.link, t.keyPair, sender, sender, mineKey);
      final m = await VaultCrypto.openJson(
        outer['box']! as String,
        key,
        '$_version|pair|grant|${t.link.id}',
        error,
      ) as Map<String, Object?>;
      final dek = base64.decode(m['dek']! as String);
      if (dek.length != 32) throw const FormatException();
      return PairingGrant(
        email: m['email']! as String,
        userId: m['userId']! as String,
        secret: m['secret']! as String,
        dataKey: dek,
      );
    } on CryptoException {
      rethrow;
    } on Object {
      throw CryptoException(error);
    }
  }

  static Future<SecretKey> _requestKey(PairingLink link) =>
      VaultCrypto.deriveKey(link.secret, '$_version|pair|request-key|${link.id}');

  /// Both sides derive this from the X25519 secret; [from] and [to] (the
  /// sender's and recipient's public keys) are bound in.
  static Future<SecretKey> _grantKey(
    PairingLink link,
    SimpleKeyPair own,
    List<int> other,
    List<int> from,
    List<int> to,
  ) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: own,
      remotePublicKey: SimplePublicKey(other, type: KeyPairType.x25519),
    );
    final bytes = await shared.extractBytes();
    // A low-order public key gives an all-zero secret anyone can compute.
    if (bytes.every((b) => b == 0)) throw CryptoException('The other device sent an invalid key');
    return VaultCrypto.deriveKey(
      bytes,
      '$_version|pair|grant-key|${link.id}|${base64.encode(from)}|${base64.encode(to)}',
      salt: link.secret,
    );
  }

  static String _clip(String s) => s.length > 60 ? s.substring(0, 60) : s;
}

List<int>? _unbase64Url(String s) {
  try {
    return base64Url.decode(base64Url.normalize(s));
  } on FormatException {
    return null;
  }
}
