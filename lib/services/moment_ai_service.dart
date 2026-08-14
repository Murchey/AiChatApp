import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../models/moment_notification.dart';
import '../models/visibility_group.dart';
import '../providers/api_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../utils/app_toast.dart';
import 'dev_log_service.dart';
import 'llm_service.dart';

/// 朋友圈 AI 互动引擎。
///
/// 用户发布朋友圈后，遍历「展示范围」内可见的角色（使用各自系统提示词），
/// 将动态序列化为 JSON（图文动态附带图片）请求模型决定是否点赞 / 评论：
/// 每次角色互动成功后写入动态点赞/评论，并生成未读通知（铃铛角标 + 红点）。
/// 任一角色请求失败自动重试，累计失败 10 次即停止，Toast 告知错误原因。
class MomentAiService {
  /// 累计失败次数上限（达到后停止全部角色互动）
  static const int maxFailures = 10;

  /// 根据动态展示范围解析可见角色：
  /// - only_me：无任何角色可见
  /// - all：全部可管理角色（排除"自己"）
  /// - 分组 id：分组内成员（分组被删/成员缺失时回退全部可管理角色）
  static List<Character> visibleCharacters(
    CharacterProvider provider,
    String visibility,
  ) {
    if (visibility == VisibilityScope.onlyMe) return const [];
    if (visibility == VisibilityScope.all) return provider.manageableCharacters;
    for (final group in provider.visibilityGroups) {
      if (group.id == visibility) {
        final members = group.memberIds
            .map(provider.getCharacterById)
            .whereType<Character>()
            .toList();
        if (members.isNotEmpty) return members;
      }
    }
    return provider.manageableCharacters;
  }

  /// 朋友圈互动断点存储键：应用中途被杀/退出时记录未完成的互动，
  /// 下次启动从断点续跑剩余角色，避免互动被中断后丢失。
  static const String breakpointKey = 'moment_interaction_breakpoint_v1';

  /// 全局互斥：同一时刻只允许一轮互动运行，避免并发写断点互相覆盖。
  static bool _interactionRunning = false;

  /// 正在生成"评论回复"的组合键集合（"回复者 id|动态 id"），
  /// 防止同一回复者针对同一动态并发触发多次回复；
  /// 同一动态下不同回复者的回复互不阻塞。
  static final Set<String> _replyingMomentIds = <String>{};

  /// 组装评论回复互斥键：以「回复者 + 动态」为粒度去重
  static String _replyKey(String characterId, String momentId) =>
      '$characterId|$momentId';

