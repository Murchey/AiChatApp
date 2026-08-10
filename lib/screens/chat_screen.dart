import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/message.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/character_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/message_input.dart';
import 'chat_settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String characterName;
  final String characterAvatar;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.characterName,
    this.characterAvatar = '',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  Message? _quoteMessage; // 待引用的消息

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  /// 右上角三点菜单：聊天设置 / 导出聊天记录
  void _showMoreActions(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(widget.characterName),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => const ChatSettingsScreen(),
                ),
              );
            },
            child: const Text('聊天设置'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _exportChat();
            },
            child: const Text('导出聊天记录'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 导出当前聊天记录为 Markdown 文件保存到手机
  Future<void> _exportChat() async {
    final messages =
        context.read<ChatProvider>().getMessages(widget.conversationId);
    if (messages.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('暂无聊天记录可导出'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    // 生成 Markdown 内容
    final sb = StringBuffer();
    sb.writeln('# 与 ${widget.characterName} 的聊天记录');
    sb.writeln();
    sb.writeln('> 导出时间: ${_formatDateTime(DateTime.now())}');
    sb.writeln();
    for (final message in messages) {
      final who = message.isFromUser ? '我' : widget.characterName;
      sb.writeln('## ${_formatDateTime(message.createdAt)} - $who');
      sb.writeln();
      sb.writeln(message.content);
      sb.writeln();
    }

    // 保存文件到手机下载目录
    String savePath;
    try {
      final dir = await getDownloadsDirectory();
      if (dir == null) {
        final docDir = await getApplicationDocumentsDirectory();
        savePath = '${docDir.path}/AiChat导出';
      } else {
        savePath = dir.path;
      }
    } catch (_) {
      final docDir = await getApplicationDocumentsDirectory();
      savePath = '${docDir.path}/AiChat导出';
    }

    try {
      final now = DateTime.now();
      final fileName =
          '${widget.characterName}_聊天记录_${now.month}${now.day}_${now.hour}${now.minute}${now.second}.md';
      final file = File('$savePath/$fileName');
      await file.writeAsString(sb.toString());

      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('导出成功'),
          content: Text(
            '已将 ${messages.length} 条聊天记录保存为 Markdown 文件：\n\n${file.path}',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('导出失败'),
          content: Text('保存文件时出错：$e'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  String _formatDateTime(DateTime time) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final isToday = time.year == now.year &&
        time.month == now.month &&
        time.day == now.day;
    final timeStr = '${two(time.hour)}:${two(time.minute)}';
    if (isToday) return '今天 $timeStr';
    return '${time.month}月${time.day}日 $timeStr';
  }

  /// 长按气泡：弹出灰色面板（复制 / 引用 / 撤回-仅我方）
  void _showBubbleMenu(Message message) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _menuButton(ctx, CupertinoIcons.doc_on_doc, '复制', () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: message.content));
            }),
            _menuButton(ctx, CupertinoIcons.quote_bubble, '引用', () {
              Navigator.pop(ctx);
              setState(() {
                _quoteMessage = message;
              });
            }),
            if (message.isFromUser)
              _menuButton(
                ctx,
                CupertinoIcons.arrow_counterclockwise,
                '撤回',
                () {
                  Navigator.pop(ctx);
                  _withdrawMessage(message);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _menuButton(
    BuildContext ctx,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: context.textPrimaryColor),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: context.textPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 撤回消息（仅我方）：终止 AI 思考并删除消息
  void _withdrawMessage(Message message) {
    context
        .read<ChatProvider>()
        .withdrawMessage(widget.conversationId, message.id);
    // 若撤回的是被引用消息，清空引用
    if (_quoteMessage?.id == message.id) {
      setState(() {
        _quoteMessage = null;
      });
    }
  }

  /// 发送消息（携带引用）
  void _handleSend(String content) {
    final characterProvider = context.read<CharacterProvider>();
    final character = characterProvider.characters
        .where((c) => c.name == widget.characterName)
        .firstOrNull;

    // 读取聊天设置：上下文条数 + 使用的模型
    final chatSettings = context.read<ChatSettingsProvider>();
    final api = context.read<ApiProvider>();
    final model = api.getModelById(chatSettings.selectedModelId);

    final quote = _quoteMessage;
    context.read<ChatProvider>().sendMessage(
          conversationId: widget.conversationId,
          content: content,
          characterName: widget.characterName,
          characterSystemPrompt: character?.systemPrompt ?? '',
          modelName: model?.displayName ?? '',
          contextCount: chatSettings.contextCount,
          quoteContent: quote?.content ?? '',
          quoteSender: quote == null
              ? ''
              : (quote.isFromUser ? '我' : widget.characterName),
        );
    // 发送后清空引用
    if (_quoteMessage != null) {
      setState(() {
        _quoteMessage = null;
      });
    }
  }

  /// 取消引用
  void _clearQuote() {
    setState(() {
      _quoteMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.characterName),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _showMoreActions(context),
          child: const Icon(CupertinoIcons.ellipsis),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                final messages =
                    chatProvider.getMessages(widget.conversationId);

                // 双方头像（base64）
                final userAvatar =
                    context.read<AuthProvider>().user?.avatar ?? '';
                String characterAvatar = widget.characterAvatar;
                final conversation = chatProvider.conversations
                    .where((c) => c.id == widget.conversationId)
                    .firstOrNull;
                if (conversation != null) {
                  final character = context
                      .read<CharacterProvider>()
                      .getCharacterById(conversation.characterId);
                  if (character != null && character.avatar.isNotEmpty) {
                    characterAvatar = character.avatar;
                  }
                }

                if (messages.isEmpty) {
                  return ColoredBox(
                    color: context.chatBgColor,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.person_2_fill,
                            size: 48,
                            color: context.textSecondaryColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '和 ${widget.characterName} 开始聊天吧',
                            style: TextStyle(
                              fontSize: 16,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                return Container(
                  color: context.chatBgColor,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return ChatBubble(
                        message: messages[index],
                        userAvatar: userAvatar,
                        characterAvatar: characterAvatar,
                        onLongPress: () => _showBubbleMenu(messages[index]),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          Consumer<ChatProvider>(
            builder: (context, chatProvider, _) {
              if (chatProvider.isLoading) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: context.navBarColor,
                  child: Row(
                    children: [
                      const CupertinoActivityIndicator(),
                      const SizedBox(width: 10),
                      Text(
                        '${widget.characterName} 正在输入...',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // 引用条（设置了引用时显示在输入框上方）
          if (_quoteMessage != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              color: context.navBarColor,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.listBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _quoteMessage!.isFromUser
                                ? '引用 我'
                                : '引用 ${widget.characterName}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.accentColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _quoteMessage!.content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _clearQuote,
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 18,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          MessageInput(
            onSend: _handleSend,
          ),
        ],
      ),
    );
  }
}
