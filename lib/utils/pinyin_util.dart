import 'package:lpinyin/lpinyin.dart';

/// 中文拼音工具（用于通讯录按字母排序分组）
class PinyinUtil {
  /// 获取文字首字母（大写 A-Z，非中文字符返回 #）
  static String firstLetter(String text) {
    if (text.isEmpty) return '#';
    final pinyin = PinyinHelper.getFirstWordPinyin(text.trim());
    if (pinyin.isEmpty) return '#';
    final letter = pinyin.toUpperCase()[0];
    if (letter.codeUnitAt(0) >= 65 && letter.codeUnitAt(0) <= 90) {
      return letter;
    }
    return '#';
  }

  /// 获取完整拼音（小写，用于同组内排序）
  static String fullPinyin(String text) {
    final pinyin = PinyinHelper.getPinyin(text.trim(), separator: '');
    return pinyin.toLowerCase();
  }
}
