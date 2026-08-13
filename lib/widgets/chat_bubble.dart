import 'dart:io';
import 'package:flutter/cupertino.dart';
import '../config/theme.dart';
import '../models/message.dart';
import 'character_avatar.dart';

/// 微信表情代码 → emoji 映射：AI 按输出规则会携带表情包文字（如 [捂脸]），
/// 渲染时转成真实 emoji 图标，贴近微信聊天观感。未收录的代码原样保留。
const Map<String, String> _emojiCodeMap = {
  '微笑': '😊', '呲牙': '😁', '得意': '😎', '愉快': '😄', '偷笑': '😏',
  '坏笑': '😏', '憨笑': '😊', '害羞': '😳', '可爱': '🥰', '捂脸': '🤦',
  '笑哭': '😂', '大笑': '😂', '流泪': '😭', '大哭': '😭', '委屈': '😢',
  '快哭了': '😢', '难过': '😞', '尴尬': '😅', '冷汗': '😰', '流汗': '😓',
  '擦汗': '😓', '发呆': '😳', '晕': '😵', '衰': '😩', '鄙视': '🙄',
  '白眼': '🙄', '傲慢': '😤', '发怒': '😡', '咒骂': '🤬', '怄火': '😠',
  '惊讶': '😱', '惊恐': '😨', '吓': '😱', '疑问': '❓', '闭嘴': '🤐',
  '嘘': '🤫', '睡': '😴', '困': '😪', '哈欠': '🥱', '饥饿': '😋',
  '吐': '🤮', '抠鼻': '🤏', '骷髅': '💀', '猪头': '🐷', '炸弹': '💣',
  '菜刀': '🔪', '刀': '🔪', '西瓜': '🍉', '啤酒': '🍺', '咖啡': '☕',
  '饭': '🍚', '蛋糕': '🎂', '玫瑰': '🌹', '凋谢': '🥀', '爱心': '❤️',
  '心碎': '💔', '嘴唇': '👄', '亲亲': '😘', '飞吻': '😘', '拥抱': '🤗',
  '强': '👍', '弱': '👎', '差劲': '👎', '握手': '🤝', '抱拳': '🙏',
  '胜利': '✌️', '拳头': '👊', '敲打': '👊', '鼓掌': '👏', '再见': '👋',
  'OK': '👌', 'NO': '🙅', '勾引': '👉', '奋斗': '💪', '给力': '💪',
  '磕头': '🙇', '月亮': '🌙', '太阳': '☀️', '闪电': '⚡', '礼物': '🎁',
  '篮球': '🏀', '足球': '⚽', '乒乓': '🏓', '瓢虫': '🐞', '便便': '💩',
};

/// 匹配 [表情名] 形式的微信表情代码（名字 1~8 个字）
final RegExp _emojiCodePattern = RegExp(r'\[([^\[\]]{1,8})\]');

/// 将消息正文中的表情代码替换为对应 emoji，未收录的代码原样保留
String _renderEmoji(String text) {
  if (text.isEmpty || !text.contains('[')) return text;
  return text.replaceAllMapped(_emojiCodePattern, (match) {
    final code = match.group(1);
    if (code == null) return match[0]!;
    return _emojiCodeMap[code] ?? match[0]!;
  });
}

class ChatBubble extends StatefulWidget {
  final Message message;
  final String userAvatar;
  final String characterAvatar;
  /// 回调参数为消息本身 + 气泡的 GlobalKey（用于定位菜单）
  final Function(Message message, GlobalKey bubbleKey)? onLongPress;
  /// 多选模式：点击气泡切换选中，且不再触发长按菜单
  final bool selectMode;
  final bool selected;
  final VoidCallback? onTap;
  /// 点击"合并转发"聊天记录卡片时回调（进入详情页）
  final VoidCallback? onForwardTap;
  /// 点击文件消息卡片时回调（参数为文件路径，用于打开文件）
  final Future<void> Function(String filePath)? onFileTap;
  /// 点击"我"的头像时回调（进入自己的空间页）
  final VoidCallback? onUserAvatarTap;
  /// 点击"对方"头像时回调（进入对方的空间页）
  final VoidCallback? onCharacterAvatarTap;

