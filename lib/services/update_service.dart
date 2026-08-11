import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Gitee 仓库信息（国内下载源，更新时优先选择）
const String kGiteeOwner = 'Murchey';
const String kGiteeRepo = 'AiChatApp';
const String kGiteeRepoUrl = 'https://gitee.com/Murchey/AiChatApp';

/// GitHub 仓库信息（备用下载源）
const String kGitHubOwner = 'Murchey';
const String kGitHubRepo = 'AiChatApp';
const String kGitHubRepoUrl = 'https://github.com/Murchey/AiChatApp';

/// Release 资产命名标准：AiChat-V1.0.0.apk
String kApkAssetName(String version) => 'AiChat-V$version.apk';

/// 内置的 GitHub 加速代理源（与学习项目 Example 保持一致）
const List<String> kProxySources = [
  'https://gh-proxy.org/',
  'https://v4.gh-proxy.org/',
  'https://cdn.gh-proxy.org/',
];

/// 更新信息（分别携带 Gitee / GitHub 两个下载源的直链）
class UpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final String giteeDownloadUrl; // 空串 = Gitee 源不可用
  final String githubDownloadUrl; // 空串 = GitHub 源不可用

  const UpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    this.giteeDownloadUrl = '',
    this.githubDownloadUrl = '',
  });
}

/// 应用自动更新服务：
/// 1. 检查最新 Release 版本（Gitee 优先，GitHub 备用，见 [checkForUpdate]）
/// 2. 下载新版 APK 到应用外部文件目录（[downloadApk]，带进度回调）
/// 3. 通过原生 FileProvider 触发系统安装（[installApk]）
class UpdateService {
  static const MethodChannel _channel = MethodChannel('com.aichat.ai_chat/files');

  /// 检查最新 Release 是否有新版本，无更新/失败返回 null。
  ///
  /// 检测顺序：Gitee（国内直连，首选）→ GitHub（备用，可通过 [proxyUrl] 加速）。
  /// 两个源都返回各自 Release 的 APK 直链，由更新弹窗的"下载源"选项卡选择。
  static Future<UpdateInfo?> checkForUpdate({String proxyUrl = ''}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // 例如 1.0.0

      // 1. Gitee 最新 Release（无需代理）
      final gitee = await _fetchRelease(
        apiUrl: 'https://gitee.com/api/v5/repos/$kGiteeOwner/$kGiteeRepo/releases/latest',
        downloadPrefix: '$kGiteeRepoUrl/releases/download',
        proxyUrl: '',
      );
      // 2. GitHub 最新 Release（可选代理加速）
      final github = await _fetchRelease(
        apiUrl: 'https://api.github.com/repos/$kGitHubOwner/$kGitHubRepo/releases/latest',
        downloadPrefix: '$kGitHubRepoUrl/releases/download',
        proxyUrl: proxyUrl,
      );

      if (gitee == null && github == null) return null;

      final latestVersion = gitee?.version ?? github!.version;
      // 更新说明优先抓取 GitHub 仓库 Release 的说明内容
      final releaseNotes =
          (github?.notes.isNotEmpty ?? false) ? github!.notes : (gitee?.notes ?? '');

      if (!_isNewerVersion(latestVersion, currentVersion)) return null;
      return UpdateInfo(
        latestVersion: latestVersion,
        releaseNotes: releaseNotes,
        giteeDownloadUrl: gitee?.downloadUrl ?? '',
        githubDownloadUrl: github?.downloadUrl ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// 请求单个源的最新 Release，解析出版本号、更新说明与 APK 直链。
  /// 失败（网络/非 200/无 tag）返回 null。
  static Future<({String version, String notes, String downloadUrl})?> _fetchRelease({
    required String apiUrl,
    required String downloadPrefix,
    required String proxyUrl,
  }) async {
    try {
      var url = apiUrl;
      if (proxyUrl.isNotEmpty) url = '$proxyUrl$url';
      final resp = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] as String?) ?? '';
      if (tagName.isEmpty) return null;
      final version = tagName.replaceFirst(RegExp(r'^[vV]'), '');
      final notes = (json['body'] as String?) ?? '';
      final expectedName = kApkAssetName(version);

      // 优先取符合命名标准（AiChat-V1.0.0.apk）的资产，其次任意 .apk 资产
      String? downloadUrl;
      final assets = json['assets'] as List? ?? [];
      for (final asset in assets) {
        final a = asset as Map<String, dynamic>;
        final name = a['name']?.toString() ?? '';
        if (name.toLowerCase() == expectedName.toLowerCase()) {
          downloadUrl = a['browser_download_url']?.toString();
          break;
        }
      }
      if (downloadUrl == null) {
        for (final asset in assets) {
          final a = asset as Map<String, dynamic>;
          final name = a['name']?.toString() ?? '';
          if (name.toLowerCase().endsWith('.apk')) {
            downloadUrl = a['browser_download_url']?.toString();
            break;
          }
        }
      }
      // 无资产时按命名标准拼接直链
      downloadUrl ??= '$downloadPrefix/$tagName/$expectedName';

      return (version: version, notes: notes, downloadUrl: downloadUrl);
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
      final file = File('${updatesDir.path}/${kApkAssetName(version)}');

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

  /// 清理更新目录中残留的安装包（.apk）。
  /// 安装完成后调用，或新版本每次启动时兜底清理，
  /// 避免安装包长期占用缓存空间。
  static Future<void> cleanupDownloadedApks() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final updatesDir = Directory('${dir.path}/updates');
      if (!updatesDir.existsSync()) return;
      for (final entry in updatesDir.listSync()) {
        if (entry is! File) continue;
        if (!entry.path.toLowerCase().endsWith('.apk')) continue;
        try {
          entry.deleteSync();
        } catch (_) {
          // 个别文件被占用时忽略，等下次启动再清
        }
      }
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
