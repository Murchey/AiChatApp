import 'package:flutter/cupertino.dart';

/// 亮/暗两套色板
class AppColors {
  // 亮色模式
  static const scaffoldLight = Color(0xFFEDEDED); // 页面背景
  static const navBarLight = Color(0xFFF7F7F7); // 导航栏背景（微信浅色）
  static const listBgLight = Color(0xFFFFFFFF); // 列表卡片背景
  static const chatBgLight = Color(0xFFFAFAFA); // 聊天纯色背景（白）
  static const bubbleSelfLight = Color(0xFFDCF8C6); // 自己气泡（浅绿）
  static const bubbleOtherLight = Color(0xFFFFFFFF); // 对方气泡
  static const textPrimaryLight = Color(0xFF1F1F1F);
  static const textSecondaryLight = Color(0xFF8A8A8E);
  static const fieldBgLight = Color(0xFFEDEDED); // 输入框背景

  // 暗色模式（统一使用 #181818）
  static const scaffoldDark = Color(0xFF181818);
  static const navBarDark = Color(0xFF181818);
  static const listBgDark = Color(0xFF222222);
  static const chatBgDark = Color(0xFF181818);
  static const bubbleSelfDark = Color(0xFF056162); // 自己气泡（深绿）
  static const bubbleOtherDark = Color(0xFF262626);
  static const textPrimaryDark = Color(0xFFF0F0F0);
  static const textSecondaryDark = Color(0xFF8E8E93);
  static const fieldBgDark = Color(0xFF2A2A2C);

  // 预设主题色（5 个）
  static const presetColors = <Color>[
    Color(0xFF07C160), // 微信绿
    Color(0xFF25D366), // WhatsApp 绿
    Color(0xFF007AFF), // 经典蓝
    Color(0xFFFF9500), // 活力橙
    Color(0xFFAF52DE), // 神秘紫
  ];
}

class AppTheme {
  /// 构建动态主题（明暗 + 主题色）
  static CupertinoThemeData buildTheme({
    required Brightness brightness,
    required Color accent,
  }) {
    final isDark = brightness == Brightness.dark;
    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: accent,
      primaryContrastingColor: CupertinoColors.white,
      scaffoldBackgroundColor:
          isDark ? AppColors.scaffoldDark : AppColors.scaffoldLight,
      barBackgroundColor: isDark ? AppColors.navBarDark : AppColors.navBarLight,
      textTheme: CupertinoTextThemeData(
        primaryColor: accent,
        textStyle: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 16,
          color: isDark
              ? AppColors.textPrimaryDark
              : AppColors.textPrimaryLight,
        ),
        navTitleTextStyle: TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: isDark
              ? AppColors.textPrimaryDark
              : AppColors.textPrimaryLight,
        ),
        navActionTextStyle: TextStyle(fontSize: 16, color: accent),
      ),
    );
  }
}

/// 通过 BuildContext 便捷获取主题相关颜色
extension AppThemeX on BuildContext {
  bool get isDark => CupertinoTheme.of(this).brightness == Brightness.dark;

  Color get accentColor => CupertinoTheme.of(this).primaryColor;

  Color get scaffoldColor =>
      isDark ? AppColors.scaffoldDark : AppColors.scaffoldLight;

  Color get navBarColor => isDark ? AppColors.navBarDark : AppColors.navBarLight;

  Color get listBgColor => isDark ? AppColors.listBgDark : AppColors.listBgLight;

  Color get chatBgColor => isDark ? AppColors.chatBgDark : AppColors.chatBgLight;

  Color get bubbleSelfColor =>
      isDark ? AppColors.bubbleSelfDark : AppColors.bubbleSelfLight;

  Color get bubbleOtherColor =>
      isDark ? AppColors.bubbleOtherDark : AppColors.bubbleOtherLight;

  Color get textPrimaryColor =>
      isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

  Color get textSecondaryColor =>
      isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  Color get fieldBgColor => isDark ? AppColors.fieldBgDark : AppColors.fieldBgLight;

  Color get separatorColor =>
      isDark ? CupertinoColors.white.withValues(alpha: 0.1) : CupertinoColors.systemGrey5;
}
