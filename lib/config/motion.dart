import 'package:flutter/animation.dart';

/// 全局动效时长与曲线 token。
/// 替换各处散落的 Duration/Curves 字面量，保证节奏一致。
class AppMotion {
  AppMotion._();

  /// 按压、开关等瞬时反馈
  static const Duration micro = Duration(milliseconds: 80);

  /// 面板 / 菜单出现
  static const Duration quick = Duration(milliseconds: 160);

  /// 常规过渡（滚动到目标、轻量布局变化）
  static const Duration base = Duration(milliseconds: 220);

  /// 封面吸附、页面切换等大位移
  static const Duration slow = Duration(milliseconds: 280);

  /// 输入栏键盘收起后再接管面板的等待
  static const Duration inputPanelSettle = Duration(milliseconds: 180);

  /// 选中态、半透明胶囊等轻量状态变化
  static const Duration tabSelection = Duration(milliseconds: 240);

  /// 兼容已有轻量选中态调用方
  static const Duration selection = tabSelection;

  /// 选中图标与标签的淡入切换
  static const Duration tabIconFade = Duration(milliseconds: 140);

  /// 按压反馈的轻微缩放比例
  static const double pressScale = 0.98;

  static const Curve tabSelectionCurve = Curves.easeOutCubic;

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve standard = Curves.easeInOutCubic;

  /// 列表 animateTo 等偏轻的双向过渡
  static const Curve soft = Curves.easeInOut;
  static const Curve out = Curves.easeOut;
}
