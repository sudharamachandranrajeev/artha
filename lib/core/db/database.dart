import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

/// Tables whose rows sync between devices, keyed by SQL table name. Entries
/// carry their postings with them (see SyncEngine).
const syncedTables = [
  'commodities',
  'accounts',
  'entries',
  'prices',
  'balance_checks',
  'rules',
  'budgets',
  'targets',
  'facts',
  'prefs',
  'import_profiles',
];

@DriftDatabase(
  tables: [
    Commodities,
    Accounts,
    Entries,
    Postings,
    Prices,
    BalanceChecks,
    Rules,
    Budgets,
    Targets,
    Facts,
    Prefs,
    ImportProfiles,
    Outbox,
    SyncCursors,
    LocalSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      for (final sql in _indexes) {
        await customStatement(sql);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static const _indexes = [
    'CREATE INDEX postings_account ON postings (account_id)',
    'CREATE INDEX postings_entry ON postings (entry_id)',
    'CREATE INDEX entries_date ON entries (date)',
    'CREATE INDEX entries_import_ref ON entries (import_ref)',
    'CREATE INDEX prices_lookup ON prices (commodity_id, quote, date)',
  ];

  TableInfo<Table, dynamic>? tableNamed(String name) {
    for (final t in allTables) {
      if (t.actualTableName == name) return t;
    }
    return null;
  }
}

/// Where the on-device database lives.
Future<File> appDatabaseFile([String name = 'artha']) async =>
    File(p.join((await getApplicationSupportDirectory()).path, '$name.sqlite'));

/// Opens the on-device database, encrypted with SQLite3MultipleCiphers.
///
/// [key] is a random hex secret kept in the platform keystore (KeyVault).
/// Opening fails loudly if the bundled SQLite lacks encryption support or the
/// key is wrong, rather than ever writing finance data in plain text.
AppDatabase openAppDatabase(String key, {String name = 'artha'}) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
    throw ArgumentError('database key must be 64 hex characters');
  }
  return AppDatabase(
    driftDatabase(
      name: name,
      native: DriftNativeOptions(
        databasePath: () async => (await appDatabaseFile(name)).path,
        setup: (db) => applyEncryptionKey(db, key),
      ),
    ),
  );
}

/// Runs inside the connection's isolate before drift touches the file.
void applyEncryptionKey(CommonDatabase db, String key) {
  db.execute("PRAGMA key = '$key'");
  // Fails with "no such function" on a plain SQLite build (where PRAGMA key is
  // silently ignored) and with "file is not a database" on a wrong key, so an
  // unencrypted or mis-keyed database is never used.
  db.select('SELECT sqlite3mc_version()');
}
