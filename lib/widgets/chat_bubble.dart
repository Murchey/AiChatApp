import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/message.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final String userAvatar;
  final String characterAvatar;
  final VoidCallback? onLongPress;

  const ChatBubble({
    super.key,
    required this.message,
    this.userAvatar = '',
    this.characterAvatar = '',
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isFromUser;
    final avatar = isUser ? userAvatar : characterAvatar;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(context, avatar),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                      ? context.bubbleSelfColor
                      : context.bubbleOtherColor,
                  borderRadius: BorderRadius.circular(12),
                  // 灰色轮廓描边
                  border: Border.all(
                    color: context.separatorColor,
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 引用块
                    if (message.quoteContent.isNotEmpty)
                      _buildQuoteBlock(context, message),
                    Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('HH:mm').format(message.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: isUser
                            ? context.textPrimaryColor.withValues(alpha: 0.45)
                            : context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            _buildAvatar(context, avatar),
          ],
        ],
      ),
    );
  }

  /// 引用消息块
  Widget _buildQuoteBlock(BuildContext context, Message message) {
    final quoteName = message.quoteSender.isNotEmpty
        ? '${message.quoteSender}: '
        : '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$quoteName${message.quoteContent}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          height: 1.3,
          color: context.textSecondaryColor,
        ),
      ),
    );
  }

  /// 方形头像：已设置显示图片，未设置显示默认用户图标
  Widget _buildAvatar(BuildContext context, String avatarBase64) {
    if (avatarBase64.isNotEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: MemoryImage(base64Decode(avatarBase64)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.accentColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.person_fill,
        size: 22,
        color: context.accentColor,
      ),
    );
  }
}
