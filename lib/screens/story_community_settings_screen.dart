import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../config/ui_spec.dart';
import '../models/story_package.dart';
import '../providers/story_provider.dart';
import '../utils/app_toast.dart';
import '../widgets/settings/settings_ui.dart';

/// Story source configuration is kept separate from the feed so the main
/// page can stay focused on browsing stories.
class StoryCommunitySettingsScreen extends StatefulWidget {
  const StoryCommunitySettingsScreen({super.key});

  @override
  State<StoryCommunitySettingsScreen> createState() =>
      _StoryCommunitySettingsScreenState();
}

class _StoryCommunitySettingsScreenState
    extends State<StoryCommunitySettingsScreen> {
  final _baseUrlController = TextEditingController();
  final _portController = TextEditingController();
  final _tokenController = TextEditingController();
  final _indexController = TextEditingController();
  final _repositoryController = TextEditingController();
  final _branchController = TextEditingController();
  final _pathController = TextEditingController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<StoryProvider>();
      await provider.init();
      if (!mounted) return;
      _loadControllers(provider.config);
      setState(() => _ready = true);
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

  Future<void> _saveConfig() async {
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
  }

  Future<void> _testConnection() async {
    final provider = context.read<StoryProvider>();
    try {
      await _saveConfig();
      await provider.testConnection();
      if (mounted) showAppToast('连接成功');
    } catch (error) {
      if (mounted) showAppToast(provider.readableError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoryProvider>();
    final config = provider.config;
    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(context, '故事线设置'),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        key: const PageStorageKey<String>('story-community-settings-list'),
        padding: settingsPageContentPadding(
          context,
          bottom: UiSpec.floatingContentBottomInset +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          if (!_ready)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CupertinoActivityIndicator()),
            )
          else ...[
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
                    if (mounted) _loadControllers(provider.config);
                  },
                  panelKey: 'story-community-source-picker',
                  rowBuilder: (context, toggle) => SettingsRow(
                    icon: CupertinoIcons.cloud,
                    title: const Text('故事来源'),
                    subtitle: Text(config.type.description),
                    trailing:
                        settingsValueText(context, config.type.displayName),
                    showChevron: true,
                    onTap: toggle,
                  ),
                ),
                ..._buildConfigRows(context, config),
              ],
            ),
            SettingsSection(
              title: '使用说明',
              footer: const Text(
                '自建服务器支持服务端搜索和下载统计。COS / OSS、GitHub、Gitee 仅读取公开的 index.json 和故事 JSON，不保存平台密钥。',
              ),
              children: [
                SettingsRow(
                  icon: CupertinoIcons.info,
                  title: const Text('当前配置状态'),
                  subtitle: Text(
                    provider.isConfigured ? '已填写故事来源，可以测试连接' : '尚未填写故事来源地址',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildConfigRows(
    BuildContext context,
    StorySourceConfig config,
  ) {
    if (config.type == StorySourceType.server) {
      return [
        _textRow('服务器地址', _baseUrlController, 'https://example.com'),
        _textRow(
          '端口',
          _portController,
          '8080',
          keyboardType: TextInputType.number,
        ),
        _textRow('设备令牌（可选）', _tokenController, 'Bearer token'),
        _connectionRow(
          title: '测试服务器连接',
          subtitle: '请求 /api/health 检查服务是否可用',
        ),
      ];
    }
    if (config.type == StorySourceType.cos) {
      return [
        _textRow('对象存储公共地址', _baseUrlController, 'https://bucket.example.com'),
        _textRow('索引地址（可选）', _indexController, 'https://.../index.json'),
        _textRow('索引路径', _pathController, 'index.json'),
        _connectionRow(
          title: '保存并测试来源',
          subtitle: '使用公共只读地址，不在 App 内保存 AccessKey',
        ),
      ];
    }
    return [
      _textRow('索引地址（可选）', _indexController, 'https://.../index.json'),
      _textRow('仓库地址', _repositoryController, 'owner/repository'),
      _textRow('分支', _branchController, 'main'),
      _textRow('索引路径', _pathController, 'index.json'),
      _connectionRow(
        title: '保存并测试来源',
        subtitle: '静态来源只读取公开 JSON，不保存平台密钥',
      ),
    ];
  }

  Widget _connectionRow({required String title, required String subtitle}) {
    return SettingsRow(
      icon: CupertinoIcons.link,
      iconColor: context.accentColor,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(CupertinoIcons.arrow_right, size: 18),
      onTap: _testConnection,
    );
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
        onSubmitted: (_) => _saveConfig(),
      ),
    );
  }
}
