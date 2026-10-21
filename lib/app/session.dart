import 'package:brahma_core/brahma_core.dart';

import '../db/database.dart';
import '../modules/finance/domain/ledger.dart';

/// Artha in Brahma's terms: the app's id, name and Android package.
const arthaIdentity = AppIdentity(id: 'artha', name: 'Artha', androidPackage: 'dev.artha.artha');

/// Everything a running app needs: keys, the encrypted database and the
/// services on top of it. Opened once at start-up.
class AppSession extends CoreSession {
  AppSession(super.keys, super.store, this.ledger, {super.deviceName});

  final Ledger ledger;

  @override
  AppDatabase get db => store.db as AppDatabase;

  static Future<AppSession> open(KeyVault keys) => CoreSession.open(
    arthaIdentity,
    keys,
    openDatabase: AppDatabase.open,
    build: (store, deviceName) => AppSession(keys, store, Ledger(store), deviceName: deviceName),
  );
}
