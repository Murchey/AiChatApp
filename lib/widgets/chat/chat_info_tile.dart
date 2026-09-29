import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';

/// 资料卡条目：图标 + 标签 + 当前值 + 右箭头
class ChatInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String placeholder;
  final VoidCallback onTap;

  const ChatInfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.placeholder = '',
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      leading: Icon(icon, color: context.textPrimaryColor),
      title: Text(
        label,
        style: TextStyle(color: context.textPrimaryColor),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              value.isEmpty ? placeholder : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: value.isEmpty
                    ? context.textSecondaryColor.withValues(alpha: 0.6)
                    : context.textSecondaryColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            CupertinoIcons.chevron_right,
            size: 14,
            color: context.textSecondaryColor,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// 列表内分隔线
class ChatSectionSeparator extends StatelessWidget {
  const ChatSectionSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 52),
      color: context.separatorColor,
    );
  }
}
