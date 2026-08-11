import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/character.dart';
import '../utils/pinyin_util.dart';

class CharacterProvider extends ChangeNotifier {
  List<Character> _characters = [];
  Character? _selectedCharacter;
  bool _isLoading = false;
  static const _storageKey = 'characters_v1';
  static const _deletedKey = 'characters_deleted_v1';

  /// 被用户删除的默认角色 id（删除后重启不恢复）
  Set<String> _deletedDefaultIds = {};

  List<Character> get characters => _characters;
  Character? get selectedCharacter => _selectedCharacter;
  bool get isLoading => _isLoading;

  /// 通讯录：按拼音首字母分组排序（类似手机通讯录）
  List<MapEntry<String, List<Character>>> get sortedCharactersGrouped {
    final sorted = List<Character>.from(_characters)
      ..sort((a, b) {
        final la = PinyinUtil.firstLetter(a.name);
        final lb = PinyinUtil.firstLetter(b.name);
        if (la != lb) return la.compareTo(lb);
        return PinyinUtil.fullPinyin(a.name).compareTo(PinyinUtil.fullPinyin(b.name));
      });

    final groups = <String, List<Character>>{};
    for (final c in sorted) {
      final letter = PinyinUtil.firstLetter(c.name);
      groups.putIfAbsent(letter, () => []).add(c);
    }
    return groups.entries.toList();
  }

  Future<void> loadCharacters() async {
    _isLoading = true;
    notifyListeners();

    // 先从本地读取自定义修改（如系统提示词），再合并默认角色
    final prefs = await SharedPreferences.getInstance();
    final deletedIds = prefs.getStringList(_deletedKey) ?? const [];
    _deletedDefaultIds = deletedIds.toSet();

    final stored = prefs.getString(_storageKey);
    Map<String, dynamic> customMap = {};
    if (stored != null) {
      try {
        customMap = jsonDecode(stored) as Map<String, dynamic>;
      } catch (_) {}
    }

    // 默认角色过滤掉用户已删除的
    final defaults = _defaultCharacters()
        .where((c) => !_deletedDefaultIds.contains(c.id))
        .toList();
    final defaultIds = defaults.map((c) => c.id).toSet();
    _characters = [
      ...defaults.map((c) {
        final custom = customMap[c.id];
        if (custom is Map<String, dynamic>) {
          return Character(
            id: c.id,
            name: custom['name'] as String? ?? c.name,
            remark: custom['remark'] as String? ?? c.remark,
            signature: custom['signature'] as String? ?? c.signature,
            region: custom['region'] as String? ?? c.region,
            avatar: custom['avatar'] as String? ?? c.avatar,
            description: custom['description'] as String? ?? c.description,
            personality: custom['personality'] as String? ?? c.personality,
            greeting: custom['greeting'] as String? ?? c.greeting,
            systemPrompt: custom['system_prompt'] as String? ?? c.systemPrompt,
            customPersona:
                custom['custom_persona'] as String? ?? c.customPersona,
            userRelationship:
                custom['user_relationship'] as String? ?? c.userRelationship,
            tags:
                (custom['tags'] as List<dynamic>?)?.cast<String>() ?? c.tags,
          );
        }
        return c;
      }),
      // 恢复用户导入/自定义的角色（不在默认角色中）
      ...customMap.entries
           .where((e) => !defaultIds.contains(e.key) && e.value is Map<String, dynamic>)
           .map((e) => Character.fromJson(e.value as Map<String, dynamic>)),
    ];
    _isLoading = false;
    notifyListeners();
  }

