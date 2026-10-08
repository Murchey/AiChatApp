import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/story_package.dart';
import '../services/story_service.dart';

class StoryProvider extends ChangeNotifier {
  static const _configKey = 'story_community_source_v1';

  StorySourceConfig _config = const StorySourceConfig();
  List<StoryCatalogEntry> _entries = const [];
  bool _loading = false;
  String? _error;
  Future<void>? _initFuture;

  StorySourceConfig get config => _config;
  List<StoryCatalogEntry> get entries => List.unmodifiable(_entries);
  bool get loading => _loading;
  String? get error => _error;
  bool get supportsServerStats => _config.type == StorySourceType.server;

  /// Whether the current source has enough information to make a request.
  /// The default configuration intentionally stays offline until the user
  /// supplies an address or repository.
  bool get isConfigured {
    switch (_config.type) {
      case StorySourceType.server:
        return _config.baseUrl.trim().isNotEmpty;
      case StorySourceType.cos:
        return _config.indexUrl.trim().isNotEmpty ||
            _config.baseUrl.trim().isNotEmpty;
      case StorySourceType.github:
      case StorySourceType.gitee:
        return _config.indexUrl.trim().isNotEmpty ||
            _config.repository.trim().isNotEmpty;
    }
  }

  Future<void> init() async {
    _initFuture ??= _loadConfig();
    await _initFuture;
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _config = StorySourceConfig.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
      } catch (_) {
        _config = const StorySourceConfig();
      }
    }
    notifyListeners();
  }

  Future<void> saveConfig(StorySourceConfig config) async {
    _config = config;
    _entries = const [];
    _error = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  Future<void> loadCatalog({String? query, String? tag}) async {
    if (_loading) return;
    if (!isConfigured) {
      _entries = const [];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final decoded = await _loadCatalogJson(query: query, tag: tag);
      final list = decoded is Map
          ? (decoded['stories'] as List<dynamic>? ?? const [])
          : decoded is List
              ? decoded
              : const <dynamic>[];
      _entries = list
          .whereType<Map>()
          .map((value) =>
              StoryCatalogEntry.fromJson(value.cast<String, dynamic>()))
          .where((entry) => entry.storyId.isNotEmpty && entry.title.isNotEmpty)
          .toList(growable: false);
      if (_config.type != StorySourceType.server) {
        final q = query?.trim().toLowerCase() ?? '';
        final t = tag?.trim().toLowerCase() ?? '';
        _entries = _entries.where((entry) {
          final matchesQuery = q.isEmpty ||
              entry.title.toLowerCase().contains(q) ||
              entry.summary.toLowerCase().contains(q) ||
              entry.tags.any((value) => value.toLowerCase().contains(q));
          final matchesTag =
              t.isEmpty || entry.tags.any((value) => value.toLowerCase() == t);
          return matchesQuery && matchesTag;
        }).toList(growable: false);
      }
    } catch (e) {
      _error = readableError(e);
      _entries = const [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<StoryPackage> loadPackage(StoryCatalogEntry entry) async {
    try {
      final dynamic decoded;
      if (_config.type == StorySourceType.server) {
        decoded = await StoryService.getJson(
          StoryService.serverUri(_config,
              'api/stories/${Uri.encodeComponent(entry.storyId)}/download'),
          token: _config.token,
        );
      } else {
        final indexUri = StoryService.staticIndexUri(_config);
        decoded = await StoryService.getJson(
          StoryService.resolveStaticFile(indexUri, entry.file),
        );
      }
      if (decoded is! Map) throw const FormatException('故事详情格式无效');
      return StoryPackage.fromJson(decoded.cast<String, dynamic>());
    } catch (e) {
      throw Exception(readableError(e));
    }
  }

  Future<void> testConnection() async {
    if (!isConfigured) {
      throw const FormatException('请先填写故事来源地址');
    }
    if (_config.type == StorySourceType.server) {
      await StoryService.getJson(
        StoryService.serverUri(_config, 'api/health'),
        token: _config.token,
      );
      return;
    }
    await StoryService.getJson(StoryService.staticIndexUri(_config));
  }

  Future<dynamic> _loadCatalogJson({String? query, String? tag}) {
    if (_config.type == StorySourceType.server) {
      final uri = StoryService.serverUri(_config, 'api/stories');
      final params = <String, String>{
        if (query?.trim().isNotEmpty == true) 'q': query!.trim(),
        if (tag?.trim().isNotEmpty == true) 'tag': tag!.trim(),
      };
      return StoryService.getJson(
        params.isEmpty ? uri : uri.replace(queryParameters: params),
        token: _config.token,
      );
    }
    return StoryService.getJson(StoryService.staticIndexUri(_config));
  }

  /// Converts transport/configuration exceptions into text suitable for a
  /// toast or an inline page error. Keep raw timeout details out of the UI.
  String readableError(Object error) {
    if (error is TimeoutException) {
      return '故事来源请求超时，请检查地址、端口或网络';
    }
    if (error is SocketException || error is HandshakeException) {
      return '无法连接故事来源，请检查地址和端口';
    }
    if (error is HttpException) {
      return error.message.isEmpty ? '故事来源请求失败' : error.message;
    }
    if (error is FormatException) {
      return error.message.isEmpty ? '故事来源配置或 JSON 格式无效' : error.message;
    }
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? '故事社区请求失败，请检查来源配置' : text;
  }
}
