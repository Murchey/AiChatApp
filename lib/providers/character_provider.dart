import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../models/visibility_group.dart';
import '../utils/pinyin_util.dart';

class CharacterProvider extends ChangeNotifier {
  List<Character> _characters = [];
  Character? _selectedCharacter;
  bool _isLoading = false;
  static const _storageKey = 'characters_v1';
  static const _deletedKey = 'characters_deleted_v1';
  static const _visibilityGroupsKey = 'visibility_groups_v1';

  /// 通讯录中固定的"自己"账号 id：不能发起聊天，仅在空间页查看/发布朋友圈
  static const String selfCharacterId = 'me';

  /// 朋友圈展示范围自定义分组
  List<VisibilityGroup> _visibilityGroups = [];

  /// 被用户删除的默认角色 id（删除后重启不恢复）
  Set<String> _deletedDefaultIds = {};

  /// 角色数据修订号：任何角色/动态变更都会自增，
  /// 供朋友圈等页面按修订号做选择性重建（避免无关通知触发全量重建）
  int _dataRevision = 0;
  int get dataRevision => _dataRevision;

  /// 后台持久化单飞/脏标记（与聊天页一致）：高频变更合并为一次写盘
  bool _persistRunning = false;
  bool _persistDirty = false;

  List<Character> get characters => _characters;
  Character? get selectedCharacter => _selectedCharacter;
  bool get isLoading => _isLoading;

  /// "自己"账号（昵称/头像/签名取自用户资料，朋友圈本地持久化）
  Character? get selfCharacter => getCharacterById(selfCharacterId);

  /// 朋友圈展示范围自定义分组（不含固定选项【仅自己可见】【全部角色可见】）
  List<VisibilityGroup> get visibilityGroups => _visibilityGroups;

  /// 可被管理（删除 / 导出角色包等）的角色：排除固定的"自己"账号
  List<Character> get manageableCharacters =>
      _characters.where((c) => c.id != selfCharacterId).toList();

  /// 通讯录：按拼音首字母分组排序（类似手机通讯录）
  ///
  /// 排序依据为 [Character.displayName]（备注优先，无备注用昵称），
  /// 使"角色备注在通讯录生效"。
  List<MapEntry<String, List<Character>>> get sortedCharactersGrouped {
    final sorted = List<Character>.from(_characters)
      ..sort((a, b) {
        final la = PinyinUtil.firstLetter(a.displayName);
        final lb = PinyinUtil.firstLetter(b.displayName);
        if (la != lb) return la.compareTo(lb);
        return PinyinUtil.fullPinyin(a.displayName)
            .compareTo(PinyinUtil.fullPinyin(b.displayName));
      });

    final groups = <String, List<Character>>{};
    for (final c in sorted) {
      final letter = PinyinUtil.firstLetter(c.displayName);
      groups.putIfAbsent(letter, () => []).add(c);
    }
    return groups.entries.toList();
  }

