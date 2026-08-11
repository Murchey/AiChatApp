import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../services/llm_service.dart';
import '../services/prompt_builder.dart';
import 'api_provider.dart';

class ChatProvider extends ChangeNotifier {
  static const _conversationsKey = 'chat_conversations_v1';
  static const _messagesKey = 'chat_messages_v1';

  final Map<String, List<Message>> _messagesMap = {};
  final List<Conversation> _conversations = [];
  String? _lastError; // 最近一次 AI 请求失败的错误提示（界面展示用）

  List<Conversation> get conversations => _conversations;
  String? get lastError => _lastError;

  /// 清除错误提示（用户点击关闭后调用）
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

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

  /// 发送文本消息：仅将用户消息入库并持久化。
  ///
  /// 不自动触发模型回复——由用户在输入框右侧点击"对号"按钮后手动触发角色回复。
  Future<void> sendMessage({
    required String conversationId,
    required String content,
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
    _lastError = null;
    notifyListeners();
    await _persist();
  }

  /// 生成"角色主动发消息/回复"的消息列表。
  ///
  /// 组装阶段：调用 [PromptBuilder] 拼接 System Prompt（含人设/用户资料/时间/输出规则），
  /// 生成阶段：调用 [LLMService] 请求模型并容错解析 JSON 数组。
  /// [replyToUser] 为 true 时模型针对用户最近的消息回复（对号按钮触发）。
  /// [historyMessages] 未传时自动从当前会话取最近 [contextCount] 条文本消息，
  /// 使模型知道用户说了什么，从而分多条回复。
  /// API 层失败时设置 [_lastError] 并返回空列表；解析兜底消息由 LLMService 处理。
  Future<List<String>> generateProactiveMessages({
    required String conversationId,
    required ApiModel model,
    required String characterName,
    required String characterSystemPrompt,
    required String customPersona,
    required String userRelationship,
    required String userNickname,
    bool replyToUser = false,
    List<Map<String, String>>? historyMessages,
    int contextCount = 10,
  }) async {
    final prompt = PromptBuilder.buildSystemPrompt(
      baseSystemPrompt: characterSystemPrompt,
      characterName: characterName,
      customPersona: customPersona,
      userNickname: userNickname,
      userRelationship: userRelationship,
      currentTime: DateTime.now(),
      replyToUser: replyToUser,
    );
    try {
      return await LLMService.generateMessages(
        model: model,
        systemPrompt: prompt,
        historyMessages:
            historyMessages ?? _buildHistory(conversationId, contextCount),
        outputInstruction: PromptBuilder.buildOutputInstruction(
          characterName: characterName,
          replyToUser: replyToUser,
        ),
      );
    } on LLMException catch (e) {
      _lastError = e.message;
      return const [];
    } catch (e) {
      _lastError = LLMService.describeException(e);
      return const [];
    }
  }

  /// 从会话记录中取最近 [contextCount] 条文本消息作为对话历史
  List<Map<String, String>> _buildHistory(
      String conversationId, int contextCount) {
    final history = _messagesMap[conversationId] ?? [];
    final start =
        history.length > contextCount ? history.length - contextCount : 0;
    final result = <Map<String, String>>[];
    for (int i = start; i < history.length; i++) {
      final m = history[i];
      if (m.type != MessageType.text) continue; // 图片/文件消息不入上下文
      result.add({
        'role': m.isFromUser ? 'user' : 'assistant',
        'content': m.content,
      });
    }
    return result;
  }

  /// 将一条角色主动消息加入会话并持久化（渲染阶段逐条调用）
  void addProactiveMessage(String conversationId, String content) {
    if (content.trim().isEmpty) return;
    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: content,
      sender: MessageSender.character,
    ));
    _updateConversationLastMessage(conversationId, content);
    notifyListeners();
    _persist();
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

  /// 撤回我方消息：删除消息
  void withdrawMessage(String conversationId, String messageId) {
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

  void deleteConversation(String conversationId) {
    _conversations.removeWhere((c) => c.id == conversationId);
    _messagesMap.remove(conversationId);
    notifyListeners();
    _persist();
  }

  /// 清空当前会话的全部消息（保留会话本身）。
  /// 再次打开该聊天不会显示任何记录，AI 也不会继承此前的上下文。
  /// 消息数据会被完全抹除（存储中不再保留该会话的任何消息）。
  void clearMessages(String conversationId) {
    _messagesMap.remove(conversationId);
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(
        lastMessage: '',
        lastMessageTime: DateTime.now(),
      );
    }
    notifyListeners();
    _persist();
  }

  /// 同步角色的显示名称（备注/昵称）到其所有会话，用于首页列表与聊天页标题实时更新
  void updateCharacterDisplayName(String characterId, String displayName) {
    var changed = false;
    for (int i = 0; i < _conversations.length; i++) {
      if (_conversations[i].characterId == characterId &&
          _conversations[i].characterName != displayName) {
        _conversations[i] =
            _conversations[i].copyWith(characterName: displayName);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _persist();
    }
  }
}
