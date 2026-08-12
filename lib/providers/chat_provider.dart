import 'dart:convert';
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
import 'api_provider.dart';

class ChatProvider extends ChangeNotifier {
  static const _conversationsKey = 'chat_conversations_v1';
  static const _messagesKey = 'chat_messages_v1';
  static const _contextTokensKey = 'chat_context_tokens_v1'; // 各会话上下文 token 累计值
  static const _systemTokensKey = 'chat_system_tokens_v1'; // 各会话系统提示词 + 输出指令 token（持久化，重启恢复）

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
  final Map<String, int> _contextTokens = {}; // 会话 → 上下文 token 用量（输入侧，API usage 优先）
  final Map<String, int> _systemTokens = {}; // 会话 → 系统提示词 + 输出指令 token（内存态，供乐观更新）

  List<Conversation> get conversations => _conversations;
  String? get lastError => _lastError;

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
    debugPrint('[ChatProvider] 未读+1 $conversationId → $count（active=$_activeConversationId）');
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
    // 加载各会话上下文 token 累计值
    try {
      final ctxStr = prefs.getString(_contextTokensKey);
      if (ctxStr != null) {
        final map = jsonDecode(ctxStr) as Map<String, dynamic>;
        _contextTokens
          ..clear()
          ..addAll(map.map(
              (k, v) => MapEntry(k, (v as num).toInt())));
      }
    } catch (_) {}
    // 加载各会话系统提示词 + 输出指令 token（纯内存态重启即丢，
    // 若不恢复，重启后发送消息乐观更新时会漏掉系统提示词这一大头）
    try {
      final sysStr = prefs.getString(_systemTokensKey);
      if (sysStr != null) {
        final map = jsonDecode(sysStr) as Map<String, dynamic>;
        _systemTokens
          ..clear()
          ..addAll(map.map(
              (k, v) => MapEntry(k, (v as num).toInt())));
      }
    } catch (_) {}
    // 系统提示词恢复后，用「系统提示词 + 摘要起全部历史」重算各会话上下文，
    // 覆盖重启前可能不含系统提示词的旧快照
    _systemTokens.forEach((id, _) {
      if (_messagesMap.containsKey(id)) {
        _contextTokens[id] = _estimateSendInputBudget(id);
      }
    });
    // 加载完成后通知监听者重建界面：
    // 否则首页在 init 完成前先渲染一次（会话为空 → 显示"暂无会话"），
    // 数据就绪后没有重建通知，列表会一直停留在空状态。
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
    await prefs.setString(_contextTokensKey, jsonEncode(_contextTokens));
    await prefs.setString(_systemTokensKey, jsonEncode(_systemTokens));
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
    // 乐观更新：发送后立即按「系统提示词 + 历史 + 本条输入」估算上下文用量，
    // 无需等待 API 返回（API 返回后会用真实 usage.prompt_tokens 校准覆盖）
    _contextTokens[conversationId] =
        _estimateSendInputBudget(conversationId, extra: [content]);
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
  /// [enableCompression] 开启且 [contextLength] 已知时，若历史估算 token 达到
  /// 模型上下文 [kCompressThreshold]，会先用 [compressModel] 压缩更早的历史消息。
  /// API 层失败时设置 [_lastError] 并返回空结果；解析兜底消息由 LLMService 处理。
  Future<ProactiveResult> generateProactiveMessages({
    required String conversationId,
    required ApiModel model,
    required String characterName,
    required String characterSystemPrompt,
    required String userRelationship,
    required String userNickname,
    bool replyToUser = false,
    List<Map<String, Object>>? historyMessages,
    int contextCount = 10,
    ApiModel? compressModel,
    bool enableCompression = false,
    int contextLength = 8000,
    double compressThreshold = 0.7,
    String? imagePath, // 非空时以"图片消息"发给模型（OpenAI 视觉格式）
  }) async {
    final prompt = PromptBuilder.buildSystemPrompt(
      baseSystemPrompt: characterSystemPrompt,
      characterName: characterName,
      userNickname: userNickname,
      userRelationship: userRelationship,
      currentTime: DateTime.now(),
      replyToUser: replyToUser,
    );
    final outputInstruction = PromptBuilder.buildOutputInstruction(
      characterName: characterName,
      replyToUser: replyToUser,
    );
    // 记录本会话的系统提示词 + 输出指令 token，供发送消息时乐观更新进度条
    _systemTokens[conversationId] =
        _estimateTextTokens(prompt) + _estimateTextTokens(outputInstruction) +
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
        systemPromptTokens:
            _estimateTextTokens(prompt) + _estimateTextTokens(outputInstruction) +
                kPerMessageJsonTokens * 2, // 系统提示词与输出指令各是一条消息
      );
    }
    try {
      final history = historyMessages ??
          _buildHistory(conversationId, contextCount);
      // 图片消息走 OpenAI 兼容视觉格式，让角色"看到"图片后回复
      if (imagePath != null && imagePath.isNotEmpty) {
        return await LLMService.generateVisionReply(
          model: model,
          systemPrompt: prompt,
          historyMessages: history,
          imagePath: imagePath,
          outputInstruction: outputInstruction,
        );
      }
      return await LLMService.generateMessages(
        model: model,
        systemPrompt: prompt,
        historyMessages: history,
        outputInstruction: outputInstruction,
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
    int contextCount = 10,
    ApiModel? compressModel,
    bool enableCompression = false,
    int contextLength = 8000,
    double compressThreshold = 0.7,
    String? imagePath,
  }) {
    debugPrint('[ChatProvider] runProactiveReply 被调用: $conversationId replyToUser=$replyToUser');
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
      contextCount: contextCount,
      compressModel: compressModel,
      enableCompression: enableCompression,
      contextLength: contextLength,
      compressThreshold: compressThreshold,
      imagePath: imagePath,
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
    int contextCount = 10,
    ApiModel? compressModel,
    bool enableCompression = false,
    int contextLength = 8000,
    double compressThreshold = 0.7,
    String? imagePath,
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
        contextCount: contextCount,
        compressModel: compressModel,
        enableCompression: enableCompression,
        contextLength: contextLength,
        compressThreshold: compressThreshold,
        imagePath: imagePath,
      );
      final messages = result.messages;
      final random = Random();
      for (final content in messages) {
        addProactiveMessage(conversationId, content);
        HapticFeedback.lightImpact(); // 消息提示震动
        // 延迟 = 随机 0~1s + 消息长度 * 50ms（模拟打字耗时）+ 600ms 消息间隔
        final delay = random.nextDouble() * 1000 + content.length * 50;
        await Future.delayed(Duration(milliseconds: delay.round() + 600));
      }
      // 已使用的上下文 = 会话累计（摘要起全部文本消息 + 系统提示词）。
      // 仅当 API 返回的 prompt_tokens 更大时用它校准（说明本地估算偏低或
      // 上下文窗口未截断、prompt 代表全量真实消耗），
      // 避免把显示值压成"最近一次请求的截断窗口"（几十条消息后只剩几百）。
      final prompt = result.usage.promptTokens;
      final estimated = _estimateSendInputBudget(conversationId);
      _contextTokens[conversationId] =
          prompt != null && prompt > estimated ? prompt : estimated;
      return messages;
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
        _estimateSendInputBudget(conversationId,
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
              'content': m.content,
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
          content: '［已${force ? '手动' : '自动'}压缩更早的 ${toCompress.length} 条消息］\n$summary',
          type: MessageType.text,
          sender: MessageSender.character,
          isCompressionSummary: true,
        ),
      );
      // 压缩后参与上下文的消息大幅减少，按「摘要 + 保留消息」重算发送输入预算
      _contextTokens[conversationId] = _estimateSendInputBudget(conversationId);
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
      force: true,
    );
  }

  /// 估算一段文本的 token 数（委托 LLMService 本地分词估算：
  /// 中文保守 1 字 ≈ 2 token，英文约 4 字符 ≈ 1 token）
  static int _estimateTextTokens(String text) => LLMService.estimateTokens(text);

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
  int _estimateConversationTokens(
      String conversationId, [List<String> extra = const []]) {
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
  int getContextTokens(String conversationId) {
    final tracked = _contextTokens[conversationId];
    if (tracked != null) return tracked;
    final estimated = _estimateSendInputBudget(conversationId);
    _contextTokens[conversationId] = estimated;
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

  /// 将一条角色主动消息加入会话并持久化（渲染阶段逐条调用）
  void addProactiveMessage(String conversationId, String content) {
    if (content.trim().isEmpty) return;
    debugPrint('[ChatProvider] addProactiveMessage 入库: $conversationId');
    _messagesMap[conversationId] ??= [];
    _messagesMap[conversationId]!.add(Message(
      id: const Uuid().v4(),
      conversationId: conversationId,
      content: content,
      sender: MessageSender.character,
    ));
    _updateConversationLastMessage(conversationId, content);
    // 不在该会话页面时记未读并发送系统通知
    if (_activeConversationId != conversationId) {
      final unreadCount = _increaseUnread(conversationId);
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        final conv = _conversations[index];
        NotificationService.instance.showCharacterNotification(
          conversationId: conversationId,
          characterName: conv.characterName,
          content: content,
          unreadCount: unreadCount,
          avatarBase64: conv.characterAvatar,
        );
      }
    }
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
    final items = messages.map((m) => ForwardItem(
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
        )).toList();
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
    _contextTokens.remove(conversationId);
    notifyListeners();
    _persist();
  }

  /// 清空当前会话的全部消息（保留会话本身）。
  /// 再次打开该聊天不会显示任何记录，AI 也不会继承此前的上下文。
  /// 消息数据会被完全抹除（存储中不再保留该会话的任何消息）。
  void clearMessages(String conversationId) {
    _messagesMap.remove(conversationId);
    _contextTokens.remove(conversationId);
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
