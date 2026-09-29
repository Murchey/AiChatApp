import 'dart:math';

import 'package:flutter/services.dart';

import '../providers/token_usage_provider.dart';
import '../services/llm_service.dart';
import '../services/sticker_search_service.dart';
import '../services/sticker_query_protocol.dart';

/// 处理模型返回的多条回复：拆表情 / 逐条入库 / 统计 token。
class ProactiveReplyHooks {
  final void Function(
    String conversationId,
    String content, {
    String reasoningContent,
    int? reasoningDurationMs,
  }) addProactiveMessage;
  final void Function({
    required String conversationId,
    required String stickerPath,
    required String label,
  }) addSticker;
  final int Function(String conversationId) messageCount;
  final String Function(String conversationId) conversationAvatar;
  final int Function(String conversationId, int contextCount) estimateInputBudget;
  final void Function(String conversationId, int tokens) setContextTokens;
  final void Function() clearReplying;
  final void Function() notify;

  const ProactiveReplyHooks({
    required this.addProactiveMessage,
    required this.addSticker,
    required this.messageCount,
    required this.conversationAvatar,
    required this.estimateInputBudget,
    required this.setContextTokens,
    required this.clearReplying,
    required this.notify,
  });
}

/// 将 [messages] 逐条写入会话（含表情查询协议处理）。
Future<List<String>> processProactiveReplyMessages({
  required ProactiveReplyHooks hooks,
  required String conversationId,
  required String characterName,
  required List<String> messages,
  required ProactiveResult result,
  required String reasoningContent,
  required int? reasoningDurationMs,
  required int contextCount,
  required ChatUsage usage,
  StickerMatch? Function(String query)? findSticker,
}) async {
  var usageAdj = usage;
  if (usageAdj.reasoningTokens == null && reasoningContent.trim().isNotEmpty) {
    usageAdj = ChatUsage(
      promptTokens: usageAdj.promptTokens,
      completionTokens: usageAdj.completionTokens,
      totalTokens: usageAdj.totalTokens,
      reasoningTokens: LLMService.estimateReasoningTokens(reasoningContent),
    );
  }
  await TokenUsageProvider.instance.addUsage(
    conversationId,
    usageAdj,
    label: characterName,
    avatar: hooks.conversationAvatar(conversationId),
  );
  final random = Random();
  final displayedMessages = <String>[];
  var stickerSent = false;
  var reasoningAttached = false;
  for (final content in messages) {
    final query = StickerQueryProtocol.extractQuery(content);
    final visibleContent = StickerQueryProtocol.visibleText(content);
    if (query != null) {
      final sticker = !stickerSent ? findSticker?.call(query) : null;
      if (sticker != null) {
        final beforeCount = hooks.messageCount(conversationId);
        hooks.addSticker(
          conversationId: conversationId,
          stickerPath: sticker.imagePath,
          label: sticker.label,
        );
        if (hooks.messageCount(conversationId) > beforeCount) {
          stickerSent = true;
          displayedMessages.add('[表情包]');
        }
      }
      if (visibleContent.isEmpty) continue;
    }
    if (visibleContent.isEmpty) continue;
    hooks.addProactiveMessage(
      conversationId,
      visibleContent,
      reasoningContent: reasoningAttached ? '' : reasoningContent,
      reasoningDurationMs: reasoningAttached ? null : reasoningDurationMs,
    );
    if (reasoningContent.trim().isNotEmpty) reasoningAttached = true;
    displayedMessages.add(visibleContent);
    HapticFeedback.lightImpact();
    final delay = random.nextDouble() * 1000 + visibleContent.length * 50;
    await Future.delayed(Duration(milliseconds: delay.round() + 600));
  }
  final prompt = usage.promptTokens;
  final estimated = hooks.estimateInputBudget(conversationId, contextCount);
  hooks.setContextTokens(
    conversationId,
    prompt != null && prompt > estimated ? prompt : estimated,
  );
  return displayedMessages;
}
