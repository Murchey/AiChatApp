import 'dart:math';
import '../models/character.dart';
import '../models/moment.dart';
import '../models/user.dart';
import '../providers/api_provider.dart';
import '../providers/auto_moment_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/group_chat_provider.dart';
import '../providers/memory_point_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../providers/proactive_greeting_provider.dart';
import '../providers/token_usage_provider.dart';
import 'dev_log_service.dart';
import 'llm_service.dart';
import 'moment_ai_service.dart';
import 'notification_service.dart';

/// 角色自动发朋友圈调度器。
///
/// 采用「前台补发布」策略：应用启动 / 回到前台时调用 [checkAndPublish]，
/// 扫描所有开启该功能的角色，对已到期的角色执行「生成文案 → 发布」。
/// 全部发布完成后，再串行触发其他角色的点赞/评论互动（复用 [MomentAiService]）。
///
/// 性能约束：全程串行，一次只发一个 LLM 请求；网络 async 不阻塞 UI，
/// 失败静默跳过并记录日志，不弹 Toast 干扰用户。
class AutoMomentService {
  AutoMomentService._();
  static final AutoMomentService instance = AutoMomentService._();

  bool _running = false;

  /// 低频（一周<7条）补发积压的上限：最多一次补发 3 条，
  /// 防止用户长时间未打开时一次刷出过多动态。
  static const int maxCatchupCount = 3;

  /// 扫描并补发布已到期的角色朋友圈。
  Future<void> checkAndPublish({
    required CharacterProvider characterProvider,
    required ApiProvider apiProvider,
    required ChatProvider chatProvider,
    required ChatSettingsProvider chatSettings,
    required GroupChatProvider groupChatProvider,
    required MomentNotificationProvider notificationProvider,
    required AutoMomentProvider autoMomentProvider,
    required MemoryPointProvider memoryPointProvider,
    User? user,
  }) async {
    if (_running) return;
    _running = true;
    try {
      final model = apiProvider.getModelById(apiProvider.momentModelId);
      if (model == null) {
        DevLogService.instance.log('自动发朋友圈：未配置「朋友圈互动」模型，跳过');
        return;
      }

      final now = DateTime.now();
      final toPublish = <(Character, Moment)>[];

      // 第一阶段：串行生成 + 发布（每个角色一次 LLM 请求）
      for (final character in characterProvider.manageableCharacters) {
        final config = autoMomentProvider.configFor(character.id);
        if (!config.enabled) continue;

        final subInterval = _subIntervalHours(config);
        final dueAt = config.nextDueAt;

        // 首次开启：初始化排期（不立刻发），等满一个子间隔
        if (dueAt == null) {
          await _advanceNextDue(
            autoMomentProvider,
            character.id,
            now,
            subInterval,
          );
          continue;
        }
        // 未到期
        if (dueAt.isAfter(now)) continue;

        // 到期：重新读取最新角色快照，避免用旧数据覆盖
        final latest = characterProvider.getCharacterById(character.id);
        if (latest == null) continue;

        // 积压条数（含当前这条）：从上次到期至今过了几个子间隔
        final elapsedMinutes = now.difference(dueAt).inMinutes;
        final missed = (elapsedMinutes / (subInterval * 60)).floor() + 1;

        // 高频（一周≥7条，子间隔≤24h）：错过多条时不补发积压，
        // 把排期后延到下一个子间隔，保持密度但不刷屏；只错过 1 条时正常补发。
        if (subInterval <= 24 && missed >= 2) {
          DevLogService.instance.log(
              '「${latest.displayName}」自动朋友圈积压 $missed 条（高频），'
              '不补发，排期后延');
          await _advanceNextDue(
            autoMomentProvider,
            character.id,
            now,
            subInterval,
          );
          continue;
        }

        // 本次要发布的条数：
        // - 高频（子间隔≤24h）：最多补发当前这条（积压≥2 已在上方后延）；
        // - 低频（子间隔>24h）：允许补发积压，但上限 maxCatchupCount 条，
        //   防止长时间未打开时一次刷出过多动态。
        final catchupCount =
            subInterval <= 24 ? 1 : min(missed, AutoMomentService.maxCatchupCount);

        for (var i = 0; i < catchupCount; i++) {
          try {
            final chatHistory = chatProvider.getRecentHistoryForCharacter(
              character.id,
              chatSettings.contextCount,
            );
            // 角色的持久化记忆点：与聊天一样随系统提示词发送，让角色发
            // 朋友圈时同样记住这些长期信息
            final memoryPoints = memoryPointProvider
                .pointsFor(character.id)
                .map((p) => p.content)
                .toList();
            final content = await _generateContent(
              model: model,
              character: latest,
              chatHistory: chatHistory,
              memoryPoints: memoryPoints,
            );
            if (content != null && content.isNotEmpty) {
              // 补发时间戳：按子间隔从最早错过时刻均匀错开到 now，
              // 避免多条补发挤在同一时刻（朋友圈按 createdAt 降序展示）
              final createdAt = i == catchupCount - 1
                  ? now
                  : now.subtract(Duration(
                      minutes: ((catchupCount - 1 - i) * subInterval * 60)
                          .round()));
              final moment = await _publishMoment(
                characterProvider: characterProvider,
                character: latest,
                content: content,
                visibility: config.visibility,
                createdAt: createdAt,
              );
              DevLogService.instance
                  .log('「${latest.displayName}」自动发布朋友圈：$content');
              toPublish.add((latest, moment));
            } else {
              DevLogService.instance
                  .log('「${latest.displayName}」自动朋友圈文案为空，跳过本次');
            }
          } catch (e) {
            DevLogService.instance.log(
                '「${character.displayName}」自动朋友圈生成失败：'
                '${LLMService.describeException(e)}');
          }
        }
        // 无论成功失败都推进下次到期，避免同一角色反复重试
        await _advanceNextDue(
          autoMomentProvider,
          character.id,
          now,
          subInterval,
        );
      }

      // 第二阶段：串行触发其他角色的点赞/评论互动（按动态可见范围，排除发布者本人）
      for (final (owner, moment) in toPublish) {
        final visible =
            MomentAiService.visibleCharacters(characterProvider, moment.visibility)
                .where((c) => c.id != owner.id)
                .toList();
        if (visible.isEmpty) continue;
        await MomentAiService.run(
          characterProvider: characterProvider,
          apiProvider: apiProvider,
          notificationProvider: notificationProvider,
          chatProvider: chatProvider,
          chatSettings: chatSettings,
          groupChatProvider: groupChatProvider,
          memoryPointProvider: memoryPointProvider,
          user: user,
          moment: moment,
          characters: visible,
          momentOwnerId: owner.id,
        );
      }
    } finally {
      _running = false;
    }
  }