  Future<void> loadCharacters() async {
    _isLoading = true;
    notifyListeners();

    // 读取本地原始数据（不含解析），随后把 JSON 反序列化、默认角色合并、
    // "自己"账号构建、动态 id 归一化等重活全部放到后台 isolate，
    // 避免含 base64 头像/背景的大 JSON 在主线程解码拖慢启动首帧。
    final prefs = await SharedPreferences.getInstance();
    final raw = _CharacterRawStore(
      stored: prefs.getString(_storageKey),
      deletedIds: prefs.getStringList(_deletedKey) ?? const [],
      visibilityGroupsStr: prefs.getString(_visibilityGroupsKey),
      nickname: prefs.getString('user_nickname') ?? '',
      avatar: prefs.getString('user_avatar') ?? '',
      signature: prefs.getString('user_signature') ?? '',
    );

    _CharacterDecoded? decoded;
    try {
      decoded = await compute(_decodeCharacterStore, raw);
    } catch (e) {
      debugPrint('[CharacterProvider] 加载角色数据失败，按空数据启动: $e');
    }
    if (decoded != null) {
      _characters = decoded.characters;
      _visibilityGroups = decoded.visibilityGroups;
      _deletedDefaultIds = decoded.deletedIds;
    }
    _isLoading = false;
    _dataRevision++;
    notifyListeners();
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

  /// 更新角色详情页背景图并持久化
  Future<void> updateBackground(String id, String backgroundBase64) async {
    final index = _characters.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _characters[index] =
        _characters[index].copyWith(background: backgroundBase64);
    notifyListeners();
    await _persistCharacters();
  }

  /// 更新角色资料信息（昵称/备注/个性签名/定位地区/关系/活跃时段）并持久化
  Future<void> updateCharacterInfo(
    String id, {
    String? name,
    String? remark,
    String? signature,
    String? region,
    String? userRelationship,
    String? activeStart,
    String? activeEnd,
  }) async {
    final index = _characters.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _characters[index] = _characters[index].copyWith(
      name: name,
      remark: remark,
      signature: signature,
      region: region,
      userRelationship: userRelationship,
      activeStart: activeStart,
      activeEnd: activeEnd,
    );
    notifyListeners();
    await _persistCharacters();
  }

  /// 更新角色的朋友圈动态并持久化
  Future<void> updateMoments(String id, List<Moment> moments) async {
    final index = _characters.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _characters[index] = _characters[index].copyWith(moments: moments);
    notifyListeners();
    await _persistCharacters();
  }

  /// 同步"自己"账号资料（昵称/头像/签名），与用户资料保持一致
  Future<void> syncSelfFromUser({
    String? nickname,
    String? avatar,
    String? signature,
  }) async {
    final index = _characters.indexWhere((c) => c.id == selfCharacterId);
    final trimmed = nickname?.trim();
    if (index == -1) {
      if (trimmed == null || trimmed.isEmpty) return;
      _characters.add(Character(
        id: selfCharacterId,
        name: trimmed,
        avatar: avatar ?? '',
        signature: signature ?? '',
      ));
    } else {
      final cur = _characters[index];
      _characters[index] = cur.copyWith(
        name: trimmed != null && trimmed.isNotEmpty ? trimmed : cur.name,
        avatar: avatar,
        signature: signature,
      );
    }
    notifyListeners();
    await _persistCharacters();
  }

  /// 以"自己"身份发布一条朋友圈（新动态置顶显示），返回发布成功的动态。
  Future<Moment> publishSelfMoment({
    required String content,
    required List<String> images,
    String location = '',
    String visibility = 'all',
  }) async {
    final index = _characters.indexWhere((c) => c.id == selfCharacterId);
    if (index == -1) {
      throw StateError('self character not found');
    }
    final moment = Moment(
      id: 'moment_${DateTime.now().microsecondsSinceEpoch}',
      content: content.trim(),
      location: location.trim(),
      visibility: visibility,
      images: images,
      createdAt: DateTime.now(),
    );
    _characters[index] = _characters[index]
        .copyWith(moments: [moment, ..._characters[index].moments]);
    notifyListeners();
    await _persistCharacters();
    return moment;
  }

  /// 新增角色（导入角色包 / 自定义添加）并持久化
  Future<Character> addCharacter(Character character) async {
    _characters.add(character);
    notifyListeners();
    await _persistCharacters();
    return character;
  }

  /// 按名称查找角色（用于重名判断 / 覆盖导入定位目标）
  Character? findCharacterByName(String name) {
    final trimmed = name.trim();
    for (final c in _characters) {
      if (c.name.trim() == trimmed) return c;
    }
    return null;
  }

  /// 用导入的数据覆盖现有角色（保留 id，聊天记录不受影响）：
  /// 替换资料、提示词、朋友圈等除聊天记录外的全部角色卡数据。
  Future<void> overwriteCharacter(Character character) async {
    final index = _characters.indexWhere((c) => c.id == character.id);
    if (index == -1) {
      _characters.add(character);
    } else {
      _characters[index] = character;
    }
    notifyListeners();
    await _persistCharacters();
  }

  /// 新建朋友圈展示范围分组（初始为空，联系人后续在分组管理页编辑）
  Future<VisibilityGroup> addVisibilityGroup(String name) async {
    final group = VisibilityGroup(
      id: 'group_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
    );
    _visibilityGroups.add(group);
    notifyListeners();
    await _persistVisibilityGroups();
    return group;
  }

  /// 更新分组（名称 / 联系人）并持久化
  Future<void> updateVisibilityGroup(VisibilityGroup group) async {
    final index = _visibilityGroups.indexWhere((g) => g.id == group.id);
    if (index == -1) return;
    _visibilityGroups[index] = group;
    notifyListeners();
    await _persistVisibilityGroups();
  }

  /// 删除分组并持久化
  Future<void> removeVisibilityGroup(String id) async {
    _visibilityGroups.removeWhere((g) => g.id == id);
    notifyListeners();
    await _persistVisibilityGroups();
  }

  /// 批量删除角色并持久化（"自己"账号不可删除）
  Future<void> removeCharacters(List<String> ids) async {
    final idSet = ids.where((id) => id != selfCharacterId).toSet();
    if (idSet.isEmpty) return;
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
    // 每次变更都推进修订号（在进入异步之前同步自增，确保下一帧重建读到新值）
    _dataRevision++;
    if (_persistRunning) {
      _persistDirty = true;
      return;
    }
    _persistRunning = true;
    try {
      do {
        _persistDirty = false;
        // 浅拷贝快照（指针级，开销小），确保后台序列化期间数据一致；
        // 含 base64 头像/背景的大 JSON 在后台 isolate 序列化，避免主线程卡顿
        final snapshot = List<Character>.of(_characters);
        final encoded = await compute(_encodeCharacterStore, snapshot);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, encoded);
      } while (_persistDirty);
    } catch (e) {
      // 持久化失败不阻塞主流程（多为平台通道/磁盘异常），下次变更会再次尝试
      debugPrint('[CharacterProvider] 持久化失败: $e');
    } finally {
      _persistRunning = false;
    }
  }

