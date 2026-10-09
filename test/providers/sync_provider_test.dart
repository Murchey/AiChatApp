import 'dart:convert';
import 'package:ai_chat/data/db/app_database.dart';
import 'package:ai_chat/providers/backend_provider.dart';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/providers/sync_provider.dart';
import 'package:ai_chat/services/backend_http_client.dart';
import 'package:ai_chat/services/sync_crypto.dart';
import 'package:ai_chat/services/sync_outbox_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/backend_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'opt-in pilot persists encrypted changes offline and retries stable writes',
      () async {
    var offline = false;
    var revision = 0;
    final keys = <String>[];
    Map<String, dynamic>? uploaded;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final outbox = SyncOutboxStore(db);
    final keyStore = MemoryTokenStore();
    final backend = BackendProvider(
        tokenStore: MemoryTokenStore(),
        client: BackendHttpClient(client: MockClient((req) async {
          if (req.url.path.endsWith('/health')) {
            return jsonResponse({
              'data': {'status': 'UP'}
            });
          }
          if (req.url.path.endsWith('/version')) {
            return jsonResponse({
              'data': {
                'apiVersion': 'v1',
                'serverVersion': 'test',
                'minClientVersion': '1.0.0',
                'features': {'stories': true, 'sync': true}
              }
            });
          }
          if (req.url.path.endsWith('/exchange')) {
            return jsonResponse(tokens('sync'));
          }
          if (req.url.path.contains('/scopes/')) {
            return jsonResponse({
              'data': {'enabled': true}
            });
          }
          if (req.url.path.contains('/objects/')) {
            keys.add(req.headers['Idempotency-Key'] ??
                req.headers['idempotency-key']!);
            if (offline) throw const BackendException(message: 'offline');
            uploaded = (jsonDecode(req.body) as Map).cast<String, dynamic>();
            revision++;
            return jsonResponse({
              'data': {'revision': revision, 'sha256': uploaded!['sha256']}
            });
          }
          throw StateError('unexpected ${req.url.path}');
        })));
    final settings = SettingsProvider();
    await settings.init();
    await backend.configureEndpoint(baseUrl: 'https://sync.test');
    await backend.bindInvite('invite');
    final sync = SyncProvider(
        backend: backend,
        settings: settings,
        outbox: outbox,
        keyStoreFactory: (_) => keyStore);
    try {
      expect(sync.enabled, false);
      await sync.setEnabled(true);
      expect(sync.error, isNull);
      expect(sync.enabled, true);
      offline = true;
      await settings.setThemeMode(AppThemeMode.dark);
      await sync.upload();
      expect(sync.error, isNotNull);
      final attempted = keys.single;
      await settings.setHomeNavigationStyle(HomeNavigationStyle.bottomPanel);
      offline = false;
      await sync.upload();
      expect(sync.error, isNull);
      expect(keys[1], attempted);
      expect(revision, 2);
      final payload =
          SyncCrypto.decrypt(uploaded!, base64Decode(keyStore.value!));
      expect(payload, {
        'schemaVersion': 1,
        'themeMode': 'dark',
        'homeNavigationStyle': 'bottomPanel'
      });
      expect(await outbox.pending('https://sync.test', backend.config.deviceId),
          isEmpty);
      await backend.configureEndpoint(baseUrl: 'https://other.test');
      expect(sync.enabled, false);
    } finally {
      sync.dispose();
      settings.dispose();
      backend.dispose();
      await db.close();
    }
  });
}
