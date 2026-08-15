import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';
import '../widgets/chat_bubble.dart';

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
                        ? ''
                        : style == BubbleStyle.ww
                            ? ''
                            : '',
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
            if (current == BubbleStyle.sr ||
                current == BubbleStyle.ww ||
                current == BubbleStyle.zmd)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                child: Text(
                  '该样式使用自带配色，自定义气泡颜色不可用；切回「默认」可恢复',
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
      child: switch (style) {
        BubbleStyle.ww => _wwBubble(context, isUser, text),
        BubbleStyle.zmd => _zmdBubble(context, isUser, text),
        _ => Container(
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
      },
    );
  }

  /// ww 鸣潮样式预览：用 CustomClipper 绘制带尾巴形状，与聊天页一致
  Widget _wwBubble(BuildContext context, bool isUser, String text) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        // 圆角按尾巴朝向镜像（我方右下角/对方左下角为大圆角），与裁剪形状一致
        borderRadius: isUser
            ? const BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(5),
                bottomLeft: Radius.circular(15),
                bottomRight: Radius.circular(5),
              )
            : const BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(5),
                bottomLeft: Radius.circular(5),
                bottomRight: Radius.circular(15),
              ),
        boxShadow: [
          BoxShadow(
            color: context.isDark
                ? WwBubbleColors.shadowColorDark
                : WwBubbleColors.shadowColorLight,
            offset: const Offset(0, 1),
            blurRadius: 3,
          ),
        ],
      ),
      child: ClipPath(
        clipper: WwBubbleClipper(isUser: isUser),
        child: Container(
          color: isUser
              ? (context.isDark
                  ? WwBubbleColors.selfColorDark
                  : WwBubbleColors.selfColorLight)
              : (context.isDark
                  ? WwBubbleColors.otherColorDark
                  : WwBubbleColors.otherColorLight),
          padding: EdgeInsets.only(
            left: isUser ? 12 : 12 + WwBubbleClipper.tailLen,
            right: isUser ? 12 + WwBubbleClipper.tailLen : 12,
            top: 10,
            bottom: 10,
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: isUser
                  ? WwBubbleColors.selfTextColor
                  : context.isDark
                      ? WwBubbleColors.otherTextColorDark
                      : WwBubbleColors.otherTextColorLight,
            ),
          ),
        ),
      ),
    );
  }

  /// zmd 终末地样式预览：基于鸣潮尾巴形状（三角均 15px、回程弧 10px），
  /// 我方白底黑字带黑色描边，对方深灰底白字，与聊天页一致
  Widget _zmdBubble(BuildContext context, bool isUser, String text) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        // 圆角按尾巴朝向镜像：我方 tail 朝右，对方 tail 朝左
        borderRadius: isUser
            ? const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.zero,
                bottomLeft: Radius.circular(15),
                bottomRight: Radius.circular(15),
              )
            : const BorderRadius.only(
                topLeft: Radius.zero,
                topRight: Radius.circular(15),
                bottomLeft: Radius.circular(15),
                bottomRight: Radius.circular(15),
              ),
        boxShadow: [
          BoxShadow(
            color: context.isDark
                ? ZmdBubbleColors.shadowColorDark
                : ZmdBubbleColors.shadowColorLight,
            offset: const Offset(0, 1),
            blurRadius: 3,
          ),
        ],
      ),
      child: ClipPath(
        clipper: ZmdBubbleClipper(isUser: isUser),
        child: Container(
          color: isUser
              ? ZmdBubbleColors.selfColor
              : ZmdBubbleColors.otherColor,
          // 我方白色气泡带黑色轮廓描边（浅深一致）
          foregroundDecoration: isUser
              ? BoxDecoration(
                  border: Border.all(
                    color: ZmdBubbleColors.selfBorderColor,
                    width: 1,
                  ),
                )
              : null,
          padding: EdgeInsets.only(
            left: isUser ? 12 : 12 + ZmdBubbleClipper.tailLen,
            right: isUser ? 12 + ZmdBubbleClipper.tailLen : 12,
            top: 10,
            bottom: 10,
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: isUser
                  ? ZmdBubbleColors.selfTextColor
                  : ZmdBubbleColors.otherTextColor,
            ),
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
