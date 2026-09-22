import '../models/character.dart';
import 'pinyin_util.dart';

/// 角色关键词匹配：昵称 / 备注 / 签名 / 地区 / 简介 / 标签的原文，
/// 或昵称的完整拼音（如查「zhangsan」可命中「张三」）。
/// [query] 需为小写。
bool characterMatchesQuery(Character character, String query) {
  if (query.isEmpty) return true;
  final haystack = [
    character.displayName,
    character.name,
    character.remark,
    character.signature,
    character.region,
    character.description,
    ...character.tags,
  ].join(' ').toLowerCase();
  if (haystack.contains(query)) return true;
  return PinyinUtil.fullPinyin(character.displayName).contains(query);
}