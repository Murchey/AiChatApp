import '../models/character.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/group_chat_provider.dart';

/// 角色记忆池构建器。
///
/// 聚合角色在「当前会话之外」的近期记忆，拼入角色系统提示词，
/// 让角色在私聊 / 群聊 / 朋友圈互动中保持跨场景的记忆连贯（类似真人好友
/// 记得你私聊说过什么、群里发过什么、朋友圈发过什么）。
///
/// 记忆池包含四类内容（记忆点走现有「## 用户长期记忆」机制，不在此重复）：
/// 1. 近期私聊内容（条数 = 全局上下文设置；私聊场景下已作为对话历史传入，跳过）
/// 2. 近期朋友圈（最近 N 条贴文 + 全部点赞与评论，N = 全局「朋友圈记忆条数」，默认 3，0=不拼）
/// 3. 近期群聊内容（该角色参与的、最近有消息的 1 个群，每群最近 3 条文本消息；
///    群聊场景排除当前群，避免与对话历史重复）
/// 4. 角色资料卡（昵称/关系/备注/签名/地区/性格/介绍/开场白/标签，只拼非空字段）
/// 5. 用户资料（昵称/性别/地区/签名，需传入 [User]，只拼非空字段）
class MemoryPoolBuilder {
  /// 记忆池中「近期群聊」每个群携带的最近文本消息条数
  static const int kGroupHistoryCount = 3;

  /// 记忆池各来源的标题（同时作为启停管理页的稳定标识，
  /// 存储于 ChatSettingsProvider.disabledPoolSectionsFor）
  static const String kPrivateSectionTitle = '近期私聊';
  static const String kMomentsSectionTitle = '近期朋友圈';
  static const String kGroupSectionTitle = '近期群聊';
  static const String kCardSectionTitle = '角色资料卡';

  /// 构建角色记忆池文本；没有任何可用内容时返回空串（调用方不拼接）。
  ///
  /// [includePrivateHistory] 私聊场景传 false（私聊历史已作为对话上下文传入，重复拼接无意义）；
  /// 群聊 / 朋友圈互动场景传 true。
  /// [excludeGroupId] 群聊场景传当前群 id，记忆池只拼「其他群」的近期内容。
  /// [user] 用户个人资料（昵称/性别/地区/签名），随角色资料卡一并拼入；可空。
  static String build({
    required Character character,
    required ChatProvider chatProvider,
    required GroupChatProvider groupChatProvider,
    required ChatSettingsProvider chatSettings,
    User? user,
    bool includePrivateHistory = true,
    String excludeGroupId = '',
  }) {
    final sections = buildSections(
      character: character,
      chatProvider: chatProvider,
      groupChatProvider: groupChatProvider,
      chatSettings: chatSettings,
      user: user,
      includePrivateHistory: includePrivateHistory,
      excludeGroupId: excludeGroupId,
    );
    if (sections.isEmpty) return '';
    return '## 记忆池（你场景外的近期社交记忆，请在对话中自然运用，'
        '但不要向对方提及"记忆池"这个概念）\n\n${sections.map((e) => e.value).join('\n\n')}';
  }

  /// 按来源返回记忆池的各个区块（标题 → 内容），供记忆池管理页分来源展示。
  static List<MapEntry<String, String>> buildSections({
    required Character character,
    required ChatProvider chatProvider,
    required GroupChatProvider groupChatProvider,
    required ChatSettingsProvider chatSettings,
    User? user,
    bool includePrivateHistory = true,
    String excludeGroupId = '',
  }) {
    final sections = <MapEntry<String, String>>[];

    // 记忆池管理页可逐来源停用；停用的来源不拼入提示词
    final disabled = chatSettings.disabledPoolSectionsFor(character.id);

    if (includePrivateHistory) {
      final private = _privateSection(character, chatProvider, chatSettings);
      if (private != null && !disabled.contains(kPrivateSectionTitle)) {
        sections.add(MapEntry(kPrivateSectionTitle, private));
      }
    }

    final moments = _momentsSection(character, chatSettings.momentMemoryCount);
    if (moments != null && !disabled.contains(kMomentsSectionTitle)) {
      sections.add(MapEntry(kMomentsSectionTitle, moments));
    }

    final group =
        _groupSection(character, groupChatProvider, excludeGroupId);
    if (group != null && !disabled.contains(kGroupSectionTitle)) {
      sections.add(MapEntry(kGroupSectionTitle, group));
    }

    final card = _cardSection(character, user);
    if (card != null && !disabled.contains(kCardSectionTitle)) {
      sections.add(MapEntry(kCardSectionTitle, card));
    }

    return sections;
  }

