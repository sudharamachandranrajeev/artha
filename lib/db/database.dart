import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

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
class AppDatabase extends _$AppDatabase with SyncedDatabase {
  AppDatabase(super.e);

  /// Opens Artha's encrypted database (see [openEncryptedDatabase]).
  AppDatabase.open(String key) : this(openEncryptedDatabase('artha', key));

  @override
  final syncedTables = const [
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

  /// Entries carry their postings with them.
  @override
  final childRows = const {
    'entries': ChildRows(table: 'postings', parentColumn: 'entry_id', orderBy: 'position'),
  };

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
}
