import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../providers/chat_provider.dart';

/// 聊天管理区：自动朗读 / 背景 / 组建群聊 / 清空 / 删除
class ChatDetailManageSection extends StatelessWidget {
  final String conversationId;
  final VoidCallback onShowBackground;
  final VoidCallback onCreateGroup;
  final VoidCallback onClearContext;
  final VoidCallback onDeleteChat;

  const ChatDetailManageSection({
    super.key,
    required this.conversationId,
    required this.onShowBackground,
    required this.onCreateGroup,
    required this.onClearContext,
    required this.onDeleteChat,
  });

  Widget _sep(BuildContext context) => Container(
        height: 0.5,
        margin: const EdgeInsets.only(left: 16),
        color: context.separatorColor,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Consumer<ChatProvider>(builder: (context, chatProvider, _) {
            final conversation = chatProvider.conversations
                .where((c) => c.id == conversationId)
                .firstOrNull;
            return CupertinoListTile(
              leading: Icon(CupertinoIcons.speaker_3_fill,
                  color: context.textSecondaryColor),
              title: Text('自动朗读',
                  style: TextStyle(color: context.textPrimaryColor)),
              subtitle: Text('角色生成回复后自动播放语音',
                  style: TextStyle(
                      fontSize: 12, color: context.textSecondaryColor)),
              trailing: CupertinoSwitch(
                value: conversation?.autoRead ?? false,
                onChanged: (value) => context
                    .read<ChatProvider>()
                    .setConversationAutoRead(conversationId, value),
              ),
            );
          }),
          Consumer<ChatProvider>(builder: (context, chatProvider, _) {
            final conversation = chatProvider.conversations
                .where((c) => c.id == conversationId)
                .firstOrNull;
            return CupertinoListTile(
              leading: Icon(CupertinoIcons.play_circle,
                  color: context.textSecondaryColor),
              title: Text('连续播放回复',
                  style: TextStyle(color: context.textPrimaryColor)),
              subtitle: Text('一轮多条角色回复按顺序连续播放',
                  style: TextStyle(
                      fontSize: 12, color: context.textSecondaryColor)),
              trailing: CupertinoSwitch(
                value: conversation?.continuousRead ?? false,
                onChanged: (value) => context
                    .read<ChatProvider>()
                    .setConversationContinuousRead(conversationId, value),
              ),
            );
          }),
          Consumer<ChatProvider>(builder: (context, chatProvider, _) {
            final conversation = chatProvider.conversations
                .where((c) => c.id == conversationId)
                .firstOrNull;
            return CupertinoListTile(
              leading: Icon(CupertinoIcons.speaker_1,
                  color: context.textSecondaryColor),
              title: Text('显示小喇叭图标',
                  style: TextStyle(color: context.textPrimaryColor)),
              subtitle: Text('角色气泡下方显示朗读按钮（默认关闭）',
                  style: TextStyle(
                      fontSize: 12, color: context.textSecondaryColor)),
              trailing: CupertinoSwitch(
                value: conversation?.showSpeakerIcon ?? false,
                onChanged: (value) => context
                    .read<ChatProvider>()
                    .setConversationShowSpeakerIcon(conversationId, value),
              ),
            );
          }),
          _sep(context),
          CupertinoListTile(
            leading: const Icon(
              CupertinoIcons.photo_fill_on_rectangle_fill,
              color: CupertinoColors.systemPink,
            ),
            title:
                Text('聊天背景', style: TextStyle(color: context.textPrimaryColor)),
            subtitle: Text(
              '为当前会话设置独立背景与高斯模糊效果',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
            ),
            trailing: Icon(CupertinoIcons.chevron_right,
                size: 14, color: context.textSecondaryColor),
            onTap: onShowBackground,
          ),
          _sep(context),
          CupertinoListTile(
            leading: Icon(CupertinoIcons.person_3_fill,
                color: context.textPrimaryColor),
            title:
                Text('组建群聊', style: TextStyle(color: context.textPrimaryColor)),
            subtitle: Text('把当前角色和其他角色拉进同一个群聊',
                style:
                    TextStyle(fontSize: 12, color: context.textSecondaryColor)),
            onTap: onCreateGroup,
          ),
          _sep(context),
          CupertinoListTile(
            leading: Icon(CupertinoIcons.clear_circled,
                color: context.textPrimaryColor),
            title: Text('清空上下文',
                style: TextStyle(color: context.textPrimaryColor)),
            subtitle: Text(
              '清除当前聊天的全部消息，再次打开时不会显示任何记录，AI 也不会继承此前的对话内容',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: context.textSecondaryColor),
            ),
            onTap: onClearContext,
          ),
          _sep(context),
          CupertinoListTile(
            leading: const Icon(CupertinoIcons.trash,
                color: CupertinoColors.systemRed),
            title: const Text('删除聊天',
                style: TextStyle(color: CupertinoColors.systemRed)),
            subtitle: Text(
              '从首页会话列表中移除该聊天，同时删除全部聊天记录与上下文，此操作不可恢复',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: context.textSecondaryColor),
            ),
            onTap: onDeleteChat,
          ),
        ],
      ),
    );
  }
}
