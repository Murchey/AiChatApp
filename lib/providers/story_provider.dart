import '../services/secure_config_storage.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/story_package.dart';
import '../models/story_index.dart';
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
  List<StoryCatalogEntry>? _entriesBacking, _unfilteredBacking;
  List<StoryCatalogEntry> _entriesView = const [], _unfilteredView = const [];
  List<StoryCatalogEntry> get entries {
    if (!identical(_entriesBacking, _entries)) {
      _entriesBacking = _entries;
      _entriesView = UnmodifiableListView(_entries);
    }
    return _entriesView;
  }

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
  List<StoryIndexReference> _indexes = [];
  final Map<String, Map<String, dynamic>> _indexPages = {};
  final Map<String, int> _indexTimes = {};
  final List<String> _loadedIndexes = [];
  String? _currentIndex;
  Future<void>? _staticFuture;
  String? _staticRequestKey;
  String? _failedIndexSelection;
  List<StoryIndexReference> get indexes => List.unmodifiable(_indexes);
  String? get currentIndex => _currentIndex;
  List<String> get loadedIndexes => List.unmodifiable(_loadedIndexes);
  List<StoryCatalogEntry> get unfilteredEntries {
    if (config.type == StorySourceType.server) return entries;
    if (!identical(_unfilteredBacking, _cachedEntries)) {
      _unfilteredBacking = _cachedEntries;
      _unfilteredView = UnmodifiableListView(_cachedEntries);
    }
    return _unfilteredView;
  }

  final Map<String, Map<String, dynamic>> _parsedPageData = {};
  final Map<String, List<StoryCatalogEntry>> _parsedPages = {};
  List<StoryCatalogEntry> _parseIndexPage(
      String file, Map<String, dynamic> data) {
    if (!identical(_parsedPageData[file], data)) {
      _parsedPages[file] = parseStaticStories(data);
      _parsedPageData[file] = data;
    }
    return _parsedPages[file]!;
  }

  String get _rootIndex =>
      StoryService.staticIndexUri(_config).pathSegments.last;
  String get _pageCacheKey => _cacheKey.replaceFirst(
      'story_catalog_cache_v1_', 'story_catalog_pages_v2_');

  void _resetIndexes() {
    _indexes = [];
    _indexPages.clear();
    _parsedPages.clear();
    _parsedPageData.clear();
    _indexTimes.clear();
    _loadedIndexes.clear();
    _currentIndex = null;
    _failedIndexSelection = null;
  }

  void _applyStaticFilter(String query, String tag,
      {bool rebuildCatalog = false}) {
    _query = query;
    _tag = tag;
    if (rebuildCatalog) {
      final all = <String, StoryCatalogEntry>{};
      for (final file in _loadedIndexes) {
        for (final entry in _parseIndexPage(file, _indexPages[file]!)) {
          all.putIfAbsent(entry.storyId, () => entry);
        }
      }
      _cachedEntries = all.values.toList(growable: false);
    }
    _entries = _filter(_cachedEntries, query, tag);
    final last = _loadedIndexes.isEmpty
        ? -1
        : _indexes.indexWhere((v) => v.file == _loadedIndexes.last);
    _hasMore = last >= 0 && last < _indexes.length - 1;
  }

  Future<void> _restoreIndexPages(SharedPreferences prefs) async {
    final raw = prefs.getString(_pageCacheKey);
    if (raw == null) return;
    try {
      final snapshot = jsonDecode(raw) as Map;
      final pages = snapshot['pages'] as Map;
      for (final item in pages.entries) {
        final page = item.value as Map;
        final data = Map<String, dynamic>.from(page['data'] as Map);
        _parseIndexPage(item.key as String, data);
        _indexPages[item.key as String] = data;
        _indexTimes[item.key as String] = page['time'] as int;
      }
      final root = _indexPages[_rootIndex];
      if (root == null) return;
      _indexes = StoryIndexReference.parse(root, _rootIndex);
      _loadedIndexes.add(_rootIndex);
      _currentIndex = _rootIndex;
      _applyStaticFilter('', '', rebuildCatalog: true);
      _usingCache = true;
    } catch (_) {
      _resetIndexes();
    }
  }

  Future<void> _saveIndexPages() async {
    final cacheKey = _pageCacheKey;
    final legacyKey = _cacheKey;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final snapshot = {
      'access': now,
      'pages': {
        for (final item in _indexPages.entries)
          item.key: {
            'data': item.value,
            'time': _indexTimes[item.key] ?? 0,
          }
      },
    };
    await prefs.setString(cacheKey, jsonEncode(snapshot));
    // Remove legacy static catalog snapshots after migrating to page caches.
    await prefs.remove(legacyKey);
    final records = <({String key, int time, int bytes})>[];
    for (final key in prefs
        .getKeys()
        .where((v) => v.startsWith('story_catalog_pages_v2_'))) {
      final raw = prefs.getString(key) ?? '';
      var access = 0;
      try {
        access = (jsonDecode(raw) as Map)['access'] as int;
      } catch (_) {}
      records.add((key: key, time: access, bytes: utf8.encode(raw).length));
    }
    records.sort((a, b) => b.time.compareTo(a.time));
    var bytes = 0;
    for (var i = 0; i < records.length; i++) {
      final item = records[i];
      if (i >= 5 || bytes + item.bytes > 5 * 1024 * 1024) {
        await prefs.remove(item.key);
      } else {
        bytes += item.bytes;
      }
    }
  }

  Future<Map<String, dynamic>> _readIndexPage(
      String file, BackendRequestScope scope,
      {required bool force}) async {
    final cached = _indexPages[file];
    final time = _indexTimes[file] ?? 0;
    if (!force &&
        cached != null &&
        DateTime.now().millisecondsSinceEpoch - time < 5 * 60 * 1000) {
      return cached;
    }
    final root = StoryService.staticIndexUri(_config);
    final uri = root.resolve(file);
    final value = _usesDefaultStaticClient
        ? await StoryService.getStaticJson(_config, uri,
            filePath: StoryService.staticFilePath(_config, uri))
        : await _staticClient.getJson(uri, scope: scope);
    scope.check();
    final data = value is List
        ? <String, dynamic>{'stories': value}
        : value is Map
            ? Map<String, dynamic>.from(value)
            : throw const FormatException('索引格式无效');
    _parseIndexPage(file, data);
    if (file == _rootIndex) StoryIndexReference.parse(data, _rootIndex);
    return data;
  }

  Future<void> selectIndex(String file) async {
    await init();
    if (!_indexes.any((v) => v.file == file)) return;
    await _staticCatalog('', '', selected: file);
  }

  Future<void> _staticCatalog(String q, String t,
      {bool append = false, bool force = false, String? selected}) {
    final key = '$q/$t/$append/$force/$selected/$_currentIndex';
    if (_loading && _staticRequestKey == key && _staticFuture != null) {
      return _staticFuture!;
    }
    _staticRequestKey = key;
    final future = _loadStaticCatalog(q, t,
        append: append, force: force, selected: selected);
    _staticFuture = future;
    return future;
  }

  Future<void> _loadStaticCatalog(String q, String t,
      {bool append = false, bool force = false, String? selected}) async {
    if (append && !_hasMore) return;
    cancelCatalog();
    final generation = _generation;
    final scope = BackendRequestScope();
    _catalogScope = scope;
    _loading = true;
    _loadingMore = append;
    _failedAppend = append;
    _failedIndexSelection = selected;
    _error = null;
    _notify();
    try {
      final staged = <String, Map<String, dynamic>>{};
      var directory = _indexes;
      String target;
      if (force) {
        staged[_rootIndex] =
            await _readIndexPage(_rootIndex, scope, force: true);
        directory = StoryIndexReference.parse(staged[_rootIndex], _rootIndex);
        final refresh = _loadedIndexes
            .where((v) => directory.any((p) => p.file == v))
            .toList();
        if (refresh.isEmpty) refresh.add(_rootIndex);
        for (final file in refresh) {
          if (file != _rootIndex) {
            staged[file] = await _readIndexPage(file, scope, force: true);
          }
        }
        target = refresh.first;
      } else if (selected != null) {
        target = selected;
        staged[target] = await _readIndexPage(target, scope, force: false);
        if (target == _rootIndex) {
          directory = StoryIndexReference.parse(staged[target], _rootIndex);
        }
      } else if (append) {
        final last = directory.indexWhere((v) => v.file == _loadedIndexes.last);
        target = directory[last + 1].file;
        staged[target] = await _readIndexPage(target, scope, force: false);
      } else {
        target = _rootIndex;
        staged[target] = await _readIndexPage(target, scope, force: false);
        directory = StoryIndexReference.parse(staged[target], _rootIndex);
      }
      scope.check();
      if (generation != _generation) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final item in staged.entries) {
        if (!identical(_indexPages[item.key], item.value)) {
          _indexTimes[item.key] = now;
        }
        _indexPages[item.key] = item.value;
      }
      _indexes = directory;
      final allowed = directory.map((v) => v.file).toSet();
      _indexPages.removeWhere((k, v) => !allowed.contains(k));
      _indexTimes.removeWhere((k, v) => !allowed.contains(k));
      _parsedPages.removeWhere((k, v) => !allowed.contains(k));
      _parsedPageData.removeWhere((k, v) => !allowed.contains(k));
      if (force) {
        _loadedIndexes.removeWhere((v) => !allowed.contains(v));
        if (_loadedIndexes.isEmpty) _loadedIndexes.add(target);
      } else if (append) {
        if (!_loadedIndexes.contains(target)) _loadedIndexes.add(target);
      } else {
        _loadedIndexes
          ..clear()
          ..add(target);
      }
      _currentIndex = _loadedIndexes.first;
      _failedIndexSelection = null;
      _usingCache = !force &&
          staged.entries.every((v) => (_indexTimes[v.key] ?? 0) < now);
      _applyStaticFilter(q, t, rebuildCatalog: true);
      await _saveIndexPages();
    } catch (error) {
      if (generation == _generation && error is! RequestCancelled) {
        _error = readableError(error);
        _usingCache = _indexPages.isNotEmpty || _cachedEntries.isNotEmpty;
      }
    } finally {
      if (generation == _generation && !_disposed) {
        _loading = false;
        _loadingMore = false;
        _catalogScope = null;
        _notify();
      }
    }
  }

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
    _resetIndexes();
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
    if (_config.type != StorySourceType.server && isConfigured) {
      await _restoreIndexPages(prefs);
      if (_indexPages.isNotEmpty) return;
    }
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
    if (_config.type != StorySourceType.server) {
      if (!append && !force && (query != null || tag != null)) {
        // Search never starts a download, even during the initial page load.
        // Reuse that in-flight result rather than requesting the root again.
        final generation = _generation;
        if (_loading && _loadedIndexes.isEmpty) {
          await _staticFuture;
          if (_disposed || generation != _generation) return;
        }
        cancelCatalog();
        _error = null;
        if (_loadedIndexes.isEmpty) {
          _query = q;
          _tag = t;
          _entries = _filter(_cachedEntries, q, t);
        } else {
          _applyStaticFilter(q, t);
        }
        _notify();
        return;
      }
      return _staticCatalog(q, t, append: append, force: force);
    }

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
          await _pruneCatalogCaches(prefs);
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

  /// Keep a small number of source-specific catalog snapshots. Source URLs
  /// and paths are part of the cache key, so changing them repeatedly would
  /// otherwise leave one full index in SharedPreferences for every old config.
  Future<void> _pruneCatalogCaches(SharedPreferences prefs) async {
    final keys = prefs
        .getKeys()
        .where((key) =>
            key.startsWith('story_catalog_cache_v1_') &&
            !key.contains('_package_'))
        .toList()
      ..sort();
    final keep = <String>{_cacheKey};
    for (final key in keys.reversed) {
      if (keep.length >= 5) break;
      keep.add(key);
    }
    for (final key in keys) {
      if (!keep.contains(key)) await prefs.remove(key);
    }
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
    if (_config.type != StorySourceType.server && _loadedIndexes.isNotEmpty) {
      cancelCatalog();
      _applyStaticFilter('', '');
      _error = null;
      _notify();
      return;
    }
    if (_cachedEntries.isEmpty) return;
    cancelCatalog();
    _entries = _cachedEntries;
    _query = '';
    _tag = '';
    _error = null;
    _usingCache = true;
    _notify();
  }

  Future<void> retryCatalog({String? query, String? tag}) {
    if (_config.type != StorySourceType.server) {
      return _staticCatalog(query?.trim() ?? '', tag?.trim() ?? '',
          append: _failedAppend, selected: _failedIndexSelection);
    }
    return loadCatalog(query: query, tag: tag, append: _failedAppend);
  }

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
                filePath: StoryService.staticFilePath(source, uri),
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
    if (q.isEmpty && t.isEmpty) return values;
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
