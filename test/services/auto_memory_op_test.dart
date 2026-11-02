import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/models/auto_memory_op.dart';

void main() {
  test('解析裸 JSON 操作数组', () {
    final ops = AutoMemoryOp.parseList(
      '[{"op":"add","content":"新剧情"},{"op":"update","id":"p1","content":"改写"},{"op":"delete","id":"p2"}]',
    );
    expect(ops.length, 3);
    expect(ops[0].isAdd, isTrue);
    expect(ops[0].content, '新剧情');
    expect(ops[1].isUpdate, isTrue);
    expect(ops[1].id, 'p1');
    expect(ops[2].isDelete, isTrue);
    expect(ops[2].id, 'p2');
    expect(ops[2].content, isEmpty);
  });

  test('容错解析代码围栏与前后杂文', () {
    final ops = AutoMemoryOp.parseList(
      '好的，记录如下：\n```json\n[{"op":"add","content":"围栏里的记录"}]\n```\n以上。',
    );
    expect(ops.length, 1);
    expect(ops.first.content, '围栏里的记录');

    expect(AutoMemoryOp.parseList('这次没有需要记录的变化'), isEmpty);
    expect(AutoMemoryOp.parseList('[]'), isEmpty);
    expect(AutoMemoryOp.parseList('不是 JSON'), isEmpty);
  });

  test('忽略非法项：未知 op、缺内容、缺 id', () {
    final ops = AutoMemoryOp.parseList(
      '['
      '{"op":"merge","content":"未知操作"},'
      '{"op":"add","content":"  "},'
      '{"op":"update","content":"缺 id"},'
      '{"op":"delete"},'
      '{"op":"add","content":"有效记录"}'
      ']',
    );
    expect(ops.length, 1);
    expect(ops.first.content, '有效记录');

    // action 别名可用
    final aliased = AutoMemoryOp.parseList('[{"action":"add","content":"别名操作"}]');
    expect(aliased.length, 1);
    expect(aliased.first.isAdd, isTrue);
  });

  test('超量操作截断、超长内容截断', () {
    final buffer = StringBuffer('[');
    for (var i = 0; i < 15; i++) {
      if (i > 0) buffer.write(',');
      buffer.write('{"op":"add","content":"记录$i"}');
    }
    buffer.write(']');
    final ops = AutoMemoryOp.parseList(buffer.toString());
    expect(ops.length, AutoMemoryOp.maxOps);

    final long = '长' * 300;
    final clamped =
        AutoMemoryOp.parseList('[{"op":"add","content":"$long"}]');
    expect(clamped.first.content.length, AutoMemoryOp.maxContentLength);
  });
}
