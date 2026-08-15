import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../providers/auth_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/group_chat_provider.dart';
import '../services/memory_pool_builder.dart';
import '../widgets/character_avatar.dart';

/// 记忆池管理页：查看与管理每个角色记忆池的拼接内容。
///
/// 记忆池 = 角色「当前会话之外」的近期社交记忆，拼接进角色提示词，
/// 让角色在私聊 / 群聊 / 朋友圈互动中保持跨场景记忆连贯。
/// 本页支持：
/// - 全局调节「朋友圈记忆条数」
/// - 逐角色展开查看四类来源的拼接内容，并可单独停用某来源
///
/// 入口：【我】→【设置】→【记忆池管理】
class MemoryPoolManagerScreen extends StatefulWidget {
  const MemoryPoolManagerScreen({super.key});

  @override
  State<MemoryPoolManagerScreen> createState() =>
      _MemoryPoolManagerScreenState();
}

class _MemoryPoolManagerScreenState extends State<MemoryPoolManagerScreen> {
  /// 已展开查看详情的角色 id 集合
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final chatSettings = context.watch<ChatSettingsProvider>();
    final characterProvider = context.watch<CharacterProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final groupChatProvider = context.watch<GroupChatProvider>();

    final characters = characterProvider.manageableCharacters;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('记忆池管理')),
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          // 功能说明
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('说明'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  '记忆池会聚合角色最近的私聊、朋友圈、群聊与资料卡内容，'
                  '拼入角色提示词，让角色在私聊 / 群聊 / 朋友圈互动中记得你说过什么。'
                  '下方可逐角色查看拼接内容，并单独停用某一类来源。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
          // 全局：朋友圈记忆条数
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('全局设置'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '记忆池携带朋友圈条数',
                      style: TextStyle(
                        fontSize: 16,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        chatSettings.momentMemoryCount == 0
                            ? '不携带'
                            : '${chatSettings.momentMemoryCount} 条',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlider(
                    value: chatSettings.momentMemoryCount
                        .clamp(0, 10)
                        .toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    activeColor: context.accentColor,
                    onChanged: (value) =>
                        chatSettings.setMomentMemoryCount(value.round()),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  '0 = 不携带；最多 10 条（含每条的全部点赞与评论）',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (characters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                '暂无角色',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondaryColor),
              ),
            )
          else
            for (final c in characters)
              _CharacterCard(
                character: c,
                expanded: _expanded.contains(c.id),
                sections: MemoryPoolBuilder.buildSections(
                  character: c,
                  chatProvider: chatProvider,
                  groupChatProvider: groupChatProvider,
                  chatSettings: chatSettings,
                  user: context.read<AuthProvider>().user,
                  includePrivateHistory: true,
                ),
                onToggleExpand: () => setState(() {
                  if (!_expanded.add(c.id)) _expanded.remove(c.id);
                }),
                onSectionChanged: (title, enabled) =>
                    chatSettings.setPoolSectionEnabled(c.id, title, enabled),
              ),
        ],
      ),
    );
  }
}

/// 单个角色的记忆池卡片：头部（头像 + 名称 + 箭头），展开后逐来源展示。
class _CharacterCard extends StatelessWidget {
  final Character character;
  final bool expanded;

  /// 当前实际会拼入提示词的来源区块（已按启停状态过滤）
  final List<MapEntry<String, String>> sections;
  final VoidCallback onToggleExpand;
  final void Function(String title, bool enabled) onSectionChanged;

  const _CharacterCard({
    required this.character,
    required this.expanded,
    required this.sections,
    required this.onToggleExpand,
    required this.onSectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final disabled =
        context.watch<ChatSettingsProvider>().disabledPoolSectionsFor(character.id);

    String? contentOf(String title) {
      for (final e in sections) {
        if (e.key == title) return e.value;
      }
      return null;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          CupertinoListTile(
            leading: CharacterAvatar(
              base64: character.avatar,
              size: 40,
            ),
            title: Text(
              character.displayName,
              style: TextStyle(
                fontSize: 16,
                color: context.textPrimaryColor,
              ),
            ),
            subtitle: Text(
              expanded ? '点击收起详情' : '点击查看记忆池拼接内容',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
            trailing: Icon(
              expanded
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              size: 16,
              color: context.textSecondaryColor,
            ),
            onTap: onToggleExpand,
          ),
          if (expanded) ...[
            Container(height: 0.5, color: context.separatorColor),
            _SectionRow(
              title: MemoryPoolBuilder.kPrivateSectionTitle,
              content: contentOf(MemoryPoolBuilder.kPrivateSectionTitle),
              enabled: !disabled.contains(MemoryPoolBuilder.kPrivateSectionTitle),
              onChanged: (v) => onSectionChanged(
                MemoryPoolBuilder.kPrivateSectionTitle,
                v,
              ),
            ),
            _SectionRow(
              title: MemoryPoolBuilder.kMomentsSectionTitle,
              content: contentOf(MemoryPoolBuilder.kMomentsSectionTitle),
              enabled:
                  !disabled.contains(MemoryPoolBuilder.kMomentsSectionTitle),
              onChanged: (v) => onSectionChanged(
                MemoryPoolBuilder.kMomentsSectionTitle,
                v,
              ),
            ),
            _SectionRow(
              title: MemoryPoolBuilder.kGroupSectionTitle,
              content: contentOf(MemoryPoolBuilder.kGroupSectionTitle),
              enabled: !disabled.contains(MemoryPoolBuilder.kGroupSectionTitle),
              onChanged: (v) => onSectionChanged(
                MemoryPoolBuilder.kGroupSectionTitle,
                v,
              ),
            ),
            _SectionRow(
              title: MemoryPoolBuilder.kCardSectionTitle,
              content: contentOf(MemoryPoolBuilder.kCardSectionTitle),
              enabled: !disabled.contains(MemoryPoolBuilder.kCardSectionTitle),
              onChanged: (v) => onSectionChanged(
                MemoryPoolBuilder.kCardSectionTitle,
                v,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个来源行：标题 + 启停开关 + 拼接内容预览
class _SectionRow extends StatelessWidget {
  final String title;
  final String? content;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SectionRow({
    required this.title,
    required this.content,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                ),
              ),
              CupertinoSwitch(value: enabled, onChanged: onChanged),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _buildPreview(context),
        ),
        Container(height: 0.5, color: context.separatorColor),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    if (!enabled) {
      return Text(
        '已停用，不拼入记忆池',
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: context.textSecondaryColor,
        ),
      );
    }
    final text = content?.trim() ?? '';
    if (text.isEmpty) {
      return Text(
        '暂无内容',
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: context.textSecondaryColor,
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.fieldBgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: context.textSecondaryColor,
        ),
      ),
    );
  }
}
