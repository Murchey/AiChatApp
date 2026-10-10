import 'dart:convert';
import 'dart:typed_data';
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

  test(
      'uploads images into shared img directory with flat and legacy relative paths',
      () async {
    final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('', 200);
    });
    await http.runWithClient(() async {
      final flat = await service.uploadImage(config, 'assets/new.json', bytes);
      expect(flat, startsWith('img/'));
      final legacy =
          await service.uploadImage(config, 'assets/old/1.json', bytes);
      expect(legacy, startsWith('../img/'));
    }, () => client);
    expect(requests, hasLength(2));
    for (final request in requests) {
      expect(request.method, 'PUT');
      expect(request.url.path, startsWith('/stories/assets/img/'));
      expect(request.headers['content-type'], 'image/png');
      expect(request.bodyBytes, bytes);
    }
  });

  test(
      'deleting an image updates only published image paths and can retry after deletion',
      () async {
    final entry =
        StoryCatalogEntry.fromJson({...existing, 'file': 'assets/old.json'});
    final requests = <String>[];
    Map? updated;
    final client = MockClient((request) async {
      requests.add(request.method);
      if (request.method == 'GET') {
        return http.Response(
            jsonEncode({
              ...detail('old'),
              'custom': 'keep',
              'images': ['img/a.png', 'img/b.png']
            }),
            200);
      }
      if (request.method == 'DELETE') return http.Response('', 404);
      updated = jsonDecode(request.body) as Map;
      return http.Response('', 200);
    });
    await http.runWithClient(
        () =>
            service.deleteImage(config, entry.file, 'img/a.png', entry: entry),
        () => client);
    expect(requests, ['GET', 'DELETE', 'PUT']);
    expect(updated!['images'], ['img/b.png']);
    expect(updated!['introduction'], 'Post text');
    expect(updated!['custom'], 'keep');
  });

  test(
      'rejects external and non-image-directory deletion before network access',
      () async {
    var requests = 0;
    final client = MockClient((r) async {
      requests++;
      return http.Response('', 200);
    });
    await http.runWithClient(() async {
      for (final image in [
        'https://other.example/a.png',
        '../index.json',
        'img/../../index.json'
      ]) {
        await expectLater(service.deleteImage(config, 'assets/new.json', image),
            throwsFormatException);
      }
    }, () => client);
    expect(requests, 0);
  });

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
    expect(savedIndex!.containsKey('schemaVersion'), isFalse);
    expect((savedIndex!['stories'] as List).last, existing);
    expect((savedIndex!['stories'] as List).first['storyId'], 'new');
    expect(
        (savedIndex!['stories'] as List).first.containsKey('version'), isFalse);
  });

  test(
      'versionless index accepts and caches metadata without inventing a version',
      () async {
    final entry = StoryCatalogEntry.fromJson(
        {'storyId': 'old', 'title': 'Old', 'file': 'assets/old.json'});
    expect(entry.hasVersion, isFalse);
    expect(entry.toJson().containsKey('version'), isFalse);
    final client = MockClient((request) async =>
        http.Response(jsonEncode({...detail('old'), 'version': 2}), 200));
    await http.runWithClient(() async {
      final result = await service.loadDetail(config, entry);
      expect(result['version'], 2);
    }, () => client);
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
