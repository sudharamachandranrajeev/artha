import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class CryptoException implements Exception {
  CryptoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a password turns into. The server only ever sees [authSecret] (as
/// the account password); [kek] never leaves the device.
class PasswordKeys {
  PasswordKeys(this.authSecret, this.kek);
  final String authSecret;
  final SecretKey kek;
}

/// End-to-end encryption for sync.
///
/// password --Argon2id--> master --HKDF--> auth secret (server login)
///                                    \--> KEK, which wraps a random data key
/// The data key (DEK) encrypts every change with XChaCha20-Poly1305. A
/// recovery key wraps the same DEK so a forgotten password loses nothing.
/// Shortest password accepted for a sync account. The password derives the
/// key that wraps the data key, so it is the main defence if the server leaks.
const minPasswordLength = 12;

class VaultCrypto {
  static const version = 'artha/v1';
  static final _aead = Xchacha20.poly1305Aead();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _random = Random.secure();

  /// OWASP's minimum Argon2id profile (19 MiB, 2 passes), run off the UI
  /// isolate. The salt is per account, derived from the e-mail address.
  static Future<PasswordKeys> fromPassword(String email, String password) async {
    if (password.length < minPasswordLength) {
      throw CryptoException('Use a password of at least $minPasswordLength characters');
    }
    final salt = (await Sha256().hash(utf8.encode('$version/${email.trim().toLowerCase()}'))).bytes;
    final secret = utf8.encode(password);
    final master = await Isolate.run(() async {
      final k = await Argon2id(
        parallelism: 1,
        memory: 19456,
        iterations: 2,
        hashLength: 32,
      ).deriveKey(secretKey: SecretKey(secret), nonce: salt);
      return k.extractBytes();
    });
    final masterKey = SecretKey(master);
    final auth = await _hkdf.deriveKey(secretKey: masterKey, info: utf8.encode('artha auth v1'));
    final kek = await _hkdf.deriveKey(secretKey: masterKey, info: utf8.encode('artha kek v1'));
    return PasswordKeys(_hex(await auth.extractBytes()), kek);
  }

  static List<int> randomBytes(int n) => List<int>.generate(n, (_) => _random.nextInt(256));

  /// A new data encryption key.
  static List<int> newDataKey() => randomBytes(32);

  /// A new recovery key, e.g. "7KQ2-M9XD-...": 256 bits in Crockford base32.
  static String newRecoveryKey() {
    final s = _base32(randomBytes(32));
    return [for (var i = 0; i < s.length; i += 4) s.substring(i, min(i + 4, s.length))].join('-');
  }

  static Future<SecretKey> recoveryKek(String recoveryKey) async {
    final bytes = _unbase32(recoveryKey);
    if (bytes == null || bytes.length != 32) throw CryptoException('That recovery key is not valid');
    return _hkdf.deriveKey(secretKey: SecretKey(bytes), info: utf8.encode('artha recovery v1'));
  }

  /// Encrypts [key] under [kek]; [purpose] is bound in, so a password wrap
  /// cannot be passed off as a recovery wrap or the reverse.
  static Future<String> wrapKey(List<int> key, SecretKey kek, String purpose) =>
      _encrypt(key, kek, utf8.encode('$version|wrap|$purpose'));

  static Future<List<int>> unwrapKey(String wrapped, SecretKey kek, String purpose) =>
      _decrypt(wrapped, kek, utf8.encode('$version|wrap|$purpose'), 'Wrong password or recovery key');

  /// Compresses and encrypts a JSON value. [aad] ties the ciphertext to its
  /// place (owner, device, sequence), so the server cannot move it around.
  static Future<String> seal(Object json, List<int> dataKey, String aad) =>
      _encrypt(gzip.encode(utf8.encode(jsonEncode(json))), SecretKey(dataKey), utf8.encode(aad));

  static Future<Object?> open(String sealed, List<int> dataKey, String aad) async {
    final clear = await _decrypt(
      sealed,
      SecretKey(dataKey),
      utf8.encode(aad),
      'A synced change failed its integrity check',
    );
    return jsonDecode(utf8.decode(gzip.decode(clear)));
  }

  /// A 32-byte key for [info] from [secret] (HKDF-SHA256, optional [salt]).
  static Future<SecretKey> deriveKey(List<int> secret, String info, {List<int> salt = const []}) =>
      _hkdf.deriveKey(secretKey: SecretKey(secret), nonce: salt, info: utf8.encode(info));

  /// Encrypts a small JSON value under [key], bound to [aad]; [openJson]
  /// reverses it and throws [CryptoException] with [error] on any tampering.
  static Future<String> sealJson(Object json, SecretKey key, String aad) =>
      _encrypt(utf8.encode(jsonEncode(json)), key, utf8.encode(aad));

  static Future<Object?> openJson(String sealed, SecretKey key, String aad, String error) async {
    final clear = await _decrypt(sealed, key, utf8.encode(aad), error);
    try {
      return jsonDecode(utf8.decode(clear));
    } on FormatException {
      throw CryptoException(error);
    }
  }

  static Future<String> _encrypt(List<int> clear, SecretKey key, List<int> aad) async {
    final box = await _aead.encrypt(clear, secretKey: key, aad: aad);
    return base64.encode(box.concatenation());
  }

  static Future<List<int>> _decrypt(String data, SecretKey key, List<int> aad, String error) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64.decode(data),
        nonceLength: _aead.nonceLength,
        macLength: _aead.macAlgorithm.macLength,
      );
      return await _aead.decrypt(box, secretKey: key, aad: aad);
    } on SecretBoxAuthenticationError {
      throw CryptoException(error);
    } on FormatException {
      throw CryptoException(error);
    } on ArgumentError {
      throw CryptoException(error);
    }
  }
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String _base32(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0, bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

/// Accepts lower case, spaces and dashes, and the usual misreadings
/// (O for 0, I/L for 1).
Uint8List? _unbase32(String text) {
  final clean = text
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');
  final out = <int>[];
  var buffer = 0, bits = 0;
  for (final ch in clean.split('')) {
    final v = _alphabet.indexOf(ch);
    if (v < 0) return null;
    buffer = (buffer << 5) | v;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 255);
      bits -= 8;
      buffer &= (1 << bits) - 1;
    }
  }
  return Uint8List.fromList(out);
}
