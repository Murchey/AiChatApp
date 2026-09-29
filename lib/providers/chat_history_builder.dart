import '../models/message.dart';

List<Map<String, String>> buildChatHistory(
      List<Message> history, int contextCount,
      {required String Function(Message m) describe}) {
    var cutStart = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].isCompressionSummary) {
        cutStart = i;
        break;
      }
    }
    final start = contextCount > 0 && history.length - contextCount > cutStart
        ? history.length - contextCount
        : cutStart;
    final result = <Map<String, String>>[];
    for (int i = start; i < history.length; i++) {
      final m = history[i];
      if (m.type == MessageType.sticker) {
        result.add({
          'role': m.isFromUser ? 'user' : 'assistant',
          'content': describe(m),
        });
        continue;
      }
      if (m.type == MessageType.narration) {
        result.add({
          'role': 'user',
          'content': '【用户剧情行动/旁白】\n${m.content}',
        });
        continue;
      }
      if (m.type != MessageType.text) continue; // 图片/文件消息不入上下文
      // 合并转发卡片：展开为原始对话消息，参与上下文
      if (m.isForwardCard) {
        for (final item in m.forwardedItems) {
          if (item.type != 'text') continue;
          result.add({
            'role': item.isUser ? 'user' : 'assistant',
            'content': item.content,
          });
        }
        continue;
      }
      result.add({
        'role': m.isFromUser ? 'user' : 'assistant',
        'content': m.content,
      });
    }
    return result;
  }
