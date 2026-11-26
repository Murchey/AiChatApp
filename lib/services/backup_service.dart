import 'chat_draft_service.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auto_memory_service.dart';
import 'backup_crypto.dart';
import 'storage_migration_service.dart';

/// 备份/恢复过程进度回调：[progress] 0~1，[stage] 为阶段说明。
typedef BackupProgressCallback = void Function(double progress, String stage);

Uint8List _encodeBackup(Map<String, Object?> request) {
  final output = OutputMemoryStream();
  final encoder = ZipEncoder()..startEncode(output);
  final entries = request['entries'] as List<String>;
  for (var i = 0; i < entries.length; i += 2) {
    final input = InputFileStream(entries[i + 1]);
    try {
      encoder.add(ArchiveFile.stream(entries[i], input), autoClose: true);
    } finally {
      input.closeSync();
    }
  }
  final prefs = request['prefs'] as Map<String, dynamic>;
  final docsPath = request['docsPath'] as String;
  final encodedPrefs = <String, dynamic>{};
  for (final entry in prefs.entries) {
    final sanitized = BackupService.sanitizePrefForExport(
      entry.key,
      BackupService._relativizePaths(entry.value, docsPath),
    );
    if (sanitized != null) {
      encodedPrefs[entry.key] = BackupService._encodePrefValue(sanitized);
    }
  }
  encoder.add(ArchiveFile.string(
    BackupService._manifestName,
    const JsonEncoder.withIndent('  ').convert(request['manifest']),
  ));
  encoder.add(ArchiveFile.string(
    BackupService._prefsName,
    const JsonEncoder.withIndent('  ').convert(encodedPrefs),
  ));
  encoder.endEncode();
  final zipBytes = output.getBytes();
  final password = request['password'] as String?;
  return password == null || password.isEmpty
      ? zipBytes
      : BackupCrypto.encrypt(zipBytes, password);
}

/// 本地导出结果
class LocalExport {
  final Uint8List bytes;
  final String fileName;
  final int size;

  const LocalExport({
    required this.bytes,
    required this.fileName,
    required this.size,
  });
}

/// 全量数据备份：导出 / 导入 / 恢复。
///
/// 备份 zip 结构（对齐 inkqilin-ledger 本地备份能力）：
///   manifest.json   格式与应用信息
///   prefs.json      全部 SharedPreferences（路径已相对化，兼容旧版本）
///   database.sqlite SQLite 核心数据快照（新版本优先恢复）
///   files/**        用户数据文件（相对文档目录）
///
/// 可选 AES-256-GCM 密码加密整包（密文布局见 [BackupCrypto]）。
class BackupService {
  static const int formatVersion = 2;
  static Future<void> _exportQueue = Future<void>.value();
  static const String _manifestName = 'manifest.json';
  static const String _prefsName = 'prefs.json';
  static const String _sqliteName = 'database.sqlite';
  static const String _filesPrefix = 'files/';
  static const String _docsPlaceholder = '{DOCS}';

