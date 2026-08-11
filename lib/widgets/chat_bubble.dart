import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/message.dart';

class ChatBubble extends StatefulWidget {
  final Message message;
  final String userAvatar;
  final String characterAvatar;
  /// 回调参数为消息本身 + 气泡的 GlobalKey（用于定位菜单）
  final Function(Message message, GlobalKey bubbleKey)? onLongPress;

  const ChatBubble({
    super.key,
    required this.message,
    this.userAvatar = '',
    this.characterAvatar = '',
    this.onLongPress,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  final GlobalKey _bubbleKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.isFromUser;
    final avatar = isUser ? widget.userAvatar : widget.characterAvatar;
    final isImage = message.type == MessageType.image;
    final isFile = message.type == MessageType.file;

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
              onLongPress: widget.onLongPress != null
                  ? () => widget.onLongPress!(message, _bubbleKey)
                  : null,
              child: Container(
                key: _bubbleKey,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                      ? context.bubbleSelfColor
                      : context.bubbleOtherColor,
                  borderRadius: BorderRadius.circular(12),
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
                      _buildQuoteBlock(context, widget.message),
                    // 图片消息
                    if (isImage) ...[
                      _buildImageContent(context),
                      const SizedBox(height: 6),
                    ] else if (isFile) ...[
                      _buildFileContent(context),
                      const SizedBox(height: 6),
                    ] else ...[
                      Text(
                        message.content,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.4,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
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

  /// 文件消息显示
  Widget _buildFileContent(BuildContext context) {
    final fileName = widget.message.content.split('/').last;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.doc_fill,
            size: 32,
            color: context.accentColor,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '点击打开文件',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 图片消息显示
  Widget _buildImageContent(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
        child: Image.file(
          File(widget.message.content),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(
                  CupertinoIcons.photo,
                  size: 40,
                  color: context.textSecondaryColor,
                ),
                const SizedBox(height: 6),
                Text(
                  '图片加载失败',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
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
