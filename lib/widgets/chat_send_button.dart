import 'package:flutter/cupertino.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';

/// 聊天发送按钮：宽 64 × 高 40，圆角 10px。
///
/// 经典样式：主题色实底白字；
/// zmd 终末地样式：深色底（#272302）白字 + 金色描边（#D8BF00），
/// 浅色 / 深色模式公用同一套设计。
class ChatSendButton extends StatelessWidget {
  final VoidCallback onPressed;

  const ChatSendButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isZmd = context.uiStyle == UiStyle.zmd;
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
            color: isZmd ? const Color(0xFF272302) : context.accentColor,
            borderRadius: BorderRadius.circular(10),
            border:
                isZmd ? Border.all(color: const Color(0xFFD8BF00)) : null,
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
}
