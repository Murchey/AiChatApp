import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/conversation.dart';

class ChatProvider extends ChangeNotifier {
  final Map<String, List<Message>> _messagesMap = {};
  final List<Conversation> _conversations = [];
  bool _isLoading = false;

  List<Conversation> get conversations => _conversations;
  bool get isLoading => _isLoading;

  List<Message> getMessages(String conversationId) {
    return _messagesMap[conversationId] ?? [];
  }

  void loadConversations() {
    // TODO: 从API获取会话列表，目前模拟数据在创建会话时动态添加
    notifyListeners();
  }

  Conversation getOrCreateConversation({
    required String characterId,
    required String characterName,
    String characterAvatar = '',
  }) {
    try {
      return _conversations.firstWhere((c) => c.characterId == characterId);
    } catch (_) {
      final conversation = Conversation(
        id: const Uuid().v4(),
        characterId: characterId,
        characterName: characterName,
        characterAvatar: characterAvatar,
      );
      _conversations.insert(0, conversation);
      _messagesMap[conversation.id] = [];
      notifyListeners();
      return conversation;
    }
  }

  Future<void> sendMessage({
    required String conversationId,
    required String content,
    required String characterName,
    String characterSystemPrompt = '',
  }) async {
    final userMessage = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: content,
      sender: MessageSender.user,
    );

    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(userMessage);
    _updateConversationLastMessage(conversationId, content);
    notifyListeners();

    // TODO: 调用AI API获取回复，这里先用模拟回复
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));

    final aiMessage = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: _generateMockReply(characterName, content),
      sender: MessageSender.character,
    );

    _messagesMap[conversationId]!.add(aiMessage);
    _updateConversationLastMessage(conversationId, aiMessage.content);

    _isLoading = false;
    notifyListeners();
  }

  void _updateConversationLastMessage(String conversationId, String content) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(
        lastMessage: content,
        lastMessageTime: DateTime.now(),
      );
      final conv = _conversations.removeAt(index);
      _conversations.insert(0, conv);
    }
  }

  String _generateMockReply(String characterName, String userMessage) {
    // 模拟AI回复，实际应调用后端API
    final preview = userMessage.length > 20
        ? '${userMessage.substring(0, 20)}...'
        : userMessage;
    return '[$characterName] 收到了你的消息："$preview"。这是一个模拟回复，接入AI API后会得到真正的角色扮演回复。';
  }

  void deleteConversation(String conversationId) {
    _conversations.removeWhere((c) => c.id == conversationId);
    _messagesMap.remove(conversationId);
    notifyListeners();
  }
}
