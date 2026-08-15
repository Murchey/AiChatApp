import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单个会话的聊天背景设置
class ChatBackgroundInfo {
  /// 背景图片在本地的持久化路径（不存在图片时为空字符串）
  final String imagePath;
  /// 高斯模糊度（0 = 不模糊）
  final double blur;

  const ChatBackgroundInfo({required this.imagePath, this.blur = 10});

  bool get hasImage => imagePath.isNotEmpty;

  /// 已持久化的图片文件是否存在
  bool get fileExists => hasImage && File(imagePath).existsSync();
}

/// 聊天背景管理：每个会话（私聊 conversationId / 群聊 groupId）独立设置，
/// 背景图片复制到应用文档目录持久化，模糊度随会话单独存储。
class ChatBackgroundProvider extends ChangeNotifier {
  /// 会话 id → 背景设置（懒加载缓存）
  final Map<String, ChatBackgroundInfo> _cache = {};

  static const _imageKeyPrefix = 'chat_bg_image_';
  static const _blurKeyPrefix = 'chat_bg_blur_';

  /// 默认模糊度
  static const double defaultBlur = 10;

  /// 获取某会话的背景设置（首次访问时从 SharedPreferences 懒加载）
  Future<ChatBackgroundInfo> getInfo(String chatId) async {
    final cached = _cache[chatId];
    if (cached != null) return cached;
    final info = await _loadFromPrefs(chatId);
    _cache[chatId] = info;
    // 通知依赖方：首次懒加载完成后重建，以渲染已持久化的背景
    notifyListeners();
    return info;
  }

  /// 同步读取缓存中的背景设置（无缓存时返回空值，不会阻塞等待异步加载）
  ChatBackgroundInfo? getInfoSync(String chatId) => _cache[chatId];

  /// 从 SharedPreferences 加载某会话背景（内部方法）
  static Future<ChatBackgroundInfo> _loadFromPrefs(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString(_imageKeyPrefix + chatId) ?? '';
    final blur = prefs.getDouble(_blurKeyPrefix + chatId) ?? defaultBlur;
    return ChatBackgroundInfo(imagePath: imagePath, blur: blur);
  }

  /// 从相册选择的临时文件设置背景（复制到应用文档目录持久化）
  Future<void> setImage(String chatId, String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final bgDir = Directory('${dir.path}/chat_backgrounds');
    if (!bgDir.existsSync()) bgDir.createSync(recursive: true);
    // 替换背景时先删除旧图，避免产生孤儿文件
    final old = _cache[chatId] ?? await _loadFromPrefs(chatId);
    if (old.hasImage && old.fileExists) _deleteFileQuietly(old.imagePath);
    // 保留原扩展名（便于识别），时间戳避免同名覆盖
    final ext = sourcePath.contains('.')
        ? sourcePath.split('.').last
        : 'img';
    final destPath =
        '${bgDir.path}/${chatId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(sourcePath).copy(destPath);

    final info = old.copyWith(imagePath: destPath);
    _cache[chatId] = info;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_imageKeyPrefix + chatId, destPath);
    notifyListeners();
  }

  /// 移除某会话的背景图片（保留模糊度设置，清除后重新设置时仍生效）。
  /// 同时删除已持久化的物理文件，避免残留孤儿图片。
  Future<void> clearImage(String chatId) async {
    final existing = _cache[chatId] ?? await _loadFromPrefs(chatId);
    if (existing.hasImage && existing.fileExists) {
      _deleteFileQuietly(existing.imagePath);
    }
    final info = existing.copyWith(imagePath: '');
    _cache[chatId] = info;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_imageKeyPrefix + chatId);
    notifyListeners();
  }

  /// 静默删除文件（失败不影响主流程）
  void _deleteFileQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// 设置某会话背景的高斯模糊度
  Future<void> setBlur(String chatId, double blur) async {
    final existing = _cache[chatId] ?? await _loadFromPrefs(chatId);
    final info = existing.copyWith(blur: blur);
    _cache[chatId] = info;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_blurKeyPrefix + chatId, blur);
    notifyListeners();
  }
}

extension ChatBackgroundInfoX on ChatBackgroundInfo {
  ChatBackgroundInfo copyWith({String? imagePath, double? blur}) {
    return ChatBackgroundInfo(
      imagePath: imagePath ?? this.imagePath,
      blur: blur ?? this.blur,
    );
  }
}
