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
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: pageH,
    vertical: spaceLg,
  );

  /// 列表条目水平内边距
  static const EdgeInsets listTilePadding = EdgeInsets.symmetric(
    horizontal: spaceLg,
    vertical: spaceMd,
  );

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

  /// 嵌入式底部导航模式下列表末尾的视觉留白。
  static const double bottomPanelContentBottomInset = spaceLg;

  /// 设置页浮动选择面板与锚定条目之间的间距。
  static const double settingsInlinePanelGap = 8;

  /// 设置页浮动选择面板圆角与阴影。
  static const double settingsInlinePanelRadius = 16;
  static const double settingsInlinePanelMaxHeight = 520;
  static const double settingsInlinePanelShadowBlur = 18;
  static const double settingsInlinePanelShadowOpacity = 0.18;

  /// 设置页顶部与分组之间的留白。Cupertino 二级页的导航栏会占用
  /// 一行标题高度，额外留出约一行正文高度，避免首项贴入导航栏底部。
  static const double settingsPageTop = 42;

  /// 设置分组之间的垂直留白
  static const double settingsSectionGap = 24;

  /// 设置分组的圆角
  static const double settingsSectionRadius = 22;

  /// 设置页分组面板的水平内边距
  static const double settingsSectionHorizontal = 2;

  /// 设置行最小高度
  static const double settingsRowMinHeight = 62;

  /// 设置行内容水平内边距
  static const double settingsRowHorizontal = 16;

  /// 设置行内容垂直内边距
  static const double settingsRowVertical = 11;

  /// 设置图标的占位宽度，确保各行标题左边缘对齐
  static const double settingsIconWidth = 38;

  /// 设置分组标题字号
  static const double settingsSectionTitle = 15;

  /// 设置项标题字号
  static const double settingsRowTitle = 16;

  /// 设置项说明字号
  static const double settingsRowSubtitle = 12;

  /// 首页会话行高度
  static const double conversationRowHeight = 76;

  /// 首页会话头像尺寸
  static const double conversationAvatar = 44;

  /// 导航选中指示器尺寸
  static const double floatingIndicatorHeight = 48;
  static const double floatingIndicatorRadius = 24;

  /// 导航选中指示器的中性表面透明度
  static const double floatingSelectedSurfaceLightOpacity = 0.86;
  static const double floatingSelectedSurfaceDarkOpacity = 0.82;

  /// 导航选中指示器的主题色细描边透明度
  static const double floatingSelectedBorderLightOpacity = 0.24;
  static const double floatingSelectedBorderDarkOpacity = 0.32;

  /// 导航选中指示器的抬升阴影
  static const double floatingSelectedShadowLightOpacity = 0.10;
  static const double floatingSelectedShadowDarkOpacity = 0.28;
  static const double floatingSelectedShadowBlur = 10;
  static const Offset floatingSelectedShadowOffset = Offset(0, 2);

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

  /// Telegram-style chat tool panel sizing.
  // 工具面板内容从顶部开始排列，避免加号面板出现一整行多余留白。
  static const double inputPanelTopPadding = 0;
  static const double inputPanelBottomPadding = 4;
  static const double inputPanelHandleGap = 0;
  static const double inputPanelHandleWidth = 32;
  static const double inputPanelHandleHeight = 3;
  static const double inputPanelButtonSize = 56;
  static const double inputPanelRowGap = 12;
  static const double inputPanelMaxHeight = 320;

  /// 图文间距
  static const double iconLabelGap = spaceSm;
}

/// 常用文案样式
extension UiSpecText on TextStyle {
  TextStyle get caption => copyWith(fontSize: UiSpec.fontCaption);
  TextStyle get bodySm => copyWith(fontSize: UiSpec.fontBodySm);
}
