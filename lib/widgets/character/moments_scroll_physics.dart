import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';

/// 朋友圈列表滚动物理（顶部橡皮筋、底部硬截止）。
class MomentsScrollPhysics extends BouncingScrollPhysics {
  /// [allowTopOverscroll] 仅用于需要下拉展开内容的角色详情页。
  /// 首页朋友圈没有可展开的封面，因此默认关闭顶部惯性回弹，避免快速
  /// 连续手势在边界附近反复启动弹簧模拟而产生抖动。
  final bool allowTopOverscroll;

  const MomentsScrollPhysics({
    super.parent,
    this.allowTopOverscroll = true,
  });

  @override
  MomentsScrollPhysics applyTo(ScrollPhysics? ancestor) => MomentsScrollPhysics(
        parent: buildParent(ancestor),
        allowTopOverscroll: allowTopOverscroll,
      );

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final double result = _applyBoundaryConditions(position, value);
    return result;
  }

  double _applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value < position.minScrollExtent) {
      // 首页没有封面下拉语义，直接把拖动限制在顶部；这样快速回到
      // 顶部时不会进入负偏移弹簧，再被下一次手势反复打断。
      if (!allowTopOverscroll) {
        if (position.pixels <= position.minScrollExtent) {
          return value - position.pixels;
        }
        return value - position.minScrollExtent;
      }
      // 角色详情页保留原有轻微下拉回弹。
      return 0.0;
    }
    // 底部：硬截止（Clamping 行为），到达 maxScrollExtent 后不再越界
    if (value > position.maxScrollExtent &&
        position.pixels <= position.maxScrollExtent) {
      return value - position.maxScrollExtent;
    }
    // 防御：极端情况下已越过底部，继续增大时按越界量返回
    if (position.pixels > position.maxScrollExtent &&
        value >= position.pixels) {
      return value - position.pixels;
    }
    return 0.0;
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final Tolerance tolerance = toleranceFor(position);
    // 顶部越界：橡皮筋回弹到 0（下拉展开封面后松手回弹）。
    // 速度取原始 velocity（与官方 BouncingScrollSimulation._underscrollSimulation
    // 一致）：负速度先继续深入越界区再回弹，避免 -velocity 造成的收敛振荡。
    if (position.pixels < position.minScrollExtent) {
      if (!allowTopOverscroll) {
        return ScrollSpringSimulation(
          spring,
          position.pixels,
          position.minScrollExtent,
          0.0,
          tolerance: tolerance,
        );
      }
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        position.minScrollExtent,
        velocity,
        tolerance: tolerance,
      );
    }
    // 底部越界（防御分支，正常拖拽已被硬截止）：回弹到 maxScrollExtent
    if (position.pixels > position.maxScrollExtent) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        position.maxScrollExtent,
        math.min(0.0, velocity),
        tolerance: tolerance,
      );
    }
    // 正常范围：惯性滚动
    if (velocity.abs() < tolerance.velocity) return null;
    // 向下（朝底部）：Clamping 摩擦减速，配合拖拽硬截止，到底即停
    if (velocity > 0.0) {
      if (position.pixels >= position.maxScrollExtent) return null;
      return ClampingScrollSimulation(
        position: position.pixels,
        velocity: velocity,
        tolerance: tolerance,
      );
    }
    if (!allowTopOverscroll) {
      // 首页顶部是硬边界。Clamping simulation 到达边界后由
      // applyBoundaryConditions 终止 ballistic activity，不会再启动弹簧。
      return ClampingScrollSimulation(
        position: position.pixels,
        velocity: velocity,
        tolerance: tolerance,
      );
    }
    // 角色详情页向上（朝顶部）保留官方 BouncingScrollSimulation，供封面
    // 下拉展开/回弹使用。
    return BouncingScrollSimulation(
      spring: spring,
      position: position.pixels,
      velocity: velocity,
      leadingExtent: position.minScrollExtent,
      trailingExtent: position.maxScrollExtent,
      tolerance: tolerance,
    );
  }
}
