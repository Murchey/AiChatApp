/// 角色请求本地表情包的内部协议。
///
/// 该标记绝不能直接展示给用户；解析失败时也应从可见文本中剥离。
class StickerQueryProtocol {
  static final _queryPattern = RegExp(
    r'\[\[\s*查询表情包\s*[:：]\s*([^\]]{1,80}?)\s*\]\]',
  );

  static String? extractQuery(String content) {
    final match = _queryPattern.firstMatch(content);
    final query = match?.group(1)?.trim();
    return query == null || query.isEmpty ? null : query;
  }

  /// 移除所有合法标记，以及未闭合的同类标记，防止内部协议泄漏到气泡。
  static String visibleText(String content) {
    var result = content.replaceAll(_queryPattern, '');
    result = result.replaceAll(RegExp(r'\[\[\s*查询表情包[^\n]*'), '');
    return result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }
}
