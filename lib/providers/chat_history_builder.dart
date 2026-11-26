import '../models/message.dart';

/// Model-visible entries for one stored message. Empty and local-only entries
/// do not consume the history window.
List<Map<String, String>> chatHistoryEntries(
  Message message, {
  required String Function(Message m) describe,
}) {
  if (message.isForwardCard) {
    return message.forwardedItems
        .where((item) => item.type == 'text' && item.content.trim().isNotEmpty)
        .map((item) => <String, String>{
              'role': item.isUser ? 'user' : 'assistant',
              'content': item.content,
            })
        .toList();
  }
  if (message.type == MessageType.narration) {
    if (message.content.trim().isEmpty) return const [];
    return [
      {'role': 'user', 'content': '【用户剧情行动/旁白】\n${message.content}'},
    ];
  }
  if (message.type != MessageType.text && message.type != MessageType.sticker) {
    return const [];
  }
  final content =
      message.type == MessageType.sticker ? describe(message) : message.content;
  if (content.trim().isEmpty) return const [];
  return [
    {'role': message.isFromUser ? 'user' : 'assistant', 'content': content},
  ];
}

List<Map<String, String>> buildChatHistory(
  List<Message> history,
  int contextCount, {
  required String Function(Message m) describe,
}) {
  // Old stores can contain several cumulative summaries. Only the newest
  // nonempty summary is authoritative, with its original list position.
  final summaryIndex = history.lastIndexWhere((message) =>
      message.isCompressionSummary && message.content.trim().isNotEmpty);
  final recent = <Map<String, String>>[];
  for (var i = summaryIndex + 1; i < history.length; i++) {
    final message = history[i];
    if (message.isCompressionSummary) continue;
    recent.addAll(chatHistoryEntries(message, describe: describe));
  }
  final start = contextCount > 0 && recent.length > contextCount
      ? recent.length - contextCount
      : 0;
  return [
    if (summaryIndex >= 0)
      ...chatHistoryEntries(history[summaryIndex], describe: describe),
    ...recent.skip(start),
  ];
}
