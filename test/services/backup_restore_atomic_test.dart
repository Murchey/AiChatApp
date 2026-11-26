import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat/services/backup_service.dart';
import 'package:ai_chat/services/storage_migration_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      '${root.path}/documents';
  @override
  Future<String?> getApplicationSupportPath() async => '${root.path}/support';
  @override
  Future<String?> getTemporaryPath() async => '${root.path}/temp';
}

Uint8List _zip(Map<String, dynamic> prefs, {List<int>? sqlite}) {
  final archive = Archive();
  archive.addFile(ArchiveFile.string('prefs.json', jsonEncode(prefs)));
  archive.addFile(ArchiveFile.string('files/stickers/new.txt', 'new'));
  archive.addFile(ArchiveFile.string('files/root.txt', 'new-root'));
  if (sqlite != null) {
    archive.addFile(ArchiveFile('database.sqlite', sqlite.length, sqlite));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Paths paths;
  late PathProviderPlatform previous;
  late SharedPreferences prefs;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('restore-atomic-');
    for (final name in ['documents', 'support', 'temp']) {
      await Directory('${root.path}/$name').create();
    }
    paths = _Paths(root);
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = paths;
    await StorageMigrationService.init();
    prefs = await SharedPreferences.getInstance();
  });
  setUp(() async {
    await prefs.clear();
    await prefs.setString('api_key', 'private-key');
    await prefs.setString('setting', 'original');
    final old = File('${root.path}/documents/stickers/old.txt');
    await old.parent.create(recursive: true);
    await old.writeAsString('old');
    await File('${root.path}/documents/root.txt').writeAsString('old-root');
    await StorageMigrationService.database.customStatement(
        "INSERT OR REPLACE INTO character_metas (key, value) VALUES ('test', 'original')");
  });
  tearDownAll(() async {
    await StorageMigrationService.database.close();
    PathProviderPlatform.instance = previous;
    await root.delete(recursive: true);
  });
  Future<void> checkOriginal() async {
    expect(prefs.getString('api_key'), 'private-key');
    expect(prefs.getString('setting'), 'original');
    expect(await File('${root.path}/documents/stickers/old.txt').readAsString(),
        'old');
    expect(await File('${root.path}/documents/root.txt').readAsString(),
        'old-root');
    expect(await File('${root.path}/documents/stickers/new.txt').exists(),
        isFalse);
    final rows = await StorageMigrationService.database
        .customSelect("SELECT value FROM character_metas WHERE key = 'test'")
        .get();
    expect(rows.single.read<String>('value'), 'original');
  }

  test('preference failure rolls back secrets and files', () async {
    await expectLater(
        BackupService.restoreZipBytes(_zip({
          'setting': {'t': 'i', 'v': 'invalid'}
        })),
        throwsStateError);
    await checkOriginal();
  });
  test(
      'failure after file replacement rolls back files, preferences and SQLite',
      () async {
    final snapshot = File('${root.path}/snapshot.sqlite');
    await StorageMigrationService.database.customStatement(
        "UPDATE character_metas SET value = 'backup' WHERE key = 'test'");
    await StorageMigrationService.exportSqlite(snapshot);
    await StorageMigrationService.database.customStatement(
        "UPDATE character_metas SET value = 'original' WHERE key = 'test'");
    await expectLater(
        BackupService.restoreZipBytes(
            _zip({'setting': 'new'}, sqlite: await snapshot.readAsBytes()),
            onProgress: (_, stage) {
          if (stage == '恢复用户文件') throw StateError('injected failure');
        }),
        throwsStateError);
    await checkOriginal();
  });
  test('invalid SQLite import preserves original data', () async {
    await expectLater(
        BackupService.restoreZipBytes(
            _zip({'setting': 'new'}, sqlite: utf8.encode('bad database'))),
        throwsStateError);
    await checkOriginal();
  });
}
