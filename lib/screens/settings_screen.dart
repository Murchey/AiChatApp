import 'package:flutter/cupertino.dart';

import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/ui_spec.dart';
import '../widgets/settings/color_picker_widgets.dart';
import '../widgets/settings/settings_pickers.dart';
import '../widgets/settings/settings_ui.dart';

import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/auto_moment_provider.dart';
import '../providers/proactive_greeting_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/group_chat_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../providers/memory_point_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/workshop_provider.dart';
import '../services/auto_moment_service.dart';
import '../services/update_service.dart';
import '../services/workshop_service.dart';
import '../utils/app_toast.dart';
import '../widgets/update_dialogs.dart';
import 'backup_screen.dart';
import 'bubble_style_screen.dart';
import 'bubble_font_screen.dart';
import 'memory_pool_manager_screen.dart';
import 'splash_icon_screen.dart';
import 'storage_manage_screen.dart';
import 'sticker_manage_screen.dart';
import 'ui_style_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showCustomPicker = false;

  String _themeLabel(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
      case AppThemeMode.system:
        return '跟随系统';
    }
  }

  String _avatarFrameLabel(AvatarFrameStyle style) => avatarFrameLabel(style);

  String _proxyDisplayText(String url) => proxyDisplayText(url);

  /// 快速测试：立即触发一次自动发朋友圈（开发者模式专用）。
  /// 把所有已开启自动发朋友圈的角色到期时间设为现在，再调用调度器补发布。
  Future<void> _quickTestAutoMoment() async {
    final apiProvider = context.read<ApiProvider>();
    final autoProvider = context.read<AutoMomentProvider>();
    final characterProvider = context.read<CharacterProvider>();
    final chatProvider = context.read<ChatProvider>();
    final chatSettings = context.read<ChatSettingsProvider>();
    final notificationProvider = context.read<MomentNotificationProvider>();
    final memoryPointProvider = context.read<MemoryPointProvider>();
    final groupChatProvider = context.read<GroupChatProvider>();
    final authUser = context.read<AuthProvider>().user;

    if (apiProvider.getModelById(apiProvider.momentModelId) == null) {
      showAppToast('请先在「API 设置」中配置「朋友圈互动」模型');
      return;
    }
    if (characterProvider.isLoading) {
      showAppToast('角色数据加载中，请稍后再试');
      return;
    }
    await autoProvider.expediteAllDue();
    showAppToast('已触发，正在让角色发布朋友圈…');
    await AutoMomentService.instance.checkAndPublish(
      characterProvider: characterProvider,
      apiProvider: apiProvider,
      chatProvider: chatProvider,
      chatSettings: chatSettings,
      groupChatProvider: groupChatProvider,
      notificationProvider: notificationProvider,
      autoMomentProvider: autoProvider,
      memoryPointProvider: memoryPointProvider,
      user: authUser,
    );
    if (mounted) {
      showAppToast('测试完成，请到朋友圈查看');
    }
  }

  /// 快速测试主动问候（开发者模式专用）。
  /// 立即让所有已开启主动问候的角色触发一次问候消息。
  Future<void> _quickTestProactiveGreeting() async {
    final apiProvider = context.read<ApiProvider>();
    final characterProvider = context.read<CharacterProvider>();
    final chatProvider = context.read<ChatProvider>();
    final chatSettings = context.read<ChatSettingsProvider>();
    final greetingProvider = context.read<ProactiveGreetingProvider>();
    final memoryPointProvider = context.read<MemoryPointProvider>();

    if (apiProvider.getModelById(apiProvider.momentModelId) == null &&
        apiProvider.models.isEmpty) {
      showAppToast('请先在「API 设置」中配置至少一个模型');
      return;
    }
    if (characterProvider.isLoading) {
      showAppToast('角色数据加载中，请稍后再试');
      return;
    }

    // 检查是否有角色开启了主动问候
    final hasEnabled = characterProvider.manageableCharacters.any(
      (c) => greetingProvider.configFor(c.id).enabled,
    );
    if (!hasEnabled) {
      showAppToast('没有角色开启「主动问候」，请先在角色聊天设置中开启');
      return;
    }

    showAppToast('已触发，正在生成主动问候消息…');
    await AutoMomentService.instance.checkProactiveGreeting(
      characterProvider: characterProvider,
      apiProvider: apiProvider,
      chatProvider: chatProvider,
      chatSettings: chatSettings,
      greetingProvider: greetingProvider,
      memoryPointProvider: memoryPointProvider,
      force: true,
    );
    if (mounted) {
      showAppToast('测试完成，请到聊天列表查看');
    }
  }

  /// 快速测试角色仓库更新通知（开发者模式专用）
  /// 忽略内容去重，直接显示一次通知弹窗
  Future<void> _quickTestWorkshopNotify() async {
    final workshopProvider = context.read<WorkshopProvider>();

    // 检查是否已配置通知仓库
    if (!workshopProvider.notifyEnabled ||
        workshopProvider.notifyRepoId == null) {
      showAppToast('请先在「创意工坊设置」中开启通知并选择仓库');
      return;
    }

    final notifyRepo = workshopProvider.notifyRepository;
    if (notifyRepo == null) {
      showAppToast('通知仓库未找到，请重新选择');
      return;
    }

    // 读取当前所选仓库的真实最新发布 / COS Note，不构造测试文案。
    showAppToast('正在获取仓库最新更新内容...');
    final String? body;
    final String emptyTip;
    if (notifyRepo.isCos) {
      body = await WorkshopService.fetchCosNote(
        notifyRepo.url,
        auth: notifyRepo.hasCosAuth ? notifyRepo.cosAuth : null,
      );
      emptyTip = '未找到 Note/*.md 或内容为空';
    } else {
      final release = await WorkshopService.fetchLatestRelease(notifyRepo.url);
      body = release?.body;
      emptyTip = '未找到最新正式 Release 或内容为空';
    }

    if (!mounted) return;

    if (body == null || body.isEmpty) {
      showAppToast(emptyTip);
      return;
    }

    // 直接显示通知（忽略去重）
    _showUpdateNotification(body);
  }

  /// 触发 APP 更新弹窗（开发者模式专用）
  /// 模拟一次 APP 更新检测，无论是否有更新都显示弹窗
  Future<void> _triggerAppUpdateDialog() async {
    showAppToast('正在检测更新...');

    final settings = context.read<SettingsProvider>();
    UpdateInfo? info = await UpdateService.checkForUpdate(
      proxyUrl: settings.updateProxyUrl,
      giteeRepoUrl: settings.updateGiteeRepoUrl,
      githubRepoUrl: settings.updateGitHubRepoUrl,
      includeCurrentRelease: true,
    );

    if (!mounted) return;

    if (info == null) {
      showAppToast('当前设置的更新仓库未找到可用 Release');
      return;
    }

    // 显示更新弹窗
    showUpdateAvailableDialog(
      context,
      info,
      proxyUrl: settings.updateProxyUrl,
    );
  }

  void _showUpdateNotification(String body) {
    showMarkdownUpdatePanel(
      context,
      title: '角色仓库有更新',
      body: body,
      footer: '开发者模式快速测试',
    );
  }

  Future<void> _showBubbleFontSizePicker(
      BuildContext context, SettingsProvider settings) async {
    var size = settings.bubbleFontSize;
    final selected = await showCupertinoModalPopup<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SafeArea(
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ctx.scaffoldColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '调整气泡内字体大小',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CupertinoColors.label.resolveFrom(ctx),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final isUser in [false, true])
                    Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: ctx.bubbleBgColor(isUser),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(isUser ? '我方气泡预览 Aa 123' : '对方气泡预览 Aa 123',
                            style: TextStyle(
                                fontSize: size,
                                color: ctx.bubbleTextColor(isUser),
                                fontFamily: ctx.bubbleFontFamily(isUser))),
                      ),
                    ),
                  Text('${size.round()}（默认 16）', textAlign: TextAlign.center),
                  CupertinoSlider(
                    value: size,
                    min: 12,
                    max: 24,
                    divisions: 12,
                    onChanged: (value) => update(() => size = value),
                  ),
                  CupertinoButton(
                    onPressed: () => update(() => size = 16),
                    child: const Text('恢复默认'),
                  ),
                  CupertinoButton.filled(
                    onPressed: () => Navigator.pop(ctx, size),
                    child: const Text('保存'),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selected != null) await settings.setBubbleFontSize(selected);
  }

  /// 弹出深浅色选择（下拉选项框）
  Widget _value(BuildContext context, String value) =>
      settingsValueText(context, value);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(context, '设置'),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + UiSpec.settingsPageTop,
          bottom: UiSpec.floatingContentBottomInset,
        ),
        children: [
          SettingsSection(
            title: '外观',
            children: [
              SettingsRow(
                icon: CupertinoIcons.moon,
                title: const Text('深色模式'),
                trailing: _value(context, _themeLabel(settings.themeMode)),
                showChevron: true,
                onTap: () => SettingsPickers.showThemePicker(context, settings),
              ),
              SettingsRow(
                icon: CupertinoIcons.person_crop_circle,
                title: const Text('角色头像框样式'),
                subtitle: const Text('方形 / 圆形，作用于所有角色头像'),
                trailing: _value(
                    context, _avatarFrameLabel(settings.avatarFrameStyle)),
                showChevron: true,
                onTap: () =>
                    SettingsPickers.showAvatarFramePicker(context, settings),
              ),
            ],
          ),
          SettingsSection(
            title: '表情包',
            children: [
              SettingsRow(
                icon: CupertinoIcons.smiley,
                iconColor: context.settingIconColor(SettingIconRole.stickers),
                title: const Text('管理表情包'),
                subtitle: const Text('查看或编辑已导入的表情包'),
                showChevron: true,
                onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const StickerManageScreen())),
              ),
              SettingsRow(
                icon: CupertinoIcons.hand_thumbsup,
                title: const Text('允许角色发送表情包'),
                subtitle: Text(settings.allowStickerSend
                    ? '角色可按语义发送已保存的表情包'
                    : '已关闭，角色回复时不发送表情包'),
                trailing: CupertinoSwitch(
                  value: settings.allowStickerSend,
                  onChanged: settings.setAllowStickerSend,
                ),
              ),
            ],
          ),
          SettingsSection(
            title: '主题色',
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final color in AppColors.presetColors)
                      PresetColorDot(
                        color: color,
                        selected:
                            color.toARGB32() == settings.accentColor.toARGB32(),
                        onTap: () => settings.setAccentColor(color),
                      ),
                  ],
                ),
              ),
              SettingsRow(
                icon: CupertinoIcons.paintbrush,
                title: const Text('自定义颜色'),
                trailing: Icon(
                  _showCustomPicker
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 17,
                  color: context.textSecondaryColor,
                ),
                onTap: () =>
                    setState(() => _showCustomPicker = !_showCustomPicker),
              ),
              if (_showCustomPicker)
                CustomColorPicker(
                  initialColor: settings.accentColor,
                  onChanged: settings.setAccentColor,
                ),
            ],
          ),
          SettingsSection(
            title: '显示',
            children: [
              SettingsRow(
                icon: CupertinoIcons.chat_bubble_2_fill,
                iconColor: context.settingIconColor(SettingIconRole.display),
                title: const Text('气泡样式'),
                trailing: _value(context, settings.bubbleStyle.displayName),
                showChevron: true,
                onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const BubbleStyleScreen())),
              ),
              SettingsRow(
                icon: CupertinoIcons.textformat,
                title: const Text('UI 样式'),
                subtitle: const Text('会话标题栏与发送按钮'),
                trailing: _value(context, settings.uiStyle.displayName),
                showChevron: true,
                onTap: () => Navigator.push(context,
                    CupertinoPageRoute(builder: (_) => const UiStyleScreen())),
              ),
              SettingsRow(
                icon: CupertinoIcons.photo,
                title: const Text('开屏图标'),
                subtitle: const Text('自定义启动页图片'),
                trailing:
                    _value(context, settings.hasSplashIcon ? '自定义' : '默认'),
                showChevron: true,
                onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const SplashIconScreen())),
              ),
              SettingsRow(
                icon: CupertinoIcons.textformat_alt,
                title: const Text('气泡字体'),
                subtitle: const Text('分别设置我方与对方聊天正文，可导入 TTF 文件'),
                showChevron: true,
                onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const BubbleFontScreen())),
              ),
              SettingsRow(
                icon: CupertinoIcons.textformat_size,
                title: const Text('调整气泡内字体大小'),
                subtitle: Text('${settings.bubbleFontSize.round()}（默认 16）'),
                showChevron: true,
                onTap: () => _showBubbleFontSizePicker(context, settings),
              ),
              if (settings.bubbleStyle == BubbleStyle.classic)
                SettingsRow(
                  icon: CupertinoIcons.paintbrush,
                  title: const Text('自定义气泡颜色'),
                  subtitle: const Text('自己 / 对方，浅色 / 深色模式分别设置'),
                  showChevron: true,
                  onTap: () =>
                      SettingsPickers.showBubbleColorDrawer(context, settings),
                ),
            ],
          ),
          SettingsSection(
            title: '通知',
            children: [
              SettingsRow(
                icon: CupertinoIcons.bell,
                title: const Text('未读消息发送系统通知'),
                subtitle: Text(settings.unreadNotify ? '离开聊天页时推送角色新消息' : '已关闭'),
                trailing: CupertinoSwitch(
                  value: settings.unreadNotify,
                  onChanged: settings.setUnreadNotify,
                ),
              ),
            ],
          ),
          SettingsSection(
            title: '开发者',
            children: [
              SettingsRow(
                icon: CupertinoIcons.wrench,
                title: const Text('开发者模式'),
                subtitle: Text(settings.developerMode
                    ? '已开启，「我」页底部显示软件通知互动日志'
                    : '已关闭，开启后可查看软件通知互动日志'),
                trailing: CupertinoSwitch(
                  value: settings.developerMode,
                  onChanged: settings.setDeveloperMode,
                ),
              ),
              if (settings.developerMode) ...[
                SettingsRow(
                  icon: CupertinoIcons.bolt,
                  title: const Text('快速测试自动发朋友圈'),
                  subtitle: const Text('立即触发已启用角色的自动发帖，仅用于测试'),
                  onTap: _quickTestAutoMoment,
                ),
                SettingsRow(
                  icon: CupertinoIcons.text_bubble,
                  title: const Text('立即触发角色主动问候'),
                  subtitle: const Text('立即触发已启用角色的主动问候，仅用于测试'),
                  onTap: _quickTestProactiveGreeting,
                ),
                SettingsRow(
                  icon: CupertinoIcons.news,
                  title: const Text('快速触发角色仓库提醒'),
                  subtitle: const Text('模拟一次仓库更新通知，用于测试弹窗效果'),
                  onTap: _quickTestWorkshopNotify,
                ),
                SettingsRow(
                  icon: CupertinoIcons.arrow_down_circle,
                  title: const Text('触发 APP 更新弹窗'),
                  subtitle: const Text('立即检测更新并显示更新弹窗'),
                  onTap: _triggerAppUpdateDialog,
                ),
              ],
            ],
          ),
          SettingsSection(
            title: '更新',
            children: [
              SettingsRow(
                icon: CupertinoIcons.arrow_down_circle,
                title: const Text('启动时自动检测更新'),
                subtitle:
                    Text(settings.autoCheckUpdate ? '已启用，启动时自动检测新版本' : '已关闭'),
                trailing: CupertinoSwitch(
                  value: settings.autoCheckUpdate,
                  onChanged: settings.setAutoCheckUpdate,
                ),
              ),
              SettingsRow(
                icon: CupertinoIcons.globe,
                title: const Text('Gitee 更新仓库'),
                subtitle: Text(settings.updateGiteeRepoUrl),
                showChevron: true,
                onTap: () =>
                    SettingsPickers.showGiteeRepoDialog(context, settings),
              ),
              SettingsRow(
                icon: CupertinoIcons.globe,
                title: const Text('GitHub 更新仓库'),
                subtitle: Text(settings.updateGitHubRepoUrl),
                showChevron: true,
                onTap: () =>
                    SettingsPickers.showGitHubRepoDialog(context, settings),
              ),
              SettingsRow(
                icon: CupertinoIcons.link,
                title: const Text('GitHub 加速地址'),
                subtitle: Text(_proxyDisplayText(settings.updateProxyUrl)),
                showChevron: true,
                onTap: () => SettingsPickers.showProxyPicker(context, settings),
              ),
            ],
          ),
          SettingsSection(
            title: 'AI 记忆',
            children: [
              SettingsRow(
                icon: CupertinoIcons.clock,
                title: const Text('记忆池管理'),
                subtitle: const Text('管理角色跨场景记忆来源'),
                showChevron: true,
                onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const MemoryPoolManagerScreen())),
              ),
            ],
          ),
          SettingsSection(
            title: '存储',
            children: [
              SettingsRow(
                icon: CupertinoIcons.arrow_2_circlepath,
                title: const Text('数据备份'),
                subtitle: const Text('导出或恢复全部聊天、角色与设置'),
                showChevron: true,
                onTap: () => Navigator.push(context,
                    CupertinoPageRoute(builder: (_) => const BackupScreen())),
              ),
              SettingsRow(
                icon: CupertinoIcons.folder,
                title: const Text('管理占用空间'),
                subtitle: const Text('查看并清理用户数据与应用缓存'),
                showChevron: true,
                onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const StorageManageScreen())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
