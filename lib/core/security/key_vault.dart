import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto.dart';

/// Where secrets live: the OS keychain on devices, memory in tests.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore, Windows Credential Manager (DPAPI), libsecret on Linux.
class DeviceSecretStore implements SecretStore {
  const DeviceSecretStore();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// The device's keys: the local database key and, once signed in, the sync
/// data key. Neither is ever written anywhere but the [SecretStore].
class KeyVault {
  KeyVault(this.store);
  final SecretStore store;

  static const _dbKey = 'artha.db.key';
  static const _dataKey = 'artha.sync.dek';
  static const _session = 'artha.sync.session';

  /// The database encryption key for this device, created on first use. With
  /// [create] false (a database already exists) a missing key is an error:
  /// a fresh key could never open the old file, and storing one would stop
  /// the old key working if the keychain comes back.
  Future<String> databaseKey({bool create = true}) async {
    final existing = await store.read(_dbKey);
    if (existing != null) return existing;
    if (!create) {
      throw CryptoException(
        'The database key is missing from the system keychain. Unlock or restore the keychain, '
        'then start Artha again.',
      );
    }
    final key = VaultCrypto.randomBytes(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await store.write(_dbKey, key);
    if (await store.read(_dbKey) != key) {
      throw CryptoException('The system keychain did not keep the database key');
    }
    return key;
  }

  Future<List<int>?> dataKey() async {
    final v = await store.read(_dataKey);
    return v == null ? null : base64.decode(v);
  }

  Future<void> setDataKey(List<int> key) => store.write(_dataKey, base64.encode(key));

  /// Server URL, user id and auth token of the signed-in sync account.
  Future<Map<String, Object?>?> session() async {
    final v = await store.read(_session);
    return v == null ? null : jsonDecode(v) as Map<String, Object?>;
  }

  Future<void> setSession(Map<String, Object?> s) => store.write(_session, jsonEncode(s));

  Future<void> signOut() async {
    await store.delete(_dataKey);
    await store.delete(_session);
  }
}
