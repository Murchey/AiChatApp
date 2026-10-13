import 'dart:convert';
import 'dart:io';
import 'package:ai_chat/providers/backend_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../support/backend_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final endpoint = Platform.environment['AICHAT_TEST_BACKEND'] ?? '';
  test('live server account register, restore, logout, login and refresh',
      () async {
    expect(
        {'127.0.0.1', 'localhost', '::1'}, contains(Uri.parse(endpoint).host));
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'local_chat': 'keep'});
    final store = MemoryTokenStore();
    final backend = BackendProvider(tokenStore: store);
    final client = http.Client();
    final username = 'live_${DateTime.now().microsecondsSinceEpoch}';
    const password = 'local-test-password';
    Future<http.Response> me(String token) =>
        client.get(Uri.parse(endpoint).resolve('/api/auth/me'),
            headers: {'Authorization': 'Bearer $token'});
    try {
      await backend.configureEndpoint(baseUrl: endpoint);
      await backend.authenticateAccount(username, password, register: true);
      expect(backend.isAccountLoggedIn, true);
      final firstDevice = backend.config.deviceId;
      final userId = backend.config.accountUserId;
      final firstToken = backend.config.accessToken;
      final identity = await me(firstToken);
      expect(identity.statusCode, 200);
      expect(jsonDecode(identity.body)['data']['userId'], userId);
      final restored = BackendProvider(tokenStore: store);
      await restored.init();
      expect(restored.isAccountLoggedIn, true);
      expect(restored.config.accountUserId, userId);
      restored.dispose();
      await backend.revokeDevice();
      expect((await me(firstToken)).statusCode, 401);
      expect(backend.isAuthenticated, false);
      await backend.authenticateAccount(username.toUpperCase(), password);
      expect(backend.config.deviceId, isNot(firstDevice));
      expect(backend.config.accountUserId, userId);
      final refreshToken = backend.config.refreshToken;
      final refreshed = await backend.refreshAccessToken();
      expect(refreshed, isNotEmpty);
      expect(backend.config.refreshToken, isNot(refreshToken));
      expect((await me(refreshed!)).statusCode, 200);
      await backend.revokeDevice();
      expect((await me(refreshed)).statusCode, 401);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_chat'), 'keep');
      expect(prefs.getString(BackendProvider.configKey),
          isNot(contains(password)));
      expect(backend.config.accountUsername, username);
    } finally {
      client.close();
      backend.dispose();
    }
  },
      skip: endpoint.isEmpty
          ? 'Set AICHAT_TEST_BACKEND to a disposable local JAR'
          : false);
}
