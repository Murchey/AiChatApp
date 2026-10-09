import 'dart:convert';
import 'dart:io';
import 'package:ai_chat/data/db/app_database.dart';
import 'package:ai_chat/providers/backend_provider.dart';
import 'package:ai_chat/services/sync_crypto.dart';
import 'package:ai_chat/services/sync_outbox_store.dart';
import 'package:ai_chat/services/sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../support/backend_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final endpoint = Platform.environment['AICHAT_TEST_BACKEND'] ?? '';
  test(
      'live JAR accepts Flutter authenticated ciphertext and returns decryptable data',
      () async {
        final uri = Uri.parse(endpoint);
        HttpOverrides.global = null; // Opt-in live fixture, not a widget HTTP mock.
        SharedPreferences.setMockInitialValues({});
    expect({'127.0.0.1', 'localhost', '::1'}, contains(uri.host));
    final admin = Platform.environment['AICHAT_TEST_ADMIN_TOKEN'];
    expect(admin, isNotNull);
    final client = http.Client();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final backend = BackendProvider(tokenStore: MemoryTokenStore());
    try {
      final invite = await client.post(uri.resolve('/api/admin/invites'),
          headers: {
            'X-Admin-Token': admin!,
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'maxUses': 1, 'expiresInHours': 1}));
      expect(invite.statusCode, 200);
      final data = jsonDecode(invite.body)['data'] as Map;
      await backend.configureEndpoint(baseUrl: endpoint);
      await backend.bindInvite(data['code'] as String);
      final outbox = SyncOutboxStore(db);
      final service = SyncService(backend: backend, outbox: outbox);
      await service.enableDomain('settings', true);
      final key = SyncCrypto.generateKey();
      final payload = <String, Object?>{
        'schemaVersion': 1,
        'themeMode': 'dark',
        'homeNavigationStyle': 'floating'
      };
      await outbox.writeLocal(
          backend.config.endpoint('').toString(),
          backend.config.deviceId,
          'settings',
          SyncCrypto.encrypt(payload, key, 0));
      await service.flush();
      final remote = await service.download('settings');
      expect(remote['revision'], 1);
      expect(SyncCrypto.decrypt(remote, key), payload);
      expect(
          await outbox.pending(
              backend.config.endpoint('').toString(), backend.config.deviceId),
          isEmpty);
      await backend.revokeDevice();
    } finally {
      client.close();
      backend.dispose();
      await db.close();
    }
  },
      skip: endpoint.isEmpty
          ? 'Set AICHAT_TEST_BACKEND and AICHAT_TEST_ADMIN_TOKEN for a disposable local JAR'
          : false);
}
