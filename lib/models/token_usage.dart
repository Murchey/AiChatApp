/// Persisted category keeps deleted and UUID-named group chats classified.
enum TokenUsageKind { privateChat, groupChat, moment }

/// Accumulated input and output tokens. Cache counters are input subsets and
/// reasoning tokens are an output subset, so neither is added to [totalTokens].
class TokenUsage {
  final int sentTokens;
  final int receivedTokens;
  final int reasoningTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  final String label;
  final String avatar;
  final TokenUsageKind? kind;

  const TokenUsage({
    this.sentTokens = 0,
    this.receivedTokens = 0,
    this.reasoningTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheCreationTokens = 0,
    this.label = '',
    this.avatar = '',
    this.kind,
  });

  int get bodyTokens =>
      (receivedTokens - reasoningTokens).clamp(0, receivedTokens);
  int get totalTokens => sentTokens + receivedTokens;
  bool get isEmpty =>
      sentTokens == 0 &&
      receivedTokens == 0 &&
      reasoningTokens == 0 &&
      cacheReadTokens == 0 &&
      cacheCreationTokens == 0;
  bool get hasLabel => label.trim().isNotEmpty;

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      sentTokens: _count(json['sent']),
      receivedTokens: _count(json['received']),
      reasoningTokens: _count(json['reasoning']),
      cacheReadTokens: _count(json['cacheRead']),
      cacheCreationTokens: _count(json['cacheCreation']),
      label: json['label'] is String ? json['label'] as String : '',
      avatar: json['avatar'] is String ? json['avatar'] as String : '',
      kind: _kind(json['kind']),
    );
  }

  static TokenUsageKind? _kind(Object? value) {
    for (final kind in TokenUsageKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }

  static int _count(Object? value) {
    final count = switch (value) {
      int number => number,
      num number when number.isFinite => number.toInt(),
      String text => int.tryParse(text.trim()) ?? 0,
      _ => 0,
    };
    return count < 0 ? 0 : count;
  }

  Map<String, dynamic> toJson() => {
        'sent': sentTokens,
        'received': receivedTokens,
        'reasoning': reasoningTokens,
        'cacheRead': cacheReadTokens,
        'cacheCreation': cacheCreationTokens,
        'label': label,
        'avatar': avatar,
        if (kind != null) 'kind': kind!.name,
      };

  TokenUsage copyWith({
    int? sentTokens,
    int? receivedTokens,
    int? reasoningTokens,
    int? cacheReadTokens,
    int? cacheCreationTokens,
    String? label,
    String? avatar,
    TokenUsageKind? kind,
  }) =>
      TokenUsage(
        sentTokens: sentTokens ?? this.sentTokens,
        receivedTokens: receivedTokens ?? this.receivedTokens,
        reasoningTokens: reasoningTokens ?? this.reasoningTokens,
        cacheReadTokens: cacheReadTokens ?? this.cacheReadTokens,
        cacheCreationTokens: cacheCreationTokens ?? this.cacheCreationTokens,
        label: label ?? this.label,
        avatar: avatar ?? this.avatar,
        kind: kind ?? this.kind,
      );
}
