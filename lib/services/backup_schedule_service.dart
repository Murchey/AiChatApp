import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';
import 'cloud_backup_service.dart';

/// 定时备份触发方式
enum BackupScheduleMode {
  /// 关闭定时备份
  disabled,

  /// 每次打开 APP
  onAppOpen,

  /// 每天（当天首次打开时）
  daily,

  /// 每周指定星期（该日及之后首次打开时）
  weekly,

  /// 每月指定日期（该日及之后首次打开时）
  monthly,
}

extension BackupScheduleModeX on BackupScheduleMode {
  String get displayName => switch (this) {
        BackupScheduleMode.disabled => '关闭',
        BackupScheduleMode.onAppOpen => '打开 APP 时',
        BackupScheduleMode.daily => '每天',
        BackupScheduleMode.weekly => '每周',
        BackupScheduleMode.monthly => '每月',
      };

  String describe({int weeklyDay = 1, int monthlyDay = 1}) => switch (this) {
        BackupScheduleMode.disabled => '关闭',
        BackupScheduleMode.onAppOpen => '打开 APP 时备份',
        BackupScheduleMode.daily => '每天备份',
        BackupScheduleMode.weekly => '每${weekdayName(weeklyDay)}备份',
        BackupScheduleMode.monthly => '每月 $monthlyDay 日备份',
      };
}

String weekdayName(int day) {
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  final i = day.clamp(1, 7) - 1;
  return '周${names[i]}';
}

/// 单侧（本地 / 云端）定时备份配置
class BackupScheduleConfig {
  final BackupScheduleMode mode;

  /// 每周：1=周一 … 7=周日
  final int weeklyDay;

  /// 每月：1–31（超过当月天数时按月末）
  final int monthlyDay;

  /// 自动备份时删除上一份自动备份（不影响手动备份）
  final bool deletePrevious;

  /// 自动备份加密密码；空则不加密
  final String password;

  const BackupScheduleConfig({
    this.mode = BackupScheduleMode.disabled,
    this.weeklyDay = 1,
    this.monthlyDay = 1,
    this.deletePrevious = true,
    this.password = '',
  });

  bool get enabled => mode != BackupScheduleMode.disabled;

  bool get encryptEnabled => password.trim().isNotEmpty;

  /// 当前策略的可读描述
  String describe() =>
      mode.describe(weeklyDay: weeklyDay, monthlyDay: monthlyDay);

  BackupScheduleConfig copyWith({
    BackupScheduleMode? mode,
    int? weeklyDay,
    int? monthlyDay,
    bool? deletePrevious,
    String? password,
  }) {
    return BackupScheduleConfig(
      mode: mode ?? this.mode,
      weeklyDay: (weeklyDay ?? this.weeklyDay).clamp(1, 7),
      monthlyDay: (monthlyDay ?? this.monthlyDay).clamp(1, 31),
      deletePrevious: deletePrevious ?? this.deletePrevious,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'weeklyDay': weeklyDay,
        'monthlyDay': monthlyDay,
        'deletePrevious': deletePrevious,
        'password': password,
      };

  factory BackupScheduleConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BackupScheduleConfig();
    final modeName = json['mode'] as String? ?? 'disabled';
    final mode = BackupScheduleMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => BackupScheduleMode.disabled,
    );
    return BackupScheduleConfig(
      mode: mode,
      weeklyDay: ((json['weeklyDay'] as num?) ?? 1).toInt().clamp(1, 7),
      monthlyDay: ((json['monthlyDay'] as num?) ?? 1).toInt().clamp(1, 31),
      deletePrevious: json['deletePrevious'] as bool? ?? true,
      password: json['password'] as String? ?? '',
    );
  }
}

