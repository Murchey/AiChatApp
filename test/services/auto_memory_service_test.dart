import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/models/message.dart';
import 'package:ai_chat/services/auto_memory_service.dart';
import 'package:ai_chat/services/llm_service.dart';

void main() {
  test('shouldRecord 阈值与清空聊天后的游标钳制', () {
    expect(AutoMemoryService.shouldRecord(10, 0), isTrue);
    expect(AutoMemoryService.shouldRecord(9, 0), isFalse);
    expect(AutoMemoryService.shouldRecord(15, 5), isTrue);
    expect(AutoMemoryService.shouldRecord(15, 6), isFalse);
    expect(AutoMemoryService.shouldRecord(15, 10), isFalse);
    // 清空聊天后游标大于消息数：从当前消息数重新起算
    expect(AutoMemoryService.shouldRecord(10, 100), isTrue);
    expect(AutoMemoryService.shouldRecord(4, 100), isFalse);
  });

  test('buildRecordHistory 过滤无关消息并截取最近窗口', () {
    final messages = <Message>[
      Message(
        id: '1',
        conversationId: 'c',
        content: '你好',
        sender: MessageSender.user,
      ),
      Message(
        id: '2',
        conversationId: 'c',
        content: '在吗',
        sender: MessageSender.character,
      ),
      Message(
        id: '3',
        conversationId: 'c',
        content: '压缩摘要内容',
        sender: MessageSender.character,
        isCompressionSummary: true,
      ),
      Message(
        id: '4',
        conversationId: 'c',
        content: '',
        sender: MessageSender.user,
        type: MessageType.image,
      ),
      Message(
        id: '5',
        conversationId: 'c',
        content: '（拔剑）看招',
        sender: MessageSender.user,
        type: MessageType.narration,
      ),
    ];
    final history = AutoMemoryService.buildRecordHistory(messages);
    expect(history.length, 3);
    expect(history[0], {'role': 'user', 'content': '你好'});
    expect(history[1], {'role': 'assistant', 'content': '在吗'});
    expect(history[2], {'role': 'user', 'content': '【剧情行动】（拔剑）看招'});

    final many = List.generate(
      35,
      (i) => Message(
        id: 'id-$i',
        conversationId: 'c',
        content: '消息$i',
        sender: MessageSender.user,
      ),
    );
    final windowed = AutoMemoryService.buildRecordHistory(many);
    expect(windowed.length, AutoMemoryService.kHistoryWindow);
    expect(windowed.last['content'], '消息34');
    expect(windowed.first['content'], '消息5');
  });

  test('剧情记录指令包含现有记录与输出格式约束', () {
    final instruction = buildPlotMemoryInstruction([
      {'id': 'p1', 'content': '旧记录'},
    ]);
    expect(instruction, contains('id=p1'));
    expect(instruction, contains('旧记录'));
    expect(instruction, contains('"op":"add"'));
    expect(instruction, contains('"op":"update"'));
    expect(instruction, contains('"op":"delete"'));

    final empty = buildPlotMemoryInstruction(const []);
    expect(empty, contains('（暂无剧情记录）'));
  });
}
