import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/story_package.dart';

class StoryService {
  const StoryService._();

  /// Story sources are user-configured external addresses. Keep an unreachable
  /// source from blocking the community page for the full platform timeout.
  static const requestTimeout = Duration(seconds: 8);

  static Future<dynamic> getJson(
    Uri uri, {
    String token = '',
  }) async {
    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
      },
    ).timeout(
      requestTimeout,
      onTimeout: () => throw TimeoutException(
        '故事来源请求超时，请检查地址、端口或网络',
        requestTimeout,
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('请求失败（HTTP ${response.statusCode}）');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const FormatException('服务器返回的 JSON 无法解析');
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
      return Uri.parse(config.indexUrl.trim());
    }
    if (config.type == StorySourceType.cos) {
      var base = config.baseUrl.trim();
      if (base.isEmpty) throw const FormatException('请填写 COS / OSS 公共地址');
      if (!base.contains('://')) base = 'https://$base';
      final path =
          config.path.trim().isEmpty ? 'index.json' : config.path.trim();
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
    if (parts.length < 2)
      throw const FormatException('仓库地址应为 owner/repository');
    final owner = parts[0];
    final repository = parts[1].replaceFirst(RegExp(r'\.git$'), '');
    if (host.contains('gitee.com') || config.type == StorySourceType.gitee) {
      return Uri.parse(
        'https://gitee.com/$owner/$repository/raw/$branch/${path.replaceFirst(RegExp(r'^/+'), '')}',
      );
    }
    return Uri.parse(
      'https://raw.githubusercontent.com/$owner/$repository/$branch/${path.replaceFirst(RegExp(r'^/+'), '')}',
    );
  }

  static Uri resolveStaticFile(Uri indexUri, String file) {
    if (file.trim().isEmpty) throw const FormatException('故事条目缺少文件地址');
    final direct = Uri.tryParse(file.trim());
    if (direct != null && direct.hasScheme) return direct;
    return indexUri.resolve(file.trim());
  }
}
