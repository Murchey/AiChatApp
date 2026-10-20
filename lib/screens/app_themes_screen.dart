import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../config/theme.dart';
import '../models/app_theme_pack.dart';
import '../models/workshop_repository.dart';
import '../models/workshop_asset.dart';
import '../providers/workshop_provider.dart';
import '../services/app_theme_store.dart';
import '../services/theme_image.dart';
import '../services/cos_auth.dart';
import '../services/workshop_service.dart';
import '../utils/app_toast.dart';
import '../utils/pinyin_util.dart';
import '../widgets/workshop/workshop_repo_widgets.dart';
import '../widgets/workshop/workshop_download_dialogs.dart';
import '../widgets/settings/settings_ui.dart';

class AppThemesScreen extends StatefulWidget {
  const AppThemesScreen({super.key});
  @override
  State<AppThemesScreen> createState() => _AppThemesScreenState();
}

class _AppThemesScreenState extends State<AppThemesScreen> {
  final store = AppThemeStore.instance;
  bool _busy = false;
  int _tab = 0;
  List<ZipItem> _items = [];
  final Set<String> _selected = {};
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _onlineLoaded = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ZipItem> get _visibleItems {
    final query = _query.trim().toLowerCase();
    return _items
        .where((item) =>
            query.isEmpty ||
            item.asset.displayName.toLowerCase().contains(query) ||
            PinyinUtil.fullPinyin(item.asset.displayName).contains(query))
        .toList();
  }

  Future<void> _refresh() => _run(() async {
        if (_tab == 0) {
          await store.init();
        } else {
          await _load(force: true);
        }
      });

  Future<void> _openSources() async {
    await Navigator.push(context,
        CupertinoPageRoute(builder: (_) => const ThemeSourcesScreen()));
    if (!mounted) return;
    if (_tab == 1) {
      await _run(() => _load(force: true));
    } else {
      setState(() => _onlineLoaded = false);
    }
  }

