import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/memory_point.dart';

/// 角色的持久化记忆点管理：每个角色独立一组记忆点，按角色 id 分 key 持久化。
///
/// 记忆点在生成系统提示词时由调用方取出并拼接（见 ChatProvider），
/// 长按聊天气泡进入多选可批量添加，会话详情「提示词设置」下方可管理。
class MemoryPointProvider extends ChangeNotifier {
  static const _prefix = 'memory_points_v1_';

  final Map<String, List<MemoryPoint>> _pointsByCharacter = {};
  bool _loaded = false;

  /// 某个角色的全部记忆点（按创建时间倒序，最新的在前）
  List<MemoryPoint> pointsFor(String characterId) =>
      List.unmodifiable(_pointsByCharacter[characterId] ?? const []);

  /// 全部已启用记忆点的角色 id
  Iterable<String> get characterIds => _pointsByCharacter.keys;

  bool get loaded => _loaded;

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys()
        .where((k) => k.startsWith(_prefix))
        .toList();
    for (final key in keys) {
      final characterId = key.substring(_prefix.length);
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => MemoryPoint.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) _pointsByCharacter[characterId] = list;
      } catch (e) {
        debugPrint('[MemoryPoint] 解析失败 $characterId: $e');
      }
    }
  }

  /// 为角色添加一条记忆点（批量去重：内容相同的只保留一条）
  Future<void> addPoints(String characterId, List<String> contents) async {
    final clean = contents
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (clean.isEmpty) return;
    final existing = _pointsByCharacter[characterId] ?? [];
    final seen = existing.map((p) => p.content).toSet();
    final news = clean.where((c) => !seen.contains(c)).toList();
    if (news.isEmpty) return;
    // 新记忆点插到最前（最新优先展示）
    final updated = [
      ...news.map((c) => MemoryPoint(content: c)),
      ...existing,
    ];
    _pointsByCharacter[characterId] = updated;
    await _persist(characterId);
    notifyListeners();
  }

  /// 更新一条记忆点内容（空内容视为删除）
  Future<void> updatePoint(
      String characterId, String pointId, String content) async {
    final list = _pointsByCharacter[characterId];
    if (list == null) return;
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      await removePoint(characterId, pointId);
      return;
    }
    final index = list.indexWhere((p) => p.id == pointId);
    if (index < 0) return;
    list[index] = list[index].copyWith(content: trimmed);
    await _persist(characterId);
    notifyListeners();
  }

  /// 删除一条记忆点
  Future<void> removePoint(String characterId, String pointId) async {
    final list = _pointsByCharacter[characterId];
    if (list == null) return;
    list.removeWhere((p) => p.id == pointId);
    if (list.isEmpty) {
      _pointsByCharacter.remove(characterId);
    }
    await _persist(characterId);
    notifyListeners();
  }

  Future<void> _persist(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _pointsByCharacter[characterId];
    if (list == null || list.isEmpty) {
      await prefs.remove('$_prefix$characterId');
      return;
    }
    await prefs.setString(
      '$_prefix$characterId',
      jsonEncode(list.map((p) => p.toJson()).toList()),
    );
  }
}
