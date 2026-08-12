import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../models/moment_notification.dart';
import '../models/visibility_group.dart';
import '../providers/api_provider.dart';
import '../providers/character_provider.dart';
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

  /// 运行一轮朋友圈互动（后台异步执行，不阻塞 UI）。
  ///
  /// 按角色逐个请求，单个角色失败自动重试；累计失败 [maxFailures] 次
  /// 立即终止全部互动，并以 Toast + 开发者日志告知错误原因。
  static Future<void> run({
    required CharacterProvider characterProvider,
    required ApiProvider apiProvider,
    required MomentNotificationProvider notificationProvider,
    required Moment moment,
    required List<Character> characters,
  }) async {
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

    DevLogService.instance.log(
        '开始朋友圈 AI 互动：共 ${characters.length} 个角色可见（模型：${model.displayName}）');
    var totalFailures = 0;
    String? lastError;

    for (final character in characters) {
      if (totalFailures >= maxFailures) break;
      var success = false;
      while (!success && totalFailures < maxFailures) {
        try {
          final decision = await _askCharacter(
            model,
            character,
            moment,
            // 累计已失败 4 次后（即第 5 次尝试起），不再发送自定义
            // temperature，让模型使用默认值（部分模型不支持 temperature 字段）
            useDefaultTemperature: totalFailures >= 4,
          );
          await _applyDecision(
            characterProvider,
            notificationProvider,
            moment,
            character,
            decision,
          );
          success = true;
          final actions = <String>[
            if (decision.like) '点赞',
            if (decision.comment.isNotEmpty) '评论：${decision.comment}',
          ];
          DevLogService.instance.log(
              '「${character.displayName}」互动成功：${actions.isEmpty ? '仅浏览' : actions.join('，')}');
        } catch (e) {
          totalFailures++;
          lastError = LLMService.describeException(e);
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
  }

  /// 请求单个角色是否点赞 / 评论，返回解析后的决策。
  ///
  /// 使用角色系统提示词作为 system 消息，动态 JSON 与输出格式指令
  /// 作为最后一条 user 消息（含用户给角色设置的关系）；图文动态时
  /// 附带 base64 图片（视觉消息）。
  /// 网络 / API / 解析失败均抛出 [LLMException]，由外层计入失败次数。
  /// [useDefaultTemperature] 为 true 时不发送 temperature 字段，
  /// 由模型使用自身默认值。
  static Future<MomentDecision> _askCharacter(
    ApiModel model,
    Character character,
    Moment moment, {
    bool useDefaultTemperature = false,
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
            ? _buildUserPrompt(moment, relationship)
            : _buildVisionUserContent(moment, relationship),
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

  /// 动态文本部分：JSON 序列化动态 + 用户关系 + 输出格式指令
  static String _buildUserPrompt(Moment moment, String relationship) {
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
        '请你以当前角色的身份决定互动方式，只输出一个 JSON 对象，'
        '不要输出任何其他文字，不要用代码块包裹。格式：\n'
        '{"like": true或false, "comment": "评论内容"}\n\n'
        '要求：\n'
        '- like：是否要给这条朋友圈点赞（true 点赞 / false 不点赞）\n'
        '- comment：若想评论，写 5~30 字中文评论，内容符合角色性格、'
        '你与朋友圈主人的关系以及说话习惯；不想评论则填空字符串 ""';
  }

  /// 图文动态：文本指令 + 图片（base64 data URL，OpenAI 视觉格式）
  static Object _buildVisionUserContent(Moment moment, String relationship) {
    final parts = <Map<String, Object>>[
      {'type': 'text', 'text': _buildUserPrompt(moment, relationship)},
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
}

/// 单个角色对一条朋友圈的互动决策
class MomentDecision {
  final bool like;
  final String comment;

  const MomentDecision({required this.like, required this.comment});
}
