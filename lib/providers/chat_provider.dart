import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../services/llm_service.dart';
import '../services/notification_service.dart';
import '../services/prompt_builder.dart';
import '../services/widget_sync_service.dart';
import '../services/sticker_query_protocol.dart';
import '../services/sticker_search_service.dart';
import 'api_provider.dart';
import 'token_usage_provider.dart';

class ChatProvider extends ChangeNotifier {
  static const _conversationsKey = 'chat_conversations_v1';
  static const _messagesKey = 'chat_messages_v1';
  static const _contextTokensKey = 'chat_context_tokens_v1'; // 各会话上下文 token 累计值
  static const _systemTokensKey =
      'chat_system_tokens_v1'; // 各会话系统提示词 + 输出指令 token（持久化，重启恢复）
  static const _roleplayChoicesKey = 'chat_roleplay_choices_v1';

  // 会话压缩参数
  static const int kKeepRecentMessages = 20; // 压缩时保留的最近消息条数
  // 每条消息的 JSON 结构开销（role/content 键名、括号、引号等约占 4~5 token，
  // 计入本地估算，贴近服务端按整个 JSON 计费的真实情况）
  static const int kPerMessageJsonTokens = 5;

  final Map<String, List<Message>> _messagesMap = {};
  final List<Conversation> _conversations = [];
  String? _lastError; // 最近一次 AI 请求失败的错误提示（界面展示用）
  String? _activeConversationId; // 当前打开的聊天会话（其内新增角色消息不记未读）
  String? _replyingConversationId; // 正在生成/逐条渲染回复的会话（防止重复触发）
  Future<List<String>>? _runningReply; // 进行中的回复流程（重复触发时复用）
  final Map<String, int> _contextTokens =
      {}; // 会话 → 上下文 token 用量（输入侧，API usage 优先）
  final Map<String, int> _systemTokens =
      {}; // 会话 → 系统提示词 + 输出指令 token（内存态，供乐观更新）
  final Map<String, List<String>> _roleplayChoices = {};

