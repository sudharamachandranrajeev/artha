import 'package:drift/drift.dart';

import '../db/database.dart';
import '../db/store.dart';
import '../security/crypto.dart';

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RemoteChange {
  RemoteChange(this.seq, this.payload);
  final int seq;
  final String payload;
}

/// The server side of sync, reduced to an append-only log per device.
abstract interface class SyncRemote {
  /// Stores change [seq] of [device]. False when that slot already exists.
  Future<bool> push(String device, int seq, String payload);

  /// The stored payload of one change, or null.
  Future<String?> fetch(String device, int seq);

  /// Highest stored seq of [device] (0 if none).
  Future<int> lastSeq(String device);

  /// Every device of this account that has pushed anything.
  Future<List<String>> devices();

  /// Changes of [device] after [afterSeq], oldest first.
  Future<List<RemoteChange>> pull(String device, int afterSeq, {int limit = 50});
}

class SyncResult {
  SyncResult(this.pushed, this.pulled);
  final int pushed;
  final int pulled;
}

/// Moves encrypted changes between this device and the server.
///
/// Push: outbox rows go out in numbered batches, strictly in order; a batch
/// is only removed from the outbox after the server holds it. Pull: each
/// other device's batches are applied in order, the newest write (by HLC)
/// winning per row; the cursor moves in the same transaction.
class SyncEngine {
  SyncEngine(this.store, this.remote, this.dataKey, this.owner);

  final Store store;
  final SyncRemote remote;
  final List<int> dataKey;
  final String owner;
  AppDatabase get db => store.db;

  static const batchSize = 200;
  static const _assigned = 'sync.seq';
  static const _sent = 'sync.sent';

  String _aad(String device, int seq) => '${VaultCrypto.version}|$owner|$device|$seq';

  Future<SyncResult> run() async => SyncResult(await push(), await pull());

  Future<int> _setting(String key) async => int.parse(await db.localSetting(key) ?? '0');

  Future<int> push() async {
    final me = store.deviceId;
    // A restored backup may hold an older counter than the server: never reuse a slot.
    final serverLast = await remote.lastSeq(me);
    if (serverLast > await _setting(_assigned)) {
      await db.transaction(() async {
        await db.customStatement('UPDATE outbox SET seq = NULL WHERE seq > ?', [await _setting(_sent)]);
        await db.setLocalSetting(_assigned, '$serverLast');
        await db.setLocalSetting(_sent, '$serverLast');
      });
    }
    var pushed = 0;
    while (true) {
      final seq = await _nextBatch();
      if (seq == null) return pushed;
      final rows = await _collect(seq);
      final payload = await VaultCrypto.seal({'v': 1, 'rows': rows}, dataKey, _aad(me, seq));
      if (!await remote.push(me, seq, payload) && !await _sameAsServer(seq, rows)) {
        // The slot holds something else (e.g. from a since-restored copy of
        // this device): move the batch to a fresh number and try again.
        await db.transaction(() async {
          final fresh = await _setting(_assigned) + 1;
          await db.customStatement('UPDATE outbox SET seq = ? WHERE seq = ?', [fresh, seq]);
          await db.setLocalSetting(_assigned, '$fresh');
          await db.setLocalSetting(_sent, '$seq');
        });
        continue;
      }
      await db.transaction(() async {
        await db.customStatement('DELETE FROM outbox WHERE seq = ?', [seq]);
        await db.setLocalSetting(_sent, '$seq');
      });
      pushed += rows.length;
    }
  }

  /// The batch to send next: an unconfirmed one first, else a new one.
  Future<int?> _nextBatch() => db.transaction(() async {
    final assigned = await _setting(_assigned), sent = await _setting(_sent);
    if (sent < assigned) return sent + 1;
    final waiting = await db.customSelect('SELECT 1 FROM outbox WHERE seq IS NULL LIMIT 1').get();
    if (waiting.isEmpty) return null;
    final seq = assigned + 1;
    await db.customStatement(
      'UPDATE outbox SET seq = ? WHERE rowid IN (SELECT rowid FROM outbox WHERE seq IS NULL LIMIT $batchSize)',
      [seq],
    );
    await db.setLocalSetting(_assigned, '$seq');
    return seq;
  });

  Future<List<Map<String, Object?>>> _collect(int seq) async {
    final items = await db
        .customSelect('SELECT entity, row_id FROM outbox WHERE seq = ?', variables: [Variable(seq)])
        .get();
    final rows = <Map<String, Object?>>[];
    for (final it in items) {
      final table = it.read<String>('entity');
      if (!syncedTables.contains(table)) continue;
      final id = it.read<String>('row_id');
      final row = await db
          .customSelect('SELECT * FROM "$table" WHERE id = ?', variables: [Variable(id)])
          .get();
      if (row.isEmpty) continue;
      rows.add({
        't': table,
        'r': row.single.data,
        if (table == 'entries')
          'p': [
            for (final p
                in await db
                    .customSelect(
                      'SELECT * FROM postings WHERE entry_id = ? ORDER BY position',
                      variables: [Variable(id)],
                    )
                    .get())
              p.data,
          ],
      });
    }
    return rows;
  }