  Future<void> _persistVisibilityGroups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _visibilityGroupsKey,
      jsonEncode(_visibilityGroups.map((g) => g.toJson()).toList()),
    );
  }

  /// 清除全部角色与朋友圈数据并恢复默认角色（管理占用空间页使用）：
  /// 删除角色卡（含头像/背景 base64）、朋友圈动态、分组与被删记录，
  /// 随后重新加载内置默认角色；用户资料（昵称/头像/签名）不受影响。
  Future<void> resetAllData() async {
    _characters = [];
    _visibilityGroups = [];
    _deletedDefaultIds = {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_visibilityGroupsKey);
    await prefs.remove(_deletedKey);
    await loadCharacters();
  }
}

// ─── 角色加载跨 isolate 传输的数据结构与解码函数 ─────────────────

/// 本地存储的原始数据（供后台 isolate 反序列化）。
class _CharacterRawStore {
  final String? stored;
  final List<String> deletedIds;
  final String? visibilityGroupsStr;
  final String nickname;
  final String avatar;
  final String signature;

  const _CharacterRawStore({
    this.stored,
    required this.deletedIds,
    this.visibilityGroupsStr,
    required this.nickname,
    required this.avatar,
    required this.signature,
  });
}

/// 后台 isolate 解码后的结果。
class _CharacterDecoded {
  final List<Character> characters;
  final List<VisibilityGroup> visibilityGroups;
  final Set<String> deletedIds;

  const _CharacterDecoded({
    required this.characters,
    required this.visibilityGroups,
    required this.deletedIds,
  });
}

/// 后台 isolate：把角色列表序列化为存储 JSON（含 base64 头像/背景等大数据，
/// 避免主线程 JSON 序列化造成卡顿）。
@pragma('vm:entry-point')
String _encodeCharacterStore(List<Character> characters) {
  return jsonEncode({
    for (final c in characters) c.id: c.toJson(),
  });
}

