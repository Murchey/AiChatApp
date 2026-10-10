import 'dart:convert';
import 'dart:io';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/services/cos_auth.dart';
import 'package:ai_chat/services/story_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final host in [
    'demo-123.cos.ap-guangzhou.myqcloud.com',
    'demo.oss-cn-hangzhou.aliyuncs.com'
  ]) {
    test('write probe uses actual method in signature: $host', () async {
      final methods = <String>[];
      final config = StorySourceConfig(
          type: StorySourceType.cos,
          baseUrl: 'https://$host',
          storagePath: 'stories/',
          secretId: 'test-id',
          secretKey: 'test-key');
      final client = MockClient((request) async {
        methods.add(request.method);
        final auth = request.headers['Authorization']!;
        DateTime now;
        if (host.contains('myqcloud')) {
          final start =
              RegExp(r'q-sign-time=(\d+);').firstMatch(auth)!.group(1)!;
          now = DateTime.fromMillisecondsSinceEpoch(int.parse(start) * 1000,
              isUtc: true);
        } else {
          // Use the real Date header to validate the complete OSS signature.
          now = HttpDate.parse(request.headers['Date']!);
        }
        final expected = buildCosAuthHeaders(
            method: request.method,
            uri: request.url,
            accessKeyId: 'test-id',
            secretAccessKey: 'test-key',
            now: now,
            contentType: request.headers['Content-Type']);
        expect(auth, expected['Authorization']);
        expect(request.url.path, startsWith('/stories/.aichat-write-test-'));
        if (request.method == 'PUT') {
          expect(jsonDecode(request.body), {'ok': true});
        }
        return http.Response('', 200);
      });
      await http.runWithClient(
          () => StoryService.probeStaticWrite(config), () => client);
      expect(methods, ['PUT', 'DELETE']);
    });
  }
}