  /// 子间隔（小时）= 周期 ÷ 周期内条数
  double _subIntervalHours(AutoMomentConfig config) {
    final count = config.count.clamp(1, AutoMomentProvider.maxCount);
    return config.periodHours / count;
  }

  /// 推进下一次到期时间：子间隔 ± 30% 随机抖动，避免多角色扎堆
  Future<void> _advanceNextDue(
    AutoMomentProvider provider,
    String characterId,
    DateTime now,
    double subIntervalHours,
  ) async {
    final jitter = (Random().nextDouble() * 0.6) - 0.3; // -0.3 ~ +0.3
    final nextHours = subIntervalHours * (1 + jitter);
    await provider.setNextDueAt(
      characterId,
      now.add(Duration(minutes: (nextHours * 60).round())),
    );
  }

  /// 扫描并触发主动问候。
  ///
  /// [force] 为 true 时跳过所有检查（nextDueAt / 空闲时长），直接为每个
  /// 已开启的角色生成一条问候消息，用于开发者快速测试。
  Future<void> checkProactiveGreeting({
    required CharacterProvider characterProvider,
    required ApiProvider apiProvider,
    required ChatProvider chatProvider,
    required ChatSettingsProvider chatSettings,
    required ProactiveGreetingProvider greetingProvider,
    required MemoryPointProvider memoryPointProvider,
    bool force = false,
  }) async {
    try {
      // 优先使用朋友圈互动模型，其次取第一个可用模型
      final model = apiProvider.getModelById(apiProvider.momentModelId) ??
          (apiProvider.models.isNotEmpty ? apiProvider.models.first : null);
      if (model == null) {
        DevLogService.instance.log('主动问候：未配置可用模型，跳过');
        return;
      }

      final now = DateTime.now();
      var triggered = 0;

      for (final character in characterProvider.manageableCharacters) {
        final config = greetingProvider.configFor(character.id);
        if (!config.enabled) continue;

        if (!force) {
          // 正常模式：检查 nextDueAt 和空闲时长
          final dueAt = config.nextDueAt;
          if (dueAt != null && dueAt.isAfter(now)) continue;

          // 首次开启：初始化排期
          if (dueAt == null) {
            final nextCheck = now.add(Duration(hours: config.idleHours));
            await greetingProvider.setNextDueAt(character.id, nextCheck);
            continue;
          }

          // 获取最后消息时间
          final lastMsgTime =
              chatProvider.getLastMessageTimeForCharacter(character.id);

          // 从未聊过天：跳过
          if (lastMsgTime == null) {
            await _advanceGreetingNextDue(greetingProvider, character.id, now);
            continue;
          }

          // 计算空闲时长
          final idleHours = now.difference(lastMsgTime).inHours;

          // 未达到空闲阈值：跳过
          if (idleHours < config.idleHours) {
            await _advanceGreetingNextDue(greetingProvider, character.id, now);
            continue;
          }
        }

        // 计算空闲时长（用于生成上下文，force 模式下可能为 0）
        final lastMsgTime =
            chatProvider.getLastMessageTimeForCharacter(character.id);
        final idleHours = lastMsgTime != null
            ? now.difference(lastMsgTime).inHours
            : config.idleHours;

        DevLogService.instance.log(
          '主动问候：触发「${character.displayName}」'
          '${force ? '（开发者模式）' : '（空闲 ${idleHours}h）'}',
        );

        // 获取聊天记录上下文
        final chatHistory =
            chatProvider.getRecentHistoryForCharacter(character.id, 5);
        final memoryPoints =
            memoryPointProvider.pointsFor(character.id).map((p) => p.content).toList();

        // 生成问候内容
        final content = await _generateGreeting(
          model: model,
          character: character,
          chatHistory: chatHistory,
          memoryPoints: memoryPoints,
          idleHours: idleHours,
        );

        if (content == null || content.isEmpty) {
          DevLogService.instance.log(
            '主动问候：「${character.displayName}」生成内容为空，跳过',
          );
          if (!force) {
            await _advanceGreetingNextDue(greetingProvider, character.id, now);
          }
          continue;
        }

        // 发送消息到聊天中（作为角色发送）
        final conversation = chatProvider.getOrCreateConversation(
          characterId: character.id,
          characterName: character.displayName,
          characterAvatar: character.avatar,
        );
        await chatProvider.sendGreetingMessage(
          conversationId: conversation.id,
          characterId: character.id,
          content: content,
        );

        // 发送系统通知提醒用户
        await NotificationService.instance.showCharacterNotification(
          conversationId: conversation.id,
          characterName: character.displayName,
          content: content,
          unreadCount: 1,
          avatarBase64: character.avatar,
        );

        triggered++;
        DevLogService.instance.log(
          '主动问候：「${character.displayName}」已发送问候消息',
        );

        // 推进下次检查时间
        if (!force) {
          await _advanceGreetingNextDue(greetingProvider, character.id, now);
        }
      }

      DevLogService.instance.log(
        '主动问候：完成，共触发 $triggered 个角色'
        '${force ? '（开发者模式）' : ''}',
      );
    } catch (e) {
      DevLogService.instance.log('主动问候检查异常：$e');
    }
  }