  String? _error;
  int _loadRevision = 0;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showAppToast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showCupertinoDialog<bool>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
                  title: Text(title),
                  content: Text(text),
                  actions: [
                    CupertinoDialogAction(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    CupertinoDialogAction(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('确定')),
                  ])) ??
      false;
  Future<bool> _install(String path) async {
    AppThemePack pack;
    try {
      pack = await store.install(path);
    } on ThemeAlreadyInstalled {
      if (!mounted || !await _confirm('替换主题', '已安装同 ID 主题，是否替换？')) return false;
      pack = await store.install(path, replace: true);
    }
    if (mounted) {
      setState(() => _tab = 0);
      showAppToast('已安装「${pack.name}」，可预览并启用');
    }
    return true;
  }

  Future<void> _local() => _run(() async {
        final picked = await FilePicker.platform
            .pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
        if (picked?.files.single.path != null) {
          await _install(picked!.files.single.path!);
        }
      });
  Future<void> _load({bool force = false}) async {
    final revision = ++_loadRevision;
    setState(() => _error = null);
    final items = <ZipItem>[];
    final errors = <String>[];
    for (final repo in List<WorkshopRepository>.of(store.repositories)) {
      if (force && repo.isCos) WorkshopService.invalidateCosListCache(repo.url);
      try {
        final assets = repo.isCos
            ? await WorkshopService.listCosAssets(repo.url, kThemeStoreTag,
                auth: repo.cosAuth, loadAll: true)
            : await WorkshopService.listAssets(repo.url, kThemeStoreTag);
        items.addAll(assets.map((asset) =>
            ZipItem(asset: asset, repoName: repo.name, repoId: repo.id)));
      } catch (e) {
        errors.add('${repo.name}：$e');
        // A failed refresh keeps this source's previous items available.
        items.addAll(_items.where((item) => item.repoId == repo.id));
      }
      if (!mounted || revision != _loadRevision) return;
    }
    if (!mounted || revision != _loadRevision) return;
    setState(() {
      _items = items;
      _selected.retainAll(items.map((item) => item.key));
      _error = errors.isEmpty ? null : '部分来源加载失败：\n${errors.join('\n')}';
      _onlineLoaded = true;
    });
  }

  Future<void> _downloadSelected() => _run(() async {
        final selected =
            _items.where((item) => _selected.contains(item.key)).toList();
        if (selected.isEmpty) return;
        WorkshopRepository repo(String id) =>
            store.repositories.firstWhere((repo) => repo.id == id);
        final results = await showCupertinoDialog<Map<String, String>>(
            context: context,
            barrierDismissible: false,
            builder: (_) => BatchDownloadDialog(
                forceDownload: true,
                maxBytes: 50 * 1024 * 1024,
                items: selected,
                getProxyUrl: (item) => repo(item.repoId).proxyUrl,
                getCosAuth: (item) => repo(item.repoId).cosAuth));
        if (results == null) return;
        final errors = <String>[];
        try {
          for (final item in selected) {
            if (!mounted) return;
            final path = results[item.key];
            if (path == null) continue;
            try {
              final installed = await _install(path);
              if (!mounted) return;
              if (installed) setState(() => _selected.remove(item.key));
            } catch (e) {
              errors.add('${item.asset.displayName}：$e');
            }
          }
        } finally {
          for (final path in results.values.toSet()) {
            WorkshopService.removeDownloadCache(path);
          }
        }
        if (errors.isNotEmpty && mounted) {
          showAppToast('导入失败：${errors.join('；')}');
        }
      });
  Future<void> _export(AppThemePack pack) => _run(() async {
        final bytes = Uint8List.fromList(await store.export(pack));
        if (Platform.isAndroid) {
          await const MethodChannel('com.aichat.ai_chat/files').invokeMethod(
              'saveFile', {
            'suggestedName': '${pack.id}.zip',
            'mimeType': 'application/zip',
            'bytes': bytes
          });
        } else {
          final path = await FilePicker.platform.saveFile(
              dialogTitle: '导出主题', fileName: '${pack.id}.zip', bytes: bytes);
          if (path != null && !Platform.isIOS) {
            await File(path).writeAsBytes(bytes);
          }
        }
      });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) => DefaultTextStyle.merge(
          style: TextStyle(color: context.textPrimaryColor),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: context.isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              child: CupertinoPageScaffold(
                backgroundColor: context.scaffoldColor,
                navigationBar: settingsNavigationBar(context, '应用主题',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      CupertinoButton(
                          key: const ValueKey('theme-refresh'),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          onPressed: _busy ? null : _refresh,
                          child: Icon(CupertinoIcons.refresh,
                              size: 22, color: context.textSecondaryColor)),
                      CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          onPressed: _busy ? null : _openSources,
                          child: Icon(CupertinoIcons.gear,
                              size: 22, color: context.textSecondaryColor)),
                    ])),
                child: SafeArea(
                    child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: CupertinoSlidingSegmentedControl<int>(
                          groupValue: _tab,
                          backgroundColor: context.fieldBgColor,
                          thumbColor: context.surfaceColor,
                          children: {
                            0: Text('已安装',
                                style:
                                    TextStyle(color: context.textPrimaryColor)),
                            1: Text('在线主题',
                                style:
                                    TextStyle(color: context.textPrimaryColor)),
                          },
                          onValueChanged: (v) {
                            if (!_busy) {
                              setState(() => _tab = v ?? 0);
                              if (_tab == 1 && !_onlineLoaded) {
                                _run(() => _load());
                              }
                            }
                          })),
                  if (_busy)
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: CupertinoActivityIndicator()),
                  Expanded(
                      child: ListView(children: [
                    if (_tab == 0) ...[
                      CupertinoButton(
                          onPressed: _busy ? null : _local,
                          child: _ThemeActionButton(
                              icon: CupertinoIcons.folder_badge_plus,
                              label: '从本地导入 ZIP 主题')),
                      if (store.active != null)
                        CupertinoButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() => store.enable(null)),
                            child: _ThemeActionButton(
                                icon: CupertinoIcons.clear_circled,
                                label: '禁用当前主题')),
                      if (store.installed.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('尚未安装主题。可本地导入或配置在线来源。')),
                      for (final pack in store.installed)
                        Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (pack.preview != null)
                                    Image(
                                        image: themePreviewProvider(pack),
                                        height: 150,
                                        width: double.infinity,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stack) =>
                                            const SizedBox()),
                                  Text(
                                      '${pack.name}${store.activeId == pack.id ? ' · 使用中' : ''}',
                                      style: TextStyle(
                                          fontSize: 18,
                                          color: context.textPrimaryColor)),
                                  Text(
                                      '${pack.manifest['author'] ?? ''}  ${pack.manifest['description'] ?? ''}',
                                      style: TextStyle(
                                          color: context.textSecondaryColor)),
                                  Wrap(children: [
                                    CupertinoButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _run(
                                                () => store.enable(pack.id)),
                                        child: _ThemeActionButton(
                                            icon: CupertinoIcons.checkmark,
                                            label: '启用',
                                            filled: true)),
                                    CupertinoButton(
                                        onPressed:
                                            _busy ? null : () => _export(pack),
                                        child: _ThemeActionButton(
                                            icon: CupertinoIcons.share,
                                            label: '导出')),
                                    CupertinoButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _run(() async {
                                                  if (await _confirm('删除主题',
                                                      '删除「${pack.name}」？若正在使用，将恢复原设置。')) {
                                                    await store.delete(pack.id);
                                                  }
                                                }),
                                        child: const _ThemeActionButton(
                                            icon: CupertinoIcons.trash,
                                            label: '删除',
                                            destructive: true)),
                                  ]),
                                ])),
                    ] else ...[
                      if (store.repositories.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('点击右上角配置仓库或对象存储来源。')),
                      if (store.repositories.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                                '可用仓库：${store.repositories.map((repo) => repo.name).join('、')}',
                                style: TextStyle(
                                    color: context.textSecondaryColor))),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: CupertinoSearchTextField(
                              controller: _search,
                              placeholder: '搜索已加载主题（支持拼音）',
                              onChanged: (value) =>
                                  setState(() => _query = value))),
                      if (_error != null) ...[
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_error!)),
                        CupertinoButton(
                            onPressed: _busy ? null : _refresh,
                            child: _ThemeActionButton(
                                icon: CupertinoIcons.refresh, label: '重试加载')),
                      ],
                      if (_onlineLoaded &&
                          !_busy &&
                          _visibleItems.isEmpty &&
                          _error == null)
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_query.trim().isEmpty
                                ? '该来源暂无在线主题。'
                                : '没有匹配的主题。')),
                      for (final item in _visibleItems)
                        CupertinoListTile(
                            leading: Icon(CupertinoIcons.archivebox,
                                color: context.textSecondaryColor),
                            title: Text(item.asset.displayName),
                            subtitle: Text(item.repoName,
                                style: TextStyle(
                                    color: context.textSecondaryColor)),
                            trailing: Icon(
                                _selected.contains(item.key)
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                color: _selected.contains(item.key)
                                    ? context.accentColor
                                    : context.textSecondaryColor),
                            onTap: _busy
                                ? null
                                : () => setState(() {
                                      if (!_selected.add(item.key)) {
                                        _selected.remove(item.key);
                                      }
                                    })),
                    ],
                  ])),
                  if (_tab == 1)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                            width: double.infinity,
                            child: CupertinoButton.filled(
                                borderRadius: BorderRadius.circular(14),
                                onPressed: _busy || _selected.isEmpty
                                    ? null
                                    : _downloadSelected,
                                child: Text(_busy
                                    ? '正在处理…'
                                    : _selected.isEmpty
                                        ? '请选择要下载的 ZIP'
                                        : '下载导入 (${_selected.length})')))),
                ])),
              ))));
}