  /// 会话列表：置顶会话排最前，其余按最近消息时间倒序
  List<Conversation> get conversations {
    final list = List.of(_conversations);
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.lastMessageTime.compareTo(a.lastMessageTime);
    });
    return list;
  }

  String? get lastError => _lastError;

  /// 语C候选行动按会话保存，重新进入聊天时可继续使用。
  List<String> roleplayChoicesFor(String conversationId) =>
      List.unmodifiable(_roleplayChoices[conversationId] ?? const []);

  Future<void> setRoleplayChoices(
      String conversationId, List<String> choices) async {
    final clean = choices
        .map((choice) => choice.trim())
        .where((choice) => choice.isNotEmpty)
        .take(4)
        .toList();
    if (clean.isEmpty) {
      _roleplayChoices.remove(conversationId);
    } else {
      _roleplayChoices[conversationId] = clean;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _roleplayChoicesKey,
      jsonEncode(_roleplayChoices),
    );
  }

  Future<void> _clearRoleplayChoicesForNextTurn(String conversationId) async {
    if (!_roleplayChoices.containsKey(conversationId)) return;
    await setRoleplayChoices(conversationId, const []);
  }

  /// 设置/取消会话置顶（置顶后移到会话列表最前）
  void setPinned(String conversationId, bool pinned) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1 || _conversations[index].pinned == pinned) return;
    _conversations[index] = _conversations[index].copyWith(pinned: pinned);
    notifyListeners();
    _persist();
  }

  /// 是否正在为该会话生成回复（聊天标题据此显示"对方正在输入……"）
  bool isReplying(String conversationId) =>
      _replyingConversationId == conversationId;

  /// 聊天界面打开时调用：记录当前会话并清除其未读
  void markConversationActive(String conversationId) {
    _activeConversationId = conversationId;
    debugPrint('[ChatProvider] 会话打开 active=$conversationId');
    _clearUnread(conversationId);
  }

  /// 聊天界面销毁时调用：该会话新增消息恢复计入未读
  void markConversationInactive(String conversationId) {
    if (_activeConversationId == conversationId) {
      _activeConversationId = null;
      debugPrint('[ChatProvider] 会话退出 active=null');
    }
  }

  void _clearUnread(String conversationId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1 || _conversations[index].unreadCount == 0) return;
    _conversations[index] = _conversations[index].copyWith(unreadCount: 0);
    notifyListeners();
    _persist();
  }

  /// 新增角色消息时：若用户不在该会话页面则未读 +1（不单独 notify，由调用方统一触发）
  int _increaseUnread(String conversationId) {
    if (_activeConversationId == conversationId) return 0;
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return 0;
    final count = _conversations[index].unreadCount + 1;
    _conversations[index] = _conversations[index].copyWith(unreadCount: count);
    debugPrint(
        '[ChatProvider] 未读+1 $conversationId → $count（active=$_activeConversationId）');
    return count;
  }

  /// 清除错误提示（用户点击关闭后调用）
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  List<Message> getMessages(String conversationId) {
    return _messagesMap[conversationId] ?? [];
  }

  /// 聊天记录搜索：在所有会话的文本消息中查找包含 [keyword] 的消息。
  /// 返回按会话分组的匹配结果（会话内保持消息时间升序），
  /// 会话按「最近一条匹配消息」的时间降序排列（更新鲜的排前面）。
  /// 图片/文件消息（正文为文件路径）与压缩摘要消息不参与匹配；
  /// 合并转发卡片展开其内部文本参与匹配。
  List<MapEntry<Conversation, List<Message>>> searchMessages(String keyword) {
    final kw = keyword.trim().toLowerCase();
    if (kw.isEmpty) return const [];
    final groups = <MapEntry<Conversation, List<Message>>>[];
    for (final c in _conversations) {
      final messages = _messagesMap[c.id] ?? const <Message>[];
      final matches = <Message>[];
      for (final m in messages) {
        if (m.isCompressionSummary) continue;
        if (m.isForwardCard) {
          final hit = m.forwardedItems.any(
            (f) => f.type == 'text' && f.content.toLowerCase().contains(kw),
          );
          if (hit) matches.add(m);
        } else if (m.type == MessageType.text &&
            m.content.toLowerCase().contains(kw)) {
          matches.add(m);
        }
      }
      if (matches.isNotEmpty) {
        groups.add(MapEntry(c, matches));
      }
    }
    groups.sort(
      (a, b) => b.value.last.createdAt.compareTo(a.value.last.createdAt),
    );
    return groups;
  }

  /// 获取某角色的最近聊天记录（按上下文条数），供朋友圈评论回复等场景使用。
  ///
  /// 返回 `[{'role': 'user'|'assistant', 'content': ...}, ...]`；
  /// [contextCount] <= 0 表示无限制（取摘要起全部历史）。
  /// 该角色没有会话记录时返回空列表；不会新建会话。
  List<Map<String, String>> getRecentHistoryForCharacter(
    String characterId,
    int contextCount,
  ) {
    for (final c in _conversations) {
      if (c.characterId == characterId) {
        return _buildHistory(c.id, contextCount);
      }
    }
    return const [];
  }

  /// 会话头像快照（统计页记忆用；会话不存在时返回空）
  String _conversationAvatar(String conversationId) {
    for (final c in _conversations) {
      if (c.id == conversationId) return c.characterAvatar;
    }
    return '';
  }

  /// 获取某角色最后一条消息的时间。
  /// 没有会话记录时返回 null。
  DateTime? getLastMessageTimeForCharacter(String characterId) {
    for (final c in _conversations) {
      if (c.characterId == characterId) {
        return c.lastMessageTime;
      }
    }
    return null;
  }

  /// 从本地存储加载会话与聊天记录（持久化）。
  /// 全部 JSON 反序列化与上下文 token 重算都在后台 isolate 中执行，
  /// 避免大量聊天记录在主线程解码拖慢启动。
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _RawStore(
      conversationsJson: prefs.getString(_conversationsKey),
      messagesJson: prefs.getString(_messagesKey),
      contextTokensJson: prefs.getString(_contextTokensKey),
      systemTokensJson: prefs.getString(_systemTokensKey),
    );
    _DecodedStore? decoded;
    try {
      decoded = await compute(_decodePersistStore, raw);
    } catch (e) {
      debugPrint('[ChatProvider] 加载本地数据失败，按空数据启动: $e');
    }
    if (decoded != null) {
      _conversations
        ..clear()
        ..addAll(decoded.conversations);
      _messagesMap
        ..clear()
        ..addAll(decoded.messages);
      _contextTokens
        ..clear()
        ..addAll(decoded.contextTokens);
      _systemTokens
        ..clear()
        ..addAll(decoded.systemTokens);
    }
    try {
      final rawChoices = prefs.getString(_roleplayChoicesKey);
      if (rawChoices != null && rawChoices.isNotEmpty) {
        final decodedChoices = jsonDecode(rawChoices) as Map<String, dynamic>;
        _roleplayChoices
          ..clear()
          ..addAll(decodedChoices.map(
            (id, values) => MapEntry(id, List<String>.from(values as List)),
          ));
      }
    } catch (e) {
      debugPrint('[ChatProvider] 语C候选行动加载失败: $e');
      _roleplayChoices.clear();
    }
    // 加载完成后通知监听者重建界面：
    // 否则首页在 init 完成前先渲染一次（会话为空 → 显示"暂无会话"），
    // 数据就绪后没有重建通知，列表会一直停留在空状态。
    notifyListeners();
  }

  /// 保存会话与聊天记录到本地（持久化）
  ///
  /// JSON 序列化在后台 isolate 中执行，避免长会话（上千条消息、多会话）时
  /// 每次入库都同步编码全量数据阻塞主线程——这是发送/渲染卡顿的直接原因。
  /// 采用「单飞 + 脏标记」：写入进行中再触发时只标记待写，由当前写入收尾时
  /// 自动补写，AI 逐条渲染期间的高频调用会合并为少量实际写盘，
  /// 且最后一次写入始终包含最新数据。
  bool _persistRunning = false;
  bool _persistDirty = false;

  Future<void> _persist() async {
    if (_persistRunning) {
      _persistDirty = true;
      return;
    }
    _persistRunning = true;
    try {
      do {
        _persistDirty = false;
        // 浅拷贝快照（指针级，开销小），确保后台序列化期间数据一致
        final snapshot = _PersistSnapshot(
          conversations: List.of(_conversations),
          messages: _messagesMap.map(
            (key, value) => MapEntry(key, List.of(value)),
          ),
          contextTokens: Map.of(_contextTokens),
          systemTokens: Map.of(_systemTokens),
        );
        final encoded = await compute(_encodePersistSnapshot, snapshot);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_conversationsKey, encoded['conversations']!);
        await prefs.setString(_messagesKey, encoded['messages']!);
        await prefs.setString(_contextTokensKey, encoded['contextTokens']!);
        await prefs.setString(_systemTokensKey, encoded['systemTokens']!);
      } while (_persistDirty);
    } catch (e) {
      // 持久化失败不阻塞主流程（多为平台通道/磁盘异常），下次变更会再次尝试
      debugPrint('[ChatProvider] 持久化失败: $e');
    } finally {
      _persistRunning = false;
      // 同步到小组件（异步，不阻塞）
      _syncToWidget();
    }
  }

  /// 同步会话数据到小组件
  void _syncToWidget() {
    Future.microtask(() async {
      try {
        final convList = _conversations
            .map((conv) => {
                  'id': conv.id,
                  'character_id': conv.characterId,
                  'character_name': conv.characterName,
                  'last_message': conv.lastMessage,
                  'last_message_time':
                      conv.lastMessageTime.millisecondsSinceEpoch,
                  'unread_count': conv.unreadCount,
                  'pinned': conv.pinned,
                })
            .toList();

        await WidgetSyncService.syncConversations(convList);
      } catch (e) {
        debugPrint('[ChatProvider] Widget sync failed: $e');
      }
    });
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
    await _clearRoleplayChoicesForNextTurn(conversationId);
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
    // 用户消息已经入库，直接按当前会话历史估算，避免把本条输入重复计入。
    // API 返回后会用真实 usage.prompt_tokens 校准输入 token。
    _contextTokens[conversationId] = _estimateSendInputBudget(conversationId);
    _lastError = null;
    notifyListeners();
    await _persist();
  }

  /// 添加用户主导的语C剧情行动/旁白，不自动触发角色回复。
  Future<void> addRoleplayNarration({
    required String conversationId,
    required String content,
  }) async {
    final text = content.trim();
    if (text.isEmpty) return;
    await _clearRoleplayChoicesForNextTurn(conversationId);
    final message = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: text,
      type: MessageType.narration,
      sender: MessageSender.user,
    );
    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(message);
    _updateConversationLastMessage(conversationId, '［剧情行动］$text');
    _contextTokens[conversationId] = _estimateSendInputBudget(conversationId);
    _lastError = null;
    notifyListeners();
    await _persist();
  }

  /// 发送主动问候消息：以角色身份发送一条消息到聊天中。
  Future<void> sendGreetingMessage({
    required String conversationId,
    required String characterId,
    required String content,
  }) async {
    final message = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: content,
      sender: MessageSender.character,
      senderCharacterId: characterId,
    );

    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(message);
    _updateConversationLastMessage(conversationId, content);
    _lastError = null;
    notifyListeners();
    await _persist();
  }

  /// 语C正文走 SSE 流式输出：先插入一条角色消息，再随着片段到达更新内容。
  /// 语C不解析 JSON，因此可安全逐段渲染同一条纯文本气泡。
  Future<List<String>> runRoleplayStream({
    required String conversationId,
    required ApiModel model,
    required String characterName,
    required String characterSystemPrompt,
    required String userRelationship,
    required String userNickname,
    required List<String> memoryPoints,
    required int contextCount,
    String progressionStyle = 'free',
    bool includeChoices = true,
  }) {
    if (_runningReply != null && _replyingConversationId == conversationId) {
      return _runningReply!;
    }
    _replyingConversationId = conversationId;
    notifyListeners();
    final future = _doRunRoleplayStream(
      conversationId: conversationId,
      model: model,
      characterName: characterName,
      characterSystemPrompt: characterSystemPrompt,
      userRelationship: userRelationship,
      userNickname: userNickname,
      memoryPoints: memoryPoints,
      contextCount: contextCount,
      progressionStyle: progressionStyle,
      includeChoices: includeChoices,
    );
    _runningReply = future;
    return future;
  }

  Future<List<String>> _doRunRoleplayStream({
    required String conversationId,
    required ApiModel model,
    required String characterName,
    required String characterSystemPrompt,
    required String userRelationship,
    required String userNickname,
    required List<String> memoryPoints,
    required int contextCount,
    required String progressionStyle,
    required bool includeChoices,
  }) async {
    final prompt = PromptBuilder.buildSystemPrompt(
      baseSystemPrompt: characterSystemPrompt,
      characterName: characterName,
      userNickname: userNickname,
      userRelationship: userRelationship,
      currentTime: DateTime.now(),
      replyToUser: true,
      memoryPoints: memoryPoints,
      roleplayProgressionStyle: progressionStyle,
      roleplayMode: true,
    );
    final instruction = PromptBuilder.buildOutputInstruction(
      characterName: characterName,
      replyToUser: true,
      roleplayMode: true,
      includeRoleplayChoices: includeChoices,
    );
    final history = _buildHistory(conversationId, contextCount);
    final systemPromptTokens =
        _estimateTextTokens(prompt) +
        _estimateTextTokens(instruction) +
        kPerMessageJsonTokens * 2;
    _systemTokens[conversationId] = systemPromptTokens;
    final message = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: '',
      sender: MessageSender.character,
    );
    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(message);
    notifyListeners();
    var content = '';
    var reasoning = '';
    ChatUsage streamUsage = const ChatUsage();
    final streamWatch = Stopwatch()..start();
    try {
      await for (final chunk in LLMService.streamCompletion(
        model: model,
        messages: [
          {'role': 'system', 'content': prompt},
          ...history,
          {'role': 'user', 'content': instruction},
        ],
      )) {
        content += chunk.content;
        reasoning += chunk.reasoning;
        if (!chunk.usage.isEmpty) streamUsage = chunk.usage;
        final index = _messagesMap[conversationId]!
            .indexWhere((item) => item.id == message.id);
        if (index >= 0) {
          _messagesMap[conversationId]![index] = message.copyWith(
            content: content,
            reasoningContent: reasoning,
          );
          notifyListeners();
        }
      }
      streamWatch.stop();
      final reply = LLMService.parseRoleplayReply(content);
      content = reply.content;
      if (reply.choices.isNotEmpty) {
        await setRoleplayChoices(conversationId, reply.choices);
      }
      final index = _messagesMap[conversationId]!
          .indexWhere((item) => item.id == message.id);
      if (index >= 0) {
        _messagesMap[conversationId]![index] = message.copyWith(
          content: content,
          reasoningContent: reasoning,
          reasoningDurationMs:
              reasoning.trim().isEmpty ? null : streamWatch.elapsedMilliseconds,
        );
        _persist();
      }
      _updateConversationLastMessage(conversationId, content);
      final promptTokens = streamUsage.promptTokens ??
          systemPromptTokens +
              history.fold<int>(
                0,
                (sum, item) =>
                    sum + _estimateTextTokens(item['content'] ?? '') +
                        kPerMessageJsonTokens,
              );
      // completion 已含思考；网关未给 reasoning_tokens 时按思考正文估算
      final reasoningTokens = streamUsage.reasoningTokens ??
          LLMService.estimateReasoningTokens(reasoning);
      final completionTokens = streamUsage.completionTokens ??
          _estimateTextTokens(content) + reasoningTokens;
      await TokenUsageProvider.instance.addUsage(
        conversationId,
        ChatUsage(
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: promptTokens + completionTokens,
          reasoningTokens: reasoningTokens,
        ),
        label: characterName,
        avatar: _conversationAvatar(conversationId),
      );
      // 进度条显示下一次请求可能携带的上下文，必须与 contextCount 和
      // _buildHistory 的消息转换规则保持一致。
      _contextTokens[conversationId] = _estimateRequestInputBudget(
        conversationId,
        contextCount: contextCount,
        systemTokens: systemPromptTokens,
      );
      await _persist();
      return content.isEmpty ? const [] : [content];
    } on LLMException catch (e) {
      _lastError = e.message;
      _messagesMap[conversationId]
          ?.removeWhere((item) => item.id == message.id);
      return const [];
    } catch (e) {
      _lastError = LLMService.describeException(e);
      _messagesMap[conversationId]
          ?.removeWhere((item) => item.id == message.id);
      return const [];
    } finally {
      _replyingConversationId = null;
      _runningReply = null;
      notifyListeners();
    }
  }

  /// 生成"角色主动发消息/回复"的消息列表。
  ///
  /// 组装阶段：调用 [PromptBuilder] 拼接 System Prompt（含人设/用户资料/时间/输出规则），
  /// 生成阶段：调用 [LLMService] 请求模型并容错解析 JSON 数组。
  /// [replyToUser] 为 true 时模型针对用户最近的消息回复（对号按钮触发）。
  /// [historyMessages] 未传时自动从当前会话取最近 [contextCount] 条文本消息，
  /// 使模型知道用户说了什么，从而分多条回复。
  /// [enableCompression] 开启且 [contextLength] 已知时，若历史估算 token 达到
  /// 模型上下文 [kCompressThreshold]，会先用 [compressModel] 压缩更早的历史消息。
  /// [activeStart]/[activeEnd] 为角色活跃时段（"HH:mm"），落在时段内时
  /// 角色不会主动道别/说晚安。
  /// API 层失败时设置 [_lastError] 并返回空结果；解析兜底消息由 LLMService 处理。
  Future<ProactiveResult> generateProactiveMessages({
    required String conversationId,
    required ApiModel model,
    required String characterName,
    required String characterSystemPrompt,
    required String userRelationship,
    required String userNickname,
    bool replyToUser = false,
    bool roleplayMode = false,
    String roleplayProgressionStyle = 'free',
    List<Map<String, Object>>? historyMessages,
    int contextCount = 10,
    ApiModel? compressModel,
    bool enableCompression = false,
    int contextLength = 8000,
    double compressThreshold = 0.7,
    String? imagePath, // 非空时以"图片消息"发给模型（OpenAI 视觉格式）
    String activeStart = '',
    String activeEnd = '',
    List<String> memoryPoints = const [], // 用户持久化的长期记忆点，拼入系统提示词
    String extraSystemContext = '', // 额外的记忆上下文（如角色记忆池），拼入系统提示词
  }) async {
    final now = DateTime.now();
    final prompt = PromptBuilder.buildSystemPrompt(
      baseSystemPrompt: characterSystemPrompt,
      characterName: characterName,
      userNickname: userNickname,
      userRelationship: userRelationship,
      currentTime: now,
      replyToUser: replyToUser,
      activeStart: roleplayMode ? '' : activeStart,
      activeEnd: roleplayMode ? '' : activeEnd,
      memoryPoints: memoryPoints,
      roleplayProgressionStyle: roleplayProgressionStyle,
      extraContext: roleplayMode ? '' : extraSystemContext,
      roleplayMode: roleplayMode,
    );
    final outputInstruction = PromptBuilder.buildOutputInstruction(
      characterName: characterName,
      replyToUser: replyToUser,
      currentTime: roleplayMode ? null : now,
      roleplayMode: roleplayMode,
      // 非流式语C会在正文完成后单独请求候选行动。正文请求不附带候选
      // 标记，避免模型生成后被解析器丢弃，既浪费输出 token 又造成统计偏差。
      includeRoleplayChoices: false,
    );
    // 记录本会话的系统提示词 + 输出指令 token，供发送消息时乐观更新进度条
    _systemTokens[conversationId] = _estimateTextTokens(prompt) +
        _estimateTextTokens(outputInstruction) +
        kPerMessageJsonTokens * 2;
    // 会话压缩：开启压缩且模型上下文已知时，先检查历史长度是否达到阈值。
    // 预算同时计入系统提示词与格式指令占用的 token——
    // 系统提示词越长，压缩越早触发，避免「提示词 + 历史」超过模型上下文上限
    if (enableCompression && compressModel != null && contextLength > 0) {
      await _maybeCompressConversation(
        conversationId: conversationId,
        compressModel: compressModel,
        contextLength: contextLength,
        threshold: compressThreshold,
        systemPromptTokens: _estimateTextTokens(prompt) +
            _estimateTextTokens(outputInstruction) +
            kPerMessageJsonTokens * 2, // 系统提示词与输出指令各是一条消息
        contextCount: contextCount,
      );
    }
    try {
      final history =
          historyMessages ?? _buildHistory(conversationId, contextCount);
      // 图片消息走 OpenAI 兼容视觉格式，让角色"看到"图片后回复
      if (imagePath != null && imagePath.isNotEmpty) {
        return await LLMService.generateVisionReply(
          model: model,
          systemPrompt: prompt,
          historyMessages: history,
          imagePath: imagePath,
          outputInstruction: outputInstruction,
          roleplayMode: roleplayMode,
        );
      }
      return await LLMService.generateMessages(
        model: model,
        systemPrompt: prompt,
        historyMessages: history,
        outputInstruction: outputInstruction,
        roleplayMode: roleplayMode,
      );
    } on LLMException catch (e) {
      _lastError = e.message;
      return const ProactiveResult([], ChatUsage());
    } catch (e) {
      _lastError = LLMService.describeException(e);
      return const ProactiveResult([], ChatUsage());
    }
  }

  /// 生成并逐条加入角色的回复消息（微信拟真：逐条延迟渲染）。
  ///
  /// 整个流程在本 Provider（应用级单例）中执行，不依赖聊天界面是否存活：
  /// 即使 AI 尚未回复完就退出聊天界面，回复也会继续生成并完整入库，
  /// 退出期间产生的角色消息会记为未读。
  /// 同一会话同时只允许一个回复流程在跑，重复触发时复用进行中的流程。
  /// 返回生成的消息列表（可能为空，空且无错误时由界面给出轻提示）。
  Future<List<String>> runProactiveReply({
    required String conversationId,
    required ApiModel model,
    required String characterName,
    required String characterSystemPrompt,
    required String userRelationship,
    required String userNickname,
    bool replyToUser = false,
    bool roleplayMode = false,
    String roleplayProgressionStyle = 'free',
    int contextCount = 10,
    ApiModel? compressModel,
    bool enableCompression = false,
    int contextLength = 8000,
    double compressThreshold = 0.7,
    String? imagePath,
    String activeStart = '',
    String activeEnd = '',
    List<String> memoryPoints = const [],
    String extraSystemContext =
        '', // 角色记忆池等额外记忆上下文，透传给 generateProactiveMessages
    // 角色可按需发送本地表情包（自定义 + 创意工坊 Pack）；null 表示关闭该能力。
    StickerMatch? Function(String query)? findSticker,
  }) {
    debugPrint(
        '[ChatProvider] runProactiveReply 被调用: $conversationId replyToUser=$replyToUser');
    // 同一会话的回复进行中：直接复用同一次流程（防止重复触发/误报空回复）
    if (_runningReply != null && _replyingConversationId == conversationId) {
      debugPrint('[ChatProvider] 复用进行中的回复流程: $conversationId');
      return _runningReply!;
    }
    _replyingConversationId = conversationId;
    notifyListeners(); // 聊天标题立即显示"对方正在输入……"
    final future = _doRunProactiveReply(
      conversationId: conversationId,
      model: model,
      characterName: characterName,
      characterSystemPrompt: characterSystemPrompt,
      userRelationship: userRelationship,
      userNickname: userNickname,
      replyToUser: replyToUser,
      roleplayMode: roleplayMode,
      roleplayProgressionStyle: roleplayProgressionStyle,
      contextCount: contextCount,
      compressModel: compressModel,
      enableCompression: enableCompression,
      contextLength: contextLength,
      compressThreshold: compressThreshold,
      imagePath: imagePath,
      activeStart: activeStart,
      activeEnd: activeEnd,
      memoryPoints: memoryPoints,
      extraSystemContext: extraSystemContext,
      findSticker: findSticker,
    );
    _runningReply = future;
    return future;
  }

  Future<List<String>> _doRunProactiveReply({
    required String conversationId,
    required ApiModel model,
    required String characterName,
    required String characterSystemPrompt,
    required String userRelationship,
    required String userNickname,
    bool replyToUser = false,
    bool roleplayMode = false,
    String roleplayProgressionStyle = 'free',
    int contextCount = 10,
    ApiModel? compressModel,
    bool enableCompression = false,
    int contextLength = 8000,
    double compressThreshold = 0.7,
    String? imagePath,
    String activeStart = '',
    String activeEnd = '',
    List<String> memoryPoints = const [],
    String extraSystemContext = '',
    StickerMatch? Function(String query)? findSticker,
  }) async {
    debugPrint('[ChatProvider] _doRunProactiveReply 开始: $conversationId');
    try {
      final result = await generateProactiveMessages(
        conversationId: conversationId,
        model: model,
        characterName: characterName,
        characterSystemPrompt: characterSystemPrompt,
        userRelationship: userRelationship,
        userNickname: userNickname,
        replyToUser: replyToUser,
        roleplayMode: roleplayMode,
        roleplayProgressionStyle: roleplayProgressionStyle,
        contextCount: contextCount,
        compressModel: compressModel,
        enableCompression: enableCompression,
        contextLength: contextLength,
        compressThreshold: compressThreshold,
        imagePath: imagePath,
        activeStart: activeStart,
        activeEnd: activeEnd,
        memoryPoints: memoryPoints,
        extraSystemContext: extraSystemContext,
      );
      final messages = result.messages;
      // 累计真实 token 用量（发送 = prompt_tokens，接收 = completion_tokens，含思考）
      var usage = result.usage;
      if (usage.reasoningTokens == null &&
          result.reasoningContent.trim().isNotEmpty) {
        usage = ChatUsage(
          promptTokens: usage.promptTokens,
          completionTokens: usage.completionTokens,
          totalTokens: usage.totalTokens,
          reasoningTokens:
              LLMService.estimateReasoningTokens(result.reasoningContent),
        );
      }
      await TokenUsageProvider.instance.addUsage(
        conversationId,
        usage,
        label: characterName,
        avatar: _conversationAvatar(conversationId),
      );
      final random = Random();
      final displayedMessages = <String>[];
      var stickerSent = false;
      var reasoningAttached = false;
      for (final content in messages) {
        final query = StickerQueryProtocol.extractQuery(content);
        final visibleContent = StickerQueryProtocol.visibleText(content);
        if (query != null) {
          // 每轮最多发送一张；只有本地真实检索到的表情包才会显示。
          final sticker = !stickerSent ? findSticker?.call(query) : null;
          if (sticker != null) {
            final beforeCount = _messagesMap[conversationId]?.length ?? 0;
            addCharacterStickerMessage(
              conversationId: conversationId,
              stickerPath: sticker.imagePath,
              label: sticker.label,
            );
            if ((_messagesMap[conversationId]?.length ?? 0) > beforeCount) {
              stickerSent = true;
              // 仅供调用方判断本轮是否有回复；不会作为文本气泡写入会话。
              displayedMessages.add('[表情包]');
            }
          }
          // 模型偶尔会把查询标记和正常文字写在同一元素中；仅展示剥离标记后的文字。
          if (visibleContent.isEmpty) continue;
        }
        if (visibleContent.isEmpty) continue;
        addProactiveMessage(
          conversationId,
          visibleContent,
          reasoningContent: reasoningAttached
              ? ''
              : result.reasoningContent,
          reasoningDurationMs: reasoningAttached
              ? null
              : result.reasoningDurationMs,
        );
        if (result.reasoningContent.trim().isNotEmpty) reasoningAttached = true;
        displayedMessages.add(visibleContent);
        HapticFeedback.lightImpact(); // 消息提示震动
        // 延迟 = 随机 0~1s + 消息长度 * 50ms（模拟打字耗时）+ 600ms 消息间隔
        final delay = random.nextDouble() * 1000 + visibleContent.length * 50;
        await Future.delayed(Duration(milliseconds: delay.round() + 600));
      }
      // 已使用的上下文 = 会话累计（摘要起全部文本消息 + 系统提示词）。
      // 仅当 API 返回的 prompt_tokens 更大时用它校准（说明本地估算偏低或
      // 上下文窗口未截断、prompt 代表全量真实消耗），
      // 避免把显示值压成"最近一次请求的截断窗口"（几十条消息后只剩几百）。
      final prompt = result.usage.promptTokens;
      final estimated = _estimateRequestInputBudget(
        conversationId,
        contextCount: contextCount,
      );
      _contextTokens[conversationId] =
          prompt != null && prompt > estimated ? prompt : estimated;
      return displayedMessages;
    } finally {
      debugPrint('[ChatProvider] _doRunProactiveReply 结束: $conversationId');
      _replyingConversationId = null;
      _runningReply = null;
      notifyListeners();
    }
  }

  /// 会话压缩：当"已使用的上下文 token"（摘要起全部文本消息）估算值 +
  /// 系统提示词 + 格式指令达到模型上下文的 [threshold] 时，
  /// 将更早的消息交给压缩模型生成摘要，在压缩边界插入摘要消息（原文保留）。
  /// [systemPromptTokens] 为系统提示词 + 格式指令占用的 token，计入压缩预算。
  /// [force] 为 true（手动压缩）时忽略阈值判断，只要存在可压缩的早期消息就执行。
  /// 压缩失败（网络/API 异常）时静默跳过，不影响本次回复；返回是否完成压缩。
  Future<bool> _maybeCompressConversation({
    required String conversationId,
    required ApiModel compressModel,
    required int contextLength,
    required double threshold,
    int systemPromptTokens = 0,
    int contextCount = 0,
    bool force = false,
  }) async {
    final messages = _messagesMap[conversationId] ?? [];
    if (messages.isEmpty) return false;
    final textMessages =
        messages.where((m) => m.type == MessageType.text).toList();
    if (textMessages.length <= kKeepRecentMessages) return false;

    // 发送输入预算（系统提示词 + 摘要起历史）+ 系统提示词一起判断是否达到压缩阈值
    // （手动压缩时跳过）。与进度条展示的上下文使用量同口径。
    if (!force &&
        _estimateRequestInputBudget(
                conversationId,
                contextCount: contextCount,
                systemTokens: systemPromptTokens) <
            contextLength * threshold) {
      return false;
    }

    // 确定压缩边界：从尾部数出最近 kKeepRecentMessages 条文本消息，之前的全部压缩
    var cutIndex = 0;
    var textSeen = 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].type == MessageType.text) textSeen++;
      if (textSeen == kKeepRecentMessages) {
        cutIndex = i;
        break;
      }
    }
    if (cutIndex <= 0) return false;
    final toCompress = messages.sublist(0, cutIndex);
    final kept = messages.sublist(cutIndex);

    final history = toCompress
        .map((m) => {
              'role': m.isFromUser ? 'user' : 'assistant',
              // 表情包/图片/文件绝不让文件路径进入压缩模型的上下文。
              'content': _describeMessageForModel(m),
            })
        .toList();

    try {
      final summary = await LLMService.compressHistory(
        model: compressModel,
        historyMessages: history,
      );
      if (summary.isEmpty) return false;
      // 压缩不删除前文：原文消息完整保留，仅在压缩边界处插入一条摘要消息。
      // 后续发送上下文从最后一条摘要消息起取（其前原文不再发给模型，界面仍可完整查看）。
      _messagesMap[conversationId]!.insert(
        cutIndex,
        Message(
          id: const Uuid().v4(),
          conversationId: conversationId,
          content:
              '［已${force ? '手动' : '自动'}压缩更早的 ${toCompress.length} 条消息］\n$summary',
          type: MessageType.text,
          sender: MessageSender.character,
          isCompressionSummary: true,
        ),
      );
      // 压缩后参与上下文的消息大幅减少，按「摘要 + 保留消息」重算发送输入预算
      _contextTokens[conversationId] = _estimateRequestInputBudget(
        conversationId,
        contextCount: contextCount,
      );
      _updateConversationLastMessage(conversationId, kept.last.content);
      notifyListeners();
      await _persist();
      return true;
    } catch (e) {
      debugPrint('[ChatProvider] 会话压缩失败，继续原样发送: $e');
      return false;
    }
  }

  /// 手动压缩会话（聊天设置页「压缩对话」按钮）：
  /// 忽略阈值判断，直接压缩更早的历史消息。
  /// 无可压缩消息或压缩失败时返回 false。
  Future<bool> compressConversationNow({
    required String conversationId,
    required ApiModel compressModel,
    int contextLength = 8000,
  }) {
    return _maybeCompressConversation(
      conversationId: conversationId,
      compressModel: compressModel,
      contextLength: contextLength,
      threshold: 1.0, // force 模式下不参与判断
      contextCount: 0,
      force: true,
    );
  }

  /// 估算一段文本的 token 数（委托 LLMService 本地分词估算：
  /// 中文保守 1 字 ≈ 2 token，英文约 4 字符 ≈ 1 token）
  static int _estimateTextTokens(String text) =>
      LLMService.estimateTokens(text);

  /// 估算文本消息列表的 token 数（含每条消息的 JSON 结构开销）
  static int _estimateTokens(List<Message> messages) {
    var total = 0;
    for (final m in messages) {
      if (m.type != MessageType.text) continue;
      total += LLMService.estimateTokens(m.content) + kPerMessageJsonTokens;
    }
    return total;
  }

  /// 本地分词估算某会话的上下文 token（从最后一条压缩摘要消息起取全部 + 可选额外文本），
  /// 每条消息计入 JSON 结构开销。作为无真实 usage 记录时的兜底粗估。
  int _estimateConversationTokens(String conversationId,
      [List<String> extra = const []]) {
    return _estimateSendBudget(conversationId, 0, extra);
  }

  /// 估算会话当前"发送输入预算"（历史部分）：
  /// 从最后一条压缩摘要消息起，取最近 [contextCount] 条文本消息
  /// （[contextCount] <= 0 表示从摘要起取全部），每条计入 JSON 结构开销。
  /// [extra] 为本次提问 / 本次回复等额外文本。
  int _estimateSendBudget(String conversationId, int contextCount,
      [List<String> extra = const []]) {
    final messages = _messagesMap[conversationId] ?? const <Message>[];
    var start = 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isCompressionSummary) {
        start = i;
        break;
      }
    }
    final from = contextCount > 0 && messages.length - start > contextCount
        ? messages.length - contextCount
        : start;
    var total = 0;
    for (int i = from; i < messages.length; i++) {
      final m = messages[i];
      if (m.type == MessageType.text) {
        total += LLMService.estimateTokens(m.content) + kPerMessageJsonTokens;
      }
    }
    for (final text in extra) {
      total += LLMService.estimateTokens(text) + kPerMessageJsonTokens;
    }
    return total;
  }

  /// 按实际会发送给模型的 history payload 估算输入预算。
  ///
  /// 与 [_buildHistory] 共用同一套消息筛选和转换逻辑，因而会正确计入语C
  /// 剧情行动、表情包描述和合并转发内容；[contextCount] 与实际请求一致。
  int _estimateRequestInputBudget(
    String conversationId, {
    required int contextCount,
    int? systemTokens,
  }) {
    final sys = systemTokens ?? (_systemTokens[conversationId] ?? 0);
    final history = _buildHistory(conversationId, contextCount);
    final historyTokens = history.fold<int>(
      0,
      (sum, item) =>
          sum + _estimateTextTokens(item['content'] ?? '') + kPerMessageJsonTokens,
    );
    return sys + historyTokens;
  }

  /// 估算会话当前"发送输入预算"（进度条口径，即公式的分子）：
  /// = 系统提示词 + 输出指令（[systemTokens] 或上次记录的缓存）+
  ///   摘要起全部文本消息历史 + [extra] 额外文本（如当前用户输入）。
  int _estimateSendInputBudget(String conversationId,
      {int? systemTokens, List<String> extra = const []}) {
    final sys = systemTokens ?? (_systemTokens[conversationId] ?? 0);
    var total = sys + _estimateConversationTokens(conversationId);
    for (final text in extra) {
      total += LLMService.estimateTokens(text) + kPerMessageJsonTokens;
    }
    return total;
  }

  /// 获取某会话当前上下文 token 用量（发送输入预算，用于「聊天设置」展示与压缩进度）。
  /// 有记录时优先返回；无记录时用本地分词估算并缓存。
  int getContextTokens(String conversationId, {int contextCount = 0}) {
    final tracked = _contextTokens[conversationId];
    // 有真实/最近一次请求记录时仍需在设置页按当前 contextCount 重算，
    // 避免重启后或切换上下文条数后沿用旧口径。
    if (tracked != null && contextCount == 0) return tracked;
    final estimated = _estimateRequestInputBudget(
      conversationId,
      contextCount: contextCount,
    );
    // 有限上下文的展示值只是临时口径，不能覆盖缓存中的真实/全量请求值；
    // 否则用户切回「无限制」时会错误沿用之前有限窗口的占用量。
    if (contextCount == 0) _contextTokens[conversationId] = estimated;
    return estimated;
  }

  /// 该会话是否已有系统提示词 token 记录。
  /// 升级迁移提示用：无记录说明本进程内从未触发过 AI 回复，
  /// 上下文统计会暂时漏掉系统提示词，触发一次回复后自动校正。
  bool hasSystemTokensRecord(String conversationId) =>
      _systemTokens.containsKey(conversationId);

  /// 从会话记录中取最近 [contextCount] 条文本消息作为对话历史。
  /// 压缩后原文不删除：历史起点定位到最后一条压缩摘要消息（含），
  /// 摘要之前的原文已被摘要替代、不再发送给模型。
  List<Map<String, String>> _buildHistory(
      String conversationId, int contextCount) {
    final history = _messagesMap[conversationId] ?? [];
    var cutStart = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].isCompressionSummary) {
        cutStart = i;
        break;
      }
    }
    final start = contextCount > 0 && history.length - contextCount > cutStart
        ? history.length - contextCount
        : cutStart;
    final result = <Map<String, String>>[];
    for (int i = start; i < history.length; i++) {
      final m = history[i];
      if (m.type == MessageType.sticker) {
        result.add({
          'role': m.isFromUser ? 'user' : 'assistant',
          'content': _describeMessageForModel(m),
        });
        continue;
      }
      if (m.type == MessageType.narration) {
        result.add({
          'role': 'user',
          'content': '【用户剧情行动/旁白】\n${m.content}',
        });
        continue;
      }
      if (m.type != MessageType.text) continue; // 图片/文件消息不入上下文
      // 合并转发卡片：展开为原始对话消息，参与上下文
      if (m.isForwardCard) {
        for (final item in m.forwardedItems) {
          if (item.type != 'text') continue;
          result.add({
            'role': item.isUser ? 'user' : 'assistant',
            'content': item.content,
          });
        }
        continue;
      }
      result.add({
        'role': m.isFromUser ? 'user' : 'assistant',
        'content': m.content,
      });
    }
    return result;
  }

  /// 把消息转换为模型可读的上下文描述：
  /// - 表情包绝不暴露本地文件路径；
  /// - 角色自己发送的表情包用「你」而不是「用户」，避免后续把
  ///   角色发的表情错记成用户发的；
  /// - 图片/文件以占位说明进入上下文。
  String _describeMessageForModel(Message m) {
    switch (m.type) {
      case MessageType.sticker:
        final label = m.stickerLabel?.trim() ?? '';
        final who = m.isFromUser ? '用户' : '你';
        return label.isEmpty ? '[$who发送了一个表情包]' : '[$who发送了一个表情包（备注：$label）]';
      case MessageType.image:
        return m.isFromUser ? '[用户发送了一张图片]' : '[你发送了一张图片]';
      case MessageType.file:
        final fileName = m.content.split(RegExp(r'[/\\]')).last;
        return m.isFromUser ? '[用户发送了一个文件：$fileName]' : '[你发送了一个文件：$fileName]';
      case MessageType.text:
      case MessageType.system:
      case MessageType.narration:
        return m.content;
    }
  }

  /// 将一条角色主动消息加入会话并持久化（渲染阶段逐条调用）。
  /// [reasoningContent] / [reasoningDurationMs] 仅挂在第一条文本消息上。
  void addProactiveMessage(
    String conversationId,
    String content, {
    String reasoningContent = '',
    int? reasoningDurationMs,
  }) {
    if (content.trim().isEmpty) return;
    debugPrint('[ChatProvider] addProactiveMessage 入库: $conversationId');
    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: content,
      sender: MessageSender.character,
      reasoningContent: reasoningContent,
      reasoningDurationMs: reasoningDurationMs,
    ));
    _updateConversationLastMessage(conversationId, content);
    _notifyCharacterMessage(conversationId, content);
    notifyListeners();
    _persist();
  }

  /// 用户不在会话页面时：未读 +1 并发送系统通知（文本与表情消息共用）。
  void _notifyCharacterMessage(
      String conversationId, String notificationContent) {
    if (_activeConversationId == conversationId) return;
    final unreadCount = _increaseUnread(conversationId);
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final conv = _conversations[index];
      NotificationService.instance.showCharacterNotification(
        conversationId: conversationId,
        characterName: conv.characterName,
        content: notificationContent,
        unreadCount: unreadCount,
        avatarBase64: conv.characterAvatar,
      );
    }
  }

  /// 角色表情只允许由本地检索得到的真实文件创建，避免模型伪造路径或编号。
  void addCharacterStickerMessage({
    required String conversationId,
    required String stickerPath,
    String? label,
  }) {
    if (stickerPath.trim().isEmpty || !File(stickerPath).existsSync()) {
      debugPrint('[Sticker] 角色表情发送失败：图片文件不存在 path=$stickerPath');
      return;
    }
    debugPrint('[Sticker] 角色表情发送成功 label=${label ?? ''} path=$stickerPath');
    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: stickerPath,
      type: MessageType.sticker,
      sender: MessageSender.character,
      stickerLabel: label?.trim().isEmpty == true ? null : label?.trim(),
    ));
    _updateConversationLastMessage(
      conversationId,
      label?.trim().isNotEmpty == true ? '[表情包: ${label!.trim()}]' : '[表情包]',
    );
    _notifyCharacterMessage(
      conversationId,
      label?.trim().isNotEmpty == true ? '[表情包：${label!.trim()}]' : '[表情包]',
    );
    notifyListeners();
    _persist();
  }

  /// 逐条转发：将选中消息逐条作为"我"的消息加入目标会话（保留原消息类型）
  Future<void> forwardIndividually({
    required String conversationId,
    required List<Message> messages,
  }) async {
    if (messages.isEmpty) return;
    _messagesMap[conversationId] ??= [];
    for (final m in messages) {
      _messagesMap[conversationId]!.add(Message(
        id: const Uuid().v4(),
        conversationId: conversationId,
        content: m.content,
        type: m.type,
        sender: MessageSender.user,
      ));
    }
    _updateConversationLastMessage(conversationId, messages.last.content);
    notifyListeners();
    await _persist();
  }

  /// 合并转发：生成一条"聊天记录"卡片消息加入目标会话，
  /// 点击卡片可进入二级页面查看原始对话（消息数据保存在 [Message.forwardedItems]）。
  Future<void> forwardMerged({
    required String conversationId,
    required String sourceName,
    String sourceAvatar = '',
    required List<Message> messages,
  }) async {
    if (messages.isEmpty) return;
    final items = messages
        .map((m) => ForwardItem(
              senderName: m.isFromUser ? '我' : sourceName,
              isUser: m.isFromUser,
              content: m.content,
              type: m.type == MessageType.image
                  ? 'image'
                  : m.type == MessageType.file
                      ? 'file'
                      : 'text',
              createdAt: m.createdAt,
              characterAvatar: m.isFromUser ? '' : sourceAvatar,
            ))
        .toList();
    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: '［聊天记录］',
      sender: MessageSender.user,
      forwardedItems: items,
    ));
    _updateConversationLastMessage(conversationId, '［聊天记录］');
    notifyListeners();
    await _persist();
  }

  /// 通用删除单条消息（用于重新回复等场景）
  void deleteMessage(String conversationId, String messageId) {
    final messages = _messagesMap[conversationId];
    if (messages == null) return;
    messages.removeWhere((m) => m.id == messageId);
    // 删除消息后按剩余消息重新估算上下文 token
    _contextTokens[conversationId] = _estimateSendInputBudget(conversationId);
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

  /// 修改消息内容，供语C用户编辑剧情行动或模型上一轮回复。
  Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String content,
  }) async {
    final text = content.trim();
    if (text.isEmpty) return;
    final messages = _messagesMap[conversationId];
    if (messages == null) return;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    messages[index] = messages[index].copyWith(content: text);
    _contextTokens[conversationId] = _estimateSendInputBudget(conversationId);
    _updateConversationLastMessage(conversationId, text);
    notifyListeners();
    await _persist();
  }

  /// 撤回我方消息：删除消息
  void withdrawMessage(String conversationId, String messageId) {
    final messages = _messagesMap[conversationId];
    if (messages == null) return;

    messages.removeWhere((m) => m.id == messageId);
    // 撤回后按剩余消息重新估算上下文 token
    _contextTokens[conversationId] = _estimateSendInputBudget(conversationId);
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

  /// 导入聊天记录：将解析出的消息追加到当前会话（保留原消息时间戳）
  Future<void> importMessages({
    required String conversationId,
    required List<Message> messages,
  }) async {
    if (messages.isEmpty) return;
    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.addAll(messages);
    // 累加导入消息的上下文 token
    _contextTokens[conversationId] =
        (_contextTokens[conversationId] ?? 0) + _estimateTokens(messages);
    _updateConversationLastMessage(conversationId, messages.last.content);
    notifyListeners();
    await _persist();
  }

  /// 分支对话：以 [sourceConversationId] 中 [throughMessageId]（含）为分叉点，
  /// 复制该条及之前的消息到新角色的新会话，返回新会话。
  /// 原会话不受影响；分支点之后的消息不会带入新会话。
  Future<Conversation> branchConversation({
    required String sourceConversationId,
    required String throughMessageId,
    required String newCharacterId,
    required String newCharacterName,
    String newCharacterAvatar = '',
  }) async {
    final source = _messagesMap[sourceConversationId] ?? const <Message>[];
    final branchIndex =
        source.indexWhere((m) => m.id == throughMessageId);
    if (branchIndex < 0) {
      throw StateError('分支点消息不存在');
    }
    final branchPoint = source[branchIndex];
    final conversation = Conversation(
      id: const Uuid().v4(),
      characterId: newCharacterId,
      characterName: newCharacterName,
      characterAvatar: newCharacterAvatar,
      lastMessage: branchPoint.content,
      lastMessageTime: branchPoint.createdAt,
    );
    final copied = <Message>[];
    for (var i = 0; i <= branchIndex; i++) {
      final m = source[i];
      copied.add(Message(
        id: const Uuid().v4(),
        conversationId: conversation.id,
        content: m.content,
        type: m.type,
        sender: m.sender,
        // 分支会话是 1v1：清掉群聊侧的发送者标记，避免头像/上下文错乱
        senderCharacterId: '',
        senderName: '',
        createdAt: m.createdAt,
        isRead: true,
        quoteContent: m.quoteContent,
        quoteSender: m.quoteSender,
        stickerLabel: m.stickerLabel,
        stickerSource: m.stickerSource,
        forwardedItems: m.forwardedItems,
        isCompressionSummary: m.isCompressionSummary,
        reasoningContent: m.reasoningContent,
        reasoningDurationMs: m.reasoningDurationMs,
      ));
    }
    _conversations.insert(0, conversation);
    _messagesMap[conversation.id] = copied;
    _contextTokens[conversation.id] =
        _estimateConversationTokens(conversation.id);
    notifyListeners();
    await _persist();
    return conversation;
  }

  /// 发送图片消息
  Future<void> sendImageMessage({
    required String conversationId,
    required String imagePath,
    required String characterName,
    String modelName = '',
    int contextCount = 10,
  }) async {
    await _clearRoleplayChoicesForNextTurn(conversationId);
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

  /// 发送表情包消息。回复仍由输入框的对号按钮触发，与图片消息保持一致。
  Future<void> sendStickerMessage({
    required String conversationId,
    required String stickerPath,
    required String? label,
    String? stickerSource,
  }) async {
    final normalizedLabel = label?.trim();
    await _clearRoleplayChoicesForNextTurn(conversationId);
    final userMessage = Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: stickerPath,
      type: MessageType.sticker,
      sender: MessageSender.user,
      stickerLabel: normalizedLabel?.isEmpty == true ? null : normalizedLabel,
      stickerSource: stickerSource,
    );
    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(userMessage);
    _updateConversationLastMessage(
      conversationId,
      normalizedLabel == null || normalizedLabel.isEmpty
          ? '[表情包]'
          : '[表情包: $normalizedLabel]',
    );
    notifyListeners();
    await _persist();
  }

  /// 发送文件消息（file path）
  Future<void> sendFileMessage({
    required String conversationId,
    required String filePath,
    required String fileName,
  }) async {
    await _clearRoleplayChoicesForNextTurn(conversationId);
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

  /// 设置当前会话是否在角色回复完成后自动朗读。
  Future<void> setConversationAutoRead(String conversationId, bool value) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    _conversations[index] = _conversations[index].copyWith(autoRead: value);
    notifyListeners();
    await _persist();
  }

  void deleteConversation(String conversationId) {
    _conversations.removeWhere((c) => c.id == conversationId);
    _messagesMap.remove(conversationId);
    _contextTokens.remove(conversationId);
    setRoleplayChoices(conversationId, const []);
    notifyListeners();
    _persist();
  }

  /// 清空全部聊天数据（管理占用空间页使用）：
  /// 清空内存中的会话/消息/上下文统计，并删除本地存储键。
  Future<void> clearAllData() async {
    _conversations.clear();
    _messagesMap.clear();
    _contextTokens.clear();
    _systemTokens.clear();
    _roleplayChoices.clear();
    _activeConversationId = null;
    _replyingConversationId = null;
    _runningReply = null;
    _lastError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_conversationsKey);
    await prefs.remove(_messagesKey);
    await prefs.remove(_contextTokensKey);
    await prefs.remove(_systemTokensKey);
    await prefs.remove(_roleplayChoicesKey);
    notifyListeners();
  }

  /// 清空当前会话的全部消息（保留会话本身）。
  /// 再次打开该聊天不会显示任何记录，AI 也不会继承此前的上下文。
  /// 消息数据会被完全抹除（存储中不再保留该会话的任何消息）。
  void clearMessages(String conversationId) {
    _messagesMap.remove(conversationId);
    _contextTokens.remove(conversationId);
    setRoleplayChoices(conversationId, const []);
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

  /// 同步角色头像到其所有会话（首页消息列表头像实时更新）。
  /// 会话保存的是创建时的 characterAvatar 快照，角色更换头像后需手动同步。
  void updateCharacterAvatar(String characterId, String avatar) {
    var changed = false;
    for (int i = 0; i < _conversations.length; i++) {
      if (_conversations[i].characterId == characterId &&
          _conversations[i].characterAvatar != avatar) {
        _conversations[i] = _conversations[i].copyWith(characterAvatar: avatar);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _persist();
    }
  }

  /// 重新关联孤儿会话：角色删除后重新导入同名角色时，
  /// 把仍指向旧角色 id 的会话重新指向新角色，并刷新名称/头像快照。
  /// 仅调整会话指向，不覆盖任何聊天记录。
  void relinkConversation({
    required String oldCharacterId,
    required String newCharacterId,
    required String name,
    String avatar = '',
  }) {
    var changed = false;
    for (int i = 0; i < _conversations.length; i++) {
      if (_conversations[i].characterId == oldCharacterId) {
        _conversations[i] = _conversations[i].copyWith(
          characterId: newCharacterId,
          characterName: name,
          characterAvatar: avatar,
        );
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _persist();
    }
  }
}

// ─── 持久化跨 isolate 传输的数据结构 ─────────────────────────────

/// 本地存储的原始 JSON 字符串（供后台 isolate 反序列化）
class _RawStore {
  final String? conversationsJson;
  final String? messagesJson;
  final String? contextTokensJson;
  final String? systemTokensJson;

  const _RawStore({
    this.conversationsJson,
    this.messagesJson,
    this.contextTokensJson,
    this.systemTokensJson,
  });
}

/// 后台 isolate 反序列化后的结果
class _DecodedStore {
  final List<Conversation> conversations;
  final Map<String, List<Message>> messages;
  final Map<String, int> contextTokens;
  final Map<String, int> systemTokens;

  const _DecodedStore({
    required this.conversations,
    required this.messages,
    required this.contextTokens,
    required this.systemTokens,
  });
}

/// 待持久化的内存数据快照（供后台 isolate 序列化）
class _PersistSnapshot {
  final List<Conversation> conversations;
  final Map<String, List<Message>> messages;
  final Map<String, int> contextTokens;
  final Map<String, int> systemTokens;

  const _PersistSnapshot({
    required this.conversations,
    required this.messages,
    required this.contextTokens,
    required this.systemTokens,
  });
}

/// 后台 isolate：反序列化全部本地数据。
/// 解析完成后在后台重算各会话上下文 token：
/// 系统提示词恢复后，按「系统提示词 + 摘要起全部历史」估算，
/// 覆盖重启前可能不含系统提示词的旧快照。
@pragma('vm:entry-point')
_DecodedStore _decodePersistStore(_RawStore raw) {
  var conversations = const <Conversation>[];
  var messages = <String, List<Message>>{};
  var contextTokens = <String, int>{};
  var systemTokens = <String, int>{};

  try {
    final convStr = raw.conversationsJson;
    if (convStr != null) {
      final list = jsonDecode(convStr) as List<dynamic>;
      conversations = list
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  } catch (_) {}
  try {
    final msgStr = raw.messagesJson;
    if (msgStr != null) {
      final map = jsonDecode(msgStr) as Map<String, dynamic>;
      map.forEach((convId, msgs) {
        messages[convId] = (msgs as List<dynamic>)
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    }
  } catch (_) {}
  try {
    final ctxStr = raw.contextTokensJson;
    if (ctxStr != null) {
      final map = jsonDecode(ctxStr) as Map<String, dynamic>;
      contextTokens = map.map((k, v) => MapEntry(k, (v as num).toInt()));
    }
  } catch (_) {}
  try {
    final sysStr = raw.systemTokensJson;
    if (sysStr != null) {
      final map = jsonDecode(sysStr) as Map<String, dynamic>;
      systemTokens = map.map((k, v) => MapEntry(k, (v as num).toInt()));
    }
  } catch (_) {}

  // 与旧版主线程逻辑等价的上下文 token 重算（移入后台避免拖慢启动）
  for (final entry in systemTokens.entries) {
    final msgs = messages[entry.key];
    if (msgs == null) continue;
    var start = 0;
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].isCompressionSummary) {
        start = i;
        break;
      }
    }
    var total = entry.value;
    for (var i = start; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.type == MessageType.text) {
        total += LLMService.estimateTokens(m.content) +
            ChatProvider.kPerMessageJsonTokens;
      }
    }
    contextTokens[entry.key] = total;
  }

  return _DecodedStore(
    conversations: conversations,
    messages: messages,
    contextTokens: contextTokens,
    systemTokens: systemTokens,
  );
}

/// 后台 isolate：将内存数据序列化为各存储键的 JSON 字符串。
@pragma('vm:entry-point')
Map<String, String> _encodePersistSnapshot(_PersistSnapshot snapshot) {
  return {
    'conversations':
        jsonEncode(snapshot.conversations.map((c) => c.toJson()).toList()),
    'messages': jsonEncode(snapshot.messages.map(
      (key, value) => MapEntry(key, value.map((m) => m.toJson()).toList()),
    )),
    'contextTokens': jsonEncode(snapshot.contextTokens),
    'systemTokens': jsonEncode(snapshot.systemTokens),
  };
}
