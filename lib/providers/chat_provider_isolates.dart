part of 'chat_provider.dart';

/// 本地存储的原始 JSON 字符串（供后台 isolate 反序列化）
class _RawStore {
  final String? conversationsJson;
  final String? messagesJson;
  final String? contextTokensJson;
  final String? systemTokensJson;

  const _RawStore({
    this.conversationsJson,
    this.messagesJson,
    this.contextTokensJson,
    this.systemTokensJson,
  });
}

/// 后台 isolate 反序列化后的结果
class _DecodedStore {
  final List<Conversation> conversations;
  final Map<String, List<Message>> messages;
  final Map<String, int> contextTokens;
  final Map<String, int> systemTokens;

  const _DecodedStore({
    required this.conversations,
    required this.messages,
    required this.contextTokens,
    required this.systemTokens,
  });
}

/// 待持久化的内存数据快照（供后台 isolate 序列化）
class _PersistSnapshot {
  final List<Conversation> conversations;
  final Map<String, List<Message>> messages;
  final Map<String, int> contextTokens;
  final Map<String, int> systemTokens;

  const _PersistSnapshot({
    required this.conversations,
    required this.messages,
    required this.contextTokens,
    required this.systemTokens,
  });
}

/// 后台 isolate：反序列化全部本地数据。
/// 解析完成后在后台重算各会话上下文 token：
/// 系统提示词恢复后，按「系统提示词 + 摘要起全部历史」估算，
/// 覆盖重启前可能不含系统提示词的旧快照。
@pragma('vm:entry-point')
_DecodedStore _decodePersistStore(_RawStore raw) {
  var conversations = const <Conversation>[];
  var messages = <String, List<Message>>{};
  var contextTokens = <String, int>{};
  var systemTokens = <String, int>{};

  try {
    final convStr = raw.conversationsJson;
    if (convStr != null) {
      final list = jsonDecode(convStr) as List<dynamic>;
      conversations = list
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  } catch (_) {}
  try {
    final msgStr = raw.messagesJson;
    if (msgStr != null) {
      final map = jsonDecode(msgStr) as Map<String, dynamic>;
      map.forEach((convId, msgs) {
        messages[convId] = (msgs as List<dynamic>)
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    }
  } catch (_) {}
  try {
    final ctxStr = raw.contextTokensJson;
    if (ctxStr != null) {
      final map = jsonDecode(ctxStr) as Map<String, dynamic>;
      contextTokens = map.map((k, v) => MapEntry(k, (v as num).toInt()));
    }
  } catch (_) {}
  try {
    final sysStr = raw.systemTokensJson;
    if (sysStr != null) {
      final map = jsonDecode(sysStr) as Map<String, dynamic>;
      systemTokens = map.map((k, v) => MapEntry(k, (v as num).toInt()));
    }
  } catch (_) {}

  // 与旧版主线程逻辑等价的上下文 token 重算（移入后台避免拖慢启动）
  for (final entry in systemTokens.entries) {
    final msgs = messages[entry.key];
    if (msgs == null) continue;
    var start = 0;
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].isCompressionSummary) {
        start = i;
        break;
      }
    }
    var total = entry.value;
    for (var i = start; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.type == MessageType.text) {
        total += LLMService.estimateTokens(m.content) +
            ChatProvider.kPerMessageJsonTokens;
      }
    }
    contextTokens[entry.key] = total;
  }

  return _DecodedStore(
    conversations: conversations,
    messages: messages,
    contextTokens: contextTokens,
    systemTokens: systemTokens,
  );
}

/// 后台 isolate：将内存数据序列化为各存储键的 JSON 字符串。
@pragma('vm:entry-point')
Map<String, String> _encodePersistSnapshot(_PersistSnapshot snapshot) {
  return {
    'conversations':
        jsonEncode(snapshot.conversations.map((c) => c.toJson()).toList()),
    'messages': jsonEncode(snapshot.messages.map(
      (key, value) => MapEntry(key, value.map((m) => m.toJson()).toList()),
    )),
    'contextTokens': jsonEncode(snapshot.contextTokens),
    'systemTokens': jsonEncode(snapshot.systemTokens),
  };
}
