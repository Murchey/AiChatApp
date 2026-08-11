import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub 仓库信息：发布 Release 并附带 APK 后即可自动检查更新
const String kGitHubOwner = 'Murchey';
const String kGitHubRepo = 'AiChatApp';
const String kGitHubRepoUrl = 'https://github.com/Murchey/AiChatApp';

/// 内置的 GitHub 加速代理源（与学习项目 Example 保持一致）
const List<String> kProxySources = [
  'https://gh-proxy.org/',
  'https://v4.gh-proxy.org/',
  'https://cdn.gh-proxy.org/',
];

/// 更新信息
class UpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;

  const UpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
  });
}

/// 应用自动更新服务：
/// 1. 检查 GitHub 最新 Release 版本（[checkForUpdate]）
/// 2. 下载新版 APK 到应用外部文件目录（[downloadApk]，带进度回调）
/// 3. 通过原生 FileProvider 触发系统安装（[installApk]）
class UpdateService {
  static const MethodChannel _channel = MethodChannel('com.aichat.ai_chat/files');

  /// 检查 GitHub 最新 Release 是否有新版本，无更新/失败返回 null。
  /// [proxyUrl] 非空时通过加速代理前缀访问 GitHub API。
  static Future<UpdateInfo?> checkForUpdate({String proxyUrl = ''}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // 例如 1.0.0

      var apiUrl =
          'https://api.github.com/repos/$kGitHubOwner/$kGitHubRepo/releases/latest';
      if (proxyUrl.isNotEmpty) apiUrl = '$proxyUrl$apiUrl';
      final uri = Uri.parse(apiUrl);
      final resp = await http
          .get(uri, headers: {'Accept': 'application/vnd.github.v3+json'})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] as String?) ?? '';
      if (tagName.isEmpty) return null;
      final latestVersion = tagName.replaceFirst(RegExp(r'^[vV]'), '');
      final releaseNotes = (json['body'] as String?) ?? '';

      // 优先取 Release 资产里的 APK 直链；无资产时按 GitHub 下载地址规则拼接
      String? downloadUrl;
      final assets = json['assets'] as List? ?? [];
      for (final asset in assets) {
        final a = asset as Map<String, dynamic>;
        final name = a['name']?.toString() ?? '';
        if (name.endsWith('.apk')) {
          downloadUrl = a['browser_download_url']?.toString();
          break;
        }
      }
      downloadUrl ??=
          'https://github.com/$kGitHubOwner/$kGitHubRepo/releases/download/$tagName/app.apk';

      if (!_isNewerVersion(latestVersion, currentVersion)) return null;
      return UpdateInfo(
        latestVersion: latestVersion,
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// 下载 APK 到 外部文件目录/updates 下，实时回报进度（0.0~1.0）。
  /// [proxyUrl] 非空时通过加速代理前缀下载。
  /// 返回 APK 绝对路径，失败返回 null。
  static Future<String?> downloadApk({
    required String downloadUrl,
    required String version,
    String proxyUrl = '',
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await getExternalStorageDirectory();
      final updatesDir = Directory('${dir?.path}/updates');
      if (!updatesDir.existsSync()) updatesDir.createSync(recursive: true);
      final file = File('${updatesDir.path}/app-v$version.apk');

      // 已存在完整文件则跳过下载
      if (file.existsSync() && file.lengthSync() > 0) return file.path;

      final finalUrl = proxyUrl.isNotEmpty ? '$proxyUrl$downloadUrl' : downloadUrl;
      final request = http.Request('GET', Uri.parse(finalUrl));
      final resp = await http.Client().send(request);
      if (resp.statusCode != 200) return null;

      final total = resp.contentLength;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0 && onProgress != null) {
            onProgress((received / total).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.close();
      }

      if (file.lengthSync() == 0) return null;
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 触发系统安装（原生 FileProvider + ACTION_VIEW）
  static Future<void> installApk(String path) async {
    try {
      await _channel.invokeMethod('installApk', {'path': path});
    } catch (_) {}
  }

  /// 简单的语义化版本号比较：latest > current 返回 true
  static bool _isNewerVersion(String latest, String current) {
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = l.length > c.length ? l.length : c.length;
    for (var i = 0; i < len; i++) {
      final a = i < l.length ? l[i] : 0;
      final b = i < c.length ? c[i] : 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false;
  }
}
