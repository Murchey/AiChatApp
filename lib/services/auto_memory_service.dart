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
/// 自动调用一次「剧情记录」，把剧情推进要点写入记忆点的「AI 托管」分区。
class AutoMemoryService {
  AutoMemoryService._();

  static const int kMessagesPerRecord = 10;
  static const int kHistoryWindow = 30;
  static const String _cursorsKey = 'auto_memory_cursors';
  static const String _cursorsPrefsKey = 'auto_memory_cursors_v1';

  static final Set<String> _inFlight = <String>{};
  static final Set<String> _pending = <String>{};
  static final Map<String, Future<void>> _tasks = <String, Future<void>>{};
  static final Map<String, int> _conversationGenerations = <String, int>{};
  static int _allGeneration = 0;
  static int _backupBarriers = 0;
  static Future<void> _backupQueue = Future<void>.value();

  /// Quiesces in-flight recording before capturing both storage projections.
  static Future<T> withBackupBarrier<T>(Future<T> Function() action) {
    _backupBarriers++;
    final task = _backupQueue.then((_) async {
      cancelAll();
      await drain();
      return MemoryPointProvider.withBackupBarrier(action);
    });
    _backupQueue = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task.whenComplete(() => _backupBarriers--);
  }

  static bool shouldRecord(int messageCount, int cursor) {
    final base = cursor > messageCount ? 0 : cursor;
    return messageCount - base >= kMessagesPerRecord;
  }

  static bool _eligible(Message message) =>
      !message.isCompressionSummary &&
      message.content.trim().isNotEmpty &&
      (message.type == MessageType.text ||
          message.type == MessageType.narration);

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

  /// 检查并录制所有已达到阈值的批次。调用方可以 fire-and-forget。
  static Future<void> maybeRecord({
    required ChatProvider chatProvider,
    required String conversationId,
    required ChatSettingsProvider chatSettings,
    required MemoryPointProvider memoryPointProvider,
    required ApiProvider apiProvider,
  }) {
    if (_backupBarriers > 0 || !chatSettings.autoMemoryEnabled) {
      return Future<void>.value();
    }
    if (!_inFlight.add(conversationId)) {
      _pending.add(conversationId);
      return _tasks[conversationId] ?? Future<void>.value();
    }
    final allGeneration = _allGeneration;
    final conversationGeneration =
        _conversationGenerations[conversationId] ?? 0;
    Future<void> run() async {
      do {
        _pending.remove(conversationId);
        await _record(
          chatProvider: chatProvider,
          conversationId: conversationId,
          chatSettings: chatSettings,
          memoryPointProvider: memoryPointProvider,
          apiProvider: apiProvider,
          allGeneration: allGeneration,
          conversationGeneration: conversationGeneration,
        );
      } while (_pending.contains(conversationId) &&
          chatSettings.autoMemoryEnabled &&
          allGeneration == _allGeneration &&
          conversationGeneration ==
              (_conversationGenerations[conversationId] ?? 0));
    }

    final task = run().whenComplete(() {
      _inFlight.remove(conversationId);
      _tasks.remove(conversationId);
      final shouldRunAgain = _pending.remove(conversationId);
      if (shouldRunAgain &&
          chatSettings.autoMemoryEnabled &&
          allGeneration == _allGeneration &&
          conversationGeneration ==
              (_conversationGenerations[conversationId] ?? 0)) {
        maybeRecord(
          chatProvider: chatProvider,
          conversationId: conversationId,
          chatSettings: chatSettings,
          memoryPointProvider: memoryPointProvider,
          apiProvider: apiProvider,
        );
      }
    });
    _tasks[conversationId] = task;
    return task;
  }

  /// 使指定会话的在途请求失效。网络请求本身无法取消。
  static void cancelConversation(String conversationId) {
    _conversationGenerations[conversationId] =
        (_conversationGenerations[conversationId] ?? 0) + 1;
  }

  /// 使所有在途请求失效。网络请求本身无法取消。
  static void cancelAll() {
    _allGeneration++;
  }

  /// 等待当前在途录制任务及其游标写入结束。
  static Future<void> drain() async {
    while (_tasks.isNotEmpty) {
      await Future.wait(_tasks.values.toList(growable: false));
    }
  }

