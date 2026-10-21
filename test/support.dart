import 'dart:io';

import 'package:artha/app/session.dart' show arthaIdentity;
import 'package:artha/db/database.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pocketbase/pocketbase.dart';

const testKey = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

/// A fresh encrypted database in a temp file (memory databases skip the
/// cipher, so a file is the honest test).
Future<AppDatabase> openTestDatabase({String key = testKey, File? file}) async {
  // Each call opens its own file, which is what drift's warning is about.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final f = file ?? File('${(await Directory.systemTemp.createTemp('artha')).path}/t.db');
  return AppDatabase(NativeDatabase(f, setup: (db) => applyEncryptionKey(db, key)));
}

/// A local PocketBase from scripts/run-local-server.sh, or null when its
/// variables are not set (live tests then skip).
class LiveServer {
  LiveServer._(this.url, this.invite, this._adminEmail, this._adminPassword);
  final String url;
  final String invite;
  final String _adminEmail, _adminPassword;
  late final PocketBase admin = PocketBase(url);
  late Map<String, dynamic> limits;

  static const skipReason =
      'Live server test: set ARTHA_PB_URL, ARTHA_SIGNUP_CODE, ARTHA_PB_ADMIN, ARTHA_PB_ADMIN_PASSWORD '
      '(scripts/run-local-server.sh writes them to server/.env)';

  static LiveServer? fromEnvironment() {
    final env = Platform.environment;
    final url = env['ARTHA_PB_URL'], invite = env['ARTHA_SIGNUP_CODE'];
    final email = env['ARTHA_PB_ADMIN'], password = env['ARTHA_PB_ADMIN_PASSWORD'];
    if (url == null || invite == null || email == null || password == null) return null;
    return LiveServer._(url, invite, email, password);
  }

  RandomAccessFile? _turn;

  /// Signs in as admin and lifts the rate limits, which would stop a test
  /// half way. [restore] puts them back.
  ///
  /// Test files run in parallel, so this first waits until no other live
  /// file holds the server. Otherwise it would save that file's lifted
  /// limits as the ones to put back. The OS drops the lock if a run dies.
  Future<void> relax() async {
    _turn = await File('${Directory.systemTemp.path}/artha-live-server.lock').open(mode: FileMode.write);
    await _turn!.lock(FileLock.blockingExclusive);
    await admin.collection('_superusers').authWithPassword(_adminEmail, _adminPassword);
    limits = Map<String, dynamic>.from((await admin.settings.getAll())['rateLimits'] as Map);
    await admin.settings.update(
      body: {
        'rateLimits': {
          ...limits,
          'rules': [
            for (final r in limits['rules'] as List) {...r as Map, 'maxRequests': 10000},
          ],
        },
      },
    );
  }

  /// Restores the rate limits and deletes users whose e-mail contains [tag].
  Future<void> restore(String tag) async {
    try {
      await admin.settings.update(body: {'rateLimits': limits});
      for (final u in await admin.collection('users').getFullList(filter: 'email ~ "$tag"')) {
        await admin.collection('users').delete(u.id);
      }
    } finally {
      await _turn?.close();
      _turn = null;
    }
  }
}

/// One app install: its own database, keychain and account service.
class Phone {
  Phone._(this.db, this.store, this.ledger, this.keys, this.account);
  final AppDatabase db;
  final Store store;
  final Ledger ledger;
  final KeyVault keys;
  final AccountService account;

  static Future<Phone> open({String name = ''}) async {
    final db = await openTestDatabase();
    final store = await Store.open(db);
    final ledger = Ledger(store);
    await ledger.seedDefaults('GBP');
    final keys = KeyVault(MemorySecretStore(), arthaIdentity);
    return Phone._(
      db,
      store,
      ledger,
      keys,
      AccountService(keys, deviceId: store.deviceId, deviceName: name, platform: 'test'),
    );
  }

  Future<SyncEngine> engine() async => (await account.engine(store))!;
  Future<PocketBaseRemote> remote() async => (await engine()).remote as PocketBaseRemote;
}
