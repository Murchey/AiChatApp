import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/moment_notification.dart';

/// 朋友圈互动通知：角色给动态点赞/评论产生的未读通知列表（持久化到本地）。
///
/// - [hasUnread] 驱动朋友圈底部 tab 红点与左上角铃铛角标；
/// - 打开通知页（[markAllRead]）后红点消失。
class MomentNotificationProvider extends ChangeNotifier {
  static const _storageKey = 'moment_notifications_v1';

  List<MomentNotification> _activities = [];

  List<MomentNotification> get activities => List.unmodifiable(_activities);

  int get unreadCount => _activities.where((a) => !a.read).length;

  bool get hasUnread => unreadCount > 0;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored != null) {
      try {
        final list = jsonDecode(stored) as List<dynamic>;
        _activities = list
            .map((e) => MomentNotification.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _activities = [];
      }
    }
    notifyListeners();
  }

  /// 新增一条互动通知（置顶显示）
  Future<void> addActivity(MomentNotification notification) async {
    _activities.insert(0, notification);
    await _persist();
    notifyListeners();
  }

  /// 打开通知页后全部标记为已读
  Future<void> markAllRead() async {
    if (unreadCount == 0) return;
    _activities = [for (final a in _activities) a.copyWith(read: true)];
    await _persist();
    notifyListeners();
  }

  /// 清空全部通知（开发者调试用）
  Future<void> clearAll() async {
    if (_activities.isEmpty) return;
    _activities = [];
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_activities.map((a) => a.toJson()).toList()),
    );
  }
}
