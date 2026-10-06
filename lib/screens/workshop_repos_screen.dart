import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../widgets/workshop/workshop_repo_widgets.dart';
import '../models/workshop_repository.dart';
import '../providers/workshop_provider.dart';
import '../services/cos_auth.dart';
import '../services/update_service.dart';

/// 配置可用仓库：列出已添加的角色卡仓库，右上角加号弹窗添加仓库并自动检查可用性。
class WorkshopReposScreen extends StatefulWidget {
  const WorkshopReposScreen({super.key});

  @override
  State<WorkshopReposScreen> createState() => _WorkshopReposScreenState();
}

class _WorkshopReposScreenState extends State<WorkshopReposScreen> {
  bool _busy = false;

  /// 右上角 +：直接打开填写弹窗（类型由 URL 自动识别，弹窗内也可切换）
  Future<void> _showAddDialog() async {
    if (_busy) return;
    await _openRepoDialog(initialType: WorkshopRepoType.git.name);
  }

  Future<void> _openRepoDialog({
    required String initialType,
    String? initialPath,
    String? initialProxyUrl,
    CosAuth initialCosAuth = const CosAuth(),
    String title = '添加仓库',
    WorkshopRepository? editing,
  }) async {
    final result = await showCupertinoDialog<
        ({
          String path,
          String proxyUrl,
          String type,
          CosAuth cosAuth,
        })>(
      context: context,
      builder: (_) => AddRepoDialog(
        title: title,
        initialPath: initialPath,
        initialProxyUrl: initialProxyUrl,
        initialType: initialType,
        initialCosAuth: initialCosAuth,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final provider = context.read<WorkshopProvider>();
      final WorkshopRepository repo;
      if (editing != null) {
        repo = await provider.updateRepository(
          repo: editing,
          path: result.path,
          proxyUrl: result.proxyUrl,
          type: result.type,
          cosAuth: result.cosAuth,
        );
      } else {
        repo = await provider.addRepository(
          path: result.path,
          proxyUrl: result.proxyUrl,
          type: result.type,
          cosAuth: result.cosAuth,
        );
      }
      if (!mounted) return;
      await _showTip(
        repo.isAvailable
            ? '${editing != null ? '仓库已更新' : '仓库添加成功'}，可用分类：${_tagsLabel(repo)}'
            : '${editing != null ? '仓库已更新' : '仓库已添加'}，但未检测到可用的资产',
      );
      // 完成添加后返回上一级（创意工坊）页面
      if (editing == null && mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        await _showTip(
          '${editing != null ? '仓库更新失败' : '仓库添加失败'}：$e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _tagsLabel(WorkshopRepository repo) {
    final parts = <String>[
      if (repo.hasCharacter) '角色分类(V1.1.0)',
      if (repo.hasGame) '游戏分类(V1.0.0)',
      if (repo.hasSticker) '表情包分类(V1.3.0)',
      if (repo.hasUpdateNotify) '更新通知(V1.2.0)',
    ];
    return parts.isEmpty ? '无' : parts.join('、');
  }

  Future<void> _refresh(WorkshopRepository repo) async {
    setState(() => _busy = true);
    await context.read<WorkshopProvider>().refreshRepository(repo);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  /// 编辑仓库：弹窗预填当前路径/代理/类型/密钥，保存后重新检查可用性
  Future<void> _edit(WorkshopRepository repo) async {
    if (_busy) return;
    await _openRepoDialog(
      title: '编辑仓库',
      initialPath: repo.url,
      initialProxyUrl: repo.proxyUrl,
      initialType: repo.type.name,
      initialCosAuth: repo.cosAuth,
      editing: repo,
    );
  }

  Future<void> _remove(WorkshopRepository repo) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('移除仓库'),
        content: Text(
          '确定移除仓库「${repo.name}」吗？',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<WorkshopProvider>().removeRepository(repo.id);
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

  /// 选择通知仓库
  Future<void> _pickNotifyRepo(WorkshopProvider provider) async {
    final repos = provider.repositories;
    if (repos.isEmpty) {
      await _showTip('请先添加仓库');
      return;
    }

    final selected = await showCupertinoDialog<WorkshopRepository>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('选择通知仓库'),
        content: SizedBox(
          height: 200,
          child: ListView.builder(
            itemCount: repos.length,
            itemBuilder: (ctx, index) {
              final repo = repos[index];
              final isSelected = repo.id == provider.notifyRepoId;
              return GestureDetector(
                onTap: () => Navigator.pop(ctx, repo),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: CupertinoColors.separator,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          repo.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: context.textPrimaryColor,
                          ),
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          size: 20,
                          color: context.accentColor,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selected != null) {
      await provider.setNotifyRepoId(selected.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkshopProvider>();
    final repos = provider.repositories;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('创意工坊设置'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _busy ? null : _showAddDialog,
          child: Icon(
            CupertinoIcons.plus_circle_fill,
            size: 26,
            color: _busy ? context.textSecondaryColor : context.accentColor,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 仓库列表区域（可滚动）
            Expanded(
              flex: 3,
              child: _buildRepoSection(repos),
            ),
            // 分隔线
            Container(
              height: 8,
              color: context.scaffoldColor,
            ),
            // 通知设置区域
            Expanded(
              flex: 2,
              child: _buildNotifySection(provider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepoSection(List<WorkshopRepository> repos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '可用仓库',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textSecondaryColor,
            ),
          ),
        ),
        Expanded(
          child: repos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      '暂无可用仓库，点击右上角 + 添加角色卡仓库',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: repos.length,
                  separatorBuilder: (context, index) => Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 16),
                    color: context.separatorColor,
                  ),
                  itemBuilder: (context, index) {
                    final repo = repos[index];
                    return _buildRepoRow(context, repo);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNotifySection(WorkshopProvider provider) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '角色仓库更新通知',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textSecondaryColor,
            ),
          ),
        ),
        // 开关
        _buildNotifySwitch(provider),
        // 选择仓库
        if (provider.notifyEnabled) _buildNotifyRepoPicker(provider),
        // 说明
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            '开启后，APP 启动时会自动检查所选仓库的 V1.2.0 tag 更新。\n当 release 描述内容发生变化时，会发送通知提醒。',
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotifySwitch(WorkshopProvider provider) {
    return Container(
      color: context.listBgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.bell_fill,
            size: 20,
            color: context.textSecondaryColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '启用更新通知',
              style: TextStyle(
                fontSize: 15,
                color: context.textPrimaryColor,
              ),
            ),
          ),
          CupertinoSwitch(
            value: provider.notifyEnabled,
            onChanged: (value) => provider.setNotifyEnabled(value),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifyRepoPicker(WorkshopProvider provider) {
    final notifyRepo = provider.notifyRepository;
    return GestureDetector(
      onTap: () => _pickNotifyRepo(provider),
      child: Container(
        color: context.listBgColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const SizedBox(width: 32), // 对齐图标
            Text(
              '通知仓库',
              style: TextStyle(
                fontSize: 15,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notifyRepo?.name ?? '请选择',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 14,
                  color: notifyRepo != null
                      ? context.textSecondaryColor
                      : CupertinoColors.systemGrey,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: context.textSecondaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepoRow(BuildContext context, WorkshopRepository repo) {
    final isCos = repo.isCos;
    final typeLabel =
        isCos ? (repo.hasCosAuth ? 'COS 私有读' : 'COS 对象储存') : 'Git Release';
    final String metaLine;
    if (isCos) {
      metaLine = repo.hasCosAuth ? '$typeLabel · 访问密钥' : typeLabel;
    } else {
      final proxyIdx = kProxySources.indexOf(repo.proxyUrl);
      final proxyLabel = repo.proxyUrl.isEmpty
          ? '不使用代理'
          : (proxyIdx >= 0 ? '代理 ${proxyIdx + 1}' : '自定义代理');
      metaLine = '$typeLabel · $proxyLabel';
    }

    return Container(
      color: context.listBgColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        repo.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimaryColor,
                        ),
                      ),
                    ),
                    TagChip(
                      text: typeLabel,
                      color: isCos
                          ? const Color(0xFF8B5CF6)
                          : const Color(0xFF64748B),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  repo.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metaLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 6),
                if (repo.error != null)
                  Text(
                    repo.error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.systemRed,
                    ),
                  )
                else if (repo.availableTags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (repo.hasCharacter)
                        TagChip(
                          text: isCos ? '角色分类 Characters' : '角色分类 V1.1.0',
                        ),
                      if (repo.hasGame)
                        TagChip(
                          text: isCos ? '游戏分类 Games' : '游戏分类 V1.0.0',
                          color: const Color(0xFF3B82F6),
                        ),
                      if (repo.hasSticker)
                        TagChip(
                          text: isCos ? '表情包分类 Stickers' : '表情包分类 V1.3.0',
                          color: const Color(0xFFEC4899),
                        ),
                    ],
                  )
                else
                  Text(
                    isCos ? '未检测到可用目录' : '未检测到可用 tag',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
              ],
            ),
          ),
          // 编辑 / 刷新 / 移除
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            onPressed: _busy ? null : () => _edit(repo),
            child: Icon(
              CupertinoIcons.pencil,
              size: 18,
              color: _busy ? context.textSecondaryColor : context.accentColor,
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            onPressed: _busy ? null : () => _refresh(repo),
            child: Icon(
              CupertinoIcons.arrow_clockwise,
              size: 18,
              color: _busy ? context.textSecondaryColor : context.accentColor,
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            onPressed: _busy ? null : () => _remove(repo),
            child: Icon(
              CupertinoIcons.trash,
              size: 18,
              color: _busy
                  ? context.textSecondaryColor
                  : CupertinoColors.systemRed,
            ),
          ),
        ],
      ),
    );
  }
}
