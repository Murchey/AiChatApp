import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/message.dart';
import '../widgets/character_avatar.dart';

/// 合并转发详情页：展示原始的聊天对话。
///
/// 规则：
/// - 所有消息头像均靠左排列；
/// - 同一发送者连续发送的消息，头像不重复显示（只在第一组显示）；
/// - 每条消息上方单独一行：左侧昵称、右侧发送时间。
class ForwardDetailScreen extends StatelessWidget {
  final List<ForwardItem> items;
  final String userAvatar;
  final String characterAvatar;

  const ForwardDetailScreen({
    super.key,
    required this.items,
    this.userAvatar = '',
    this.characterAvatar = '',
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('聊天记录'),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          // 与上一条发送者相同则视为连续消息，不再重复显示头像
          final showAvatar = index == 0 ||
              items[index - 1].senderName != item.senderName;
          return _buildItem(context, item, showAvatar);
        },
      ),
    );
  }

  Widget _buildItem(BuildContext context, ForwardItem item, bool showAvatar) {
    // 优先使用源会话角色头像（转发时已固化），旧数据回退到当前传入的头像
    final avatar = item.isUser
        ? userAvatar
        : (item.characterAvatar.isNotEmpty
            ? item.characterAvatar
            : characterAvatar);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 昵称（左）+ 发送时间（右），与气泡起始位置对齐
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 12, bottom: 2),
            child: Row(
              children: [
                Text(
                  item.senderName,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('HH:mm').format(item.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAvatar)
                _buildAvatar(context, avatar)
              else
                const SizedBox(width: 40),
              const SizedBox(width: 8),
              Flexible(child: _buildBubble(context, item)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, String avatarBase64) {
    return CharacterAvatar(base64: avatarBase64, size: 40);
  }

  Widget _buildBubble(BuildContext context, ForwardItem item) {
    if (item.type == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
          child: Image.file(
            File(item.content),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPlaceholder(
              context,
              CupertinoIcons.photo,
              '图片加载失败',
            ),
          ),
        ),
      );
    }
    if (item.type == 'file') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: item.isUser
              ? context.bubbleSelfColor
              : context.bubbleOtherColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.separatorColor,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.doc_fill,
              size: 28,
              color: context.accentColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                item.content.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.textPrimaryColor,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: item.isUser
            ? context.bubbleSelfColor
            : context.bubbleOtherColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.separatorColor,
          width: 0.5,
        ),
      ),
      child: Text(
        item.content,
        style: TextStyle(
          fontSize: 16,
          height: 1.4,
          color: item.isUser
              ? context.bubbleTextSelfColor
              : context.bubbleTextOtherColor,
        ),
      ),
    );
  }

  Widget _buildPlaceholder(
    BuildContext context,
    IconData icon,
    String text,
  ) {
    return Container(
      width: 120,
      height: 90,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: context.textSecondaryColor),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
