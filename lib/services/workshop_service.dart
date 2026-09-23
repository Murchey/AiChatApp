import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import '../models/workshop_asset.dart';
import '../models/workshop_repository.dart';
import 'cos_auth.dart';

/// 仓库最新正式 Release 的可展示信息，用于通知预览而非资源包分类。
class LatestRepositoryRelease {
  const LatestRepositoryRelease({required this.tag, required this.body});

  final String tag;
  final String body;
}

/// 从官方 API 返回的 Release 列表中选择最靠前的正式发布。
LatestRepositoryRelease? latestPublishedReleaseFromJson(List<dynamic> releases) {
  for (final item in releases) {
    if (item is! Map) continue;
    final map = item.cast<String, dynamic>();
    if (map['draft'] == true || map['prerelease'] == true) continue;
    final tag = (map['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty) continue;
    final body = (map['body'] as String? ?? '').trim();
    final name = (map['name'] as String? ?? '').trim();
    return LatestRepositoryRelease(tag: tag, body: body.isEmpty ? name : body);
  }
  return null;
}

/// 创意工坊仓库服务：检查仓库 Release tag 可用性、拉取资产 zip、下载 zip。
///
/// 创意工坊仓库约定（[kCharacterPackTag] / [kGamePackTag] / [kStickerPackTag]）：
///   V1.1.0 = 角色分类角色包（zip 内含 Profile.json 的角色文件夹）
///   V1.0.0 = 游戏分类角色包（zip 内含 moments.json 的朋友圈数据包）
/// 支持 GitHub 与 Gitee 仓库；检测与资产拉取直连官方 API，
/// 代理仅用于 zip 下载加速（仅对 GitHub 生效，Gitee 始终直连）。
///
/// 另支持 COS 类对象储存（腾讯云 COS / 阿里云 OSS 等）：
/// 用户填写 BASE_URL，App 按固定目录约定自动发现资产。
/// 默认匿名 ListObjects + GetObject；可选访问密钥做私有读鉴权。
class WorkshopService {
  /// COS 目录约定：角色分类
  static const String kCosCharactersFolder = 'Characters';

  /// COS 目录约定：游戏分类
  static const String kCosGamesFolder = 'Games';

  /// COS 目录约定：表情包分类
  static const String kCosStickersFolder = 'Stickers';

  /// COS 目录约定：更新通知 Markdown
  static const String kCosNoteFolder = 'Note';

  /// ListObjects 结果内存缓存（短 TTL，避免同一会话内重复全量列举）
  static final Map<
      String,
      ({
        DateTime at,
        List<({String key, int size})> objects,
        bool complete,
      })> _cosListCache = {};
  static const Duration _cosListCacheTtl = Duration(minutes: 30);

  /// 首屏列表页大小（角色很多时只先拉一页）
  static const int kCosFirstPageSize = 500;

  /// 清除 COS 列表缓存（仓库刷新时调用）
  static void invalidateCosListCache([String? baseUrl]) {
    if (baseUrl == null) {
      _cosListCache.clear();
      return;
    }
    final key = _cosListCacheKey(baseUrl, null);
    _cosListCache.remove(key);
    _cosListCache.removeWhere((k, _) => k.startsWith('$key|'));
  }

  /// 该 BASE_URL 当前缓存（或最近一次 List）是否已取完全部对象。
  static bool cosListIsComplete(String baseUrl, {CosAuth? auth}) {
    final hit = _cosListCache[_cosListCacheKey(baseUrl, auth)];
    return hit?.complete ?? true;
  }

  static String _cosListCacheKey(String baseUrl, CosAuth? auth) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final ak = (auth?.isConfigured ?? false) ? auth!.accessKeyId.trim() : '';
    return '$base|$ak';
  }

  /// 是否像 COS 类对象储存 URL（完整 http(s) 且 host 非 GitHub / Gitee）。
  static bool looksLikeCosUrl(String input) {
    final s = input.trim();
    if (s.isEmpty) return false;
    final uri = Uri.tryParse(s);
    if (uri == null) return false;
    if (!uri.isScheme('http') && !uri.isScheme('https')) return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (host.contains('github.com') || host.contains('gitee.com')) {
      return false;
    }
    return true;
  }

  /// 解析 COS BASE_URL：列表打在桶根，路径前缀用于 ListObjects prefix。
  /// 返回 `(bucketRoot: scheme://host[:port], prefix: 无首尾斜杠的路径)`。
  static ({Uri bucketRoot, String prefix}) parseCosBaseUrl(String url) {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(trimmed);
    final path =
        uri.path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    final bucketRoot = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
    return (bucketRoot: bucketRoot, prefix: path);
  }

  /// COS 仓库显示名：`host/末级路径`（无路径时仅 host）。
  static String cosDisplayName(String url) {
    final parsed = parseCosBaseUrl(url);
    final host = parsed.bucketRoot.host;
    final segs =
        parsed.prefix.split('/').where((s) => s.isNotEmpty).toList(growable: false);
    if (segs.isEmpty) return host;
    return '$host/${segs.last}';
  }

  /// 检测输入应归为 Git 还是 COS 仓库。
  static WorkshopRepoType detectRepoType(String input) {
    final p = input.trim();
    if (p.isEmpty) return WorkshopRepoType.git;
    if (!p.contains('://')) return WorkshopRepoType.git;
    return looksLikeCosUrl(p) ? WorkshopRepoType.cos : WorkshopRepoType.git;
  }

  static Map<String, String> _cosHeaders(Uri uri, CosAuth? auth) {
    if (auth == null || !auth.isConfigured) return const {};
    return buildCosAuthHeaders(
      method: 'GET',
      uri: uri,
      accessKeyId: auth.accessKeyId,
      secretAccessKey: auth.secretAccessKey,
    );
  }

  static void _throwCosStatus(int status, String body, {CosAuth? auth}) {
    if (status == 403) {
      final usingAuth = auth?.isConfigured ?? false;
      final code = _cosErrorCode(body);
      throw HttpException(
        usingAuth
            ? '对象储存鉴权失败（HTTP 403${code.isEmpty ? '' : ' / $code'}）。'
                '请检查 SecretId/SecretKey 是否配对、密钥是否有效，'
                '以及子账号是否有 ListBucket / GetObject 权限。'
            : '对象储存拒绝匿名访问（HTTP 403${code.isEmpty ? '' : ' / $code'}）。'
                '可开启公有读，或在添加仓库时启用访问密钥做私有读。',
      );
    }
    throw HttpException('对象储存请求失败（HTTP $status）');
  }

  static String _cosErrorCode(String body) {
    try {
      final doc = XmlDocument.parse(body);
      for (final e in doc.descendantElements) {
        if (e.name.local == 'Code') return e.innerText.trim();
      }
    } catch (_) {}
    return '';
  }

  /// S3 ListObjects V2。
  ///
  /// [firstPageOnly] 为 true 时只取首页约 [kCosFirstPageSize] 条（打开分类用）；
  /// 为 false 时跟随 continuation-token 拉到取完或 [maxPages] 页（搜索/加载更多）。
  /// 完整列表优先复用缓存；首页缓存若已 complete 也会直接当全量返回。
  /// [force] 跳过缓存（用户手动刷新）。
  static Future<List<({String key, int size})>> listCosObjects(
    String baseUrl, {
    CosAuth? auth,
    bool force = false,
    bool firstPageOnly = false,
    int maxPages = 10,
  }) async {
    final cacheKey = _cosListCacheKey(baseUrl, auth);
    if (!force) {
      final hit = _cosListCache[cacheKey];
      if (hit != null &&
          DateTime.now().difference(hit.at) < _cosListCacheTtl) {
        // 全量请求：仅当缓存已完整时才可直接返回
        if (firstPageOnly || hit.complete) return hit.objects;
      }
    }

    final parsed = parseCosBaseUrl(baseUrl);
    final prefix = parsed.prefix.isEmpty ? '' : '${parsed.prefix}/';
    final pageSize = firstPageOnly ? kCosFirstPageSize : 1000;
    final pages = firstPageOnly ? 1 : maxPages;
    final result = <({String key, int size})>[];
    String? continuationToken;
    var truncated = false;

    for (var page = 0; page < pages; page++) {
      // 空 prefix / token 不可写入 queryParameters：Dart 会拼成 `prefix`（无 =），COS 返回 400
      final listUri = parsed.bucketRoot.replace(
        path: '/',
        queryParameters: {
          'list-type': '2',
          if (prefix.isNotEmpty) 'prefix': prefix,
          'max-keys': '$pageSize',
          if (continuationToken != null && continuationToken.isNotEmpty)
            'continuation-token': continuationToken,
        },
      );
      final resp = await http
          .get(listUri, headers: _cosHeaders(listUri, auth))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        _throwCosStatus(
          resp.statusCode,
          utf8.decode(resp.bodyBytes, allowMalformed: true),
          auth: auth,
        );
      }
      final doc = XmlDocument.parse(utf8.decode(resp.bodyBytes));
      result.addAll(_parseListBucketContents(doc));

      truncated = doc.descendantElements
          .any((e) => e.name.local == 'IsTruncated' && e.innerText.trim() == 'true');
      String? next;
      for (final e in doc.descendantElements) {
        if (e.name.local == 'NextContinuationToken') {
          next = e.innerText.trim();
          break;
        }
      }
      if (!truncated || next == null || next.isEmpty) {
        truncated = false;
        break;
      }
      continuationToken = next;
    }

    // 首页模式：若未截断则已完整；全量模式在 maxPages 打满且仍截断时视为不完整
    final complete = !truncated;
    _cosListCache[cacheKey] = (
      at: DateTime.now(),
      objects: result,
      complete: complete,
    );
    return result;
  }

  static List<({String key, int size})> _parseListBucketContents(
      XmlDocument doc) {
    final result = <({String key, int size})>[];
    // 按 local name 匹配，兼容带默认命名空间或前缀的 S3/COS 响应
    for (final content in doc.descendantElements) {
      if (content.name.local != 'Contents') continue;
      String? key;
      var size = 0;
      for (final child in content.childElements) {
        if (child.name.local == 'Key') {
          key = child.innerText.trim();
        } else if (child.name.local == 'Size') {
          size = int.tryParse(child.innerText.trim()) ?? 0;
        }
      }
      if (key == null || key.isEmpty) continue;
      result.add((key: key, size: size));
    }
    return result;
  }

  /// 探测 COS 四类目录是否含有效资产，返回可用 tag 列表。
  static Future<List<String>> checkCosFolders(
    String baseUrl, {
    CosAuth? auth,
    bool force = false,
  }) async {
    try {
      // 目录探测用首页即可：只需知道各分类是否有文件
      final objects = await listCosObjects(
        baseUrl,
        auth: auth,
        force: force,
        firstPageOnly: true,
      );
      final basePrefix = _cosBasePrefix(baseUrl);

      bool hasZip(String folder) =>
          _hasTopLevelFiles(objects, '$basePrefix$folder/', '.zip');
      bool hasMd(String folder) =>
          _hasTopLevelFiles(objects, '$basePrefix$folder/', '.md');

      return [
        if (hasZip(kCosCharactersFolder)) kCharacterPackTag,
        if (hasZip(kCosGamesFolder)) kGamePackTag,
        if (hasZip(kCosStickersFolder)) kStickerPackTag,
        if (hasMd(kCosNoteFolder)) kUpdateNotifyTag,
      ];
    } on HttpException catch (e) {
      // 匿名 List 失败时仍探测 Note；已配置密钥则不再匿名探测
      if ((auth?.isConfigured ?? false) || !e.message.contains('403')) {
        rethrow;
      }
      final tags = await _probeCosNoteTag(baseUrl);
      if (tags.isNotEmpty) return tags;
      rethrow;
    }
  }

  /// 探测固定 Note 文件名，返回可用 tag（仅在匿名 ListObjects 失败时使用）。
  static Future<List<String>> _probeCosNoteTag(String baseUrl) async {
    final basePrefix = _cosBasePrefix(baseUrl);
    for (final name in const ['update.md', 'note.md', 'readme.md']) {
      final key = '$basePrefix$kCosNoteFolder/$name';
      try {
        final url = Uri.parse(_cosDownloadUrl(baseUrl, key, basePrefix));
        final resp = await http
            .get(url)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          return const [kUpdateNotifyTag];
        }
      } catch (_) {}
    }
    return const [];
  }

  /// 列出 COS 某分类下的 zip 资产（downloadUrl = BASE_URL + 编码后的相对 Key）。
  /// [loadAll] 为 false 时仅用首页（约 500 条）过滤；为 true 时拉全量。
  static Future<List<WorkshopAsset>> listCosAssets(
    String baseUrl,
    String tag, {
    CosAuth? auth,
    bool loadAll = false,
  }) async {
    if (!kWorkshopPackTags.contains(tag)) return const [];
    final folder = switch (tag) {
      kCharacterPackTag => kCosCharactersFolder,
      kGamePackTag => kCosGamesFolder,
      kStickerPackTag => kCosStickersFolder,
      _ => null,
    };
    if (folder == null) return const [];

    final objects = await listCosObjects(
      baseUrl,
      auth: auth,
      firstPageOnly: !loadAll,
    );
    final basePrefix = _cosBasePrefix(baseUrl);
    final folderPrefix = '$basePrefix$folder/';
    final assets = <WorkshopAsset>[];
    for (final o in objects) {
      if (!o.key.startsWith(folderPrefix)) continue;
      final name = o.key.substring(folderPrefix.length);
      if (name.isEmpty || name.contains('/')) continue;
      if (!name.toLowerCase().endsWith('.zip')) continue;
      assets.add(WorkshopAsset(
        tag: tag,
        name: name,
        label: '',
        downloadUrl: _cosDownloadUrl(baseUrl, o.key, basePrefix),
        sizeBytes: o.size,
      ));
    }
    return assets;
  }

  /// 轻量探测 Note 文件（不 List 整桶）：按 update.md → note.md → readme.md 顺序 GET。
  /// 用于进分类前判断「通知内容是否变化」。找不到返回 null。
  static Future<String?> probeCosNote(
    String baseUrl, {
    CosAuth? auth,
  }) async {
    final basePrefix = _cosBasePrefix(baseUrl);
    for (final name in const ['update.md', 'note.md', 'readme.md']) {
      try {
        final body = await _getCosText(
          baseUrl,
          '$basePrefix$kCosNoteFolder/$name',
          auth: auth,
        );
        if (body != null && body.isNotEmpty) return body;
      } catch (_) {}
    }
    return null;
  }

  /// 归一化 Note 正文，避免换行/BOM 差异导致「内容未变却反复提醒」。
  static String normalizeCosNote(String body) {
    var s = body;
    if (s.startsWith('﻿')) s = s.substring(1);
    return s.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  }

  /// 拉取 COS Note 目录更新通知 Markdown 全文。
  ///
  /// 优先按固定文件名探测（update.md → note.md → readme.md），结果稳定；
  /// 都没有时再 List 目录取最后一个 `.md`（按 Key 排序，避免列举顺序抖动）。
  static Future<String?> fetchCosNote(
    String baseUrl, {
    CosAuth? auth,
  }) async {
    // 1) 固定文件名探测（私有读也走签名 GET，结果稳定）
    final probed = await probeCosNote(baseUrl, auth: auth);
    if (probed != null) return normalizeCosNote(probed);

    // 2) List 目录找其它 .md
    try {
      final objects = await listCosObjects(baseUrl, auth: auth);
      final basePrefix = _cosBasePrefix(baseUrl);
      final notePrefix = '$basePrefix$kCosNoteFolder/';

      final mdKeys = objects
          .where((o) =>
              o.key.startsWith(notePrefix) &&
              o.key.toLowerCase().endsWith('.md') &&
              !o.key.substring(notePrefix.length).contains('/'))
          .map((o) => o.key)
          .toList()
        ..sort();
      if (mdKeys.isEmpty) return null;

      final raw = await _getCosText(baseUrl, mdKeys.last, auth: auth);
      return raw == null || raw.isEmpty ? null : normalizeCosNote(raw);
    } on HttpException {
      // List 失败时再试一次带鉴权的固定名探测已做过；直接视为无通知
      return null;
    }
  }

  static Future<String?> _getCosText(
    String baseUrl,
    String key, {
    CosAuth? auth,
  }) async {
    final basePrefix = _cosBasePrefix(baseUrl);
    final uri = Uri.parse(_cosDownloadUrl(baseUrl, key, basePrefix));
    final resp = await http
        .get(uri, headers: _cosHeaders(uri, auth))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    return utf8.decode(resp.bodyBytes);
  }

  static String _cosBasePrefix(String baseUrl) {
    final prefix = parseCosBaseUrl(baseUrl).prefix;
    return prefix.isEmpty ? '' : '$prefix/';
  }

  static bool _hasTopLevelFiles(
    List<({String key, int size})> objects,
    String folderPrefix,
    String ext,
  ) {
    final lowerExt = ext.toLowerCase();
    for (final o in objects) {
      if (!o.key.startsWith(folderPrefix)) continue;
      final name = o.key.substring(folderPrefix.length);
      if (name.isEmpty || name.contains('/')) continue;
      if (name.toLowerCase().endsWith(lowerExt)) return true;
    }
    return false;
  }

  /// BASE_URL + 编码后的相对 Key（相对路径按 segment 做 encodeComponent）。
  static String _cosDownloadUrl(
    String baseUrl,
    String key,
    String basePrefix,
  ) {
    final relative =
        key.startsWith(basePrefix) ? key.substring(basePrefix.length) : key;
    final encoded =
        relative.split('/').map(Uri.encodeComponent).join('/');
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/$encoded';
  }

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

  /// 检查仓库可用的 Release tag：返回仓库中存在的支持 tag（含 V1.3.0 表情包）。
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
    // 检查所有支持的 tag，包括更新通知用的 V1.2.0
    final allTags = [...kWorkshopPackTags, kUpdateNotifyTag];
    return allTags.where(releases.containsKey).toList();
  }

  /// 列出仓库某 tag 下的 zip 资产（角色/游戏/表情包分类）。
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
    final resp = await http.get(Uri.parse(apiUrl), headers: {
      'Accept': 'application/json'
    }).timeout(const Duration(seconds: 15));
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
        final label = am['label']?.toString() ?? '';
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
          label: label,
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
  /// [auth] 非空且已配置时，对 COS 私有对象签名 GET（此时忽略代理）。
  static Future<String?> downloadZip({
    required String downloadUrl,
    String proxyUrl = '',
    CosAuth? auth,
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

      // 私有读签名时不能走加速代理（签名绑定原 host）
      final useAuth = auth?.isConfigured ?? false;
      final useProxy = !useAuth && proxyUrl.isNotEmpty;
      final finalUrl = useProxy ? '$proxyUrl$downloadUrl' : downloadUrl;
      final request = http.Request('GET', Uri.parse(finalUrl));
      if (useAuth) {
        request.headers.addAll(_cosHeaders(Uri.parse(finalUrl), auth));
      }
      final resp = await http.Client().send(request);
      if (resp.statusCode != 200) {
        debugPrint(
          '[WorkshopService] downloadZip HTTP ${resp.statusCode} '
          'url=$finalUrl useAuth=$useAuth',
        );
        return null;
      }

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

  /// 清除全部下载缓存：删除应用文档目录 workshop/ 下所有残留文件
  /// （下载失败的 .part 临时文件、导入被取消/中断未清理的 zip 等），
  /// 返回删除的文件数。仅清理下载缓存，不影响已导入的角色数据与朋友圈图片。
  static Future<int> clearDownloadCache() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final workshopDir = Directory('${docDir.path}/workshop');
      if (!workshopDir.existsSync()) return 0;
      var removed = 0;
      await for (final entity in workshopDir.list()) {
        try {
          if (entity is Directory) {
            entity.deleteSync(recursive: true);
          } else {
            entity.deleteSync();
          }
          removed++;
        } catch (_) {}
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }

  /// 获取指定 tag 的 release 描述内容（body）
  /// 用于更新通知，返回 null 表示 tag 不存在或请求失败
  static Future<String?> fetchReleaseBody(String path, String tag) async {
    final parsed = parseRepoPath(path);
    if (parsed == null) return null;

    final apiUrl = parsed.isGitee
        ? 'https://gitee.com/api/v5/repos/${parsed.owner}/${parsed.repo}/releases'
        : 'https://api.github.com/repos/${parsed.owner}/${parsed.repo}/releases';

    final resp = await http.get(Uri.parse(apiUrl), headers: {
      'Accept': 'application/json'
    }).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) return null;

    final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final tagName = (map['tag_name'] as String?)?.trim() ?? '';
      if (tagName == tag) {
        return (map['body'] as String?)?.trim() ?? '';
      }
    }
    return null;
  }

  /// 获取仓库最新正式 Release，用于开发者预览真实的仓库更新提示。
  static Future<LatestRepositoryRelease?> fetchLatestRelease(String path) async {
    final parsed = parseRepoPath(path);
    if (parsed == null) return null;
    final apiUrl = parsed.isGitee
        ? 'https://gitee.com/api/v5/repos/${parsed.owner}/${parsed.repo}/releases'
        : 'https://api.github.com/repos/${parsed.owner}/${parsed.repo}/releases';
    final resp = await http.get(Uri.parse(apiUrl), headers: {
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    return decoded is List ? latestPublishedReleaseFromJson(decoded) : null;
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
