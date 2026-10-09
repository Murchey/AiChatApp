import 'dart:convert';
import 'dart:io';
import 'package:ai_chat/data/db/app_database.dart';
import 'package:ai_chat/services/sync_crypto.dart';
import 'package:ai_chat/services/sync_outbox_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encryption authenticates content and does not expose UI settings', () {
    final key = SyncCrypto.generateKey();
    final envelope =
        SyncCrypto.encrypt({'homeNavigationStyle': 'floating'}, key, 0);
    expect(jsonEncode(envelope), isNot(contains('homeNavigationStyle')));
    expect(
        SyncCrypto.decrypt(envelope, key)['homeNavigationStyle'], 'floating');
    expect(() => SyncCrypto.decrypt(envelope, SyncCrypto.generateKey()),
        throwsFormatException);
    expect(() => SyncCrypto.decrypt({...envelope, 'sha256': 'bad'}, key),
        throwsFormatException);
  });
  test('sync key bundle is password wrapped and portable', () {
    final key = SyncCrypto.generateKey();
    final bundle = SyncCrypto.exportKey(key, 'strong-password');
    expect(bundle, isNot(contains(base64Encode(key))));
    expect(SyncCrypto.importKey(bundle, 'strong-password'), key);
    expect(() => SyncCrypto.importKey(bundle, 'wrong-pass'),
        throwsFormatException);
    expect(() => SyncCrypto.exportKey(key, 'short'), throwsArgumentError);
  });
  test('offline journal survives restart and coalesces local changes',
      () async {
    final temp = await Directory.systemTemp.createTemp('aichat-sync-test-');
    final file = File('${temp.path}/sync.sqlite');
    final first = AppDatabase.forTesting(NativeDatabase(file));
    final store = SyncOutboxStore(first);
    await store.writeLocal(
        'https://server', 'device', 'settings', {'ciphertext': 'first'});
    await store.writeLocal(
        'https://server', 'device', 'settings', {'ciphertext': 'second'});
    await first.close();
    final restored = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final journal = SyncOutboxStore(restored);
      final writes = await journal.pending('https://server', 'device');
      expect(writes, hasLength(1));
      expect(writes.single.localRevision, 2);
      expect(writes.single.envelope['ciphertext'], 'second');
      expect(await journal.pending('https://other', 'device'), isEmpty);
      expect(await journal.pending('https://server', 'other'), isEmpty);
      await journal.writeLocal(
          'https://server', 'device', 'settings', {'ciphertext': 'third'});
      await journal.acknowledge(writes.single, 1);
      final newer = (await journal.pending('https://server', 'device')).single;
      expect(newer.localRevision, 3);
      expect(newer.baseRevision, 1);
      expect(newer.envelope['ciphertext'], 'third');
      await journal.acknowledge(newer, 2);
      await journal.acknowledge(writes.single, 1);
      expect(await journal.pending('https://server', 'device'), isEmpty);
      expect(
          await journal.remoteRevision('https://server', 'device', 'settings'),
          2);
    } finally {
      await restored.close();
      await temp.delete(recursive: true);
    }
  });
  test('lost acknowledgement retries frozen payload after edit and restart',
      () async {
    final temp = await Directory.systemTemp.createTemp('aichat-sync-retry-');
    final file = File('${temp.path}/sync.sqlite');
    final first = AppDatabase.forTesting(NativeDatabase(file));
    final store = SyncOutboxStore(first);
    await store
        .writeLocal('server', 'device', 'settings', {'ciphertext': 'sent'});
    final sent = (await store.pending('server', 'device')).single;
    await store
        .writeLocal('server', 'device', 'settings', {'ciphertext': 'new'});
    await first.close();
    final reopened = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final restored = SyncOutboxStore(reopened);
      final retry = (await restored.pending('server', 'device')).single;
      expect(retry.idempotencyKey, sent.idempotencyKey);
      expect(retry.envelope, sent.envelope);
      await restored.acknowledge(retry, 1);
      final next = (await restored.pending('server', 'device')).single;
      expect(next.envelope['ciphertext'], 'new');
      expect(next.baseRevision, 1);
      expect(next.idempotencyKey, isNot(sent.idempotencyKey));
      await restored.conflict(next);
      await restored.writeLocal(
          'server', 'device', 'settings', {'ciphertext': 'still local'});
      expect(await restored.pending('server', 'device'), isEmpty);
      await restored.resolveWithLocal('server', 'device', 'settings', 3);
      final resolved = (await restored.pending('server', 'device')).single;
      expect(resolved.baseRevision, 3);
      expect(resolved.envelope['ciphertext'], 'still local');
      await restored.acceptRemote(
          'server', 'device', 'settings', 4, {'ciphertext': 'remote'});
      expect(await restored.pending('server', 'device'), isEmpty);
      expect(await restored.remoteRevision('server', 'device', 'settings'), 4);
    } finally {
      await reopened.close();
      await temp.delete(recursive: true);
    }
  });
}
