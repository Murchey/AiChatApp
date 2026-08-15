import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/group_chat.dart';
import '../models/message.dart';
import '../services/llm_service.dart';
import '../services/notification_service.dart';
import '../services/prompt_builder.dart';
import 'api_provider.dart';
import 'token_usage_provider.dart';

/// 群聊中参与回复的一个角色成员（触发回复时由界面预解析为纯数据，
/// 供后台调度循环使用，不依赖 BuildContext）。
class GroupMemberReply {
  final String characterId;
  final String name;
  final String systemPrompt;
  final String userRelationship;
  final String activeStart;
  final String activeEnd;
  final ApiModel model;
  final List<String> memoryPoints;

  /// 角色头像（base64），用于系统通知大图标
  final String avatarBase64;

  /// 角色记忆池文本（朋友圈 / 近期私聊 / 其他群内容 / 资料卡），拼入群聊系统提示词
  final String memoryPool;

  const GroupMemberReply({
    required this.characterId,
    required this.name,
    required this.systemPrompt,
    required this.userRelationship,
    required this.activeStart,
    required this.activeEnd,
    required this.model,
    required this.memoryPoints,
    this.avatarBase64 = '',
    this.memoryPool = '',
  });
}

/// 群聊回复中选中的「引用目标」（某条其他成员的消息）：
/// 生成时提示围绕它回复，落库时以引用块格式展示。
class _QuoteTarget {
  final String name;
  final String content;

  const _QuoteTarget({required this.name, required this.content});
}

/// 群聊存储与回复调度。
///
/// 群聊消息与私聊分离存储，但复用 [Message] 模型（角色消息带
/// [Message.senderCharacterId] / [Message.senderName] 区分发送者）。
/// 回复调度：随机顺序 + 逐成员 LLM「是否插话」判定 + 各自模型生成，
/// 用户提交新消息会自增 [generation] 打断进行中的旧轮。
class GroupChatProvider extends ChangeNotifier {
  static const _groupsKey = 'group_chats_v1';
  static const _messagesKey = 'group_chat_messages_v1';

  final List<GroupChat> _groups = [];
  final Map<String, List<Message>> _messages = {};

  String? _replyingGroupId; // 正在生成回复的群聊
  int _replyGeneration = 0; // 回复轮次序号（自增即打断旧轮）
  String? _lastError;

  /// 当前打开的群聊页面（其内新增角色消息不记未读、不弹系统通知）
  String? _activeGroupId;

  bool _persistRunning = false;
  bool _persistDirty = false;

