import 'dart:convert';
import 'package:ai_chat/models/story_index.dart';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/providers/story_provider.dart';
import 'package:ai_chat/services/backend_http_client.dart';
import 'package:ai_chat/services/story_editing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> row(String id) => {
      'storyId': id,
      'title': id,
      'tags': ['romance'],
      'file': 'assets/$id.json',
    };
Map<String, dynamic> detail(String id) =>
    {...row(id), 'introduction': 'Text', 'memories': []};
const config = StorySourceConfig(
    type: StorySourceType.cos,
    baseUrl: 'https://example.com',
    storagePath: 'stories/');
final refs = [
  {'file': 'index.json', 'title': 'Latest'},
  {'file': 'index-2.json', 'title': 'Archive'},
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'directory validates root, filenames and duplicates; legacy remains intact',
      () {
    expect(StoryIndexReference.parse({'stories': []}, 'index.json').single.file,
        'index.json');
    for (final files in [
      ['index-2.json'],
      ['index.json', '../index-2.json'],
      ['index.json', 'index.json'],
      ['index.json', 'https://other.test/index.json'],
    ]) {
      expect(
          () => StoryIndexReference.parse({
                'indexes': [
                  for (final f in files) {'file': f}
                ]
              }, 'index.json'),
          throwsFormatException);
    }
    expect(
        parseStaticStories({'stories': List.generate(101, (i) => row('$i'))}),
        hasLength(101));
  });

  test(
      'static search is local; append, retry, selection, refresh and restart are page-aware',
      () async {
    final calls = <String>[];
    var fail = true;
    final client = MockClient((request) async {
      calls.add(request.url.path);
      if (request.url.path.endsWith('index-2.json')) {
        if (fail) return http.Response('failed', 500);
        return http.Response(
            jsonEncode({
              'stories': [row('second')]
            }),
            200);
      }
      return http.Response(
          jsonEncode({
            'indexes': refs,
            'stories': [row('first')]
          }),
          200);
    });
    final provider =
        StoryProvider(staticClient: BackendHttpClient(client: client));
    await provider.saveConfig(config);
    await provider.loadCatalog();
    expect(calls, ['/stories/index.json']);
    final originalRows = provider.unfilteredEntries;
    final firstRow = originalRows.single;
    expect(identical(provider.entries, provider.entries), isTrue);
    await provider.loadCatalog(query: 'second');
    expect(identical(provider.unfilteredEntries, originalRows), isTrue);
    expect(identical(provider.unfilteredEntries.single, firstRow), isTrue);
    expect(calls, hasLength(1));
    expect(provider.entries, isEmpty);
    expect(provider.hasMore, isTrue);
    await provider.loadMoreCatalog(query: 'second');
    expect(provider.error, isNotNull);
    expect(provider.unfilteredEntries.single.storyId, 'first');
    fail = false;
    await provider.retryCatalog(query: 'second');
    expect(provider.entries.single.storyId, 'second');
    expect(provider.hasMore, isFalse);
    final count = calls.length;
    provider.restoreCachedCatalog();
    expect(provider.entries, hasLength(2));
    expect(calls, hasLength(count));
    await provider.selectIndex('index-2.json');
    expect(provider.entries.single.storyId, 'second');
    expect(calls, hasLength(count));
    await provider.loadCatalog(force: true);
    expect(calls.skip(count), ['/stories/index.json', '/stories/index-2.json']);
    provider.dispose();
    final restored =
        StoryProvider(staticClient: BackendHttpClient(client: client));
    await restored.init();
    await restored.loadCatalog();
    expect(restored.entries.single.storyId, 'first');
    expect(calls, hasLength(count + 2));
    restored.dispose();
  });

  test(
      'each search load-more downloads exactly one next index without prefetch',
      () async {
    final calls = <String>[];
    final provider = StoryProvider(
        staticClient: BackendHttpClient(client: MockClient((request) async {
      calls.add(request.url.path);
      final root = request.url.path.endsWith('/index.json');
      final second = request.url.path.endsWith('/index-2.json');
      return http.Response(
          jsonEncode({
            if (root)
              'indexes': [
                {'file': 'index.json'},
                {'file': 'index-2.json'},
                {'file': 'index-3.json'},
              ],
            'stories': [
              row(root
                  ? 'first'
                  : second
                      ? 'unmatched'
                      : 'target')
            ],
          }),
          200);
    })));
    addTearDown(provider.dispose);
    await provider.saveConfig(config);
    await provider.loadCatalog();
    await provider.loadCatalog(query: 'target');
    expect(calls, ['/stories/index.json']);
    await provider.loadMoreCatalog(query: 'target');
    expect(calls, ['/stories/index.json', '/stories/index-2.json']);
    expect(provider.entries, isEmpty);
    expect(provider.hasMore, isTrue);
    await provider.loadCatalog(query: 'first');
    expect(calls, hasLength(2));
    await provider.loadCatalog(query: 'target');
    await provider.loadMoreCatalog(query: 'target');
    expect(calls, [
      '/stories/index.json',
      '/stories/index-2.json',
      '/stories/index-3.json'
    ]);
    expect(provider.entries.single.storyId, 'target');
    expect(provider.hasMore, isFalse);
    await provider.loadMoreCatalog(query: 'target');
    provider.restoreCachedCatalog();
    expect(provider.entries, hasLength(3));
    expect(calls, hasLength(3));
  });

  test(
      'expired root refreshes on reopen, index cache is bounded by source and bytes',
      () async {
    var calls = 0;
    final provider = StoryProvider(
        staticClient: BackendHttpClient(client: MockClient((request) async {
      calls++;
      return http.Response(
          jsonEncode({
            'stories': [row('first')]
          }),
          200);
    })));
    for (var i = 0; i < 6; i++) {
      await provider.saveConfig(StorySourceConfig(
          type: StorySourceType.cos, baseUrl: 'https://source$i.example.com'));
      await provider.loadCatalog();
    }
    final prefs = await SharedPreferences.getInstance();
    var keys = prefs
        .getKeys()
        .where((v) => v.startsWith('story_catalog_pages_v2_'))
        .toList();
    expect(keys, hasLength(5));
    // Expire every page in the persisted cache without changing its content.
    for (final key in keys) {
      final snapshot = jsonDecode(prefs.getString(key)!) as Map;
      for (final value in (snapshot['pages'] as Map).values) {
        (value as Map)['time'] = 0;
      }
      await prefs.setString(key, jsonEncode(snapshot));
    }
    provider.dispose();
    final restored = StoryProvider(
        staticClient: BackendHttpClient(client: MockClient((request) async {
      calls++;
      return http.Response(
          jsonEncode({
            'stories': [row('updated')]
          }),
          200);
    })));
    await restored.init();
    await restored.loadCatalog();
    expect(calls, 7);
    expect(restored.entries.single.storyId, 'updated');
    restored.dispose();
    keys = prefs
        .getKeys()
        .where((v) => v.startsWith('story_catalog_pages_v2_'))
        .toList();
    expect(
        keys.fold<int>(
            0, (sum, k) => sum + utf8.encode(prefs.getString(k)!).length),
        lessThanOrEqualTo(5 * 1024 * 1024));
  });

  for (final type in [StorySourceType.github, StorySourceType.gitee]) {
    test('$type paged index uses repository-relative API fallback', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.contains('/contents/')) {
          final second = request.url.path.endsWith('index-2.json');
          return http.Response(
              jsonEncode({
                'content': base64Encode(utf8.encode(jsonEncode({
                  if (!second) 'indexes': refs,
                  'stories': [row(second ? 'second' : 'first')],
                })))
              }),
              200);
        }
        return http.Response('unavailable', 403);
      });
      await http.runWithClient(() async {
        final provider = StoryProvider();
        await provider.saveConfig(StorySourceConfig(
            type: type, repository: 'owner/repo', path: 'stories/index.json'));
        await provider.loadCatalog();
        await provider.loadMoreCatalog();
        expect(provider.entries.map((v) => v.storyId), ['first', 'second']);
        expect(paths.any((v) => v.endsWith('/contents/stories/index-2.json')),
            isTrue);
        provider.dispose();
      }, () => client);
    });
  }

  test(
      '101st story cascades through full pages, preserves extensions and writes root last',
      () async {
    final objects = <String, Map<String, dynamic>>{
      '/stories/index.json': {
        'custom': 'keep',
        'indexes': refs,
        'stories': List.generate(100, (i) => row('a$i'))
      },
      '/stories/index-2.json': {
        'custom': 'archive',
        'stories': List.generate(100, (i) => row('b$i'))
      },
    };
    final writes = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(objects[request.url.path]), 200);
      }
      if (request.method == 'PUT') {
        writes.add(request.url.path);
        objects[request.url.path] =
            Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      }
      return http.Response('', 200);
    });
    await http.runWithClient(
        () => const StoryEditingService()
            .publish(config, detail('new'), 'assets/new.json', isNew: true),
        () => client);
    expect(writes.last, '/stories/index.json');
    expect(objects['/stories/index.json']!['custom'], 'keep');
    expect(objects['/stories/index.json']!['stories'], hasLength(100));
    expect(objects['/stories/index.json']!['stories'][0]['storyId'], 'new');
    expect(objects['/stories/index-2.json']!['stories'][0]['storyId'], 'a99');
    expect(
        objects['/stories/index-3.json']!['stories'].single['storyId'], 'b99');
    expect(objects['/stories/index.json']!['indexes'], hasLength(3));
  });

  test(
      'duplicate ID across pages rejects writes; editing ID and deletion target owning page',
      () async {
    final objects = <String, Map<String, dynamic>>{
      '/stories/index.json': {
        'indexes': refs,
        'stories': [row('first')]
      },
      '/stories/index-2.json': {
        'extra': 'keep',
        'stories': [row('second')]
      },
    };
    final writes = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(objects[request.url.path]), 200);
      }
      writes.add('${request.method} ${request.url.path}');
      if (request.method == 'PUT') {
        objects[request.url.path] =
            Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      }
      if (request.method == 'DELETE') objects.remove(request.url.path);
      return http.Response('', 200);
    });
    await http.runWithClient(() async {
      const service = StoryEditingService();
      await expectLater(
          service.publish(config, detail('second'), 'assets/second.json',
              isNew: true),
          throwsFormatException);
      expect(writes, isEmpty);
      await service.publish(config, detail('renamed'), 'assets/renamed.json',
          isNew: false,
          previousEntry: StoryCatalogEntry.fromJson(row('second')));
      expect(objects['/stories/index-2.json']!['stories'].single['storyId'],
          'renamed');
      expect(objects['/stories/index-2.json']!['extra'], 'keep');
      expect(writes, contains('DELETE /stories/assets/second.json'));
      await service.deletePost(
          config, StoryCatalogEntry.fromJson(row('renamed')));
      expect(objects['/stories/index-2.json']!['stories'], isEmpty);
      expect(objects['/stories/index.json']!['stories'].single['storyId'],
          'first');
    }, () => client);
  });

  test('failed root publication restores changed archive and removes new page',
      () async {
    final original = {
      'indexes': refs,
      'stories': List.generate(100, (i) => row('a$i'))
    };
    final archive = {'stories': List.generate(100, (i) => row('b$i'))};
    final objects = <String, Map<String, dynamic>>{
      '/stories/index.json': original,
      '/stories/index-2.json': archive,
    };
    var failRoot = true;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET') {
        return http.Response(jsonEncode(objects[path]), 200);
      }
      if (request.method == 'PUT') {
        if (path.endsWith('index.json') && failRoot) {
          failRoot = false;
          return http.Response('', 403);
        }
        objects[path] =
            Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      }
      if (request.method == 'DELETE') objects.remove(path);
      return http.Response('', 200);
    });
    await http.runWithClient(() async {
      await expectLater(
          const StoryEditingService()
              .publish(config, detail('new'), 'assets/new.json', isNew: true),
          throwsA(isA<StateError>()));
    }, () => client);
    expect(objects['/stories/index.json'], original);
    expect(objects['/stories/index-2.json'], archive);
    expect(objects.containsKey('/stories/index-3.json'), isFalse);
  });
}