  /// 推进主动问候下次检查时间：idleHours ± 30% 随机抖动
  Future<void> _advanceGreetingNextDue(
    ProactiveGreetingProvider provider,
    String characterId,
    DateTime now,
  ) async {
    final config = provider.configFor(characterId);
    final jitter = (Random().nextDouble() * 0.6) - 0.3; // -0.3 ~ +0.3
    final nextHours = config.idleHours * (1 + jitter);
    await provider.setNextDueAt(
      characterId,
      now.add(Duration(hours: nextHours.round())),
    );
  }

  /// 生成主动问候消息内容。
  Future<String?> _generateGreeting({
    required ApiModel model,
    required Character character,
    required List<Map<String, String>> chatHistory,
    List<String> memoryPoints = const [],
    required int idleHours,
  }) async {
    final system = _systemWithMemory(
      character.systemPrompt,
      memoryPoints,
      fallback: '你是「${character.displayName}」。',
    );

    final idleDesc = idleHours >= 24
        ? '${(idleHours / 24).round()}天'
        : '$idleHours小时';

    final messages = <Map<String, Object>>[
      {'role': 'system', 'content': system},
      {
        'role': 'user',
        'content': '（系统提示：用户已经 $idleDesc 没有和你聊天了。'
            '请以「${character.displayName}」的身份，主动给用户发一条问候消息。'
            '要求：自然、温暖、符合角色性格，不要太长，像真人朋友发消息一样。'
            '只输出消息内容，不要加任何前缀或解释。）',
      },
    ];

    try {
      final result = await LLMService.fetchCompletion(
        model: model,
        messages: messages,
        temperature: 0.85,
        maxTokens: 200,
      );
      TokenUsageProvider.instance.addUsage(
        TokenUsageProvider.kMomentUsageId,
        result.usage,
      );
      final content = result.content.trim();
      return content.isEmpty ? null : content;
    } catch (e) {
      DevLogService.instance.log('主动问候生成失败：$e');
      return null;
    }
  }

