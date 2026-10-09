import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/story_package.dart';
import 'cos_auth.dart';

class StoryService {
  const StoryService._();

  /// Story sources are user-configured external addresses. Keep an unreachable
  /// source from blocking the community page for the full platform timeout.
  static const requestTimeout = Duration(seconds: 8);

  static Future<dynamic> getJson(
    Uri uri, {
    String token = '',
    CosAuth? auth,
    Duration? requestTimeout,
  }) async {
    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
        ...?auth == null || !auth.isConfigured
            ? null
            : buildCosAuthHeaders(
                method: 'GET',
                uri: uri,
                accessKeyId: auth.accessKeyId,
                secretAccessKey: auth.secretAccessKey),
      },
    ).timeout(
      requestTimeout ?? StoryService.requestTimeout,
      onTimeout: () => throw TimeoutException(
        '故事来源请求超时，请检查地址、端口或网络',
        requestTimeout ?? StoryService.requestTimeout,
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('请求失败（HTTP ${response.statusCode}）');
    }
    try {
      return decodeJsonText(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const FormatException('服务器返回的 JSON 无法解析');
    }
  }

  /// Reads a public GitHub/Gitee file. Raw endpoints are fast when reachable,
  /// but are often blocked independently of the normal repository website.
  /// Fall back to the platform Contents API and decode its base64 payload.
  static Future<dynamic> getStaticJson(
    StorySourceConfig config,
    Uri uri, {
    required String filePath,
    Duration? requestTimeout,
  }) async {
    Object? lastError;
    try {
      return await getJson(uri,
          auth: _authFor(config), requestTimeout: requestTimeout);
    } catch (error) {
      lastError = error;
    }
    if (config.type != StorySourceType.github &&
        config.type != StorySourceType.gitee) {
      throw lastError;
    }
    for (final alternate in _alternateStaticUris(config, filePath)) {
      try {
        return await getJson(alternate, requestTimeout: requestTimeout);
      } catch (error) {
        lastError = error;
      }
    }
    final apiUri = _contentsApiUri(config, filePath);
    if (apiUri != null) {
      try {
        final decoded = await getJson(apiUri, requestTimeout: requestTimeout);
        if (decoded is! Map || decoded['content'] == null) {
          throw const FormatException('仓库 API 未返回文件内容');
        }
        final encoded =
            decoded['content'].toString().replaceAll(RegExp(r'\s'), '');
        final text = utf8.decode(base64.decode(base64.normalize(encoded)));
        return decodeJsonText(text);
      } catch (error) {
        lastError = error;
      }
    }
    throw FormatException('故事来源返回内容无法解析：$lastError');
  }

  static List<Uri> _alternateStaticUris(
    StorySourceConfig config,
    String filePath,
  ) {
    var repository = config.repository.trim().replaceAll(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(repository);
    if (parsed != null && parsed.host.isNotEmpty) {
      repository = parsed.path.replaceFirst(RegExp(r'^/+'), '');
    }
    final parts = repository.split('/').where((v) => v.isNotEmpty).toList();
    if (parts.length < 2) return const [];
    final owner = parts[0];
    final repo = parts[1].replaceFirst(RegExp(r'\.git$'), '');
    final branch = config.branch.trim().isEmpty ? 'main' : config.branch.trim();
    final path = filePath.trim().replaceFirst(RegExp(r'^/+'), '');
    if (path.isEmpty) return const [];
    if (config.type == StorySourceType.github) {
      return [
        Uri.https('github.com', '/$owner/$repo/raw/refs/heads/$branch/$path'),
      ];
    }
    return [Uri.https('gitee.com', '/$owner/$repo/raw/$branch/$path')];
  }

  static Uri? _contentsApiUri(StorySourceConfig config, String filePath) {
    var repository = config.repository.trim().replaceAll(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(repository);
    if (parsed != null && parsed.host.isNotEmpty) {
      repository = parsed.path.replaceFirst(RegExp(r'^/+'), '');
    }
    final parts = repository.split('/').where((v) => v.isNotEmpty).toList();
    if (parts.length < 2) return null;
    final owner = parts[0];
    final repo = parts[1].replaceFirst(RegExp(r'\.git$'), '');
    final branch = config.branch.trim().isEmpty ? 'main' : config.branch.trim();
    final path = filePath.trim().replaceFirst(RegExp(r'^/+'), '');
    if (path.isEmpty) return null;
    final host =
        config.type == StorySourceType.gitee ? 'gitee.com' : 'api.github.com';
    final apiPath = config.type == StorySourceType.gitee
        ? '/api/v5/repos/$owner/$repo/contents/$path'
        : '/repos/$owner/$repo/contents/$path';
    return Uri.https(host, apiPath, {
      'ref': branch,
    });
  }

  /// Decodes JSON returned by static story sources. Some Windows editors and
  /// object-storage upload tools prepend a UTF-8 BOM; JSON parsers reject that
  /// marker even though the document itself is valid UTF-8.
  static dynamic decodeJsonText(String text) {
    var normalized = text.trimLeft();
    if (normalized.startsWith('\uFEFF')) {
      normalized = normalized.substring(1).trimLeft();
    }
    try {
      return jsonDecode(normalized);
    } catch (_) {
      // AiChatStories legacy files omit the outer opening brace and start
      // directly with a quoted property ("schemaVersion": ...).
      if (normalized.startsWith('"') && normalized.endsWith('}')) {
        try {
          return jsonDecode('{$normalized');
        } catch (_) {}
      }
      // Some repository editors save JSON inside a Markdown code block.
      // Strip only an outer fence; the normal strict JSON path stays first.
      final fenced = RegExp(
        r'^```(?:json)?\s*([\s\S]*?)\s*```\s*$',
        caseSensitive: false,
      ).firstMatch(normalized);
      if (fenced != null) return decodeJsonText(fenced.group(1)!);
      final start = normalized.indexOf(RegExp(r'[\[{]'));
      final end = normalized.lastIndexOf(RegExp(r'[\]}]'));
      if (start >= 0 && end > start) {
        return jsonDecode(normalized.substring(start, end + 1));
      }
      rethrow;
    }
  }

  static Uri serverUri(StorySourceConfig config, String path) {
    var raw = config.baseUrl.trim();
    if (raw.isEmpty) throw const FormatException('请先填写服务器地址');
    if (!raw.contains('://')) raw = 'http://$raw';
    var uri = Uri.parse(raw);
    if (config.port.trim().isNotEmpty && !uri.hasPort) {
      final port = int.tryParse(config.port.trim());
      if (port == null || port < 1 || port > 65535) {
        throw const FormatException('端口号无效');
      }
      uri = uri.replace(port: port);
    }
    final basePath = uri.path.replaceAll(RegExp(r'/+$'), '');
    return uri.replace(
        path: '$basePath/${path.replaceFirst(RegExp(r'^/+'), '')}');
  }

  static Uri staticIndexUri(StorySourceConfig config) {
    if (config.indexUrl.trim().isNotEmpty) {
      final direct = Uri.parse(config.indexUrl.trim());
      return _normalizeGitFileUri(direct) ?? direct;
    }
    if (config.type == StorySourceType.cos) {
      var base = config.baseUrl.trim();
      if (base.isEmpty) throw const FormatException('请填写 COS / OSS 公共地址');
      if (!base.contains('://')) base = 'https://$base';
      final path = _cosPath(config, 'index.json', base: base);
      return Uri.parse(
          '${base.replaceAll(RegExp(r'/+$'), '')}/${path.replaceFirst(RegExp(r'^/+'), '')}');
    }
    final repo = config.repository.trim();
    if (repo.isEmpty) throw const FormatException('请填写仓库地址');
    final branch = config.branch.trim().isEmpty ? 'main' : config.branch.trim();
    final path = config.path.trim().isEmpty ? 'index.json' : config.path.trim();
    final normalized = repo.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    String ownerRepo;
    String host;
    if (uri != null && uri.host.isNotEmpty) {
      host = uri.host.toLowerCase();
      ownerRepo = uri.path
          .replaceFirst(RegExp(r'^/+'), '')
          .replaceAll(RegExp(r'/+$'), '');
    } else {
      host = config.type == StorySourceType.gitee ? 'gitee.com' : 'github.com';
      ownerRepo = normalized.replaceFirst(RegExp(r'^/+'), '');
    }
    final parts = ownerRepo.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.length < 2) {
      throw const FormatException('仓库地址应为 owner/repository');
    }
    final owner = parts[0];
    final repository = parts[1].replaceFirst(RegExp(r'\.git$'), '');
    if (uri != null && uri.host.isNotEmpty && parts.length >= 4) {
      final marker = parts[2].toLowerCase();
      if (marker == 'blob' || marker == 'raw') {
        final fileBranch = parts[3];
        final filePath = parts.skip(4).join('/');
        if (filePath.isNotEmpty) {
          return _gitRawUri(
            host,
            owner,
            repository,
            fileBranch,
            filePath,
          );
        }
      }
    }
    if (host.contains('gitee.com') || config.type == StorySourceType.gitee) {
      return Uri.parse(
        'https://gitee.com/$owner/$repository/raw/$branch/${path.replaceFirst(RegExp(r'^/+'), '')}',
      );
    }
    return Uri.parse(
      'https://raw.githubusercontent.com/$owner/$repository/$branch/${path.replaceFirst(RegExp(r'^/+'), '')}',
    );
  }

  static Uri? _normalizeGitFileUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!host.contains('github.com') && !host.contains('gitee.com')) {
      return null;
    }
    final parts =
        uri.path.split('/').where((value) => value.isNotEmpty).toList();
    if (parts.length < 5) return null;
    final marker = parts[2].toLowerCase();
    if (marker != 'blob' && marker != 'raw') return null;
    final repository = parts[1].replaceFirst(RegExp(r'\.git$'), '');
    final filePath = parts.skip(4).join('/');
    if (filePath.isEmpty) return null;
    return _gitRawUri(host, parts[0], repository, parts[3], filePath);
  }

  static Uri _gitRawUri(
    String host,
    String owner,
    String repository,
    String branch,
    String path,
  ) {
    if (host.contains('gitee.com')) {
      return Uri.https(
        'gitee.com',
        '/$owner/$repository/raw/$branch/$path',
      );
    }
    return Uri.https(
      'raw.githubusercontent.com',
      '/$owner/$repository/$branch/$path',
    );
  }

  static Uri resolveStaticFile(Uri indexUri, String file) {
    if (file.trim().isEmpty) throw const FormatException('故事条目缺少文件地址');
    final direct = Uri.tryParse(file.trim());
    if (direct != null && direct.hasScheme) return direct;
    return indexUri.resolve(file.trim());
  }

  static CosAuth? _authFor(StorySourceConfig config) {
    if (config.type != StorySourceType.cos ||
        config.secretId.trim().isEmpty ||
        config.secretKey.trim().isEmpty) {
      return null;
    }
    return CosAuth(
        enabled: true,
        accessKeyId: config.secretId,
        secretAccessKey: config.secretKey);
  }

  static String _cosPath(StorySourceConfig config, String fallback,
      {String? base}) {
    final prefix = config.storagePath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final configured = config.path.trim().replaceFirst(RegExp(r'^/+'), '');
    // Older configurations stored a complete object key in `path`.
    if (configured.isNotEmpty && configured != 'index.json') return configured;
    final file = fallback;
    // Keep legacy base URLs such as https://host/story/index.json working.
    if (base != null) {
      final parsed = Uri.tryParse(base);
      if (parsed != null && parsed.path.replaceAll('/', '').isNotEmpty) {
        return file;
      }
    }
    return [if (prefix.isNotEmpty) prefix, file].join('/');
  }
}
