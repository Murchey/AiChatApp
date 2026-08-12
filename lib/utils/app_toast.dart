import 'dart:async';
import 'package:flutter/cupertino.dart';

/// 全局根导航 key：供后台任务（如朋友圈 AI 互动）在不持有页面
/// context 的情况下弹出 Toast / 弹窗。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 轻量 Toast：底部悬浮黑色圆角提示，[duration] 后自动消失。
///
/// 使用根 Overlay 插入，任意页面 / 后台任务均可调用，
/// 页面路由切换不影响提示展示。
void showAppToast(String message, {Duration duration = const Duration(milliseconds: 2000)}) {
  final navigator = appNavigatorKey.currentState;
  final overlay = navigator?.overlay;
  if (overlay == null || message.isEmpty) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(ctx).padding.bottom + 80,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: CupertinoColors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.white,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(duration, () {
    if (entry.mounted) entry.remove();
  });
}