  static Future<void> _record({
    required ChatProvider chatProvider,
    required String conversationId,
    required ChatSettingsProvider chatSettings,
    required MemoryPointProvider memoryPointProvider,
    required ApiProvider apiProvider,
    required int allGeneration,
    required int conversationGeneration,
  }) async {
    final providerGeneration = memoryPointProvider.generation;
    try {
      final original = List<Message>.unmodifiable(
        chatProvider.getMessages(conversationId),
      );
      final messages = List<Message>.unmodifiable(original.where(_eligible));
      final conversation = chatProvider.conversations
          .where((c) => c.id == conversationId)
          .firstOrNull;
      final characterId = conversation?.characterId ?? '';
      if (characterId.isEmpty) return;
      var checkedPrefixLength = 0;
      bool isCurrent() {
        if (allGeneration != _allGeneration ||
            conversationGeneration !=
                (_conversationGenerations[conversationId] ?? 0) ||
            memoryPointProvider.isDisposed ||
            providerGeneration != memoryPointProvider.generation ||
            !chatSettings.autoMemoryEnabled) {
          return false;
        }
        final currentConversation = chatProvider.conversations
            .where((c) => c.id == conversationId)
            .firstOrNull;
        if (currentConversation?.characterId != characterId) return false;
        final current =
            chatProvider.getMessages(conversationId).where(_eligible).toList();
        if (current.length < checkedPrefixLength) return false;
        for (var i = 0; i < checkedPrefixLength; i++) {
          final before = messages[i];
          final now = current[i];
          if (before.id != now.id ||
              before.content != now.content ||
              before.type != now.type ||
              before.sender != now.sender) {
            return false;
          }
        }
        return true;
      }

      final messageCount = messages.length;
      await memoryPointProvider.synchronizePendingTransaction();
      final cursors = await _loadCursors();
      if (!isCurrent()) return;
      final stored = cursors[conversationId];
      var cursor = 0;
      if (stored is num) {
        final oldCount = stored.toInt();
        if (oldCount >= 0 && oldCount <= original.length) {
          cursor = original.take(oldCount).where(_eligible).length;
        }
      } else if (stored is Map && stored['lastId'] is String) {
        final index =
            messages.indexWhere((message) => message.id == stored['lastId']);
        if (index >= 0) cursor = index + 1;
      }
      if (!shouldRecord(messageCount, cursor)) return;

      final model = apiProvider.getModelById(chatSettings.selectedModelId);
      if (model == null) return;
      final rawName = conversation?.characterName.trim() ?? '';
      final characterName = rawName.isEmpty ? '角色' : rawName;

      while (messageCount - cursor >= kMessagesPerRecord) {
        if (!isCurrent()) return;
        final nextCursor = cursor + kMessagesPerRecord;
        checkedPrefixLength = nextCursor;
        if (!isCurrent()) return;
        final batchMessages = messages.take(nextCursor).toList(growable: false);
        final existing = memoryPointProvider.autoPointsFor(characterId);
        final expectedRevisions = <String, int>{
          for (final point in existing) point.id: point.revision,
        };
        final completion = await generatePlotMemoryRecords(
          model: model,
          onUsage: (usage) => TokenUsageProvider.instance.addUsage(
            conversationId, usage, label: characterName,
          ),
          historyMessages: buildRecordHistory(batchMessages),
          existingRecords: [
            for (final point in existing)
              {'id': point.id, 'content': point.content},
          ],
        );
        if (!isCurrent()) return;

        final parsed = AutoMemoryOp.parseResult(completion.content);
        if (!parsed.isValidJsonArray) {
          throw const FormatException('Invalid auto memory response');
        }
        await memoryPointProvider.applyAutoOperations(
          characterId,
          parsed.operations,
          expectedRevisions: expectedRevisions,
          isCurrent: isCurrent,
          conversationId: conversationId,
          cursorCount: nextCursor,
          cursorLastId: messages[nextCursor - 1].id,
        );
        if (!isCurrent()) return;
        cursor = nextCursor;
        debugPrint('[AutoMemory] 剧情记录完成 $conversationId: '
            '${parsed.operations.length} 个操作');
      }
    } catch (e) {
      debugPrint('[AutoMemory] 剧情记录失败 $conversationId: $e');
    }
  }

  static Future<Map<String, dynamic>> _loadCursors() async {
    final raw =
        await LocalDataStore.loadChatMeta(_cursorsKey, _cursorsPrefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded;
    } catch (_) {
      return {};
    }
  }

}
