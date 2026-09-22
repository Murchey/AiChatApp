/// 单个会话（私聊 / 群聊）累计消耗的 token 用量。
///
/// - [sentTokens]：累计发送给模型的 token（API usage.prompt_tokens 累加）
/// - [receivedTokens]：累计从模型接收的 token（API usage.completion_tokens 累加，
///   **已包含**思考过程 token，与账单口径一致）
/// - [reasoningTokens]：累计思考过程 token（completion 的子集；
///   优先来自 completion_tokens_details.reasoning_tokens，否则按思考正文估算）
/// - [label] / [avatar]：会话展示名与头像快照。会话被删除后统计仍保留这些字段，
///   统计页不再显示「该对话已删除」占位。
class TokenUsage {
  final int sentTokens;
  final int receivedTokens;
  final int reasoningTokens;
  final String label;
  final String avatar;

  const TokenUsage({
    this.sentTokens = 0,
    this.receivedTokens = 0,
    this.reasoningTokens = 0,
    this.label = '',
    this.avatar = '',
  });

  /// 输出中的正文部分（不含思考）
  int get bodyTokens {
    final body = receivedTokens - reasoningTokens;
    return body < 0 ? 0 : body;
  }

  int get totalTokens => sentTokens + receivedTokens;

  bool get isEmpty =>
      sentTokens == 0 && receivedTokens == 0 && reasoningTokens == 0;

  bool get hasLabel => label.trim().isNotEmpty;

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      sentTokens: json['sent'] as int? ?? 0,
      receivedTokens: json['received'] as int? ?? 0,
      reasoningTokens: json['reasoning'] as int? ?? 0,
      label: json['label'] as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'sent': sentTokens,
        'received': receivedTokens,
        'reasoning': reasoningTokens,
        'label': label,
        'avatar': avatar,
      };

  TokenUsage copyWith({
    int? sentTokens,
    int? receivedTokens,
    int? reasoningTokens,
    String? label,
    String? avatar,
  }) {
    return TokenUsage(
      sentTokens: sentTokens ?? this.sentTokens,
      receivedTokens: receivedTokens ?? this.receivedTokens,
      reasoningTokens: reasoningTokens ?? this.reasoningTokens,
      label: label ?? this.label,
      avatar: avatar ?? this.avatar,
    );
  }
}