  const ChatBubble({
    super.key,
    required this.message,
    this.userAvatar = '',
    this.characterAvatar = '',
    this.onLongPress,
    this.selectMode = false,
    this.selected = false,
    this.onTap,
    this.onForwardTap,
    this.onFileTap,
    this.onUserAvatarTap,
    this.onCharacterAvatarTap,
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

    // 合并转发"聊天记录"卡片：独立展示，不包裹在聊天气泡内
    if (message.isForwardCard) {
      return _buildForwardCard(context);
    }

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
            _buildAvatar(context, avatar, onTap: widget.onCharacterAvatarTap),
            const SizedBox(width: 8),
          ],
          // 多选模式：选中勾选框（消息在左侧时勾选框在气泡右侧）
          if (widget.selectMode && !isUser) _buildSelectCheck(context),
          Flexible(
            child: GestureDetector(
              onTap: widget.selectMode ? widget.onTap : null,
              onLongPress: widget.selectMode
                  ? null
                  : (widget.onLongPress != null
                      ? () => widget.onLongPress!(message, _bubbleKey)
                      : null),
              child: Container(
                key: _bubbleKey,
                // 图片/文件消息不包裹气泡（透明背景、无内边距），仅多选时显示选中描边
                padding: isImage || isFile
                    ? EdgeInsets.all(widget.selected ? 2 : 0)
                    : const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isImage || isFile
                      ? CupertinoColors.transparent
                      : (isUser
                          ? context.bubbleSelfColor
                          : context.bubbleOtherColor),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.selected
                        ? context.accentColor
                        : (isImage || isFile
                            ? CupertinoColors.transparent
                            : context.separatorColor),
                    width: widget.selected ? 1.5 : 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 引用块
                    if (message.quoteContent.isNotEmpty)
                      _buildQuoteBlock(context, widget.message),
                    if (isImage)
                      _buildImageContent(context)
                    else if (isFile) ...[
                      _buildFileContent(context),
                      const SizedBox(height: 6),
                    ] else ...[
                      Text(
                        _renderEmoji(message.content),
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.4,
                          color: isUser
                              ? context.bubbleTextSelfColor
                              : context.bubbleTextOtherColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 多选模式：消息在右侧时勾选框在气泡左侧
          if (widget.selectMode && isUser) _buildSelectCheck(context),
          if (isUser) ...[
            const SizedBox(width: 8),
            _buildAvatar(context, avatar, onTap: widget.onUserAvatarTap),
          ],
        ],
      ),
    );
  }

  /// 多选模式下的选中勾选框
  Widget _buildSelectCheck(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 22),
      child: Icon(
        widget.selected
            ? CupertinoIcons.checkmark_circle_fill
            : CupertinoIcons.circle,
        size: 22,
        color: widget.selected
            ? context.accentColor
            : context.textSecondaryColor,
      ),
    );
  }

  /// 合并转发"聊天记录"卡片：独立整行展示（不用气泡包裹），
  /// 点击进入详情页查看原始对话；多选模式下点击切换选中。
  Widget _buildForwardCard(BuildContext context) {
    final items = widget.message.forwardedItems;
    final previews = items.take(3).map((e) {
      final display = e.type == 'image'
          ? '[图片]'
          : e.type == 'file'
              ? '[文件]'
              : e.content;
      return '${e.senderName}: $display';
    }).join('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // 多选模式：选中勾选框（卡片在左侧时勾选框在右侧）
          if (widget.selectMode) _buildSelectCheck(context),
          Expanded(
            child: GestureDetector(
              onTap: widget.selectMode ? widget.onTap : widget.onForwardTap,
              onLongPress: widget.selectMode
                  ? null
                  : (widget.onLongPress != null
                      ? () => widget.onLongPress!(widget.message, _bubbleKey)
                      : null),
              child: Container(
                key: _bubbleKey,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.listBgColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.selected
                        ? context.accentColor
                        : CupertinoColors.transparent,
                    width: widget.selected ? 1.5 : 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '聊天记录',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${items.length} 条消息',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 0.5,
                      color: context.separatorColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      previews,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 我方转发人头像（右侧）
          const SizedBox(width: 8),
          _buildAvatar(context, widget.userAvatar, onTap: widget.onUserAvatarTap),
        ],
      ),
    );
  }

  /// 文件消息显示（点击调用系统"打开方式"打开文件）
  Widget _buildFileContent(BuildContext context) {
    final fileName = widget.message.content.split('/').last;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onFileTap?.call(widget.message.content),
      child: Container(
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
      ),
    );
  }

  /// 图片消息显示
  Widget _buildImageContent(BuildContext context) {
    // 按实际显示尺寸（240 * 屏幕像素密度）解码图片，避免把原始大图全量解码到内存，
    // 图片消息较多时能显著降低内存占用与滚动卡顿
    final decodeSize = (240 * MediaQuery.devicePixelRatioOf(context)).ceil();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
        child: Image.file(
          File(widget.message.content),
          fit: BoxFit.cover,
          cacheWidth: decodeSize,
          cacheHeight: decodeSize,
          gaplessPlayback: true, // 列表重建时复用上一帧，避免图片闪烁
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

  /// 头像：跟随全局设置（方形 / 仿 QQ 圆形），未设置时显示默认用户图标；
  /// [onTap] 非空时头像可点击（进入对应的空间页）
  Widget _buildAvatar(BuildContext context, String avatarBase64,
      {VoidCallback? onTap}) {
    final avatar = CharacterAvatar(base64: avatarBase64, size: 40);
    if (onTap == null) return avatar;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: avatar,
    );
  }
}
