import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';

/// 多选模式底部操作栏
class ChatSelectBar extends StatelessWidget {
  final int count;
  final bool selectingMemory;
  final VoidCallback onCancel;
  final VoidCallback? onSaveMemory;
  final VoidCallback? onForwardSingle;
  final VoidCallback? onForwardMerge;

  const ChatSelectBar({
    super.key,
    required this.count,
    required this.selectingMemory,
    required this.onCancel,
    this.onSaveMemory,
    this.onForwardSingle,
    this.onForwardMerge,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0;
    Widget btn(String label, VoidCallback? onTap) => CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onPressed: onTap,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: enabled && onTap != null
                  ? context.accentColor
                  : context.textSecondaryColor,
            ),
          ),
        );
    return Container(
      color: context.navBarColor,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onPressed: onCancel,
              child: Text(
                '取消',
                style: TextStyle(
                  fontSize: 15,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '已选 $count 条',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.textPrimaryColor,
                ),
              ),
            ),
            if (selectingMemory)
              btn('存储记忆点', enabled ? onSaveMemory : null)
            else ...[
              btn('逐条转发', enabled ? onForwardSingle : null),
              btn('合并转发', enabled ? onForwardMerge : null),
            ],
          ],
        ),
      ),
    );
  }
}
