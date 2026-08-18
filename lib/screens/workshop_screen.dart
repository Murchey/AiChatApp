import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/moments_pack_entry.dart';
import '../models/workshop_asset.dart';
import '../models/workshop_repository.dart';
import '../providers/character_provider.dart';
import '../providers/workshop_provider.dart';
import '../services/character_pack_service.dart';
import '../services/workshop_service.dart';
import '../utils/conversation_relink.dart';
import '../utils/pinyin_util.dart';
import 'character_import_screen.dart';
import 'workshop_repos_screen.dart';

/// 创意工坊二级菜单页：
/// 右上角菜单图标进入「配置可用仓库」；勾选分类后展示对应 tag 的资产 zip，
/// 勾选 zip 后点击「下载导入」自动下载并导入（角色包走角色勾选二级页）。
class WorkshopScreen extends StatefulWidget {
  const WorkshopScreen({super.key});

  @override
  State<WorkshopScreen> createState() => _WorkshopScreenState();
}

/// 资产 zip 展示项（携带所属仓库信息）
class _ZipItem {
  final WorkshopAsset asset;
  final String repoName;
  final String repoId;

  _ZipItem({
    required this.asset,
    required this.repoName,
    required this.repoId,
  });

  String get key => '$repoId|${asset.tag}|${asset.name}';
}

class _WorkshopScreenState extends State<WorkshopScreen> {
  final Map<String, bool> _checked = {
    kCharacterPackTag: false,
    kGamePackTag: false,
  };
  final Map<String, List<_ZipItem>> _items = {
    kCharacterPackTag: [],
    kGamePackTag: [],
  };
  final Map<String, bool> _loading = {
    kCharacterPackTag: false,
    kGamePackTag: false,
  };
  final Set<String> _selected = {};
  bool _importing = false;

  // 搜索状态
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _categoryLabel(String tag) =>
      tag == kCharacterPackTag ? '角色分类' : '游戏分类';

  List<_ZipItem> get _allItems =>
      [..._items[kCharacterPackTag]!, ..._items[kGamePackTag]!];

  /// 搜索结果：仅在已勾选（标记开启）的两个分类内搜索。
  /// 忽略大小写，同时匹配「名称原文」与「完整拼音」：
  /// 汉字/字母查询命中名称，拼音查询命中名称拼音，结果为拼音命中 + 汉字命中的并集。
  List<_ZipItem> get _searchResults {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _allItems.where((item) {
      if (_checked[item.asset.tag] != true) return false;
      final name = item.asset.displayName;
      // 汉字/原文匹配（忽略大小写）
      if (name.toLowerCase().contains(query)) return true;
      // 拼音匹配：如查「zhangsan」可命中「张三」
      final pinyin = PinyinUtil.fullPinyin(name);
      return pinyin.contains(query);
    }).toList();
  }

