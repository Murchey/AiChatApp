/// 单个会话（私聊 / 群聊）累计消耗的 token 用量。
///
/// - [sentTokens]：累计发送给模型的 token（API usage.prompt_tokens 累加）
/// - [receivedTokens]：累计从模型接收的 token（API usage.completion_tokens 累加）
class TokenUsage {
  final int sentTokens;
  final int receivedTokens;

  const TokenUsage({this.sentTokens = 0, this.receivedTokens = 0});

  int get totalTokens => sentTokens + receivedTokens;

  bool get isEmpty => sentTokens == 0 && receivedTokens == 0;

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      sentTokens: json['sent'] as int? ?? 0,
      receivedTokens: json['received'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'sent': sentTokens,
        'received': receivedTokens,
      };

  TokenUsage copyWith({int? sentTokens, int? receivedTokens}) {
    return TokenUsage(
      sentTokens: sentTokens ?? this.sentTokens,
      receivedTokens: receivedTokens ?? this.receivedTokens,
    );
  }
}
