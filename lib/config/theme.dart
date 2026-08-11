import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

/// 亮/暗两套色板
class AppColors {
  // 亮色模式
  static const scaffoldLight = Color(0xFFEDEDED); // 页面背景
  static const navBarLight = Color(0xFFF7F7F7); // 导航栏背景（微信浅色）
  static const listBgLight = Color(0xFFFFFFFF); // 列表卡片背景
  static const chatBgLight = Color(0xFFFAFAFA); // 聊天纯色背景（白）
  static const bubbleSelfLight = Color(0xFF95EC6A); // 自己气泡
  static const bubbleOtherLight = Color(0xFFFFFFFF); // 对方气泡
  static const textPrimaryLight = Color(0xFF1F1F1F);
  static const textSecondaryLight = Color(0xFF8A8A8E);
  static const fieldBgLight = Color(0xFFEDEDED); // 输入框背景

  // 暗色模式（页面背景统一 #111111）
  static const scaffoldDark = Color(0xFF111111);
  static const navBarDark = Color(0xFF111111);
  static const listBgDark = Color(0xFF222222);
  static const chatBgDark = Color(0xFF111111);
  static const bubbleSelfDark = Color(0xFF40B475); // 自己气泡
  static const bubbleOtherDark = Color(0xFF2C2C2C); // 对方气泡
  static const textPrimaryDark = Color(0xFFF0F0F0);
  static const textSecondaryDark = Color(0xFF8E8E93);
  static const fieldBgDark = Color(0xFF2A2A2C);

  // 气泡内字体颜色（自己/对方 × 浅色/深色）
  static const bubbleTextSelfLight = Color(0xFF000000);
  static const bubbleTextOtherLight = Color(0xFF000000);
  static const bubbleTextSelfDark = Color(0xFF000000);
  static const bubbleTextOtherDark = Color(0xFFD6D6D6);

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

  /// 自己气泡颜色：支持在设置中按明暗模式单独自定义
  Color get bubbleSelfColor {
    final settings = read<SettingsProvider>();
    return settings.bubbleColor(
        isDark ? BubbleColorSlot.selfDark : BubbleColorSlot.selfLight);
  }

  /// 对方气泡颜色：支持在设置中按明暗模式单独自定义
  Color get bubbleOtherColor {
    final settings = read<SettingsProvider>();
    return settings.bubbleColor(
        isDark ? BubbleColorSlot.otherDark : BubbleColorSlot.otherLight);
  }

  /// 自己气泡内字体颜色：支持在设置中按明暗模式单独自定义
  Color get bubbleTextSelfColor {
    final settings = read<SettingsProvider>();
    return settings.bubbleTextColor(
        isDark ? BubbleTextSlot.selfDark : BubbleTextSlot.selfLight);
  }

  /// 对方气泡内字体颜色：支持在设置中按明暗模式单独自定义
  Color get bubbleTextOtherColor {
    final settings = read<SettingsProvider>();
    return settings.bubbleTextColor(
        isDark ? BubbleTextSlot.otherDark : BubbleTextSlot.otherLight);
  }

  Color get textPrimaryColor =>
      isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

  Color get textSecondaryColor =>
      isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  Color get fieldBgColor => isDark ? AppColors.fieldBgDark : AppColors.fieldBgLight;

  Color get separatorColor =>
      isDark ? CupertinoColors.white.withValues(alpha: 0.1) : CupertinoColors.systemGrey5;
}