/// 后台 isolate：反序列化角色数据并完成默认角色合并、自定义角色恢复、
/// "自己"账号构建与动态 id 归一化（与旧主线程逻辑完全一致）。
@pragma('vm:entry-point')
_CharacterDecoded _decodeCharacterStore(_CharacterRawStore raw) {
  final deletedIds = raw.deletedIds.toSet();
  Map<String, dynamic> customMap = {};
  if (raw.stored != null) {
    try {
      customMap = jsonDecode(raw.stored!) as Map<String, dynamic>;
    } catch (_) {}
  }

  final defaults = _defaultCharacters()
      .where((c) => !deletedIds.contains(c.id))
      .toList();
  final defaultIds = defaults.map((c) => c.id).toSet();
  final self = _buildSelfCharacter(
    customMap[CharacterProvider.selfCharacterId] as Map<String, dynamic>?,
    raw.nickname,
    raw.avatar,
    raw.signature,
  );

  var characters = <Character>[
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
          background: custom['background'] as String? ?? c.background,
          description: custom['description'] as String? ?? c.description,
          personality: custom['personality'] as String? ?? c.personality,
          greeting: custom['greeting'] as String? ?? c.greeting,
          systemPrompt: custom['system_prompt'] as String? ?? c.systemPrompt,
          userRelationship:
              custom['user_relationship'] as String? ?? c.userRelationship,
          activeStart: custom['active_start'] as String? ?? c.activeStart,
          activeEnd: custom['active_end'] as String? ?? c.activeEnd,
          tags: (custom['tags'] as List<dynamic>?)?.cast<String>() ?? c.tags,
        );
      }
      return c;
    }),
    ...customMap.entries
        .where((e) =>
            !defaultIds.contains(e.key) &&
            e.key != CharacterProvider.selfCharacterId &&
            e.value is Map<String, dynamic>)
        .map((e) => Character.fromJson(e.value as Map<String, dynamic>)),
    if (self != null) self,
  ];
  characters = characters
      .map((c) => c.copyWith(moments: _dedupeMomentIds(c.moments)))
      .toList();

  var groups = <VisibilityGroup>[];
  final groupsStr = raw.visibilityGroupsStr;
  if (groupsStr != null) {
    try {
      groups = (jsonDecode(groupsStr) as List<dynamic>)
          .map((e) => VisibilityGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  return _CharacterDecoded(
    characters: characters,
    visibilityGroups: groups,
    deletedIds: deletedIds,
  );
}

/// 去重动态 id：空 id 或列表内重复的 id 重新生成，
/// 返回 id 全唯一的动态列表（其余字段保持不变）。
List<Moment> _dedupeMomentIds(List<Moment> moments) {
  final seen = <String>{};
  var count = 0;
  return moments.map((m) {
    var id = m.id;
    if (id.isEmpty || !seen.add(id)) {
      id = 'moment_${DateTime.now().microsecondsSinceEpoch}_$count';
      seen.add(id);
    }
    count++;
    return Moment(
      id: id,
      content: m.content,
      location: m.location,
      visibility: m.visibility,
      images: m.images,
      likes: m.likes,
      comments: m.comments,
      createdAt: m.createdAt,
    );
  }).toList();
}

/// 构建"自己"账号：昵称/头像/签名以用户资料为准（用户未设置时回退到
/// 本地存储值），朋友圈动态从本地存储恢复。
Character? _buildSelfCharacter(
  Map<String, dynamic>? stored,
  String nickname,
  String avatar,
  String signature,
) {
  final n = nickname.trim();
  if (stored != null) {
    final base = Character.fromJson(stored);
    return Character(
      id: CharacterProvider.selfCharacterId,
      name: n.isNotEmpty ? n : base.name,
      avatar: avatar.isNotEmpty ? avatar : base.avatar,
      signature: signature.isNotEmpty ? signature : base.signature,
      remark: base.remark,
      region: base.region,
      background: base.background,
      description: base.description,
      personality: base.personality,
      greeting: base.greeting,
      systemPrompt: base.systemPrompt,
      userRelationship: base.userRelationship,
      tags: base.tags,
      moments: base.moments,
    );
  }
  return Character(
    id: CharacterProvider.selfCharacterId,
    name: n.isNotEmpty ? n : '我',
    avatar: avatar,
    signature: signature,
  );
}

/// 内置默认角色列表。
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
