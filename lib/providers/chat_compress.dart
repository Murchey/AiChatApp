import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import 'api_provider.dart';
import 'chat_history_builder.dart';
import '../services/llm_service.dart';

/// 会话压缩所需回调。
class ChatCompressHooks {
  final List<Message> Function(String conversationId) getMessages;
  final void Function(String conversationId, Message message, int index)
      insertMessage;
  final void Function(String conversationId, String messageId) removeMessage;
  final void Function(Object error)? onError;
  final void Function(String conversationId, int tokens) setContextTokens;
  final void Function(String conversationId, String content) updateLastMessage;
  final void Function() notify;
  final Future<void> Function() persist;
  final UsageCallback? onUsage;
  final int Function(String conversationId, int contextCount,
      {int systemTokens}) estimateInputBudget;

  const ChatCompressHooks({
    required this.getMessages,
    required this.insertMessage,
    required this.removeMessage,
    this.onError,
    required this.setContextTokens,
    required this.updateLastMessage,
    required this.notify,
    required this.persist,
    this.onUsage,
    required this.estimateInputBudget,
  });
}

const int kKeepRecentMessages = 6;

/// 把消息转换为模型可读的上下文描述（不暴露本地文件路径）。
String describeMessageForModel(Message m) {
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

/// 会话压缩：达到阈值时把更早消息摘要为一条压缩消息（原文保留）。
Future<bool> maybeCompressConversationWithHooks({
  required ChatCompressHooks hooks,
  required String conversationId,
  required ApiModel compressModel,
  required int contextLength,
  required double threshold,
  int systemPromptTokens = 0,
  int contextCount = 0,
  bool force = false,
}) async {
  final messages = List<Message>.of(hooks.getMessages(conversationId));
  if (messages.isEmpty) return false;
  final summaryIndex = messages.lastIndexWhere((message) =>
      message.isCompressionSummary && message.content.trim().isNotEmpty);
  final candidates = <int>[];
  for (var i = summaryIndex + 1; i < messages.length; i++) {
    if (!messages[i].isCompressionSummary &&
        chatHistoryEntries(messages[i], describe: describeMessageForModel)
            .isNotEmpty) {
      candidates.add(i);
    }
  }
  if (candidates.length <= kKeepRecentMessages) return false;

  if (!force &&
      hooks.estimateInputBudget(
            conversationId,
            contextCount,
            systemTokens: systemPromptTokens,
          ) <
          contextLength * threshold) {
    return false;
  }

  final cutIndex = candidates[candidates.length - kKeepRecentMessages];
  final toCompress = messages.sublist(summaryIndex + 1, cutIndex);
  final history = <Map<String, String>>[
    if (summaryIndex >= 0)
      ...chatHistoryEntries(messages[summaryIndex],
          describe: describeMessageForModel),
    for (final message in toCompress)
      if (!message.isCompressionSummary)
        ...chatHistoryEntries(message, describe: describeMessageForModel),
  ];

  try {
    final summary = await LLMService.compressHistory(
      model: compressModel,
      historyMessages: history,
      onUsage: hooks.onUsage,
    );
    if (summary.trim().isEmpty) return false;
    // Appends can safely continue during compression. Any change to the
    // snapshotted prefix invalidates its boundary and generated summary.
    final current = hooks.getMessages(conversationId);
    if (current.length < cutIndex) return false;
    for (var i = 0; i < cutIndex; i++) {
      if (!identical(current[i], messages[i])) return false;
    }
    final summaryId = const Uuid().v4();
    hooks.insertMessage(
      conversationId,
      Message(
        id: summaryId,
        conversationId: conversationId,
        content:
            '［已${force ? '手动' : '自动'}压缩更早的 ${toCompress.length} 条消息］\n$summary',
        type: MessageType.text,
        sender: MessageSender.character,
        isCompressionSummary: true,
      ),
      cutIndex,
    );
    hooks.setContextTokens(
      conversationId,
      hooks.estimateInputBudget(conversationId, contextCount,
          systemTokens: systemPromptTokens),
    );
    try {
      await hooks.persist();
    } catch (_) {
      hooks.removeMessage(conversationId, summaryId);
      hooks.setContextTokens(
        conversationId,
        hooks.estimateInputBudget(conversationId, contextCount,
            systemTokens: systemPromptTokens),
      );
      hooks.notify();
      try {
        await hooks.persist();
      } catch (rollbackError) {
        debugPrint('[ChatCompress] 回滚保存失败: $rollbackError');
      }
      rethrow;
    }
    hooks.notify();
    return hooks
        .getMessages(conversationId)
        .any((message) => message.id == summaryId);
  } catch (e) {
    hooks.onError?.call(e);
    debugPrint('[ChatCompress] 会话压缩失败，继续原样发送: $e');
    return false;
  }
}
