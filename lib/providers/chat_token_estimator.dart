import '../models/message.dart';
import '../services/llm_service.dart';

/// 本地 token 估算（与 ChatProvider 历史口径一致）。
class ChatTokenEstimator {
  ChatTokenEstimator._();

  static const int perMessageJsonTokens = 5;

  static int estimateText(String text) => LLMService.estimateTokens(text);

  static int estimateMessages(List<Message> messages) {
    var total = 0;
    for (final m in messages) {
      if (m.type != MessageType.text) continue;
      total += LLMService.estimateTokens(m.content) + perMessageJsonTokens;
    }
    return total;
  }

  /// 从最后一条压缩摘要起，取最近 [contextCount] 条文本消息。
  static int estimateSendBudget(
    List<Message> messages,
    int contextCount, {
    List<String> extra = const [],
  }) {
    var start = 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isCompressionSummary) {
        start = i;
        break;
      }
    }
    final from = contextCount > 0 && messages.length - start > contextCount
        ? messages.length - contextCount
        : start;
    var total = 0;
    for (var i = from; i < messages.length; i++) {
      final m = messages[i];
      if (m.type == MessageType.text) {
        total += LLMService.estimateTokens(m.content) + perMessageJsonTokens;
      }
    }
    for (final text in extra) {
      total += LLMService.estimateTokens(text) + perMessageJsonTokens;
    }
    return total;
  }

  /// 按 history payload 估算输入预算。
  static int estimateRequestBudget(
    List<Map<String, String>> history, {
    int systemTokens = 0,
  }) {
    var historyTokens = 0;
    for (final item in history) {
      historyTokens += LLMService.estimateTokens(item['content'] ?? '') +
          perMessageJsonTokens;
    }
    return systemTokens + historyTokens;
  }
}
