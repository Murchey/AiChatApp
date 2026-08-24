import 'package:ai_chat/models/sticker_pack.dart';
import 'package:ai_chat/services/sticker_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 24);
  UserSticker sticker({
    required String id,
    required String label,
    List<String> keywords = const [],
    List<String> emotions = const [],
  }) =>
      UserSticker(
        id: id,
        sha256: id,
        imagePath: '/stickers/$id.png',
        label: label,
        createdAt: now,
        keywords: keywords,
        emotionTags: emotions,
      );

  test('search returns only matching stickers and ranks label highest', () {
    final result = StickerSearchService.search([
      sticker(id: 'cat', label: '小猫叹气', keywords: ['无奈'], emotions: ['难过']),
      sticker(id: 'panda', label: '熊猫头无语', keywords: ['无语', '吐槽']),
      sticker(id: 'happy', label: '开心比心', emotions: ['开心']),
    ], '无语又想吐槽');

    expect(result.map((item) => item.id), ['panda']);
  });

  test('search returns no item for unrelated query', () {
    final result = StickerSearchService.search(
      [
        sticker(id: 'happy', label: '开心比心', emotions: ['开心'])
      ],
      '晚安睡觉',
    );

    expect(result, isEmpty);
  });
}
