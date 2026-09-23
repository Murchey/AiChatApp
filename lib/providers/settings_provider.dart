import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../services/imported_font_storage.dart';
import '../services/update_service.dart';

/// 明暗模式：跟随系统 / 浅色 / 深色
enum AppThemeMode { system, light, dark }

/// 全局角色头像框样式：方形 / 仿 QQ 圆形
enum AvatarFrameStyle { square, circle }

/// 聊天气泡样式：默认（代码绘制） / sr（崩铁短信样式）/ ww（鸣潮样式）/ zmd（终末地样式），后续可扩展其他类型
enum BubbleStyle {
  /// 默认：矩形圆角 + 描边，背景色可自定义
  classic,

  /// sr 崩铁短信样式：大圆角 + 柔和阴影，自带配色（自己=暖棕，对方=浅灰）
  sr,

  /// ww 鸣潮样式：上边共线尾巴 + 大圆角弧线，自带配色
  ww,

  /// zmd 终末地样式：基于鸣潮的尾巴形状，三角均 15px、尾巴回程弧 10px，
  /// 浅深配色一致（自己=白底黑字带黑描边，对方=深灰底白字）
  zmd,
}

extension BubbleStyleX on BubbleStyle {
  String get displayName {
    switch (this) {
      case BubbleStyle.classic:
        return '默认';
      case BubbleStyle.sr:
        return '崩铁样式';
      case BubbleStyle.ww:
        return '鸣潮样式';
      case BubbleStyle.zmd:
        return '终末地样式';
    }
  }
}

/// 会话 UI 样式（顶部标题栏 + 输入/发送栏）：默认 / zmd（终末地）
enum UiStyle {
  /// 默认：顶部居中标题 + 常规输入栏
  classic,

  /// zmd 终末地：标题靠左 + 个性签名副标题 + 在线状态点（绿/红），
  /// 发送按钮深底金边白字，浅深色模式通用
  zmd,
}

extension UiStyleX on UiStyle {
  String get displayName {
    switch (this) {
      case UiStyle.classic:
        return '默认';
      case UiStyle.zmd:
        return '终末地';
    }
  }
}

/// 聊天气泡颜色设置项：自己/对方 × 浅色/深色
enum BubbleColorSlot { selfLight, otherLight, selfDark, otherDark }

/// 聊天气泡内字体颜色设置项：自己/对方 × 浅色/深色
enum BubbleTextSlot { selfLight, otherLight, selfDark, otherDark }

extension BubbleTextSlotX on BubbleTextSlot {
  String get storageKey {
    switch (this) {
      case BubbleTextSlot.selfLight:
        return 'bubble_text_self_light';
      case BubbleTextSlot.otherLight:
        return 'bubble_text_other_light';
      case BubbleTextSlot.selfDark:
        return 'bubble_text_self_dark';
      case BubbleTextSlot.otherDark:
        return 'bubble_text_other_dark';
    }
  }

  Color get defaultColor {
    switch (this) {
      case BubbleTextSlot.selfLight:
        return AppColors.bubbleTextSelfLight;
      case BubbleTextSlot.otherLight:
        return AppColors.bubbleTextOtherLight;
      case BubbleTextSlot.selfDark:
        return AppColors.bubbleTextSelfDark;
      case BubbleTextSlot.otherDark:
        return AppColors.bubbleTextOtherDark;
    }
  }
}

extension BubbleColorSlotX on BubbleColorSlot {
  String get storageKey {
    switch (this) {
      case BubbleColorSlot.selfLight:
        return 'bubble_color_self_light';
      case BubbleColorSlot.otherLight:
        return 'bubble_color_other_light';
      case BubbleColorSlot.selfDark:
        return 'bubble_color_self_dark';
      case BubbleColorSlot.otherDark:
        return 'bubble_color_other_dark';
    }
  }

  Color get defaultColor {
    switch (this) {
      case BubbleColorSlot.selfLight:
        return AppColors.bubbleSelfLight;
      case BubbleColorSlot.otherLight:
        return AppColors.bubbleOtherLight;
      case BubbleColorSlot.selfDark:
        return AppColors.bubbleSelfDark;
      case BubbleColorSlot.otherDark:
        return AppColors.bubbleOtherDark;
    }
  }
}

