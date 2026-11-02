import 'package:flutter/cupertino.dart';
// SelectableText 仅由 material 库导出；长按选择/复制错误文本使用。
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';

import '../../config/theme.dart';
import '../../utils/app_toast.dart';

/// 会话页面的 AI 请求失败提示条：
/// 两行摘要 + 点击弹出完整报错弹窗，长按直接复制错误信息。
class ChatErrorBanner extends StatelessWidget {
  final String error;
  final VoidCallback onDismiss;

  /// 可选配色（桌面端跟随 DesktopPalette）；缺省用主题导航栏底色 + 系统红。
  final Color? background;
  final Color? foreground;

  const ChatErrorBanner({
    super.key,
    required this.error,
    required this.onDismiss,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final danger = foreground ?? CupertinoColors.systemRed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showChatErrorDialog(context, error),
      onLongPress: () => copyChatError(error),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: background ?? context.navBarColor,
        child: Row(
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              size: 15,
              color: danger,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: danger,
                ),
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 16,
                color: context.textSecondaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 复制完整错误信息并以 Toast 提示。
Future<void> copyChatError(String error) async {
  await Clipboard.setData(ClipboardData(text: error));
  showAppToast('已复制错误信息');
}

/// 完整报错弹窗：可滚动全文 + 长按选择复制，底部提供「复制」按钮。
Future<void> showChatErrorDialog(BuildContext context, String error) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: const Text('请求失败'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: SelectableText(
            error,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () async {
            await copyChatError(error);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('复制'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
