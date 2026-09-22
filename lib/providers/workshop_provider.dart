import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/workshop_asset.dart';
import '../models/workshop_repository.dart';
import '../services/cos_auth.dart';
import '../services/workshop_service.dart';

/// 创意工坊：管理可用的角色卡仓库（本地持久化），并拉取各仓库的资产 zip。
class WorkshopProvider extends ChangeNotifier {
  static const _storageKey = 'workshop_repositories_v1';
  static const _notifyEnabledKey = 'workshop_notify_enabled_v1';
  static const _notifyRepoIdKey = 'workshop_notify_repo_id_v1';
  static const _lastNotifyBodyKey = 'workshop_last_notify_body_v1'; // 旧版兼容
  static const _notifyHashKey = 'workshop_last_notify_hash_v2';

  List<WorkshopRepository> _repositories = [];
  // 仓库 id -> tag -> 资产列表（内存缓存，避免重复请求）
  final Map<String, Map<String, List<WorkshopAsset>>> _assetsCache = {};

  /// COS 仓库最近一次探测到的 Note 内容（变更检测后决定是否强制刷新）
  final Map<String, ({String body, DateTime at})> _cosNoteState = {};

  /// Note 变更探测间隔：窗口内再次进分类不再拉 Note
  static const Duration _cosNoteCheckTtl = Duration(minutes: 30);

  /// 更新通知是否启用
  bool _notifyEnabled = false;

  /// 用于接收通知的仓库 id
  String? _notifyRepoId;

  /// 各仓库上次已提醒过的通知内容指纹（sha1）。
  /// 内容不变则不再弹窗；换仓库也不会互相干扰。
  final Map<String, String> _lastNotifyHashes = {};

  /// COS 仓库列表是否已拉全（false = 目前仅有首页）
  final Map<String, bool> _cosListComplete = {};

  List<WorkshopRepository> get repositories => List.unmodifiable(_repositories);

