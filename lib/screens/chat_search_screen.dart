import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/chat_provider.dart';
import '../widgets/character_avatar.dart';
import 'chat_screen.dart';

/// 聊天记录搜索页：全局搜索所有会话的文本消息，点击结果定位到对应会话。
///
/// 搜索在内存中同步执行（所有聊天记录已常驻 ChatProvider，总量有限，
/// 逐条 contains 匹配开销极小）；结果按会话分组、每组内按时间升序，
/// 点击任意一条进入聊天页并滚动定位到该消息。
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({super.key});

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  // 时间标签用 DateFormat 只创建一次（构造开销较大）
  static final DateFormat _timeFmt = DateFormat('HH:mm');
  static final DateFormat _dateFmt = DateFormat('M月d日');
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final kw = value.trim();
    if (kw == _keyword) return;
    setState(() => _keyword = kw);
  }

  void _openChat(Conversation conv, Message msg) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conv.id,
          characterName: conv.characterName,
          characterAvatar: conv.characterAvatar,
          initialMessageId: msg.id,
        ),
      ),
    );
  }

  /// 转发卡片在结果中的预览文本：取第一条命中的内部文本
  String _forwardPreview(Message m) {
    final kw = _keyword.toLowerCase();
    for (final f in m.forwardedItems) {
      if (f.type == 'text' && f.content.toLowerCase().contains(kw)) {
        return '［聊天记录］${f.content}';
      }
    }
    return '［聊天记录］';
  }

  /// 将文本中命中关键词的部分高亮为 RichText spans
  List<TextSpan> _highlightSpans(String text) {
    final spans = <TextSpan>[];
    final kw = _keyword.toLowerCase();
    if (kw.isEmpty || !text.toLowerCase().contains(kw)) {
      spans.add(TextSpan(text: text));
      return spans;
    }
    final lower = text.toLowerCase();
    var start = 0;
    while (true) {
      final idx = lower.indexOf(kw, start);
      if (idx == -1) {
        if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + kw.length),
        style: TextStyle(
          color: context.accentColor,
          fontWeight: FontWeight.w600,
        ),
      ));
      start = idx + kw.length;
    }
    return spans;
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    return sameDay ? _timeFmt.format(time) : _dateFmt.format(time);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('搜索聊天记录'),
      ),
      child: Column(
        children: [
          // 搜索输入框（自动聚焦，输入即搜）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: CupertinoSearchTextField(
              controller: _controller,
              autofocus: true,
              placeholder: '搜索全部聊天记录',
              onChanged: _onChanged,
            ),
          ),
          Expanded(
            child: _keyword.isEmpty
                ? _buildHint()
                : Consumer<ChatProvider>(
                    builder: (context, chatProvider, _) {
                      final groups = chatProvider.searchMessages(_keyword);
                      if (groups.isEmpty) return _buildEmpty();
                      return _buildResultList(groups);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 未输入关键词时的引导提示
  Widget _buildHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.search,
            size: 48,
            color: context.textSecondaryColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '输入关键词搜索全部聊天记录',
            style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
          ),
        ],
      ),
    );
  }

  /// 无匹配结果
  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.doc_text,
            size: 48,
            color: context.textSecondaryColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '未找到相关聊天记录',
            style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
          ),
        ],
      ),
    );
  }

  /// 结果列表：按会话分组展示，每组以会话头部 + 匹配消息项
  Widget _buildResultList(
      List<MapEntry<Conversation, List<Message>>> groups) {
    final items = <MapEntry<Conversation, Message>>[
      for (final g in groups)
        for (final m in g.value) MapEntry(g.key, m),
    ];
    return Container(
      color: context.scaffoldColor,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => Container(
          height: 0.5,
          margin: const EdgeInsets.only(left: 61),
          color: context.separatorColor,
        ),
        itemBuilder: (context, index) {
          final conv = items[index].key;
          final msg = items[index].value;
          final content =
              msg.isForwardCard ? _forwardPreview(msg) : msg.content;
          return CupertinoListTile(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leadingSize: 45,
            leading: CharacterAvatar(base64: conv.characterAvatar, size: 45),
            title: Text(
              conv.characterName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: context.textPrimaryColor,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: context.textSecondaryColor,
                  ),
                  children: [
                    TextSpan(
                      text: msg.isFromUser ? '我：' : '${conv.characterName}：',
                      style: TextStyle(color: context.textPrimaryColor),
                    ),
                    ..._highlightSpans(content),
                  ],
                ),
              ),
            ),
            trailing: Text(
              _formatTime(msg.createdAt),
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
            onTap: () => _openChat(conv, msg),
          );
        },
      ),
    );
  }
}
