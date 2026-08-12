import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/workshop_asset.dart';

/// 创意工坊仓库服务：检查仓库 Release tag 可用性、拉取资产 zip、下载 zip。
///
/// 角色卡仓库约定（[kCharacterPackTag] / [kGamePackTag]）：
///   V1.1.0 = 角色分类角色包（zip 内含 Profile.json 的角色文件夹）
///   V1.0.0 = 游戏分类角色包（zip 内含 moments.json 的朋友圈数据包）
/// 支持 GitHub 与 Gitee 仓库；检测与资产拉取直连官方 API，
/// 代理仅用于 zip 下载加速（仅对 GitHub 生效，Gitee 始终直连）。
class WorkshopService {
  /// 解析仓库路径为 owner/repo 与来源平台。
  ///
  /// 兼容 `owner/repo` 与完整 URL（https://github.com/owner/repo、https://gitee.com/owner/repo）。
  /// 返回 null 表示路径格式不正确。
  static ({String owner, String repo, bool isGitee})? parseRepoPath(
    String path,
  ) {
    var p = path.trim().replaceAll(RegExp(r'/+$'), '');
    if (p.isEmpty) return null;
    String? host;
    final uri = Uri.tryParse(p);
    if (uri != null && uri.host.isNotEmpty) {
      host = uri.host.toLowerCase();
      p = uri.path.replaceAll(RegExp(r'^/+'), '');
    }
    final segs = p.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.length < 2) return null;
    return (
      owner: segs[0],
      repo: segs[1],
      isGitee: host != null && host.contains('gitee.com'),
    );
  }

  /// 检查仓库可用的 Release tag：返回仓库中存在的支持 tag（V1.1.0 / V1.0.0）。
  /// 仓库路径不合法时抛出 [FormatException]，请求失败抛出网络异常。
  ///
  /// 检测通过官方 API 直连（代理仅用于下载，不用于检测）。
  static Future<List<String>> checkTags(String path) async {
    final parsed = parseRepoPath(path);
    if (parsed == null) {
      throw const FormatException('仓库路径格式不正确（需为 owner/repo 或完整仓库 URL）');
    }
    final releases = await _fetchReleases(
      owner: parsed.owner,
      repo: parsed.repo,
      isGitee: parsed.isGitee,
    );
    return kWorkshopPackTags.where(releases.containsKey).toList();
  }

  /// 列出仓库某 tag 下的 zip 资产（仅支持角色/游戏两个分类 tag）。
  /// 资产列表通过官方 API 直连拉取（代理仅用于下载，不用于拉取）。
  static Future<List<WorkshopAsset>> listAssets(
    String path,
    String tag,
  ) async {
    if (!kWorkshopPackTags.contains(tag)) return const [];
    final parsed = parseRepoPath(path);
    if (parsed == null) return const [];
    final releases = await _fetchReleases(
      owner: parsed.owner,
      repo: parsed.repo,
      isGitee: parsed.isGitee,
    );
    return releases[tag] ?? const [];
  }

  /// 请求仓库全部 Release，按 tag 分组解析出 zip 资产。
  /// 始终直连官方 API（GitHub / Gitee），不经过加速代理。
  static Future<Map<String, List<WorkshopAsset>>> _fetchReleases({
    required String owner,
    required String repo,
    required bool isGitee,
  }) async {
    final apiUrl = isGitee
        ? 'https://gitee.com/api/v5/repos/$owner/$repo/releases?per_page=100'
        : 'https://api.github.com/repos/$owner/$repo/releases?per_page=100';
    final resp = await http
        .get(Uri.parse(apiUrl), headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw HttpException('仓库请求失败（HTTP ${resp.statusCode}）');
    }

    final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    final result = <String, List<WorkshopAsset>>{};
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final tag = (map['tag_name'] as String?)?.trim() ?? '';
      if (tag.isEmpty || !kWorkshopPackTags.contains(tag)) continue;
      final assets = <WorkshopAsset>[];
      for (final a in (map['assets'] as List? ?? [])) {
        final am = a as Map<String, dynamic>;
        final name = am['name']?.toString() ?? '';
        if (!name.toLowerCase().endsWith('.zip')) continue;
        var downloadUrl = am['browser_download_url']?.toString() ?? '';
        // Gitee 资产记录无直链时按命名规范拼接
        if (downloadUrl.isEmpty && isGitee) {
          downloadUrl =
              'https://gitee.com/$owner/$repo/releases/download/$tag/$name';
        }
        if (downloadUrl.isEmpty) continue;
        assets.add(WorkshopAsset(
          tag: tag,
          name: name,
          downloadUrl: downloadUrl,
          sizeBytes: (am['size'] as num?)?.toInt(),
        ));
      }
      result[tag] = assets;
    }
    return result;
  }

  /// 下载 zip 到应用文档目录 workshop/ 下，实时回报进度（0.0~1.0）。
  /// [proxyUrl] 非空时通过加速代理前缀下载。返回本地绝对路径，失败返回 null。
  static Future<String?> downloadZip({
    required String downloadUrl,
    String proxyUrl = '',
    void Function(double progress)? onProgress,
  }) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final workshopDir = Directory('${docDir.path}/workshop');
      if (!workshopDir.existsSync()) workshopDir.createSync(recursive: true);

      final rawName = downloadUrl.split('/').last.split('?').first;
      final name = _safeFileName(Uri.decodeComponent(rawName));
      final file = File('${workshopDir.path}/$name');
      // 已存在完整文件则跳过下载
      if (file.existsSync() && file.lengthSync() > 0) return file.path;

      final finalUrl = proxyUrl.isNotEmpty ? '$proxyUrl$downloadUrl' : downloadUrl;
      final request = http.Request('GET', Uri.parse(finalUrl));
      final resp = await http.Client().send(request);
      if (resp.statusCode != 200) return null;

      // 先写入 .part 临时文件，下载完整后再改名发布
      final tmp = File('${workshopDir.path}/$name.part');
      final total = resp.contentLength;
      var received = 0;
      final sink = tmp.openWrite();
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

      if (tmp.lengthSync() == 0) {
        tmp.deleteSync();
        return null;
      }
      if (file.existsSync()) file.deleteSync();
      tmp.renameSync(file.path);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 删除下载缓存（导入完成后调用）：清理指定 zip 及残留的 .part 临时文件。
  /// 仅删除本次导入的 zip，不影响仓库资产列表。
  static void removeDownloadCache(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
      final part = File('$path.part');
      if (part.existsSync()) part.deleteSync();
    } catch (_) {}
  }

  /// 防止空名 / '.' / '..' 等非法文件名
  static String _safeFileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') {
      return 'zip_${DateTime.now().millisecondsSinceEpoch}.zip';
    }
    return trimmed;
  }
}
