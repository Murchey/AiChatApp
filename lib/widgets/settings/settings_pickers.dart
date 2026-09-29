import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_toast.dart';
import 'color_picker_widgets.dart';
import '../../services/update_service.dart'
    show kGiteeRepoUrl, kGitHubRepoUrl, kProxySources;

String themeLabel(AppThemeMode mode) => switch (mode) {
      AppThemeMode.light => '浅色',
      AppThemeMode.dark => '深色',
      AppThemeMode.system => '跟随系统',
    };

String avatarFrameLabel(AvatarFrameStyle style) => switch (style) {
      AvatarFrameStyle.square => '方形',
      AvatarFrameStyle.circle => '圆形',
    };

String proxyDisplayText(String url) {
  if (url.isEmpty) return '不使用';
  if (url == kProxyDefault) return '默认';
  return url;
}

/// 与 SettingsProvider 内默认代理一致时的展示文案
const String kProxyDefault = 'https://gh-proxy.com/';

/// 设置页各类选择器弹窗。
class SettingsPickers {
  SettingsPickers._();

  static void showThemePicker(
      BuildContext context, SettingsProvider settings) {
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
              child: Text(themeLabel(mode)),
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

  static void showAvatarFramePicker(
      BuildContext context, SettingsProvider settings) {
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
              child: Text(avatarFrameLabel(style)),
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

  static void showSingleUpdateRepoDialog({
    required BuildContext context,
    required String title,
    required String currentUrl,
    required String defaultUrl,
    required Future<void> Function(String url) onSave,
    required Future<void> Function() onReset,
  }) {
    final controller = TextEditingController(text: currentUrl);
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: controller,
            placeholder: defaultUrl,
            maxLines: 2,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.pop(ctx);
              onReset();
            },
            child: const Text('恢复默认'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final url = controller.text.trim();
              Navigator.pop(ctx);
              if (url.isNotEmpty) onSave(url);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  static void showGiteeRepoDialog(
      BuildContext context, SettingsProvider settings) {
    showSingleUpdateRepoDialog(
      context: context,
      title: 'Gitee 更新仓库',
      currentUrl: settings.updateGiteeRepoUrl,
      defaultUrl: kGiteeRepoUrl,
      onSave: (u) => settings.setUpdateGiteeRepoUrl(u),
      onReset: () => settings.setUpdateGiteeRepoUrl(kGiteeRepoUrl),
    );
  }

  static void showGitHubRepoDialog(
      BuildContext context, SettingsProvider settings) {
    showSingleUpdateRepoDialog(
      context: context,
      title: 'GitHub 更新仓库',
      currentUrl: settings.updateGitHubRepoUrl,
      defaultUrl: kGitHubRepoUrl,
      onSave: (u) => settings.setUpdateGitHubRepoUrl(u),
      onReset: () => settings.setUpdateGitHubRepoUrl(kGitHubRepoUrl),
    );
  }

  static void showProxyPicker(
      BuildContext context, SettingsProvider settings) {
    final options = <String>[...kProxySources, 'custom'];
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('更新下载代理'),
        actions: [
          for (final opt in options)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                if (opt == 'custom') {
                  showCustomProxyDialog(context, settings);
                } else {
                  settings.setUpdateProxyUrl(opt);
                }
              },
              child: Text(opt == 'custom' ? '自定义…' : opt),
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

  static void showCustomProxyDialog(
      BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController(text: settings.updateProxyUrl);
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('自定义代理'),
        content: CupertinoTextField(
          controller: controller,
          placeholder: 'https://',
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
              Navigator.pop(ctx);
              settings.setUpdateProxyUrl(url);
              showAppToast('代理已更新');
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  static void showColorPicker({
    required BuildContext context,
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onColorChanged,
    required VoidCallback onReset,
  }) {
    var current = initialColor;
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 560,
        decoration: BoxDecoration(
          color: context.listBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onReset();
                    },
                    child: const Text('恢复默认'),
                  ),
                  CupertinoButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onColorChanged(current);
                    },
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: CustomColorPicker(
                  initialColor: initialColor,
                  onChanged: (c) => current = c,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void showBubbleColorDrawer(
      BuildContext context, SettingsProvider settings) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 420,
        decoration: BoxDecoration(
          color: context.listBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '气泡颜色',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final slot in BubbleColorSlot.values)
              BubbleColorRow(
                title: switch (slot) {
                  BubbleColorSlot.selfLight => '我方 · 浅色',
                  BubbleColorSlot.otherLight => '对方 · 浅色',
                  BubbleColorSlot.selfDark => '我方 · 深色',
                  BubbleColorSlot.otherDark => '对方 · 深色',
                },
                color: settings.bubbleColor(slot),
                onTap: () {
                  Navigator.pop(ctx);
                  showColorPicker(
                    context: context,
                    title: '气泡颜色',
                    initialColor: settings.bubbleColor(slot),
                    onColorChanged: (c) => settings.setBubbleColor(slot, c),
                    onReset: () => settings.resetBubbleColor(slot),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
