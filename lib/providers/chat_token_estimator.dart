import '../models/message.dart';
import '../services/llm_service.dart';
import 'api_provider.dart';

/// 本地 token 估算（与 ChatProvider 历史口径一致）。
class ChatTokenEstimator {
  ChatTokenEstimator._();

  static const int perMessageJsonTokens = 5;

  /// Output cap used by private proactive replies.
  static const int proactiveReplyOutputTokens = 1024;

  /// Covers message framing and local tokenization variance.
  static const int proactiveReplySafetyMarginTokens = 256;

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

  /// Estimate the already projected model payload, including multimodal parts.
  static int estimatePayload(List<Map<String, Object>> messages) {
    var total = 0;
    for (final message in messages) {
      total += perMessageJsonTokens + _estimateContent(message['content']);
    }
    return total;
  }

  static int _estimateContent(Object? content) {
    if (content is String) return estimateText(content);
    if (content is! List) return 0;
    var total = 0;
    for (final part in content.whereType<Map>()) {
      if (part['type'] == 'text' || part['type'] == 'input_text') {
        total += estimateText(part['text']?.toString() ?? '');
      } else if (part['type'] == 'image_url' || part['type'] == 'input_image') {
        // Provider processing and image dimensions determine visual tokens.
        // Encoded URL length is not a reliable visual-token estimate.
        total += 4096;
      }
    }
    return total;
  }

  /// Read the effective output cap from the same service adapter as the request.
  static int effectiveOutputTokens(ApiModel model, int requestedOutputTokens) {
    final body = LLMService.buildChatBody(
      model: model,
      messages: const [],
      maxTokens: requestedOutputTokens,
    );
    return (body['max_tokens'] ?? body['max_output_tokens']) as int;
  }

  /// Shared by streamed and non-streamed replies. Pass the exact outgoing
  /// messages and the requested output cap of the corresponding service call.
  static ChatRequestBudget requestBudget({
    required ApiModel model,
    required List<Map<String, Object>> messages,
    required int requestedOutputTokens,
    int? contextLength,
    int additionalInputTokens = 0,
  }) {
    final limit = contextLength ?? model.contextLength;
    final safetyMargin =
        limit > 0 && (limit / 10).ceil() > proactiveReplySafetyMarginTokens
            ? (limit / 10).ceil()
            : proactiveReplySafetyMarginTokens;
    return ChatRequestBudget(
      inputTokens: estimatePayload(messages) + additionalInputTokens,
      outputTokens: effectiveOutputTokens(model, requestedOutputTokens),
      safetyMarginTokens: safetyMargin,
      contextLength: limit,
    );
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

/// One reply request's local context estimate, with output and framing reserve.
class ChatRequestBudget {
  final int inputTokens;
  final int outputTokens;
  final int safetyMarginTokens;
  final int contextLength;

  const ChatRequestBudget({
    required this.inputTokens,
    required this.outputTokens,
    required this.safetyMarginTokens,
    required this.contextLength,
  });

  int get reservedTokens => outputTokens + safetyMarginTokens;
  int get totalTokens => inputTokens + reservedTokens;
  bool get exceedsContext => contextLength > 0 && totalTokens > contextLength;

  void ensureFits() {
    if (!exceedsContext) return;
    throw LLMException('聊天上下文超限（估算输入 $inputTokens + 输出预留 $outputTokens + '
        '安全余量 $safetyMarginTokens / 模型上限 $contextLength token）。'
        '请压缩历史、减少上下文条数、缩短角色提示词或记忆，或选择更大上下文模型后重试。');
  }
}
