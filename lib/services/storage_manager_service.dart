import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 占用空间条目：一个可独立查看 / 删除的存储分类。
class StorageItem {
  final String id; // 唯一标识，删除时按 id 分发
  final String title; // 名称（如「聊天记录」）
  final String subtitle; // 说明（包含删除影响）
  final bool isUserData; // true=用户数据，false=软件缓存
  final int sizeBytes; // 当前占用字节数
  final bool deletable; // 是否有内容可删（无内容时禁用删除）

  const StorageItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isUserData,
    required this.sizeBytes,
    required this.deletable,
  });
}

/// 管理占用空间：扫描应用自身占用（用户数据 + 软件缓存），
/// 并提供各分类的清理能力。
///
/// 覆盖所有 path_provider 目录 + SharedPreferences 全部键：
/// - 文档目录（getApplicationDocumentsDirectory）：workshop（下载缓存）、
///   user_moments / moment_import_*（角色朋友圈图片）、chat_import_*
///   （聊天导入文件）及其他未分类文件；
/// - 支持目录（getApplicationSupportDirectory）：角色包/其他数据文件；
/// - 内部缓存（getTemporaryDirectory，即系统「缓存」口径之一）：临时文件；
/// - 外部存储（getExternalStorageDirectory）：updates/ 下的 APK 更新包；
/// - 外部缓存（getExternalCacheDirectories）：外部临时文件；
/// - SharedPreferences：聊天/角色/通知/用户资料/设置等全部用户数据。
class StorageManagerService {
  // 聊天记录相关存储键
  static const _chatKeys = [
    'chat_conversations_v1',
    'chat_messages_v1',
    'chat_context_tokens_v1',
    'chat_system_tokens_v1',
  ];

  // 角色与朋友圈相关存储键
  static const _characterKeys = [
    'characters_v1',
    'visibility_groups_v1',
    'characters_deleted_v1',
  ];

  // 用户资料存储键（昵称/头像/地区/签名/性别，user_id 保留）
  static const _profileKeys = [
    'user_nickname',
    'user_avatar',
    'user_region',
    'user_signature',
    'user_gender',
  ];

  // 文档目录下已知分类目录
  static const _workshopDirs = ['workshop'];
  static const _characterDirs = ['user_moments'];
  static const _characterPrefixes = ['moment_import_'];
  static const _chatPrefixes = ['chat_import_'];

  /// 扫描全部存储条目（含异步文件遍历，页面加载时执行一次）。
  static Future<List<StorageItem>> scan() async {
    final prefs = await _scanPrefs();
    _debugDumpDirs(prefs);
    return [
      await _chatItem(prefs),
      await _characterItem(prefs),
      _notificationItem(prefs),
      _profileItem(prefs),
      await _downloadCacheItem(),
      await _tempItem(),
      _settingsItem(prefs),
      await _otherItem(),
    ];
  }

  /// 聊天记录：聊天会话/消息存储键 + 导入聊天时提取的图片与文件目录
  static Future<StorageItem> _chatItem(Map<String, int> prefs) async {
    final bytes = prefs['chat']! +
        await _docDirsSize(names: const [], prefixes: _chatPrefixes);
    return StorageItem(
      id: 'chat',
      title: '聊天记录',
      subtitle: '全部会话与消息，含导入的图片和文件；删除后不可恢复',
      isUserData: true,
      sizeBytes: bytes,
      deletable: bytes > 0,
    );
  }

  /// 角色与朋友圈：角色卡（含 base64 头像/背景）、朋友圈动态、
  /// 发布/导入的朋友圈图片
  static Future<StorageItem> _characterItem(Map<String, int> prefs) async {
    final bytes = prefs['character']! +
        await _docDirsSize(names: _characterDirs, prefixes: _characterPrefixes);
    return StorageItem(
      id: 'character',
      title: '角色与朋友圈数据',
      subtitle: '自定义角色、朋友圈动态与图片，含头像/背景；删除后恢复默认角色',
      isUserData: true,
      sizeBytes: bytes,
      deletable: bytes > 0,
    );
  }

  /// 朋友圈消息通知列表
  static StorageItem _notificationItem(Map<String, int> prefs) {
    final bytes = prefs['notification']!;
    return StorageItem(
      id: 'notification',
      title: '朋友圈消息通知',
      subtitle: '角色点赞、评论与回复产生的未读消息记录',
      isUserData: true,
      sizeBytes: bytes,
      deletable: bytes > 0,
    );
  }

