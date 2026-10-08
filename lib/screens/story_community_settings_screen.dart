import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../config/ui_spec.dart';
import '../models/story_package.dart';
import '../providers/story_provider.dart';
import '../providers/backend_provider.dart';
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
  final _deviceIdController = TextEditingController();
  final _inviteController = TextEditingController();
  final _indexController = TextEditingController();
  final _repositoryController = TextEditingController();
  final _branchController = TextEditingController();
  final _pathController = TextEditingController();
  bool _ready = false;
  bool _busy = false;
  StoryProvider? _provider;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) showAppToast(_provider!.readableError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<StoryProvider>();
      _provider = provider;
      final backend = provider.backend;
      await provider.init();
      if (!mounted) return;
      _loadControllers(provider.config);
      if (backend.config.deviceId.isNotEmpty) {
        _deviceIdController.text = backend.config.deviceId;
      }
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
    _provider?.cancelRequests();
    for (final controller in [
      _baseUrlController,
      _portController,
      _tokenController,
      _deviceIdController,
      _inviteController,
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
    final backend = provider.backend;
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
    if (current.type == StorySourceType.server) {
      await backend.configureEndpoint(
        baseUrl: _baseUrlController.text.trim(),
        port: _portController.text.trim(),
        deviceId: _deviceIdController.text.trim(),
        manualAccessToken: _tokenController.text.trim(),
      );
    }
  }

  Future<void> _bindServer() async {
    final backend = context.read<StoryProvider>().backend;
    try {
      await _saveConfig();
      if (!mounted) return;
      await backend.bindInvite(_inviteController.text.trim());
      if (mounted) {
        _tokenController.clear();
        _inviteController.clear();
        showAppToast('设备绑定成功');
      }
    } catch (error) {
      if (mounted) showAppToast(backend.errorMessage(error));
    }
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
      navigationBar: settingsNavigationBar(context, '故事线设置',
          trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: !_ready || _busy
                  ? null
                  : () => _run(() async {
                        await _saveConfig();
                        if (mounted) showAppToast('已保存故事来源');
                      }),
              child: const Text('保存'))),
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
                    await _run(() async {
                      await _saveConfig();
                      await provider.switchSource(type);
                      if (mounted) _loadControllers(provider.config);
                    });
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
                if (config.type == StorySourceType.server)
                  ListenableBuilder(
                      listenable: provider.backend,
                      builder: (context, _) {
                        final backend = provider.backend;
                        final status = switch (backend.status) {
                          BackendConnectionStatus.unconfigured => '尚未配置',
                          BackendConnectionStatus.idle => '等待连接',
                          BackendConnectionStatus.checking => '正在检查连接',
                          BackendConnectionStatus.connected =>
                            backend.isAuthenticated
                                ? '已连接 · 设备已绑定'
                                : '已连接 · 公共浏览',
                          BackendConnectionStatus.unauthorized => '登录已失效，请重新绑定',
                          BackendConnectionStatus.error => '连接失败',
                        };
                        return SettingsRow(
                            icon: CupertinoIcons.link,
                            title: Text(status),
                            subtitle: Text([
                              if (backend.error != null) backend.error!,
                              if (backend.capabilities != null)
                                'API ${backend.capabilities!.apiVersion} · ${backend.capabilities!.serverVersion}',
                              if (backend.storageNotice != null)
                                backend.storageNotice!
                            ].join('\n')));
                      }),
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
        _textRow('设备令牌（可选）', _tokenController, '仅在更换手动令牌时填写', secret: true),
        _textRow('设备 ID', _deviceIdController, '自动生成，可跨设备撤销'),
        _textRow('邀请码（首次绑定）', _inviteController, 'AIC-...', secret: true),
        SettingsRow(
          icon: CupertinoIcons.person_add,
          iconColor: context.accentColor,
          title: const Text('绑定设备并刷新令牌'),
          subtitle: const Text('使用邀请码获取短期访问令牌，过期后自动轮换'),
          trailing: const Icon(CupertinoIcons.arrow_right, size: 18),
          onTap: _busy ? null : () => _run(_bindServer),
        ),
        _connectionRow(
          title: '测试服务器连接',
          subtitle: '请求 /api/health 检查服务是否可用',
        ),
        SettingsRow(
            icon: CupertinoIcons.lock,
            title: const Text('清除本机登录'),
            subtitle: const Text('删除安全存储中的访问和刷新令牌'),
            onTap: _busy
                ? null
                : () => _run(() async {
                      await context
                          .read<StoryProvider>()
                          .backend
                          .clearSession();
                      if (mounted) showAppToast('已清除本机登录');
                    })),
        SettingsRow(
            icon: CupertinoIcons.person_crop_circle,
            title: const Text('撤销当前设备'),
            subtitle: const Text('服务器撤销后，该设备的令牌立即失效'),
            onTap: _busy
                ? null
                : () => _run(() async {
                      await context
                          .read<StoryProvider>()
                          .backend
                          .revokeDevice();
                      if (mounted) showAppToast('已撤销当前设备');
                    })),
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
      onTap: _busy ? null : () => _run(_testConnection),
    );
  }

  Widget _textRow(
    String title,
    TextEditingController controller,
    String placeholder, {
    TextInputType? keyboardType,
    bool secret = false,
  }) {
    return SettingsRow(
      icon: CupertinoIcons.pencil,
      title: Text(title),
      subtitle: CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        keyboardType: keyboardType,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: !secret,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: context.fieldBgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        onSubmitted: (_) => _run(_saveConfig),
      ),
    );
  }
}