  /// 进入配置可用仓库；返回后刷新已勾选分类的资产（仓库可能已变化）
  Future<void> _openRepos() async {
    await Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => const WorkshopReposScreen()),
    );
    if (!mounted) return;
    for (final tag in kWorkshopPackTags) {
      if (_checked[tag] == true) await _loadCategory(tag);
    }
  }

  Future<void> _toggleCategory(String tag, bool value) async {
    setState(() {
      _checked[tag] = value;
      if (!value) {
        // 取消勾选分类：同步清除该分类下已勾选的 zip
        _selected.removeWhere((k) => k.contains('|$tag|'));
      }
    });
    if (value) await _loadCategory(tag);
  }

  /// 拉取所有已配置仓库中该 tag 下的 zip 资产
  Future<void> _loadCategory(String tag) async {
    setState(() => _loading[tag] = true);
    final provider = context.read<WorkshopProvider>();
    final items = <_ZipItem>[];
    String? error;
    try {
      for (final repo in provider.repositories) {
        if (!repo.availableTags.contains(tag)) continue;
        final assets = await provider.loadAssets(repo, tag);
        items.addAll(assets.map(
          (a) => _ZipItem(asset: a, repoName: repo.name, repoId: repo.id),
        ));
      }
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _items[tag] = items;
      _loading[tag] = false;
    });
    if (error != null) _showTip('拉取资产失败：$error');
  }

  /// 下载选中的 zip 并逐个导入（新机制：先批量下载，再逐个确认导入）
  Future<void> _downloadAndImport() async {
    if (_importing) return;
    final selected =
        _allItems.where((i) => _selected.contains(i.key)).toList();
    if (selected.isEmpty) return;
    setState(() => _importing = true);
    final workshop = context.read<WorkshopProvider>();
    try {
      // ── 阶段一：批量下载所有 zip ──
      final downloadResults = await showCupertinoDialog<Map<String, String>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BatchDownloadDialog(
          items: selected,
          getProxyUrl: (item) => workshop.proxyById(item.repoId) ?? '',
        ),
      );
      if (!mounted) return;
      if (downloadResults == null || downloadResults.isEmpty) {
        setState(() => _importing = false);
        return;
      }

      // ── 阶段二：逐个让用户确认导入 ──
      var importCount = 0;
      var failCount = 0;
      for (final item in selected) {
        if (!mounted) return;
        final path = downloadResults[item.key];
        if (path == null) {
          // 该 zip 下载失败，跳过
          failCount++;
          continue;
        }
        if (item.asset.isCharacter) {
          final success = await _importCharacterPack(path, item);
          if (success) importCount++;
        } else {
          final success = await _importGamePack(path, item);
          if (success) importCount++;
        }
        // 导入完成：清理该 zip 的下载缓存（含 .part 临时文件）
        WorkshopService.removeDownloadCache(path);
      }

      // 显示导入结果摘要
      if (!mounted) return;
      final total = selected.length;
      final downloadFailCount = total - downloadResults.length;
      final msg = StringBuffer('批量导入完成：');
      msg.write('共 $total 个 zip，');
      if (downloadFailCount > 0) msg.write('$downloadFailCount 个下载失败，');
      msg.write('成功导入 $importCount 个');
      if (failCount > importCount) {
        msg.write('，${failCount - downloadFailCount} 个导入失败');
      }
      await _showTip(msg.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 角色分类 zip：解析后进入角色勾选二级页（与管理当前角色导入一致）
  Future<bool> _importCharacterPack(String path, _ZipItem item) async {
    try {
      final entries = await CharacterPackService.parsePack(path);
      if (!mounted) return false;
      if (entries.isEmpty) {
        _showTip('「${item.asset.displayName}」中没有找到角色包（需包含 Profile.json 的角色文件夹）');
        return false;
      }
      await Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => CharacterImportScreen(
            entries: entries,
            zipName: item.asset.displayName,
          ),
        ),
      );
      return true;
    } catch (e) {
      if (mounted) _showTip('「${item.asset.displayName}」导入失败：$e');
      return false;
    }
  }

  /// 游戏分类 zip：解析朋友圈数据包并确认导入（更新已有角色 / 新建角色）
  Future<bool> _importGamePack(String path, _ZipItem item) async {
    try {
      final entries = await CharacterPackService.parseMomentsPack(path);
      if (!mounted) return false;
      if (entries.isEmpty) {
        _showTip('「${item.asset.displayName}」中没有找到朋友圈数据（需包含 moments.json 的角色文件夹）');
        return false;
      }
      await _confirmImportMoments(entries);
      return true;
    } catch (e) {
      if (mounted) _showTip('「${item.asset.displayName}」导入失败：$e');
      return false;
    }
  }

  /// 确认导入朋友圈：匹配已有角色则更新其朋友圈，未匹配则新建角色
  Future<void> _confirmImportMoments(List<MomentsPackEntry> entries) async {
    final valid = entries
        .where((e) => e.error == null && e.moments.isNotEmpty)
        .toList();
    if (valid.isEmpty) {
      _showTip('该 zip 中没有可导入的朋友圈数据');
      return;
    }

    final provider = context.read<CharacterProvider>();
    final existing = <String, Character>{
      for (final c in provider.characters) c.displayName: c,
    };
    var updateCount = 0;
    final createNames = <String>[];
    for (final e in valid) {
      if (existing.containsKey(e.characterName)) {
        updateCount++;
      } else {
        createNames.add(e.characterName);
      }
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('导入朋友圈数据'),
        content: Text(
          '将导入 ${valid.length} 个角色的朋友圈：'
          '$updateCount 个更新到已有角色'
          '${createNames.isEmpty ? '' : '，${createNames.length} 个将新建角色（${createNames.join('、')}）'}。',
          textAlign: TextAlign.center,
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    var count = 0;
    for (final e in valid) {
      final hit = existing[e.characterName];
      if (hit != null) {
        await provider.updateMoments(hit.id, e.moments);
      } else {
        final character = Character(
          id: const Uuid().v4(),
          name: e.characterName,
          moments: e.moments,
        );
        await provider.addCharacter(character);
        // 角色删除后重新导入：把指向旧角色的孤儿会话重新关联到新角色
        if (mounted) {
          relinkOrphanedConversations(context: context, character: character);
        }
      }
      count++;
    }
    if (!mounted) return;
    await _showTip('已导入 $count 个角色的朋友圈数据');
  }

  Future<void> _showTip(String message) {
    return showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkshopProvider>();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('创意工坊'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _openRepos,
          child: Icon(
            CupertinoIcons.gear,
            size: 22,
            color: context.accentColor,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildRepoSection(context, provider),
          // 搜索框：位于「可用仓库栏」下方、「分类勾选栏」上方
          _buildSearchBar(context),
          // 分类勾选
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const SizedBox.shrink(),
            children: [
              CupertinoListTile(
                leading: Icon(
                  CupertinoIcons.person_2_fill,
                  color: context.accentColor,
                ),
                title: const Text('按角色分类'),
                subtitle: Text(
                  '角色包（V1.1.0）',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: CupertinoSwitch(
                  value: _checked[kCharacterPackTag]!,
                  onChanged: (v) => _toggleCategory(kCharacterPackTag, v),
                ),
              ),
              CupertinoListTile(
                leading: Icon(
                  CupertinoIcons.gamecontroller_fill,
                  color: context.accentColor,
                ),
                title: const Text('按游戏分类'),
                subtitle: Text(
                  '游戏包（V1.0.0）',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: CupertinoSwitch(
                  value: _checked[kGamePackTag]!,
                  onChanged: (v) => _toggleCategory(kGamePackTag, v),
                ),
              ),
            ],
          ),
          // 资产 zip 列表
          Expanded(child: _buildAssetsList(context)),
          // 底部下载导入按钮
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoButton.filled(
                onPressed:
                    _selected.isEmpty || _importing ? null : _downloadAndImport,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _importing
                        ? '正在导入…'
                        : (_selected.isEmpty
                            ? '请选择要下载的 zip'
                            : '下载导入 (${_selected.length})'),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部仓库摘要：展示已配置仓库与可用 tag
  Widget _buildRepoSection(BuildContext context, WorkshopProvider provider) {
    final repos = provider.repositories;
    if (repos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.info_circle,
              size: 15,
              color: context.textSecondaryColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '尚未配置仓库，点击右上角菜单进入「配置可用仓库」',
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '可用仓库',
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 6),
          for (final repo in repos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      repo.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                  Text(
                    repo.isAvailable ? _repoTagsLabel(repo) : '不可用',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: repo.isAvailable
                          ? context.accentColor
                          : CupertinoColors.systemRed,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _repoTagsLabel(WorkshopRepository repo) {
    final parts = <String>[
      if (repo.hasCharacter) '角色分类',
      if (repo.hasGame) '游戏分类',
    ];
    return parts.join('·');
  }

  /// 搜索框：仅在已勾选的「角色 / 游戏」两个分类内搜索，
  /// 支持中文名称与拼音（忽略大小写），输入时实时过滤下方资产列表。
  Widget _buildSearchBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: CupertinoTextField(
        controller: _searchController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: context.listBgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.separatorColor),
        ),
        placeholder: '搜索资产（支持中文或拼音，忽略大小写）',
        placeholderStyle: TextStyle(
          fontSize: 14,
          color: context.textSecondaryColor,
        ),
        style: TextStyle(
          fontSize: 14,
          color: context.textPrimaryColor,
        ),
        prefix: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Icon(
            CupertinoIcons.search,
            size: 18,
            color: context.textSecondaryColor,
          ),
        ),
        suffix: _searchQuery.isEmpty
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: Icon(
                  CupertinoIcons.clear_circled_solid,
                  size: 18,
                  color: context.textSecondaryColor,
                ),
              ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildAssetsList(BuildContext context) {
    final hasChecked = _checked.values.any((v) => v);
    if (!hasChecked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            '勾选上方「按角色分类」或「按游戏分类」查看可下载的资产 zip',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: context.textSecondaryColor,
            ),
          ),
        ),
      );
    }
    // 搜索模式：在已勾选分类内展示拼音结果 + 汉字结果的并集
    final query = _searchQuery.trim();
    if (query.isNotEmpty) {
      final results = _searchResults;
      if (results.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              '未找到与「$query」匹配的资产',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: context.textSecondaryColor,
              ),
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [for (final item in results) _buildZipRow(context, item)],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final tag in kWorkshopPackTags)
          if (_checked[tag] == true) _buildCategorySection(context, tag),
      ],
    );
  }

  Widget _buildCategorySection(BuildContext context, String tag) {
    final items = _items[tag]!;
    final loading = _loading[tag]!;
    final isCharacter = tag == kCharacterPackTag;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Icon(
                isCharacter
                    ? CupertinoIcons.person_2_fill
                    : CupertinoIcons.gamecontroller_fill,
                size: 15,
                color: context.accentColor,
              ),
              const SizedBox(width: 6),
              Text(
                '${_categoryLabel(tag)}资产',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondaryColor,
                ),
              ),
            ],
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              '该分类暂无可用 zip 资产',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
              ),
            ),
          )
        else
          for (final item in items) _buildZipRow(context, item),
      ],
    );
  }

  Widget _buildZipRow(BuildContext context, _ZipItem item) {
    final isSelected = _selected.contains(item.key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleZip(item),
      child: Container(
        color: context.listBgColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.archivebox,
              size: 22,
              color: context.accentColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.asset.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _zipSubtitle(item),
                    // 一行显示不下时换行展示（包大小放在行尾，避免被省略号截断）
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 24,
              color: isSelected
                  ? context.accentColor
                  : CupertinoColors.systemGrey,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleZip(_ZipItem item) {
    setState(() {
      if (_selected.contains(item.key)) {
        _selected.remove(item.key);
      } else {
        _selected.add(item.key);
      }
    });
  }

  /// zip 行副标题：仓库 · 分类 · 包大小
  String _zipSubtitle(_ZipItem item) {
    final sizeText = _formatSize(item.asset.sizeBytes);
    final base = '${item.repoName} · ${_categoryLabel(item.asset.tag)}';
    return sizeText.isEmpty ? base : '$base · $sizeText';
  }

  /// 字节数格式化为可读大小（B / KB / MB）
  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }
}

/// 下载 zip 进度弹窗：完成后自动关闭并返回本地路径，失败返回 null
class _DownloadZipDialog extends StatefulWidget {
  final String name;
  final String downloadUrl;
  final String proxyUrl;

  const _DownloadZipDialog({
    required this.name,
    required this.downloadUrl,
    required this.proxyUrl,
  });

  @override
  State<_DownloadZipDialog> createState() => _DownloadZipDialogState();
}

class _DownloadZipDialogState extends State<_DownloadZipDialog> {
  double _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final path = await WorkshopService.downloadZip(
      downloadUrl: widget.downloadUrl,
      proxyUrl: widget.proxyUrl,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (path == null) {
      setState(() => _failed = true);
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).round();
    return CupertinoAlertDialog(
      title: Text(_failed ? '下载失败' : '正在下载'),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _failed
            ? const Text('下载失败，请检查网络或代理设置后重试')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.separatorColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.accentColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '下载完成后将自动进入导入流程',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (_failed)
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
      ],
    );
  }
}

