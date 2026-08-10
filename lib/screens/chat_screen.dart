import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/chat_provider.dart';
import '../providers/character_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/message_input.dart';

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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.characterName),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {},
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
                      return ChatBubble(message: messages[index]);
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
          MessageInput(
            onSend: (content) {
              final characterProvider = context.read<CharacterProvider>();
              final character = characterProvider.characters
                  .where((c) => c.name == widget.characterName)
                  .firstOrNull;

              context.read<ChatProvider>().sendMessage(
                    conversationId: widget.conversationId,
                    content: content,
                    characterName: widget.characterName,
                    characterSystemPrompt: character?.systemPrompt ?? '',
                  );
            },
          ),
        ],
      ),
    );
  }
}
