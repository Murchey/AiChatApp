import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';

/// 聊天气泡样式选择页：顶部实时预览，列表选择样式
class BubbleStyleScreen extends StatelessWidget {
  const BubbleStyleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final current = settingsProvider.bubbleStyle;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('气泡样式'),
        automaticallyImplyLeading: true,
        previousPageTitle: '显示设置',
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // 实时预览区：按当前样式渲染一对气泡
            _PreviewArea(style: current),
            CupertinoListSection.insetGrouped(
              backgroundColor: context.scaffoldColor,
              decoration: BoxDecoration(
                color: context.listBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              header: const Text('选择样式'),
              children: BubbleStyle.values.map((style) {
                final selected = style == current;
                return CupertinoListTile(
                  title: Text(style.displayName),
                  additionalInfo: Text(
                    style == BubbleStyle.sr
                        ? '暖棕 + 柔和阴影，还原崩铁短信'
                        : '矩形圆角 + 细描边，支持自定义颜色',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  trailing: selected
                      ? Icon(
                          CupertinoIcons.check_mark,
                          color: context.accentColor,
                          size: 18,
                        )
                      : const SizedBox(width: 18, height: 18),
                  onTap: () => settingsProvider.setBubbleStyle(style),
                );
              }).toList(),
            ),
            if (current == BubbleStyle.sr)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                child: Text(
                  '崩铁样式使用自带配色，自定义气泡颜色不可用；切回「默认」可恢复',
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

/// 预览区：按所选样式渲染一对示例气泡
class _PreviewArea extends StatelessWidget {
  final BubbleStyle style;

  const _PreviewArea({required this.style});

  BoxDecoration _decoration(BuildContext context, bool isUser) {
    if (style == BubbleStyle.sr) {
      return BoxDecoration(
        color: isUser
            ? SrBubbleColors.selfColor
            : context.isDark
                ? SrBubbleColors.otherColorDark
                : SrBubbleColors.otherColor,
        // 靠近头像一侧（我方右侧/对方左侧）的上边角为直角
        borderRadius: isUser
            ? const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.zero,
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              )
            : const BorderRadius.only(
                topLeft: Radius.zero,
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
        boxShadow: const [
          BoxShadow(
            color: SrBubbleColors.shadowColor,
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      );
    }
    // 经典样式：用当前自定义颜色预览
    return BoxDecoration(
      color: isUser ? context.bubbleSelfColor : context.bubbleOtherColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.separatorColor, width: 0.5),
    );
  }

  Widget _bubble(BuildContext context, bool isUser, String text) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: _decoration(context, isUser),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: style == BubbleStyle.sr
                ? context.bubbleTextColor(isUser)
                : context.textPrimaryColor,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _bubble(context, false, '开拓者，今天也要一起冒险吗？'),
          _bubble(context, true, '当然，现在就出发！'),
        ],
      ),
    );
  }
}
