import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/message.dart';
import 'api_provider.dart';
import '../providers/token_usage_provider.dart';
import '../services/llm_service.dart';
import '../services/prompt_builder.dart';

/// 语C流式回复所需的 ChatProvider 回调。
class ChatStreamHooks {
  final List<Message> Function(String conversationId) getMessages;
  final void Function(String conversationId, Message message) appendMessage;
  final void Function(String conversationId, String messageId, Message updated)
      replaceMessage;
  final void Function(String conversationId, String messageId) removeMessage;
  final void Function() notify;
  final Future<void> Function() persist;
  final void Function(String conversationId, int tokens) setSystemTokens;
  final void Function(String conversationId, int tokens) setContextTokens;
  final void Function(String? error) setLastError;
  final void Function() clearReplying;
  final int Function(String text) estimateTokens;
  final int Function(String conversationId, int contextCount, {int systemTokens})
      estimateInputBudget;
  final String Function(String conversationId) conversationAvatar;
  final Future<void> Function(String conversationId, List<String> choices)
      setRoleplayChoices;
  final void Function(String conversationId, String content) updateLastMessage;

  const ChatStreamHooks({
    required this.getMessages,
    required this.appendMessage,
    required this.replaceMessage,
    required this.removeMessage,
    required this.notify,
    required this.persist,
    required this.setSystemTokens,
    required this.setContextTokens,
    required this.setLastError,
    required this.clearReplying,
    required this.estimateTokens,
    required this.estimateInputBudget,
    required this.conversationAvatar,
    required this.setRoleplayChoices,
    required this.updateLastMessage,
  });
}

/// 语C SSE 流式回复：逐段更新气泡，结束后写入思考时长与 token 统计。
Future<List<String>> runRoleplayStreamWithHooks({
  required ChatStreamHooks hooks,
  required String conversationId,
  required ApiModel model,
  required String characterName,
  required String characterSystemPrompt,
  required String userRelationship,
  required String userNickname,
  required List<String> memoryPoints,
  required int contextCount,
  required String progressionStyle,
  required bool includeChoices,
}) async {
  final prompt = PromptBuilder.buildSystemPrompt(
    baseSystemPrompt: characterSystemPrompt,
    characterName: characterName,
    userNickname: userNickname,
    userRelationship: userRelationship,
    currentTime: DateTime.now(),
    replyToUser: true,
    memoryPoints: memoryPoints,
    roleplayProgressionStyle: progressionStyle,
    roleplayMode: true,
  );
  final instruction = PromptBuilder.buildOutputInstruction(
    characterName: characterName,
    replyToUser: true,
    roleplayMode: true,
    includeRoleplayChoices: includeChoices,
  );
  final history = _buildHistoryFromHooks(hooks, conversationId, contextCount);
  final systemPromptTokens = hooks.estimateTokens(prompt) +
      hooks.estimateTokens(instruction) +
      kPerMessageJsonTokens * 2;
  hooks.setSystemTokens(conversationId, systemPromptTokens);
  final message = Message(
    id: const Uuid().v4(),
    conversationId: conversationId,
    content: '',
    sender: MessageSender.character,
  );
  hooks.appendMessage(conversationId, message);
  hooks.notify();
  var content = '';
  var reasoning = '';
  ChatUsage streamUsage = const ChatUsage();
  final streamWatch = Stopwatch()..start();
  try {
    await for (final chunk in streamCompletion(
      model: model,
      messages: [
        {'role': 'system', 'content': prompt},
        ...history,
        {'role': 'user', 'content': instruction},
      ],
    )) {
      content += chunk.content;
      reasoning += chunk.reasoning;
      if (!chunk.usage.isEmpty) streamUsage = chunk.usage;
      hooks.replaceMessage(
        conversationId,
        message.id,
        message.copyWith(content: content, reasoningContent: reasoning),
      );
      hooks.notify();
    }
    streamWatch.stop();
    final reply = LLMService.parseRoleplayReply(content);
    content = reply.content;
    if (reply.choices.isNotEmpty) {
      await hooks.setRoleplayChoices(conversationId, reply.choices);
    }
    final reasoningTokens =
        streamUsage.reasoningTokens ?? LLMService.estimateReasoningTokens(reasoning);
    final hasThinking = reasoning.trim().isNotEmpty || reasoningTokens > 0;
    hooks.replaceMessage(
      conversationId,
      message.id,
      message.copyWith(
        content: content,
        reasoningContent: reasoning,
        reasoningDurationMs:
            hasThinking ? streamWatch.elapsedMilliseconds : null,
      ),
    );
    hooks.notify();
    await hooks.persist();
    hooks.updateLastMessage(conversationId, content);
    final promptTokens = streamUsage.promptTokens ??
        systemPromptTokens +
            history.fold<int>(
              0,
              (sum, item) =>
                  sum +
                  hooks.estimateTokens(item['content']?.toString() ?? '') +
                  kPerMessageJsonTokens,
            );
    final completionTokens = streamUsage.completionTokens ??
        hooks.estimateTokens(content) + reasoningTokens;
    await TokenUsageProvider.instance.addUsage(
      conversationId,
      ChatUsage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: promptTokens + completionTokens,
        reasoningTokens: reasoningTokens,
      ),
      label: characterName,
      avatar: hooks.conversationAvatar(conversationId),
    );
    hooks.setContextTokens(
      conversationId,
      hooks.estimateInputBudget(
        conversationId,
        contextCount,
        systemTokens: systemPromptTokens,
      ),
    );
    await hooks.persist();
    return content.isEmpty ? const [] : [content];
  } on LLMException catch (e) {
    hooks.setLastError(e.message);
    hooks.removeMessage(conversationId, message.id);
    return const [];
  } catch (e) {
    hooks.setLastError(LLMService.describeException(e));
    hooks.removeMessage(conversationId, message.id);
    return const [];
  } finally {
    hooks.clearReplying();
    hooks.notify();
  }
}

/// 与 ChatProvider._buildHistory 相同规则：取最近 N 条文本消息。
List<Map<String, Object>> _buildHistoryFromHooks(
  ChatStreamHooks hooks,
  String conversationId,
  int contextCount,
) {
  final all = hooks.getMessages(conversationId);
  final texts =
      all.where((m) => m.type == MessageType.text && m.content.trim().isNotEmpty);
  final list = texts.toList();
  final start = contextCount <= 0 ? 0 : (list.length - contextCount).clamp(0, list.length);
  return list
      .sublist(start)
      .map((m) => <String, Object>{
            'role': m.isFromUser ? 'user' : 'assistant',
            'content': m.content,
          })
      .toList();
}

/// 与 ChatProvider.kPerMessageJsonTokens 保持一致
const int kPerMessageJsonTokens = 5;
