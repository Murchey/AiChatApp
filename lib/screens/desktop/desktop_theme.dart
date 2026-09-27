import 'package:flutter/cupertino.dart';

/// 电脑端微信风配色（随系统深浅模式切换）
class DesktopPalette {
  final Brightness brightness;

  const DesktopPalette(this.brightness);

  bool get isDark => brightness == Brightness.dark;

  /// 窗口主背景
  Color get shellBg => isDark ? const Color(0xFF1F1F1F) : const Color(0xFFEDEDED);

  /// 左侧功能栏
  Color get railBg => isDark ? const Color(0xFF171717) : const Color(0xFF2E2E2E);
  Color get railIcon => isDark ? const Color(0xFFA0A0A0) : const Color(0xFF9A9A9A);
  Color get railIconActive =>
      isDark ? const Color(0xFF95EC69) : const Color(0xFF95EC69);
  Color get railItemBg => isDark ? const Color(0xFF2A2A2A) : const Color(0xFF3E3E3E);
  Color get railAvatarBg => isDark ? const Color(0xFF2A2A2A) : const Color(0xFF3E3E3E);

  /// 列表 / 主区
  Color get listBg => isDark ? const Color(0xFF242424) : const Color(0xFFEDEDED);
  Color get panelBg => isDark ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);
  Color get chatBg => isDark ? const Color(0xFF242424) : const Color(0xFFEDEDED);
  Color get selected => isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD0D0D0);
  Color get divider => isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD0D0D0);
  Color get border => isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD0D0D0);

  Color get textPrimary =>
      isDark ? const Color(0xFFEDEDED) : const Color(0xFF191919);
  Color get textSecondary =>
      isDark ? const Color(0xFF9A9A9A) : const Color(0xFF9A9A9A);
  Color get textTertiary =>
      isDark ? const Color(0xFF6E6E6E) : const Color(0xFFB2B2B2);
  Color get accent => const Color(0xFF07C160);
  Color get wechatGreen => const Color(0xFF95EC69);
  Color get danger => const Color(0xFFFA5151);

  /// 气泡
  Color get bubbleSelf => isDark ? const Color(0xFF3EB575) : const Color(0xFF95EC69);
  Color get bubbleSelfText =>
      isDark ? const Color(0xFF0B1F12) : const Color(0xFF191919);
  Color get bubbleOther => isDark ? const Color(0xFF3A3A3A) : const Color(0xFFFFFFFF);
  Color get bubbleOtherText => textPrimary;

  /// 输入区
  Color get inputBarBg => isDark ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);
  Color get inputFieldBg =>
      isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);

  static DesktopPalette of(BuildContext context) {
    final b = CupertinoTheme.of(context).brightness;
    return DesktopPalette(b ?? Brightness.light);
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
