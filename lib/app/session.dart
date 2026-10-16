import 'dart:io';

import '../core/db/database.dart';
import '../core/db/store.dart';
import '../core/security/key_vault.dart';
import '../core/sync/account_service.dart';
import '../modules/finance/domain/ledger.dart';

/// Everything a running app needs: keys, the encrypted database and the
/// services on top of it. Opened once at start-up.
class AppSession {
  AppSession(this.keys, this.db, this.store, this.ledger)
    : account = AccountService(keys, deviceId: store.deviceId, platform: Platform.operatingSystem);

  final KeyVault keys;
  final AppDatabase db;
  final Store store;
  final Ledger ledger;

  /// Sync account. The device name stays empty: the server keeps it in clear.
  final AccountService account;

  static Future<AppSession> open(KeyVault keys) async {
    final exists = await (await appDatabaseFile()).exists();
    final db = openAppDatabase(await keys.databaseKey(create: !exists));
    // Opening runs applyEncryptionKey, so a wrong key or a build without
    // encryption fails here at start-up rather than on the first screen.
    try {
      final store = await Store.open(db);
      return AppSession(keys, db, store, Ledger(store));
    } catch (_) {
      await db.close();
      rethrow;
    }
  }
}
