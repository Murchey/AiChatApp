import '../models/sticker_pack.dart';

/// 纯本地的表情包语义检索；不上传图片或元数据，也不产生 API token 消耗。
class StickerSearchService {
  static List<UserSticker> search(
    Iterable<UserSticker> stickers,
    String query, {
    int limit = 5,
  }) {
    final queryTerms = _terms(query);
    if (queryTerms.isEmpty) return const [];
    final ranked = <({UserSticker sticker, int score})>[];
    for (final sticker in stickers) {
      final label = sticker.label.toLowerCase();
      final description = sticker.description.toLowerCase();
      final keywords =
          sticker.keywords.map((item) => item.toLowerCase()).toList();
      final emotions =
          sticker.emotionTags.map((item) => item.toLowerCase()).toList();
      var score = 0;
      for (final term in queryTerms) {
        if (label.contains(term)) {
          score += 12;
        }
        if (keywords
            .any((item) => item.contains(term) || term.contains(item))) {
          score += 9;
        }
        if (emotions
            .any((item) => item.contains(term) || term.contains(item))) {
          score += 8;
        }
        if (description.contains(term)) {
          score += 5;
        }
      }
      if (score > 0) ranked.add((sticker: sticker, score: score));
    }
    ranked.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0
          ? score
          : b.sticker.useCount.compareTo(a.sticker.useCount);
    });
    return ranked.take(limit.clamp(0, 8)).map((item) => item.sticker).toList();
  }

  static List<String> _terms(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff]+'), ' ')
        .trim();
    final words =
        normalized.split(RegExp(r'\s+')).where((item) => item.isNotEmpty);
    final result = <String>{...words};
    // 中文无空格时，补充连续双字词，提高“无语/开心”等常用标签的召回率。
    for (final word in words) {
      if (RegExp(r'^[\u4e00-\u9fff]+$').hasMatch(word)) {
        for (var i = 0; i < word.length - 1; i++) {
          result.add(word.substring(i, i + 2));
        }
      }
    }
    return result.toList();
  }
}