  /// 运行一轮朋友圈互动（后台异步执行，不阻塞 UI）。
  ///
  /// 按角色逐个请求，单个角色失败自动重试；累计失败 [maxFailures] 次
  /// 立即终止全部互动，并以 Toast + 开发者日志告知错误原因。
  ///
  /// 防打断设计：启动时把「待互动角色、累计失败数、模型 id」写入断点，
  /// 每完成一个角色就更新一次断点；全部结束（或失败达上限）后清除。
  /// 应用退出后 [resumePending] 会从断点续跑剩余角色。
  static Future<void> run({
    required CharacterProvider characterProvider,
    required ApiProvider apiProvider,
    required MomentNotificationProvider notificationProvider,
    required ChatProvider chatProvider,
    required ChatSettingsProvider chatSettings,
    required Moment moment,
    required List<Character> characters,
    int initialFailures = 0,
  }) async {
    if (_interactionRunning) {
      const msg = '朋友圈互动正在进行中，已跳过本次';
      DevLogService.instance.log(msg);
      showAppToast(msg);
      return;
    }
    _interactionRunning = true;
    try {
      final model = apiProvider.getModelById(apiProvider.momentModelId);
      if (model == null) {
        const msg = '请先在「API 设置」中配置「朋友圈互动」模型';
        DevLogService.instance.log(msg);
        showAppToast(msg);
        return;
      }
      if (characters.isEmpty) {
        DevLogService.instance.log('朋友圈 AI 互动：展示范围内没有可见角色，跳过');
        return;
      }

      // 写入断点：记录待互动的剩余角色（应用被杀后下次启动可精确续跑）
      var pendingIds = characters.map((c) => c.id).toList();
      var totalFailures = initialFailures;
      await _saveBreakpoint(
        moment: moment,
        pendingCharacterIds: pendingIds,
        totalFailures: totalFailures,
        modelId: model.id,
      );

      DevLogService.instance.log(
          '开始朋友圈 AI 互动：共 ${characters.length} 个角色可见（模型：${model.displayName}）');
      String? lastError;

      for (final character in characters) {
        if (totalFailures >= maxFailures) break;
        var success = false;
        while (!success && totalFailures < maxFailures) {
          try {
            // 角色与用户的最近聊天记录（条数与用户设置的上下文条数一致），
            // 让角色在回复用户朋友圈时了解与用户之间的历史语境
            final chatHistory = chatProvider.getRecentHistoryForCharacter(
              character.id,
              chatSettings.contextCount,
            );
            final decision = await _askCharacter(
              model,
              character,
              moment,
              // 累计已失败 4 次后（即第 5 次尝试起），不再发送自定义
              // temperature，让模型使用默认值（部分模型不支持 temperature 字段）
              useDefaultTemperature: totalFailures >= 4,
              chatHistory: chatHistory,
            );
            await _applyDecision(
              characterProvider,
              notificationProvider,
              moment,
              character,
              decision,
            );
            success = true;
            // 该角色互动完成：从断点移除并持久化（崩溃/退出后可续跑剩余角色）
            pendingIds.remove(character.id);
            await _saveBreakpoint(
              moment: moment,
              pendingCharacterIds: pendingIds,
              totalFailures: totalFailures,
              modelId: model.id,
            );
            final actions = <String>[
              if (decision.like) '点赞',
              if (decision.comment.isNotEmpty) '评论：${decision.comment}',
            ];
            DevLogService.instance.log(
                '「${character.displayName}」互动成功：${actions.isEmpty ? '仅浏览' : actions.join('，')}');
          } catch (e) {
            totalFailures++;
            lastError = LLMService.describeException(e);
            // 失败计数计入断点，重启后按累计失败数续跑（保持失败上限语义）
            await _saveBreakpoint(
              moment: moment,
              pendingCharacterIds: pendingIds,
              totalFailures: totalFailures,
              modelId: model.id,
            );
            DevLogService.instance.log(
                '「${character.displayName}」请求失败（累计 $totalFailures 次）：$lastError');
          }
        }
      }

      if (totalFailures >= maxFailures) {
        final msg = '朋友圈 AI 互动失败次数过多已停止：$lastError';
        DevLogService.instance.log(msg);
        showAppToast(msg);
      } else {
        DevLogService.instance.log('朋友圈 AI 互动结束');
      }
      // 全部角色互动完成（或达到失败上限）：清除断点
      await _clearBreakpoint();
    } finally {
      _interactionRunning = false;
    }
  }

  /// 应用启动时调用：若存在未完成的朋友圈互动断点（应用中途被杀/退出），
  /// 从断点续跑剩余角色的互动。
  ///
  /// - 动态已被删除 → 清除断点；
  /// - 断点模型已不可用 → 保留断点，等待模型恢复后下次启动再续跑；
  /// - 剩余角色已全部被删除 → 清除断点。
  static Future<void> resumePending({
    required CharacterProvider characterProvider,
    required ApiProvider apiProvider,
    required MomentNotificationProvider notificationProvider,
    required ChatProvider chatProvider,
    required ChatSettingsProvider chatSettings,
  }) async {
    final bp = await _loadBreakpoint();
    if (bp == null) return;

    final self = characterProvider.selfCharacter;
    final momentExists =
        self != null && self.moments.any((m) => m.id == bp.moment.id);
    if (!momentExists) {
      DevLogService.instance.log('朋友圈互动断点：动态已不存在，清除断点');
      await _clearBreakpoint();
      return;
    }

    final model = apiProvider.getModelById(bp.modelId);
    if (model == null) {
      DevLogService.instance.log(
          '朋友圈互动断点：模型不可用，保留断点等待模型配置后恢复');
      return;
    }

    // 按断点顺序解析剩余角色；期间被删除的角色自动跳过
    final remaining = <Character>[];
    for (final id in bp.pendingCharacterIds) {
      final c = characterProvider.getCharacterById(id);
      if (c != null) remaining.add(c);
    }
    if (remaining.isEmpty) {
      DevLogService.instance.log('朋友圈互动断点：剩余角色已不存在，清除断点');
      await _clearBreakpoint();
      return;
    }

    DevLogService.instance.log(
        '恢复朋友圈 AI 互动：剩余 ${remaining.length} 个角色（累计失败 ${bp.totalFailures} 次）');
    await run(
      characterProvider: characterProvider,
      apiProvider: apiProvider,
      notificationProvider: notificationProvider,
      chatProvider: chatProvider,
      chatSettings: chatSettings,
      moment: bp.moment,
      characters: remaining,
      initialFailures: bp.totalFailures,
    );
  }