class SettingsProvider extends ChangeNotifier {
  AppThemeMode _themeMode = AppThemeMode.system;
  Color _accentColor = AppColors.presetColors.first; // 默认微信绿
  // 自定义聊天气泡颜色（未设置时使用 AppColors 默认值）
  final Map<BubbleColorSlot, Color> _bubbleColors = {};
  // 自定义聊天气泡内字体颜色（未设置时使用 AppColors 默认值）
  final Map<BubbleTextSlot, Color> _bubbleTextColors = {};
  // 启动时自动检测更新
  bool _autoCheckUpdate = true;
  // 更新代理地址（默认第一个内置加速源）
  String _updateProxyUrl = kProxySources.first;
  // 更新检测仓库（可持久化自定义，默认内置 Gitee / GitHub）
  String _updateGiteeRepoUrl = kGiteeRepoUrl;
  String _updateGitHubRepoUrl = kGitHubRepoUrl;
  // 未读消息发送系统通知
  bool _unreadNotify = true;
  // 开发者模式（在「我」页底部显示通知与日志文本框）
  bool _developerMode = false;
  // 允许角色在回复中按需发送用户已保存的表情包（默认开启）
  bool _allowStickerSend = true;
  // 全局角色头像框样式（默认方形）
  AvatarFrameStyle _avatarFrameStyle = AvatarFrameStyle.square;
  // 聊天气泡样式（默认经典）
  BubbleStyle _bubbleStyle = BubbleStyle.classic;
  // 会话 UI 样式（默认）
  UiStyle _uiStyle = UiStyle.classic;
  // 自定义开屏图标本地持久化路径（未设置时为空字符串）
  String _splashIconPath = '';
  // 气泡字体分别绑定我方与对方；空串使用系统默认字体。
  String _selfBubbleFontName = '';
  String _otherBubbleFontName = '';
  double _bubbleFontSize = 16;
  final ImportedFontStorage _fontStorage = const ImportedFontStorage();

  AppThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  bool get autoCheckUpdate => _autoCheckUpdate;
  String get updateProxyUrl => _updateProxyUrl;
  String get updateGiteeRepoUrl => _updateGiteeRepoUrl;
  String get updateGitHubRepoUrl => _updateGitHubRepoUrl;
  bool get unreadNotify => _unreadNotify;
  bool get developerMode => _developerMode;

  /// 是否允许角色按需发送用户已保存的表情包
  bool get allowStickerSend => _allowStickerSend;
  AvatarFrameStyle get avatarFrameStyle => _avatarFrameStyle;
  BubbleStyle get bubbleStyle => _bubbleStyle;
  UiStyle get uiStyle => _uiStyle;
  String get splashIconPath => _splashIconPath;
  bool get hasSplashIcon => _splashIconPath.isNotEmpty;
  String get selfBubbleFontName => _selfBubbleFontName;
  String get otherBubbleFontName => _otherBubbleFontName;
  double get bubbleFontSize => _bubbleFontSize;

  String bubbleFontFamily(bool isUser) {
    final name = isUser ? _selfBubbleFontName : _otherBubbleFontName;
    return name.isEmpty ? '' : importedFontFamily(name);
  }

  Color bubbleColor(BubbleColorSlot slot) =>
      _bubbleColors[slot] ?? slot.defaultColor;

  bool isBubbleColorDefault(BubbleColorSlot slot) =>
      !_bubbleColors.containsKey(slot);

  Color bubbleTextColor(BubbleTextSlot slot) =>
      _bubbleTextColors[slot] ?? slot.defaultColor;

  bool isBubbleTextColorDefault(BubbleTextSlot slot) =>
      !_bubbleTextColors.containsKey(slot);

