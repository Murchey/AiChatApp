import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/api_provider.dart';
import '../providers/auto_moment_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../providers/memory_point_provider.dart';
import '../providers/settings_provider.dart';
import '../services/auto_moment_service.dart';
import '../services/update_service.dart';
import '../utils/app_toast.dart';
import 'storage_manage_screen.dart';

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
      notificationProvider: notificationProvider,
      autoMomentProvider: autoProvider,
      memoryPointProvider: memoryPointProvider,
    );
    if (mounted) {
      showAppToast('测试完成，请到朋友圈查看');
    }
  }

  /// 弹出深浅色选择（下拉选项框）
  void _showThemePicker(BuildContext context, SettingsProvider settings) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('选择外观模式'),
        actions: [
          for (final mode in AppThemeMode.values)
            CupertinoActionSheetAction(
              isDefaultAction: settings.themeMode == mode,
              onPressed: () {
                settings.setThemeMode(mode);
                Navigator.pop(ctx);
              },
              child: Text(_themeLabel(mode)),
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

  String _avatarFrameLabel(AvatarFrameStyle style) {
    switch (style) {
      case AvatarFrameStyle.square:
        return '方形';
      case AvatarFrameStyle.circle:
        return '圆形';
    }
  }

  /// 弹出角色头像框样式选择（下拉选项框）
  void _showAvatarFramePicker(BuildContext context, SettingsProvider settings) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('选择角色头像框样式'),
        message: const Text('全局生效：聊天、通讯录、朋友圈等所有角色头像'),
        actions: [
          for (final style in AvatarFrameStyle.values)
            CupertinoActionSheetAction(
              isDefaultAction: settings.avatarFrameStyle == style,
              onPressed: () {
                settings.setAvatarFrameStyle(style);
                Navigator.pop(ctx);
              },
              child: Text(_avatarFrameLabel(style)),
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

  /// 代理源展示文案：内置源显示「代理 N」，自定义显示「自定义」
  String _proxyDisplayText(String url) {
    final idx = kProxySources.indexOf(url);
    if (idx >= 0) return '代理 ${idx + 1}: $url';
    return '自定义: $url';
  }

  /// 弹出更新代理源选择（底部弹层）：内置源 + 自定义
  void _showProxyPicker(BuildContext context, SettingsProvider settings) {
    final isCustom = !kProxySources.contains(settings.updateProxyUrl);
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('选择代理源'),
        message: const Text('用于加速 GitHub 更新下载'),
        actions: [
          for (var i = 0; i < kProxySources.length; i++)
            CupertinoActionSheetAction(
              isDefaultAction: settings.updateProxyUrl == kProxySources[i],
              onPressed: () {
                settings.setUpdateProxyUrl(kProxySources[i]);
                Navigator.pop(ctx);
              },
              child: Text('代理 ${i + 1}'),
            ),
          CupertinoActionSheetAction(
            isDefaultAction: isCustom,
            onPressed: () {
              Navigator.pop(ctx);
              _showCustomProxyDialog(context, settings);
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
  void _showCustomProxyDialog(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController(
      text: kProxySources.contains(settings.updateProxyUrl)
          ? ''
          : settings.updateProxyUrl,
    );
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
              if (url.isNotEmpty) settings.setUpdateProxyUrl(url);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('设置')),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          // 明暗模式
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('外观'),
            children: [
              CupertinoListTile(
                title: const Text('深色模式'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _themeLabel(settings.themeMode),
                      style: TextStyle(
                        fontSize: 14,
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
                onTap: () => _showThemePicker(context, settings),
              ),
              CupertinoListTile(
                title: const Text('角色头像框样式'),
                subtitle: Text(
                  '方形 / 圆形，作用于所有角色头像',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _avatarFrameLabel(settings.avatarFrameStyle),
                      style: TextStyle(
                        fontSize: 14,
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
                onTap: () => _showAvatarFramePicker(context, settings),
              ),
            ],
          ),
          // 主题色
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('主题色'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final color in AppColors.presetColors)
                      _PresetColorDot(
                        color: color,
                        selected: color.toARGB32() ==
                            settings.accentColor.toARGB32(),
                        onTap: () => settings.setAccentColor(color),
                      ),
                  ],
                ),
              ),
              CupertinoListTile(
                title: const Text('自定义颜色'),
                trailing: Icon(
                  _showCustomPicker
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
                onTap: () {
                  setState(() {
                    _showCustomPicker = !_showCustomPicker;
                  });
                },
              ),
              if (_showCustomPicker)
                _CustomColorPicker(
                  initialColor: settings.accentColor,
                  onChanged: (color) => settings.setAccentColor(color),
                ),
            ],
          ),
          // 显示设置：聊天气泡颜色与气泡内字体颜色（自己/对方 × 浅色/深色）
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('显示设置'),
            children: [
              _BubbleColorRow(
                title: '自己气泡（浅色）',
                color: settings.bubbleColor(BubbleColorSlot.selfLight),
                onTap: () => _showColorPicker(
                  context: context,
                  title: '自己气泡颜色（浅色模式）',
                  initialColor: settings.bubbleColor(BubbleColorSlot.selfLight),
                  onColorChanged: (c) =>
                      settings.setBubbleColor(BubbleColorSlot.selfLight, c),
                  onReset: () =>
                      settings.resetBubbleColor(BubbleColorSlot.selfLight),
                ),
              ),
              _BubbleColorRow(
                title: '对方气泡（浅色）',
                color: settings.bubbleColor(BubbleColorSlot.otherLight),
                onTap: () => _showColorPicker(
                  context: context,
                  title: '对方气泡颜色（浅色模式）',
                  initialColor:
                      settings.bubbleColor(BubbleColorSlot.otherLight),
                  onColorChanged: (c) =>
                      settings.setBubbleColor(BubbleColorSlot.otherLight, c),
                  onReset: () =>
                      settings.resetBubbleColor(BubbleColorSlot.otherLight),
                ),
              ),
              _BubbleColorRow(
                title: '自己气泡（深色）',
                color: settings.bubbleColor(BubbleColorSlot.selfDark),
                onTap: () => _showColorPicker(
                  context: context,
                  title: '自己气泡颜色（深色模式）',
                  initialColor: settings.bubbleColor(BubbleColorSlot.selfDark),
                  onColorChanged: (c) =>
                      settings.setBubbleColor(BubbleColorSlot.selfDark, c),
                  onReset: () =>
                      settings.resetBubbleColor(BubbleColorSlot.selfDark),
                ),
              ),
              _BubbleColorRow(
                title: '对方气泡（深色）',
                color: settings.bubbleColor(BubbleColorSlot.otherDark),
                onTap: () => _showColorPicker(
                  context: context,
                  title: '对方气泡颜色（深色模式）',
                  initialColor: settings.bubbleColor(BubbleColorSlot.otherDark),
                  onColorChanged: (c) =>
                      settings.setBubbleColor(BubbleColorSlot.otherDark, c),
                  onReset: () =>
                      settings.resetBubbleColor(BubbleColorSlot.otherDark),
                ),
              ),
              _BubbleColorRow(
                title: '自己气泡字体（浅色）',
                color: settings.bubbleTextColor(BubbleTextSlot.selfLight),
                onTap: () => _showColorPicker(
                  context: context,
                  title: '自己气泡字体颜色（浅色模式）',
                  initialColor:
                      settings.bubbleTextColor(BubbleTextSlot.selfLight),
                  onColorChanged: (c) =>
                      settings.setBubbleTextColor(BubbleTextSlot.selfLight, c),
                  onReset: () =>
                      settings.resetBubbleTextColor(BubbleTextSlot.selfLight),
                ),
              ),
              _BubbleColorRow(
                title: '对方气泡字体（浅色）',
                color: settings.bubbleTextColor(BubbleTextSlot.otherLight),
                onTap: () => _showColorPicker(
                  context: context,
                  title: '对方气泡字体颜色（浅色模式）',
                  initialColor:
                      settings.bubbleTextColor(BubbleTextSlot.otherLight),
                  onColorChanged: (c) =>
                      settings.setBubbleTextColor(BubbleTextSlot.otherLight, c),
                  onReset: () =>
                      settings.resetBubbleTextColor(BubbleTextSlot.otherLight),
                ),
              ),
              _BubbleColorRow(
                title: '自己气泡字体（深色）',
                color: settings.bubbleTextColor(BubbleTextSlot.selfDark),
                onTap: () => _showColorPicker(
                  context: context,
                  title: '自己气泡字体颜色（深色模式）',
                  initialColor:
                      settings.bubbleTextColor(BubbleTextSlot.selfDark),
                  onColorChanged: (c) =>
                      settings.setBubbleTextColor(BubbleTextSlot.selfDark, c),
                  onReset: () =>
                      settings.resetBubbleTextColor(BubbleTextSlot.selfDark),
                ),
              ),
              _BubbleColorRow(
                title: '对方气泡字体（深色）',
                color: settings.bubbleTextColor(BubbleTextSlot.otherDark),
                onTap: () => _showColorPicker(
                  context: context,
                  title: '对方气泡字体颜色（深色模式）',
                  initialColor:
                      settings.bubbleTextColor(BubbleTextSlot.otherDark),
                  onColorChanged: (c) =>
                      settings.setBubbleTextColor(BubbleTextSlot.otherDark, c),
                  onReset: () =>
                      settings.resetBubbleTextColor(BubbleTextSlot.otherDark),
                ),
              ),
            ],
          ),
          // 消息通知：角色新消息（未读）发送系统通知
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('消息通知'),
            children: [
              CupertinoListTile(
                title: const Text('未读消息发送系统通知'),
                subtitle: Text(
                  settings.unreadNotify
                      ? '已开启，离开聊天界面时角色新消息将通过系统通知提醒'
                      : '已关闭',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: CupertinoSwitch(
                  value: settings.unreadNotify,
                  onChanged: (v) => settings.setUnreadNotify(v),
                ),
              ),
            ],
          ),
          // 开发者模式：开启后在「我」页底部显示通知与日志文本框
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('开发者'),
            children: [
              CupertinoListTile(
                title: const Text('开发者模式'),
                subtitle: Text(
                  settings.developerMode
                      ? '已开启，「我」页底部显示软件通知与朋友圈 AI 互动日志'
                      : '已关闭',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: CupertinoSwitch(
                  value: settings.developerMode,
                  onChanged: (v) => settings.setDeveloperMode(v),
                ),
              ),
              if (settings.developerMode) ...[
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 16),
                  color: context.separatorColor,
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.bolt,
                    color: CupertinoColors.systemOrange,
                  ),
                  title: const Text('快速测试自动发朋友圈'),
                  subtitle: Text(
                    '立即让所有已开启「自动发朋友圈」的角色到期并触发一次发布，'
                    '用于快速验证效果（正常使用无需点击）',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  onTap: () => _quickTestAutoMoment(),
                ),
              ],
            ],
          ),
          // 更新检测：启动时自动检测 + 更新代理地址
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('更新检测'),
            children: [
              CupertinoListTile(
                title: const Text('启动时自动检测更新'),
                subtitle: Text(
                  settings.autoCheckUpdate
                      ? '已启用，启动时自动检测新版本'
                      : '已关闭',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: CupertinoSwitch(
                  value: settings.autoCheckUpdate,
                  onChanged: (v) => settings.setAutoCheckUpdate(v),
                ),
              ),
              CupertinoListTile(
                title: const Text('GitHub 加速地址'),
                subtitle: Text(
                  _proxyDisplayText(settings.updateProxyUrl),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
                onTap: () => _showProxyPicker(context, settings),
              ),
            ],
          ),
          // 存储空间：管理应用自身占用（用户数据 + 软件缓存）
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('存储空间'),
            children: [
              CupertinoListTile(
                title: const Text('管理占用空间'),
                subtitle: Text(
                  '扫描并清理聊天记录、角色数据、下载缓存等',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const StorageManageScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 弹出颜色选择器（底部弹层）：网格 + HEX + HSV 滑块，可实时预览
  void _showColorPicker({
    required BuildContext context,
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onColorChanged,
    required VoidCallback onReset,
  }) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 560,
        decoration: BoxDecoration(
          color: context.listBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimaryColor,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed: () {
                        onReset();
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        '恢复默认',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 0.5,
                color: context.separatorColor,
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: _CustomColorPicker(
                    initialColor: initialColor,
                    onChanged: onColorChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 气泡颜色设置行：标题 + 颜色圆点预览 + 右箭头
class _BubbleColorRow extends StatelessWidget {
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _BubbleColorRow({
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: context.textPrimaryColor,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: context.separatorColor,
                width: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: context.textSecondaryColor,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _PresetColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PresetColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: selected
              ? Border.all(
                  color: context.textSecondaryColor,
                  width: 3,
                )
              : null,
        ),
        child: selected
            ? const Icon(
                CupertinoIcons.check_mark,
                size: 20,
                color: CupertinoColors.white,
              )
            : null,
      ),
    );
  }
}

/// 自定义调色盘：颜色网格 + HEX 输入 + HSV 滑块
class _CustomColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onChanged;

  const _CustomColorPicker({
    required this.initialColor,
    required this.onChanged,
  });

  @override
  State<_CustomColorPicker> createState() => _CustomColorPickerState();
}

class _CustomColorPickerState extends State<_CustomColorPicker> {
  late HSVColor _hsv;
  late TextEditingController _hexController;

  // 预设颜色网格（色相 × 亮度）
  static const _colorGrid = [
    [Color(0xFFF44336), Color(0xFFE91E63), Color(0xFF9C27B0), Color(0xFF673AB7)],
    [Color(0xFF3F51B5), Color(0xFF2196F3), Color(0xFF03A9F4), Color(0xFF00BCD4)],
    [Color(0xFF009688), Color(0xFF4CAF50), Color(0xFF8BC34A), Color(0xFFCDDC39)],
    [Color(0xFFFFEB3B), Color(0xFFFFC107), Color(0xFFFF9800), Color(0xFFFF5722)],
    [Color(0xFF795548), Color(0xFF9E9E9E), Color(0xFF607D8B), Color(0xFF000000)],
    [Color(0xFFFFFFFF), Color(0xFFF5F5F5), Color(0xFFE0E0E0), Color(0xFFBDBDBD)],
  ];

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _colorToHex(widget.initialColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase().padLeft(6, '0')}';
  }

  Color? _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      try {
        return Color(int.parse('FF$hex', radix: 16));
      } catch (_) {
        return null;
      }
    } else if (hex.length == 8) {
      try {
        return Color(int.parse(hex, radix: 16));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  void _update({double? hue, double? saturation, double? value}) {
    setState(() {
      _hsv = HSVColor.fromAHSV(
        1,
        hue ?? _hsv.hue,
        saturation ?? _hsv.saturation,
        value ?? _hsv.value,
      );
    });
    final newColor = _hsv.toColor();
    _hexController.text = _colorToHex(newColor);
    widget.onChanged(newColor);
  }

  void _updateFromColor(Color color) {
    setState(() {
      _hsv = HSVColor.fromColor(color);
    });
    _hexController.text = _colorToHex(color);
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    final current = _hsv.toColor();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 颜色网格快速选择
          _buildColorGrid(),
          const SizedBox(height: 12),
          // 预览 + HEX 输入
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: current,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.separatorColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CupertinoTextField(
                  controller: _hexController,
                  placeholder: '#000000',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.textPrimaryColor,
                  ),
                  decoration: BoxDecoration(
                    color: context.fieldBgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onSubmitted: (value) {
                    final color = _hexToColor(value);
                    if (color != null) {
                      _updateFromColor(color);
                    } else {
                      _hexController.text = _colorToHex(current);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // HSV 滑块
          _buildSlider(
            label: '色相',
            value: _hsv.hue / 360,
            activeColor: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
            onChanged: (v) => _update(hue: v * 360),
          ),
          _buildSlider(
            label: '饱和度',
            value: _hsv.saturation,
            activeColor: HSVColor.fromAHSV(1, _hsv.hue, 1, _hsv.value).toColor(),
            onChanged: (v) => _update(saturation: v),
          ),
          _buildSlider(
            label: '亮度',
            value: _hsv.value,
            activeColor: HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor(),
            onChanged: (v) => _update(value: v),
          ),
        ],
      ),
    );
  }

  Widget _buildColorGrid() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.separatorColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: _colorGrid.map((row) {
          return Row(
            children: row.map((color) {
              final isSelected = color.toARGB32() == _hsv.toColor().toARGB32();
              return Expanded(
                child: GestureDetector(
                  onTap: () => _updateFromColor(color),
                  child: Container(
                    height: 36,
                    color: color,
                    child: isSelected
                        ? const Icon(
                            CupertinoIcons.check_mark,
                            size: 16,
                            color: CupertinoColors.white,
                          )
                        : null,
                  ),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondaryColor,
            ),
          ),
        ),
        Expanded(
          child: CupertinoSlider(
            value: value.clamp(0.0, 1.0),
            activeColor: activeColor,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
