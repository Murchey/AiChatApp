import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/conversation.dart';

class ChatProvider extends ChangeNotifier {
  static const _conversationsKey = 'chat_conversations_v1';
  static const _messagesKey = 'chat_messages_v1';

  final Map<String, List<Message>> _messagesMap = {};
  final List<Conversation> _conversations = [];
  bool _isLoading = false;
  bool _cancelGeneration = false; // 撤回时用于终止 AI 回复思考

  List<Conversation> get conversations => _conversations;
  bool get isLoading => _isLoading;

  List<Message> getMessages(String conversationId) {
    return _messagesMap[conversationId] ?? [];
  }

  /// 从本地存储加载会话与聊天记录（持久化）
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final convStr = prefs.getString(_conversationsKey);
      if (convStr != null) {
        final list = jsonDecode(convStr) as List<dynamic>;
        _conversations
          ..clear()
          ..addAll(list.map((e) =>
              Conversation.fromJson(e as Map<String, dynamic>)));
      }
    } catch (_) {}
    try {
      final msgStr = prefs.getString(_messagesKey);
      if (msgStr != null) {
        final map = jsonDecode(msgStr) as Map<String, dynamic>;
        _messagesMap.clear();
        map.forEach((convId, messages) {
          _messagesMap[convId] = (messages as List<dynamic>)
              .map((e) => Message.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {}
    notifyListeners();
  }

  /// 保存会话与聊天记录到本地（持久化）
  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _conversationsKey,
      jsonEncode(_conversations.map((c) => c.toJson()).toList()),
    );
    await prefs.setString(
      _messagesKey,
      jsonEncode(
        _messagesMap.map(
          (key, value) => MapEntry(
            key,
            value.map((m) => m.toJson()).toList(),
          ),
        ),
      ),
    );
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
      _persist();
      return conversation;
    }
  }

  Future<void> sendMessage({
    required String conversationId,
    required String content,
    required String characterName,
    String characterSystemPrompt = '',
    String modelName = '',
    int contextCount = 10,
    String quoteContent = '',
    String quoteSender = '',
  }) async {
    final userMessage = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: content,
      sender: MessageSender.user,
      quoteContent: quoteContent,
      quoteSender: quoteSender,
    );

    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(userMessage);
    _updateConversationLastMessage(conversationId, content);
    notifyListeners();

    // TODO: 调用AI API获取回复，这里先用模拟回复
    _isLoading = true;
    _cancelGeneration = false;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));

    // 撤回已终止 AI 思考：不生成回复
    if (_cancelGeneration) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    // 构建上下文：取最近 contextCount 条消息（撤回后自动排除已撤回消息）
    final history = _messagesMap[conversationId] ?? [];
    final contextMessages = history.length > contextCount
        ? history.sublist(history.length - contextCount)
        : history;

    final aiMessage = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: _generateMockReply(
        characterName,
        content,
        modelName: modelName,
        contextCount: contextMessages.length,
      ),
      sender: MessageSender.character,
    );

    _messagesMap[conversationId]!.add(aiMessage);
    _updateConversationLastMessage(conversationId, aiMessage.content);

    _isLoading = false;
    notifyListeners();
    await _persist();
  }

  /// 通用删除单条消息（用于重新回复等场景）
  void deleteMessage(String conversationId, String messageId) {
    final messages = _messagesMap[conversationId];
    if (messages == null) return;
    messages.removeWhere((m) => m.id == messageId);
    if (messages.isNotEmpty) {
      _updateConversationLastMessage(conversationId, messages.last.content);
    } else {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        _conversations[index] = _conversations[index].copyWith(
          lastMessage: '',
          lastMessageTime: DateTime.now(),
        );
      }
    }
    notifyListeners();
    _persist();
  }

  /// 撤回我方消息：删除消息，并终止正在进行的 AI 回复思考
  void withdrawMessage(String conversationId, String messageId) {
    final messages = _messagesMap[conversationId];
    if (messages == null) return;

    // 终止 AI 回复思考
    _cancelGeneration = true;
    _isLoading = false;

    messages.removeWhere((m) => m.id == messageId);
    if (messages.isNotEmpty) {
      _updateConversationLastMessage(conversationId, messages.last.content);
    } else {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        _conversations[index] = _conversations[index].copyWith(
          lastMessage: '',
          lastMessageTime: DateTime.now(),
        );
      }
    }
    notifyListeners();
    _persist();
  }

  /// 发送图片消息
  Future<void> sendImageMessage({
    required String conversationId,
    required String imagePath,
    required String characterName,
    String modelName = '',
    int contextCount = 10,
  }) async {
    final userMessage = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: imagePath,
      type: MessageType.image,
      sender: MessageSender.user,
    );

    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(userMessage);
    _updateConversationLastMessage(conversationId, '[图片]');
    notifyListeners();
    await _persist();
  }

  /// 发送文件消息（file path）
  Future<void> sendFileMessage({
    required String conversationId,
    required String filePath,
    required String fileName,
  }) async {
    final userMessage = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: filePath,
      type: MessageType.file,
      sender: MessageSender.user,
    );

    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(userMessage);
    _updateConversationLastMessage(conversationId, '[文件] $fileName');
    notifyListeners();
    await _persist();
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

  String _generateMockReply(
    String characterName,
    String userMessage, {
    String modelName = '',
    int contextCount = 10,
  }) {
    // 模拟AI回复，实际应调用后端API
    final preview = userMessage.length > 20
        ? '${userMessage.substring(0, 20)}...'
        : userMessage;
    final modelText = modelName.isNotEmpty ? '模型: $modelName' : '模型: 未选择';
    return '[$characterName] 收到了你的消息："$preview"。\n'
        '（上下文 $contextCount 条 | $modelText）\n'
        '这是一个模拟回复，接入AI API后会得到真正的角色扮演回复。';
  }

  void deleteConversation(String conversationId) {
    _conversations.removeWhere((c) => c.id == conversationId);
    _messagesMap.remove(conversationId);
    notifyListeners();
    _persist();
  }
}
