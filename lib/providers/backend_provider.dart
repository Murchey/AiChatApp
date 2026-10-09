import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/backend_capabilities.dart';
import '../models/backend_config.dart';
import '../models/story_package.dart';
import '../services/backend_http_client.dart';
import '../services/backend_token_store.dart';
import '../services/device_auth_service.dart';
import '../services/story_backend_service.dart';

enum BackendConnectionStatus {
  unconfigured,
  idle,
  checking,
  connected,
  unauthorized,
  error
}

class BackendProvider extends ChangeNotifier {
  static const configKey = 'aichat_backend_config_v1';
  static const clientVersion = '1.6.1';
  final BackendHttpClient _client;
  final BackendTokenStore _tokenStore;
  late final DeviceAuthService _auth;
  BackendConfig _config = const BackendConfig();
  BackendCapabilities? _capabilities;
  BackendConnectionStatus _status = BackendConnectionStatus.unconfigured;
  String? _error;
  String? storageNotice;
  Future<void>? _initFuture;
  Future<void>? _statusFuture;
  Future<String?>? _refreshFuture;
  DateTime? _checkedAt;
  DateTime? _retryAt;
  int _epoch = 0;
  bool _disposed = false;
  Future<void> _writes = Future.value();

  BackendProvider({BackendHttpClient? client, BackendTokenStore? tokenStore})
      : _client = client ?? BackendHttpClient(),
        _tokenStore = tokenStore ?? const SecureBackendTokenStore() {
    _auth = DeviceAuthService(_client);
  }
  BackendConfig get config => _config;
  BackendCapabilities? get capabilities => _capabilities;
  BackendConnectionStatus get status => _status;
  String? get error => _error;
  bool get isConfigured => _config.hasEndpoint;
  bool get isAuthenticated => _config.hasSession;
  bool get storiesEnabled => _capabilities?.storiesEnabled ?? false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool matchesEndpoint(String baseUrl, String port) {
    try {
      return BackendConfig(baseUrl: baseUrl, port: port).endpoint('') ==
          _config.endpoint('');
    } catch (_) {
      return false;
    }
  }

