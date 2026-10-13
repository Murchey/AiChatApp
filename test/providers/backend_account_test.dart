import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/providers/backend_provider.dart';
import 'package:ai_chat/services/backend_http_client.dart';
import '../support/backend_test_support.dart';

Map<String, Object> accountTokens() => {
      'data': {
        ...(tokens('account')['data'] as Map<String, Object>),
        'userId': 'user-1',
        'deviceId': 'server-session',
        'username': 'beta_user',
      }
    };
Map<String, Object> accountVersion() => {
      'data': {
        'apiVersion': 'v1',
        'minClientVersion': '1.6.0',
        'features': {'stories': true, 'accountAuth': true}
      }
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'local_chat': 'keep'}));
  test(
      'register uses server session and restores identity without saving password',
      () async {
    final store = MemoryTokenStore();
    final backend = BackendProvider(
        tokenStore: store,
        client: BackendHttpClient(client: MockClient((req) async {
          if (req.url.path.endsWith('health')) {
            return jsonResponse({'status': 'UP'});
          }
          if (req.url.path.endsWith('version')) {
            return jsonResponse(accountVersion());
          }
          if (req.url.path.endsWith('register')) {
            expect(jsonDecode(req.body),
                {'username': 'Beta_User', 'password': 'secret pass'});
            return jsonResponse(accountTokens());
          }
          if (req.url.path.endsWith('revoke')) {
            return jsonResponse({'revoked': true});
          }
          throw StateError('Unexpected route');
        })));
    await backend.configureEndpoint(baseUrl: 'http://server.test');
    await backend.authenticateAccount('Beta_User', 'secret pass',
        register: true);
    expect(backend.isAccountLoggedIn, true);
    expect(backend.config.deviceId, 'server-session');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BackendProvider.configKey),
        isNot(contains('secret pass')));
    expect(store.value, isNot(contains('secret pass')));
    final restored = BackendProvider(tokenStore: store);
    await restored.init();
    expect(restored.isAccountLoggedIn, true);
    expect(restored.config.accountUsername, 'beta_user');
    await backend.revokeDevice();
    expect(backend.isAccountLoggedIn, false);
    expect(backend.config.accountUsername, 'beta_user');
    expect(prefs.getString('local_chat'), 'keep');
    await restored.configureEndpoint(baseUrl: 'http://other.test');
    expect(restored.isAuthenticated, false);
    expect(restored.config.accountUserId, '');
    expect(restored.config.accountUsername, '');
    backend.dispose();
    restored.dispose();
  });
  test(
      'transient refresh failure retains account but unauthorized refresh clears it',
      () async {
    var refreshStatus = 500;
    var networkDown = false;
    final backend = BackendProvider(
        tokenStore: MemoryTokenStore(),
        client: BackendHttpClient(client: MockClient((req) async {
          if (req.url.path.endsWith('health')) {
            return jsonResponse({'status': 'UP'});
          }
          if (req.url.path.endsWith('version')) {
            return jsonResponse(accountVersion());
          }
          if (req.url.path.endsWith('login')) {
            return jsonResponse(accountTokens());
          }
          if (networkDown) throw const SocketException('Network unavailable');
          return jsonResponse({
            'error': {'code': 'REFRESH_ERROR'}
          }, status: refreshStatus);
        })));
    await backend.configureEndpoint(baseUrl: 'http://server.test');
    await backend.authenticateAccount('beta_user', 'password123');
    await expectLater(
        backend.refreshAccessToken(), throwsA(isA<BackendException>()));
    expect(backend.isAccountLoggedIn, true);
    expect(backend.config.refreshToken, 'refresh-account');
    networkDown = true;
    await expectLater(
        backend.refreshAccessToken(), throwsA(isA<SocketException>()));
    expect(backend.isAccountLoggedIn, true);
    expect(backend.config.refreshToken, 'refresh-account');
    networkDown = false;
    refreshStatus = 401;
    await backend.refreshAccessToken();
    expect(backend.isAuthenticated, false);
    expect(backend.config.accountUserId, '');
    backend.dispose();
  });
  test('old server rejects account login without sending a password', () async {
    var accountRequests = 0;
    final backend = BackendProvider(
        tokenStore: MemoryTokenStore(),
        client: BackendHttpClient(client: MockClient((req) async {
          if (req.url.path.endsWith('health')) {
            return jsonResponse({'status': 'UP'});
          }
          if (req.url.path.endsWith('version')) return jsonResponse(version());
          accountRequests++;
          return jsonResponse(accountTokens());
        })));
    await backend.configureEndpoint(baseUrl: 'http://old.test');
    await expectLater(backend.authenticateAccount('beta_user', 'password123'),
        throwsA(isA<BackendException>()));
    expect(accountRequests, 0);
    backend.dispose();
  });
}
