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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<StoryProvider>();
      await provider.init();
      if (!mounted) return;
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
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
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
    await Navigator.push<void>(
      context,
      CupertinoPageRoute(
        builder: (_) => const StoryCommunitySettingsScreen(),
      ),
    );
    if (!mounted) return;
    final changed = before != jsonEncode(provider.config.toJson());
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
    final hasStateItem =
        provider.loading || provider.error != null || provider.entries.isEmpty;
    final itemCount = 1 + (hasStateItem ? 1 : provider.entries.length);

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
                      ? '来源：' + provider.config.type.displayName
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
                          '故事设定 · v' + entry.version.toString(),
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
                            '#' + tag,
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
                      '下载 ' + entry.downloadCount.toString(),
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

class StoryDetailScreen extends StatefulWidget {
  final StoryCatalogEntry entry;

  const StoryDetailScreen({super.key, required this.entry});

  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<StoryDetailScreen> {
  StoryPackage? _story;
  String? _error;
  Character? _selectedCharacter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final story =
          await context.read<StoryProvider>().loadPackage(widget.entry);
      if (mounted)
        setState(() {
          _story = story;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
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
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
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
            SettingsSection(
              title: '章节预览',
              children: [
                for (final chapter in story.chapters)
                  SettingsRow(
                    icon: CupertinoIcons.book,
                    title:
                        Text(chapter.title.isEmpty ? '未命名章节' : chapter.title),
                    subtitle: Text('${chapter.memories.length} 条故事记忆'),
                  ),
              ],
            ),
            SettingsSection(
              title: '安装到角色',
              children: [
                SettingsInlinePicker<Character?>(
                  value: _selectedCharacter,
                  options: [
                    for (final character in characters)
                      SettingsChoiceOption<Character?>(
                        value: character,
                        label: character.displayName,
                        subtitle: '将故事设定作为独立记忆源安装',
                      ),
                  ],
                  onChanged: (character) =>
                      setState(() => _selectedCharacter = character),
                  panelKey: 'story-character-picker',
                  rowBuilder: (context, toggle) => SettingsRow(
                    leading: _selectedCharacter == null
                        ? const Icon(CupertinoIcons.person_crop_circle)
                        : CharacterAvatar(
                            base64: _selectedCharacter!.avatar, size: 38),
                    title: Text(_selectedCharacter?.displayName ?? '选择本地角色'),
                    subtitle: const Text('故事线记忆不会覆盖已有记忆'),
                    showChevron: true,
                    onTap: toggle,
                  ),
                ),
                SettingsRow(
                  icon: CupertinoIcons.arrow_down_circle,
                  iconColor: context.accentColor,
                  title: const Text('下载并安装'),
                  subtitle: const Text('同一故事再次安装会更新原有故事记忆'),
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
}
