import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class BackendException implements Exception {
  final int? statusCode;
  final String code;
  final String message;
  final String? requestId;
  final int? retryAfterSeconds;
  const BackendException(
      {this.statusCode,
      this.code = 'BACKEND_ERROR',
      this.message = '服务器请求失败',
      this.requestId,
      this.retryAfterSeconds});
  bool get isUnauthorized => statusCode == 401;
  @override
  String toString() => message;
}

class RequestCancelled implements Exception {
  const RequestCancelled();
  @override
  String toString() => '请求已取消';
}

class BackendRequestScope {
  final _abort = Completer<void>();
  bool get cancelled => _abort.isCompleted;
  Future<void> get aborted => _abort.future;
  void cancel() {
    if (!cancelled) _abort.complete();
  }

  void check() {
    if (cancelled) throw const RequestCancelled();
  }

  Future<T> wait<T>(Future<T> future) => Future.any([
        future,
        aborted.then<T>((_) => throw const RequestCancelled()),
      ]);
}

class BackendHttpClient {
  final http.Client _client;
  final Duration timeout;
  final _scopes = <BackendRequestScope>{};
  BackendHttpClient(
      {http.Client? client, this.timeout = const Duration(seconds: 8)})
      : _client = client ?? http.Client();

  Future<dynamic> getJson(Uri uri,
          {String token = '',
          Future<String?> Function()? onUnauthorized,
          BackendRequestScope? scope,
          Map<String, String> headers = const {},
          Duration? requestTimeout}) =>
      requestJson(uri,
          token: token,
          onUnauthorized: onUnauthorized,
          scope: scope,
          headers: headers,
          requestTimeout: requestTimeout);

  Future<dynamic> postJson(Uri uri,
          {String token = '',
          Object? body,
          Future<String?> Function()? onUnauthorized,
          BackendRequestScope? scope}) =>
      requestJson(uri,
          method: 'POST',
          token: token,
          body: body,
          onUnauthorized: onUnauthorized,
          scope: scope);

  Future<dynamic> requestJson(Uri uri,
      {String method = 'GET',
      String token = '',
      Object? body,
      Future<String?> Function()? onUnauthorized,
      BackendRequestScope? scope,
      Map<String, String> headers = const {},
      Duration? requestTimeout}) async {
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('地址必须是 HTTP / HTTPS 且不能包含用户名密码');
    }
    final operation = scope ?? BackendRequestScope();
    _scopes.add(operation);
    final requestId = 'req_${const Uuid().v4().replaceAll('-', '')}';
    var currentToken = token;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        operation.check();
        final request =
            http.AbortableRequest(method, uri, abortTrigger: operation.aborted)
              ..headers.addAll({
                HttpHeaders.acceptHeader: 'application/json',
                'X-Request-Id': requestId,
                ...headers,
                if (body != null)
                  HttpHeaders.contentTypeHeader: 'application/json',
                if (currentToken.isNotEmpty)
                  HttpHeaders.authorizationHeader: 'Bearer $currentToken'
              })
              ..body = body == null ? '' : jsonEncode(body);
        http.Response response;
        try {
          response = await operation
              .wait(_client.send(request).then(http.Response.fromStream))
              .timeout(requestTimeout ?? timeout, onTimeout: () {
            operation.cancel();
            throw TimeoutException('服务器请求超时', requestTimeout ?? timeout);
          });
        } on http.RequestAbortedException {
          throw const RequestCancelled();
        } on http.ClientException {
          operation.check();
          throw const BackendException(
              code: 'NETWORK_ERROR', message: '无法连接故事来源，请检查地址和网络');
        }
        final decoded = _decode(response);
        if (response.statusCode == 401 &&
            attempt == 0 &&
            onUnauthorized != null) {
          final refreshed = await operation.wait(onUnauthorized());
          if (refreshed != null && refreshed.isNotEmpty) {
            currentToken = refreshed;
            continue;
          }
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final raw = decoded is Map && decoded['error'] is Map
              ? decoded['error'] as Map
              : const {};
          throw BackendException(
              statusCode: response.statusCode,
              code: raw['code']?.toString() ?? 'HTTP_${response.statusCode}',
              message:
                  raw['message']?.toString() ?? _message(response.statusCode),
              requestId: raw['requestId']?.toString() ??
                  response.headers['x-request-id'] ??
                  requestId,
              retryAfterSeconds: int.tryParse(
                  '${raw['retryAfterSeconds'] ?? response.headers['retry-after'] ?? ''}'));
        }
        return decoded;
      }
      throw const BackendException(statusCode: 401, message: '请重新绑定服务器');
    } finally {
      _scopes.remove(operation);
    }
  }

  dynamic _decode(http.Response response) {
    try {
      var text = utf8.decode(response.bodyBytes);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      return jsonDecode(text);
    } catch (_) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw const FormatException('服务器返回的 JSON 无法解析');
      }
      return null;
    }
  }

  String _message(int status) {
    if (status == 401) return '服务器登录已失效，请重新绑定设备';
    if (status == 403) return '当前设备没有执行此操作的权限';
    if (status == 404) return '服务器接口或内容不存在';
    if (status == 429) return '请求过于频繁，请稍后再试';
    if (status >= 500) return '服务器暂时不可用，请稍后重试';
    return '服务器请求失败（HTTP $status）';
  }

  void cancelAll() {
    for (final scope in _scopes.toList()) {
      scope.cancel();
    }
  }

  void close() {
    cancelAll();
    _client.close();
  }
}