  /// 应用私有本地备份目录（卸载会丢失，重要备份请导出到系统文件）
  static Future<Directory> localBackupDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docDir.path}/backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> _safetyDir() async {
    final base = await localBackupDir();
    final dir = Directory('${base.path}/pre_restore');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 需要纳入备份的用户数据目录名（相对文档目录）
  static const List<String> userDataDirs = [
    'stickers',
    'user_moments',
    'chat_backgrounds',
    'imported_fonts',
    'app_themes',
    'app_icons',
    'voice',
    'voice_samples',
  ];

  /// 需要纳入备份的用户数据目录前缀
  static const List<String> userDataDirPrefixes = [
    'moment_import_',
    'chat_import_',
  ];

  // These large records are represented by database.sqlite in format v2.
  // They remain readable from prefs.json when importing a format v1 backup.
  static const Set<String> _sqliteOwnedPrefsKeys = {
    'characters_v1',
    'characters_deleted_v1',
    'visibility_groups_v1',
    'chat_conversations_v1',
    'chat_messages_v1',
    'chat_context_tokens_v1',
    'chat_system_tokens_v1',
    'chat_roleplay_choices_v1',
  };

  /// 排除（缓存 / 系统 / 备份自身）
  static const List<String> _excludedDirs = [
    'workshop',
    'flutter_assets',
    'backups',
    'pre_restore',
  ];

  static bool _isUserDir(String name) {
    if (_excludedDirs.contains(name)) return false;
    return userDataDirs.contains(name) ||
        userDataDirPrefixes.any((p) => name.startsWith(p));
  }

  /// 生成全量备份字节；[password] 非空则 AES-GCM 加密整包。
  /// [fileNamePrefix] 用于区分自动 / 手动备份文件名（默认手动）。
  /// [onProgress] 可选进度回调（打包过程按文件推进）。
  static Future<LocalExport> exportBackupZip({
    String? password,
    String fileNamePrefix = 'aichat_backup',
    BackupProgressCallback? onProgress,
  }) {
    // Bound peak memory when manual, local, and cloud exports overlap.
    final operation = _exportQueue
        .then((_) => AutoMemoryService.withBackupBarrier(() => _exportBackupZip(
              password: password,
              fileNamePrefix: fileNamePrefix,
              onProgress: onProgress,
            )));
    _exportQueue =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  static Future<LocalExport> _exportBackupZip({
    String? password,
    required String fileNamePrefix,
    BackupProgressCallback? onProgress,
  }) async {
    void report(double p, String stage) =>
        onProgress?.call(p.clamp(0, 1), stage);

    report(0.02, '准备导出');
    final docDir = await getApplicationDocumentsDirectory();
    final prefs = await SharedPreferences.getInstance();
    final encrypted = password != null && password.isNotEmpty;

    // 1. SharedPreferences 全量（路径相对化 + 密钥脱敏）
    report(0.08, '读取应用设置');
    final rawPrefs = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (_sqliteOwnedPrefsKeys.contains(key)) continue;
      final value = prefs.get(key);
      if (value == null) continue;
      rawPrefs[key] = value;
    }

    final ts = _timestamp();
    final fileName = encrypted
        ? '${fileNamePrefix}_${ts}_enc.zip'
        : '${fileNamePrefix}_$ts.zip';

    // Only paths cross the isolate boundary. The worker reads and compresses
    // one file at a time, so all uncompressed assets are never held together.
    final archiveEntries = <String>[];

    // 2. 先统计用户文件数量，便于按比例回报进度
    report(0.12, '扫描用户文件');
    final pendingFiles = <File>[];
    final root = Directory(docDir.path);
    if (await root.exists()) {
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        final name = _basename(entity.path);
        if (!_isUserDir(name)) continue;
        await for (final file in entity.list(recursive: true)) {
          if (file is File) pendingFiles.add(file);
        }
      }
      await for (final entity in root.list()) {
        if (entity is! File) continue;
        final name = _basename(entity.path);
        // v2 already contains a consistent database.sqlite snapshot; never
        // archive the live Drift database or its WAL sidecars as user files.
        if (name == 'ai_chat_core.sqlite' ||
            name == 'ai_chat_core.sqlite-wal' ||
            name == 'ai_chat_core.sqlite-shm' ||
            name.startsWith('.')) {
          continue;
        }
        pendingFiles.add(entity);
      }
    }

    var fileCount = 0;
    final total = pendingFiles.isEmpty ? 1 : pendingFiles.length;
    for (var i = 0; i < pendingFiles.length; i++) {
      final file = pendingFiles[i];
      final rel = _relativeTo(file.path, docDir.path) ?? _basename(file.path);
      archiveEntries
        ..add('files/$rel')
        ..add(file.path);
      fileCount++;
      if (i % 5 == 0 || i == pendingFiles.length - 1) {
        report(
          0.15 + 0.65 * ((i + 1) / total),
          '打包用户文件 ${i + 1}/$total',
        );
      }
    }

    report(0.84, '写入清单与设置');
    final manifest = <String, dynamic>{
      'app': 'AiChat',
      'format': formatVersion,
      'app_version': await _appVersion(),
      'export_time': DateTime.now().toIso8601String(),
      'file_count': fileCount,
    };

    // SQLite is the efficient primary representation for large core data.
    // prefs.json remains for settings and for importing older format-v1 ZIPs.
    report(0.86, '生成 SQLite 数据快照');
    final sqliteTemp = File(
      '${docDir.path}/.aichat_backup_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    try {
      await ChatDraftService.instance.flushAll();
      await StorageMigrationService.exportSqlite(sqliteTemp);
      archiveEntries
        ..add(_sqliteName)
        ..add(sqliteTemp.path);

      report(0.88, '压缩打包');
      // compute transfers the returned bytes using Isolate.exit on native platforms.
      // ZIP and encryption share one worker, so the ZIP never returns to the UI.
      final out = await compute(_encodeBackup, <String, Object?>{
        'entries': archiveEntries,
        'prefs': rawPrefs,
        'docsPath': docDir.path,
        'manifest': manifest,
        'password': password,
      });
      report(1, '导出完成');
      return LocalExport(bytes: out, fileName: fileName, size: out.length);
    } finally {
      if (await sqliteTemp.exists()) await sqliteTemp.delete();
    }
  }

  /// 生成备份并写入本地备份目录，返回目标文件。
  /// [fileNamePrefix]：手动 `aichat_backup`，自动 `aichat_auto`。
  static Future<File> createLocalBackup({
    String? password,
    String fileNamePrefix = 'aichat_backup',
    BackupProgressCallback? onProgress,
  }) async {
    final export = await exportBackupZip(
      password: password,
      fileNamePrefix: fileNamePrefix,
      onProgress: (p, stage) {
        // 预留最后 8% 给写入本地文件
        onProgress?.call(p * 0.92, stage);
      },
    );
    onProgress?.call(0.94, '写入本地备份');
    final dir = await localBackupDir();
    final target = File('${dir.path}/${export.fileName}');
    final temp =
        File('${target.path}.tmp_${DateTime.now().microsecondsSinceEpoch}');
    try {
      await temp.writeAsBytes(export.bytes, flush: true);
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
    onProgress?.call(1, '本地备份完成');
    return target;
  }

  /// 删除指定前缀的本地备份（用于自动备份清理上一份），返回删除数量。
  /// 只匹配同前缀文件，不影响手动备份。
  static Future<int> deleteLocalBackupsByPrefix(
    String prefix, {
    String? exceptPath,
  }) async {
    final dir = await localBackupDir();
    if (!await dir.exists()) return 0;
    var deleted = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      if ((exceptPath != null && name == _basename(exceptPath)) ||
          !name.startsWith(prefix)) {
        continue;
      }
      if (await deleteLocalBackup(entity)) deleted++;
    }
    return deleted;
  }

  static Future<List<File>> listLocalBackups() async {
    final dir = await localBackupDir();
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = _basename(entity.path).toLowerCase();
      if (name.endsWith('.zip') || name.endsWith('.aibackup')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// 从系统选择器拷贝到本地的 zip 路径导入到本地备份列表。
  /// 接受明文 zip（PK 开头）或本应用加密包（AIBK1）。
  static Future<File> importBackupFromPath(
    String sourcePath, {
    String? displayName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('无法读取所选文件');
    }
    final bytes = await source.readAsBytes();
    if (bytes.length < 32) {
      throw StateError('文件过小，不是有效备份');
    }

    final isZip = bytes[0] == 0x50 && bytes[1] == 0x4B;
    final isEnc = BackupCrypto.isEncrypted(bytes);
    if (!isZip && !isEnc) {
      throw StateError('不是 AiChat 备份文件（需为 zip 或本应用加密包）');
    }
    if (isZip) {
      try {
        ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        throw StateError('zip 无法解析：$e');
      }
    }

    var name = _basename(displayName ?? sourcePath).trim();
    if (name.isEmpty) {
      name = 'imported_${DateTime.now().millisecondsSinceEpoch}';
    }
    if (!name.toLowerCase().endsWith('.zip') &&
        !name.toLowerCase().endsWith('.aibackup')) {
      name = isEnc ? '${name}_enc.zip' : '$name.zip';
    }

    final dir = await localBackupDir();
    var target = File('${dir.path}/$name');
    var seq = 1;
    while (await target.exists()) {
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot + 1) : 'zip';
      target = File('${dir.path}/${base}_$seq.$ext');
      seq++;
    }
    await target.writeAsBytes(bytes, flush: true);
    return target;
  }

  static bool isLocalBackupEncrypted(File file) {
    if (!file.existsSync() || file.lengthSync() < 5) return false;
    final raf = file.openSync();
    try {
      final header = raf.readSync(5);
      return header.length >= 5 &&
          header[0] == 0x41 &&
          header[1] == 0x49 &&
          header[2] == 0x42 &&
          header[3] == 0x4B &&
          header[4] == 0x31;
    } finally {
      raf.closeSync();
    }
  }

  /// 用备份覆盖当前全部用户数据与设置。
  /// 恢复前自动写入安全副本；写入失败时回滚原数据。
  static Future<void> restoreLocalBackup(
    File file, {
    String? password,
    BackupProgressCallback? onProgress,
  }) async {
    void report(double p, String stage) =>
        onProgress?.call(p.clamp(0, 1), stage);

    report(0.05, '读取备份文件');
    if (!await file.exists()) {
      throw StateError('本地备份文件不存在');
    }
    final raw = await file.readAsBytes();
    Uint8List zipBytes;
    if (BackupCrypto.isEncrypted(raw)) {
      report(0.12, '解密备份包');
      zipBytes = await BackupCrypto.decryptInIsolate(raw, password ?? '');
    } else {
      zipBytes = raw;
    }
    await restoreZipBytes(zipBytes, onProgress: onProgress);
  }

  static Future<void> restoreZipBytes(
    Uint8List zipBytes, {
    BackupProgressCallback? onProgress,
  }) => AutoMemoryService.withBackupBarrier(
        () => _restoreZipBytes(zipBytes, onProgress: onProgress),
      );

  static Future<void> _restoreZipBytes(
    Uint8List zipBytes, {
    BackupProgressCallback? onProgress,
  }) async {
    void report(double p, String stage) =>
        onProgress?.call(p.clamp(0, 1), stage);

    if (zipBytes.isEmpty) {
      throw StateError('备份内容为空，已取消恢复');
    }
    report(0.18, '解析备份包');
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw StateError('备份包无法解析，已取消恢复：$e');
    }

    Uint8List? prefsBytes;
    Uint8List? sqliteBytes;
    final fileEntries = <String, Uint8List>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll('\\', '/');
      if (name == _prefsName) {
        prefsBytes = Uint8List.fromList(entry.content as List<int>);
      } else if (name == _sqliteName) {
        sqliteBytes = Uint8List.fromList(entry.content as List<int>);
      } else if (name.startsWith(_filesPrefix)) {
        final rel = name.substring(_filesPrefix.length);
        if (rel.isEmpty || rel.endsWith('/')) continue;
        fileEntries[rel] = Uint8List.fromList(entry.content as List<int>);
      }
    }
    if (prefsBytes == null) {
      throw StateError('备份包中缺少 prefs.json，已取消恢复');
    }

    report(0.28, '读取设置数据');
    Map<String, dynamic> decodedPrefs;
    try {
      decodedPrefs =
          jsonDecode(utf8.decode(prefsBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw StateError('备份包中的设置数据无效或已损坏：$e');
    }

    final docDir = await getApplicationDocumentsDirectory();
    final prefs = await SharedPreferences.getInstance();

    // Drain pending writes before replacing the database; old timers must not
    // write conversation drafts into the restored snapshot.
    await ChatDraftService.instance.flushAll();
    ChatDraftService.instance.reset();

    // 恢复前：快照本机密钥（备份中不含密钥，恢复后回填，避免丢 Key）
    report(0.36, '创建安全副本');
    final localSecretTop = <String, String>{};
    final localSecretsByField = <String, String>{}; // 字段名 → 有值密钥
    final localSecretsByPath = <String, String>{}; // 完整路径 → 密钥
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value == null) continue;
      if (secretTopLevelKeys.contains(key) && value is String) {
        localSecretTop[key] = value;
        continue;
      }
      if (value is! String) continue;
      for (final e in extractSecretFields(value).entries) {
        localSecretsByPath['$key|${e.key}'] = e.value;
        localSecretsByField.putIfAbsent(e.key.split('.').last, () => e.value);
        localSecretsByField.putIfAbsent(e.key, () => e.value);
      }
    }

    // 恢复前安全副本（设置快照，不含密钥）
    final safetyDir = await _safetyDir();
    final safetyPrefs = File('${safetyDir.path}/prefs.json');
    final current = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value == null) continue;
      final sanitized = sanitizePrefForExport(key, value);
      if (sanitized == null) continue;
      current[key] = _encodePrefValue(sanitized);
    }
    await safetyPrefs.writeAsString(
      const JsonEncoder.withIndent('  ').convert(current),
      flush: true,
    );

    final originalPrefs = <String, dynamic>{
      for (final key in prefs.getKeys()) key: prefs.get(key),
    };
    final staging = await Directory(docDir.path).createTemp('.aichat_restore_');
    final stagedFiles = Directory('${staging.path}/new');
    final oldFiles = Directory('${staging.path}/old');
    final movedOld = <String>[];
    final installed = <String>[];
    var rollbackFailed = false;
    var prefsTouched = false;
    try {
      await stagedFiles.create();
      await oldFiles.create();
      for (final entry in fileEntries.entries) {
        final parts = entry.key.split('/');
        if (parts.any((part) =>
                part.isEmpty ||
                part == '.' ||
                part == '..' ||
                part.contains(':')) ||
            (parts.length > 1 && !_isUserDir(parts.first))) {
          throw StateError('备份包含无效的文件路径：${entry.key}');
        }
        final target = File('${stagedFiles.path}/${entry.key}');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.value, flush: true);
      }
      final sqliteTemp = File('${staging.path}/database.sqlite');
      if (sqliteBytes != null) {
        await sqliteTemp.writeAsBytes(sqliteBytes, flush: true);
      }

      Future<void> applyRestore() async {
        // 1. 覆盖 SharedPreferences
        report(0.45, '恢复应用设置');
        prefsTouched = true;
        if (!await prefs.clear()) throw StateError('清理设置失败');
        for (final entry in decodedPrefs.entries) {
          await _setPrefValue(prefs, entry.key, entry.value, docDir.path);
        }
        // 回填本机密钥（备份里是空的）
        for (final entry in localSecretTop.entries) {
          if (!await prefs.setString(entry.key, entry.value)) {
            throw StateError('写入设置失败：${entry.key}');
          }
        }
        for (final key in prefs.getKeys()) {
          final value = prefs.get(key);
          if (value is! String) continue;
          final trimmed = value.trim();
          if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) continue;
          try {
            final decoded = jsonDecode(trimmed);
            final byPath = <String, String>{};
            for (final e in localSecretsByPath.entries) {
              if (e.key.startsWith('$key|')) {
                byPath[e.key.substring(key.length + 1)] = e.value;
              }
            }
            final filled = fillSecretFields(
              decoded,
              '',
              {...localSecretsByField, ...byPath},
            );
            final encoded = jsonEncode(filled);
            if (encoded != value && !await prefs.setString(key, encoded)) {
              throw StateError('写入设置失败：$key');
            }
          } on FormatException catch (_) {}
        }

        // 2. Move original entries aside before installing staged entries.
        report(0.55, '清理旧用户文件');
        final root = Directory(docDir.path);
        final names = <String>{};
        await for (final entity in root.list(followLinks: false)) {
          final name = _basename(entity.path);
          if (entity is Directory && _isUserDir(name)) names.add(name);
        }
        await for (final entity in stagedFiles.list(followLinks: false)) {
          names.add(_basename(entity.path));
        }
        for (final name in names) {
          final path = '${docDir.path}/$name';
          final type = await FileSystemEntity.type(path, followLinks: false);
          if (type == FileSystemEntityType.link) {
            throw StateError('恢复目标包含符号链接：$name');
          }
          if (type == FileSystemEntityType.directory) {
            await Directory(path).rename('${oldFiles.path}/$name');
            movedOld.add(name);
          } else if (type == FileSystemEntityType.file) {
            await File(path).rename('${oldFiles.path}/$name');
            movedOld.add(name);
          }
          final stagedPath = '${stagedFiles.path}/$name';
          final stagedType = await FileSystemEntity.type(stagedPath);
          if (stagedType == FileSystemEntityType.directory) {
            await Directory(stagedPath).rename(path);
            installed.add(name);
          } else if (stagedType == FileSystemEntityType.file) {
            await File(stagedPath).rename(path);
            installed.add(name);
          }
        }
        report(0.98, '恢复用户文件');
      }

      if (sqliteBytes != null) {
        report(0.98, '恢复 SQLite 数据');
        await StorageMigrationService.importSqlite(sqliteTemp,
            beforeCommit: applyRestore);
      } else {
        await applyRestore();
      }
    } catch (e) {
      final failures = <String>[];
      for (final name in installed.reversed) {
        try {
          final path = '${docDir.path}/$name';
          final type = await FileSystemEntity.type(path, followLinks: false);
          if (type == FileSystemEntityType.directory) {
            await Directory(path).delete(recursive: true);
          } else if (type != FileSystemEntityType.notFound) {
            await File(path).delete();
          }
        } catch (error) {
          failures.add('删除新文件 $name: $error');
        }
      }
      for (final name in movedOld.reversed) {
        try {
          final path = '${oldFiles.path}/$name';
          if (await FileSystemEntity.type(path) ==
              FileSystemEntityType.directory) {
            await Directory(path).rename('${docDir.path}/$name');
          } else {
            await File(path).rename('${docDir.path}/$name');
          }
        } catch (error) {
          failures.add('恢复原文件 $name: $error');
        }
      }
      try {
        if (prefsTouched && !await prefs.clear()) {
          throw StateError('清理设置失败');
        }
        for (final entry in (prefsTouched
            ? originalPrefs.entries
            : <MapEntry<String, dynamic>>[])) {
          await _setPrefValue(prefs, entry.key, entry.value, docDir.path);
        }
      } catch (error) {
        failures.add('恢复设置: $error');
      }
      rollbackFailed = failures.isNotEmpty;
      throw StateError(
          '恢复写入失败：$e${failures.isEmpty ? "" : "；回滚失败：${failures.join(", ")}；原文件保留在 ${oldFiles.path}"}');
    } finally {
      if (!rollbackFailed) {
        try {
          await staging.delete(recursive: true);
        } catch (e) {
          debugPrint('[BackupService] 清理恢复临时文件失败: $e');
        }
      }
    }
    report(1, '恢复完成');
  }

  static Future<bool> hasSafetyCopy() async {
    final dir = await _safetyDir();
    final f = File('${dir.path}/prefs.json');
    return f.existsSync() && f.lengthSync() > 2;
  }

  /// 用恢复前安全副本覆盖当前设置（救灾用；不恢复文件）。
  static Future<void> restoreFromSafetyCopy() async {
    final dir = await _safetyDir();
    final f = File('${dir.path}/prefs.json');
    if (!await f.exists()) {
      throw StateError('没有找到恢复前安全副本');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      throw StateError('安全副本已损坏：$e');
    }
    final docDir = await getApplicationDocumentsDirectory();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    for (final entry in data.entries) {
      await _setPrefValue(prefs, entry.key, entry.value, docDir.path);
    }
  }

  /// 彻底删除本地备份：零字节覆写后 unlink
  static Future<bool> deleteLocalBackup(File file) async {
    if (!await file.exists()) return true;
    try {
      final raf = file.openSync(mode: FileMode.write);
      try {
        final length = raf.lengthSync();
        final chunk = Uint8List(256 * 1024);
        var written = 0;
        while (written < length) {
          final n = (length - written).clamp(0, chunk.length);
          raf.writeFromSync(chunk, 0, n);
          written += n;
        }
        await raf.flush();
      } finally {
        raf.closeSync();
      }
      await file.delete();
      return !await file.exists();
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
      return !await file.exists();
    }
  }

  static Future<String> describeLocalBackupFiles() async {
    final dir = await localBackupDir();
    final safetyDir = await _safetyDir();
    final backups = await listLocalBackups();
    final names = backups.isEmpty
        ? '无'
        : backups.map((f) => _basename(f.path)).join(', ');
    final safety = File('${safetyDir.path}/prefs.json');
    final safetyInfo =
        safety.existsSync() ? 'prefs.json(${safety.lengthSync()})' : '无';
    return '本地备份: $names\n安全副本: $safetyInfo\n备份目录: ${dir.path}';
  }

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024.0).toStringAsFixed(2)} GB';
  }

  // ─── 内部工具 ───────────────────────────────────────────────

  static String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}_'
        '${n.microsecondsSinceEpoch}';
  }

  static String _basename(String path) {
    var p = path;
    if (p.endsWith('/') || p.endsWith('\\')) {
      p = p.substring(0, p.length - 1);
    }
    final i = p.lastIndexOf(RegExp(r'[/\\]'));
    return i < 0 ? p : p.substring(i + 1);
  }

  static String? _relativeTo(String path, String base) {
    var p = path.replaceAll('\\', '/');
    var b = base.replaceAll('\\', '/');
    if (!b.endsWith('/')) b = '$b/';
    if (!p.startsWith(b)) return null;
    return p.substring(b.length);
  }

  static dynamic _relativizePaths(dynamic value, String docPath) {
    if (value is String) {
      return value.replaceAll(docPath, _docsPlaceholder);
    }
    if (value is List) {
      return value
          .map((e) => e is String ? e.replaceAll(docPath, _docsPlaceholder) : e)
          .toList();
    }
    return value;
  }

  static dynamic _absolutizePaths(dynamic value, String docPath) {
    if (value is String) {
      return value.replaceAll(_docsPlaceholder, docPath);
    }
    if (value is List) {
      return value
          .map((e) => e is String ? e.replaceAll(_docsPlaceholder, docPath) : e)
          .toList();
    }
    return value;
  }

  // ─── 密钥脱敏：备份不含任何密钥 ─────────────────────────────

  /// 整键排除（纯密钥，备份中不出现）
  static const Set<String> secretTopLevelKeys = {
    'api_key',
    'cloud_backup_secret_id',
    'cloud_backup_secret_key',
  };

  /// JSON 内敏感字段名（大小写不敏感）：导出时清空，恢复时回填本机密钥
  static const Set<String> secretJsonFieldNames = {
    'api_key',
    'apikey',
    'accesskeyid',
    'secretaccesskey',
    'secretid',
    'secretkey',
    'secret_id',
    'secret_key',
    'password',
    'secret',
    'token',
  };

  static bool _isSecretField(String name) =>
      secretJsonFieldNames.contains(name.toLowerCase());

  /// 递归清空 Map/List 中的密钥字段（结构保留，值置空串）
  static dynamic sanitizeSecrets(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) {
        final key = k.toString();
        if (_isSecretField(key)) {
          out[key] = '';
        } else {
          out[key] = sanitizeSecrets(v);
        }
      });
      return out;
    }
    if (value is List) {
      return value.map(sanitizeSecrets).toList();
    }
    return value;
  }

  /// 若字符串是 JSON 对象/数组则脱敏后重新编码，否则原样返回
  static String _sanitizeJsonString(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return raw;
    if (!(s.startsWith('{') || s.startsWith('['))) return raw;
    try {
      final decoded = jsonDecode(s);
      final cleaned = sanitizeSecrets(decoded);
      return jsonEncode(cleaned);
    } catch (_) {
      return raw;
    }
  }

  /// 导出前处理某个 prefs 键值：整键排除或 JSON 内脱敏
  /// 返回 null 表示该键不进入备份。
  static dynamic sanitizePrefForExport(String key, dynamic value) {
    if (secretTopLevelKeys.contains(key)) return null;
    if (value is String) return _sanitizeJsonString(value);
    return value;
  }

  /// 从本机原始 JSON 值中抽取密钥字段路径 → 值（用于恢复后回填）
  static Map<String, String> extractSecretFields(String jsonRaw) {
    final result = <String, String>{};
    final s = jsonRaw.trim();
    if (s.isEmpty || !(s.startsWith('{') || s.startsWith('['))) return result;
    try {
      final decoded = jsonDecode(s);
      void walk(dynamic node, String path) {
        if (node is Map) {
          node.forEach((k, v) {
            final key = k.toString();
            final next = path.isEmpty ? key : '$path.$key';
            if (_isSecretField(key) && v is String && v.isNotEmpty) {
              result[next] = v;
            } else {
              walk(v, next);
            }
          });
        } else if (node is List) {
          for (var i = 0; i < node.length; i++) {
            walk(node[i], '$path[$i]');
          }
        }
      }

      walk(decoded, '');
    } catch (_) {}
    return result;
  }

  /// 按路径回填密钥到 JSON 结构（仅填空值，不覆盖已有）
  static dynamic fillSecretFields(
    dynamic node,
    String path,
    Map<String, String> secrets,
  ) {
    if (node is Map) {
      final out = <String, dynamic>{};
      node.forEach((k, v) {
        final key = k.toString();
        final next = path.isEmpty ? key : '$path.$key';
        if (_isSecretField(key)) {
          final current = v?.toString() ?? '';
          out[key] = current.isNotEmpty
              ? v
              : (secrets[next] ?? secrets[key] ?? current);
        } else {
          out[key] = fillSecretFields(v, next, secrets);
        }
      });
      return out;
    }
    if (node is List) {
      final out = <dynamic>[];
      for (var i = 0; i < node.length; i++) {
        out.add(fillSecretFields(node[i], '$path[$i]', secrets));
      }
      return out;
    }
    return node;
  }

  /// SharedPreferences 值序列化：保留类型信息
  static Map<String, dynamic> _encodePrefValue(dynamic value) {
    if (value is String) return {'t': 's', 'v': value};
    if (value is bool) return {'t': 'b', 'v': value};
    if (value is int) return {'t': 'i', 'v': value};
    if (value is double) return {'t': 'd', 'v': value};
    if (value is List) {
      return {
        't': 'l',
        'v': value.map((e) => e.toString()).toList(),
      };
    }
    return {'t': 's', 'v': value.toString()};
  }

  static Future<void> _setPrefValue(
    SharedPreferences prefs,
    String key,
    dynamic encoded,
    String docPath,
  ) async {
    if (encoded is Map) {
      final type = encoded['t'] as String? ?? 's';
      final raw = _absolutizePaths(encoded['v'], docPath);
      switch (type) {
        case 's':
          if (!await prefs.setString(key, raw as String)) {
            throw StateError('写入设置失败：$key');
          }
        case 'b':
          if (!await prefs.setBool(key, raw as bool)) {
            throw StateError('写入设置失败：$key');
          }
        case 'i':
          if (!await prefs.setInt(key, (raw as num).toInt())) {
            throw StateError('写入设置失败：$key');
          }
        case 'd':
          if (!await prefs.setDouble(key, (raw as num).toDouble())) {
            throw StateError('写入设置失败：$key');
          }
        case 'l':
          if (!await prefs.setStringList(
            key,
            (raw as List).map((e) => e.toString()).toList(),
          )) {
            throw StateError('写入设置失败：$key');
          }
      }
      return;
    }
    // 兼容未带类型的裸值
    if (encoded is String) {
      if (!await prefs.setString(key, encoded)) throw StateError('写入设置失败：$key');
    } else if (encoded is bool) {
      if (!await prefs.setBool(key, encoded)) throw StateError('写入设置失败：$key');
    } else if (encoded is int) {
      if (!await prefs.setInt(key, encoded)) throw StateError('写入设置失败：$key');
    } else if (encoded is double) {
      if (!await prefs.setDouble(key, encoded)) throw StateError('写入设置失败：$key');
    } else if (encoded is List) {
      if (!await prefs.setStringList(
        key,
        encoded.map((e) => e.toString()).toList(),
      )) {
        throw StateError('写入设置失败：$key');
      }
    }
  }

  static Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return 'unknown';
    }
  }
}
