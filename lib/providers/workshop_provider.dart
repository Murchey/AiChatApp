import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/workshop_asset.dart';
import '../models/workshop_repository.dart';
import '../services/workshop_service.dart';

/// 创意工坊：管理可用的角色卡仓库（本地持久化），并拉取各仓库的资产 zip。
class WorkshopProvider extends ChangeNotifier {
  static const _storageKey = 'workshop_repositories_v1';

  List<WorkshopRepository> _repositories = [];
  // 仓库 id -> tag -> 资产列表（内存缓存，避免重复请求）
  final Map<String, Map<String, List<WorkshopAsset>>> _assetsCache = {};

  List<WorkshopRepository> get repositories =>
      List.unmodifiable(_repositories);

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
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_repositories.map((r) => r.toJson()).toList()),
    );
  }

  /// 添加仓库：解析路径后自动检查可用性（是否有 V1.1.0 / V1.0.0 tag），再保存。
  /// 检查失败或没有可用 tag 时抛出异常。
  Future<WorkshopRepository> addRepository({
    required String path,
    String proxyUrl = '',
  }) async {
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
      availableTags: tags,
      error: tags.isEmpty ? '未检测到 V1.1.0 / V1.0.0 资产 tag' : null,
    );
    _repositories.insert(0, repo);
    notifyListeners();
    await _persist();
    return repo;
  }

  /// 重新检查某个仓库的可用 tag（保留仓库其余配置）
  Future<void> refreshRepository(WorkshopRepository repo) async {
    final index = _repositories.indexWhere((r) => r.id == repo.id);
    if (index == -1) return;
    final parsed = WorkshopService.parseRepoPath(repo.url);
    if (parsed == null) return;
    try {
      final tags = await WorkshopService.checkTags(repo.url);
      _repositories[index] = repo.copyWith(
        availableTags: tags,
        error: tags.isEmpty ? '未检测到 V1.1.0 / V1.0.0 资产 tag' : null,
      );
      // 清空该仓库的资产缓存，重新拉取
      _assetsCache.remove(repo.id);
    } catch (e) {
      _repositories[index] = repo.copyWith(error: '$e');
    }
    notifyListeners();
    await _persist();
  }

  /// 修改仓库的路径/代理并重新检查可用性（保留仓库 id）。
  /// 检查失败或没有可用 tag 时抛出异常。
  Future<WorkshopRepository> updateRepository({
    required WorkshopRepository repo,
    required String path,
    String proxyUrl = '',
  }) async {
    final parsed = WorkshopService.parseRepoPath(path);
    if (parsed == null) {
      throw const FormatException('仓库路径格式不正确（需为 owner/repo 或完整仓库 URL）');
    }
    // 重新检查可用性（直连官方 API；代理仅用于下载，Gitee 固定直连）
    final tags = await WorkshopService.checkTags(path);
    final updated = WorkshopRepository(
      id: repo.id,
      name: '${parsed.owner}/${parsed.repo}',
      url: path.trim(),
      proxyUrl: parsed.isGitee ? '' : proxyUrl,
      availableTags: tags,
      error: tags.isEmpty ? '未检测到 V1.1.0 / V1.0.0 资产 tag' : null,
    );
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
    notifyListeners();
    await _persist();
  }

  /// 拉取仓库某 tag 下的 zip 资产（带内存缓存）
  Future<List<WorkshopAsset>> loadAssets(
    WorkshopRepository repo,
    String tag,
  ) async {
    final cached = _assetsCache[repo.id]?[tag];
    if (cached != null) return cached;
    final parsed = WorkshopService.parseRepoPath(repo.url);
    final list = parsed == null
        ? const <WorkshopAsset>[]
        : await WorkshopService.listAssets(repo.url, tag);
    _assetsCache.putIfAbsent(repo.id, () => {})[tag] = list;
    return list;
  }

  /// 查询仓库的下载代理（Gitee 仓库固定不使用代理）
  String proxyFor(WorkshopRepository repo) {
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
}
