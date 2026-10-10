import 'dart:convert';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/services/story_editing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const service = StoryEditingService();
  const config = StorySourceConfig(
      type: StorySourceType.cos,
      baseUrl: 'https://test.cos.ap-guangzhou.myqcloud.com',
      storagePath: 'stories/');
  final existing = {
    'storyId': 'old',
    'version': 1,
    'title': 'Old',
    'file': 'assets/old/1.json',
    'downloadCount': 20
  };
  Map<String, dynamic> detail(String id) => {
        'storyId': id,
        'title': 'New title',
        'version': 1,
        'introduction': 'Post text',
        'tags': ['romance'],
        'memories': ['Fact']
      };

  test('new post uploads detail first and preserves all existing catalog data',
      () async {
    final writes = <String>[];
    Map? savedIndex;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
            jsonEncode({
              'schemaVersion': 2,
              'custom': 'keep',
              'stories': [existing]
            }),
            200);
      }
      writes.add(request.url.path);
      if (request.url.path.endsWith('index.json')) {
        savedIndex = jsonDecode(request.body) as Map;
      }
      return http.Response('', 200);
    });
    await http.runWithClient(
        () => service.publish(config, detail('new'), 'assets/new/1.json',
            isNew: true),
        () => client);
    expect(writes, ['/stories/assets/new/1.json', '/stories/index.json']);
    expect(savedIndex!['custom'], 'keep');
    expect((savedIndex!['stories'] as List).last, existing);
    expect((savedIndex!['stories'] as List).first['storyId'], 'new');
  });

  test('duplicate ID is rejected before writing any object', () async {
    var writes = 0;
    final client = MockClient((request) async {
      if (request.method != 'GET') writes++;
      return http.Response(
          jsonEncode({
            'stories': [existing]
          }),
          200);
    });
    await http.runWithClient(() async {
      await expectLater(
          service.publish(config, detail('old'), 'assets/old/1.json',
              isNew: true),
          throwsFormatException);
    }, () => client);
    expect(writes, 0);
  });

  test('editing keeps catalog extensions and reports a failed index update',
      () async {
    Map? updated;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
            jsonEncode({
              'stories': [existing]
            }),
            200);
      }
      if (request.url.path.endsWith('index.json')) {
        updated = jsonDecode(request.body) as Map;
        return http.Response('', 403);
      }
      return http.Response('', 200);
    });
    await http.runWithClient(() async {
      await expectLater(
          service.publish(config, detail('old'), 'assets/old/1.json',
              isNew: false),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('索引更新失败'))));
    }, () => client);
    expect(updated!['stories'][0]['downloadCount'], 20);
    expect(updated!['stories'][0]['title'], 'New title');
  });
}
