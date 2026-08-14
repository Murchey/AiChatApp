import 'dart:math';
import '../models/character.dart';
import '../models/moment.dart';
import '../providers/api_provider.dart';
import '../providers/auto_moment_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/moment_notification_provider.dart';
import 'dev_log_service.dart';
import 'llm_service.dart';
import 'moment_ai_service.dart';

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

  /// 扫描并补发布已到期的角色朋友圈。
  Future<void> checkAndPublish({
    required CharacterProvider characterProvider,
    required ApiProvider apiProvider,
    required ChatProvider chatProvider,
    required ChatSettingsProvider chatSettings,
    required MomentNotificationProvider notificationProvider,
    required AutoMomentProvider autoMomentProvider,
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

        try {
          final chatHistory = chatProvider.getRecentHistoryForCharacter(
            character.id,
            chatSettings.contextCount,
          );
          final content = await _generateContent(
            model: model,
            character: latest,
            chatHistory: chatHistory,
          );
          if (content != null && content.isNotEmpty) {
            final moment = await _publishMoment(
              characterProvider: characterProvider,
              character: latest,
              content: content,
              visibility: config.visibility,
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

  /// 生成一条符合角色人设的朋友圈文案（纯文字）。
  /// 有聊天记录时优先贴合最近语境；无聊天记录时让 AI 捏造日常小故事。
  Future<String?> _generateContent({
    required ApiModel model,
    required Character character,
    required List<Map<String, String>> chatHistory,
  }) async {
    final system = character.systemPrompt.trim().isEmpty
        ? '你是「${character.displayName}」，正在发布一条朋友圈。'
        : character.systemPrompt;
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

  /// 往角色自己的朋友圈列表头部插入一条动态（朋友圈 feed 会自动聚合展示）
  Future<Moment> _publishMoment({
    required CharacterProvider characterProvider,
    required Character character,
    required String content,
    required String visibility,
  }) async {
    final moment = Moment(
      id: 'auto_${DateTime.now().microsecondsSinceEpoch}',
      content: content,
      visibility: visibility,
      createdAt: DateTime.now(),
    );
    await characterProvider.updateMoments(character.id, [
      moment,
      ...character.moments,
    ]);
    return moment;
  }
}
