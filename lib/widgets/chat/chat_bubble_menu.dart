import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';

/// 长按气泡菜单网格面板（与手机聊天页常量一致）。
class ChatBubbleMenuPanel extends StatelessWidget {
  final List<Widget> items;

  static const double cellWidth = 74;
  static const double cellHeight = 46;
  static const double spacing = 4;
  static const double padding = 8;
  static const double border = 0.5;
  static const int maxColumns = 3;

  const ChatBubbleMenuPanel({super.key, required this.items});

  static int rowCount(int itemCount) =>
      (itemCount + maxColumns - 1) ~/ maxColumns;

  static int columns(int itemCount) {
    final rows = rowCount(itemCount);
    return (itemCount + rows - 1) ~/ rows;
  }

  static double panelWidth(int itemCount) {
    final cols = columns(itemCount);
    return cols * cellWidth + (cols - 1) * spacing + (padding + border) * 2;
  }

  static double panelHeight(int itemCount) {
    final rows = rowCount(itemCount);
    return rows * cellHeight + (rows - 1) * spacing + (padding + border) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final rowN = rowCount(items.length);
    final base = items.length ~/ rowN;
    final extra = items.length % rowN;
    final rows = <Widget>[];
    var index = 0;
    for (var r = 0; r < rowN; r++) {
      final count = base + (r < extra ? 1 : 0);
      final rowItems = items.sublist(index, index + count);
      index += count;
      rows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < rowItems.length; i++) ...[
              if (i > 0) const SizedBox(width: spacing),
              rowItems[i],
            ],
          ],
        ),
      );
      if (r != rowN - 1) rows.add(const SizedBox(height: spacing));
    }
    return Container(
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.resolveFrom(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CupertinoColors.systemGrey4.resolveFrom(context),
          width: border,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// 菜单单格：图标 + 单行文案（忽略系统字号缩放）
class ChatBubbleMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ChatBubbleMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: ChatBubbleMenuPanel.cellWidth,
        height: ChatBubbleMenuPanel.cellHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: context.textPrimaryColor),
            const SizedBox(height: 3),
            MediaQuery.withNoTextScaling(
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.15,
                  color: context.textPrimaryColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
