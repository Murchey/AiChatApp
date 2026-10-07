import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/navigation_icons.dart';
import '../config/ui_spec.dart';
import '../providers/settings_provider.dart';
import '../widgets/chat_send_button.dart';
import '../widgets/chat_title_bar.dart';
import '../widgets/settings/settings_ui.dart';

/// 会话 UI 样式选择页：顶部实时预览（会话上方的状态条 + 下方的输入框），
/// 列表选择样式。
class UiStyleScreen extends StatelessWidget {
  const UiStyleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final current = settingsProvider.uiStyle;
    final navigationStyle = settingsProvider.homeNavigationStyle;
    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(context, 'UI 样式'),
      backgroundColor: context.scaffoldColor,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // 实时预览区：会话上方状态条 + 下方输入栏，随所选样式渲染
            _PreviewArea(style: current),
            _NavigationPreview(style: navigationStyle),
            SettingsSection(
              title: '选择样式',
              children: [
                SettingsInlinePicker<UiStyle>(
                  value: current,
                  options: [
                    for (final style in UiStyle.values)
                      SettingsChoiceOption(
                        value: style,
                        label: style.displayName,
                      ),
                  ],
                  onChanged: settingsProvider.setUiStyle,
                  panelKey: 'ui-style-chat-picker',
                  rowBuilder: (context, toggle) => SettingsRow(
                    icon: CupertinoIcons.paintbrush,
                    title: Text(current.displayName),
                    trailing: settingsValueText(context, current.displayName),
                    showChevron: true,
                    onTap: toggle,
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: '底部导航栏',
              children: [
                SettingsInlinePicker<HomeNavigationStyle>(
                  value: navigationStyle,
                  options: [
                    for (final style in HomeNavigationStyle.values)
                      SettingsChoiceOption(
                        value: style,
                        label: style.displayName,
                        subtitle: style.description,
                      ),
                  ],
                  onChanged: settingsProvider.setHomeNavigationStyle,
                  panelKey: 'ui-style-navigation-picker',
                  rowBuilder: (context, toggle) => SettingsRow(
                    icon: CupertinoIcons.square_stack,
                    title: Text(navigationStyle.displayName),
                    subtitle: Text(navigationStyle.description),
                    trailing:
                        settingsValueText(context, navigationStyle.displayName),
                    showChevron: true,
                    onTap: toggle,
                  ),
                ),
              ],
            ),
            if (current == UiStyle.zmd)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                child: Text(
                  '终末地样式会调整会话顶部的标题栏（姓名、个性签名与在线状态点）'
                  '以及输入栏的发送按钮，浅色 / 深色模式通用',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 预览区：会话上方的状态条 + 下方的输入框
class _PreviewArea extends StatelessWidget {
  final UiStyle style;

  const _PreviewArea({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // 会话上方的状态条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.navBarColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: style == UiStyle.zmd
                ? const ChatTitleBar(
                    name: '艾维莉亚',
                    signature: '来自终末地的员工，喜欢在星海间漂泊与聆听故事。',
                    activeStart: '08:00',
                    activeEnd: '22:00',
                  )
                : const ChatTitleBar(name: '艾维莉亚'),
          ),
          const SizedBox(height: 12),
          // 会话下方的输入栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: context.navBarColor,
              borderRadius: BorderRadius.circular(10),
              border: Border(
                top: BorderSide(color: context.separatorColor),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.add_circled,
                  color: context.textSecondaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: context.fieldBgColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '输入消息...',
                      style: TextStyle(
                        fontSize: 16,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ChatSendButton(onPressed: () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationPreview extends StatelessWidget {
  final HomeNavigationStyle style;

  const _NavigationPreview({required this.style});

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.navBarColor.withValues(
          alpha: style == HomeNavigationStyle.floating ? 0.72 : 1,
        ),
        borderRadius: BorderRadius.circular(
          style == HomeNavigationStyle.floating ? 30 : 14,
        ),
        border: Border.all(color: context.settingsOutlineColor, width: 0.6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < AppNavigationIcons.tabs.length; i++)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  AppNavigationIcons.tabs[i].activeIcon,
                  size: 18,
                  color:
                      i == 0 ? context.accentColor : context.textSecondaryColor,
                ),
                Text(
                  AppNavigationIcons.tabs[i].label,
                  style: TextStyle(
                    fontSize: 9,
                    color: i == 0
                        ? context.accentColor
                        : context.textSecondaryColor,
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    return Container(
      height: 94,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.settingsSurfaceColor,
        borderRadius: BorderRadius.circular(UiSpec.settingsSectionRadius),
        border: Border.all(
          color: context.settingsOutlineColor.withValues(alpha: 0.7),
          width: 0.6,
        ),
      ),
      child: Align(alignment: Alignment.bottomCenter, child: panel),
    );
  }
}
