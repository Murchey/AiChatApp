import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import 'api_provider.dart';
import '../services/llm_service.dart';

/// 会话压缩所需回调。
class ChatCompressHooks {
  final List<Message> Function(String conversationId) getMessages;
  final void Function(String conversationId, Message message, int index)
      insertMessage;
  final void Function(String conversationId, int tokens) setContextTokens;
  final void Function(String conversationId, String content) updateLastMessage;
  final void Function() notify;
  final Future<void> Function() persist;
  final int Function(String conversationId, int contextCount, {int systemTokens})
      estimateInputBudget;

  const ChatCompressHooks({
    required this.getMessages,
    required this.insertMessage,
    required this.setContextTokens,
    required this.updateLastMessage,
    required this.notify,
    required this.persist,
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
      return label.isEmpty
          ? '[$who发送了一个表情包]'
          : '[$who发送了一个表情包（备注：$label）]';
    case MessageType.image:
      return m.isFromUser ? '[用户发送了一张图片]' : '[你发送了一张图片]';
    case MessageType.file:
      final fileName = m.content.split(RegExp(r'[/\\]')).last;
      return m.isFromUser
          ? '[用户发送了一个文件：$fileName]'
          : '[你发送了一个文件：$fileName]';
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
  final messages = hooks.getMessages(conversationId);
  if (messages.isEmpty) return false;
  final textMessages =
      messages.where((m) => m.type == MessageType.text).toList();
  if (textMessages.length <= kKeepRecentMessages) return false;

  if (!force &&
      hooks.estimateInputBudget(
            conversationId,
            contextCount,
            systemTokens: systemPromptTokens,
          ) <
          contextLength * threshold) {
    return false;
  }

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
            'content': describeMessageForModel(m),
          })
      .toList();

  try {
    final summary = await LLMService.compressHistory(
      model: compressModel,
      historyMessages: history,
    );
    if (summary.isEmpty) return false;
    hooks.insertMessage(
      conversationId,
      Message(
        id: const Uuid().v4(),
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
      hooks.estimateInputBudget(conversationId, contextCount),
    );
    hooks.updateLastMessage(conversationId, kept.last.content);
    hooks.notify();
    await hooks.persist();
    return true;
  } catch (e) {
    debugPrint('[ChatCompress] 会话压缩失败，继续原样发送: $e');
    return false;
  }
}
