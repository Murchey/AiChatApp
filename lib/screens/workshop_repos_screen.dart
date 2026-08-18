import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/workshop_repository.dart';
import '../providers/workshop_provider.dart';
import '../services/update_service.dart';

/// 配置可用仓库：列出已添加的角色卡仓库，右上角加号弹窗添加仓库并自动检查可用性。
class WorkshopReposScreen extends StatefulWidget {
  const WorkshopReposScreen({super.key});

  @override
  State<WorkshopReposScreen> createState() => _WorkshopReposScreenState();
}

class _WorkshopReposScreenState extends State<WorkshopReposScreen> {
  bool _busy = false;

  /// 弹窗添加仓库 → 自动检查可用性 → 提示成功后返回上一级页面
  Future<void> _showAddDialog() async {
    if (_busy) return;
    final result = await showCupertinoDialog<({String path, String proxyUrl})>(
      context: context,
      builder: (_) => const _AddRepoDialog(),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final provider = context.read<WorkshopProvider>();
      final repo = await provider.addRepository(
        path: result.path,
        proxyUrl: result.proxyUrl,
      );
      if (!mounted) return;
      await _showTip(
        repo.isAvailable
            ? '仓库添加成功，可用分类：${_tagsLabel(repo)}'
            : '仓库已添加，但未检测到可用的资产 tag',
      );
      // 完成添加后返回上一级（创意工坊）页面
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) await _showTip('仓库添加失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _tagsLabel(WorkshopRepository repo) {
    final parts = <String>[
      if (repo.hasCharacter) '角色分类(V1.1.0)',
      if (repo.hasGame) '游戏分类(V1.0.0)',
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

  /// 编辑仓库：弹窗预填当前路径/代理，保存后重新检查可用性
  Future<void> _edit(WorkshopRepository repo) async {
    if (_busy) return;
    final result = await showCupertinoDialog<({String path, String proxyUrl})>(
      context: context,
      builder: (_) => _AddRepoDialog(
        title: '编辑仓库',
        initialPath: repo.url,
        initialProxyUrl: repo.proxyUrl,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final provider = context.read<WorkshopProvider>();
      final updated = await provider.updateRepository(
        repo: repo,
        path: result.path,
        proxyUrl: result.proxyUrl,
      );
      if (!mounted) return;
      await _showTip(
        updated.isAvailable
            ? '仓库已更新，可用分类：${_tagsLabel(updated)}'
            : '仓库已更新，但未检测到可用的资产 tag',
      );
    } catch (e) {
      if (mounted) await _showTip('仓库更新失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(WorkshopRepository repo) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('移除仓库'),
        content: Text('确定移除仓库「${repo.name}」吗？'),
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
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                          style: TextStyle(
                            fontSize: 15,
                            color: context.textPrimaryColor,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          size: 20,
                          color: context.accentColor,
                        ),
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
              color: CupertinoColors.systemGroupedBackground,
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
            color: context.accentColor,
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
            const Spacer(),
            Text(
              notifyRepo?.name ?? '请选择',
              style: TextStyle(
                fontSize: 14,
                color: notifyRepo != null
                    ? context.textSecondaryColor
                    : CupertinoColors.systemGrey,
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
    final proxyIdx = kProxySources.indexOf(repo.proxyUrl);
    final proxyLabel = repo.proxyUrl.isEmpty
        ? '不使用代理'
        : (proxyIdx >= 0 ? '代理 ${proxyIdx + 1}' : '自定义代理');

    return Container(
      color: context.listBgColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$repo.url · $proxyLabel',
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
                  Row(
                    children: [
                      if (repo.hasCharacter)
                        const _TagChip(text: '角色分类 V1.1.0'),
                      if (repo.hasGame) ...[
                        const SizedBox(width: 6),
                        const _TagChip(
                          text: '游戏分类 V1.0.0',
                          color: Color(0xFF3B82F6),
                        ),
                      ],
                    ],
                  )
                else
                  Text(
                    '未检测到可用 tag',
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

/// 仓库可用 tag 标记
class _TagChip extends StatelessWidget {
  final String text;
  final Color color;

  const _TagChip({
    required this.text,
    this.color = const Color(0xFF34C759),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 添加 / 编辑仓库弹窗：下载代理选项（不使用 / 内置代理 / 自定义）+ 仓库路径
class _AddRepoDialog extends StatefulWidget {
  final String title;
  final String? initialPath;
  final String? initialProxyUrl;

  const _AddRepoDialog({
    this.title = '添加仓库',
    this.initialPath,
    this.initialProxyUrl,
  });

  @override
  State<_AddRepoDialog> createState() => _AddRepoDialogState();
}

class _AddRepoDialogState extends State<_AddRepoDialog> {
  late final TextEditingController _pathController;
  late String _proxyUrl; // 当前代理选择（空 = 不使用代理）
  late String _customProxy; // 用户输入的自定义代理
  String? _hint;

  @override
  void initState() {
    super.initState();
    final initProxy = widget.initialProxyUrl ?? '';
    _pathController = TextEditingController(text: widget.initialPath ?? '');
    _proxyUrl = initProxy;
    // 初始代理为自定义时，回填自定义输入框内容
    _customProxy =
        initProxy.isNotEmpty && !kProxySources.contains(initProxy) ? initProxy : '';
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  String get _proxyLabel {
    if (_proxyUrl.isEmpty) return '不使用代理';
    final idx = kProxySources.indexOf(_proxyUrl);
    if (idx >= 0) return '代理 ${idx + 1}';
    return '自定义';
  }

  /// 弹出下载代理选择（底部弹层）：不使用代理 / 内置代理 / 自定义
  void _pickProxy() {
    final isCustom = _proxyUrl.isNotEmpty && !kProxySources.contains(_proxyUrl);
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('选择下载代理'),
        message: const Text('用于加速 GitHub 仓库资产下载，Gitee 仓库无需代理'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: _proxyUrl.isEmpty,
            onPressed: () {
              setState(() => _proxyUrl = '');
              Navigator.pop(ctx);
            },
            child: const Text('不使用代理'),
          ),
          for (var i = 0; i < kProxySources.length; i++)
            CupertinoActionSheetAction(
              isDefaultAction: _proxyUrl == kProxySources[i],
              onPressed: () {
                setState(() => _proxyUrl = kProxySources[i]);
                Navigator.pop(ctx);
              },
              child: Text('代理 ${i + 1}'),
            ),
          CupertinoActionSheetAction(
            isDefaultAction: isCustom,
            onPressed: () {
              Navigator.pop(ctx);
              _showCustomProxyDialog();
            },
            child: const Text('自定义'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 自定义代理源输入弹窗
  void _showCustomProxyDialog() {
    final controller = TextEditingController(text: _customProxy);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('自定义代理源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              '请输入代理源 URL 前缀',
              style: TextStyle(
                fontSize: 13,
                color: ctx.isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: controller,
              placeholder: 'https://example.com/',
              autofocus: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                setState(() {
                  _customProxy = url;
                  _proxyUrl = url;
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _hint = '请输入仓库路径');
      return;
    }
    Navigator.pop(context, (path: path, proxyUrl: _proxyUrl));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          // 下载代理选项
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickProxy,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(
                    '下载代理',
                    style: TextStyle(
                      fontSize: 15,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _proxyLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    CupertinoIcons.chevron_down,
                    size: 14,
                    color: context.textSecondaryColor,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 仓库路径
          CupertinoTextField(
            controller: _pathController,
            autofocus: true,
            placeholder: 'owner/repo 或仓库 URL',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onChanged: (_) {
              if (_hint != null) setState(() => _hint = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 6),
          Text(
            _hint ?? '例如：Murchey/AiChatCharacterCommunity',
            style: TextStyle(
              fontSize: 12,
              color: _hint != null
                  ? CupertinoColors.systemRed
                  : context.textSecondaryColor,
            ),
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