  /// 用户资料：昵称/头像/地区/签名/性别（头像为 base64 时体积较大）
  static StorageItem _profileItem(Map<String, int> prefs) {
    final bytes = prefs['profile']!;
    return StorageItem(
      id: 'profile',
      title: '用户资料',
      subtitle: '头像、签名、地区与性别（昵称与账号保留）',
      isUserData: true,
      sizeBytes: bytes,
      deletable: bytes > 0,
    );
  }

  /// 设置与配置：主题、API 配置、模型选择等（仅展示，不提供删除）
  static StorageItem _settingsItem(Map<String, int> prefs) {
    final bytes = prefs['settings']!;
    return StorageItem(
      id: 'settings',
      title: '设置与配置',
      subtitle: '主题、API 配置与模型选择等；不提供删除，以免误清配置',
      isUserData: true,
      sizeBytes: bytes,
      deletable: false,
    );
  }

  /// 下载缓存：创意工坊下载残留（workshop）+ 外部存储中的 APK 更新包（updates）
  static Future<StorageItem> _downloadCacheItem() async {
    var bytes = await _docDirsSize(names: _workshopDirs, prefixes: const []);
    final updates = await _externalUpdatesDir();
    if (updates != null) {
      bytes += _dirSize(updates);
    }
    return StorageItem(
      id: 'download_cache',
      title: '下载缓存',
      subtitle: '创意工坊下载残留与 APK 更新包，可随时重新下载',
      isUserData: false,
      sizeBytes: bytes,
      deletable: bytes > 0,
    );
  }

  /// 临时文件：内部缓存 + 外部缓存
  static Future<StorageItem> _tempItem() async {
    var bytes = _dirSize(await getTemporaryDirectory());
    final extCache = await _externalCacheDir();
    if (extCache != null) bytes += _dirSize(extCache);
    return StorageItem(
      id: 'temp',
      title: '临时文件',
      subtitle: '系统缓存目录中的临时文件，删除不影响已保存的数据',
      isUserData: false,
      sizeBytes: bytes,
      deletable: bytes > 0,
    );
  }

  /// 其他应用文件（兜底）：文档目录中未归入上述分类的文件 +
  /// 支持目录（角色包等数据文件）。确保总占用与系统口径接近。
  static Future<StorageItem> _otherItem() async {
    var bytes = await _unclassifiedDocBytes();
    try {
      final support = await getApplicationSupportDirectory();
      bytes += _dirSize(Directory(support.path));
    } catch (_) {}
    return StorageItem(
      id: 'other',
      title: '其他应用文件',
      subtitle: '未归类的角色包等应用数据文件',
      isUserData: true,
      sizeBytes: bytes,
      deletable: false, // 无法安全归类，不提供删除
    );
  }

  // ─── 文件清理（返回释放的字节数）────────────────────────────

  /// 删除导入聊天时提取的图片/文件目录（chat_import_*）
  static Future<int> clearChatFiles() async {
    return _deleteDocDirs(names: const [], prefixes: _chatPrefixes);
  }

  /// 删除发布/导入的朋友圈图片目录（user_moments、moment_import_*）
  static Future<int> clearCharacterFiles() async {
    return _deleteDocDirs(names: _characterDirs, prefixes: _characterPrefixes);
  }

  /// 清除外部存储 updates/ 下的 APK 更新包，返回释放的字节数
  static Future<int> clearUpdateApks() async {
    final updates = await _externalUpdatesDir();
    if (updates == null || !updates.existsSync()) return 0;
    var freed = 0;
    for (final entity in updates.listSync()) {
      try {
        final size = entity is File
            ? entity.lengthSync()
            : _dirSize(entity as Directory);
        if (entity is Directory) {
          entity.deleteSync(recursive: true);
        } else {
          entity.deleteSync();
        }
        freed += size;
      } catch (_) {}
    }
    return freed;
  }

  /// 清除内部 + 外部缓存目录内容，返回释放的字节数
  static Future<int> clearTempFiles() async {
    var freed = _clearDirContents(await getTemporaryDirectory());
    final extCache = await _externalCacheDir();
    if (extCache != null) freed += _clearDirContents(extCache);
    return freed;
  }

