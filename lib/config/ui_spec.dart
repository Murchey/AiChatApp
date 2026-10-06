import 'package:flutter/cupertino.dart';

/// UI 设计规范常量（developDocs/UI设计规范.md）。
/// 间距 / 字号 / 圆角统一从这里取，避免页面内魔法数字。
class UiSpec {
  UiSpec._();

  // ── 间距（8 网格 + 4 半格） ──
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double spaceXxl = 24;

  /// 页面左右标准边距
  static const double pageH = spaceLg;

  /// 页面上下内边距
  static const EdgeInsets pagePadding =
      EdgeInsets.symmetric(horizontal: pageH, vertical: spaceLg);

  /// 列表条目水平内边距
  static const EdgeInsets listTilePadding =
      EdgeInsets.symmetric(horizontal: spaceLg, vertical: spaceMd);

  // ── 移动端现代壳层 ──
  /// 首页悬浮导航胶囊的高度
  static const double floatingNavHeight = 64;

  /// 悬浮导航和输入浮层的水平外边距
  static const double floatingHorizontal = 16;

  /// 悬浮导航与安全区之间的视觉留白
  static const double floatingBottomGap = 8;

  /// 轻毛玻璃模糊半径
  static const double glassBlurSigma = 18;

  /// 首页底部导航使用的更强背景模糊
  static const double floatingNavBlurSigma = 22;

  /// 悬浮导航的背景透明度（按明暗模式取值）
  static const double floatingNavDarkOpacity = 0.58;
  static const double floatingNavLightOpacity = 0.70;

  /// 页面内容需要为悬浮导航预留的滚动底部空间（不包含系统安全区）
  static const double floatingContentBottomInset =
      floatingNavHeight + floatingBottomGap + spaceLg;

  /// 设置分组之间的垂直留白
  static const double settingsSectionGap = 14;

  /// 设置分组的圆角
  static const double settingsSectionRadius = 16;

  /// 首页会话行高度
  static const double conversationRowHeight = 76;

  /// 首页会话头像尺寸
  static const double conversationAvatar = 44;

  /// 导航选中指示器尺寸
  static const double floatingIndicatorHeight = 48;
  static const double floatingIndicatorRadius = 24;

  /// 导航选中指示器透明度
  static const double floatingSelectedLightOpacity = 0.16;
  static const double floatingSelectedDarkOpacity = 0.22;

  // ── 字号阶梯 ──
  static const double fontTitle = 17;
  static const double fontBody = 15;
  static const double fontBodySm = 14;
  static const double fontCaption = 12;
  static const double fontTiny = 11;
  static const double fontMicro = 10;
  static const double fontDisplay = 28;

  // ── 圆角 ──
  static const double radiusCard = 18;
  static const double radiusInput = 12;
  static const double radiusButton = 14;
  static const double radiusBubble = 18;
  static const double radiusPanel = 20;

  /// 聊天输入浮层的胶囊圆角
  static const double radiusInputCapsule = 24;

  // ── 控件高度 ──
  static const double controlHeight = 44;
  static const double miniButtonHeight = 32;
  static const double avatarChat = 40;
  static const double avatarList = 48;
  static const double avatarProfile = 72;

  /// 聊天输入浮层的高度范围
  static const double inputCapsuleMinHeight = 48;
  static const double inputCapsuleMaxHeight = 108;

  /// 图文间距
  static const double iconLabelGap = spaceSm;
}

/// 常用文案样式
extension UiSpecText on TextStyle {
  TextStyle get caption => copyWith(fontSize: UiSpec.fontCaption);
  TextStyle get bodySm => copyWith(fontSize: UiSpec.fontBodySm);
}
