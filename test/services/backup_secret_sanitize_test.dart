import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/backup_service.dart';

void main() {
  group('BackupService secret sanitization', () {
    test('top-level secret keys are excluded from export', () {
      expect(BackupService.sanitizePrefForExport('api_key', 'sk-123'), isNull);
      expect(
        BackupService.sanitizePrefForExport('cloud_backup_secret_id', 'AKID'),
        isNull,
      );
      expect(
        BackupService.sanitizePrefForExport('cloud_backup_secret_key', 'key'),
        isNull,
      );
    });

    test('settings keys are kept as-is', () {
      expect(
        BackupService.sanitizePrefForExport('theme_mode', 'dark'),
        'dark',
      );
      expect(
        BackupService.sanitizePrefForExport('bubble_font_size', 16),
        16,
      );
    });

    test('api_models json secrets are blanked but settings kept', () {
      final raw = jsonEncode([
        {
          'id': 'm1',
          'display_name': 'DeepSeek',
          'model_name': 'deepseek-v4-flash',
          'base_url': 'https://api.deepseek.com',
          'api_key': 'sk-secret',
          'context_length': 8000,
        },
      ]);
      final out = BackupService.sanitizePrefForExport('api_models_v1', raw);
      expect(out, isA<String>());
      final decoded = jsonDecode(out as String) as List<dynamic>;
      final model = decoded.first as Map<String, dynamic>;
      expect(model['api_key'], '');
      expect(model['model_name'], 'deepseek-v4-flash');
      expect(model['base_url'], 'https://api.deepseek.com');
    });

    test('workshop cosAuth secrets are blanked', () {
      final raw = jsonEncode([
        {
          'id': 'r1',
          'name': 'repo',
          'url': 'https://bucket.oss-cn-hangzhou.aliyuncs.com',
          'cosAuth': {
            'enabled': true,
            'accessKeyId': 'LTAI',
            'secretAccessKey': 'secret',
          },
        },
      ]);
      final out =
          BackupService.sanitizePrefForExport('workshop_repositories_v1', raw);
      final decoded = jsonDecode(out as String) as List<dynamic>;
      final repo = decoded.first as Map<String, dynamic>;
      final auth = repo['cosAuth'] as Map<String, dynamic>;
      expect(auth['accessKeyId'], '');
      expect(auth['secretAccessKey'], '');
      expect(auth['enabled'], true);
    });

    test('schedule password is blanked', () {
      final raw = jsonEncode({
        'mode': 'daily',
        'weeklyDay': 1,
        'monthlyDay': 1,
        'deletePrevious': true,
        'password': 'auto-pass',
      });
      final out =
          BackupService.sanitizePrefForExport('backup_schedule_local_v1', raw);
      final decoded = jsonDecode(out as String) as Map<String, dynamic>;
      expect(decoded['password'], '');
      expect(decoded['mode'], 'daily');
    });

    test('extract and fill secret fields roundtrip', () {
      final raw = jsonEncode([
        {
          'id': 'm1',
          'api_key': 'sk-abc',
          'nested': {'secretKey': 'xyz'},
        },
      ]);
      final secrets = BackupService.extractSecretFields(raw);
      expect(secrets.values, contains('sk-abc'));
      expect(secrets.values, contains('xyz'));

      final blanked = BackupService.sanitizeSecrets(jsonDecode(raw));
      final filled = BackupService.fillSecretFields(blanked, '', secrets);
      final list = filled as List<dynamic>;
      final m = list.first as Map<String, dynamic>;
      expect(m['api_key'], 'sk-abc');
      expect((m['nested'] as Map)['secretKey'], 'xyz');
    });

    test('non-json strings pass through', () {
      expect(
        BackupService.sanitizePrefForExport('user_nickname', '小明'),
        '小明',
      );
    });
  });
}
