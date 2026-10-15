import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/models/workshop_repository.dart';
import 'package:ai_chat/services/app_theme_store.dart';
import 'package:ai_chat/services/backup_crypto.dart';
import 'package:ai_chat/services/backup_service.dart';
import 'package:ai_chat/services/cos_auth.dart';
import 'package:ai_chat/services/storage_migration_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Isolate actual backup files and SQLite from application data.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BackupPaths extends PathProviderPlatform {
  _BackupPaths(this.base);
  final Directory base;
  String get documents => '${base.path}/documents';
  @override
  Future<String?> getApplicationDocumentsPath() async => documents;
  @override
  Future<String?> getApplicationSupportPath() async => '${base.path}/support';
  @override
  Future<String?> getTemporaryPath() async => '${base.path}/temp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'full and encrypted backups restore theme files, sources and adjustments',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('aichat-theme-backup-');
    final previousPaths = PathProviderPlatform.instance;
    final paths = _BackupPaths(dir);
    PathProviderPlatform.instance = paths;
    for (final name in ['documents', 'support', 'temp']) {
      await Directory('${dir.path}/$name').create();
    }
    final store = AppThemeStore();
    var databaseOpened = false;
    try {
      await StorageMigrationService.init();
      databaseOpened = true;
      final pack = await store.install('docs/soft-cloud-theme.zip');
      await store.enable(pack.id);
      await store.adjust('textLight', 0xFF123456);
      await store.adjust('textDark', 0xFFABCDEF);
      await store.adjust('font', '__theme__');
      await store.adjust('bubble', true);
      await store.saveRepositories(const [
        WorkshopRepository(
          id: 'theme-source',
          name: '主题仓库',
          url: 'https://example.com/workshop/',
          proxyUrl: '',
          type: WorkshopRepoType.cos,
          cosAuth: CosAuth(
              enabled: true,
              accessKeyId: 'private-id',
              secretAccessKey: 'private-key'),
        ),
      ]);
      final expectedFiles = <String, List<int>>{};
      await for (final file
          in Directory(pack.directory).list(recursive: true)) {
        if (file is File) {
          final relative = file.path
              .substring(paths.documents.length + 1)
              .replaceAll('\\', '/');
          expectedFiles['files/$relative'] = await file.readAsBytes();
        }
      }
      expect(expectedFiles.keys,
          contains('files/app_themes/${pack.id}/content.json'));
      expect(expectedFiles.keys.any((p) => p.endsWith('.ttf')), true);

      // Exercise both backup variants used by local/cloud/manual/scheduled flows.
      final exports = [
        await BackupService.exportBackupZip(),
        await BackupService.exportBackupZip(password: 'test-backup-password'),
      ];
      for (var i = 0; i < exports.length; i++) {
        final output = exports[i];
        final bytes = i == 0
            ? output.bytes
            : BackupCrypto.decrypt(output.bytes, 'test-backup-password');
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final entry in expectedFiles.entries) {
          expect(
              archive.findFile(entry.key)?.content, orderedEquals(entry.value),
              reason: entry.key);
        }
        final prefsJson =
            utf8.decode(archive.findFile('prefs.json')!.content as List<int>);
        expect(prefsJson, contains('app_theme_active'));
        expect(prefsJson, contains('app_theme_adjustments'));
        expect(prefsJson, contains('app_theme_repositories'));
        expect(prefsJson, isNot(contains('private-key')));
        expect(prefsJson, isNot(contains('private-id')));

        await Directory('${paths.documents}/app_themes')
            .delete(recursive: true);
        await (await SharedPreferences.getInstance()).clear();
        FlutterSecureStorage.setMockInitialValues({});
        await store.init();
        expect(store.installed, isEmpty);
        final backup = File('${dir.path}/backup-$i.zip');
        await backup.writeAsBytes(output.bytes);
        await BackupService.restoreLocalBackup(backup,
            password: i == 0 ? null : 'test-backup-password');
        await store.init(); // Same reload performed by the backup screen.
        expect(store.activeId, pack.id);
        expect(store.installed.single.id, pack.id);
        expect(store.bubbleEnabled, true);
        expect(store.textColor(false)!.toARGB32(), 0xFF123456);
        expect(store.textColor(true)!.toARGB32(), 0xFFABCDEF);
        expect(store.fontFamily, isNotNull);
        expect(store.adjustments['bubble'], true);
        expect(store.repositories.single.url, 'https://example.com/workshop/');
        expect(store.repositories.single.cosAuth.secretAccessKey, isEmpty);
        for (final entry in expectedFiles.entries) {
          final relative = entry.key.substring('files/'.length);
          expect(await File('${paths.documents}/$relative').readAsBytes(),
              orderedEquals(entry.value),
              reason: relative);
        }
      }
    } finally {
      store.dispose();
      if (databaseOpened) await StorageMigrationService.database.close();
      PathProviderPlatform.instance = previousPaths;
      await dir.delete(recursive: true);
    }
  });
}
