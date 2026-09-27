import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'backup_service.dart';

/// 局域网同步：手机 → 电脑（AiChat 桌面版 desktop_server）。
///
/// 协议：HTTP，IP + 端口 + 配对码。
/// 兼容手机热点：双方在同一局域网（含热点网段）即可。
class LanSyncService {
  /// 连接目标：主机（IP）与端口
  static Uri buildUri({
    required String host,
    required int port,
    required String path,
    Map<String, String>? query,
  }) {
    return Uri(
      scheme: 'http',
      host: host.trim(),
      port: port,
      path: path,
      queryParameters: query,
    );
  }

  /// 解析用户输入的 `IP:端口` 或 `http://IP:端口`
  static ({String host, int port})? parseEndpoint(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (s.contains('://')) {
      final uri = Uri.tryParse(s);
      if (uri == null || uri.host.isEmpty) return null;
      final port = uri.hasPort ? uri.port : 80;
      return (host: uri.host, port: port);
    }
    // IPv4:port / hostname:port
    final idx = s.lastIndexOf(':');
    if (idx <= 0 || idx == s.length - 1) return null;
    final host = s.substring(0, idx).trim();
    final port = int.tryParse(s.substring(idx + 1).trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
    return (host: host, port: port);
  }

  /// 探测桌面服务状态；返回服务说明与配对码是否匹配。
  static Future<Map<String, dynamic>> fetchStatus({
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final uri = buildUri(host: host, port: port, path: '/api/status');
    final resp = await http.get(uri).timeout(timeout);
    if (resp.statusCode != 200) {
      throw HttpException('桌面服务返回 HTTP ${resp.statusCode}');
    }
    final map = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return map;
  }

  /// 将本地备份文件发送到电脑。
  /// [file] 为应用备份目录中的 zip。
  static Future<void> sendBackupFile({
    required String host,
    required int port,
    required String pairCode,
    required File file,
    String kind = 'local',
    void Function(double progress, String stage)? onProgress,
  }) async {
    onProgress?.call(0.05, '读取备份文件');
    if (!await file.exists()) {
      throw StateError('备份文件不存在');
    }
    final bytes = await file.readAsBytes();
    await sendBackupBytes(
      host: host,
      port: port,
      pairCode: pairCode,
      fileName: file.path.split(RegExp(r'[/\\]')).last,
      bytes: bytes,
      kind: kind,
      onProgress: onProgress,
    );
  }

  /// 发送备份字节到电脑端 `/api/sync`。
  static Future<void> sendBackupBytes({
    required String host,
    required int port,
    required String pairCode,
    required String fileName,
    required Uint8List bytes,
    String kind = 'local',
    void Function(double progress, String stage)? onProgress,
  }) async {
    final pair = pairCode.trim();
    if (pair.isEmpty) {
      throw StateError('请输入电脑端显示的配对码');
    }
    onProgress?.call(0.15, '连接电脑端 $host:$port');
    final uri = buildUri(
      host: host,
      port: port,
      path: '/api/sync',
      query: {
        'name': fileName,
        'kind': kind,
      },
    );
    final request = http.Request('POST', uri)
      ..headers['X-Pair-Code'] = pair
      ..headers['Content-Type'] = 'application/octet-stream'
      ..bodyBytes = bytes;
    onProgress?.call(0.35, '上传备份包');

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(
        const Duration(minutes: 5),
      );
      final resp = await http.Response.fromStream(streamed).timeout(
        const Duration(minutes: 5),
      );
      if (resp.statusCode == 403) {
        throw StateError('配对码错误，请核对电脑端显示的配对码');
      }
      if (resp.statusCode != 200) {
        final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
        throw StateError('同步失败 HTTP ${resp.statusCode}：$body');
      }
      onProgress?.call(1, '同步完成');
    } finally {
      client.close();
    }
  }

  /// 一键：导出最新全量备份并发送到电脑（用于「发送当前数据」）。
  static Future<void> exportAndSend({
    required String host,
    required int port,
    required String pairCode,
    void Function(double progress, String stage)? onProgress,
  }) async {
    onProgress?.call(0.02, '打包当前数据');
    final export = await BackupService.exportBackupZip(
      fileNamePrefix: 'aichat_sync',
      onProgress: (p, stage) => onProgress?.call(p * 0.55, stage),
    );
    await sendBackupBytes(
      host: host,
      port: port,
      pairCode: pairCode,
      fileName: export.fileName,
      bytes: export.bytes,
      kind: 'export',
      onProgress: (p, stage) => onProgress?.call(0.55 + p * 0.45, stage),
    );
  }
}
