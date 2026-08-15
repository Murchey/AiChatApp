import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import '../config/theme.dart';
import '../models/message.dart';
import '../providers/settings_provider.dart';
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

/// 将消息内容渲染为富文本：`[表情]` 转 emoji，`@名字` 高亮为蓝色。
TextSpan _buildMessageSpan(
  BuildContext context,
  String content,
  Color baseColor,
) {
  final text = _renderEmoji(content);
  final spans = <TextSpan>[];
  var start = 0;
  for (final m in RegExp(r'(@[^\s@]+)').allMatches(text)) {
    if (m.start > start) {
      spans.add(TextSpan(text: text.substring(start, m.start)));
    }
    spans.add(TextSpan(
      text: m.group(1),
      style: const TextStyle(
        color: CupertinoColors.systemBlue,
        fontWeight: FontWeight.w500,
      ),
    ));
    start = m.end;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }
  return TextSpan(
    children: spans,
    style: TextStyle(fontSize: 16, height: 1.4, color: baseColor),
  );
}

class ChatBubble extends StatefulWidget {
  final Message message;
  final String userAvatar;
  final String characterAvatar;
  /// 群聊中角色消息的发送者显示名（非空时显示在气泡上方，私聊为空）
  final String senderName;
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
    this.senderName = '',
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

