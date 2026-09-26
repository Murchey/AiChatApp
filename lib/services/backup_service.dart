import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_crypto.dart';

/// 备份/恢复过程进度回调：[progress] 0~1，[stage] 为阶段说明。
typedef BackupProgressCallback = void Function(double progress, String stage);

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
///   prefs.json      全部 SharedPreferences（路径已相对化）
///   files/**        用户数据文件（相对文档目录）
///
/// 可选 AES-256-GCM 密码加密整包（密文布局见 [BackupCrypto]）。
class BackupService {
  static const int formatVersion = 1;
  static const String _manifestName = 'manifest.json';
  static const String _prefsName = 'prefs.json';
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
    'voice',
    'voice_samples',
  ];

  /// 需要纳入备份的用户数据目录前缀
  static const List<String> userDataDirPrefixes = [
    'moment_import_',
    'chat_import_',
  ];

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
  }) async {
    void report(double p, String stage) => onProgress?.call(p.clamp(0, 1), stage);

    report(0.02, '准备导出');
    final docDir = await getApplicationDocumentsDirectory();
    final prefs = await SharedPreferences.getInstance();
    final encrypted = password != null && password.isNotEmpty;

    // 1. SharedPreferences 全量（路径相对化）
    report(0.08, '读取应用设置');
    final rawPrefs = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value == null) continue;
      rawPrefs[key] = _encodePrefValue(_relativizePaths(value, docDir.path));
    }

    final ts = _timestamp();
    final fileName = encrypted
        ? '${fileNamePrefix}_${ts}_enc.zip'
        : '${fileNamePrefix}_$ts.zip';

    final archive = Archive();
    final filesMap = <String, dynamic>{};

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
        if (_basename(entity.path).startsWith('.')) continue;
        pendingFiles.add(entity);
      }
    }

    var fileCount = 0;
    final total = pendingFiles.isEmpty ? 1 : pendingFiles.length;
    for (var i = 0; i < pendingFiles.length; i++) {
      final file = pendingFiles[i];
      final rel = _relativeTo(file.path, docDir.path) ?? _basename(file.path);
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile.bytes('files/$rel', bytes));
      filesMap[rel] = bytes.length;
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
    archive.addFile(ArchiveFile.string(
      _manifestName,
      const JsonEncoder.withIndent('  ').convert(manifest),
    ));
    archive.addFile(ArchiveFile.string(
      _prefsName,
      const JsonEncoder.withIndent('  ').convert(rawPrefs),
    ));

    report(0.88, '压缩打包');
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    if (encrypted) {
      report(0.93, '加密备份包');
    }
    final out = encrypted ? BackupCrypto.encrypt(zipBytes, password) : zipBytes;
    report(1, '导出完成');
    return LocalExport(bytes: out, fileName: fileName, size: out.length);
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
    await target.writeAsBytes(export.bytes, flush: true);
    onProgress?.call(1, '本地备份完成');
    return target;
  }

  /// 删除指定前缀的本地备份（用于自动备份清理上一份），返回删除数量。
  /// 只匹配同前缀文件，不影响手动备份。
  static Future<int> deleteLocalBackupsByPrefix(String prefix) async {
    final dir = await localBackupDir();
    if (!await dir.exists()) return 0;
    var deleted = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      if (!name.startsWith(prefix)) continue;
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
  /// 恢复前自动写入安全副本；失败时回滚设置。
  static Future<void> restoreLocalBackup(
    File file, {
    String? password,
    BackupProgressCallback? onProgress,
  }) async {
    void report(double p, String stage) => onProgress?.call(p.clamp(0, 1), stage);

    report(0.05, '读取备份文件');
    if (!await file.exists()) {
      throw StateError('本地备份文件不存在');
    }
    final raw = await file.readAsBytes();
    Uint8List zipBytes;
    if (BackupCrypto.isEncrypted(raw)) {
      report(0.12, '解密备份包');
      zipBytes = BackupCrypto.decrypt(raw, password ?? '');
    } else {
      zipBytes = raw;
    }
    await restoreZipBytes(zipBytes, onProgress: onProgress);
  }

  static Future<void> restoreZipBytes(
    Uint8List zipBytes, {
    BackupProgressCallback? onProgress,
  }) async {
    void report(double p, String stage) => onProgress?.call(p.clamp(0, 1), stage);

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
    final fileEntries = <String, Uint8List>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll('\\', '/');
      if (name == _prefsName) {
        prefsBytes = Uint8List.fromList(entry.content as List<int>);
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

    // 恢复前安全副本（设置快照）
    report(0.36, '创建安全副本');
    final safetyDir = await _safetyDir();
    final safetyPrefs = File('${safetyDir.path}/prefs.json');
    final current = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value == null) continue;
      current[key] = _encodePrefValue(value);
    }
    await safetyPrefs.writeAsString(
      const JsonEncoder.withIndent('  ').convert(current),
      flush: true,
    );

    try {
      // 1. 覆盖 SharedPreferences
      report(0.45, '恢复应用设置');
      await prefs.clear();
      for (final entry in decodedPrefs.entries) {
        await _setPrefValue(prefs, entry.key, entry.value, docDir.path);
      }

      // 2. 替换用户数据文件：先清掉旧目录，再写入备份内容
      report(0.55, '清理旧用户文件');
      final root = Directory(docDir.path);
      if (await root.exists()) {
        await for (final entity in root.list()) {
          if (entity is! Directory) continue;
          final name = _basename(entity.path);
          if (!_isUserDir(name)) continue;
          await entity.delete(recursive: true);
        }
      }
      final total = fileEntries.isEmpty ? 1 : fileEntries.length;
      var index = 0;
      for (final entry in fileEntries.entries) {
        final target = File('${docDir.path}/${entry.key}');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.value, flush: true);
        index++;
        if (index % 5 == 0 || index == fileEntries.length) {
          report(
            0.58 + 0.4 * (index / total),
            '恢复用户文件 $index/$total',
          );
        }
      }
      report(1, '恢复完成');
    } catch (e) {
      // 回滚设置
      try {
        final rollback =
            jsonDecode(await safetyPrefs.readAsString()) as Map<String, dynamic>;
        await prefs.clear();
        for (final entry in rollback.entries) {
          await _setPrefValue(prefs, entry.key, entry.value, docDir.path);
        }
      } catch (_) {}
      throw StateError('恢复写入失败，已尝试回滚设置：$e');
    }
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
    final names =
        backups.isEmpty ? '无' : backups.map((f) => _basename(f.path)).join(', ');
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
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
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
          await prefs.setString(key, raw as String);
        case 'b':
          await prefs.setBool(key, raw as bool);
        case 'i':
          await prefs.setInt(key, (raw as num).toInt());
        case 'd':
          await prefs.setDouble(key, (raw as num).toDouble());
        case 'l':
          await prefs.setStringList(
            key,
            (raw as List).map((e) => e.toString()).toList(),
          );
      }
      return;
    }
    // 兼容未带类型的裸值
    if (encoded is String) {
      await prefs.setString(key, encoded);
    } else if (encoded is bool) {
      await prefs.setBool(key, encoded);
    } else if (encoded is int) {
      await prefs.setInt(key, encoded);
    } else if (encoded is double) {
      await prefs.setDouble(key, encoded);
    } else if (encoded is List) {
      await prefs.setStringList(
        key,
        encoded.map((e) => e.toString()).toList(),
      );
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