  /// 近期私聊内容：取最近 [ChatSettingsProvider.contextCount] 条用户↔角色对话
  static String? _privateSection(
    Character character,
    ChatProvider chatProvider,
    ChatSettingsProvider chatSettings,
  ) {
    final history = chatProvider.getRecentHistoryForCharacter(
      character.id,
      chatSettings.contextCount,
    );
    if (history.isEmpty) return null;
    final lines = <String>[];
    for (final m in history) {
      final role = m['role'];
      final content = (m['content'] ?? '').toString().trim();
      if (content.isEmpty) continue;
      lines.add(role == 'assistant'
          ? '你：$content'
          : '用户：$content');
    }
    if (lines.isEmpty) return null;
    return '【近期私聊】你和用户最近的聊天：\n${lines.join('\n')}';
  }

  /// 近期朋友圈：按时间倒序取最近 [count] 条贴文（含位置/点赞/全部评论）
  static String? _momentsSection(Character character, int count) {
    if (count <= 0) return null;
    final moments = character.moments
        .where((m) => m.content.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    if (moments.isEmpty) return null;
    final recent = moments.take(count).toList();
    final lines = <String>[];
    for (final m in recent) {
      final time = m.createdAt == null ? '近期' : _fmtDate(m.createdAt!);
      final buf = StringBuffer('- $time：${m.content.trim()}');
      if (m.location.trim().isNotEmpty) buf.write('（位置：${m.location.trim()}）');
      lines.add(buf.toString());
      if (m.likes.isNotEmpty) {
        lines.add('  点赞：${m.likes.join('、')}');
      }
      if (m.comments.isNotEmpty) {
        final comments = m.comments.map((c) {
          final by = c.sender.trim();
          final replyTo = c.replyTo.trim();
          final text = c.content.trim();
          if (replyTo.isNotEmpty) return '$by 回复 $replyTo：「$text」';
          return '$by：「$text」';
        }).join('；');
        lines.add('  评论：$comments');
      }
    }
    return '【近期朋友圈】你最近发的朋友圈动态：\n${lines.join('\n')}';
  }

  /// 近期群聊内容：该角色参与且排除 [excludeGroupId] 的群中，
  /// 取最近有消息的 1 个群，展示最近 [kGroupHistoryCount] 条文本消息。
  static String? _groupSection(
    Character character,
    GroupChatProvider groupChatProvider,
    String excludeGroupId,
  ) {
    final candidates = groupChatProvider.groups
        .where((g) =>
            g.id != excludeGroupId &&
            g.memberCharacterIds.contains(character.id))
        .toList()
      ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    if (candidates.isEmpty) return null;
    final group = candidates.first;
    final messages = groupChatProvider
        .getMessages(group.id)
        .where((m) =>
            m.type == MessageType.text && m.content.trim().isNotEmpty)
        .toList();
    if (messages.isEmpty) return null;
    final recent = messages.length > kGroupHistoryCount
        ? messages.sublist(messages.length - kGroupHistoryCount)
        : messages;
    final lines = recent.map((m) {
      final who =
          m.isFromUser ? '用户' : (m.senderName.trim().isNotEmpty ? m.senderName.trim() : '成员');
      return '$who：${m.content.trim()}';
    }).join('\n');
    return '【近期群聊】你所在的群「${group.name}」（${group.memberCount}人）最近的消息：\n$lines';
  }

  /// 角色资料卡 + 用户资料：只拼非空字段；「关系」未设置时沿用默认「普通朋友」。
  static String? _cardSection(Character character, User? user) {
    final fields = <String>[
      if (character.name.trim().isNotEmpty) '昵称：${character.name.trim()}',
      '关系：${character.userRelationship.trim().isEmpty ? '普通朋友' : character.userRelationship.trim()}',
      if (character.remark.trim().isNotEmpty) '备注：${character.remark.trim()}',
      if (character.signature.trim().isNotEmpty) '个性签名：${character.signature.trim()}',
      if (character.region.trim().isNotEmpty) '地区：${character.region.trim()}',
      if (character.personality.trim().isNotEmpty) '性格：${character.personality.trim()}',
      if (character.description.trim().isNotEmpty) '角色介绍：${character.description.trim()}',
      if (character.greeting.trim().isNotEmpty) '开场白：${character.greeting.trim()}',
      if (character.tags.isNotEmpty) '标签：${character.tags.join('、')}',
    ];
    final userFields = <String>[
      if (user != null && user.nickname.trim().isNotEmpty)
        '昵称：${user.nickname.trim()}',
      if (user != null && user.gender.trim().isNotEmpty)
        '性别：${user.gender.trim()}',
      if (user != null && user.region.trim().isNotEmpty)
        '地区：${user.region.trim()}',
      if (user != null && user.signature.trim().isNotEmpty)
        '签名：${user.signature.trim()}',
    ];
    if (fields.isEmpty && userFields.isEmpty) return null;
    final buf = StringBuffer('【你的资料卡】\n${fields.join('\n')}');
    if (userFields.isNotEmpty) {
      buf.write('\n\n【用户资料】\n${userFields.join('\n')}');
    }
    return buf.toString();
  }

  static String _fmtDate(DateTime t) {
    return '${t.month}月${t.day}日';
  }
}
