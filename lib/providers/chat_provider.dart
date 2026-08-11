import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  bool _isLoading = false;
  bool _cancelGeneration = false; // 撤回时用于终止 AI 回复思考
  String? _lastError; // 最近一次 AI 请求失败的错误提示（界面展示用）

  List<Conversation> get conversations => _conversations;
  bool get isLoading => _isLoading;
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

  Future<void> sendMessage({
    required String conversationId,
    required String content,
    required String characterName,
    String characterSystemPrompt = '',
    String userProfile = '', // 用户个人信息（昵称/性别/地区/签名），随上下文发送给 AI
    ApiModel? model, // 选中的模型配置；为 null 时使用模拟回复
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
    _lastError = null;
    notifyListeners();
    await _persist(); // 先持久化用户消息，避免请求期间进程被杀丢失

    _isLoading = true;
    _cancelGeneration = false;
    notifyListeners();

    // 回复内容：未配置模型走模拟回复；已配置则调用真实 AI API（OpenAI 兼容格式）
    String? replyContent;
    if (model == null) {
      await Future.delayed(const Duration(seconds: 1));
      if (!_cancelGeneration) {
        final history = _messagesMap[conversationId] ?? [];
        final contextMessages = history.length > contextCount
            ? history.sublist(history.length - contextCount)
            : history;
        replyContent = _generateMockReply(
          characterName,
          content,
          contextCount: contextMessages.length,
        );
      }
    } else {
      replyContent = await _callChatCompletion(
        conversationId: conversationId,
        model: model,
        characterSystemPrompt: characterSystemPrompt,
        userProfile: userProfile,
        contextCount: contextCount,
      );
    }

    // 撤回已终止 AI 思考：不生成回复
    if (_cancelGeneration) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = false;
    if (replyContent != null && replyContent.isNotEmpty) {
      final aiMessage = Message(
        id: const Uuid().v4(),
        conversationId: conversationId,
        content: replyContent,
        sender: MessageSender.character,
      );
      _messagesMap[conversationId]!.add(aiMessage);
      _updateConversationLastMessage(conversationId, aiMessage.content);
    }
    notifyListeners();
    await _persist();
  }

  /// 调用对话补全 API（DeepSeek 官方接口，OpenAI 兼容格式）。
  /// 返回 AI 回复文本；失败时设置 [_lastError] 并返回 null。
  Future<String?> _callChatCompletion({
    required String conversationId,
    required ApiModel model,
    required String characterSystemPrompt,
    required String userProfile,
    required int contextCount,
  }) async {
    if (model.modelName.isEmpty) {
      _lastError = '所选模型未填写模型名称，请到「API 设置」中检查';
      return null;
    }
    if (model.apiKey.isEmpty) {
      _lastError = '所选模型未配置 API Key，请到「API 设置」中填写';
      return null;
    }

    // 构建消息列表：system（角色提示词 + 用户资料）+ 最近 contextCount 条文本消息
    final messages = <Map<String, String>>[];
    if (characterSystemPrompt.trim().isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': characterSystemPrompt.trim(),
      });
    }
    if (userProfile.trim().isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': userProfile.trim(),
      });
    }
    final history = _messagesMap[conversationId] ?? [];
    final start =
        history.length > contextCount ? history.length - contextCount : 0;
    for (int i = start; i < history.length; i++) {
      final m = history[i];
      if (m.type != MessageType.text) continue; // 图片/文件消息不入上下文
      messages.add({
        'role': m.isFromUser ? 'user' : 'assistant',
        'content': m.content,
      });
    }

    // 拼接请求地址：baseUrl 留空时使用 DeepSeek 官方地址，兼容结尾 /v1 或 /chat/completions
    var base = model.baseUrl.trim().isNotEmpty
        ? model.baseUrl.trim()
        : 'https://api.deepseek.com';
    base = base.replaceAll(RegExp(r'/+$'), '');
    final url =
        base.endsWith('/chat/completions') ? base : '$base/chat/completions';

    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      request.headers
          .set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer ${model.apiKey}');
      request.add(utf8.encode(jsonEncode({
        'model': model.modelName,
        'messages': messages,
        'stream': false,
        'max_tokens': 2048,
        'temperature': 1.0,
      })));

      final response =
          await request.close().timeout(const Duration(seconds: 60));
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final choices = decoded['choices'] as List<dynamic>? ?? const [];
        if (choices.isEmpty) {
          _lastError = 'API 返回异常：未包含任何回复内容';
          return null;
        }
        final message =
            (choices.first as Map<String, dynamic>)['message']
                as Map<String, dynamic>?;
        final content = message?['content'] as String? ?? '';
        if (content.trim().isEmpty) {
          _lastError = 'API 返回内容为空';
          return null;
        }
        return content;
      }

      // 非 200：尽量解析官方错误信息 {"error":{"message":...}}
      var errorMessage = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final err = decoded['error'] as Map<String, dynamic>?;
        final msg = err?['message'];
        if (msg != null) errorMessage = '$msg';
      } catch (_) {}
      _lastError = 'API 请求失败：$errorMessage';
      return null;
    } catch (e) {
      if (e is TimeoutException) {
        _lastError = '请求超时，请检查网络后重试';
      } else if (e is SocketException || e is HandshakeException) {
        _lastError = '网络连接失败，请检查网络与 API 地址';
      } else {
        _lastError = '请求出错：$e';
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 生成"角色主动发消息"的消息列表。
  ///
  /// 组装阶段：调用 [PromptBuilder] 拼接 System Prompt（含人设/用户资料/时间/输出规则），
  /// 生成阶段：调用 [LLMService] 请求模型并容错解析 JSON 数组。
  /// API 层失败时设置 [_lastError] 并返回空列表；解析兜底消息由 LLMService 处理。
  Future<List<String>> generateProactiveMessages({
    required String conversationId,
    required ApiModel model,
    required String characterName,
    required String characterSystemPrompt,
    required String customPersona,
    required String userRelationship,
    required String userNickname,
  }) async {
    final prompt = PromptBuilder.buildSystemPrompt(
      baseSystemPrompt: characterSystemPrompt,
      characterName: characterName,
      customPersona: customPersona,
      userNickname: userNickname,
      userRelationship: userRelationship,
      currentTime: DateTime.now(),
    );
    try {
      return await LLMService.generateMessages(
        model: model,
        systemPrompt: prompt,
      );
    } on LLMException catch (e) {
      _lastError = e.message;
      return const [];
    } catch (e) {
      _lastError = LLMService.describeException(e);
      return const [];
    }
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
    int contextCount = 10,
  }) {
    // 模拟AI回复，实际应调用后端API
    final preview = userMessage.length > 20
        ? '${userMessage.substring(0, 20)}...'
        : userMessage;
    return '[$characterName] 收到了你的消息："$preview"。\n'
        '（上下文 $contextCount 条 | 未配置模型，当前为模拟回复）\n'
        '如需真实 AI 回复，请到「我 → API 设置」中添加模型，并在「聊天设置」中选择。';
  }

  void deleteConversation(String conversationId) {
    _conversations.removeWhere((c) => c.id == conversationId);
    _messagesMap.remove(conversationId);
    notifyListeners();
    _persist();
  }

  /// 清空当前会话的全部消息（保留会话本身），并终止进行中的 AI 回复。
  /// 再次打开该聊天不会显示任何记录，AI 也不会继承此前的上下文。
  /// 消息数据会被完全抹除（存储中不再保留该会话的任何消息）。
  void clearMessages(String conversationId) {
    _cancelGeneration = true;
    _isLoading = false;
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