  /// 保存朋友圈互动断点
  static Future<void> _saveBreakpoint({
    required Moment moment,
    required List<String> pendingCharacterIds,
    required int totalFailures,
    required String modelId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      breakpointKey,
      jsonEncode(_InteractionBreakpoint(
        moment: moment,
        pendingCharacterIds: pendingCharacterIds,
        totalFailures: totalFailures,
        modelId: modelId,
      ).toJson()),
    );
  }

  /// 清除朋友圈互动断点
  static Future<void> _clearBreakpoint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(breakpointKey);
  }

  /// 读取朋友圈互动断点（无断点或数据损坏时返回 null）
  static Future<_InteractionBreakpoint?> _loadBreakpoint() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(breakpointKey);
    if (raw == null) return null;
    try {
      return _InteractionBreakpoint.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// 请求单个角色是否点赞 / 评论，返回解析后的决策。
  ///
  /// 使用角色系统提示词作为 system 消息，动态 JSON 与输出格式指令
  /// 作为最后一条 user 消息（含用户给角色设置的关系）；图文动态时
  /// 附带 base64 图片（视觉消息）。
  /// 网络 / API / 解析失败均抛出 [LLMException]，由外层计入失败次数。
  /// [useDefaultTemperature] 为 true 时不发送 temperature 字段，
  /// 由模型使用自身默认值。
  /// [chatHistory] 为角色与用户的最近聊天记录（用户设置的上下文条数），
  /// 附加到 user 消息中，让角色互动时了解与用户的历史语境。
  static Future<MomentDecision> _askCharacter(
    ApiModel model,
    Character character,
    Moment moment, {
    bool useDefaultTemperature = false,
    List<Map<String, String>> chatHistory = const [],
  }) async {
    final system = character.systemPrompt.trim().isEmpty
        ? '你是「${character.displayName}」，正在浏览朋友圈。'
        : character.systemPrompt;
    final relationship = character.userRelationship.trim();
    final messages = <Map<String, Object>>[
      {'role': 'system', 'content': system},
      {
        'role': 'user',
        'content': moment.images.isEmpty
            ? _buildUserPrompt(moment, relationship, chatHistory)
            : _buildVisionUserContent(moment, relationship, chatHistory),
      },
    ];
    final result = await LLMService.fetchCompletion(
      model: model,
      messages: messages,
      temperature: useDefaultTemperature ? null : 0.9,
      maxTokens: 300,
      jsonMode: true,
    );
    debugPrint('[MomentAi] ${character.displayName} 原始响应: ${result.content}');
    return _parseDecision(result.content);
  }

  /// 动态文本部分：JSON 序列化动态 + 用户关系 + 输出格式指令。
  /// [chatHistory] 非空时附带「最近聊天记录」段落。
  static String _buildUserPrompt(
    Moment moment,
    String relationship, [
    List<Map<String, String>> chatHistory = const [],
  ]) {
    final json = jsonEncode({
      'content': moment.content,
      'location': moment.location,
      'created_at': moment.createdAt?.toIso8601String(),
      'image_count': moment.images.length,
      if (moment.images.isNotEmpty)
        'images': [
          for (final p in moment.images.take(9)) p.split(RegExp(r'[/\\]')).last,
        ],
    });
    return '以下是朋友圈主人刚发布的一条朋友圈（JSON 格式）：\n'
        '$json\n\n'
        '你和朋友圈主人的关系：'
        '${relationship.isEmpty ? '普通朋友' : relationship}\n\n'
        '${_chatHistorySection(chatHistory)}'
        '请你以当前角色的身份决定互动方式，只输出一个 JSON 对象，'
        '不要输出任何其他文字，不要用代码块包裹。格式：\n'
        '{"like": true或false, "comment": "评论内容"}\n\n'
        '要求：\n'
        '- like：是否要给这条朋友圈点赞（true 点赞 / false 不点赞）\n'
        '- comment：若想评论，写 5~30 字中文评论，内容符合角色性格、'
        '你与朋友圈主人的关系以及说话习惯；不想评论则填空字符串 ""';
  }

  /// 图文动态：文本指令 + 图片（base64 data URL，OpenAI 视觉格式）
  static Object _buildVisionUserContent(
    Moment moment,
    String relationship, [
    List<Map<String, String>> chatHistory = const [],
  ]) {
    final parts = <Map<String, Object>>[
      {'type': 'text', 'text': _buildUserPrompt(moment, relationship, chatHistory)},
    ];
    for (final path in moment.images.take(9)) {
      try {
        final bytes = File(path).readAsBytesSync();
        parts.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:${_imageMime(path)};base64,${base64Encode(bytes)}',
          },
        });
      } catch (e) {
        debugPrint('[MomentAi] 读取图片失败: $path ($e)');
      }
    }
    return parts;
  }

  /// 按文件扩展名推断图片 MIME（OpenAI 视觉格式要求 data URL 带类型）
  static String _imageMime(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  /// 组装「最近聊天记录」段落（无记录时返回空串）。
  /// [characterName] 用于把 assistant 角色标注为角色名。
  static String _chatHistorySection(
    List<Map<String, String>> chatHistory, [
    String characterName = '角色',
  ]) {
    if (chatHistory.isEmpty) return '';
    final buf = StringBuffer('你与该用户最近的聊天记录（按时间顺序）：\n');
    for (final m in chatHistory) {
      final speaker = m['role'] == 'user' ? '用户' : characterName;
      buf.writeln('$speaker：${m['content']}');
    }
    buf.writeln();
    return buf.toString();
  }

  /// 容错解析模型返回的 JSON 决策对象（兼容代码块包裹 / 前后多余文本）。
  /// 解析失败抛出 [LLMException]，计入失败次数并重试。
  static MomentDecision _parseDecision(String raw) {
    var text = raw.trim();
    // 去掉 ```json ... ``` 代码块包裹
    text = text
        .replaceAll(RegExp(r'^```(json)?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*```$', caseSensitive: false), '')
        .trim();

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      // 提取首个 {...} 片段再解析
      final match = RegExp(r'\{.*\}', dotAll: true).firstMatch(text);
      if (match != null) {
        try {
          decoded = jsonDecode(match.group(0)!);
        } catch (_) {
          decoded = null;
        }
      }
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LLMException('模型返回的不是有效的 JSON 决策');
    }
    final like = _readBool(decoded, const ['like', 'liked', 'is_like', 'like_it']);
    final comment = (decoded['comment'] ?? decoded['content'] ?? decoded['reply'] ?? '')
        .toString()
        .trim();
    return MomentDecision(like: like ?? false, comment: comment);
  }

  static bool? _readBool(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final v = map[key];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == 'yes' || s == '1' || s == '是') return true;
        if (s == 'false' || s == 'no' || s == '0' || s == '否') return false;
      }
    }
    return null;
  }

  /// 将角色决策写入动态（点赞去重、追加评论）并生成未读通知
  static Future<void> _applyDecision(
    CharacterProvider characterProvider,
    MomentNotificationProvider notificationProvider,
    Moment moment,
    Character character,
    MomentDecision decision,
  ) async {
    final self = characterProvider.selfCharacter;
    if (self == null) return;
    final moments = [...self.moments];
    final index = moments.indexWhere((m) => m.id == moment.id);
    if (index == -1) return; // 动态已被删除，跳过

    final cur = moments[index];
    // 点赞去重：同名昵称只保留一个
    final likes = <String>[];
    for (final n in cur.likes) {
      if (!likes.contains(n)) likes.add(n);
    }
    if (decision.like && !likes.contains(character.displayName)) {
      likes.add(character.displayName);
    }
    final comments = [...cur.comments];
    if (decision.comment.isNotEmpty) {
      comments.add(MomentComment(
        sender: character.displayName,
        content: decision.comment,
      ));
    }

    moments[index] = Moment(
      id: cur.id,
      content: cur.content,
      location: cur.location,
      visibility: cur.visibility,
      images: cur.images,
      likes: likes,
      comments: comments,
      createdAt: cur.createdAt,
    );
    await characterProvider.updateMoments(
      CharacterProvider.selfCharacterId,
      moments,
    );
    await notificationProvider.addActivity(MomentNotification(
      id: 'mn_${DateTime.now().microsecondsSinceEpoch}',
      characterId: character.id,
      characterName: character.displayName,
      momentId: moment.id,
      momentContent: moment.content,
      liked: decision.like,
      comment: decision.comment,
      createdAt: DateTime.now(),
    ));
  }

  /// 用户评论角色的朋友圈后，由该角色（动态发布者）回复用户的评论。
  ///
  /// 模型输入包含：动态完整 JSON（文案/图片/点赞/评论）、用户的角色卡片、
  /// 用户与角色的关系、角色的最近聊天记录（条数与用户设置的上下文条数一致）、
  /// 角色系统提示词。生成的回复作为一条「带回复评论」写入该动态
  /// （sender=角色名，reply_to=用户昵称）。
  ///
  /// 同一动态同时只触发一次回复；重复触发直接忽略。
  static Future<void> replyToUserComment({
    required ApiProvider apiProvider,
    required ChatSettingsProvider chatSettings,
    required ChatProvider chatProvider,
    required CharacterProvider characterProvider,
    required MomentNotificationProvider notificationProvider,
    required Character character,
    required Character owner,
    required Moment moment,
    required String userNickname,
    required String userComment,
    String replyToName = '',
    String repliedComment = '',
  }) async {
    final replyKey = _replyKey(character.id, moment.id);
    if (_replyingMomentIds.contains(replyKey)) {
      DevLogService.instance
          .log('「${character.displayName}」评论回复进行中，跳过重复触发');
      return;
    }
    _replyingMomentIds.add(replyKey);
    try {
      // 朋友圈回复优先使用「朋友圈互动」模型，未配置时回退聊天模型
      final model = apiProvider.getModelById(apiProvider.momentModelId) ??
          apiProvider.getModelById(chatSettings.selectedModelId);
      if (model == null) {
        const msg = '请先在「API 设置」中配置「朋友圈互动」模型或聊天模型';
        DevLogService.instance.log(msg);
        showAppToast(msg);
        return;
      }
      final self = characterProvider.selfCharacter;
      final relationship = character.userRelationship.trim();
      var chatHistory = chatProvider.getRecentHistoryForCharacter(
        character.id,
        chatSettings.contextCount,
      );

      // 组装 prompt 前，从发布者处重新读取该动态的最新快照
      // （用户刚提交的评论此刻已写入 provider），让模型看到完整的评论区上下文
      var latestMoment = moment;
      final ownerLatest = characterProvider.getCharacterById(owner.id);
      if (ownerLatest != null) {
        for (final m in ownerLatest.moments) {
          if (m.id == moment.id) {
            latestMoment = m;
            break;
          }
        }
      }

      final system = character.systemPrompt.trim().isEmpty
          ? '你是「${character.displayName}」。'
          : character.systemPrompt;
      var userPrompt = _buildReplyPrompt(
        character: character,
        self: self,
        moment: latestMoment,
        relationship: relationship,
        chatHistory: chatHistory,
        userNickname: userNickname,
        userComment: userComment,
        replyToName: replyToName,
        repliedComment: repliedComment,
      );

      // 上下文估算：若已达到互动模型上下文窗口的 70%，自动压缩聊天记录后再回复
      final estimated = LLMService.estimateTokens(system) +
          LLMService.estimateTokens(userPrompt);
      if (model.contextLength > 0 &&
          chatHistory.isNotEmpty &&
          estimated >= model.contextLength * 0.7) {
        DevLogService.instance.log(
            '「${character.displayName}」评论回复上下文估算 $estimated/${model.contextLength}'
            ' token（≥70%），自动压缩最近聊天记录后回复');
        try {
          final summary = await LLMService.compressHistory(
            model: model,
            historyMessages: chatHistory,
          );
          if (summary.isNotEmpty) {
            // 以压缩摘要替代完整聊天记录重新组装 prompt
            chatHistory = [
              {
                'role': 'assistant',
                'content': '［已压缩的最近聊天记录摘要］\n$summary',
              },
            ];
            userPrompt = _buildReplyPrompt(
              character: character,
              self: self,
              moment: latestMoment,
              relationship: relationship,
              chatHistory: chatHistory,
              userNickname: userNickname,
              userComment: userComment,
              replyToName: replyToName,
              repliedComment: repliedComment,
            );
            DevLogService.instance.log(
                '「${character.displayName}」评论回复压缩完成，压缩后估算 '
                '${LLMService.estimateTokens(system) + LLMService.estimateTokens(userPrompt)} token');
          }
        } catch (e) {
          DevLogService.instance.log(
              '「${character.displayName}」评论回复压缩失败，按原文回复：'
              '${LLMService.describeException(e)}');
        }
      } else if (model.contextLength > 0) {
        DevLogService.instance.log(
            '「${character.displayName}」评论回复上下文估算 $estimated/${model.contextLength}'
            ' token（未达 70% 阈值，不压缩）');
      }

      final messages = <Map<String, Object>>[
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': userPrompt},
      ];
      final result = await LLMService.fetchCompletion(
        model: model,
        messages: messages,
        temperature: 0.9,
        maxTokens: 200,
      );
      final reply = _cleanReply(result.content);
      if (reply.isEmpty) return;

      // 重新读取发布者（owner）的最新角色（含用户刚提交的评论），
      // 在其动态上追加角色回复，避免用旧的快照覆盖掉用户刚写入的评论。
      // 回复评论以「回复者」身份署名，但始终落在发布者的动态下。
      final latest = characterProvider.getCharacterById(owner.id);
      if (latest == null) return;
      final moments = [...latest.moments];
      final index = moments.indexWhere((m) => m.id == moment.id);
      if (index == -1) return; // 动态已被删除
      final cur = moments[index];
      final comments = [
        ...cur.comments,
        MomentComment(
          sender: character.displayName,
          content: reply,
          replyTo: userNickname,
        ),
      ];
      moments[index] = Moment(
        id: cur.id,
        content: cur.content,
        location: cur.location,
        visibility: cur.visibility,
        images: cur.images,
        likes: cur.likes,
        comments: comments,
        createdAt: cur.createdAt,
      );
      await characterProvider.updateMoments(owner.id, moments);
      await notificationProvider.addActivity(MomentNotification(
        id: 'mn_${DateTime.now().microsecondsSinceEpoch}',
        characterId: character.id,
        characterName: character.displayName,
        momentId: moment.id,
        momentContent: moment.content,
        comment: reply,
        isReply: true,
        createdAt: DateTime.now(),
      ));
      DevLogService.instance
          .log('「${character.displayName}」回复了 $userNickname 的评论：$reply');
    } catch (e) {
      DevLogService.instance.log(
          '「${character.displayName}」评论回复失败：${LLMService.describeException(e)}');
    } finally {
      _replyingMomentIds.remove(replyKey);
    }
  }

  /// 组装「角色回复用户评论」的 user 消息。
  ///
  /// [replyToName] 为用户回复的评论者昵称（为空表示用户直接评论动态），
  /// [repliedComment] 为被回复评论的原文，让模型知道用户是针对"谁说了什么"在回复。
  static String _buildReplyPrompt({
    required Character character,
    required Character? self,
    required Moment moment,
    required String relationship,
    required List<Map<String, String>> chatHistory,
    required String userNickname,
    required String userComment,
    String replyToName = '',
    String repliedComment = '',
  }) {
    final momentJson = jsonEncode({
      'content': moment.content,
      'location': moment.location,
      'created_at': moment.createdAt?.toIso8601String(),
      if (moment.images.isNotEmpty)
        'images': [
          for (final p in moment.images.take(9)) p.split(RegExp(r'[/\\]')).last,
        ],
      'likes': moment.likes,
      'comments': moment.comments.map((c) => c.toJson()).toList(),
    });

    final userCard = <String>[
      '昵称：${self?.displayName ?? userNickname}',
      if (self != null && self.signature.isNotEmpty) '签名：${self.signature}',
      if (self != null && self.region.isNotEmpty) '地区：${self.region}',
      if (self != null && self.description.isNotEmpty) '简介：${self.description}',
      if (self != null && self.personality.isNotEmpty) '性格：${self.personality}',
    ].join('\n');

    final chatSection = _chatHistorySection(chatHistory, character.displayName);

    // 用户回复的上下文：是直接评论，还是回复了某人的评论（附原评论内容）
    final replyContext = replyToName.isEmpty
        ? '用户在这条动态下直接发表了评论（不是回复某条评论）'
        : '用户回复了「$replyToName」的评论'
            '${repliedComment.isEmpty ? '' : '，被回复的原评论内容是：「$repliedComment」'}';

    return '用户在朋友圈给你的一条动态下留了评论，请你以「${character.displayName}」的身份回复这条评论。\n\n'
        '【朋友圈动态（JSON）】\n$momentJson\n\n'
        '【用户角色卡片】\n${userCard.isEmpty ? '（无资料）' : userCard}\n\n'
        '【用户与你的关系】\n${relationship.isEmpty ? '普通朋友' : relationship}\n\n'
        '${chatSection.isEmpty ? '' : '$chatSection\n'}'
        '【用户这次评论的上下文】\n$replyContext\n\n'
        '【用户的最新评论】\n$userComment\n\n'
        '请直接输出你要回复的内容（5~50 字中文），符合你的角色性格与说话习惯，'
        '并针对「用户这次评论的上下文」中的原评论内容自然回应，'
        '不要带任何前缀、引号、解释，也不要输出 JSON 或代码块。';
  }

  /// 清洗模型返回的回复文本：去掉代码块包裹与首尾引号。
  static String _cleanReply(String raw) {
    var text = raw.trim();
    text = text.replaceAll(RegExp(r'```[a-zA-Z]*'), '').trim();
    text = text.replaceAll('```', '').trim();
    if (text.startsWith('"') && text.endsWith('"') && text.length >= 2) {
      text = text.substring(1, text.length - 1).trim();
    }
    return text.trim();
  }
}