  /// 结合系统亮度解析当前使用的明暗模式
  Brightness resolveBrightness(Brightness systemBrightness) {
    switch (_themeMode) {
      case AppThemeMode.system:
        return systemBrightness;
      case AppThemeMode.light:
        return Brightness.light;
      case AppThemeMode.dark:
        return Brightness.dark;
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('theme_mode');
    _themeMode = AppThemeMode.values.firstWhere(
      (m) => m.name == mode,
      orElse: () => AppThemeMode.system,
    );
    final colorValue = prefs.getInt('accent_color');
    _accentColor =
        colorValue != null ? Color(colorValue) : AppColors.presetColors.first;
    for (final slot in BubbleColorSlot.values) {
      final v = prefs.getInt(slot.storageKey);
      if (v != null) _bubbleColors[slot] = Color(v);
    }
    for (final slot in BubbleTextSlot.values) {
      final v = prefs.getInt(slot.storageKey);
      if (v != null) _bubbleTextColors[slot] = Color(v);
    }
    _autoCheckUpdate = prefs.getBool('auto_check_update') ?? true;
    _updateProxyUrl =
        prefs.getString('update_proxy_url') ?? kProxySources.first;
    _updateGiteeRepoUrl =
        prefs.getString('update_gitee_repo_url') ?? kGiteeRepoUrl;
    _updateGitHubRepoUrl =
        prefs.getString('update_github_repo_url') ?? kGitHubRepoUrl;
    // 将早期内置仓库地址迁移到当前官方仓库；用户自定义的其他地址不覆盖。
    if (_updateGitHubRepoUrl == 'https://github.com/Niriko-mu/AiChat') {
      _updateGitHubRepoUrl = kGitHubRepoUrl;
      await prefs.setString('update_github_repo_url', kGitHubRepoUrl);
    }
    _unreadNotify = prefs.getBool('unread_notify') ?? true;
    _developerMode = prefs.getBool('developer_mode') ?? false;
    _allowStickerSend = prefs.getBool('allow_sticker_send') ?? true;
    _avatarFrameStyle = AvatarFrameStyle.values.firstWhere(
      (s) => s.name == prefs.getString('avatar_frame_style'),
      orElse: () => AvatarFrameStyle.square,
    );
    // 旧命名 honkaiSms 兼容映射到 sr
    final storedBubbleStyle = prefs.getString('bubble_style');
    _bubbleStyle = switch (storedBubbleStyle) {
      'honkaiSms' || 'sr' => BubbleStyle.sr,
      'ww' => BubbleStyle.ww,
      'zmd' => BubbleStyle.zmd,
      _ => BubbleStyle.classic,
    };
    _uiStyle = UiStyle.values.firstWhere(
      (s) => s.name == prefs.getString('ui_style'),
      orElse: () => UiStyle.classic,
    );
    _splashIconPath = prefs.getString('splash_icon_path') ?? '';
    _selfBubbleFontName = prefs.getString('bubble_font_self') ?? '';
    _otherBubbleFontName = prefs.getString('bubble_font_other') ?? '';
    _bubbleFontSize = (prefs.getDouble('bubble_font_size') ?? 16)
        .clamp(12, 24)
        .toDouble();
    await _restoreBubbleFonts(prefs);
    notifyListeners();
  }

  Future<void> _restoreBubbleFonts(SharedPreferences prefs) async {
    final selfLoaded = await _loadBubbleFont(_selfBubbleFontName);
    if (!selfLoaded && _selfBubbleFontName.isNotEmpty) {
      _selfBubbleFontName = '';
      await prefs.remove('bubble_font_self');
    }
    final otherLoaded = await _loadBubbleFont(_otherBubbleFontName);
    if (!otherLoaded && _otherBubbleFontName.isNotEmpty) {
      _otherBubbleFontName = '';
      await prefs.remove('bubble_font_other');
    }
  }

  Future<bool> _loadBubbleFont(String name) async {
    if (name.isEmpty) return true;
    final Uint8List? bytes = await _fontStorage.loadFont(name);
    if (bytes == null) return false;
    final loader = FontLoader(importedFontFamily(name))
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    return true;
  }

  /// 设置我方或对方气泡的字体；空名称恢复系统默认字体。
  Future<void> setBubbleFont({required bool isUser, required String name}) async {
    if (name.isNotEmpty && !await _loadBubbleFont(name)) {
      throw StateError('字体文件不存在或无法加载');
    }
    if (isUser) {
      _selfBubbleFontName = name;
    } else {
      _otherBubbleFontName = name;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(isUser ? 'bubble_font_self' : 'bubble_font_other', name);
    notifyListeners();
  }

  /// 设置双方聊天气泡正文的字号，范围 12~24 logical pixels。
  Future<void> setBubbleFontSize(double value) async {
    _bubbleFontSize = value.clamp(12, 24).toDouble();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bubble_font_size', _bubbleFontSize);
    notifyListeners();
  }

  /// 删除字体后清除引用，防止下次启动时保留失效选择。
  Future<void> clearDeletedBubbleFont(String name) async {
    var changed = false;
    if (_selfBubbleFontName == name) {
      _selfBubbleFontName = '';
      changed = true;
    }
    if (_otherBubbleFontName == name) {
      _otherBubbleFontName = '';
      changed = true;
    }
    if (!changed) return;
    final prefs = await SharedPreferences.getInstance();
    if (_selfBubbleFontName.isEmpty) await prefs.remove('bubble_font_self');
    if (_otherBubbleFontName.isEmpty) await prefs.remove('bubble_font_other');
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accent_color', color.toARGB32());
    notifyListeners();
  }

  /// 设置某一气泡颜色项（浅/深 × 自己/对方）
  Future<void> setBubbleColor(BubbleColorSlot slot, Color color) async {
    _bubbleColors[slot] = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(slot.storageKey, color.toARGB32());
    notifyListeners();
  }

  /// 恢复某一气泡颜色项为默认
  Future<void> resetBubbleColor(BubbleColorSlot slot) async {
    _bubbleColors.remove(slot);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(slot.storageKey);
    notifyListeners();
  }

  /// 设置启动时自动检测更新
  Future<void> setAutoCheckUpdate(bool value) async {
    _autoCheckUpdate = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_check_update', value);
    notifyListeners();
  }

  /// 设置更新代理地址
  Future<void> setUpdateProxyUrl(String url) async {
    _updateProxyUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('update_proxy_url', url);
    notifyListeners();
  }

  /// 设置更新检测用的 Gitee 仓库地址（空串恢复默认）
  Future<void> setUpdateGiteeRepoUrl(String url) async {
    final v = url.trim();
    _updateGiteeRepoUrl = v.isEmpty ? kGiteeRepoUrl : v.replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('update_gitee_repo_url', _updateGiteeRepoUrl);
    notifyListeners();
  }

  /// 设置更新检测用的 GitHub 仓库地址（空串恢复默认）
  Future<void> setUpdateGitHubRepoUrl(String url) async {
    final v = url.trim();
    _updateGitHubRepoUrl =
        v.isEmpty ? kGitHubRepoUrl : v.replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('update_github_repo_url', _updateGitHubRepoUrl);
    notifyListeners();
  }

  /// 恢复更新仓库为内置默认
  Future<void> resetUpdateRepos() async {
    await setUpdateGiteeRepoUrl(kGiteeRepoUrl);
    await setUpdateGitHubRepoUrl(kGitHubRepoUrl);
  }

  /// 设置未读消息是否发送系统通知
  Future<void> setUnreadNotify(bool value) async {
    _unreadNotify = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('unread_notify', value);
    notifyListeners();
  }

  /// 设置开发者模式开关（开启后「我」页底部显示通知与日志文本框）
  Future<void> setDeveloperMode(bool value) async {
    _developerMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('developer_mode', value);
    notifyListeners();
  }

  /// 设置是否允许角色按需发送用户已保存的表情包
  Future<void> setAllowStickerSend(bool value) async {
    _allowStickerSend = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('allow_sticker_send', value);
    notifyListeners();
  }

  /// 设置全局角色头像框样式（方形 / 圆形）
  Future<void> setAvatarFrameStyle(AvatarFrameStyle style) async {
    _avatarFrameStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('avatar_frame_style', style.name);
    notifyListeners();
  }

  /// 设置聊天气泡样式（经典 / 崩铁）
  Future<void> setBubbleStyle(BubbleStyle style) async {
    _bubbleStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bubble_style', style.name);
    notifyListeners();
  }

  /// 设置会话 UI 样式（默认 / 终末地）
  Future<void> setUiStyle(UiStyle style) async {
    _uiStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ui_style', style.name);
    notifyListeners();
  }

  /// 设置开屏图标：把相册/文件选择器选中的图片复制到应用文档目录持久化。
  /// 更换图标时先删除旧的本地图片，避免残留孤儿文件占用缓存。
  Future<void> setSplashIcon(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final iconDir = Directory('${dir.path}/splash_icons');
    if (!iconDir.existsSync()) iconDir.createSync(recursive: true);
    if (_splashIconPath.isNotEmpty) _deleteFileQuietly(_splashIconPath);
    // 保留原扩展名（便于识别），时间戳避免同名覆盖
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'img';
    final destPath =
        '${iconDir.path}/splash_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(sourcePath).copy(destPath);

    _splashIconPath = destPath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('splash_icon_path', destPath);
    notifyListeners();
  }

  /// 恢复默认开屏图标：删除已导入的本地图片并清空设置
  Future<void> resetSplashIcon() async {
    if (_splashIconPath.isNotEmpty) _deleteFileQuietly(_splashIconPath);
    _splashIconPath = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('splash_icon_path');
    notifyListeners();
  }

  /// 静默删除文件（失败不影响主流程）
  void _deleteFileQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// 设置某一气泡内字体颜色项（浅/深 × 自己/对方）
  Future<void> setBubbleTextColor(BubbleTextSlot slot, Color color) async {
    _bubbleTextColors[slot] = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(slot.storageKey, color.toARGB32());
    notifyListeners();
  }

  /// 恢复某一气泡内字体颜色项为默认
  Future<void> resetBubbleTextColor(BubbleTextSlot slot) async {
    _bubbleTextColors.remove(slot);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(slot.storageKey);
    notifyListeners();
  }
}
