import '../models/sticker_pack.dart';

/// 角色发送表情包的候选结果：图片路径 + 展示备注。
/// 覆盖「用户自定义表情」与「创意工坊 Pack 表情」两种来源。
class StickerMatch {
  final String imagePath;
  final String label;
  const StickerMatch({required this.imagePath, this.label = ''});
}

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
      final score = _scoreTerms(
        terms: queryTerms,
        label: label,
        description: description,
        keywords: keywords,
        emotions: emotions,
      );
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

  /// 在「用户自定义表情包」与「创意工坊 Pack 表情」两类中合并检索：
  /// 按匹配分排序后返回统一候选，供角色发送。
  static List<StickerMatch> searchAll({
    required Iterable<UserSticker> userStickers,
    required Iterable<StickerPack> packs,
    required String query,
    int limit = 5,
  }) {
    final terms = _terms(query);
    if (terms.isEmpty) return const [];
    final ranked = <({StickerMatch match, int score, int order})>[];
    var order = 0;
    for (final sticker in userStickers) {
      final score = _scoreTerms(
        terms: terms,
        label: sticker.label.toLowerCase(),
        description: sticker.description.toLowerCase(),
        keywords: sticker.keywords.map((item) => item.toLowerCase()).toList(),
        emotions:
            sticker.emotionTags.map((item) => item.toLowerCase()).toList(),
      );
      if (score > 0) {
        ranked.add((
          match:
              StickerMatch(imagePath: sticker.imagePath, label: sticker.label),
          score: score + (sticker.useCount ~/ 10), // 常用表情小幅加权
          order: order++,
        ));
      }
    }
    for (final pack in packs) {
      final packName = pack.name.toLowerCase();
      final author = pack.author.toLowerCase();
      for (var i = 0; i < pack.imagePaths.length; i++) {
        final label = (pack.labels[i] ?? '').trim().toLowerCase();
        var score = 0;
        for (final term in terms) {
          if (label.contains(term)) score += 12; // 单图备注最相关
          if (packName.contains(term)) score += 7; // 包名
          if (author.contains(term)) score += 2; // 作者
        }
        if (score > 0) {
          ranked.add((
            match: StickerMatch(
              imagePath: pack.imagePaths[i],
              label: pack.labels[i] ?? '',
            ),
            score: score,
            order: order++,
          ));
        }
      }
    }
    ranked.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.order.compareTo(b.order);
    });
    return ranked.take(limit.clamp(0, 8)).map((item) => item.match).toList();
  }

  static int _scoreTerms({
    required List<String> terms,
    required String label,
    required String description,
    required List<String> keywords,
    required List<String> emotions,
  }) {
    var score = 0;
    for (final term in terms) {
      if (label.contains(term)) {
        score += 12; // 备注命中权重最高
      }
      if (keywords.any((item) => item.contains(term) || term.contains(item))) {
        score += 9;
      }
      if (emotions.any((item) => item.contains(term) || term.contains(item))) {
        score += 8;
      }
      if (description.contains(term)) {
        score += 5;
      }
    }
    return score;
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
