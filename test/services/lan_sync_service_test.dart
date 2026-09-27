import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/lan_sync_service.dart';

void main() {
  group('LanSyncService.parseEndpoint', () {
    test('parses ip:port', () {
      final r = LanSyncService.parseEndpoint('192.168.43.10:8765');
      expect(r, isNotNull);
      expect(r!.host, '192.168.43.10');
      expect(r.port, 8765);
    });

    test('parses http url', () {
      final r = LanSyncService.parseEndpoint('http://192.168.1.5:9000');
      expect(r!.host, '192.168.1.5');
      expect(r.port, 9000);
    });

    test('parses hostname:port', () {
      final r = LanSyncService.parseEndpoint('desktop.local:8765');
      expect(r!.host, 'desktop.local');
      expect(r.port, 8765);
    });

    test('rejects invalid input', () {
      expect(LanSyncService.parseEndpoint(''), isNull);
      expect(LanSyncService.parseEndpoint('192.168.1.1'), isNull);
      expect(LanSyncService.parseEndpoint(':8765'), isNull);
      expect(LanSyncService.parseEndpoint('192.168.1.1:99999'), isNull);
    });
  });

  group('LanSyncService.buildUri', () {
    test('builds sync uri with query', () {
      final uri = LanSyncService.buildUri(
        host: '192.168.43.10',
        port: 8765,
        path: '/api/sync',
        query: {'name': 'a.zip', 'kind': 'local'},
      );
      expect(uri.toString(), contains('http://192.168.43.10:8765/api/sync'));
      expect(uri.queryParameters['name'], 'a.zip');
    });
  });
}