class ThemeSourcesScreen extends StatefulWidget {
  const ThemeSourcesScreen({super.key});
  @override
  State<ThemeSourcesScreen> createState() => _ThemeSourcesScreenState();
}

class _ThemeSourcesScreenState extends State<ThemeSourcesScreen> {
  final store = AppThemeStore.instance;
  bool _busy = false;
  Future<void> _edit([WorkshopRepository? old]) async {
    final result = await showCupertinoDialog<
            ({String path, String proxyUrl, String type, CosAuth cosAuth})>(
        context: context,
        builder: (_) => AddRepoDialog(
            title: old == null ? '添加主题来源' : '编辑主题来源',
            initialPath: old?.url,
            initialProxyUrl: old?.proxyUrl,
            initialType: old?.type.name ?? 'git',
            initialCosAuth: old?.cosAuth ?? const CosAuth()));
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final cos = result.type == 'cos';
      final assets = cos
          ? await WorkshopService.listCosAssets(result.path, kThemeStoreTag,
              auth: result.cosAuth, loadAll: true)
          : await WorkshopService.listAssets(result.path, kThemeStoreTag);
      final repo = WorkshopRepository(
          id: old?.id ?? const Uuid().v4(),
          name: cos ? WorkshopService.cosDisplayName(result.path) : result.path,
          url: result.path,
          proxyUrl: result.proxyUrl,
          type: cos ? WorkshopRepoType.cos : WorkshopRepoType.git,
          cosAuth: result.cosAuth,
          availableTags: assets.isEmpty ? [] : [kThemeStoreTag]);
      await store.saveRepositories(
          [...store.repositories.where((r) => r.id != old?.id), repo]);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showAppToast('来源检测失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final repos = context.read<WorkshopProvider>().repositories;
    if (repos.isEmpty) {
      showAppToast('尚未配置创意工坊仓库');
      return;
    }
    await store.saveRepositories([
      ...store.repositories,
      ...repos.where((r) => !store.repositories.any((t) => t.url == r.url))
    ]);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
      style: TextStyle(color: context.textPrimaryColor),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: context.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: CupertinoPageScaffold(
            backgroundColor: context.scaffoldColor,
            navigationBar: settingsNavigationBar(context, '主题内容来源',
                trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _busy ? null : _edit,
                    child: const Icon(CupertinoIcons.add))),
            child: SafeArea(
                child: ListView(children: [
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'GitHub/Gitee：ThemeStore Release 下的 ZIP。对象存储：配置路径/Theme/ 下的 ZIP，需具备列举和读取权限。')),
              CupertinoButton(
                  onPressed: _busy ? null : _copy,
                  child: _ThemeActionButton(
                      icon: CupertinoIcons.arrow_down_doc,
                      label: '从创意工坊复制来源配置')),
              if (_busy) const CupertinoActivityIndicator(),
              for (final repo in store.repositories)
                CupertinoListTile(
                    title: Text(repo.name),
                    subtitle: Text(repo.url,
                        style: TextStyle(color: context.textSecondaryColor)),
                    onTap: _busy ? null : () => _edit(repo),
                    trailing: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _busy
                            ? null
                            : () async {
                                await store.saveRepositories(store.repositories
                                    .where((r) => r.id != repo.id)
                                    .toList());
                                if (mounted) setState(() {});
                              },
                        child: const Icon(CupertinoIcons.trash,
                            color: CupertinoColors.systemRed))),
            ])),
          )));
}

/// 主题二级页统一的轻量操作按钮，沿用设置页的圆角、描边和字号。
class _ThemeActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool destructive;

  const _ThemeActionButton({
    required this.icon,
    required this.label,
    this.filled = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? CupertinoColors.systemRed : context.accentColor;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: filled ? color : context.fieldBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: filled ? color : context.settingsOutlineColor,
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: filled ? CupertinoColors.white : color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: filled ? CupertinoColors.white : color,
              )),
        ],
      ),
    );
  }
}
