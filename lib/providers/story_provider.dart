import '../services/secure_config_storage.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/story_package.dart';
import '../services/backend_http_client.dart';
import '../services/story_service.dart';
import 'backend_provider.dart';

class StoryProvider extends ChangeNotifier {
  static const _configKey = 'story_community_source_v1';
  static const _fallbackKey = 'story_community_static_fallback_v1';
  static const _catalogFetchedAtKey = 'story_community_catalog_fetched_at_v1';
  final BackendProvider backend;
  final bool _ownsBackend;
  final BackendHttpClient _staticClient;
  final bool _usesDefaultStaticClient;
  StoryProvider({BackendProvider? backend, BackendHttpClient? staticClient})
      : backend = backend ?? BackendProvider(),
        _ownsBackend = backend == null,
        _staticClient = staticClient ?? BackendHttpClient(),
        _usesDefaultStaticClient = staticClient == null;

  StorySourceConfig _config = const StorySourceConfig();
  StorySourceConfig? _staticFallback;
  final _savedSources = <StorySourceType, StorySourceConfig>{};
  List<StoryCatalogEntry> _entries = const [];
  List<StoryCatalogEntry> _cachedEntries = const [];
  bool _loading = false,
      _loadingMore = false,
      _hasMore = false,
      _disposed = false;
  bool _usingCache = false;
  String? _nextCursor, _error, _requestKey;
  String _query = '', _tag = '';
  Future<void>? _initFuture, _catalogFuture;
  BackendRequestScope? _catalogScope;
  int _generation = 0;
  DateTime? _catalogFetchedAt;
  bool _failedAppend = false;
  final _packageScopes = <BackendRequestScope>{};
  StorySourceConfig get config => _config;
  List<StoryCatalogEntry> get entries => List.unmodifiable(_entries);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  bool get usingCache => _usingCache;
  String? get nextCursor => _nextCursor;
  String? get error => _error;
  bool get canUseStaticFallback =>
      _staticFallback != null && _config.type == StorySourceType.server;
  bool get supportsServerStats => _config.type == StorySourceType.server;
  bool get isConfigured => switch (_config.type) {
        StorySourceType.server => _config.baseUrl.trim().isNotEmpty,
        StorySourceType.cos => _config.indexUrl.trim().isNotEmpty ||
            _config.baseUrl.trim().isNotEmpty,
        _ => _config.indexUrl.trim().isNotEmpty ||
            _config.repository.trim().isNotEmpty,
      };
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> init() => _initFuture ??= _loadConfig();
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = await SecureConfigStorage.readJson(prefs, _configKey);
      if (raw != null) {
        _config = StorySourceConfig.fromJson(
            (jsonDecode(raw) as Map).cast<String, dynamic>());
      }
      final fetched = prefs.getInt(_catalogFetchedAtKey);
      if (fetched != null) {
        _catalogFetchedAt = DateTime.fromMillisecondsSinceEpoch(fetched);
      }
      final fallback = await SecureConfigStorage.readJson(prefs, _fallbackKey);
      if (fallback != null) {
        _staticFallback = StorySourceConfig.fromJson(
                (jsonDecode(fallback) as Map).cast<String, dynamic>())
            .copyWith(token: '');
        _savedSources[_staticFallback!.type] = _staticFallback!;
      }
      final sources = await SecureConfigStorage.readJson(
          prefs, 'story_community_sources_v1');
      if (sources != null) {
        final values = jsonDecode(sources) as Map;
        for (final value in values.values) {
          final saved = StorySourceConfig.fromJson(
              (value as Map).cast<String, dynamic>());
          _savedSources[saved.type] = saved.copyWith(token: '');
        }
      }
    } on FormatException {
      _config = const StorySourceConfig();
    }
    await backend.init();
    if (_config.type == StorySourceType.server && isConfigured) {
      try {
        await backend.configureEndpoint(
            baseUrl: _config.baseUrl,
            port: _config.port,
            manualAccessToken: _config.token);
      } on FormatException catch (error) {
        _error = error.message;
      }
    }
    // Move legacy manually entered tokens into the backend secure session.
    _config = _config.copyWith(token: '');
    _savedSources[_config.type] = _config;
    await SecureConfigStorage.writeJson(
        prefs, _configKey, jsonEncode(_config.toJson()));
    await SecureConfigStorage.writeJson(
        prefs,
        'story_community_sources_v1',
        jsonEncode({
          for (final entry in _savedSources.entries)
            entry.key.name: entry.value.toJson(),
        }));
    if (_staticFallback != null) {
      await SecureConfigStorage.writeJson(
          prefs, _fallbackKey, jsonEncode(_staticFallback!.toJson()));
    }
    await _restoreCache(prefs);
    _notify();
  }

  Future<void> saveConfig(StorySourceConfig config) async {
    await init();
    if (config.type == StorySourceType.server) {
      await backend.configureEndpoint(
          baseUrl: config.baseUrl,
          port: config.port,
          manualAccessToken: config.token);
    }
    final sanitized = config.copyWith(token: '');
    if (jsonEncode(sanitized.toJson()) == jsonEncode(_config.toJson())) return;
    cancelRequests();
    _config = sanitized;
    _entries = const [];
    _cachedEntries = const [];
    _query = '';
    _tag = '';
    _nextCursor = null;
    _hasMore = false;
    _error = null;
    _usingCache = false;
    final prefs = await SharedPreferences.getInstance();
    await SecureConfigStorage.writeJson(
        prefs, _configKey, jsonEncode(sanitized.toJson()));
    _savedSources[sanitized.type] = sanitized;
    await SecureConfigStorage.writeJson(
        prefs,
        'story_community_sources_v1',
        jsonEncode({
          for (final entry in _savedSources.entries)
            entry.key.name: entry.value.toJson(),
        }));
    if (config.type != StorySourceType.server && isConfigured) {
      _staticFallback = sanitized;
      await SecureConfigStorage.writeJson(
          prefs, _fallbackKey, jsonEncode(sanitized.toJson()));
    }
    await _restoreCache(prefs);
    _notify();
  }

  Future<void> switchSource(StorySourceType type) async {
    await init();
    final saved = _savedSources[type] ?? StorySourceConfig(type: type);
    await saveConfig(saved);
  }

  Future<void> useStaticFallback() async {
    final fallback = _staticFallback;
    if (fallback == null) return;
    await saveConfig(fallback);
    await loadCatalog();
  }

  String get _cacheKey =>
      'story_catalog_cache_v1_${sha256.convert(utf8.encode(jsonEncode(_config.toJson())))}';
  Future<void> _restoreCache(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      _entries = _parseEntries(jsonDecode(raw));
      _cachedEntries = _entries;
      _usingCache = _entries.isNotEmpty;
    } catch (_) {/* A damaged cache must not prevent configuration. */}
  }

  Future<void> loadCatalog(
      {String? query,
      String? tag,
      bool append = false,
      bool force = false}) async {
    await init();
    if (_disposed) return;
    if (!isConfigured) return;
    final q = query?.trim() ?? '', t = tag?.trim() ?? '';
    if (!force &&
        !append &&
        q.isEmpty &&
        t.isEmpty &&
        _cachedEntries.isNotEmpty &&
        _catalogFetchedAt != null &&
        DateTime.now().difference(_catalogFetchedAt!).inMinutes < 5) {
      _entries = _cachedEntries;
      _usingCache = true;
      _error = null;
      _notify();
      return;
    }
    if (append && (q != _query || t != _tag || !_hasMore)) return;
    final key = '$q\n$t\n${append ? _nextCursor : ''}';
    if (_loading && _requestKey == key) {
      await _catalogFuture;
      return;
    }
    cancelCatalog();
    final scope = BackendRequestScope();
    _catalogScope = scope;
    final generation = _generation;
    final config = _config;
    final cursor = append ? _nextCursor : null;
    _requestKey = key;
    _loading = true;
    _loadingMore = append;
    _failedAppend = append;
    _error = null;
    _notify();
    final future =
        _fetchCatalog(config, q, t, cursor, scope).then((decoded) async {
      scope.check();
      if (generation != _generation) return;
      final values = _parseEntries(decoded);
      final data = decoded is Map && decoded['data'] is Map
          ? decoded['data'] as Map
          : decoded;
      final next = decoded is Map
          ? (decoded['nextCursor'] ?? (data is Map ? data['nextCursor'] : null))
          : null;
      final more = decoded is Map
          ? (decoded['hasMore'] ?? (data is Map ? data['hasMore'] : null))
          : null;
      if (more == true &&
          (next == null || next.toString().isEmpty || next == cursor)) {
        throw const FormatException('服务器分页响应缺少有效的下一页游标');
      }
      final filtered = config.type == StorySourceType.server
          ? values
          : _filter(values, q, t);
      _entries = append ? _merge(filtered) : filtered;
      _query = q;
      _tag = t;
      _nextCursor = next?.toString();
      _hasMore = more == true;
      _usingCache = false;
      if (q.isEmpty && t.isEmpty) {
        _cachedEntries = _entries;
        final prefs = await SharedPreferences.getInstance();
        if (generation == _generation) {
          _catalogFetchedAt = DateTime.now();
          await prefs.setInt(
              _catalogFetchedAtKey, _catalogFetchedAt!.millisecondsSinceEpoch);
          await prefs.setString(_cacheKey,
              jsonEncode(_entries.take(500).map((v) => v.toJson()).toList()));
        }
      }
    }).catchError((Object error) {
      if (error is RequestCancelled || generation != _generation || _disposed) {
        return;
      }
      _error = readableError(error);
      _usingCache = _entries.isNotEmpty || _cachedEntries.isNotEmpty;
      // Offline queries can still filter the previously downloaded catalog.
      if (!append && _usingCache && (q != _query || t != _tag)) {
        _entries = _filter(
            _cachedEntries.isNotEmpty ? _cachedEntries : _entries, q, t);
      }
    }).whenComplete(() {
      if (generation == _generation && !_disposed) {
        _loading = false;
        _loadingMore = false;
        _catalogScope = null;
        _catalogFuture = null;
        _notify();
      }
    });
    _catalogFuture = future;
    await future;
  }

  Future<dynamic> _fetchCatalog(StorySourceConfig config, String q, String t,
      String? cursor, BackendRequestScope scope) {
    if (config.type == StorySourceType.server) {
      return backend.loadStories(
          query: q, tag: t, cursor: cursor, scope: scope);
    }
    // Static GitHub/Gitee/COS sources are public JSON endpoints. Keep them on
    // the plain HTTP path: the backend client adds server request semantics
    // (abortable requests and API headers) that are not needed by raw hosts
    // and can make redirected raw URLs fail on desktop platforms.
    final uri = StoryService.staticIndexUri(config);
    return _usesDefaultStaticClient
        ? StoryService.getStaticJson(config, uri, filePath: config.path)
        : _staticClient.getJson(uri, scope: scope);
  }

  Future<void> loadMoreCatalog({String? query, String? tag}) =>
      loadCatalog(query: query, tag: tag, append: true);

  /// Return to the unfiltered cached feed without touching the network.
  void restoreCachedCatalog() {
    if (_cachedEntries.isEmpty) return;
    cancelCatalog();
    _entries = _cachedEntries;
    _query = '';
    _tag = '';
    _error = null;
    _usingCache = true;
    _notify();
  }

  Future<void> retryCatalog({String? query, String? tag}) =>
      loadCatalog(query: query, tag: tag, append: _failedAppend);
  Future<StoryPackage> loadPackage(StoryCatalogEntry entry,
      {BackendRequestScope? scope}) async {
    await init();
    final operation = scope ?? BackendRequestScope();
    final generation = _generation;
    final source = _config;
    final cacheKey =
        '${_cacheKey}_package_${entry.storyId}_${entry.version}_${Uri.encodeComponent(entry.file)}';
    _packageScopes.add(operation);
    try {
      final StoryPackage story;
      if (source.type == StorySourceType.server) {
        story = await backend.loadStoryPackage(entry, scope: operation);
      } else {
        final uri = StoryService.resolveStaticFile(
            StoryService.staticIndexUri(source), entry.file);
        final decoded = _usesDefaultStaticClient
            ? await StoryService.getStaticJson(source, uri,
                filePath: entry.file,
                requestTimeout: const Duration(seconds: 20))
            : await _staticClient.getJson(uri,
                scope: operation, requestTimeout: const Duration(seconds: 20));
        if (decoded is! Map) throw const FormatException('故事详情格式无效');
        story = StoryPackage.fromJson(decoded.cast<String, dynamic>());
      }
      operation.check();
      if (generation != _generation) throw const RequestCancelled();
      if (story.storyId != entry.storyId ||
          (entry.hasVersion && story.version != entry.version)) {
        throw const FormatException('故事 ID 或版本与目录不一致，请刷新目录');
      }
      final prefs = await SharedPreferences.getInstance();
      final data = _packageJson(story);
      final encoded = jsonEncode(data);
      if (encoded.length < 1000000) {
        final keys = prefs
            .getKeys()
            .where((v) =>
                v.startsWith('story_catalog_cache_v1_') &&
                v.contains('_package_'))
            .toList()
          ..sort();
        for (final key in keys.take((keys.length - 9).clamp(0, keys.length))) {
          await prefs.remove(key);
        }
        await prefs.setString(cacheKey, encoded);
      }
      return story;
    } catch (error) {
      if (error is RequestCancelled) rethrow;
      final prefs = await SharedPreferences.getInstance();
      operation.check();
      if (generation != _generation) throw const RequestCancelled();
      final raw = prefs.getString(cacheKey);
      if (raw != null) {
        try {
          return StoryPackage.fromText(raw);
        } catch (_) {}
      }
      throw Exception(readableError(error));
    } finally {
      _packageScopes.remove(operation);
    }
  }

  Future<void> testConnection() async {
    await init();
    if (!isConfigured) throw const FormatException('请先填写故事来源地址');
    if (_config.type == StorySourceType.server) {
      await backend.testStoryConnection();
      if (!backend.storiesEnabled) {
        throw const BackendException(
            code: 'FEATURE_DISABLED', message: '服务器未开启故事服务');
      }
    } else {
      final uri = StoryService.staticIndexUri(_config);
      _parseEntries(_usesDefaultStaticClient
          ? await StoryService.getStaticJson(_config, uri,
              filePath: _config.path)
          : await _staticClient.getJson(uri));
    }
  }

  List<StoryCatalogEntry> _parseEntries(dynamic decoded) {
    final raw = decoded is List
        ? decoded
        : decoded is Map
            ? (decoded['stories'] ??
                (decoded['data'] is Map ? decoded['data']['items'] : null))
            : null;
    if (raw is! List) {
      throw const FormatException('故事目录缺少 stories 列表，请检查服务器版本或切换静态来源');
    }
    return raw.map((value) {
      if (value is! Map) throw const FormatException('故事条目格式无效');
      final entry = StoryCatalogEntry.fromJson(value.cast<String, dynamic>());
      if (entry.storyId.isEmpty || entry.title.isEmpty) {
        throw const FormatException('故事条目缺少 ID 或标题');
      }
      return entry;
    }).toList(growable: false);
  }

  List<StoryCatalogEntry> _filter(
      List<StoryCatalogEntry> values, String query, String tag) {
    final q = query.toLowerCase(), t = tag.toLowerCase();
    return values
        .where((entry) =>
            (q.isEmpty ||
                entry.title.toLowerCase().contains(q) ||
                entry.summary.toLowerCase().contains(q) ||
                entry.tags.any((v) => v.toLowerCase().contains(q))) &&
            (t.isEmpty || entry.tags.any((v) => v.toLowerCase() == t)))
        .toList(growable: false);
  }

  List<StoryCatalogEntry> _merge(List<StoryCatalogEntry> values) {
    final result = {for (final entry in _entries) entry.storyId: entry};
    for (final entry in values) {
      result[entry.storyId] = entry;
    }
    return result.values.toList(growable: false);
  }

  Map<String, dynamic> _packageJson(StoryPackage story) => {
        'schemaVersion': 1,
        'storyId': story.storyId,
        'version': story.version,
        'title': story.title,
        'author': story.author,
        'summary': story.summary,
        'publishedAt': story.publishedAt,
        'introduction': story.introduction,
        'tags': story.tags,
        'memories': [for (final memory in story.memories) memory.content],
        'images': story.images,
      };
  String readableError(Object error) {
    if (error is TimeoutException) return '故事来源请求超时，请检查地址、端口或网络';
    if (error is SocketException || error is HandshakeException) {
      return '无法连接故事来源，请检查地址和端口';
    }
    if (error is BackendException) return error.message;
    if (error is HttpException) return error.message;
    if (error is FormatException) return error.message;
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  void cancelCatalog() {
    _generation++;
    _catalogScope?.cancel();
    _catalogScope = null;
    _catalogFuture = null;
    _loading = false;
    _loadingMore = false;
  }

  void cancelRequests() {
    cancelCatalog();
    for (final scope in _packageScopes.toList()) {
      scope.cancel();
    }
    _staticClient.cancelAll();
    backend.cancelRequests();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelRequests();
    _staticClient.close();
    if (_ownsBackend) backend.dispose();
    super.dispose();
  }
}