  Future<void> init() => _initFuture ??= _load();
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(configKey);
    if (raw != null) {
      try {
        final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
        _config = BackendConfig.fromJson(data);
        if (data['capabilities'] is Map) {
          _capabilities = BackendCapabilities.fromJson(data['capabilities']);
        }
      } catch (_) {
        _config = const BackendConfig();
      }
    }
    try {
      final secret = await _tokenStore.read();
      if (secret != null) {
        final session = BackendConfig.fromJson(
            (jsonDecode(secret) as Map).cast<String, dynamic>());
        if (session.baseUrl == _config.baseUrl &&
            session.port == _config.port &&
            session.deviceId == _config.deviceId) {
          _config = _config.copyWith(
              accessToken: session.accessToken,
              refreshToken: session.refreshToken);
        }
      }
    } catch (_) {
      storageNotice = '安全存储不可用，仅保留本次启动的短期令牌，重启后需要重新绑定';
    }
    _status = isConfigured
        ? BackendConnectionStatus.idle
        : BackendConnectionStatus.unconfigured;
    // Also strips secrets left by development versions from ordinary prefs.
    await _persist();
    _notify();
  }

  Future<void> configureEndpoint(
      {required String baseUrl,
      String port = '',
      String scheme = 'https',
      String? deviceId,
      String? manualAccessToken,
      bool persist = true}) async {
    await init();
    final candidate = _config.copyWith(
        baseUrl: baseUrl.trim(),
        port: port.trim(),
        scheme: scheme,
        deviceId: deviceId?.trim().isNotEmpty == true
            ? deviceId!.trim()
            : (_config.deviceId.isEmpty
                ? const Uuid().v4()
                : _config.deviceId));
    if (candidate.hasEndpoint) candidate.endpoint('');
    final changed = candidate.baseUrl != _config.baseUrl ||
        candidate.port != _config.port ||
        candidate.scheme != _config.scheme ||
        candidate.deviceId != _config.deviceId;
    final manualChanged = manualAccessToken?.isNotEmpty == true &&
        manualAccessToken != _config.accessToken;
    if (!changed && !manualChanged) return;
    _epoch++;
    _client.cancelAll();
    _statusFuture = null;
    _refreshFuture = null;
    _checkedAt = null;
    _retryAt = null;
    _config = candidate.copyWith(
        accessToken: manualAccessToken?.trim() ?? '',
        refreshToken: '',
        clearAccessExpiry: true,
        clearRefreshExpiry: true,
        clearLastSuccessfulAt: true,
        featureFlags: {});
    _capabilities = null;
    _error = null;
    _status = isConfigured
        ? BackendConnectionStatus.idle
        : BackendConnectionStatus.unconfigured;
    if (persist) await _persist();
    _notify();
  }

  Future<void> bindInvite(String inviteCode,
      {String label = 'AiChat device', BackendRequestScope? scope}) async {
    await init();
    if (!isConfigured) throw const FormatException('请先填写服务器地址');
    if (inviteCode.trim().isEmpty) throw const FormatException('请输入邀请码');
    final epoch = _epoch;
    try {
      final pair = await _auth.exchangeInvite(_config, inviteCode,
          label: label, scope: scope);
      _guard(epoch);
      _config = _applyTokens(pair);
      await _persist();
      _guard(epoch);
      _status = BackendConnectionStatus.connected;
      _error = null;
      _notify();
    } catch (error) {
      if (epoch == _epoch && error is! RequestCancelled) {
        _status = BackendConnectionStatus.error;
        _error = errorMessage(error);
        _notify();
      }
      rethrow;
    }
  }

  Future<String?> refreshAccessToken() {
    if (_refreshFuture != null) return _refreshFuture!;
    final future = _refreshInternal();
    _refreshFuture = future;
    future.whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
    return future;
  }

  Future<String?> _refreshInternal() async {
    await init();
    final epoch = _epoch;
    if (_config.refreshToken.isEmpty) {
      await clearSession(cancelRequests: false);
      _status = BackendConnectionStatus.unauthorized;
      _error = '服务器登录已失效，请重新绑定设备';
      _notify();
      return null;
    }
    try {
      final pair = await _auth.refresh(_config);
      _guard(epoch);
      _config = _applyTokens(pair);
      await _persist();
      _guard(epoch);
      _status = BackendConnectionStatus.connected;
      _notify();
      return _config.accessToken;
    } catch (error) {
      if (epoch != _epoch || _disposed || error is RequestCancelled) {
        return null;
      }
      await clearSession(cancelRequests: false);
      _status = BackendConnectionStatus.unauthorized;
      _error = errorMessage(error);
      _notify();
      return null;
    }
  }

  Future<void> refreshStatus(
      {bool force = true, BackendRequestScope? scope}) async {
    await init();
    if (!isConfigured) return;
    if (_statusFuture != null) {
      final pending = _statusFuture!;
      return scope == null ? pending : scope.wait(pending);
    }
    if (!force &&
        _checkedAt != null &&
        DateTime.now().difference(_checkedAt!) < const Duration(minutes: 1)) {
      _validateCapabilities();
      return;
    }
    final future = _probe(scope: scope);
    _statusFuture = future;
    try {
      if (scope == null) {
        await future;
      } else {
        await scope.wait(future);
      }
    } finally {
      if (identical(_statusFuture, future)) _statusFuture = null;
    }
  }

  Future<void> _probe({BackendRequestScope? scope}) async {
    final epoch = _epoch;
    final config = _config;
    _status = BackendConnectionStatus.checking;
    _notify();
    try {
      final responses = await Future.wait([
        _client.getJson(config.endpoint('/api/health'), scope: scope),
        _client.getJson(config.endpoint('/api/version'), scope: scope),
      ]);
      _guard(epoch);
      final health = responses[0];
      final healthData =
          health is Map && health['data'] is Map ? health['data'] : health;
      if (healthData is! Map || healthData['status'] != 'UP') {
        throw const FormatException('服务器健康检查响应格式无效');
      }
      _capabilities = BackendCapabilities.fromJson(responses[1]);
      _validateCapabilities();
      _checkedAt = DateTime.now();
      _config = _config.copyWith(
          lastSuccessfulAt: DateTime.now().toUtc(),
          featureFlags: _capabilities!.features);
      _error = null;
      _status = BackendConnectionStatus.connected;
      await _persist();
      _guard(epoch);
      _notify();
    } catch (error) {
      if (epoch == _epoch && error is! RequestCancelled && !_disposed) {
        _status = BackendConnectionStatus.error;
        _error = errorMessage(error);
        _notify();
      }
      rethrow;
    }
  }

  void _validateCapabilities() {
    final capabilities = _capabilities;
    if (capabilities == null || capabilities.apiVersion != 'v1') {
      throw const BackendException(
          code: 'API_INCOMPATIBLE', message: '服务器 API 版本不兼容，请升级服务器或切换静态来源');
    }
    final minimum = capabilities.minClientVersion;
    if (minimum.isNotEmpty && _compareVersion(clientVersion, minimum) < 0) {
      throw const BackendException(
          code: 'CLIENT_TOO_OLD', message: '服务器需要更新版本的 App，请更新或切换静态来源');
    }
  }

  int _compareVersion(String left, String right) {
    final a = left
        .split('+')
        .first
        .split('.')
        .map((v) => int.tryParse(v) ?? 0)
        .toList();
    final b = right
        .split('+')
        .first
        .split('.')
        .map((v) => int.tryParse(v) ?? 0)
        .toList();
    for (var i = 0; i < 3; i++) {
      final difference = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
      if (difference != 0) return difference;
    }
    return 0;
  }

  Future<StoryBackendService> _storyService(BackendRequestScope? scope) async {
    scope?.check();
    _checkRateLimit();
    await init();
    final epoch = _epoch;
    await refreshStatus(force: false, scope: scope);
    _guard(epoch);
    scope?.check();
    if (!storiesEnabled) {
      throw const BackendException(
          code: 'FEATURE_DISABLED', message: '服务器未开启故事服务，可切换静态来源');
    }
    if (_config.accessExpired && _config.refreshToken.isNotEmpty) {
      await refreshAccessToken();
      _guard(epoch);
    }
    scope?.check();
    final usedToken = _config.accessToken;
    return StoryBackendService(
        client: _client,
        config: _config,
        refreshAccessToken: () {
          // Another request may already have rotated this token.
          if (_config.accessToken != usedToken &&
              _config.accessToken.isNotEmpty) {
            return Future.value(_config.accessToken);
          }
          return refreshAccessToken();
        });
  }

  Future<dynamic> loadStories(
      {String? query,
      String? tag,
      String? cursor,
      int limit = 20,
      BackendRequestScope? scope}) async {
    try {
      final service = await _storyService(scope);
      return await service.loadCatalog(
          query: query, tag: tag, cursor: cursor, limit: limit, scope: scope);
    } on BackendException catch (error) {
      await _recordRequestError(error);
      rethrow;
    }
  }

  Future<StoryPackage> loadStoryPackage(StoryCatalogEntry entry,
      {BackendRequestScope? scope}) async {
    try {
      final service = await _storyService(scope);
      return await service.loadPackage(entry, scope: scope);
    } on BackendException catch (error) {
      await _recordRequestError(error);
      rethrow;
    }
  }

  Future<void> testStoryConnection() => refreshStatus();

  /// Optional modules share the same auth/session lifecycle as story requests.
  Future<dynamic> requestModule(String feature, String path,
      {String method = 'GET',
      Object? body,
      Map<String, String> headers = const {},
      BackendRequestScope? scope}) async {
    scope?.check();
    _checkRateLimit();
    await init();
    final epoch = _epoch;
    await refreshStatus(force: false, scope: scope);
    _guard(epoch);
    if (_capabilities?.features[feature] != true) {
      throw BackendException(
          statusCode: 403,
          code: 'FEATURE_DISABLED',
          message: '服务器未启用 $feature');
    }
    if (_config.accessExpired && _config.refreshToken.isNotEmpty) {
      await refreshAccessToken();
      _guard(epoch);
    }
    scope?.check();
    final usedToken = _config.accessToken;
    try {
      final response = await _client.requestJson(_config.endpoint(path),
          method: method,
          body: body,
          headers: headers,
          scope: scope,
          token: usedToken, onUnauthorized: () {
        _guard(epoch);
        return _config.accessToken.isNotEmpty &&
                _config.accessToken != usedToken
            ? Future.value(_config.accessToken)
            : refreshAccessToken();
      });
      _guard(epoch);
      return response;
    } on BackendException catch (error) {
      _guard(epoch);
      await _recordRequestError(error);
      rethrow;
    }
  }

  void cancelRequests() => _client.cancelAll();
  void _checkRateLimit() {
    final remaining = _retryAt?.difference(DateTime.now()).inSeconds ?? 0;
    if (remaining > 0) {
      throw BackendException(
          statusCode: 429,
          code: 'RATE_LIMITED',
          message: '请求过于频繁，请在 $remaining 秒后重试',
          retryAfterSeconds: remaining);
    }
  }

  Future<void> _recordRequestError(BackendException error) async {
    if (error.statusCode == 429) {
      _retryAt = DateTime.now().add(
          Duration(seconds: (error.retryAfterSeconds ?? 30).clamp(1, 86400)));
    }
    if (error.isUnauthorized && !_disposed) {
      await clearSession(cancelRequests: false);
      _status = BackendConnectionStatus.unauthorized;
      _error = '服务器登录已失效，请重新绑定设备';
      _notify();
    }
  }

  Future<void> clearSession({bool cancelRequests = true}) async {
    _epoch++;
    if (cancelRequests) _client.cancelAll();
    _refreshFuture = null;
    _config = _config.copyWith(
        accessToken: '',
        refreshToken: '',
        clearAccessExpiry: true,
        clearRefreshExpiry: true);
    _status = isConfigured
        ? BackendConnectionStatus.idle
        : BackendConnectionStatus.unconfigured;
    _error = null;
    await _persist();
    _notify();
  }

  Future<void> revokeDevice() async {
    await init();
    if (!isAuthenticated) return;
    await _client.postJson(_config.endpoint('/api/auth/revoke'),
        token: _config.accessToken, onUnauthorized: refreshAccessToken);
    await clearSession();
  }

  BackendConfig _applyTokens(DeviceTokenPair pair) => _config.copyWith(
      accessToken: pair.accessToken,
      refreshToken: pair.refreshToken,
      accessExpiresAt: pair.accessExpiresAt,
      refreshExpiresAt: pair.refreshExpiresAt,
      clearAccessExpiry: pair.accessExpiresAt == null,
      clearRefreshExpiry: pair.refreshExpiresAt == null);
  Future<void> _persist() {
    // Writes are ordered so a late write cannot restore a revoked session.
    final snapshot = _config;
    final capabilities = _capabilities;
    final future = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          configKey,
          jsonEncode({
            ...snapshot.toJson(),
            if (capabilities != null) 'capabilities': capabilities.toJson()
          }));
      try {
        if (snapshot.accessToken.isEmpty && snapshot.refreshToken.isEmpty) {
          await _tokenStore.clear();
        } else {
          await _tokenStore
              .write(jsonEncode(snapshot.toJson(includeSecrets: true)));
        }
      } catch (_) {
        storageNotice = '安全存储不可用，仅保留本次启动的短期令牌，重启后需要重新绑定';
        // Never keep long-lived credentials when secure storage is unavailable.
        _config = _config.copyWith(refreshToken: '', clearRefreshExpiry: true);
      }
    });
    _writes = future.catchError((Object _) {});
    return future;
  }

  void _guard(int epoch) {
    if (_disposed || epoch != _epoch) throw const RequestCancelled();
  }

  String errorMessage(Object error) {
    if (error is TimeoutException) return '服务器请求超时，请检查地址、端口或网络';
    if (error is BackendException) return error.message;
    if (error is FormatException) return error.message;
    return '无法连接服务器，请检查地址、端口或网络';
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _client.close();
    super.dispose();
  }
}
