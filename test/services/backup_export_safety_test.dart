import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat/services/backup_crypto.dart';
import 'package:ai_chat/services/backup_schedule_service.dart';
import 'package:ai_chat/services/backup_service.dart';
import 'package:ai_chat/services/cloud_backup_service.dart';
import 'package:ai_chat/services/storage_migration_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BackupPaths extends PathProviderPlatform {
  _BackupPaths(this.base);
  final Directory base;
  bool failDocuments = false;
  String get documents => '${base.path}/documents';

  @override
  Future<String?> getApplicationDocumentsPath() async {
    if (failDocuments) throw StateError('simulated path provider failure');
    return documents;
  }

  @override
  Future<String?> getApplicationSupportPath() async => '${base.path}/support';

  @override
  Future<String?> getTemporaryPath() async => '${base.path}/temp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _BackupPaths paths;
  late PathProviderPlatform previousPaths;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('aichat-backup-safety-');
    paths = _BackupPaths(root);
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = paths;
    for (final directory in ['documents', 'support', 'temp']) {
      await Directory('${root.path}/$directory').create();
    }
    await StorageMigrationService.init();
  });

  tearDownAll(() async {
    await StorageMigrationService.database.close();
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  });

  test('encrypted export keeps v2 format and UI event loop responsive',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'test_backup_settings',
        jsonEncode({
          'asset': '${paths.documents}/stickers/image.bin',
          'apiKey': 'sensitive-secret',
        }));
    await prefs.setString(
        'test_backup_path', '${paths.documents}/stickers/image.bin');
    final asset = File('${paths.documents}/stickers/image.bin');
    await asset.parent.create(recursive: true);
    await asset.writeAsBytes(Uint8List.fromList(
      List<int>.generate(128 * 1024, (index) => (index * 37) % 256),
    ));
    var ticksDuringEncoding = 0;
    Timer? ticker;
    try {
      final output = await BackupService.exportBackupZip(
        password: 'compatibility-password',
        onProgress: (progress, stage) {
          if (stage == '压缩打包') {
            ticker = Timer.periodic(const Duration(milliseconds: 1), (_) {
              ticksDuringEncoding++;
            });
          }
        },
      );
      ticker?.cancel();
      expect(ticksDuringEncoding, greaterThan(0));
      expect(output.size, output.bytes.length);
      expect(BackupCrypto.isEncrypted(output.bytes), isTrue);
      final decrypted = await BackupCrypto.decryptInIsolate(
          output.bytes, 'compatibility-password');
      final archive = ZipDecoder().decodeBytes(decrypted);
      expect(archive.findFile('database.sqlite'), isNotNull);
      expect(archive.findFile('files/stickers/image.bin')!.content,
          orderedEquals(await asset.readAsBytes()));
      final manifest = jsonDecode(
          utf8.decode(archive.findFile('manifest.json')!.content as List<int>));
      expect(manifest['format'], BackupService.formatVersion);
      final settings =
          utf8.decode(archive.findFile('prefs.json')!.content as List<int>);
      expect(settings, contains('{DOCS}/stickers/image.bin'));
      expect(settings, isNot(contains('sensitive-secret')));
    } finally {
      ticker?.cancel();
    }
  });

  test('failed cloud upload never lists or deletes previous backups', () async {
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);
      return http.Response('simulated upload failure', 500);
    });
    await http.runWithClient(() async {
      await expectLater(
        BackupScheduleService.runCloudAutoBackup(
          const CloudBackupConfig(
              secretId: 'id',
              secretKey: 'key',
              bucketUrl: 'https://backup.example.com'),
          const BackupScheduleConfig(mode: BackupScheduleMode.daily),
        ),
        throwsA(isA<HttpException>()),
      );
    }, () => client);
    expect(methods, ['PUT']);
    expect(await BackupScheduleService.lastCloudRun(), isNull);
  });

  test('cloud retention follows upload and excludes the completed object',
      () async {
    final methods = <String>[];
    String? newKey;
    final client = MockClient((request) async {
      methods.add(request.method);
      if (request.method == 'PUT') {
        newKey = request.url.path.substring(1);
        return http.Response('', 200);
      }
      if (request.method == 'GET') {
        return http.Response(
            '<ListBucketResult>'
            '<Contents><Key>backups/v1/aichat_auto_old.zip</Key><Size>1</Size></Contents>'
            '<Contents><Key>$newKey</Key><Size>1</Size></Contents>'
            '<Contents><Key>backups/v1/aichat_backup_manual.zip</Key><Size>1</Size></Contents>'
            '</ListBucketResult>',
            200);
      }
      if (request.method == 'DELETE') {
        expect(request.url.path, '/backups/v1/aichat_auto_old.zip');
        return http.Response('', 204);
      }
      expect(request.method, 'HEAD');
      return http.Response('', 404);
    });
    await http.runWithClient(() async {
      await BackupScheduleService.runCloudAutoBackup(
        const CloudBackupConfig(
            secretId: 'id',
            secretKey: 'key',
            bucketUrl: 'https://backup.example.com'),
        const BackupScheduleConfig(mode: BackupScheduleMode.daily),
      );
    }, () => client);
    expect(methods, ['PUT', 'GET', 'DELETE', 'HEAD']);
    expect(await BackupScheduleService.lastCloudRun(), isNotNull);
  });

  test('failed automatic export preserves previous local backup', () async {
    final directory = await BackupService.localBackupDir();
    final previous = File('${directory.path}/aichat_auto_previous.zip');
    await previous.writeAsString('known-good-previous');
    paths.failDocuments = true;
    try {
      await expectLater(
          BackupScheduleService.runLocalAutoBackup(
              const BackupScheduleConfig(mode: BackupScheduleMode.daily)),
          throwsStateError);
    } finally {
      paths.failDocuments = false;
    }
    expect(await previous.readAsString(), 'known-good-previous');
  });

  test('overlapping automatic runs share one export and retain completed file',
      () async {
    final directory = await BackupService.localBackupDir();
    final manual = File('${directory.path}/aichat_backup_manual.zip');
    await manual.writeAsString('manual');
    const config = BackupScheduleConfig(mode: BackupScheduleMode.daily);
    final first = BackupScheduleService.runLocalAutoBackup(config);
    final second = BackupScheduleService.runLocalAutoBackup(config);
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    final files = await BackupService.listLocalBackups();
    final automatic =
        files.where((file) => file.path.contains('aichat_auto')).toList();
    expect(automatic, hasLength(1));
    expect(
        ZipDecoder()
            .decodeBytes(await automatic.single.readAsBytes())
            .findFile('database.sqlite'),
        isNotNull);
    expect(await manual.readAsString(), 'manual');
    expect(await BackupScheduleService.lastLocalRun(), isNotNull);
    expect(await directory.list().any((entry) => entry.path.contains('.tmp_')),
        isFalse);
  });
}
