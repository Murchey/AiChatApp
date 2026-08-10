import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';

/// 明暗模式：跟随系统 / 浅色 / 深色
enum AppThemeMode { system, light, dark }

class SettingsProvider extends ChangeNotifier {
  AppThemeMode _themeMode = AppThemeMode.system;
  Color _accentColor = AppColors.presetColors.first; // 默认微信绿

  AppThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;

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
    _accentColor = colorValue != null ? Color(colorValue) : AppColors.presetColors.first;
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
}