  bool get notifyEnabled => _notifyEnabled;
  String? get notifyRepoId => _notifyRepoId;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _repositories = (jsonDecode(raw) as List<dynamic>)
            .map((e) => WorkshopRepository.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _repositories = [];
      }
    }
    _notifyEnabled = prefs.getBool(_notifyEnabledKey) ?? false;
    _notifyRepoId = prefs.getString(_notifyRepoIdKey);
    _lastNotifyHashes.clear();
    final rawHashes = prefs.getString(_notifyHashKey);
    if (rawHashes != null && rawHashes.isNotEmpty) {
      try {
        final map = jsonDecode(rawHashes) as Map<String, dynamic>;
        for (final e in map.entries) {
          if (e.value is String) _lastNotifyHashes[e.key] = e.value as String;
        }
      } catch (_) {}
    }
    // 旧版仅存一份全文：迁移到当前通知仓库指纹，避免升级后重复弹一次
    final legacyBody = prefs.getString(_lastNotifyBodyKey);
    if (legacyBody != null &&
        legacyBody.isNotEmpty &&
        _notifyRepoId != null &&
        !_lastNotifyHashes.containsKey(_notifyRepoId)) {
      _lastNotifyHashes[_notifyRepoId!] =
          _noteFingerprint(WorkshopService.normalizeCosNote(legacyBody));
    }

    // 检查是否需要自动设置通知仓库（APP 更新后）
    await _autoSetupNotifyRepoIfNeeded(prefs);

    notifyListeners();
  }

  /// APP 更新后自动设置第一个有 V1.2.0 tag 的仓库为通知来源
  Future<void> _autoSetupNotifyRepoIfNeeded(SharedPreferences prefs) async {
    // 如果已有通知仓库，不需要自动设置
    if (_notifyRepoId != null && _notifyEnabled) return;

    // 如果没有仓库，不需要设置
    if (_repositories.isEmpty) return;

    try {
      // 查找第一个有 V1.2.0 tag 的仓库
      WorkshopRepository? notifyRepo;
      for (final repo in _repositories) {
        if (repo.hasUpdateNotify) {
          notifyRepo = repo;
          break;
        }
      }

      // 如果没有找到有 V1.2.0 tag 的仓库，跳过
      if (notifyRepo == null) {
        debugPrint('[WorkshopProvider] 未找到有 V1.2.0 tag 的仓库，跳过自动设置');
        return;
      }

      // 自动设置该仓库为通知来源
      _notifyEnabled = true;
      _notifyRepoId = notifyRepo.id;

      // 持久化
      await prefs.setBool(_notifyEnabledKey, true);
      await prefs.setString(_notifyRepoIdKey, notifyRepo.id);

      debugPrint('[WorkshopProvider] 自动设置通知仓库: ${notifyRepo.name}');
    } catch (e) {
      debugPrint('[WorkshopProvider] 自动设置通知仓库失败: $e');
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_repositories.map((r) => r.toJson()).toList()),
    );
  }

  /// 添加仓库：按 type / 自动探测分流 Git / COS，检查可用性后保存。
  /// 检查失败或没有可用 tag 时抛出异常。
  Future<WorkshopRepository> addRepository({
    required String path,
    String proxyUrl = '',
    String? type,
    CosAuth cosAuth = const CosAuth(),
  }) async {
    final repoType = _resolveRepoType(path, type);

    if (repoType == WorkshopRepoType.cos) {
      if (!WorkshopService.looksLikeCosUrl(path)) {
        throw const FormatException(
          'COS 来源需填写完整 http(s) BASE_URL（且不能为 GitHub / Gitee）',
        );
      }
      if (cosAuth.enabled &&
          (cosAuth.accessKeyId.trim().isEmpty ||
              cosAuth.secretAccessKey.trim().isEmpty)) {
        throw const FormatException('启用访问密钥时，请填写 AccessKey ID 与 Secret');
      }
      final tags = await WorkshopService.checkCosFolders(
        path,
        auth: cosAuth.isConfigured ? cosAuth : null,
      );
      final repo = WorkshopRepository(
        id: const Uuid().v4(),
        name: WorkshopService.cosDisplayName(path),
        url: path.trim(),
        proxyUrl: '',
        type: WorkshopRepoType.cos,
        availableTags: tags,
        cosAuth: cosAuth.isConfigured ? cosAuth : const CosAuth(),
        error: tags.isEmpty
            ? '未检测到 Characters / Games / Stickers / Note 目录'
            : null,
      );
      _repositories.insert(0, repo);
      notifyListeners();
      await _persist();
      return repo;
    }

    final parsed = WorkshopService.parseRepoPath(path);
    if (parsed == null) {
      throw const FormatException('仓库路径格式不正确（需为 owner/repo 或完整仓库 URL）');
    }
    // 自动检查可用性（直连官方 API；代理仅用于下载，Gitee 固定直连）
    final tags = await WorkshopService.checkTags(path);
    final repo = WorkshopRepository(
      id: const Uuid().v4(),
      name: '${parsed.owner}/${parsed.repo}',
      url: path.trim(),
      proxyUrl: parsed.isGitee ? '' : proxyUrl,
      type: WorkshopRepoType.git,
      availableTags: tags,
      error:
          tags.isEmpty ? '未检测到 V1.1.0 / V1.0.0 / V1.2.0 / V1.3.0 资产 tag' : null,
    );
    _repositories.insert(0, repo);
    notifyListeners();
    await _persist();
    return repo;
  }

  WorkshopRepoType _resolveRepoType(String path, String? type) {
    if (type != null) {
      return WorkshopRepoType.values.firstWhere(
        (e) => e.name == type,
        orElse: () => WorkshopService.detectRepoType(path),
      );
    }
    return WorkshopService.detectRepoType(path);
  }

  static const _gitEmptyTagError =
      '未检测到 V1.1.0 / V1.0.0 / V1.2.0 / V1.3.0 资产 tag';
  static const _cosEmptyTagError =
      '未检测到 Characters / Games / Stickers / Note 目录';

  /// 重新检查某个仓库的可用 tag（保留仓库其余配置）
  Future<void> refreshRepository(WorkshopRepository repo) async {
    final index = _repositories.indexWhere((r) => r.id == repo.id);
    if (index == -1) return;
    try {
      if (repo.isCos) {
        final tags = await WorkshopService.checkCosFolders(
          repo.url,
          auth: repo.hasCosAuth ? repo.cosAuth : null,
          force: true,
        );
        WorkshopService.invalidateCosListCache(repo.url);
        _repositories[index] = repo.copyWith(
          availableTags: tags,
          error: tags.isEmpty ? _cosEmptyTagError : null,
        );
      } else {
        final parsed = WorkshopService.parseRepoPath(repo.url);
        if (parsed == null) return;
        final tags = await WorkshopService.checkTags(repo.url);
        _repositories[index] = repo.copyWith(
          availableTags: tags,
          error: tags.isEmpty ? _gitEmptyTagError : null,
        );
      }
      // 清空该仓库的资产缓存，重新拉取
      _assetsCache.remove(repo.id);
      _cosNoteState.remove(repo.id);
      _cosListComplete.remove(repo.id);
      if (repo.isCos) WorkshopService.invalidateCosListCache(repo.url);
    } catch (e) {
      _repositories[index] = repo.copyWith(error: '$e');
    }
    notifyListeners();
    await _persist();
  }

  /// 修改仓库的路径/代理/类型并重新检查可用性（保留仓库 id）。
  /// 检查失败或没有可用 tag 时抛出异常。
  Future<WorkshopRepository> updateRepository({
    required WorkshopRepository repo,
    required String path,
    String proxyUrl = '',
    String? type,
    CosAuth? cosAuth,
  }) async {
    final repoType = _resolveRepoType(path, type ?? repo.type.name);
    late final WorkshopRepository updated;

    if (repoType == WorkshopRepoType.cos) {
      if (!WorkshopService.looksLikeCosUrl(path)) {
        throw const FormatException(
          'COS 来源需填写完整 http(s) BASE_URL（且不能为 GitHub / Gitee）',
        );
      }
      final auth = cosAuth ?? repo.cosAuth;
      if (auth.enabled &&
          (auth.accessKeyId.trim().isEmpty ||
              auth.secretAccessKey.trim().isEmpty)) {
        throw const FormatException('启用访问密钥时，请填写 AccessKey ID 与 Secret');
      }
      final tags = await WorkshopService.checkCosFolders(
        path,
        auth: auth.isConfigured ? auth : null,
      );
      updated = WorkshopRepository(
        id: repo.id,
        name: WorkshopService.cosDisplayName(path),
        url: path.trim(),
        proxyUrl: '',
        type: WorkshopRepoType.cos,
        availableTags: tags,
        cosAuth: auth.isConfigured ? auth : const CosAuth(),
        error: tags.isEmpty ? _cosEmptyTagError : null,
      );
    } else {
      final parsed = WorkshopService.parseRepoPath(path);
      if (parsed == null) {
        throw const FormatException('仓库路径格式不正确（需为 owner/repo 或完整仓库 URL）');
      }
      final tags = await WorkshopService.checkTags(path);
      updated = WorkshopRepository(
        id: repo.id,
        name: '${parsed.owner}/${parsed.repo}',
        url: path.trim(),
        proxyUrl: parsed.isGitee ? '' : proxyUrl,
        type: WorkshopRepoType.git,
        availableTags: tags,
        error: tags.isEmpty ? _gitEmptyTagError : null,
      );
    }

    final index = _repositories.indexWhere((r) => r.id == repo.id);
    if (index != -1) _repositories[index] = updated;
    // 清空该仓库的资产缓存，重新拉取
    _assetsCache.remove(repo.id);
    notifyListeners();
    await _persist();
    return updated;
  }

  Future<void> removeRepository(String id) async {
    _repositories.removeWhere((r) => r.id == id);
    _assetsCache.remove(id);
    _cosNoteState.remove(id);
    notifyListeners();
    await _persist();
  }

  /// 进分类时用 Note 内容做变更探测：
  /// 与上次不同 → 清空 List/资产缓存强制刷新；相同或窗口内已探测 → 不拉。
  Future<void> _syncCosIfNoteChanged(WorkshopRepository repo) async {
    if (!repo.isCos) return;
    final now = DateTime.now();
    final state = _cosNoteState[repo.id];
    if (state != null && now.difference(state.at) < _cosNoteCheckTtl) {
      return;
    }

    String? note;
    try {
      note = await WorkshopService.probeCosNote(
        repo.url,
        auth: repo.hasCosAuth ? repo.cosAuth : null,
      );
    } catch (_) {
      return; // 探测失败不阻断列表
    }

    if (note == null) {
      _cosNoteState[repo.id] = (body: '', at: now);
      return;
    }
    note = WorkshopService.normalizeCosNote(note);
    // 与本地已存 Note 不一致 → 强制刷新
    if (state != null && state.body.isNotEmpty && note != state.body) {
      WorkshopService.invalidateCosListCache(repo.url);
      _assetsCache.remove(repo.id);
      _cosListComplete.remove(repo.id);
    }
    _cosNoteState[repo.id] = (body: note, at: now);
  }

  /// 该 COS 仓库当前资产列表是否已取全（false 时可「加载更多」）
  bool cosListComplete(String repoId) => _cosListComplete[repoId] ?? true;

  /// 拉取仓库某 tag 下的 zip 资产（带内存缓存）。
  /// COS 默认只拉首页（约 500 条对象）；[loadAll] 为 true 时拉全量。
  Future<List<WorkshopAsset>> loadAssets(
    WorkshopRepository repo,
    String tag, {
    bool loadAll = false,
  }) async {
    // COS：先做 Note 变更探测（变了才清缓存）
    if (repo.isCos) {
      await _syncCosIfNoteChanged(repo);
      if (loadAll) {
        // 全量前清掉该 tag 的首页缓存，避免拿到截断列表
        _assetsCache[repo.id]?.remove(tag);
      }
    }
    final cached = _assetsCache[repo.id]?[tag];
    if (cached != null) return cached;
    final List<WorkshopAsset> list;
    if (repo.isCos) {
      list = await WorkshopService.listCosAssets(
        repo.url,
        tag,
        auth: repo.hasCosAuth ? repo.cosAuth : null,
        loadAll: loadAll,
      );
      _cosListComplete[repo.id] = WorkshopService.cosListIsComplete(
        repo.url,
        auth: repo.hasCosAuth ? repo.cosAuth : null,
      );
    } else {
      final parsed = WorkshopService.parseRepoPath(repo.url);
      list = parsed == null
          ? const <WorkshopAsset>[]
          : await WorkshopService.listAssets(repo.url, tag);
      _cosListComplete[repo.id] = true;
    }
    _assetsCache.putIfAbsent(repo.id, () => {})[tag] = list;
    return list;
  }

  /// 查询仓库的下载代理（Gitee / COS 仓库固定不使用代理）
  String proxyFor(WorkshopRepository repo) {
    if (repo.isCos) return '';
    final parsed = WorkshopService.parseRepoPath(repo.url);
    return parsed != null && parsed.isGitee ? '' : repo.proxyUrl;
  }

  /// 按仓库 id 查询下载代理（Gitee 仓库固定不使用代理）
  String? proxyById(String id) {
    for (final r in _repositories) {
      if (r.id == id) return proxyFor(r);
    }
    return null;
  }

  /// 按仓库 id 查询 COS 私有读鉴权（未配置返回 null）
  CosAuth? cosAuthById(String id) {
    for (final r in _repositories) {
      if (r.id == id && r.hasCosAuth) return r.cosAuth;
    }
    return null;
  }

  /// 设置更新通知开关
  Future<void> setNotifyEnabled(bool enabled) async {
    _notifyEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifyEnabledKey, enabled);
  }

  /// 设置用于接收通知的仓库 id
  Future<void> setNotifyRepoId(String? repoId) async {
    _notifyRepoId = repoId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (repoId == null) {
      await prefs.remove(_notifyRepoIdKey);
    } else {
      await prefs.setString(_notifyRepoIdKey, repoId);
    }
  }

  /// 检查仓库更新（APP 启动时调用）
  /// 返回通知内容（如果有更新），无更新返回 null
  Future<String?> checkForUpdates() async {
    if (!_notifyEnabled || _notifyRepoId == null) return null;

    // 查找通知仓库
    WorkshopRepository? notifyRepo;
    for (final r in _repositories) {
      if (r.id == _notifyRepoId) {
        notifyRepo = r;
        break;
      }
    }
    if (notifyRepo == null) return null;

    try {
      // Git：读 V1.2.0 Release body；COS：读 Note/*.md 全文
      final String? body;
      if (notifyRepo.isCos) {
        body = await WorkshopService.fetchCosNote(
          notifyRepo.url,
          auth: notifyRepo.hasCosAuth ? notifyRepo.cosAuth : null,
        );
        // 启动通知检查时记录 Note，供进分类时做变更对比
        if (body != null) {
          _cosNoteState[notifyRepo.id] = (body: body, at: DateTime.now());
        }
      } else {
        body = await WorkshopService.fetchReleaseBody(
          notifyRepo.url,
          kUpdateNotifyTag,
        );
      }
      if (body == null || body.trim().isEmpty) return null;

      final normalized = notifyRepo.isCos
          ? WorkshopService.normalizeCosNote(body)
          : body.trim();
      final hash = _noteFingerprint(normalized);
      final last = _lastNotifyHashes[notifyRepo.id];

      // 与该仓库上次已提醒内容相同 → 不再提醒
      if (last != null && last == hash) return null;

      // 内容有变化（或首次记录），保存指纹后再弹窗
      _lastNotifyHashes[notifyRepo.id] = hash;
      await _persistNotifyHashes();
      return normalized;
    } catch (_) {
      return null;
    }
  }

  static String _noteFingerprint(String body) =>
      sha1.convert(utf8.encode(body)).toString();

  Future<void> _persistNotifyHashes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notifyHashKey, jsonEncode(_lastNotifyHashes));
  }

  /// 获取通知仓库信息（用于 UI 显示）
  WorkshopRepository? get notifyRepository {
    if (_notifyRepoId == null) return null;
    for (final r in _repositories) {
      if (r.id == _notifyRepoId) return r;
    }
    return null;
  }
}
