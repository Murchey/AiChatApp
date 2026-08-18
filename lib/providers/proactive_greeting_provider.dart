import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单个角色的「主动问候」配置。
///
/// 当用户一段时间没有与角色聊天时，角色会主动发送问候消息。
/// 触发机制与自动发朋友圈一致：应用启动 / 回到前台时检查是否到期。
class ProactiveGreetingConfig {
  final bool enabled;
  final int idleHours; // 无消息多少小时后触发问候
  final DateTime? nextDueAt; // 下一次检查到期时间（null 表示尚未排期）

  const ProactiveGreetingConfig({
    this.enabled = false,
    this.idleHours = 72, // 默认 3 天
    this.nextDueAt,
  });

  static const Object _unset = Object();

  ProactiveGreetingConfig copyWith({
    bool? enabled,
    int? idleHours,
    Object? nextDueAt = _unset,
  }) {
    return ProactiveGreetingConfig(
      enabled: enabled ?? this.enabled,
      idleHours: idleHours ?? this.idleHours,
      nextDueAt: nextDueAt == _unset ? this.nextDueAt : nextDueAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'idle_hours': idleHours,
        if (nextDueAt != null) 'next_due_at': nextDueAt!.toIso8601String(),
      };

  factory ProactiveGreetingConfig.fromJson(Map<String, dynamic> json) {
    return ProactiveGreetingConfig(
      enabled: json['enabled'] as bool? ?? false,
      idleHours: (json['idle_hours'] as num?)?.toInt() ?? 72,
      nextDueAt: DateTime.tryParse(json['next_due_at'] as String? ?? ''),
    );
  }
}

/// 主动问候配置持久化：以角色 id 为 key 存到 SharedPreferences，
/// 不侵入 [Character] 模型。
class ProactiveGreetingProvider extends ChangeNotifier {
  static const _storageKey = 'proactive_greeting_configs_v1';

  /// 空闲时长档位（小时）：半天 / 1天 / 2天 / 3天 / 5天 / 7天 / 10天
  static const List<int> idleOptions = [12, 24, 48, 72, 120, 168, 240];
  static const List<String> idleLabels = [
    '无消息半天',
    '无消息1天',
    '无消息2天',
    '无消息3天',
    '无消息5天',
    '无消息7天',
    '无消息10天',
  ];

  final Map<String, ProactiveGreetingConfig> _configs = {};

  ProactiveGreetingConfig configFor(String characterId) =>
      _configs[characterId] ?? const ProactiveGreetingConfig();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((id, v) {
        _configs[id] =
            ProactiveGreetingConfig.fromJson(v as Map<String, dynamic>);
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
      nextDueAt: enabled ? cur.nextDueAt : null,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> setIdleHours(String characterId, int hours) async {
    final cur = configFor(characterId);
    _configs[characterId] = cur.copyWith(idleHours: hours);
    notifyListeners();
    await _persist();
  }

  /// 更新下一次检查到期时间（调度器在检查完成后调用）
  Future<void> setNextDueAt(String characterId, DateTime? dueAt) async {
    final cur = configFor(characterId);
    _configs[characterId] = cur.copyWith(nextDueAt: dueAt);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_configs.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }
}