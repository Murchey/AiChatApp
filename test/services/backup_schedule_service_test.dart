import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/backup_schedule_service.dart';

void main() {
  group('BackupScheduleConfig', () {
    test('defaults to disabled with delete previous on', () {
      const config = BackupScheduleConfig();
      expect(config.enabled, isFalse);
      expect(config.deletePrevious, isTrue);
      expect(config.encryptEnabled, isFalse);
    });

    test('round trips json including password and deletePrevious', () {
      const config = BackupScheduleConfig(
        mode: BackupScheduleMode.weekly,
        weeklyDay: 3,
        monthlyDay: 15,
        deletePrevious: false,
        password: 'secret',
      );
      final decoded = BackupScheduleConfig.fromJson(config.toJson());
      expect(decoded.mode, BackupScheduleMode.weekly);
      expect(decoded.weeklyDay, 3);
      expect(decoded.monthlyDay, 15);
      expect(decoded.deletePrevious, isFalse);
      expect(decoded.password, 'secret');
      expect(decoded.encryptEnabled, isTrue);
    });
  });

  group('BackupScheduleService.isDue', () {
    final now = DateTime(2026, 3, 18, 10); // Wednesday

    test('disabled is never due', () {
      expect(
        BackupScheduleService.isDue(
          config: const BackupScheduleConfig(
            mode: BackupScheduleMode.disabled,
          ),
          lastRun: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('onAppOpen is always due', () {
      expect(
        BackupScheduleService.isDue(
          config: const BackupScheduleConfig(
            mode: BackupScheduleMode.onAppOpen,
          ),
          lastRun: now,
          now: now,
        ),
        isTrue,
      );
    });

    test('daily due only on a new calendar day', () {
      const config = BackupScheduleConfig(mode: BackupScheduleMode.daily);
      expect(
        BackupScheduleService.isDue(
          config: config,
          lastRun: DateTime(2026, 3, 18, 8),
          now: now,
        ),
        isFalse,
      );
      expect(
        BackupScheduleService.isDue(
          config: config,
          lastRun: DateTime(2026, 3, 17, 23),
          now: now,
        ),
        isTrue,
      );
    });

    test('weekly due after this week target day', () {
      // 每周一；now 是周三 3/18
      const config = BackupScheduleConfig(
        mode: BackupScheduleMode.weekly,
        weeklyDay: 1,
      );
      // 上次是本周一之后 → 不到期
      expect(
        BackupScheduleService.isDue(
          config: config,
          lastRun: DateTime(2026, 3, 16, 9),
          now: now,
        ),
        isFalse,
      );
      // 上次是上周 → 到期
      expect(
        BackupScheduleService.isDue(
          config: config,
          lastRun: DateTime(2026, 3, 9, 9),
          now: now,
        ),
        isTrue,
      );
    });

    test('monthly due after this month target day', () {
      // 每月 15 日；now 是 3/18
      const config = BackupScheduleConfig(
        mode: BackupScheduleMode.monthly,
        monthlyDay: 15,
      );
      expect(
        BackupScheduleService.isDue(
          config: config,
          lastRun: DateTime(2026, 3, 15, 1),
          now: now,
        ),
        isFalse,
      );
      expect(
        BackupScheduleService.isDue(
          config: config,
          lastRun: DateTime(2026, 2, 20, 1),
          now: now,
        ),
        isTrue,
      );
      // 本月 10 日（尚未到 15）且上次备份在 3/1 → 不到期
      expect(
        BackupScheduleService.isDue(
          config: config,
          lastRun: DateTime(2026, 3, 1, 1),
          now: DateTime(2026, 3, 10, 10),
        ),
        isFalse,
      );
    });
  });

  group('auto file prefix', () {
    test('auto prefix differs from manual backup naming', () {
      expect(BackupScheduleService.autoFilePrefix, 'aichat_auto');
      expect(BackupScheduleService.autoFilePrefix, isNot('aichat_backup'));
    });
  });
}
