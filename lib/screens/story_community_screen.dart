import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../config/ui_spec.dart';
import '../models/character.dart';
import '../models/story_package.dart';
import '../providers/character_provider.dart';
import '../providers/memory_point_provider.dart';
import '../providers/story_provider.dart';
import '../services/backend_http_client.dart';
import '../services/story_service.dart';
import '../utils/app_toast.dart';
import '../widgets/character_avatar.dart';
import '../widgets/settings/settings_ui.dart';
import 'story_community_settings_screen.dart';

class StoryCommunityScreen extends StatefulWidget {
  const StoryCommunityScreen({super.key});

  @override
  State<StoryCommunityScreen> createState() => _StoryCommunityScreenState();
}

class _StoryCommunityScreenState extends State<StoryCommunityScreen> {
  final _queryController = TextEditingController();
  bool _ready = false;
  String? _selectedTag;
  StoryProvider? _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<StoryProvider>();
      _provider = provider;
      await provider.init();
      if (!mounted) return;
      setState(() => _ready = true);
      if (provider.isConfigured) {
        await provider.loadCatalog();
      }
      if (mounted) {
        setState(() {
          _ready = true;
        });
      }
    });
  }

  @override
  void dispose() {
    // Leave no health/version probe or catalog request running after the feed
    // leaves the navigator; this also prevents late status notifications.
    _provider?.cancelRequests();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_queryController.text.trim().isEmpty && _selectedTag == null) {
      context.read<StoryProvider>().restoreCachedCatalog();
      return;
    }
    await context.read<StoryProvider>().loadCatalog(
          query: _queryController.text,
          tag: _selectedTag,
        );
  }

  Future<void> _openSettings() async {
    final provider = context.read<StoryProvider>();
    await provider.init();
    if (!mounted) return;
    final before = jsonEncode(provider.config.toJson());
    final beforeToken = provider.backend.config.accessToken;
    provider.cancelCatalog();
    await Navigator.push<void>(
      context,
      CupertinoPageRoute(
        builder: (_) => const StoryCommunitySettingsScreen(),
      ),
    );
    if (!mounted) return;
    final changed = before != jsonEncode(provider.config.toJson()) ||
        beforeToken != provider.backend.config.accessToken;
    if (changed) {
      _queryController.clear();
      _selectedTag = null;
      if (provider.isConfigured) await provider.loadCatalog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoryProvider>();
    final tags = provider.entries.expand((entry) => entry.tags).toSet().toList()
      ..sort();
    final hasStateItem = !_ready || provider.entries.isEmpty;
    final hasFooter = !hasStateItem &&
        (provider.hasMore || provider.loadingMore || provider.error != null);
    final itemCount =
        1 + (hasStateItem ? 1 : provider.entries.length + (hasFooter ? 1 : 0));

    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(
        context,
        '故事线社区',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(36, 36),
              onPressed: provider.loading ? null : _refresh,
              child: const Icon(CupertinoIcons.refresh, size: 20),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(36, 36),
              onPressed: _openSettings,
              child: const Icon(CupertinoIcons.gear, size: 20),
            ),
          ],
        ),
      ),
      backgroundColor: context.scaffoldColor,
      child: ListView.builder(
        key: const PageStorageKey<String>('story-community-feed-list'),
        padding: settingsPageContentPadding(
          context,
          bottom: UiSpec.floatingContentBottomInset +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildFeedHeader(context, provider, tags);
          }
          if (hasStateItem) {
            return _buildFeedState(context, provider);
          }
          if (index - 1 == provider.entries.length) {
            return _buildFeedFooter(context, provider);
          }
          final entry = provider.entries[index - 1];
          return _StoryFeedCard(
            entry: entry,
            showDownloadCount: provider.supportsServerStats,
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => StoryDetailScreen(entry: entry),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _refresh() async {
    final provider = context.read<StoryProvider>();
    if (!provider.isConfigured) {
      await _openSettings();
      return;
    }
    await provider.loadCatalog(
      query: _queryController.text,
      tag: _selectedTag,
      force: true,
    );
  }

  Widget _buildFeedHeader(
    BuildContext context,
    StoryProvider provider,
    List<String> tags,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.book,
                size: 18,
                color: context.textSecondaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  provider.isConfigured
                      ? '来源：${provider.config.type.displayName}'
                      : '还没有配置故事来源',
                  style: TextStyle(
                    fontSize: UiSpec.settingsRowSubtitle,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
              if (!provider.isConfigured)
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  minimumSize: Size.zero,
                  onPressed: _openSettings,
                  child: const Text('去设置'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: CupertinoSearchTextField(
                  controller: _queryController,
                  placeholder: '搜索故事标题、简介或标签',
                  onSubmitted: (_) => _search(),
                  onChanged: (value) {
                    if (value.trim().isEmpty && _selectedTag == null) {
                      context.read<StoryProvider>().restoreCachedCatalog();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton.filled(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                minimumSize: Size.zero,
                onPressed: provider.isConfigured ? _search : _openSettings,
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
        if (provider.usingCache)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '当前显示已缓存内容，连接恢复后可刷新最新故事',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
          ),
        if (tags.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: tags.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final tag = index == 0 ? null : tags[index - 1];
                final selected = _selectedTag == tag;
                return CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  color: selected
                      ? context.accentColor.withValues(alpha: 0.14)
                      : context.fieldBgColor,
                  onPressed: () async {
                    setState(() => _selectedTag = tag);
                    await _search();
                  },
                  child: Text(
                    tag ?? '全部',
                    style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? context.accentColor
                          : context.textSecondaryColor,
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildFeedState(BuildContext context, StoryProvider provider) {
    if (!_ready || provider.loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (provider.error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
        child: Column(
          children: [
            Text(
              provider.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondaryColor),
            ),
            const SizedBox(height: 10),
            CupertinoButton(
              onPressed: provider.loading ? null : _refresh,
              child: const Text('重试'),
            ),
            CupertinoButton(
                onPressed: _openSettings, child: const Text('重新配置服务器或切换来源')),
            if (provider.canUseStaticFallback)
              CupertinoButton(
                  onPressed: () => provider.useStaticFallback(),
                  child: const Text('使用上次的静态来源')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 44),
      child: Column(
        children: [
          Icon(
            provider.isConfigured ? CupertinoIcons.book : CupertinoIcons.cloud,
            size: 30,
            color: context.textSecondaryColor,
          ),
          const SizedBox(height: 12),
          Text(
            provider.isConfigured ? '暂无故事内容' : '请先配置故事来源',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textSecondaryColor),
          ),
          if (!provider.isConfigured) ...[
            const SizedBox(height: 10),
            CupertinoButton(
              onPressed: _openSettings,
              child: const Text('打开故事线设置'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeedFooter(BuildContext context, StoryProvider provider) {
    if (provider.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (provider.error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
        child: Column(
          children: [
            Text(provider.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondaryColor)),
            CupertinoButton(
                onPressed: provider.loading ? null : _retry,
                child: const Text('重试加载')),
            CupertinoButton(
                onPressed: _openSettings, child: const Text('重新配置服务器或切换来源')),
            if (provider.canUseStaticFallback)
              CupertinoButton(
                  onPressed: () => provider.useStaticFallback(),
                  child: const Text('使用上次的静态来源')),
          ],
        ),
      );
    }
    if (!provider.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: CupertinoButton(onPressed: _loadMore, child: const Text('加载更多故事')),
    );
  }

  Future<void> _loadMore() => context.read<StoryProvider>().loadMoreCatalog(
        query: _queryController.text,
        tag: _selectedTag,
      );

  Future<void> _retry() => context
      .read<StoryProvider>()
      .retryCatalog(query: _queryController.text, tag: _selectedTag);
}

class _StoryFeedCard extends StatelessWidget {
  final StoryCatalogEntry entry;
  final bool showDownloadCount;
  final VoidCallback onTap;

  const _StoryFeedCard({
    required this.entry,
    required this.showDownloadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final author = entry.author.trim().isEmpty ? '故事线社区' : entry.author.trim();
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: context.fieldBgColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      CupertinoIcons.book,
                      size: 21,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '故事设定 · v${entry.version}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 17,
                    color: context.textSecondaryColor.withValues(alpha: 0.7),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                entry.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimaryColor,
                  height: 1.25,
                ),
              ),
              if (entry.summary.trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  entry.summary.trim(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: context.textPrimaryColor.withValues(alpha: 0.86),
                  ),
                ),
              ],
              if (entry.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in entry.tags.take(5))
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.fieldBgColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 11),
              Row(
                children: [
                  Text(
                    '查看详情',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.accentColor,
                    ),
                  ),
                  if (showDownloadCount && entry.downloadCount != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      '下载 ${entry.downloadCount}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 0.5, color: context.settingsDividerColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryCharacterPickerScreen extends StatefulWidget {
  final Character? selected;
  const _StoryCharacterPickerScreen({this.selected});

  @override
  State<_StoryCharacterPickerScreen> createState() =>
      _StoryCharacterPickerScreenState();
}

class _StoryCharacterPickerScreenState
    extends State<_StoryCharacterPickerScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = context.watch<CharacterProvider>().manageableCharacters;
    final query = _search.text.trim().toLowerCase();
    final characters = query.isEmpty
        ? all
        : all
            .where((c) => c.displayName.toLowerCase().contains(query))
            .toList();
    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(context, '选择本地角色'),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        padding: settingsPageContentPadding(context),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: CupertinoSearchTextField(
              controller: _search,
              placeholder: '搜索角色',
              onChanged: (_) => setState(() {}),
            ),
          ),
          SettingsSection(
            title: '本地角色',
            children: [
              for (final character in characters)
                SettingsRow(
                  leading: CharacterAvatar(base64: character.avatar, size: 38),
                  title: Text(character.displayName),
                  subtitle: const Text('首次导入故事记忆点'),
                  trailing: character.id == widget.selected?.id
                      ? Icon(CupertinoIcons.check_mark,
                          color: context.accentColor)
                      : null,
                  onTap: () => Navigator.of(context).pop(character),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class StoryDetailScreen extends StatefulWidget {
  final StoryCatalogEntry entry;

  const StoryDetailScreen({super.key, required this.entry});

  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<StoryDetailScreen> {
  BackendRequestScope _request = BackendRequestScope();
  StoryPackage? _story;
  String? _error;
  Character? _selectedCharacter;
  bool _loading = true;
  bool _showMemories = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    _request.cancel();
    _request = BackendRequestScope();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final story = await context
          .read<StoryProvider>()
          .loadPackage(widget.entry, scope: _request);
      if (mounted) {
        setState(() {
          _story = story;
          _loading = false;
        });
      }
    } catch (e) {
      if (e is RequestCancelled) return;
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _request.cancel();
    super.dispose();
  }

  Future<void> _install() async {
    final story = _story;
    final character = _selectedCharacter;
    if (story == null || character == null) {
      showAppToast('请选择要绑定的角色');
      return;
    }
    await context.read<MemoryPointProvider>().installStory(character.id, story);
    if (mounted) showAppToast('已安装到「${character.displayName}」的故事线记忆');
  }

  @override
  Widget build(BuildContext context) {
    final characters = context.watch<CharacterProvider>().manageableCharacters;
    final story = _story;
    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(context, widget.entry.title),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        key: const PageStorageKey<String>('story-detail-list'),
        padding: settingsPageContentPadding(context),
        children: [
          if (_loading)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(children: [
                const CupertinoActivityIndicator(),
                CupertinoButton(
                    onPressed: () {
                      _request.cancel();
                      setState(() {
                        _loading = false;
                        _error = '下载已取消，可以重试';
                      });
                    },
                    child: const Text('取消下载'))
              ]),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Text(_error!, textAlign: TextAlign.center),
                CupertinoButton(onPressed: _load, child: const Text('重试下载'))
              ]),
            )
          else if (story != null) ...[
            SettingsSection(
              title: '故事信息',
              children: [
                SettingsRow(
                  icon: CupertinoIcons.book,
                  title: Text(story.title),
                  subtitle: Text(
                    [
                      if (story.author.isNotEmpty) story.author,
                      'v${story.version}',
                      if (story.publishedAt.isNotEmpty) story.publishedAt,
                      ...story.tags
                    ].join(' · '),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    story.summary.isEmpty ? '暂无简介' : story.summary,
                    style: TextStyle(
                        height: 1.5, color: context.textSecondaryColor),
                  ),
                ),
              ],
            ),
            _buildPost(context, story),
            SettingsSection(
              title: '故事记忆点',
              children: [
                SettingsRow(
                  icon: CupertinoIcons.book,
                  title: Text(_showMemories ? '收起记忆点' : '展开记忆点'),
                  subtitle: Text('${story.memories.length} 条记忆点，仅安装时写入角色'),
                  showChevron: true,
                  onTap: () => setState(() => _showMemories = !_showMemories),
                ),
                if (_showMemories)
                  for (var i = 0; i < story.memories.length; i++)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: Text(
                        '${i + 1}. ${story.memories[i].content}',
                        style: TextStyle(
                            color: context.textPrimaryColor, height: 1.45),
                      ),
                    ),
              ],
            ),
            SettingsSection(
              title: '安装到角色',
              children: [
                SettingsRow(
                  leading: _selectedCharacter == null
                      ? const Icon(CupertinoIcons.person_crop_circle)
                      : CharacterAvatar(
                          base64: _selectedCharacter!.avatar, size: 38),
                  title: Text(_selectedCharacter?.displayName ?? '选择本地角色'),
                  subtitle: const Text('故事线记忆不会覆盖已有记忆'),
                  showChevron: true,
                  onTap: () async {
                    final character = await Navigator.push<Character?>(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => _StoryCharacterPickerScreen(
                          selected: _selectedCharacter,
                        ),
                      ),
                    );
                    if (mounted && character != null) {
                      setState(() => _selectedCharacter = character);
                    }
                  },
                ),
                SettingsRow(
                  icon: CupertinoIcons.arrow_down_circle,
                  iconColor: context.accentColor,
                  title: const Text('下载并安装'),
                  subtitle: const Text('仅首次导入故事记忆点，之后不会主动覆盖角色记录'),
                  trailing: const Icon(CupertinoIcons.arrow_right, size: 18),
                  onTap: characters.isEmpty ? null : _install,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPost(BuildContext context, StoryPackage story) {
    final provider = context.read<StoryProvider>();
    Uri? detailUri;
    if (provider.config.type != StorySourceType.server) {
      final indexUri = StoryService.staticIndexUri(provider.config);
      detailUri = StoryService.resolveStaticFile(indexUri, widget.entry.file);
    }
    return SettingsSection(
      title: '帖子正文',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            story.introduction.isEmpty ? story.summary : story.introduction,
            style: TextStyle(
                fontSize: 16, height: 1.55, color: context.textPrimaryColor),
          ),
        ),
        for (final image in story.images)
          if (detailUri != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  detailUri.resolve(image).toString(),
                  headers: StoryService.staticHeaders(
                      provider.config, detailUri.resolve(image)),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
      ],
    );
  }
}
