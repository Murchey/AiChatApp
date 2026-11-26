import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/data/dao/conversation_dao.dart';
import 'package:ai_chat/models/auto_memory_op.dart';
import 'package:ai_chat/providers/memory_point_provider.dart';
import 'package:ai_chat/services/storage_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
  @override
  Future<String?> getApplicationSupportPath() async => root.path;
  @override
  Future<String?> getTemporaryPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform originalPaths;
  late ConversationDao dao;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('memory-transaction-');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root);
    await StorageMigrationService.init();
    dao = ConversationDao(StorageMigrationService.database);
  });

  setUp(() async {
    MemoryPointProvider.transactionTestHook = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await dao.setMeta('auto_memory_transaction_v1', '');
    await dao.setMeta('auto_memory_cursors', '');
  });

  tearDownAll(() async {
    MemoryPointProvider.transactionTestHook = null;
    await StorageMigrationService.database.close();
    PathProviderPlatform.instance = originalPaths;
    await root.delete(recursive: true);
  });

  for (final stage in ['journal', 'committed', 'points', 'cursor']) {
    test('recovers deterministically after failure at $stage', () async {
      final provider = MemoryPointProvider();
      await provider.init();
      await provider.addPoints('character', ['user memory']);
      MemoryPointProvider.transactionTestHook = (current) async {
        if (current == stage) throw StateError('injected failure');
      };
      await expectLater(
        provider.applyAutoOperations('character', [
          const AutoMemoryOp(op: AutoMemoryOp.opAdd, content: 'generated'),
        ], conversationId: 'conversation', cursorCount: 10, cursorLastId: 'last'),
        throwsStateError,
      );
      MemoryPointProvider.transactionTestHook = null;
      final reopened = MemoryPointProvider();
      await reopened.init();
      final contents = reopened.pointsFor('character').map((p) => p.content);
      expect(contents, contains('user memory'));
      final cursor = await dao.meta('auto_memory_cursors');
      if (stage == 'journal') {
        expect(contents, isNot(contains('generated')));
        expect(cursor, isEmpty);
      } else {
        expect(contents, contains('generated'));
        expect((jsonDecode(cursor!) as Map)['conversation']['lastId'], 'last');
        expect(await dao.meta('auto_memory_transaction_v1'), isEmpty);
      }
      provider.dispose();
      reopened.dispose();
    });
  }

  test('backup barrier prevents concurrent mutations', () async {
    final provider = MemoryPointProvider();
    await provider.init();
    final entered = Completer<void>();
    final release = Completer<void>();
    final backup = MemoryPointProvider.withBackupBarrier(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    var finished = false;
    final mutation = provider.addPoints('character', ['new']).then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    release.complete();
    await backup;
    await mutation;
    expect(provider.pointsFor('character').single.content, 'new');
    provider.dispose();
  });
}