/// 朋友圈互动断点：记录一轮未完成互动的位置，应用退出后据此续跑。
///
/// [moment] 为动态快照（互动内容以发布时为准）；
/// [pendingCharacterIds] 为尚未互动的角色 id（有序）；
/// [totalFailures] 为跨重启累计的失败次数（保持失败上限语义）；
/// [modelId] 为发布互动时使用的模型，恢复时校验其仍可用。
class _InteractionBreakpoint {
  final Moment moment;
  final List<String> pendingCharacterIds;
  final int totalFailures;
  final String modelId;

  const _InteractionBreakpoint({
    required this.moment,
    required this.pendingCharacterIds,
    required this.totalFailures,
    required this.modelId,
  });

  factory _InteractionBreakpoint.fromJson(Map<String, dynamic> json) {
    return _InteractionBreakpoint(
      moment: Moment.fromJson(json['moment'] as Map<String, dynamic>? ?? {}),
      pendingCharacterIds: (json['pending_character_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      totalFailures: (json['total_failures'] as num?)?.toInt() ?? 0,
      modelId: json['model_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'moment': moment.toJson(),
        'pending_character_ids': pendingCharacterIds,
        'total_failures': totalFailures,
        'model_id': modelId,
      };
}

/// 单个角色对一条朋友圈的互动决策
class MomentDecision {
  final bool like;
  final String comment;

  const MomentDecision({required this.like, required this.comment});
}
