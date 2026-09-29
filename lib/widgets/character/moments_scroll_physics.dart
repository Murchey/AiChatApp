import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';

/// 朋友圈列表滚动物理（顶部橡皮筋、底部硬截止）。
class MomentsScrollPhysics extends BouncingScrollPhysics {
  const MomentsScrollPhysics({super.parent});

  @override
  MomentsScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      MomentsScrollPhysics(parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final double result = _applyBoundaryConditions(position, value);
    return result;
  }

  double _applyBoundaryConditions(ScrollMetrics position, double value) {
    // 顶部：允许越界（Bouncing 行为），供下拉展开封面
    if (value < position.minScrollExtent) return 0.0;
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
    // 向上（朝顶部）：官方 BouncingScrollSimulation —— 摩擦减速，接近顶部时
    // 转入受限弹簧回弹。不能再用 ClampingScrollSimulation：顶部为开边界而
    // 惯性模拟不经过 applyBoundaryConditions，会直接穿透顶部滑进深度越界区
    // （-100~-160px）再缓慢回弹，即用户感知的"抖动"。
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
