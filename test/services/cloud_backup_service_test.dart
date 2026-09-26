import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/cloud_backup_service.dart';
import 'package:ai_chat/services/cos_auth.dart';

void main() {
  group('CloudBackupConfig', () {
    test('parses tencent COS bucket host', () {
      const config = CloudBackupConfig(
        secretId: 'id',
        secretKey: 'key',
        bucketUrl: 'https://demo-1250000000.cos.ap-guangzhou.myqcloud.com/',
        prefix: 'backups/v1',
      );
      expect(config.isConfigured, isTrue);
      expect(config.host, 'demo-1250000000.cos.ap-guangzhou.myqcloud.com');
      expect(config.vendor, CosVendor.tencent);
      expect(config.bucketLabel, 'demo-1250000000');
      expect(config.normalizedPrefix, 'backups/v1');
    });

    test('parses aliyun OSS bucket host and vendor', () {
      const config = CloudBackupConfig(
        secretId: 'id',
        secretKey: 'key',
        bucketUrl: 'https://my-bucket.oss-cn-hangzhou.aliyuncs.com',
      );
      expect(config.isConfigured, isTrue);
      expect(config.vendor, CosVendor.aliyun);
      expect(config.vendorLabel, '阿里云 OSS');
      expect(config.normalizedPrefix, 'backups/v1');
    });

    test('normalizeBucketUrl adds https and strips trailing slash', () {
      expect(
        CloudBackupService.normalizeBucketUrl('demo.cos.ap-guangzhou.myqcloud.com/'),
        'https://demo.cos.ap-guangzhou.myqcloud.com',
      );
      expect(
        CloudBackupService.normalizeBucketUrl('http://bucket.oss-cn-hangzhou.aliyuncs.com//'),
        'http://bucket.oss-cn-hangzhou.aliyuncs.com',
      );
    });

    test('objectKey joins prefix and file name', () {
      const config = CloudBackupConfig(
        secretId: 'id',
        secretKey: 'key',
        bucketUrl: 'https://demo-1.cos.ap-guangzhou.myqcloud.com',
        prefix: '/backups/v1/',
      );
      expect(
        CloudBackupService.objectKey(config, 'a.zip'),
        'backups/v1/a.zip',
      );
    });

    test('incomplete config is not configured', () {
      expect(const CloudBackupConfig().isConfigured, isFalse);
      expect(
        const CloudBackupConfig(secretId: 'a', secretKey: 'b').isConfigured,
        isFalse,
      );
    });
  });

  group('cos_auth Content-Type signing', () {
    test('tencent auth includes Authorization only', () {
      final uri = Uri.parse(
        'https://demo-1250000000.cos.ap-guangzhou.myqcloud.com/backups/v1/a.zip',
      );
      final headers = buildCosAuthHeaders(
        method: 'PUT',
        uri: uri,
        accessKeyId: 'AKIDxxx',
        secretAccessKey: 'yyy',
        contentType: 'application/octet-stream',
      );
      expect(headers.containsKey('Authorization'), isTrue);
      expect(headers.containsKey('Date'), isFalse);
      expect(headers['Authorization'], contains('q-sign-algorithm=sha1'));
    });

    test('aliyun auth signs Date and Authorization', () {
      final uri = Uri.parse(
        'https://my-bucket.oss-cn-hangzhou.aliyuncs.com/backups/v1/a.zip',
      );
      final headers = buildCosAuthHeaders(
        method: 'PUT',
        uri: uri,
        accessKeyId: 'LTAIxxx',
        secretAccessKey: 'zzz',
        contentType: 'application/octet-stream',
      );
      expect(headers.containsKey('Date'), isTrue);
      expect(headers['Authorization'], startsWith('OSS LTAIxxx:'));
    });
  });
}
