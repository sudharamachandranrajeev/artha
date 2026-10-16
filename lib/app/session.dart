import 'dart:io';

import '../core/db/database.dart';
import '../core/db/store.dart';
import '../core/security/key_vault.dart';
import '../core/sync/account_service.dart';
import '../modules/finance/domain/ledger.dart';
import 'links.dart';

/// Everything a running app needs: keys, the encrypted database and the
/// services on top of it. Opened once at start-up.
class AppSession {
  AppSession(this.keys, this.db, this.store, this.ledger, {String deviceName = ''})
    : account = AccountService(
        keys,
        deviceId: store.deviceId,
        deviceName: deviceName,
        platform: Platform.operatingSystem,
      );

  final KeyVault keys;
  final AppDatabase db;
  final Store store;
  final Ledger ledger;

  /// Sync account. The device name goes only into sealed pairing requests:
  /// the server keeps its device list in clear, so that stays nameless.
  final AccountService account;

  static Future<AppSession> open(KeyVault keys) async {
    final exists = await (await appDatabaseFile()).exists();
    final db = openAppDatabase(await keys.databaseKey(create: !exists));
    // Opening runs applyEncryptionKey, so a wrong key or a build without
    // encryption fails here at start-up rather than on the first screen.
    try {
      final store = await Store.open(db);
      return AppSession(keys, db, store, Ledger(store), deviceName: await PlatformLinks.deviceName());
    } catch (_) {
      await db.close();
      rethrow;
    }
  }
}