  /// Whether the server's copy of [seq] already carries these row versions.
  Future<bool> _sameAsServer(int seq, List<Map<String, Object?>> rows) async {
    final stored = await remote.fetch(store.deviceId, seq);
    if (stored == null) return false;
    try {
      final data = await VaultCrypto.open(stored, dataKey, _aad(store.deviceId, seq));
      String key(Object? r) {
        final m = r! as Map;
        final row = m['r'] as Map;
        return '${m['t']}/${row['id']}/${row['hlc']}';
      }

      final theirs = {for (final r in (data! as Map)['rows'] as List) key(r)};
      return rows.every((r) => theirs.contains(key(r)));
    } on Object {
      return false;
    }
  }

  Future<int> pull() async {
    var applied = 0;
    for (final device in await remote.devices()) {
      if (device == store.deviceId) continue;
      var cursor = await _cursor(device);
      stream:
      while (true) {
        final batch = await remote.pull(device, cursor);
        if (batch.isEmpty) break;
        for (final change in batch) {
          // Batches are pushed strictly in order, so a gap means the server
          // is still catching up (or holding something back): stop here.
          if (change.seq != cursor + 1) break stream;
          final data = await VaultCrypto.open(change.payload, dataKey, _aad(device, change.seq));
          final rows = data is Map && data['rows'] is List ? data['rows'] as List : null;
          if (rows == null) throw SyncException('A change from another device is malformed');
          await db.transaction(() async {
            for (final r in rows) {
              await _apply(r);
            }
            await db.customStatement(
              'INSERT INTO sync_cursors (device_id, seq) VALUES (?, ?) '
              'ON CONFLICT(device_id) DO UPDATE SET seq = excluded.seq',
              [device, change.seq],
            );
          });
          cursor = change.seq;
          applied += rows.length;
        }
      }
    }
    return applied;
  }

  Future<int> _cursor(String device) async {
    final r = await db
        .customSelect('SELECT seq FROM sync_cursors WHERE device_id = ?', variables: [Variable(device)])
        .getSingleOrNull();
    return r?.read<int>('seq') ?? 0;
  }

  static final _hlc = RegExp(r'^\d{15}-\d{6}-[A-Za-z0-9]+$');

  /// Writes one remote row if it is newer than the local copy. Columns this
  /// version does not know are ignored, so newer app versions can add some.
  Future<void> _apply(Object? change) async {
    if (change is! Map || change['t'] is! String || change['r'] is! Map) {
      throw SyncException('A change from another device is malformed');
    }
    final table = change['t'] as String;
    final row = (change['r'] as Map).cast<String, Object?>();
    final info = db.tableNamed(table);
    if (!syncedTables.contains(table) || info == null) return;
    final id = row['id'], hlc = row['hlc'];
    if (id is! String || hlc is! String || !_hlc.hasMatch(hlc)) {
      throw SyncException('A change from another device is malformed');
    }
    final local = await db
        .customSelect('SELECT hlc FROM "$table" WHERE id = ?', variables: [Variable(id)])
        .getSingleOrNull();
    store.clock.receive(hlc);
    if (local != null && local.read<String>('hlc').compareTo(hlc) >= 0) return;

    await _upsert(table, {for (final c in info.$columns) c.name}, row);
    if (table == 'entries') {
      await db.customStatement('DELETE FROM postings WHERE entry_id = ?', [id]);
      final postings = change['p'];
      if (postings is List) {
        final cols = {for (final c in db.postings.$columns) c.name};
        for (final p in postings) {
          if (p is! Map || p['entry_id'] != id) {
            throw SyncException('A synced posting does not match its entry');
          }
          await _upsert('postings', cols, p.cast<String, Object?>());
        }
      }
    }
  }

  Future<void> _upsert(String table, Set<String> known, Map<String, Object?> row) async {
    final cols = [
      for (final MapEntry(key: k, value: v) in row.entries)
        if (known.contains(k) && (v == null || v is String || v is num || v is bool)) k,
    ];
    if (!cols.contains('id') || cols.length < 2) throw SyncException('A synced row is incomplete');
    final values = [for (final c in cols) row[c] is bool ? ((row[c]! as bool) ? 1 : 0) : row[c]];
    await db.customStatement(
      'INSERT INTO "$table" (${cols.map((c) => '"$c"').join(', ')}) '
      'VALUES (${List.filled(cols.length, '?').join(', ')}) '
      'ON CONFLICT(id) DO UPDATE SET ${cols.where((c) => c != 'id').map((c) => '"$c" = excluded."$c"').join(', ')}',
      values,
    );
  }
}
