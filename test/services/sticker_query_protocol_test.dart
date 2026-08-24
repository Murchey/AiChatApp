import 'package:ai_chat/services/sticker_query_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts query and removes a standalone internal marker', () {
    const marker = '[[查询表情包:猫猫傲娇]]';

    expect(StickerQueryProtocol.extractQuery(marker), '猫猫傲娇');
    expect(StickerQueryProtocol.visibleText(marker), isEmpty);
  });

  test('never leaks a query marker mixed with normal text', () {
    const content = '哼 [[ 查询表情包：猫猫傲娇 ]] 才不是想你了';

    expect(StickerQueryProtocol.extractQuery(content), '猫猫傲娇');
    expect(StickerQueryProtocol.visibleText(content), '哼 才不是想你了');
  });

  test('removes malformed unclosed marker from visible text', () {
    expect(
      StickerQueryProtocol.visibleText('好吧 [[查询表情包:猫猫傲娇'),
      '好吧',
    );
  });
}
