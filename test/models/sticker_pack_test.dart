import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/models/sticker_pack.dart';

void main() {
  test('StickerPack preserves indexed labels', () {
    final pack = StickerPack(
      id: 'pack-1',
      name: '日常',
      author: '作者',
      coverImagePath: '/stickers/packs/pack-1/1.png',
      imagePaths: const ['/stickers/packs/pack-1/1.png'],
      importedAt: DateTime.utc(2026, 8, 23),
      labels: const {0: '哈哈'},
    );

    final restored = StickerPack.fromJson(pack.toJson());

    expect(restored.imagePaths, pack.imagePaths);
    expect(restored.labels[0], '哈哈');
    expect(restored.coverImagePath, pack.coverImagePath);
  });
}