/// 定时备份调度：本地 / 云端配置分开，按需在 APP 打开时执行。
///
/// 说明：定时触发点为「打开 APP」（含每日 / 每周 / 每月到期后的首次打开），
/// 不依赖后台服务，避免杀进程后静默失败。自动备份不加密。
class BackupScheduleService {
  static const _localKey = 'backup_schedule_local_v1';
  static const _cloudKey = 'backup_schedule_cloud_v1';
  static const _lastLocalKey = 'backup_schedule_last_local_v1';
  static const _lastCloudKey = 'backup_schedule_last_cloud_v1';

  static Future<BackupScheduleConfig> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey);
    return _decode(raw);
  }

  static Future<BackupScheduleConfig> loadCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cloudKey);
    return _decode(raw);
  }

  static BackupScheduleConfig _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const BackupScheduleConfig();
    try {
      return BackupScheduleConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const BackupScheduleConfig();
    }
  }

  static Future<void> saveLocal(BackupScheduleConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localKey, jsonEncode(config.toJson()));
  }

  static Future<void> saveCloud(BackupScheduleConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cloudKey, jsonEncode(config.toJson()));
  }

  static Future<DateTime?> lastLocalRun() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastLocalKey) ?? '');
  }

  static Future<DateTime?> lastCloudRun() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastCloudKey) ?? '');
  }

  static Future<void> _markLocalRun(DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastLocalKey, at.toIso8601String());
  }

  static Future<void> _markCloudRun(DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCloudKey, at.toIso8601String());
  }

  /// 是否到期需要备份。
  ///
  /// [lastRun] 为上次自动备份时间（null=从未）。
  static bool isDue({
    required BackupScheduleConfig config,
    required DateTime? lastRun,
    DateTime? now,
  }) {
    if (!config.enabled) return false;
    final n = now ?? DateTime.now();
    switch (config.mode) {
      case BackupScheduleMode.disabled:
        return false;
      case BackupScheduleMode.onAppOpen:
        return true;
      case BackupScheduleMode.daily:
        if (lastRun == null) return true;
        return !_sameDate(lastRun, n);
      case BackupScheduleMode.weekly:
        if (lastRun == null) return true;
        return _isWeeklyDue(lastRun, n, config.weeklyDay);
      case BackupScheduleMode.monthly:
        if (lastRun == null) return true;
        return _isMonthlyDue(lastRun, n, config.monthlyDay);
    }
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 每周：本周的「目标日 00:00」已到，且上次备份早于该时刻。
  static bool _isWeeklyDue(DateTime lastRun, DateTime now, int weeklyDay) {
    final target = _thisWeekStart(now, weeklyDay);
    return lastRun.isBefore(target);
  }

  /// 每月：本月的「目标日 00:00」已到，且上次备份早于该时刻。
  static bool _isMonthlyDue(DateTime lastRun, DateTime now, int monthlyDay) {
    final target = _thisMonthDay(now, monthlyDay);
    return lastRun.isBefore(target);
  }

  /// 本周（周一为 1）目标星期的 00:00。若今天是目标日之前，返回上周该日。
  static DateTime _thisWeekStart(DateTime now, int weeklyDay) {
    // DateTime.monday=1 … sunday=7
    final today = DateTime(now.year, now.month, now.day);
    final delta = now.weekday - weeklyDay; // 今天相对目标日
    if (delta >= 0) {
      return today.subtract(Duration(days: delta));
    }
    // 目标日在本周后面 → 取上周
    return today.subtract(Duration(days: delta + 7));
  }

  /// 本月目标日 00:00（超过当月天数则取月末）；若今天未到目标日，取上月。
  static DateTime _thisMonthDay(DateTime now, int monthlyDay) {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final day = monthlyDay.clamp(1, daysInMonth);
    final thisTarget = DateTime(now.year, now.month, day);
    final today = DateTime(now.year, now.month, now.day);
    if (!today.isBefore(thisTarget)) return thisTarget;
    // 尚未到本月目标日 → 判定上月
    final prevMonth = DateTime(now.year, now.month - 1, 1);
    final prevDays = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
    final prevDay = monthlyDay.clamp(1, prevDays);
    return DateTime(prevMonth.year, prevMonth.month, prevDay);
  }

  /// 自动备份统一文件名前缀，与手动备份（aichat_backup）区分。
  static const autoFilePrefix = 'aichat_auto';

  /// 执行一次本地自动备份；按配置清理上一份自动备份。
  static Future<String> runLocalAutoBackup(BackupScheduleConfig config) async {
    if (config.deletePrevious) {
      await BackupService.deleteLocalBackupsByPrefix(autoFilePrefix);
    }
    final file = await BackupService.createLocalBackup(
      password: config.encryptEnabled ? config.password.trim() : null,
      fileNamePrefix: autoFilePrefix,
    );
    await _markLocalRun(DateTime.now());
    return '本地自动备份完成：${_baseName(file.path)}';
  }

  /// 执行一次云端自动备份；按配置清理上一份云端自动备份。
  static Future<String> runCloudAutoBackup(
    CloudBackupConfig cloudConfig,
    BackupScheduleConfig config,
  ) async {
    if (config.deletePrevious) {
      await CloudBackupService.deleteBackupsByFileNamePrefix(
        cloudConfig,
        autoFilePrefix,
      );
    }
    final item = await CloudBackupService.uploadBackup(
      cloudConfig,
      password: config.encryptEnabled ? config.password.trim() : null,
      fileNamePrefix: autoFilePrefix,
    );
    await _markCloudRun(DateTime.now());
    return '云端自动备份完成：${item.fileName}';
  }

  /// 打开 APP 时检查并执行到期的本地 / 云端自动备份。
  /// 返回本次实际执行的备份说明（用于 Toast）；无执行返回空列表。
  static Future<List<String>> checkAndRunOnAppOpen() async {
    final results = <String>[];
    final localCfg = await loadLocal();
    final cloudCfg = await loadCloud();

    if (isDue(config: localCfg, lastRun: await lastLocalRun())) {
      try {
        results.add(await runLocalAutoBackup(localCfg));
      } catch (e) {
        debugPrint('[BackupSchedule] local auto backup failed: $e');
        results.add('本地自动备份失败：$e');
      }
    }

    if (isDue(config: cloudCfg, lastRun: await lastCloudRun())) {
      final cloudConfig = await CloudBackupService.loadConfig();
      if (!cloudConfig.isConfigured) {
        results.add('云端定时备份已到期，但未配置对象储存，已跳过');
      } else {
        try {
          results.add(await runCloudAutoBackup(cloudConfig, cloudCfg));
        } catch (e) {
          debugPrint('[BackupSchedule] cloud auto backup failed: $e');
          results.add('云端自动备份失败：$e');
        }
      }
    }
    return results;
  }

  /// 备份页保存配置后立即评估一次（便于用户刚改完就能触发）。
  static Future<List<String>> checkAndRunNow({
    required bool local,
    required bool cloud,
  }) async {
    final results = <String>[];
    if (local) {
      final cfg = await loadLocal();
      if (isDue(config: cfg, lastRun: await lastLocalRun())) {
        try {
          results.add(await runLocalAutoBackup(cfg));
        } catch (e) {
          results.add('本地自动备份失败：$e');
        }
      }
    }
    if (cloud) {
      final cfg = await loadCloud();
      if (isDue(config: cfg, lastRun: await lastCloudRun())) {
        final cloudConfig = await CloudBackupService.loadConfig();
        if (!cloudConfig.isConfigured) {
          results.add('云端定时备份已到期，但未配置对象储存，已跳过');
        } else {
          try {
            results.add(await runCloudAutoBackup(cloudConfig, cfg));
          } catch (e) {
            results.add('云端自动备份失败：$e');
          }
        }
      }
    }
    return results;
  }

  static String _baseName(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i < 0 ? path : path.substring(i + 1);
  }
}
