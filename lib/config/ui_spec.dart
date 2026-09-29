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

  // ── 字号阶梯 ──
  static const double fontTitle = 17;
  static const double fontBody = 15;
  static const double fontBodySm = 14;
  static const double fontCaption = 12;
  static const double fontTiny = 11;
  static const double fontMicro = 10;
  static const double fontDisplay = 28;

  // ── 圆角 ──
  static const double radiusCard = 12;
  static const double radiusInput = 10;
  static const double radiusButton = 10;
  static const double radiusBubble = 15;
  static const double radiusPanel = 14;

  // ── 控件高度 ──
  static const double controlHeight = 44;
  static const double miniButtonHeight = 32;
  static const double avatarChat = 40;
  static const double avatarList = 48;
  static const double avatarProfile = 72;

  /// 图文间距
  static const double iconLabelGap = spaceSm;
}

/// 常用文案样式
extension UiSpecText on TextStyle {
  TextStyle get caption => copyWith(fontSize: UiSpec.fontCaption);
  TextStyle get bodySm => copyWith(fontSize: UiSpec.fontBodySm);
}
