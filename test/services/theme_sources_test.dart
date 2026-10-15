import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_chat/services/workshop_service.dart';
import 'package:ai_chat/services/cos_auth.dart';
import 'package:ai_chat/models/workshop_asset.dart';

void main() {
  for (final host in ['github', 'gitee']) {
    test('$host reads ThemeStore assets without mixing character releases',
        () async {
      final client = MockClient((request) async {
        expect(request.url.host,
            host == 'github' ? 'api.github.com' : 'gitee.com');
        return http.Response(
            jsonEncode([
              {
                'tag_name': kCharacterPackTag,
                'assets': [
                  {
                    'name': 'characters.zip',
                    'browser_download_url': 'https://example.com/characters.zip'
                  }
                ]
              },
              {
                'tag_name': kThemeStoreTag,
                'assets': [
                  {
                    'name': 'theme.zip',
                    if (host == 'github')
                      'browser_download_url': 'https://example.com/theme.zip'
                  }
                ]
              },
            ]),
            200);
      });
      final result = await http.runWithClient(
          () => WorkshopService.listAssets(
              'https://$host.com/demo/themes', kThemeStoreTag),
          () => client);
      expect(result.single.name, 'theme.zip');
      if (host == 'gitee') {
        expect(result.single.downloadUrl,
            'https://gitee.com/demo/themes/releases/download/ThemeStore/theme.zip');
      }
    });
  }
  for (final host in [
    'demo.cos.ap-guangzhou.myqcloud.com',
    'demo.oss-cn-hangzhou.aliyuncs.com'
  ]) {
    for (final basePath in ['', 'workshop/']) {
      test(
          'private object storage Theme/ requests sign ListObjects: $host/$basePath',
          () async {
        WorkshopService.invalidateCosListCache();
        final client = MockClient((request) async {
          expect(request.url.queryParameters['prefix'] ?? '', basePath);
          expect(request.headers.keys.map((v) => v.toLowerCase()),
              contains('authorization'));
          return http.Response(
              '<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>${basePath}Theme/soft.zip</Key><Size>123</Size></Contents><Contents><Key>${basePath}Characters/role.zip</Key><Size>123</Size></Contents><Contents><Key>${basePath}ThemeStore/legacy.zip</Key><Size>123</Size></Contents></ListBucketResult>',
              200);
        });
        final assets = await http.runWithClient(
            () => WorkshopService.listCosAssets(
                'https://$host/$basePath', kThemeStoreTag,
                auth: const CosAuth(
                    enabled: true,
                    accessKeyId: 'test-key',
                    secretAccessKey: 'test-secret'),
                loadAll: true),
            () => client);
        expect(assets.single.name, 'soft.zip');
        expect(assets.single.downloadUrl,
            'https://$host/${basePath}Theme/soft.zip');
        final tags = await http.runWithClient(
            () => WorkshopService.checkCosFolders('https://$host/$basePath',
                auth: const CosAuth(
                    enabled: true,
                    accessKeyId: 'test-key',
                    secretAccessKey: 'test-secret'),
                force: true),
            () => client);
        expect(tags, contains(kThemeStoreTag));
      });
    }
  }
}
