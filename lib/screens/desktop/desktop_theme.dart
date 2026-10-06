import 'package:flutter/cupertino.dart';

/// 电脑端 Apple / iMessage 风格配色（随系统深浅模式切换）。
///
/// 桌面壳只使用这一组 token，避免和手机端的 Cupertino 主题出现两套
/// 颜色语义。颜色保持高对比度，气泡和面板在浅色、深色模式下都能清楚
/// 区分层级。
class DesktopPalette {
  final Brightness brightness;
  final Color accentColor;

  const DesktopPalette(this.brightness, this.accentColor);

  bool get isDark => brightness == Brightness.dark;

  /// 窗口主背景
  Color get shellBg =>
      isDark ? const Color(0xFF0B0B0F) : const Color(0xFFF5F5F7);

  /// 左侧功能栏
  Color get railBg =>
      isDark ? const Color(0xFF111318) : const Color(0xFFECECF0);
  Color get railIcon =>
      isDark ? const Color(0xFF9A9CA5) : const Color(0xFF686A73);
  Color get railIconActive => accentColor;
  Color get railItemBg => accentColor.withValues(alpha: isDark ? 0.18 : 0.12);
  Color get railAvatarBg =>
      isDark ? const Color(0xFF252A34) : const Color(0xFFF0F0F5);

  /// 列表 / 主区
  Color get listBg =>
      isDark ? const Color(0xFF111318) : const Color(0xFFF5F5F7);
  Color get panelBg =>
      isDark ? const Color(0xFF17191F) : const Color(0xFFFFFFFF);
  Color get chatBg =>
      isDark ? const Color(0xFF0F1116) : const Color(0xFFF5F5F7);
  Color get selected =>
      isDark ? const Color(0xFF252A34) : const Color(0xFFE2EEFF);
  Color get divider =>
      isDark ? const Color(0xFF2A2D35) : const Color(0xFFE1E1E6);
  Color get border =>
      isDark ? const Color(0xFF2A2D35) : const Color(0xFFE1E1E6);

  Color get textPrimary =>
      isDark ? const Color(0xFFF5F5F7) : const Color(0xFF1C1C1E);
  Color get textSecondary =>
      isDark ? const Color(0xFFA7AAB4) : const Color(0xFF6C6C70);
  Color get textTertiary =>
      isDark ? const Color(0xFF747782) : const Color(0xFF98989D);
  Color get accent => accentColor;
  Color get danger =>
      isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);

  /// 气泡
  Color get bubbleSelf =>
      isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
  Color get bubbleSelfText => const Color(0xFFFFFFFF);
  Color get bubbleOther =>
      isDark ? const Color(0xFF292C33) : const Color(0xFFFFFFFF);
  Color get bubbleOtherText => textPrimary;

  /// 输入区
  Color get inputBarBg =>
      isDark ? const Color(0xFF17191F) : const Color(0xFFFFFFFF);
  Color get inputFieldBg =>
      isDark ? const Color(0xFF252A34) : const Color(0xFFF0F0F5);

  static DesktopPalette of(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final b = theme.brightness;
    return DesktopPalette(b ?? Brightness.light, theme.primaryColor);
  }
}

/// Windows / 桌面默认字体栈
const List<String> kDesktopFontFallback = <String>[
  'Segoe UI',
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'sans-serif',
];