/// 批量下载 zip 进度弹窗：下载所有 zip 后自动关闭，返回 item.key -> 本地路径 的映射
class _BatchDownloadDialog extends StatefulWidget {
  final List<_ZipItem> items;
  final String Function(_ZipItem item) getProxyUrl;

  const _BatchDownloadDialog({
    required this.items,
    required this.getProxyUrl,
  });

  @override
  State<_BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<_BatchDownloadDialog> {
  int _currentIndex = 0;
  double _currentProgress = 0;
  bool _failed = false;
  final Map<String, String> _results = {};

  @override
  void initState() {
    super.initState();
    _startBatchDownload();
  }

  Future<void> _startBatchDownload() async {
    for (var i = 0; i < widget.items.length; i++) {
      if (!mounted) return;
      setState(() {
        _currentIndex = i;
        _currentProgress = 0;
      });

      final item = widget.items[i];
      final proxyUrl = widget.getProxyUrl(item);
      final path = await WorkshopService.downloadZip(
        downloadUrl: item.asset.downloadUrl,
        proxyUrl: proxyUrl,
        onProgress: (p) {
          if (mounted) setState(() => _currentProgress = p);
        },
      );

      if (!mounted) return;
      if (path == null) {
        setState(() {
          _failed = true;
        });
        // 等待用户确认后继续或取消
        final shouldContinue = await showCupertinoDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('下载失败'),
            content: Text(
              '「${item.asset.displayName}」下载失败，请检查网络或代理设置',
              textAlign: TextAlign.center,
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('取消全部'),
                onPressed: () => Navigator.pop(ctx, false),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('跳过继续'),
              ),
            ],
          ),
        );
        if (shouldContinue != true) {
          // 用户选择取消全部，返回已有结果
          if (mounted) Navigator.pop(context, _results.isNotEmpty ? _results : null);
          return;
        }
        // 跳过当前失败的，继续下载下一个
        setState(() => _failed = false);
        continue;
      }

      _results[item.key] = path;
    }

    // 全部下载完成
    if (mounted) Navigator.pop(context, _results);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final currentName = _currentIndex < total
        ? widget.items[_currentIndex].asset.displayName
        : '';
    final percent = (_currentProgress * 100).round();

    return CupertinoAlertDialog(
      title: Text(_failed ? '下载失败' : '正在批量下载'),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 整体进度提示
            Text(
              '正在下载 (${_currentIndex + 1}/$total)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),
            // 当前文件名
            Text(
              currentName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 12),
            // 进度条
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: context.separatorColor,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _currentProgress,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 百分比
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 8),
            // 提示文字
            Text(
              '全部下载完成后将逐个确认导入',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
          ],
        ),
      ),
      actions: const [], // 下载过程中不允许取消（已在失败时提供选项）
    );
  }
}
