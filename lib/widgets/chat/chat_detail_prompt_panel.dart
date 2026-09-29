import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';

  class ChatDetailPromptPanel extends StatelessWidget {
  final VoidCallback onOpenPrompt;
  final VoidCallback onOpenMemory;

  const ChatDetailPromptPanel({
    super.key,
    required this.onOpenPrompt,
    required this.onOpenMemory,
  });

  @override
  Widget build(BuildContext context) {
    return _body(context);
  }

  Widget _body(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          CupertinoListTile(
            leading: const Icon(CupertinoIcons.text_quote),
            title: Text(
              '提示词设置',
              style: TextStyle(color: context.textPrimaryColor),
            ),
            subtitle: Text(
              '定义角色对话时的行为与设定，点击进入编辑',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: context.textSecondaryColor,
            ),
            onTap: onOpenPrompt,
          ),
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(left: 16),
            color: context.separatorColor,
          ),
          CupertinoListTile(
            leading: const Icon(CupertinoIcons.bookmark),
            title: Text(
              '记忆点管理',
              style: TextStyle(color: context.textPrimaryColor),
            ),
            subtitle: Text(
              '此处可以储存世界观、用户人设、对话中的记忆点等，可回传到上下文',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: context.textSecondaryColor,
            ),
            onTap: onOpenMemory,
          ),
        ],
      ),
    );
  }
}
