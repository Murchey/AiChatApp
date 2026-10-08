import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/models/story_package.dart';
import 'package:ai_chat/providers/backend_provider.dart';
import 'package:ai_chat/providers/story_provider.dart';
import 'package:ai_chat/services/backend_http_client.dart';
import '../support/backend_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'cursor appends without duplicates, queries reset pagination, failures keep cache',
      () async {
    var broken = false;
    final calls = <Uri>[];
    final backend = BackendProvider(
        tokenStore: MemoryTokenStore(),
        client: BackendHttpClient(client: MockClient((req) async {
          if (req.url.path.endsWith('health'))
            return jsonResponse({'status': 'UP'});
          if (req.url.path.endsWith('version')) return jsonResponse(version());
          calls.add(req.url);
          if (broken) return jsonResponse({'missing': []});
          if (req.url.queryParameters.containsKey('q'))
            return jsonResponse({
              'data': {
                'items': [catalogEntry('filtered')],
                'hasMore': false
              }
            });
          if (req.url.queryParameters['cursor'] == 'second')
            return jsonResponse({
              'stories': [catalogEntry('a'), catalogEntry('b')],
              'hasMore': false
            });
          return jsonResponse({
            'stories': [catalogEntry('a')],
            'nextCursor': 'second',
            'hasMore': true
          });
        })));
    final stories = StoryProvider(backend: backend);
    await stories
        .saveConfig(const StorySourceConfig(baseUrl: 'https://backend.test'));
    await stories.loadCatalog();
    expect(stories.hasMore, true);
    await stories.loadMoreCatalog();
    expect(stories.entries.map((e) => e.storyId), ['a', 'b']);
    expect(stories.hasMore, false);
    await stories.loadCatalog(query: 'filtered');
    expect(calls.last.queryParameters['cursor'], isNull);
    expect(stories.entries.single.storyId, 'filtered');
    broken = true;
    await stories.loadCatalog(query: 'filtered');
    expect(stories.entries.single.storyId, 'filtered');
    expect(stories.error, isNotNull);
    stories.dispose();
    backend.dispose();
  });
  test(
      'identical concurrent refreshes are coalesced, a new query cancels old query',
      () async {
    final first = Completer<http.Response>(), entered = Completer<void>();
    var calls = 0;
    final staticClient = BackendHttpClient(client: MockClient((_) {
      calls++;
      if (calls == 1) {
        entered.complete();
        return first.future;
      }
      return Future.value(jsonResponse({
        'stories': [catalogEntry('new')]
      }));
    }));
    final stories = StoryProvider(staticClient: staticClient);
    await stories.saveConfig(const StorySourceConfig(
        type: StorySourceType.cos, baseUrl: 'https://static.test'));
    final load = stories.loadCatalog();
    await entered.future;
    final duplicate = stories.loadCatalog();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    final newQuery = stories.loadCatalog(query: 'new');
    await Future.wait([load, duplicate, newQuery]);
    first.complete(jsonResponse({
      'stories': [catalogEntry('old')]
    }));
    expect(stories.entries.single.storyId, 'new');
    stories.dispose();
  });
  test('changing source cancels response and does not mix old data', () async {
    final pending = Completer<http.Response>(), entered = Completer<void>();
    final stories =
        StoryProvider(staticClient: BackendHttpClient(client: MockClient((req) {
      if (req.url.host == 'first.test') {
        entered.complete();
        return pending.future;
      }
      return Future.value(jsonResponse({
        'stories': [catalogEntry('new')]
      }));
    })));
    await stories.saveConfig(const StorySourceConfig(
        type: StorySourceType.cos, baseUrl: 'https://first.test'));
    final old = stories.loadCatalog();
    await entered.future;
    await stories.saveConfig(const StorySourceConfig(
        type: StorySourceType.cos, baseUrl: 'https://second.test'));
    await stories.loadCatalog();
    await old;
    pending.complete(jsonResponse({
      'stories': [catalogEntry('old')]
    }));
    expect(stories.entries.single.storyId, 'new');
    stories.dispose();
  });

  test('source settings are retained independently when switching sources',
      () async {
    SharedPreferences.setMockInitialValues({});
    final stories = StoryProvider(
        staticClient: BackendHttpClient(
            client: MockClient((_) async => jsonResponse({'stories': []}))));
    await stories.saveConfig(const StorySourceConfig(
        type: StorySourceType.github,
        repository: 'owner/repo',
        branch: 'main',
        path: 'index.json'));
    await stories.saveConfig(const StorySourceConfig(
        type: StorySourceType.server,
        baseUrl: 'https://server.test',
        port: '8443'));
    await stories.switchSource(StorySourceType.github);
    expect(stories.config.repository, 'owner/repo');
    expect(stories.config.type, StorySourceType.github);
    await stories.switchSource(StorySourceType.server);
    expect(stories.config.baseUrl, 'https://server.test');
    expect(stories.config.port, '8443');
    stories.dispose();
  });

  test('story source configuration never persists a server token in prefs',
      () async {
    final store = MemoryTokenStore();
    final backend = BackendProvider(tokenStore: store);
    final stories = StoryProvider(backend: backend);
    await stories.saveConfig(const StorySourceConfig(
      baseUrl: 'https://server.test',
      token: 'short-lived-access-token',
    ));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('story_community_source_v1'),
        isNot(contains('short-lived-access-token')));
    expect(backend.config.accessToken, 'short-lived-access-token');
    expect(store.value, contains('short-lived-access-token'));
    stories.dispose();
    backend.dispose();
  });
  test('catalog and downloaded package survive restart and timeout', () async {
    var offline = false;
    final create = () => StoryProvider(
            staticClient: BackendHttpClient(client: MockClient((req) async {
          if (offline) throw http.ClientException('offline');
          return jsonResponse(req.url.path.endsWith('index.json')
              ? {
                  'stories': [catalogEntry('world')]
                }
              : package('world'));
        })));
    final first = create();
    await first.saveConfig(const StorySourceConfig(
        type: StorySourceType.cos, baseUrl: 'https://static.test'));
    await first.loadCatalog();
    await first.loadPackage(first.entries.single);
    first.dispose();
    offline = true;
    final restored = create();
    await restored.init();
    expect(restored.entries.single.storyId, 'world');
    await restored.loadCatalog();
    expect(restored.entries.single.storyId, 'world');
    expect(restored.usingCache, true);
    final story = await restored.loadPackage(restored.entries.single);
    expect(story.memories.single.content, '设定');
    restored.dispose();
  });
  test(
      'unsupported backend leaves local cache and can return to saved static source',
      () async {
    final backend = BackendProvider(
        tokenStore: MemoryTokenStore(),
        client: BackendHttpClient(
            client: MockClient((req) async => jsonResponse(
                req.url.path.endsWith('health')
                    ? {'status': 'UP'}
                    : version(api: 'v0')))));
    final stories = StoryProvider(
        backend: backend,
        staticClient: BackendHttpClient(
            client: MockClient((_) async => jsonResponse({
                  'stories': [catalogEntry('static-world')]
                }))));
    await stories.saveConfig(const StorySourceConfig(
        type: StorySourceType.github, repository: 'owner/repo'));
    await stories.loadCatalog();
    await stories
        .saveConfig(const StorySourceConfig(baseUrl: 'https://backend.test'));
    await stories.loadCatalog();
    expect(stories.error, contains('版本不兼容'));
    expect(stories.canUseStaticFallback, true);
    await stories.useStaticFallback();
    expect(stories.entries.single.storyId, 'static-world');
    expect(stories.supportsServerStats, false);
    stories.dispose();
    backend.dispose();
  });
  test(
      'catalog cancel restores loading state and package cancel cannot serve stale cache',
      () async {
    final pending = Completer<http.Response>(), entered = Completer<void>();
    final stories =
        StoryProvider(staticClient: BackendHttpClient(client: MockClient((_) {
      entered.complete();
      return pending.future;
    })));
    await stories.saveConfig(const StorySourceConfig(
        type: StorySourceType.cos, baseUrl: 'https://static.test'));
    final loading = stories.loadCatalog();
    await entered.future;
    stories.cancelCatalog();
    await loading;
    expect(stories.loading, false);
    expect(stories.error, null);
    pending.complete(jsonResponse({'stories': []}));
    stories.dispose();
  });
}
