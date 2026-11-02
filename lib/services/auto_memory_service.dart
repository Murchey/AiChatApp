import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/local_data_store.dart';
import '../models/auto_memory_op.dart';
import '../models/message.dart';
import '../providers/api_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/memory_point_provider.dart';
import '../providers/token_usage_provider.dart';
import 'llm_service.dart';

/// 记忆点自动托管：私聊每累计 [kMessagesPerRecord] 条消息，
/// 自动调用一次「剧情记录」，把剧情推进要点写入记忆点的「AI 托管」分区
/// （MemoryPoint.sourceType == 'auto'）。
///
/// 触发时点在 AI 回复流程完成后（见 ChatProvider.autoMemoryRecorder）；
/// 游标记录上次成功录制时的消息条数，按会话持久化（LocalDataStore chat meta）。
/// 录制请求失败不推进游标，下一次回复完成后自然重试；不会打扰用户。
class AutoMemoryService {
  AutoMemoryService._();

  /// 每累计多少条消息记录一次剧情。
  static const int kMessagesPerRecord = 10;

  /// 录制时携带的最近消息窗口条数。
  static const int kHistoryWindow = 30;

  static const String _cursorsKey = 'auto_memory_cursors';
  static const String _cursorsPrefsKey = 'auto_memory_cursors_v1';

  /// 正在录制的会话 id（防止同一会话并发录制）。
  static final Set<String> _inFlight = <String>{};

  /// 纯函数：判断当前消息数是否达到录制阈值。
  ///
  /// [cursor] 为上次成功录制时的消息条数；清空聊天等导致 cursor > messageCount
  /// 时按当前消息数重新起算。
  static bool shouldRecord(int messageCount, int cursor) {
    final base = cursor > messageCount ? 0 : cursor;
    return messageCount - base >= kMessagesPerRecord;
  }

  /// 纯函数：把会话消息映射为录制请求的对话历史（最近 [kHistoryWindow] 条）。
  ///
  /// 跳过空内容、压缩摘要与表情/图片/文件消息；用户剧情行动标注前缀后
  /// 归为 user 角色。
  static List<Map<String, String>> buildRecordHistory(List<Message> messages) {
    final lines = <Map<String, String>>[];
    for (final m in messages) {
      if (m.isCompressionSummary) continue;
      final content = m.content.trim();
      if (content.isEmpty) continue;
      if (m.type == MessageType.text) {
        lines.add({
          'role': m.isFromUser ? 'user' : 'assistant',
          'content': content,
        });
      } else if (m.type == MessageType.narration) {
        lines.add({'role': 'user', 'content': '【剧情行动】$content'});
      }
    }
    if (lines.length <= kHistoryWindow) return lines;
    return lines.sublist(lines.length - kHistoryWindow);
  }

  /// 检查并在达到阈值时录制一次剧情。调用方无需等待（内部 fire-and-forget 亦可）。
  ///
  /// 未开开关 / 并发录制中 / 未达阈值 / 无聊天模型时静默返回；
  /// 请求成功后把游标推进到当前消息数（解析结果为空也视为完成本次记录，
  /// 避免空记录反复触发），请求失败不推进游标。
  static Future<void> maybeRecord({
    required ChatProvider chatProvider,
    required String conversationId,
    required ChatSettingsProvider chatSettings,
    required MemoryPointProvider memoryPointProvider,
    required ApiProvider apiProvider,
  }) async {
    if (!chatSettings.autoMemoryEnabled) return;
    if (!_inFlight.add(conversationId)) return;
    try {
      final messages = chatProvider.getMessages(conversationId);
      final cursors = await _loadCursors();
      final cursor = cursors[conversationId] ?? 0;
      if (!shouldRecord(messages.length, cursor)) return;

      final model = apiProvider.getModelById(chatSettings.selectedModelId);
      if (model == null) return; // 未选模型：静默跳过，不推进游标

      final conversation = chatProvider.conversations
          .where((c) => c.id == conversationId)
          .firstOrNull;
      final characterId = conversation?.characterId ?? '';
      if (characterId.isEmpty) return;
      final rawName = conversation?.characterName.trim() ?? '';
      final characterName = rawName.isEmpty ? '角色' : rawName;

      final existing = memoryPointProvider.autoPointsFor(characterId);
      final completion = await generatePlotMemoryRecords(
        model: model,
        historyMessages: buildRecordHistory(messages),
        existingRecords: [
          for (final p in existing) {'id': p.id, 'content': p.content},
        ],
      );

      // 请求已达模型并返回：无论解析出多少操作都推进游标，避免反复触发。
      final ops = AutoMemoryOp.parseList(completion.content);
      if (ops.isNotEmpty) {
        await memoryPointProvider.applyAutoOperations(characterId, ops);
      }
      await TokenUsageProvider.instance.addUsage(
        conversationId,
        completion.usage,
        label: characterName,
      );
      await _saveCursor(conversationId, messages.length);
      debugPrint('[AutoMemory] 剧情记录完成 $conversationId: '
          '${ops.length} 个操作');
    } catch (e) {
      // 请求失败不推进游标，下一次回复完成后自然重试；不打扰用户。
      debugPrint('[AutoMemory] 剧情记录失败 $conversationId: $e');
    } finally {
      _inFlight.remove(conversationId);
    }
  }

  /// 读取全部会话的录制游标（convId → 上次录制时的消息条数）。
  static Future<Map<String, int>> _loadCursors() async {
    final raw = await LocalDataStore.loadChatMeta(_cursorsKey, _cursorsPrefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveCursor(String conversationId, int count) async {
    final cursors = await _loadCursors();
    cursors[conversationId] = count;
    await LocalDataStore.saveChatMeta(
      _cursorsKey,
      _cursorsPrefsKey,
      jsonEncode(cursors),
    );
  }
}
