import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../services/update_service.dart';

/// 明暗模式：跟随系统 / 浅色 / 深色
enum AppThemeMode { system, light, dark }

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
  // 未读消息发送系统通知
  bool _unreadNotify = true;

  AppThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  bool get autoCheckUpdate => _autoCheckUpdate;
  String get updateProxyUrl => _updateProxyUrl;
  bool get unreadNotify => _unreadNotify;

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
    _unreadNotify = prefs.getBool('unread_notify') ?? true;
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

  /// 设置未读消息是否发送系统通知
  Future<void> setUnreadNotify(bool value) async {
    _unreadNotify = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('unread_notify', value);
    notifyListeners();
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
