import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/models/backend_config.dart';
import 'package:ai_chat/providers/backend_provider.dart';
import 'package:ai_chat/services/backend_http_client.dart';
import '../support/backend_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('URL normalization rejects credentials, schemes and invalid ports', () {
    expect(
        const BackendConfig(
                baseUrl: 'host.test//base///', port: '8080', scheme: 'http')
            .endpoint('/api/health')
            .toString(),
        'http://host.test:8080/base/api/health');
    for (final value in [
      'ftp://host.test',
      'https://a:b@host.test',
      'http://host.test?token=x'
    ]) {
      expect(() => BackendConfig(baseUrl: value).endpoint('/api'),
          throwsFormatException);
    }
    expect(
        () => const BackendConfig(baseUrl: 'host.test', port: '70000')
            .endpoint('/api'),
        throwsFormatException);
    expect(
        const BackendConfig(accessToken: 'secret', refreshToken: 'refresh')
            .toJson()
            .containsKey('refresh_token'),
        false);
  });
  test('unconfigured startup never sends a request', () async {
    var calls = 0;
    final backend = BackendProvider(
        tokenStore: MemoryTokenStore(),
        client: BackendHttpClient(client: MockClient((_) async {
          calls++;
          return jsonResponse({});
        })));
    await backend.init();
    await backend.refreshStatus();
    expect(calls, 0);
    expect(backend.status, BackendConnectionStatus.unconfigured);
    backend.dispose();
  });
  test('bind stores secrets securely, restart restores and revoke clears',
      () async {
    final store = MemoryTokenStore();
    final backend = BackendProvider(
        tokenStore: store,
        client: BackendHttpClient(client: MockClient((req) async {
          if (req.url.path.endsWith('exchange'))
            return jsonResponse(tokens('first'));
          if (req.url.path.endsWith('revoke'))
            return jsonResponse({
              'data': {'revoked': true}
            });
          throw StateError('unexpected request');
        })));
    await backend.configureEndpoint(baseUrl: 'https://backend.test');
    await backend.bindInvite('invite');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BackendProvider.configKey),
        isNot(contains('access-first')));
    expect(store.value, contains('refresh-first'));
    final restored = BackendProvider(tokenStore: store);
    await restored.init();
    expect(restored.config.refreshToken, 'refresh-first');
    await backend.revokeDevice();
    expect(backend.isAuthenticated, false);
    expect(store.value, null);
    restored.dispose();
    backend.dispose();
  });
  test('secure storage failure discards refresh and does not persist access',
      () async {
    final store = MemoryTokenStore()..unavailable = true;
    final backend = BackendProvider(
        tokenStore: store,
        client: BackendHttpClient(
            client: MockClient((_) async => jsonResponse(tokens('one')))));
    await backend.configureEndpoint(baseUrl: 'https://backend.test');
    await backend.bindInvite('invite');
    expect(backend.config.refreshToken, '');
    expect(backend.isAuthenticated, true);
    expect(backend.storageNotice, isNotNull);
    expect(
        (await SharedPreferences.getInstance())
            .getString(BackendProvider.configKey),
        isNot(contains('access-one')));
    backend.dispose();
  });
  test('parallel 401s share one refresh and failed refresh clears session',
      () async {
    var refreshes = 0;
    var fail = false;
    final backend = BackendProvider(
        tokenStore: MemoryTokenStore(),
        client: BackendHttpClient(client: MockClient((req) async {
          if (req.url.path.endsWith('exchange'))
            return jsonResponse(tokens('one'));
          if (req.url.path.endsWith('health'))
            return jsonResponse({
              'data': {'status': 'UP'}
            });
          if (req.url.path.endsWith('version')) return jsonResponse(version());
          if (req.url.path.endsWith('refresh')) {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return fail
                ? jsonResponse({
                    'error': {'code': 'INVALID_REFRESH_TOKEN'}
                  }, status: 401)
                : jsonResponse(tokens('two'));
          }
          if (req.headers['Authorization'] != 'Bearer access-two' || fail)
            return jsonResponse({
              'error': {'code': 'TOKEN_EXPIRED'}
            }, status: 401);
          return jsonResponse({'stories': []});
        })));
    await backend.configureEndpoint(baseUrl: 'https://backend.test');
    await backend.bindInvite('invite');
    await Future.wait([backend.loadStories(), backend.loadStories()]);
    expect(refreshes, 1);
    fail = true;
    await expectLater(backend.loadStories(), throwsA(isA<BackendException>()));
    expect(backend.config.accessToken, '');
    expect(backend.config.refreshToken, '');
    expect(backend.status, BackendConnectionStatus.unauthorized);
    backend.dispose();
  });
  test(
      'old API, missing fields, minimum client and disabled stories are rejected',
      () async {
    for (final capabilities in [
      version(api: 'v2'),
      {'data': {}},
      version(minimum: '9.0.0'),
      version(stories: false)
    ]) {
      final backend = BackendProvider(
          tokenStore: MemoryTokenStore(),
          client: BackendHttpClient(
              client: MockClient((req) async => jsonResponse(
                  req.url.path.endsWith('health')
                      ? {'status': 'UP'}
                      : capabilities))));
      await backend.configureEndpoint(baseUrl: 'https://backend.test');
      await expectLater(
          backend.loadStories(), throwsA(isA<BackendException>()));
      backend.dispose();
    }
  });
  test('source change while binding never restores old credentials', () async {
    final reply = Completer<dynamic>();
    final entered = Completer<void>();
    final backend = BackendProvider(
        tokenStore: MemoryTokenStore(),
        client: BackendHttpClient(client: MockClient((_) async {
          entered.complete();
          return jsonResponse(await reply.future);
        })));
    await backend.configureEndpoint(baseUrl: 'https://first.test');
    final binding = backend.bindInvite('invite');
    final rejected = expectLater(binding, throwsA(isA<RequestCancelled>()));
    await entered.future;
    await backend.configureEndpoint(baseUrl: 'https://second.test');
    await rejected;
    reply.complete(tokens('old'));
    expect(backend.config.baseUrl, 'https://second.test');
    expect(backend.isAuthenticated, false);
    backend.dispose();
  });
  test('429 cooldown prevents retry loop', () async {
    var catalogs = 0;
    final backend = BackendProvider(
        tokenStore: MemoryTokenStore(),
        client: BackendHttpClient(client: MockClient((req) async {
          if (req.url.path.endsWith('health'))
            return jsonResponse({'status': 'UP'});
          if (req.url.path.endsWith('version')) return jsonResponse(version());
          catalogs++;
          return jsonResponse({
            'error': {'code': 'RATE_LIMITED', 'retryAfterSeconds': 60}
          }, status: 429);
        })));
    await backend.configureEndpoint(baseUrl: 'https://backend.test');
    for (var i = 0; i < 2; i++) {
      await expectLater(
          backend.loadStories(), throwsA(isA<BackendException>()));
    }
    expect(catalogs, 1);
    backend.dispose();
  });
}