  /// 群聊列表：置顶优先，其余按最近消息时间倒序
  List<GroupChat> get groups {
    final list = List.of(_groups);
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.lastMessageTime.compareTo(a.lastMessageTime);
    });
    return list;
  }

  String? get lastError => _lastError;

  /// 全部群聊未读消息数（首页底部 tab 角标用）
  int get totalUnreadCount =>
      _groups.fold<int>(0, (sum, g) => sum + g.unreadCount);

  bool isReplying(String groupId) => _replyingGroupId == groupId;

  /// 群聊页面打开时调用：记录当前群并清除其未读
  void markGroupActive(String groupId) {
    _activeGroupId = groupId;
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1 || _groups[index].unreadCount == 0) return;
    _groups[index] = _groups[index].copyWith(unreadCount: 0);
    notifyListeners();
    _persist();
  }

  /// 群聊页面销毁/退到后台时调用：该群新增角色消息恢复计入未读
  void markGroupInactive(String groupId) {
    if (_activeGroupId == groupId) {
      _activeGroupId = null;
    }
  }

  GroupChat? getGroupById(String id) {
    try {
      return _groups.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Message> getMessages(String groupId) => _messages[groupId] ?? const [];

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final groupsStr = prefs.getString(_groupsKey);
      if (groupsStr != null) {
        final list = jsonDecode(groupsStr) as List<dynamic>;
        _groups
          ..clear()
          ..addAll(
              list.map((e) => GroupChat.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('[GroupChatProvider] 加载群聊失败: $e');
    }
    try {
      final messagesStr = prefs.getString(_messagesKey);
      if (messagesStr != null) {
        final map = jsonDecode(messagesStr) as Map<String, dynamic>;
        _messages.clear();
        map.forEach((groupId, msgs) {
          _messages[groupId] = (msgs as List<dynamic>)
              .map((e) => Message.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('[GroupChatProvider] 加载群聊消息失败: $e');
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_persistRunning) {
      _persistDirty = true;
      return;
    }
    _persistRunning = true;
    try {
      do {
        _persistDirty = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _groupsKey,
          jsonEncode(_groups.map((g) => g.toJson()).toList()),
        );
        await prefs.setString(
          _messagesKey,
          jsonEncode(_messages.map(
            (key, value) => MapEntry(key, value.map((m) => m.toJson()).toList()),
          )),
        );
      } while (_persistDirty);
    } catch (e) {
      debugPrint('[GroupChatProvider] 持久化失败: $e');
    } finally {
      _persistRunning = false;
    }
  }

  // ── 群聊管理 ──

  GroupChat createGroup({
    required String name,
    required List<String> memberCharacterIds,
  }) {
    final group = GroupChat(
      id: const Uuid().v4(),
      name: name.trim(),
      memberCharacterIds: memberCharacterIds,
    );
    _groups.insert(0, group);
    _messages[group.id] = [];
    notifyListeners();
    _persist();
    return group;
  }

  void updateGroupName(String groupId, String name) {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) return;
    _groups[index] = _groups[index].copyWith(name: name.trim());
    notifyListeners();
    _persist();
  }

  /// 更新群头像（base64，空表示清除）
  Future<void> updateGroupAvatar(String groupId, String avatarBase64) async {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) return;
    _groups[index] = _groups[index].copyWith(avatar: avatarBase64);
    notifyListeners();
    await _persist();
  }

  /// 更新群简介（会进入模型请求上下文）
  Future<void> updateGroupDescription(
    String groupId,
    String description,
  ) async {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) return;
    _groups[index] = _groups[index].copyWith(description: description.trim());
    notifyListeners();
    await _persist();
  }

  /// 拉人进群。[names] 与 [characterIds] 一一对应（角色显示名，用于事件气泡）；
  /// 实际加入的成员会生成一条「XX 加入了群聊」系统事件消息。
  void addMembers(
    String groupId,
    List<String> characterIds, {
    List<String>? names,
  }) {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1 || characterIds.isEmpty) return;
    final cur = _groups[index].memberCharacterIds;
    final merged = <String>[...cur];
    for (final id in characterIds) {
      if (!merged.contains(id)) merged.add(id);
    }
    _groups[index] = _groups[index].copyWith(memberCharacterIds: merged);
    for (var i = 0; i < characterIds.length; i++) {
      final id = characterIds[i];
      if (cur.contains(id)) continue; // 本就在群内，未实际加入，不生成事件
      final name = (names != null && i < names.length && names[i].isNotEmpty)
          ? names[i]
          : id;
      _addSystemMessage(groupId, '「$name」加入了群聊');
    }
    notifyListeners();
    _persist();
  }

  /// 移出群成员。[names] 与 [characterIds] 一一对应（角色显示名，用于事件气泡）；
  /// 实际被移出的成员会生成一条「XX 已被移出群聊」系统事件消息。
  void removeMembers(
    String groupId,
    List<String> characterIds, {
    List<String>? names,
  }) {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1 || characterIds.isEmpty) return;
    final removed = characterIds.toSet();
    final before = _groups[index].memberCharacterIds;
    _groups[index] = _groups[index].copyWith(
      memberCharacterIds: before.where((id) => !removed.contains(id)).toList(),
    );
    for (var i = 0; i < characterIds.length; i++) {
      final id = characterIds[i];
      if (!before.contains(id)) continue; // 本就不在群内，不生成事件
      final name = (names != null && i < names.length && names[i].isNotEmpty)
          ? names[i]
          : id;
      _addSystemMessage(groupId, '「$name」已被移出群聊');
    }
    notifyListeners();
    _persist();
  }

  /// 插入一条群聊系统事件消息（如成员加入/移除）：
  /// 列表中以居中灰色小气泡展示（ChatBubble 专门渲染 system 类型），
  /// 不进入 LLM 回复上下文，仅作会话内提示。
  void _addSystemMessage(String groupId, String content) {
    _messages[groupId] ??= [];
    _messages[groupId]!.add(Message(
      id: const Uuid().v4(),
      conversationId: groupId,
      content: content,
      type: MessageType.system,
      sender: MessageSender.character,
    ));
    _updateLastMessage(groupId, content);
  }

  void deleteGroup(String groupId) {
    _groups.removeWhere((g) => g.id == groupId);
    _messages.remove(groupId);
    if (_replyingGroupId == groupId) {
      _replyGeneration++;
      _replyingGroupId = null;
    }
    notifyListeners();
    _persist();
  }

  void setPinned(String groupId, bool pinned) {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1 || _groups[index].pinned == pinned) return;
    _groups[index] = _groups[index].copyWith(pinned: pinned);
    notifyListeners();
    _persist();
  }

  /// 设置群聊上下文条数：null=跟随全局聊天设置；0=无限制；>0=最近 N 条。
  /// 直接重建 GroupChat 以支持把 override 清回 null（copyWith 无法清空）。
  Future<void> setContextCount(String groupId, int? count) async {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1 || _groups[index].contextCount == count) return;
    final g = _groups[index];
    _groups[index] = GroupChat(
      id: g.id,
      name: g.name,
      avatar: g.avatar,
      description: g.description,
      contextCount: count,
      silenceProbability: g.silenceProbability,
      quoteProbability: g.quoteProbability,
      memberCharacterIds: g.memberCharacterIds,
      lastMessage: g.lastMessage,
      lastMessageTime: g.lastMessageTime,
      pinned: g.pinned,
      unreadCount: g.unreadCount,
      createdAt: g.createdAt,
    );
    notifyListeners();
    await _persist();
  }

  /// 设置角色不说话概率（0~1）：每轮每个未被 @ 的角色以此概率保持沉默。
  Future<void> setSilenceProbability(String groupId, double value) async {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) return;
    final g = _groups[index];
    _groups[index] = GroupChat(
      id: g.id,
      name: g.name,
      avatar: g.avatar,
      description: g.description,
      contextCount: g.contextCount,
      silenceProbability: value,
      quoteProbability: g.quoteProbability,
      memberCharacterIds: g.memberCharacterIds,
      lastMessage: g.lastMessage,
      lastMessageTime: g.lastMessageTime,
      pinned: g.pinned,
      unreadCount: g.unreadCount,
      createdAt: g.createdAt,
    );
    notifyListeners();
    await _persist();
  }

  /// 设置角色引用回复概率（0~1）：发言时以此概率引用最近其他成员的消息。
  Future<void> setQuoteProbability(String groupId, double value) async {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) return;
    final g = _groups[index];
    _groups[index] = GroupChat(
      id: g.id,
      name: g.name,
      avatar: g.avatar,
      description: g.description,
      contextCount: g.contextCount,
      silenceProbability: g.silenceProbability,
      quoteProbability: value,
      memberCharacterIds: g.memberCharacterIds,
      lastMessage: g.lastMessage,
      lastMessageTime: g.lastMessageTime,
      pinned: g.pinned,
      unreadCount: g.unreadCount,
      createdAt: g.createdAt,
    );
    notifyListeners();
    await _persist();
  }

  // ── 消息 ──

  /// 用户发送消息（第一阶段：仅入库，不触发回复）。
  /// [quoteContent]/[quoteSender] 为引用消息内容（非空时气泡上方显示引用块）。
  Future<void> sendMessage({
    required String groupId,
    required String content,
    String quoteContent = '',
    String quoteSender = '',
  }) async {
    final msg = Message(
      id: const Uuid().v4(),
      conversationId: groupId,
      content: content,
      sender: MessageSender.user,
      quoteContent: quoteContent,
      quoteSender: quoteSender,
    );
    _messages[groupId] ??= [];
    _messages[groupId]!.add(msg);
    _updateLastMessage(groupId, content);
    _lastError = null;
    notifyListeners();
    await _persist();
  }

  /// 导入聊天记录 zip（群聊）：解析结果直接追加到群内消息列表，
  /// 含各角色的发送者信息（senderCharacterId/senderName）以还原多角色发言。
  Future<void> importMessages({
    required String groupId,
    required List<Message> messages,
  }) async {
    if (messages.isEmpty) return;
    _messages[groupId] ??= [];
    _messages[groupId]!.addAll(messages);
    _refreshLastMessage(groupId);
    notifyListeners();
    await _persist();
  }

  /// 发送图片消息（用户）：本地插入图片气泡，不触发回复，
  /// 由用户点击对号后群内角色在上下文中感知到「用户发送了图片」。
  Future<void> sendImageMessage({
    required String groupId,
    required String imagePath,
  }) async {
    final msg = Message(
      id: const Uuid().v4(),
      conversationId: groupId,
      content: imagePath,
      type: MessageType.image,
      sender: MessageSender.user,
    );
    _messages[groupId] ??= [];
    _messages[groupId]!.add(msg);
    _updateLastMessage(groupId, '[图片]');
    _lastError = null;
    notifyListeners();
    await _persist();
  }

  /// 发送文件消息（用户）：本地插入文件气泡，不触发回复。
  Future<void> sendFileMessage({
    required String groupId,
    required String filePath,
    required String fileName,
  }) async {
    final msg = Message(
      id: const Uuid().v4(),
      conversationId: groupId,
      content: filePath,
      type: MessageType.file,
      sender: MessageSender.user,
    );
    _messages[groupId] ??= [];
    _messages[groupId]!.add(msg);
    _updateLastMessage(groupId, '[文件] $fileName');
    _lastError = null;
    notifyListeners();
    await _persist();
  }

  /// 删除单条消息（角色消息长按删除）：移除后不再作为群聊上下文。
  void deleteMessage(String groupId, String messageId) {
    final messages = _messages[groupId];
    if (messages == null) return;
    messages.removeWhere((m) => m.id == messageId);
    _refreshLastMessage(groupId);
    notifyListeners();
    _persist();
  }

  /// 撤回用户消息：删除该消息并中断进行中的回复轮（消息已被撤走，
  /// 旧轮的回复不应再落到群里）。
  void withdrawMessage(String groupId, String messageId) {
    _replyGeneration++; // 中断进行中的回复轮
    _replyingGroupId = null;
    final messages = _messages[groupId];
    if (messages == null) return;
    messages.removeWhere((m) => m.id == messageId);
    _refreshLastMessage(groupId);
    notifyListeners();
    _persist();
  }

  /// 删除/撤回后按剩余消息重建会话摘要与时间。
  void _refreshLastMessage(String groupId) {
    final messages = _messages[groupId] ?? const <Message>[];
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) return;
    final last = messages.isNotEmpty ? messages.last : null;
    _groups[index] = _groups[index].copyWith(
      lastMessage: last == null ? '' : _lastMessagePreview(last),
      lastMessageTime: last?.createdAt ?? DateTime.now(),
    );
  }

  /// 会话列表展示用的消息预览（图片/文件显示占位文案）。
  String _lastMessagePreview(Message m) {
    switch (m.type) {
      case MessageType.image:
        return '[图片]';
      case MessageType.file:
        return '[文件] ${m.content.split('/').last}';
      case MessageType.text:
      case MessageType.system:
        return m.content;
    }
  }

  void _updateLastMessage(String groupId, String content) {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index != -1) {
      _groups[index] = _groups[index].copyWith(
        lastMessage: content,
        lastMessageTime: DateTime.now(),
      );
    }
  }

  /// 群聊回复调度（第二阶段：对号提交触发）。
  ///
  /// 每次调用自增 [generation]，正在进行的上一轮在下一个 await 后检测到
  /// 序号变化即退出（软中断：已发出的 HTTP 无法取消，靠序号丢弃过期结果）。
  /// [members] 为参与回复的角色快照：被 @ 的角色排最前且必定发言，
  /// 其余角色按「不说话概率」随机沉默，发言者用该角色自己的模型生成回复。
  Future<void> runGroupReply({
    required String groupId,
    required List<GroupMemberReply> members,
    required String userNickname,
    int contextCount = 10,
    // @ 提及的角色：优先发言且必定回复（跳过插话判定）
    List<String> mentionedCharacterIds = const [],
  }) async {
    final generation = ++_replyGeneration;
    _replyingGroupId = groupId;
    _lastError = null;
    notifyListeners();

    final random = Random();
    // 不说话概率：每轮每个未被 @ 的角色以此概率随机保持沉默
    final silenceRate = getGroupById(groupId)?.silenceProbability ?? 0.2;
    // 排序：被 @ 的角色排最前（必定发言），其余角色随机顺序 + 概率沉默
    final mentionedSet = mentionedCharacterIds.toSet();
    final ordered = <GroupMemberReply>[
      for (final m in members)
        if (mentionedSet.contains(m.characterId)) m,
      ...members
          .where((m) => !mentionedSet.contains(m.characterId))
          .toList()
        ..shuffle(random),
    ];

    for (final member in ordered) {
      if (generation != _replyGeneration) break; // 被打断
      try {
        final systemPrompt =
            _buildGroupSystemPrompt(groupId, member, userNickname);
        final history = _buildGroupHistory(groupId, contextCount);

        final isMentioned = mentionedSet.contains(member.characterId);
        // 未 @ 的角色按「不说话概率」随机决定是否沉默（不再调用 LLM 判定插话，
        // 避免无外部指令时成员集体不说话）；被 @ 的角色必定发言。
        if (!isMentioned && random.nextDouble() < silenceRate) {
          continue;
        }

        // 角色可以选择回复上文其他成员的消息：只在最近 5 条内随机选取一条
        // 其他成员文本消息作为引用目标（按群配置的引用概率触发，默认 20%），
        // 避免话题已过仍引用旧消息；生成时提示围绕该消息回复，
        // 落库时带上引用块（quoteContent/quoteSender），与用户引用同格式展示。
        final quoteRate = getGroupById(groupId)?.quoteProbability ?? 0.2;
        final quote = random.nextDouble() < quoteRate
            ? _pickQuoteTarget(groupId, member.characterId)
            : null;

        var outputInstruction = PromptBuilder.buildOutputInstruction(
          characterName: member.name,
          replyToUser: true,
        );
        // 群聊中只允许输出自己的新内容：防止模型复述/转述其他成员的发言
        outputInstruction =
            '只输出 $member.name 自己的新内容，不要复述或转述群内其他人刚说过的话。$outputInstruction';
        if (isMentioned) {
          outputInstruction = '用户刚在群里 @了你，请立刻回应 ta。$outputInstruction';
        }
        if (quote != null) {
          outputInstruction = '你想回应群友「${quote.name}」刚说的话：'
              '"${quote.content}"，请围绕这条消息回复。$outputInstruction';
        }

        final result = await LLMService.generateMessages(
          model: member.model,
          systemPrompt: systemPrompt,
          historyMessages: history,
          outputInstruction: outputInstruction,
        );
        if (generation != _replyGeneration) break;
        // 累计该群真实 token 用量（发送 = prompt_tokens，接收 = completion_tokens）
        TokenUsageProvider.instance.addUsage(groupId, result.usage);

        for (var i = 0; i < result.messages.length; i++) {
          if (generation != _replyGeneration) break;
          final content = result.messages[i];
          _addGroupMessage(
            groupId,
            member.characterId,
            member.name,
            content,
            // 仅首条消息带引用块，避免连续多条都带引用显得累赘
            quoteContent: i == 0 ? (quote?.content ?? '') : '',
            quoteSender: i == 0 ? (quote?.name ?? '') : '',
            avatarBase64: member.avatarBase64,
            // 回复轮内不逐条落盘，整轮结束后统一写一次
            persist: false,
          );
          // 模拟打字耗时 + 消息间隔，贴近群聊逐条弹出观感
          final delay =
              random.nextDouble() * 800 + content.length * 40 + 500;
          await Future.delayed(Duration(milliseconds: delay.round()));
        }
      } on LLMException catch (e) {
        if (generation != _replyGeneration) break;
        _lastError = e.message;
        notifyListeners();
      } catch (e) {
        if (generation != _replyGeneration) break;
        _lastError = LLMService.describeException(e);
        notifyListeners();
      }
    }

    _replyingGroupId = null;
    notifyListeners();
    // 整个回复轮合并为一次落盘：避免长聊天下每条角色消息都触发
    // 全量 JSON 序列化（上千条消息时尤其明显），从而减少 UI 卡顿
    await _persist();
  }

  /// 从群内最近消息中随机选一条「其他成员」的文本消息作为引用目标。
  /// 只选非本成员、非系统的文本消息；没有可引用的内容时返回 null。
  _QuoteTarget? _pickQuoteTarget(
    String groupId,
    String selfCharacterId,
  ) {
    final messages = _messages[groupId] ?? const <Message>[];
    if (messages.isEmpty) return null;
    // 只从最近 5 条内选引用目标，确保引用贴近当前话题，避免翻旧账
    final start = messages.length > 5 ? messages.length - 5 : 0;
    final candidates = <Message>[];
    for (var i = start; i < messages.length; i++) {
      final m = messages[i];
      if (m.isFromUser || m.type != MessageType.text) continue;
      if (m.senderCharacterId == selfCharacterId) continue; // 不引用自己
      if (m.content.trim().isEmpty) continue;
      candidates.add(m);
    }
    if (candidates.isEmpty) return null;
    final target = candidates[Random().nextInt(candidates.length)];
    return _QuoteTarget(
      name: target.senderName.isEmpty ? '角色' : target.senderName,
      content: target.content,
    );
  }

  void _addGroupMessage(
    String groupId,
    String characterId,
    String name,
    String content, {
    String quoteContent = '',
    String quoteSender = '',
    String avatarBase64 = '',
    bool persist = true,
  }) {
    if (content.trim().isEmpty) return;
    _messages[groupId] ??= [];
    _messages[groupId]!.add(Message(
      id: const Uuid().v4(),
      conversationId: groupId,
      content: content,
      sender: MessageSender.character,
      senderCharacterId: characterId,
      senderName: name,
      quoteContent: quoteContent,
      quoteSender: quoteSender,
    ));
    _updateLastMessage(groupId, content);
    // 用户不在该群页面时记未读并发送系统通知
    if (_activeGroupId != groupId) {
      final unreadCount = _increaseGroupUnread(groupId);
      NotificationService.instance.showCharacterNotification(
        conversationId: groupId,
        characterName: name,
        content: content,
        unreadCount: unreadCount,
        avatarBase64: avatarBase64,
      );
    }
    notifyListeners();
    if (persist) _persist();
  }

  /// 新增角色消息时：若用户不在该群页面则未读 +1
  int _increaseGroupUnread(String groupId) {
    if (_activeGroupId == groupId) return 0;
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) return 0;
    final count = _groups[index].unreadCount + 1;
    _groups[index] = _groups[index].copyWith(unreadCount: count);
    return count;
  }

  /// 群聊系统提示词：人设（角色系统提示词）+ 群名/简介 + 用户信息 +
  /// 群聊语境 + 口语化短消息要求；沉默规则由角色活跃时段决定。
  String _buildGroupSystemPrompt(
    String groupId,
    GroupMemberReply m,
    String userNickname,
  ) {
    final group = getGroupById(groupId);
    final groupName = group?.name.trim().isEmpty == false
        ? group!.name.trim()
        : '群聊';
    final groupDescription = group?.description.trim() ?? '';
    final memory = m.memoryPoints
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    // 角色人设（角色系统提示词）：必须拼入，否则回复不贴人设
    final persona = m.systemPrompt.trim();
    // 活跃时段：命中时要求保持活跃、禁止沉默（与私聊一致）；
    // 未设置活跃时段时维持"按时间合理与否"的兜底判断
    final active =
        PromptBuilder.inActivePeriod(now, m.activeStart, m.activeEnd);
    final activeLine = active
        ? '当前正处于你的活跃时段（${m.activeStart} ~ ${m.activeEnd}）内：'
            '即使时间看起来较晚，也绝对不要道别、说晚安或提前结束，保持活跃地自然回应。'
        : '结合"当前时间"和你的"人设作息"判断：如果当前时间极不合理'
            '（如凌晨3点且你不是夜猫子），可以保持沉默。';
    final base = persona.isEmpty
        ? '你是 ${m.name}，正在微信群「$groupName」里，和用户「$userNickname」'
            '以及其他角色一起聊天。'
        : persona;
    final extra = m.memoryPool.trim();
    return '''
$base

（以下是你在微信群「$groupName」里的聊天指令）
群简介：${groupDescription.isEmpty ? '（无）' : groupDescription}
你们的关系：${m.userRelationship.isEmpty ? '普通朋友' : m.userRelationship}
${memory.isEmpty ? '' : '''
## 用户长期记忆
${memory.map((e) => '- $e').join('\n')}'''}
${extra.isEmpty ? '' : '\n$extra\n'}
## 当前时间
$time

## 群聊回复要求
1. 消息必须极度口语化，像真实微信群聊，允许语气词、表情包文字（如[捂脸]）或不规范大小写。
2. 针对群聊中的最新内容，把想说的话拆分为 1~3 条短消息，每条 5~15 个字，最多不超过 20 个字。
3. 只输出你自己想说的话：严禁复述、转述、总结或引用其他成员的发言内容，也不要出现"XX说……"之类的句式。
4. $activeLine'''.trim();
  }

  /// 构建群聊上下文（供模型理解语境）：用户消息 role=user，
  /// 角色消息 role=assistant 并带发送者名前缀，便于区分是谁说的。
  List<Map<String, Object>> _buildGroupHistory(String groupId, int contextCount) {
    final messages = _messages[groupId] ?? const <Message>[];
    final start = contextCount > 0 && messages.length > contextCount
        ? messages.length - contextCount
        : 0;
    final result = <Map<String, Object>>[];
    for (int i = start; i < messages.length; i++) {
      final m = messages[i];
      // 系统事件（成员加入/移除）：以「群通知」形式进入上下文，
      // 让角色感知群成员变化（如新人入群、有人退群）
      if (m.type == MessageType.system) {
        result.add({'role': 'user', 'content': '【群通知】${m.content}'});
        continue;
      }
      if (m.isFromUser) {
        switch (m.type) {
          case MessageType.image:
            // 用户发的图片无法随文本传给各角色模型（群内模型可能不支持视觉），
            // 以文本提示占位，让角色感知"用户刚发了一张图片"
            result.add({'role': 'user', 'content': '[用户发送了一张图片]'});
          case MessageType.file:
            result.add({
              'role': 'user',
              'content': '[用户发送了一个文件：${m.content.split('/').last}]',
            });
          case MessageType.text:
          case MessageType.system:
            result.add({'role': 'user', 'content': m.content});
        }
      } else {
        final name = m.senderName.isEmpty ? '角色' : m.senderName;
        result.add({'role': 'assistant', 'content': '$name：${m.content}'});
      }
    }
    return result;
  }
}
