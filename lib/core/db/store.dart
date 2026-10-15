import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../sync/hlc.dart';
import 'database.dart';

const _uuid = Uuid();

/// New random row id.
String newId() => _uuid.v4();

/// The single write path for synced rows: stamps each write with an HLC and
/// queues it in the outbox inside the same transaction, so a change is never
/// saved without also being scheduled for sync (and never synced unsaved).
class Store {
  Store._(this.db, this.clock);

  final AppDatabase db;
  final HlcClock clock;

  String get deviceId => clock.node;

  static Future<Store> open(AppDatabase db) async {
    var deviceId = await db.localSetting('device.id');
    if (deviceId == null) {
      deviceId = newId().replaceAll('-', '');
      await db.setLocalSetting('device.id', deviceId);
    }
    final clock = HlcClock(deviceId);
    // Never stamp below what this database already holds, even if the
    // wall clock moved backwards since the last run.
    final union = syncedTables.map((t) => 'SELECT MAX(hlc) AS h FROM $t').join(' UNION ALL ');
    final rows = await db.customSelect('SELECT MAX(h) AS h FROM ($union)').get();
    final latest = rows.first.readNullable<String>('h');
    if (latest != null && latest.isNotEmpty) clock.receive(latest);
    return Store._(db, clock);
  }

  /// Inserts or replaces [row] in [table] and records the change.
  Future<void> save<T extends Table, D>(TableInfo<T, D> table, Insertable<D> row, String id) =>
      db.transaction(() async {
        await db.into(table).insertOnConflictUpdate(row);
        await touch(table, id);
      });

  /// Tombstones a row (deletions sync like edits).
  Future<void> remove(TableInfo table, String id) => db.transaction(() async {
    await db.customUpdate(
      'UPDATE "${table.actualTableName}" SET deleted = 1 WHERE id = ?',
      variables: [Variable(id)],
      updates: {table},
    );
    await touch(table, id);
  });

  /// Stamps an already-written row and queues it. Call inside a transaction.
  Future<void> touch(TableInfo table, String id) async {
    await db.customUpdate(
      'UPDATE "${table.actualTableName}" SET hlc = ? WHERE id = ?',
      variables: [Variable(clock.tick()), Variable(id)],
      updates: {table},
    );
    await db.customStatement(
      'INSERT INTO outbox (entity, row_id, seq) VALUES (?, ?, NULL) '
      'ON CONFLICT(entity, row_id) DO UPDATE SET seq = NULL',
      [table.actualTableName, id],
    );
  }
}

extension LocalSettingsAccess on AppDatabase {
  Future<String?> localSetting(String key) async =>
      (await (select(localSettings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setLocalSetting(String key, String value) =>
      into(localSettings).insertOnConflictUpdate(LocalSetting(key: key, value: value));
}
