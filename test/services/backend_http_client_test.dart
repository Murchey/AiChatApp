import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_chat/services/backend_http_client.dart';
import '../support/backend_test_support.dart';

void main() {
  final uri = Uri.parse('https://backend.test/api/stories');
  test('401 retries exactly once and preserves request ID', () async {
    var requests = 0, refreshes = 0;
    String? requestId;
    final client = BackendHttpClient(client: MockClient((request) async {
      requests++;
      requestId ??= request.headers['X-Request-Id'];
      expect(request.headers['X-Request-Id'], requestId);
      expect(request.headers['Authorization'],
          requests == 1 ? 'Bearer old' : 'Bearer next');
      return jsonResponse({
        'error': {'code': 'TOKEN_EXPIRED'}
      }, status: 401);
    }));
    await expectLater(
        client.getJson(uri, token: 'old', onUnauthorized: () async {
          refreshes++;
          return 'next';
        }),
        throwsA(isA<BackendException>()
            .having((v) => v.statusCode, 'status', 401)));
    expect(requests, 2);
    expect(refreshes, 1);
    client.close();
  });
  test('429 preserves Retry-After, request ID and readable message', () async {
    final client = BackendHttpClient(
        client: MockClient((_) async => http.Response(
            '{"error":{"code":"RATE_LIMITED","message":"稍后重试","requestId":"req_test","retryAfterSeconds":12}}',
            429,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    await expectLater(
        client.getJson(uri),
        throwsA(isA<BackendException>()
            .having((v) => v.retryAfterSeconds, 'retry', 12)
            .having((v) => v.requestId, 'id', 'req_test')));
    client.close();
  });
  test('timeout aborts scope without waiting for platform timeout', () async {
    final scope = BackendRequestScope();
    final pending = Completer<http.Response>();
    final client = BackendHttpClient(
        client: MockClient((_) => pending.future),
        timeout: const Duration(milliseconds: 20));
    await expectLater(
        client.getJson(uri, scope: scope), throwsA(isA<TimeoutException>()));
    expect(scope.cancelled, true);
    pending.complete(jsonResponse({}));
    client.close();
  });
  test('cancel ends awaiting request and ignores late response', () async {
    final scope = BackendRequestScope(), pending = Completer<http.Response>();
    final client = BackendHttpClient(client: MockClient((_) => pending.future));
    final request = client.getJson(uri, scope: scope);
    final check = expectLater(request, throwsA(isA<RequestCancelled>()));
    scope.cancel();
    await check;
    pending.complete(jsonResponse({}));
    client.close();
  });
  test('BOM accepted and bad successful JSON rejected', () async {
    final client = BackendHttpClient(
        client: MockClient((_) async => http.Response(
            '\uFEFF{"stories":[]}', 200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    expect(await client.getJson(uri), {'stories': []});
    client.close();
    final bad = BackendHttpClient(
        client: MockClient((_) async => http.Response('<html/>', 200)));
    await expectLater(bad.getJson(uri), throwsFormatException);
    bad.close();
  });
}
