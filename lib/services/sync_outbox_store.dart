import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../data/db/app_database.dart';

class PendingSyncWrite {
  final String endpoint, deviceId, domain, idempotencyKey;
  final int localRevision, baseRevision;
  final Map<String, dynamic> envelope;
  const PendingSyncWrite(
      {required this.endpoint,
      required this.deviceId,
      required this.domain,
      required this.idempotencyKey,
      required this.localRevision,
      required this.baseRevision,
      required this.envelope});
}

/// Durable, endpoint/device-scoped journal. Network never gates the local commit.
class SyncOutboxStore {
  final AppDatabase database;
  SyncOutboxStore(this.database);
  Future<void>? _init;
  Future<void> init() => _init ??= _create();
  Future<void> _create() async {
    await database
        .customStatement('''CREATE TABLE IF NOT EXISTS sync_local_object (
      endpoint TEXT NOT NULL, device_id TEXT NOT NULL, domain TEXT NOT NULL,
      local_revision INTEGER NOT NULL, remote_revision INTEGER NOT NULL,
      envelope TEXT NOT NULL, PRIMARY KEY(endpoint,device_id,domain))''');
    await database.customStatement('''CREATE TABLE IF NOT EXISTS sync_outbox (
      endpoint TEXT NOT NULL, device_id TEXT NOT NULL, domain TEXT NOT NULL,
      local_revision INTEGER NOT NULL, base_revision INTEGER NOT NULL,
      envelope TEXT NOT NULL, idempotency_key TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'PENDING', PRIMARY KEY(endpoint,device_id,domain))''');
    // Freeze attempted uploads until acknowledged, including across restarts.
    // Later edits remain in outbox and cannot replace an ambiguous HTTP write.
    await database.customStatement('''CREATE TABLE IF NOT EXISTS sync_inflight (
      endpoint TEXT NOT NULL, device_id TEXT NOT NULL, domain TEXT NOT NULL,
      local_revision INTEGER NOT NULL, base_revision INTEGER NOT NULL,
      envelope TEXT NOT NULL, idempotency_key TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'PENDING', PRIMARY KEY(endpoint,device_id,domain))''');
  }

  Future<int> remoteRevision(
      String endpoint, String deviceId, String domain) async {
    await init();
    final rows = await database
        .customSelect(
            'SELECT remote_revision FROM sync_local_object WHERE endpoint=? AND device_id=? AND domain=?',
            variables: _scope(endpoint, deviceId, domain))
        .get();
    return rows.isEmpty ? 0 : rows.single.read<int>('remote_revision');
  }

  Future<void> writeLocal(String endpoint, String deviceId, String domain,
      Map<String, dynamic> envelope) async {
    await init();
    await database.transaction(() async {
      final rows = await database
          .customSelect(
              'SELECT local_revision,remote_revision FROM sync_local_object WHERE endpoint=? AND device_id=? AND domain=?',
              variables: _scope(endpoint, deviceId, domain))
          .get();
      final local =
          rows.isEmpty ? 1 : rows.single.read<int>('local_revision') + 1;
      final remote =
          rows.isEmpty ? 0 : rows.single.read<int>('remote_revision');
      final encoded = jsonEncode({...envelope, 'baseRevision': remote});
      await database.customStatement(
          '''INSERT INTO sync_local_object VALUES(?,?,?,?,?,?)
        ON CONFLICT(endpoint,device_id,domain) DO UPDATE SET local_revision=excluded.local_revision,envelope=excluded.envelope''',
          [endpoint, deviceId, domain, local, remote, encoded]);
      await database.customStatement(
          '''INSERT INTO sync_outbox(endpoint,device_id,domain,local_revision,base_revision,envelope,idempotency_key) VALUES(?,?,?,?,?,?,?)
        ON CONFLICT(endpoint,device_id,domain) DO UPDATE SET local_revision=excluded.local_revision,base_revision=excluded.base_revision,envelope=excluded.envelope,idempotency_key=excluded.idempotency_key,state='PENDING' ''',
          [
            endpoint,
            deviceId,
            domain,
            local,
            remote,
            encoded,
            const Uuid().v4()
          ]);
    });
  }

  Future<List<PendingSyncWrite>> pending(
      String endpoint, String deviceId) async {
    await init();
    final rows = await database.transaction(() async {
      await database.customStatement('''INSERT OR IGNORE INTO sync_inflight
        SELECT * FROM sync_outbox WHERE endpoint=? AND device_id=? AND state='PENDING' ''',
          [endpoint, deviceId]);
      return database.customSelect(
          "SELECT * FROM sync_inflight WHERE endpoint=? AND device_id=? AND state='PENDING' ORDER BY domain",
          variables: [Variable(endpoint), Variable(deviceId)]).get();
    });
    return rows
        .map((row) => PendingSyncWrite(
            endpoint: endpoint,
            deviceId: deviceId,
            domain: row.read<String>('domain'),
            idempotencyKey: row.read<String>('idempotency_key'),
            localRevision: row.read<int>('local_revision'),
            baseRevision: row.read<int>('base_revision'),
            envelope: (jsonDecode(row.read<String>('envelope')) as Map)
                .cast<String, dynamic>()))
        .toList();
  }

