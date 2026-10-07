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

class StoryCommunityScreen extends StatefulWidget {
  const StoryCommunityScreen({super.key});

  @override
  State<StoryCommunityScreen> createState() => _StoryCommunityScreenState();
}

class _StoryCommunityScreenState extends State<StoryCommunityScreen> {
  final _queryController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _portController = TextEditingController();
  final _tokenController = TextEditingController();
  final _indexController = TextEditingController();
  final _repositoryController = TextEditingController();
  final _branchController = TextEditingController();
  final _pathController = TextEditingController();
  bool _configured = false;
  String? _selectedTag;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<StoryProvider>();
      await provider.init();
      if (!mounted) return;
      _loadControllers(provider.config);
      await provider.loadCatalog();
      if (mounted) setState(() => _configured = true);
    });
  }

  void _loadControllers(StorySourceConfig config) {
    _baseUrlController.text = config.baseUrl;
    _portController.text = config.port;
    _tokenController.text = config.token;
    _indexController.text = config.indexUrl;
    _repositoryController.text = config.repository;
    _branchController.text = config.branch;
    _pathController.text = config.path;
  }

  @override
  void dispose() {
    for (final controller in [
      _queryController,
      _baseUrlController,
      _portController,
      _tokenController,
      _indexController,
      _repositoryController,
      _branchController,
      _pathController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveConfig({bool reload = true}) async {
    final provider = context.read<StoryProvider>();
    final current = provider.config;
    await provider.saveConfig(current.copyWith(
      baseUrl: _baseUrlController.text.trim(),
      port: _portController.text.trim(),
      token: _tokenController.text.trim(),
      indexUrl: _indexController.text.trim(),
      repository: _repositoryController.text.trim(),
      branch: _branchController.text.trim().isEmpty
          ? 'main'
          : _branchController.text.trim(),
      path: _pathController.text.trim().isEmpty
          ? 'index.json'
          : _pathController.text.trim(),
    ));
    if (reload) await provider.loadCatalog();
  }

  Future<void> _testConnection() async {
    try {
      await _saveConfig(reload: false);
      await context.read<StoryProvider>().testConnection();
      if (mounted) showAppToast('连接成功');
    } catch (e) {
      if (mounted) showAppToast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _search() async {
    await context.read<StoryProvider>().loadCatalog(
          query: _queryController.text,
          tag: _selectedTag,
        );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoryProvider>();
    final config = provider.config;
    final tags = provider.entries.expand((entry) => entry.tags).toSet().toList()
      ..sort();
    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(
        context,
        '故事线社区',
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: provider.loading ? null : () => provider.loadCatalog(),
          child: const Icon(CupertinoIcons.refresh),
        ),
      ),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        key: const PageStorageKey<String>('story-community-list'),
        padding: settingsPageContentPadding(
          context,
          bottom: UiSpec.floatingContentBottomInset +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          SettingsSection(
            title: '内容来源',
            children: [
              SettingsInlinePicker<StorySourceType>(
                value: config.type,
                options: [
                  for (final type in StorySourceType.values)
                    SettingsChoiceOption(
                      value: type,
                      label: type.displayName,
                      subtitle: type.description,
                    ),
                ],
                onChanged: (type) async {
                  await provider.saveConfig(config.copyWith(type: type));
                  _loadControllers(provider.config);
                  if (mounted) await provider.loadCatalog();
                },
                panelKey: 'story-source-picker',
                rowBuilder: (context, toggle) => SettingsRow(
                  icon: CupertinoIcons.cloud,
                  title: const Text('故事来源'),
                  subtitle: Text(config.type.description),
                  trailing: settingsValueText(context, config.type.displayName),
                  showChevron: true,
                  onTap: toggle,
                ),
              ),
              ..._buildConfigRows(context, config),
            ],
          ),
          SettingsSection(
            title: '浏览故事',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoSearchTextField(
                        controller: _queryController,
                        placeholder: '搜索标题、简介或标签',
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      onPressed: _search,
                      child: const Text('搜索'),
                    ),
                  ],
                ),
              ),
              if (tags.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    scrollDirection: Axis.horizontal,
                    itemCount: tags.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final tag = index == 0 ? null : tags[index - 1];
                      final selected = _selectedTag == tag;
                      return CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
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
              if (provider.loading)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              else if (provider.error != null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        provider.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textSecondaryColor),
                      ),
                      const SizedBox(height: 10),
                      CupertinoButton(
                        onPressed: () => provider.loadCatalog(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              else if (provider.entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _configured ? '暂无故事内容，请先配置来源或刷新' : '正在读取故事来源…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textSecondaryColor),
                  ),
                )
              else
                for (final entry in provider.entries)
                  _StoryEntryTile(entry: entry),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildConfigRows(
      BuildContext context, StorySourceConfig config) {
    if (config.type == StorySourceType.server) {
      return [
        _textRow('服务器地址', _baseUrlController, 'https://example.com'),
        _textRow('端口', _portController, '8080',
            keyboardType: TextInputType.number),
        _textRow('设备令牌（可选）', _tokenController, 'Bearer token'),
        SettingsRow(
          icon: CupertinoIcons.link,
          title: const Text('测试连接'),
          subtitle: const Text('请求 /api/health 检查服务是否可用'),
          trailing: const Icon(CupertinoIcons.arrow_right, size: 18),
          onTap: _testConnection,
        ),
      ];
    }
    if (config.type == StorySourceType.cos) {
      return [
        _textRow('对象存储公共地址', _baseUrlController, 'https://bucket.example.com'),
        _textRow('索引地址（可选）', _indexController, 'https://.../index.json'),
        _textRow('索引路径', _pathController, 'index.json'),
        SettingsRow(
          icon: CupertinoIcons.link,
          title: const Text('保存并测试来源'),
          subtitle: const Text('使用公共只读地址，不在 App 内保存 AccessKey'),
          trailing: const Icon(CupertinoIcons.arrow_right, size: 18),
          onTap: _testConnection,
        ),
      ];
    }
    return [
      _textRow('索引地址（可选）', _indexController, 'https://.../index.json'),
      _textRow('仓库地址', _repositoryController, 'owner/repository'),
      _textRow('分支', _branchController, 'main'),
      _textRow('索引路径', _pathController, 'index.json'),
      SettingsRow(
        icon: CupertinoIcons.link,
        title: const Text('保存并测试来源'),
        subtitle: const Text('静态来源只读取公开 JSON，不保存平台密钥'),
        trailing: const Icon(CupertinoIcons.arrow_right, size: 18),
        onTap: _testConnection,
      ),
    ];
  }

  Widget _textRow(
    String title,
    TextEditingController controller,
    String placeholder, {
    TextInputType? keyboardType,
  }) {
    return SettingsRow(
      icon: CupertinoIcons.pencil,
      title: Text(title),
      subtitle: CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          keyboardType: keyboardType,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: context.fieldBgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          onSubmitted: (_) => _saveConfig()),
    );
  }
}

class _StoryEntryTile extends StatelessWidget {
  final StoryCatalogEntry entry;

  const _StoryEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<StoryProvider>();
    return SettingsRow(
      icon: CupertinoIcons.book_fill,
      iconColor: const Color(0xFF6C7FA8),
      title: Text(entry.title),
      subtitle: Text(
        [
          if (entry.author.isNotEmpty) entry.author,
          if (entry.summary.isNotEmpty) entry.summary,
          'v${entry.version}',
          if (provider.supportsServerStats && entry.downloadCount != null)
            '下载 ${entry.downloadCount}',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: entry.tags.isEmpty
          ? null
          : Text(
              entry.tags.first,
              style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
            ),
      showChevron: true,
      onTap: () => Navigator.push(
        context,
        CupertinoPageRoute(builder: (_) => StoryDetailScreen(entry: entry)),
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