  /// 删除文档目录下精确名或前缀匹配的目录，返回释放的字节数
  static Future<int> _deleteDocDirs({
    required List<String> names,
    required List<String> prefixes,
  }) async {
    final docDir = await getApplicationDocumentsDirectory();
    var freed = 0;
    try {
      for (final entity in Directory(docDir.path).listSync()) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments.last;
        final matched = names.contains(name) ||
            prefixes.any((p) => name.startsWith(p));
        if (!matched) continue;
        final size = _dirSize(entity);
        try {
          entity.deleteSync(recursive: true);
          freed += size;
        } catch (_) {}
      }
    } catch (_) {}
    return freed;
  }

  // ─── 体积统计 ───────────────────────────────────────────────

  /// 枚举 SharedPreferences 全部键，按分类统计字节数
  static Future<Map<String, int>> _scanPrefs() async {
    final result = <String, int>{
      'chat': 0,
      'character': 0,
      'notification': 0,
      'profile': 0,
      'settings': 0,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        final value = prefs.getString(key);
        if (value == null) continue;
        final bytes = utf8.encode(value).length;
        if (_chatKeys.contains(key)) {
          result['chat'] = result['chat']! + bytes;
        } else if (_characterKeys.contains(key)) {
          result['character'] = result['character']! + bytes;
        } else if (key == 'moment_notifications_v1') {
          result['notification'] = result['notification']! + bytes;
        } else if (_profileKeys.contains(key)) {
          result['profile'] = result['profile']! + bytes;
        } else {
          result['settings'] = result['settings']! + bytes;
        }
      }
    } catch (_) {}
    return result;
  }

  /// 文档目录下精确名或前缀匹配的子目录体积之和
  static Future<int> _docDirsSize({
    required List<String> names,
    required List<String> prefixes,
  }) async {
    final docDir = await getApplicationDocumentsDirectory();
    var total = 0;
    try {
      final dir = Directory(docDir.path);
      if (!dir.existsSync()) return 0;
      for (final entity in dir.listSync()) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments.last;
        if (names.contains(name) ||
            prefixes.any((p) => name.startsWith(p))) {
          total += _dirSize(entity);
        }
      }
    } catch (_) {}
    return total;
  }

  /// 文档目录中未归入已知分类的散文件与目录体积之和
  static Future<int> _unclassifiedDocBytes() async {
    final docDir = await getApplicationDocumentsDirectory();
    var total = 0;
    try {
      final dir = Directory(docDir.path);
      if (!dir.existsSync()) return 0;
      for (final entity in dir.listSync()) {
        try {
          if (entity is File) {
            total += entity.lengthSync();
            continue;
          }
          if (entity is! Directory) continue;
          final name = entity.uri.pathSegments.last;
          final classified = _workshopDirs.contains(name) ||
              _characterDirs.contains(name) ||
              _characterPrefixes.any((p) => name.startsWith(p)) ||
              _chatPrefixes.any((p) => name.startsWith(p));
          if (!classified) total += _dirSize(entity);
        } catch (_) {}
      }
    } catch (_) {}
    return total;
  }

  /// 外部文件目录下的 updates 子目录（APK 更新包），不可用时返回 null
  static Future<Directory?> _externalUpdatesDir() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext == null) return null;
      return Directory('${ext.path}/updates');
    } catch (_) {
      return null;
    }
  }

  /// 外部缓存目录，不可用时返回 null
  static Future<Directory?> _externalCacheDir() async {
    try {
      final dirs = await getExternalCacheDirectories();
      if (dirs == null || dirs.isEmpty) return null;
      return Directory(dirs.first.path);
    } catch (_) {
      return null;
    }
  }

  /// 删除目录下所有内容，返回释放的字节数
  static int _clearDirContents(Directory dir) {
    if (!dir.existsSync()) return 0;
    var freed = 0;
    try {
      for (final entity in dir.listSync()) {
        try {
          final size = entity is File
              ? entity.lengthSync()
              : _dirSize(entity as Directory);
          if (entity is Directory) {
            entity.deleteSync(recursive: true);
          } else {
            entity.deleteSync();
          }
          freed += size;
        } catch (_) {}
      }
    } catch (_) {}
    return freed;
  }

  /// 递归统计目录体积
  static int _dirSize(Directory dir) {
    if (!dir.existsSync()) return 0;
    var total = 0;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          try {
            total += entity.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// 调试输出：打印所有 path_provider 目录的绝对路径与实际大小，
  /// 用于与系统「缓存/数据」统计口径对齐（排查占用不准确问题）。
  static void _debugDumpDirs(Map<String, int> prefs) {
    void report(String tag, Directory? dir) {
      final size = dir == null ? -1 : _dirSize(dir);
      debugPrint('[StorageScan] $tag: ${dir?.path ?? 'n/a'} size=$size');
    }

    Future<void> dump() async {
      report('documents', await getApplicationDocumentsDirectory());
      report('support', await getApplicationSupportDirectory());
      report('cache(temp)', await getTemporaryDirectory());
      final ext = await getExternalStorageDirectory();
      report('externalStorage', ext);
      final extCache = await _externalCacheDir();
      report('externalCache', extCache);
      debugPrint('[StorageScan] prefs(bytes): $prefs');
    }

    // 异步打印，不阻塞调用方
    dump();
  }
}
