import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/visibility_group.dart';

/// 单个角色的「自动发朋友圈」配置。
class AutoMomentConfig {
  final bool enabled;
  final int periodHours; // 周期（小时）
  final int count; // 周期内发布条数
  final DateTime? nextDueAt; // 下一次到期时间（null 表示尚未排期）
  final String visibility; // 可见范围（互动该角色动态的分组）

  const AutoMomentConfig({
    this.enabled = false,
    this.periodHours = 72,
    this.count = 1,
    this.nextDueAt,
    this.visibility = VisibilityScope.all,
  });

  static const Object _unset = Object();

  AutoMomentConfig copyWith({
    bool? enabled,
    int? periodHours,
    int? count,
    Object? nextDueAt = _unset,
    String? visibility,
  }) {
    return AutoMomentConfig(
      enabled: enabled ?? this.enabled,
      periodHours: periodHours ?? this.periodHours,
      count: count ?? this.count,
      nextDueAt: nextDueAt == _unset ? this.nextDueAt : nextDueAt as DateTime?,
      visibility: visibility ?? this.visibility,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'period_hours': periodHours,
        'count': count,
        'visibility': visibility,
        if (nextDueAt != null) 'next_due_at': nextDueAt!.toIso8601String(),
      };

  factory AutoMomentConfig.fromJson(Map<String, dynamic> json) {
    return AutoMomentConfig(
      enabled: json['enabled'] as bool? ?? false,
      periodHours: (json['period_hours'] as num?)?.toInt() ?? 72,
      count: (json['count'] as num?)?.toInt() ?? 1,
      visibility: json['visibility'] as String? ?? VisibilityScope.all,
      nextDueAt: DateTime.tryParse(json['next_due_at'] as String? ?? ''),
    );
  }
}

/// 自动发朋友圈配置持久化：以角色 id 为 key 存到 SharedPreferences，
/// 不侵入 [Character] 模型（避免污染角色导入导出的 JSON）。
class AutoMomentProvider extends ChangeNotifier {
  static const _storageKey = 'auto_moment_configs_v1';

  /// 周期档位（小时）：半天 / 1天 / 2天 / 3天 / 1周 / 2周 / 1月
  static const List<int> periodOptions = [12, 24, 48, 72, 168, 336, 720];
  static const List<String> periodLabels = [
    '半天',
    '1天',
    '2天',
    '3天',
    '1周',
    '2周',
    '1月',
  ];

  static const int minCount = 1;
  static const int maxCount = 10;

  final Map<String, AutoMomentConfig> _configs = {};

  AutoMomentConfig configFor(String characterId) =>
      _configs[characterId] ?? const AutoMomentConfig();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((id, v) {
        _configs[id] =
            AutoMomentConfig.fromJson(v as Map<String, dynamic>);
      });
    } catch (_) {
      _configs.clear();
    }
    notifyListeners();
  }

  Future<void> setEnabled(String characterId, bool enabled) async {
    final cur = configFor(characterId);
    _configs[characterId] = cur.copyWith(
      enabled: enabled,
      // 关闭时清空排期；开启时保持原排期（首次开启通常为 null，由调度器初始化）
      nextDueAt: enabled ? cur.nextDueAt : null,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> setPeriod(String characterId, int hours) async {
    final cur = configFor(characterId);
    _configs[characterId] = cur.copyWith(periodHours: hours);
    notifyListeners();
    await _persist();
  }

  Future<void> setCount(String characterId, int count) async {
    final cur = configFor(characterId);
    _configs[characterId] = cur.copyWith(count: count);
    notifyListeners();
    await _persist();
  }

  /// 设置该角色自动朋友圈的可见范围（哪些角色能点赞评论）
  Future<void> setVisibility(String characterId, String visibility) async {
    final cur = configFor(characterId);
    _configs[characterId] = cur.copyWith(visibility: visibility);
    notifyListeners();
    await _persist();
  }

  /// 更新下一次到期时间（调度器在排期/发布完成后调用）
  Future<void> setNextDueAt(String characterId, DateTime? dueAt) async {
    final cur = configFor(characterId);
    _configs[characterId] = cur.copyWith(nextDueAt: dueAt);
    notifyListeners();
    await _persist();
  }

  /// 立即让所有已开启自动发朋友圈的角色到期（开发者快速测试用）。
  /// 正常使用时不调用，避免破坏「首条等满一个子间隔」的排期节奏。
  Future<void> expediteAllDue() async {
    final now = DateTime.now();
    var changed = false;
    _configs.forEach((id, config) {
      if (config.enabled) {
        _configs[id] = config.copyWith(nextDueAt: now);
        changed = true;
      }
    });
    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_configs.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }
}