  /// 生成一条符合角色人设的朋友圈文案（纯文字）。
  /// 有聊天记录时优先贴合最近语境；无聊天记录时让 AI 捏造日常小故事。
  /// [memoryPoints] 为角色的持久化记忆点，随系统提示词发送，让角色发帖
  /// 时同样记住这些长期信息。
  Future<String?> _generateContent({
    required ApiModel model,
    required Character character,
    required List<Map<String, String>> chatHistory,
    List<String> memoryPoints = const [],
  }) async {
    final system = _systemWithMemory(
      character.systemPrompt,
      memoryPoints,
      fallback: '你是「${character.displayName}」，正在发一条朋友圈。',
    );
    final messages = <Map<String, Object>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': _buildPrompt(character, chatHistory)},
    ];
    final result = await LLMService.fetchCompletion(
      model: model,
      messages: messages,
      temperature: 0.9,
      maxTokens: 200,
    );
    // 累计该次自动发帖消耗
    TokenUsageProvider.instance.addUsage(TokenUsageProvider.kMomentUsageId, result.usage);
    final content = result.content.trim();
    return content.isEmpty ? null : content;
  }

  String _buildPrompt(
    Character character,
    List<Map<String, String>> chatHistory,
  ) {
    final relationship = character.userRelationship.trim();
    final buf = StringBuffer();
    buf.writeln('请你以「${character.displayName}」的身份，发一条朋友圈动态。');
    buf.writeln('要求：');
    buf.writeln('- 只输出朋友圈文案本身，不要加任何解释、引号或前缀');
    buf.writeln('- 文案自然口语化、符合角色性格，15~80 字左右');
    buf.writeln('- 不要出现表情代码或 Markdown 标记');
    if (relationship.isNotEmpty) {
      buf.writeln('- 你与用户的关系：$relationship');
    }
    buf.writeln();
    if (chatHistory.isNotEmpty) {
      buf.writeln('参考你与该用户最近的聊天内容，让这条朋友圈与你们的语境自然相关：');
      for (final m in chatHistory) {
        final speaker = m['role'] == 'user' ? '用户' : character.displayName;
        buf.writeln('$speaker：${m['content']}');
      }
    } else {
      buf.writeln('你与该用户还没有聊天记录，请根据你的角色设定，'
          '捏造一个符合你日常的小故事或心情作为朋友圈内容。');
    }
    return buf.toString();
  }

  /// 将角色的持久化记忆点追加到系统提示词之后（无记忆点时返回基础提示词）。
  /// 语义与聊天一致：这些是用户主动保存的重要约定与共同经历，角色需牢记。
  static String _systemWithMemory(
    String basePrompt,
    List<String> memoryPoints, {
    required String fallback,
  }) {
    final base = basePrompt.trim().isEmpty ? fallback : basePrompt.trim();
    final section = _memoryPointsSection(memoryPoints);
    if (section.isEmpty) return base;
    return '$base\n\n$section';
  }

  /// 组装「长期记忆」段落（无记忆点时返回空串）。
  static String _memoryPointsSection(List<String> memoryPoints) {
    final memory = memoryPoints
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
    if (memory.isEmpty) return '';
    return '## 你的长期记忆\n'
        '这些是用户主动保存的、关于你们之间重要约定与经历的长期记忆，'
        '请在互动中牢记并自然运用：\n'
        '${memory.map((m) => '- $m').join('\n')}';
  }

  /// 往角色自己的朋友圈列表头部插入一条动态（朋友圈 feed 会自动聚合展示）。
  /// [createdAt] 默认取当前时间；补发积压时可传入错开的历史时间戳，
  /// 让多条补发在 feed 中按时间自然排开。
  Future<Moment> _publishMoment({
    required CharacterProvider characterProvider,
    required Character character,
    required String content,
    required String visibility,
    DateTime? createdAt,
  }) async {
    final moment = Moment(
      id: 'auto_${DateTime.now().microsecondsSinceEpoch}',
      content: content,
      visibility: visibility,
      createdAt: createdAt ?? DateTime.now(),
    );
    await characterProvider.updateMoments(character.id, [
      moment,
      ...character.moments,
    ]);
    return moment;
  }
}
