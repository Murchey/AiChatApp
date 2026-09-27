import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

/// 电脑端局域网同步接收服务（HttpServer）。
///
/// 手机 AiChat「局域网同步」填入电脑 IP:端口 与配对码后 POST 备份包，
/// 本服务校验配对码并写入本地备份目录（可选自动恢复）。
class DesktopSyncServer {
  HttpServer? _server;
  String _pairCode = '';
  int _port = 8765;
  final List<String> logs = [];
  final List<Map<String, dynamic>> received = [];
  bool autoRestoreLast = false;

  static const _pairKey = 'desktop_sync_pair_code';
  static const _portKey = 'desktop_sync_port';

  bool get isRunning => _server != null;
  int get port => _port;
  String get pairCode => _pairCode;
  List<String> get logLines => List.unmodifiable(logs);

  void _log(String message) {
    final line =
        '[${DateTime.now().toString().substring(11, 19)}] $message';
    logs.add(line);
    if (logs.length > 100) logs.removeRange(0, logs.length - 100);
    debugPrint('[DesktopSync] $message');
  }

  /// 生成/读取配对码
  Future<String> ensurePairCode() async {
    final prefs = await SharedPreferences.getInstance();
    var code = prefs.getString(_pairKey) ?? '';
    if (code.length != 6) {
      code = (100000 + DateTime.now().millisecondsSinceEpoch % 900000)
          .toString();
      await prefs.setString(_pairKey, code);
    }
    _pairCode = code;
    return code;
  }

  Future<void> resetPairCode() async {
    final prefs = await SharedPreferences.getInstance();
    _pairCode = (100000 + DateTime.now().millisecondsSinceEpoch % 900000)
        .toString();
    await prefs.setString(_pairKey, _pairCode);
    _log('配对码已重置为 $_pairCode');
  }

  /// 本机局域网 IP 列表
  static Future<List<String>> localIps() async {
    final result = <String>[];
    try {
      for (final iface in await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      )) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) result.add(addr.address);
        }
      }
    } catch (e) {
      debugPrint('[DesktopSync] list ip failed: $e');
    }
    return result;
  }

  /// 启动监听
  Future<void> start({int? port}) async {
    await stop();
    await ensurePairCode();
    final prefs = await SharedPreferences.getInstance();
    _port = port ?? prefs.getInt(_portKey) ?? 8765;
    if (port != null) await prefs.setInt(_portKey, port);

    _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    _log('接收服务已启动 0.0.0.0:$_port · 配对码 $_pairCode');

    _server!.listen((request) async {
      try {
        await _handle(request);
      } catch (e, st) {
        _log('处理请求失败: $e');
        debugPrint('[DesktopSync] $st');
        try {
          request.response.statusCode = 500;
          request.response.write(jsonEncode({'ok': false, 'error': '$e'}));
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
      _log('接收服务已停止');
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method.toUpperCase();

    if (method == 'GET' && (path == '/' || path == '/api/status')) {
      final ips = await localIps();
      await _json(request, 200, {
        'ok': true,
        'app': 'AiChat Desktop',
        'port': _port,
        'pairCode': _pairCode,
        'ips': ips,
        'received': received,
        'logs': logs,
      });
      return;
    }

    if (method == 'POST' && path == '/api/sync') {
      final pair = (request.headers.value('x-pair-code') ??
              request.uri.queryParameters['pair'] ??
              '')
          .trim();
      final name =
          (request.uri.queryParameters['name'] ?? 'phone_backup.zip').trim();
      final kind = (request.uri.queryParameters['kind'] ?? 'sync').trim();
      if (pair != _pairCode) {
        _log('配对失败：配对码不匹配');
        await _json(request, 403, {'ok': false, 'error': 'pair code mismatch'});
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
      }
      if (bytes.length < 16) {
        await _json(request, 400, {'ok': false, 'error': 'empty payload'});
        return;
      }
      final file = await BackupService.importBackupFromPath(
        await _writeTemp(name, bytes),
        displayName: name,
      );
      received.insert(0, {
        'name': file.path.split(RegExp(r'[/\\]')).last,
        'size': bytes.length,
        'kind': kind,
        'time': DateTime.now().toString().substring(0, 16),
      });
      if (received.length > 50) received.removeRange(50, received.length);
      _log('已接收 ${file.path.split(RegExp(r'[/\\]')).last}（${bytes.length} 字节 · $kind）');
      if (autoRestoreLast) {
        try {
          await BackupService.restoreLocalBackup(file);
          _log('已自动恢复最新备份');
        } catch (e) {
          _log('自动恢复失败: $e');
        }
      }
      await _json(request, 200, {
        'ok': true,
        'file': file.path.split(RegExp(r'[/\\]')).last,
        'size': bytes.length,
      });
      return;
    }

    await _json(request, 404, {'ok': false, 'error': 'not found'});
  }

  Future<String> _writeTemp(String name, List<int> bytes) async {
    final safe = name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final tmp = File(
      '${Directory.systemTemp.path}/aichat_sync_${DateTime.now().millisecondsSinceEpoch}_$safe',
    );
    await tmp.writeAsBytes(bytes, flush: true);
    return tmp.path;
  }

  Future<void> _json(
    HttpRequest request,
    int code,
    Map<String, dynamic> payload,
  ) async {
    final body = utf8.encode(jsonEncode(payload));
    request.response.statusCode = code;
    request.response.headers.contentType =
        ContentType('application', 'utf-8', charset: 'utf-8');
    request.response.headers.contentLength = body.length;
    request.response.add(body);
    await request.response.close();
  }

  /// 连接信息文案（给手机填写）
  Future<String> describeEndpoint() async {
    final ips = await localIps();
    final ip = ips.isNotEmpty ? ips.first : '127.0.0.1';
    return 'IP:端口  $ip:$_port\n配对码  $_pairCode';
  }
}

/// 进程内单例
final DesktopSyncServer desktopSyncServer = DesktopSyncServer();