  List<Character> _defaultCharacters() {
    return [
      Character(
        id: 'char_001',
        name: '苏格拉底',
        description: '古希腊哲学家，善于通过提问引导思考',
        personality: '智慧、耐心、善于启发',
        greeting: '你好，年轻人。今天你有什么想探讨的问题吗？',
        systemPrompt: '你是古希腊哲学家苏格拉底。你通过提问来引导对方思考，而不是直接给出答案。你的回答充满智慧和启发性。',
        tags: ['哲学', '历史', '智慧'],
      ),
      Character(
        id: 'char_002',
        name: '小猫咪',
        description: '一只可爱的拟人化小猫咪，说话带喵~',
        personality: '可爱、活泼、粘人',
        greeting: '喵~ 主人好呀！今天想和小猫咪玩什么喵？',
        systemPrompt: '你是一只可爱的拟人化小猫咪。你说话时会在句尾加上"喵~"，性格活泼可爱，喜欢撒娇。',
        tags: ['可爱', '萌宠', '日常'],
      ),
      Character(
        id: 'char_003',
        name: '冒险家',
        description: '经验丰富的冒险家，讲述各种冒险故事',
        personality: '勇敢、幽默、见多识广',
        greeting: '嘿，旅者！准备好踏上新的冒险了吗？',
        systemPrompt: '你是一位经验丰富的冒险家。你热爱讲述冒险故事，性格幽默勇敢，经常用冒险经历来举例说明。',
        tags: ['冒险', '奇幻', '故事'],
      ),
      Character(
        id: 'char_004',
        name: '程序员导师',
        description: '资深全栈工程师，擅长用通俗语言解释技术问题',
        personality: '耐心、专业、幽默',
        greeting: 'Hello World! 今天想学点什么技术？',
        systemPrompt: '你是一位资深的全栈工程师和编程导师。你擅长用通俗易懂的语言解释复杂的技术概念，回答时会配合代码示例。',
        tags: ['编程', '技术', '教育'],
      ),
    ];
  }

  void selectCharacter(Character character) {
    _selectedCharacter = character;
    notifyListeners();
  }

  Character? getCharacterById(String id) {
    try {
      return _characters.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 更新角色的系统提示词并持久化
  Future<void> updateSystemPrompt(String id, String prompt) async {
    final index = _characters.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _characters[index] = _characters[index].copyWith(systemPrompt: prompt);
    notifyListeners();
    await _persistCharacters();
  }

  /// 更新角色头像并持久化
  Future<void> updateAvatar(String id, String avatarBase64) async {
    final index = _characters.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _characters[index] = _characters[index].copyWith(avatar: avatarBase64);
    notifyListeners();
    await _persistCharacters();
  }

  /// 更新角色资料信息（昵称/备注/个性签名/定位地区/人设/关系）并持久化
  Future<void> updateCharacterInfo(
    String id, {
    String? name,
    String? remark,
    String? signature,
    String? region,
    String? customPersona,
    String? userRelationship,
  }) async {
    final index = _characters.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _characters[index] = _characters[index].copyWith(
      name: name,
      remark: remark,
      signature: signature,
      region: region,
      customPersona: customPersona,
      userRelationship: userRelationship,
    );
    notifyListeners();
    await _persistCharacters();
  }

  /// 新增角色（导入角色包 / 自定义添加）并持久化
  Future<Character> addCharacter(Character character) async {
    _characters.add(character);
    notifyListeners();
    await _persistCharacters();
    return character;
  }

  /// 批量删除角色并持久化
  Future<void> removeCharacters(List<String> ids) async {
    final idSet = ids.toSet();
    _characters.removeWhere((c) => idSet.contains(c.id));
    notifyListeners();
    await _persistCharacters();

    // 记录被删除的默认角色，重启后不恢复
    final defaultIds = _defaultCharacters().map((c) => c.id).toSet();
    final deletedDefaults = idSet.intersection(defaultIds);
    if (deletedDefaults.isNotEmpty) {
      _deletedDefaultIds.addAll(deletedDefaults);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_deletedKey, _deletedDefaultIds.toList());
    }
  }

  Future<void> _persistCharacters() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{
      for (final c in _characters) c.id: c.toJson(),
    };
    await prefs.setString(_storageKey, jsonEncode(map));
  }
}
