import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';
import '../../models/message.dart';

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

/// 气泡长按菜单项集合（回调由聊天页注入）。
class ChatBubbleMenuItems {
  final Message message;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final VoidCallback onSelectText;
  final VoidCallback onQuote;
  final VoidCallback? onWithdraw;
  final VoidCallback? onEdit;
  final VoidCallback? onShowReasoning;
  final VoidCallback? onReroll;
  final VoidCallback? onDelete;
  final VoidCallback onSaveMemory;
  final VoidCallback onMultiSelect;
  final VoidCallback onBranch;

  const ChatBubbleMenuItems({
    required this.message,
    required this.onClose,
    required this.onCopy,
    required this.onSelectText,
    required this.onQuote,
    this.onWithdraw,
    this.onEdit,
    this.onShowReasoning,
    this.onReroll,
    this.onDelete,
    required this.onSaveMemory,
    required this.onMultiSelect,
    required this.onBranch,
  });

  List<Widget> build() {
    final isUser = message.isFromUser;
    final items = <Widget>[
      ChatBubbleMenuItem(
        icon: CupertinoIcons.doc_on_doc,
        label: '复制',
        onTap: () {
          onClose();
          onCopy();
        },
      ),
      ChatBubbleMenuItem(
        icon: CupertinoIcons.text_badge_checkmark,
        label: '选择文本',
        onTap: () {
          onClose();
          onSelectText();
        },
      ),
      ChatBubbleMenuItem(
        icon: CupertinoIcons.quote_bubble,
        label: '引用',
        onTap: () {
          onClose();
          onQuote();
        },
      ),
    ];
    if (isUser) {
      if (onWithdraw != null) {
        items.add(ChatBubbleMenuItem(
          icon: CupertinoIcons.xmark_circle,
          label: '撤回',
          onTap: () {
            onClose();
            onWithdraw!();
          },
        ));
      }
      if (message.type == MessageType.narration && onEdit != null) {
        items.add(ChatBubbleMenuItem(
          icon: CupertinoIcons.pencil,
          label: '编辑剧情',
          onTap: () {
            onClose();
            onEdit!();
          },
        ));
      }
    } else {
      if (message.hasReasoning && onShowReasoning != null) {
        items.add(ChatBubbleMenuItem(
          icon: CupertinoIcons.lightbulb,
          label: '查看思考',
          onTap: () {
            onClose();
            onShowReasoning!();
          },
        ));
      }
      if (onEdit != null) {
        items.add(ChatBubbleMenuItem(
          icon: CupertinoIcons.pencil,
          label: '修改本条',
          onTap: () {
            onClose();
            onEdit!();
          },
        ));
      }
      if (onReroll != null) {
        items.add(ChatBubbleMenuItem(
          icon: CupertinoIcons.refresh,
          label: '重新回复',
          onTap: () {
            onClose();
            onReroll!();
          },
        ));
      }
      if (onDelete != null) {
        items.add(ChatBubbleMenuItem(
          icon: CupertinoIcons.delete,
          label: '删除',
          onTap: () {
            onClose();
            onDelete!();
          },
        ));
      }
    }
    items.add(ChatBubbleMenuItem(
      icon: CupertinoIcons.bookmark,
      label: '保存为记忆点',
      onTap: () {
        onClose();
        onSaveMemory();
      },
    ));
    items.add(ChatBubbleMenuItem(
      icon: CupertinoIcons.square_stack,
      label: '多选',
      onTap: () {
        onClose();
        onMultiSelect();
      },
    ));
    items.add(ChatBubbleMenuItem(
      icon: CupertinoIcons.arrow_branch,
      label: '增加分支',
      onTap: () {
        onClose();
        onBranch();
      },
    ));
    return items;
  }
}
