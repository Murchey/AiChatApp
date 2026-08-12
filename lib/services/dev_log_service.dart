import 'package:flutter/foundation.dart';

/// 开发者日志（单例 ChangeNotifier）。
///
/// 开发者模式开启后，「我」页底部文本框实时展示这里的日志：
/// 朋友圈 AI 互动日志、软件通知、错误信息等。
/// 日志有上限（[maxLines]），超出自动丢弃最旧的。
class DevLogService extends ChangeNotifier {
  DevLogService._();

  static final DevLogService instance = DevLogService._();

  static const int maxLines = 300;

  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  /// 追加一行日志（带时间戳）
  void log(String message) {
    final line = '[${_now()}] $message';
    _lines.add(line);
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    debugPrint('[DevLog] $line');
    notifyListeners();
  }

  /// 清空日志（「我」页文本框右上角清空按钮）
  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    notifyListeners();
  }

  String _now() {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