    // 系统事件消息（如群成员加入/移除）：居中灰色小气泡，无头像/引用/长按菜单
    if (message.type == MessageType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.textSecondaryColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              message.content,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: context.textSecondaryColor,
              ),
            ),
          ),
        ),
      );
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
            child: Padding(
              // sr/ww/zmd 样式：气泡顶边（含尾巴尖角）对齐头像垂直中线（头像 40px → 下移 20px）。
              // 群聊角色消息带昵称（约 19px），昵称贴顶后气泡紧跟其后顶边已在
              // 头像中线附近，无需再下移；私聊无昵称则下移 20px。
              padding: EdgeInsets.only(
                top: (context.bubbleStyle == BubbleStyle.sr ||
                        context.bubbleStyle == BubbleStyle.ww ||
                        context.bubbleStyle == BubbleStyle.zmd) &&
                        widget.senderName.isEmpty
                    ? 20
                    : 0,
              ),
              child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 群聊中角色消息显示发送者昵称（私聊无）
                if (!isUser && widget.senderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 3),
                    child: Text(
                      widget.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: widget.selectMode ? widget.onTap : null,
                  onLongPress: widget.selectMode
                      ? null
                      : (widget.onLongPress != null
                          ? () => widget.onLongPress!(message, _bubbleKey)
                          : null),
                  child: _buildBubbleBox(
                    context,
                    isImage,
                    isFile,
                    Column(
                      crossAxisAlignment: isUser
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
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
                          RichText(
                            text: _buildMessageSpan(
                              context,
                              message.content,
                              context.bubbleTextColor(isUser),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
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

  /// 构建气泡主体容器：ww 鸣潮 / zmd 终末地样式用 CustomClipper 绘制带尾巴形状，
  /// 其余样式使用普通 BoxDecoration（矩形圆角 / sr 直角圆角）
  Widget _buildBubbleBox(
    BuildContext context,
    bool isImage,
    bool isFile,
    Widget child,
  ) {
    final isUser = widget.message.isFromUser;
    // 尾巴样式（ww/zmd）：上边共线尾巴 + 大圆角弧线
    final isTailStyle =
        !isImage &&
        !isFile &&
        (context.bubbleStyle == BubbleStyle.ww ||
            context.bubbleStyle == BubbleStyle.zmd);
    if (isTailStyle) {
      final isWwStyle = context.bubbleStyle == BubbleStyle.ww;
      return Container(
        key: _bubbleKey,
        decoration: BoxDecoration(
          // 外层只负责柔和投影；圆角按尾巴朝向镜像，与裁剪形状一致
          borderRadius: isWwStyle
              ? (isUser
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(5),
                      topRight: Radius.circular(5),
                      bottomLeft: Radius.circular(15),
                      bottomRight: Radius.circular(5),
                    )
                  : const BorderRadius.only(
                      topLeft: Radius.circular(5),
                      topRight: Radius.circular(5),
                      bottomLeft: Radius.circular(5),
                      bottomRight: Radius.circular(15),
                    ))
              : (isUser
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(15),
                      topRight: Radius.zero,
                      bottomLeft: Radius.circular(15),
                      bottomRight: Radius.circular(15),
                    )
                  : const BorderRadius.only(
                      topLeft: Radius.zero,
                      topRight: Radius.circular(15),
                      bottomLeft: Radius.circular(15),
                      bottomRight: Radius.circular(15),
                    )),
          boxShadow: context.bubbleShadow,
        ),
        child: ClipPath(
          clipper: isWwStyle
              ? WwBubbleClipper(isUser: isUser)
              : ZmdBubbleClipper(isUser: isUser),
          child: Container(
            color: context.bubbleBgColor(isUser),
            // zmd 我方白底气泡带黑色轮廓描边（跟随裁剪形状），其余无描边
            foregroundDecoration: context.bubbleBorderColor(isUser) != null
                ? BoxDecoration(
                    border: Border.all(
                      color: context.bubbleBorderColor(isUser)!,
                      width: 1,
                    ),
                  )
                : null,
            // 尾巴侧多留出 tailLen 空间，内容不贴尾巴弧线（两样式 tailLen 均为 14）
            padding: EdgeInsets.only(
              left: isUser ? 14 : 14 + WwBubbleClipper.tailLen,
              right: isUser ? 14 + WwBubbleClipper.tailLen : 14,
              top: 10,
              bottom: 10,
            ),
            child: child,
          ),
        ),
      );
    }
    return Container(
      key: _bubbleKey,
      // 图片/文件消息不包裹气泡（透明背景、无内边距），仅多选时显示选中描边
      padding: isImage || isFile
          ? EdgeInsets.all(widget.selected ? 2 : 0)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isImage || isFile
            ? CupertinoColors.transparent
            : context.bubbleBgColor(isUser),
        borderRadius: context.bubbleBorderRadiusFor(isUser),
        border: widget.selected
            ? Border.all(
                color: context.accentColor,
                width: 1.5,
              )
            : (isImage ||
                    isFile ||
                    context.bubbleStyle == BubbleStyle.sr ||
                    context.bubbleStyle == BubbleStyle.ww)
                ? null
                : Border.all(
                    color: context.separatorColor,
                    width: 0.5,
                  ),
        boxShadow: isImage || isFile
            ? const <BoxShadow>[]
            : context.bubbleShadow,
      ),
      child: child,
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
      // 引用块跟随内容宽度收缩，避免把气泡撑满整行
      constraints: const BoxConstraints(maxWidth: 240),
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

/// 构建「上边共线尾巴 + 圆角」的气泡路径（ww/zmd 共用）。
/// 尾巴尖端在气泡顶边（与头像中线对齐），回程弧线圆心在气泡外侧尖端一侧，
/// 两侧镜像对称。参数：
/// [topCornerRadius] 尾巴远端的上角圆角；
/// [tailSideCornerRadius] 尾巴侧的下角圆角（底边与尾巴侧边之间）；
/// [bottomCornerRadius] 远离尾巴的下角圆角。
Path _buildTailBubblePath(
  Size size, {
  required bool isUser,
  required double tailLen,
  required double tailArcRadius,
  required double topCornerRadius,
  required double tailSideCornerRadius,
  required double bottomCornerRadius,
}) {
  final w = size.width;
  final h = size.height;
  // 回程弧线落点 y = min(h*0.25, tailArcRadius)：
  // 落点与弧半径相等时弧为标准 90° 圆弧，弦长 d = √(tailLen² + r²) < 2r 恒成立，
  // 气泡换行变高时弧线始终可画且方向稳定（凸向尖端外侧），不会退化或内凹
  final kneeY = math.min(h * 0.25, tailArcRadius);
  final path = Path();
  if (isUser) {
    // 我方气泡（右侧，说话人在右）：尾巴在右上角，尖端朝右
    path.moveTo(w, 0); // 尖端
    path.lineTo(topCornerRadius, 0); // 尾巴上边与顶边共线
    path.quadraticBezierTo(0, 0, 0, topCornerRadius); // 左上角
    path.lineTo(0, h - bottomCornerRadius); // 左边线
    path.quadraticBezierTo(0, h, bottomCornerRadius, h); // 左下角
    path.lineTo(w - tailLen - tailSideCornerRadius, h); // 底边
    path.quadraticBezierTo(w - tailLen, h, w - tailLen,
        h - tailSideCornerRadius); // 尾巴侧下角
    // 尾巴回程：竖直直线 + 固定半径弧线（圆心在气泡外侧尖端一侧）
    path.lineTo(w - tailLen, kneeY);
    path.arcToPoint(Offset(w, 0), radius: Radius.circular(tailArcRadius));
  } else {
    // 对方气泡（左侧，说话人在左）：尾巴在左上角，尖端朝左
    path.moveTo(0, 0); // 尖端
    path.lineTo(w - topCornerRadius, 0); // 尾巴上边与顶边共线
    path.quadraticBezierTo(w, 0, w, topCornerRadius); // 右上角
    path.lineTo(w, h - bottomCornerRadius); // 右边线
    path.quadraticBezierTo(w, h, w - bottomCornerRadius, h); // 右下角
    path.lineTo(tailLen + tailSideCornerRadius, h); // 底边
    path.quadraticBezierTo(
        tailLen, h, tailLen, h - tailSideCornerRadius); // 尾巴侧下角
    // 尾巴回程：竖直直线 + 固定半径弧线（圆心在气泡外侧尖端一侧，镜像对称）
    path.lineTo(tailLen, kneeY);
    path.arcToPoint(const Offset(0, 0),
        radius: Radius.circular(tailArcRadius), clockwise: false);
  }
  path.close();
  return path;
}

/// ww 鸣潮气泡形状裁剪：
/// 靠近说话人一侧的上边缘伸出锐角三角形尾巴（上边与气泡顶边共线），
/// 尾巴回程边为圆心在气泡外侧（尖端一侧）的大圆角弧线，两侧镜像对称；
/// 我方右下角 / 对方左下角为 15px 大圆角，另外两个小角 5px。
class WwBubbleClipper extends CustomClipper<Path> {
  const WwBubbleClipper({required this.isUser});

  /// 说话人在本气泡的哪一侧（true = 右侧，尾巴朝右）
  final bool isUser;

  /// 尾巴伸出长度（尖端到气泡主体侧边的水平距离）
  static const double tailLen = 14;
  /// 尾巴回程弧线 / 远离尾巴下角大圆角半径
  static const double rBig = 15;
  /// 其余两个小角圆角半径
  static const double rSmall = 5;

  @override
  Path getClip(Size size) => _buildTailBubblePath(
        size,
        isUser: isUser,
        tailLen: tailLen,
        tailArcRadius: rBig,
        topCornerRadius: rSmall,
        tailSideCornerRadius: rSmall,
        bottomCornerRadius: rBig,
      );

  @override
  bool shouldReclip(covariant WwBubbleClipper oldClipper) =>
      oldClipper.isUser != isUser;
}

/// zmd 终末地气泡形状裁剪：形状与鸣潮相同，仅圆角参数不同。
/// 终末地所有角统一 10px 圆角（tail 回程弧线与其余三个角一致）。
class ZmdBubbleClipper extends CustomClipper<Path> {
  const ZmdBubbleClipper({required this.isUser});

  /// 说话人在本气泡的哪一侧（true = 右侧，尾巴朝右）
  final bool isUser;

  /// 尾巴伸出长度（与鸣潮一致）
  static const double tailLen = 14;
  /// 尾巴回程弧线半径
  static const double tailArcRadius = 10;
  /// 其余三个角圆角半径（与 tail 连接处一致）
  static const double cornerRadius = 10;

  @override
  Path getClip(Size size) => _buildTailBubblePath(
        size,
        isUser: isUser,
        tailLen: tailLen,
        tailArcRadius: tailArcRadius,
        topCornerRadius: cornerRadius,
        tailSideCornerRadius: cornerRadius,
        bottomCornerRadius: cornerRadius,
      );

  @override
  bool shouldReclip(covariant ZmdBubbleClipper oldClipper) =>
      oldClipper.isUser != isUser;
}