  Future<void> acknowledge(PendingSyncWrite sent, int remoteRevision) async {
    await init();
    await database.transaction(() async {
      final active = await database
          .customSelect(
              'SELECT idempotency_key FROM sync_inflight WHERE endpoint=? AND device_id=? AND domain=?',
              variables: _scope(sent.endpoint, sent.deviceId, sent.domain))
          .get();
      if (active.isEmpty ||
          active.single.read<String>('idempotency_key') !=
              sent.idempotencyKey) {
        return; // Ignore duplicate/stale acknowledgements.
      }
      await database.customStatement(
          'DELETE FROM sync_inflight WHERE endpoint=? AND device_id=? AND domain=?',
          [sent.endpoint, sent.deviceId, sent.domain]);
      await database.customStatement(
          'UPDATE sync_local_object SET remote_revision=? WHERE endpoint=? AND device_id=? AND domain=?',
          [remoteRevision, sent.endpoint, sent.deviceId, sent.domain]);
      await database.customStatement(
          'DELETE FROM sync_outbox WHERE endpoint=? AND device_id=? AND domain=? AND local_revision=? AND idempotency_key=?',
          [
            sent.endpoint,
            sent.deviceId,
            sent.domain,
            sent.localRevision,
            sent.idempotencyKey
          ]);
      // A newer local write may have arrived while the acknowledged upload was in flight.
      final remaining = await database
          .customSelect(
              'SELECT envelope FROM sync_outbox WHERE endpoint=? AND device_id=? AND domain=?',
              variables: _scope(sent.endpoint, sent.deviceId, sent.domain))
          .get();
      if (remaining.isNotEmpty) {
        final envelope =
            (jsonDecode(remaining.single.read<String>('envelope')) as Map)
                .cast<String, dynamic>();
        envelope['baseRevision'] = remoteRevision;
        await database.customStatement(
            'UPDATE sync_outbox SET base_revision=?,envelope=? WHERE endpoint=? AND device_id=? AND domain=?',
            [
              remoteRevision,
              jsonEncode(envelope),
              sent.endpoint,
              sent.deviceId,
              sent.domain
            ]);
      }
    });
  }

  Future<void> conflict(PendingSyncWrite sent) async {
    await init();
    await database.transaction(() async {
      await database.customStatement(
          "UPDATE sync_inflight SET state='CONFLICT' WHERE endpoint=? AND device_id=? AND domain=? AND idempotency_key=?",
          [sent.endpoint, sent.deviceId, sent.domain, sent.idempotencyKey]);
      await database.customStatement(
          "UPDATE sync_outbox SET state='CONFLICT' WHERE endpoint=? AND device_id=? AND domain=?",
          [sent.endpoint, sent.deviceId, sent.domain]);
    });
  }

  /// Explicit resolution only: preserve the latest local encrypted snapshot.
  Future<void> resolveWithLocal(String endpoint, String deviceId, String domain,
      int remoteRevision) async {
    await init();
    await database.transaction(() async {
      final rows = await database
          .customSelect(
              'SELECT local_revision,envelope FROM sync_local_object WHERE endpoint=? AND device_id=? AND domain=?',
              variables: _scope(endpoint, deviceId, domain))
          .get();
      if (rows.isEmpty) throw StateError('没有可用于解决冲突的本地对象');
      final envelope = (jsonDecode(rows.single.read<String>('envelope')) as Map)
          .cast<String, dynamic>();
      envelope['baseRevision'] = remoteRevision;
      await database.customStatement(
          'DELETE FROM sync_inflight WHERE endpoint=? AND device_id=? AND domain=?',
          [endpoint, deviceId, domain]);
      await database.customStatement(
          'UPDATE sync_local_object SET remote_revision=? WHERE endpoint=? AND device_id=? AND domain=?',
          [remoteRevision, endpoint, deviceId, domain]);
      await database.customStatement(
          '''INSERT INTO sync_outbox
          (endpoint,device_id,domain,local_revision,base_revision,envelope,idempotency_key,state)
          VALUES(?,?,?,?,?,?,?,'PENDING') ON CONFLICT(endpoint,device_id,domain)
          DO UPDATE SET local_revision=excluded.local_revision,base_revision=excluded.base_revision,
          envelope=excluded.envelope,idempotency_key=excluded.idempotency_key,state='PENDING' ''',
          [
            endpoint,
            deviceId,
            domain,
            rows.single.read<int>('local_revision'),
            remoteRevision,
            jsonEncode(envelope),
            const Uuid().v4()
          ]);
    });
  }

  /// User chose remote: discard pending uploads for this scope, not local data.
  Future<void> acceptRemote(String endpoint, String deviceId, String domain,
      int revision, Map<String, dynamic> envelope) async {
    await init();
    await database.transaction(() async {
      for (final table in ['sync_outbox', 'sync_inflight']) {
        await database.customStatement(
            'DELETE FROM $table WHERE endpoint=? AND device_id=? AND domain=?',
            [endpoint, deviceId, domain]);
      }
      await database.customStatement(
          '''INSERT INTO sync_local_object VALUES(?,?,?,?,?,?)
        ON CONFLICT(endpoint,device_id,domain) DO UPDATE SET
        local_revision=sync_local_object.local_revision+1,
        remote_revision=excluded.remote_revision,envelope=excluded.envelope''',
          [
            endpoint,
            deviceId,
            domain,
            1,
            revision,
            jsonEncode({...envelope, 'baseRevision': revision})
          ]);
    });
  }

  List<Variable> _scope(String endpoint, String deviceId, String domain) =>
      [Variable(endpoint), Variable(deviceId), Variable(domain)];
}
