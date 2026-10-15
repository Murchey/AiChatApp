import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';
import '../services/app_theme_store.dart';
import '../widgets/settings/settings_ui.dart';
import '../widgets/settings/color_picker_widgets.dart';

/// One place for the effective theme and ordinary bubble colors.
class ThemeAppearanceScreen extends StatelessWidget {
  const ThemeAppearanceScreen({super.key});

  Future<void> _color(BuildContext context, String title, Color initial,
      Future<void> Function(Color) save, Future<void> Function() reset) async {
    Color value = initial;
    await showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) => Container(
              color: context.settingsSurfaceColor,
              child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(title,
                            style: TextStyle(color: context.textPrimaryColor))),
                    CustomColorPicker(
                        initialColor: value, onChanged: (v) => value = v),
                    CupertinoButton(
                        child: const Text('保存'),
                        onPressed: () async {
                          await save(value);
                          if (ctx.mounted) Navigator.pop(ctx);
                        }),
                    CupertinoButton(
                        child: const Text('恢复默认'),
                        onPressed: () async {
                          await reset();
                          if (ctx.mounted) Navigator.pop(ctx);
                        }),
                    CupertinoButton(
                        child: const Text('取消'),
                        onPressed: () => Navigator.pop(ctx)),
                  ]))),
            ));
  }

  Widget _side(BuildContext context, SettingsProvider settings, bool self) {
    final store = AppThemeStore.instance;
    final themed = self && store.bubbleEnabled;
    final classic = settings.bubbleStyle == BubbleStyle.classic;
    final side = self ? '我方' : '对方';
    return SettingsSection(
      title: '$side气泡与文字',
      children: [
        if (themed)
          const SettingsRow(
              icon: CupertinoIcons.photo,
              title: Text('气泡底色'),
              subtitle: Text('由主题图片决定，不支持单独改色')),
        if (!themed && !classic)
          SettingsRow(
              icon: CupertinoIcons.paintbrush,
              title: Text('${settings.bubbleStyle.displayName}自带配色'),
              subtitle: const Text('气泡和文字使用样式配色；切回默认样式后可调整')),
        for (final dark in [false, true]) ...[
          if (!themed && classic)
            Builder(builder: (context) {
              final slot = self
                  ? (dark
                      ? BubbleColorSlot.selfDark
                      : BubbleColorSlot.selfLight)
                  : (dark
                      ? BubbleColorSlot.otherDark
                      : BubbleColorSlot.otherLight);
              final title = '${dark ? '深色' : '浅色'}模式气泡颜色';
              return SettingsRow(
                  key: ValueKey('bubble-color-${slot.name}'),
                  title: Text(title),
                  trailing: Icon(CupertinoIcons.circle_fill,
                      color: settings.bubbleColor(slot)),
                  showChevron: true,
                  onTap: () => _color(
                      context,
                      '$side · $title',
                      settings.bubbleColor(slot),
                      (color) => settings.setBubbleColor(slot, color),
                      () => settings.resetBubbleColor(slot)));
            }),
          if (themed || classic)
            Builder(builder: (context) {
              final slot = self
                  ? (dark ? BubbleTextSlot.selfDark : BubbleTextSlot.selfLight)
                  : (dark
                      ? BubbleTextSlot.otherDark
                      : BubbleTextSlot.otherLight);
              final title = '${dark ? '深色' : '浅色'}模式文字颜色';
              final color = themed
                  ? store.textColor(dark) ??
                      (classic
                          ? settings.bubbleTextColor(slot)
                          : context.bubbleTextColor(true))
                  : settings.bubbleTextColor(slot);
              return SettingsRow(
                  key: ValueKey('bubble-text-${slot.name}'),
                  title: Text(title),
                  subtitle: themed ? const Text('仅应用于当前主题') : null,
                  trailing: Icon(CupertinoIcons.circle_fill, color: color),
                  showChevron: true,
                  onTap: () => _color(
                      context,
                      '$side · $title',
                      color,
                      (color) => settings.setBubbleTextColor(slot, color),
                      () => settings.resetBubbleTextColor(slot)));
            }),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return AnimatedBuilder(
        animation: AppThemeStore.instance,
        builder: (context, _) {
          final store = AppThemeStore.instance;
          return DefaultTextStyle.merge(
              style: TextStyle(color: context.textPrimaryColor),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: context.isDark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark,
                  child: CupertinoPageScaffold(
                      backgroundColor: context.scaffoldColor,
                      navigationBar: settingsNavigationBar(context, '气泡与文字颜色'),
                      child: ListView(
                          padding: settingsPageContentPadding(context),
                          children: [
                            if (store.active != null)
                              SettingsSection(
                                  title: '当前主题 · ${store.active!.name}',
                                  children: [
                                    if (store.active?.bubble != null)
                                      SettingsRow(
                                          title: const Text('使用主题我方气泡'),
                                          subtitle:
                                              const Text('关闭后可使用原气泡样式和颜色'),
                                          trailing: CupertinoSwitch(
                                              value: store.bubbleEnabled,
                                              onChanged: (v) =>
                                                  store.adjust('bubble', v))),
                                  ]),
                            _side(context, settings, true),
                            _side(context, settings, false),
                            if (store.active != null)
                              Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                      '主题我方文字颜色独立保存，禁用主题后恢复原设置。对方设置不受主题影响。',
                                      style: TextStyle(
                                          color: context.textSecondaryColor))),
                          ]))));
        });
  }
}
