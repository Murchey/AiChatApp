import 'package:flutter/cupertino.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';

/// 聊天发送按钮。
///
/// 经典样式：36×36 圆形主题色实底 + 上箭头（更轻，给输入框让出宽度）；
/// zmd 终末地样式：保持 64×40 深色底（#272302）白字 + 金色描边（#D8BF00），
/// 浅色 / 深色模式公用同一套设计。
class ChatSendButton extends StatelessWidget {
  final VoidCallback onPressed;

  const ChatSendButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isZmd = context.uiStyle == UiStyle.zmd;
    if (isZmd) {
      return SizedBox(
        width: 64,
        height: 40,
        child: CupertinoButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF272302),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD8BF00)),
            ),
            child: const Text(
              '发送',
              style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 36,
      height: 36,
      child: CupertinoButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.accentColor,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            CupertinoIcons.arrow_up,
            size: 20,
            color: CupertinoColors.white,
          ),
        ),
      ),
    );
  }
}
