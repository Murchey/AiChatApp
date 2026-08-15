import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/token_usage.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/group_chat_provider.dart';
import '../providers/token_usage_provider.dart';
import '../utils/app_toast.dart';
import '../widgets/character_avatar.dart';

/// 累计消耗 tokens 统计页：分类展示每个私聊 / 群聊消耗过的 token。
///
/// 累计消耗 = 累计发送 tokens（API usage.prompt_tokens）+ 累计接收 tokens
/// （API usage.completion_tokens），在每次真实 LLM 调用成功后累加。
/// 支持一键【重置 tokens 计数】（清空全部统计）。
class TokenUsageScreen extends StatefulWidget {
  const TokenUsageScreen({super.key});

  @override
  State<TokenUsageScreen> createState() => _TokenUsageScreenState();
}

class _TokenUsageScreenState extends State<TokenUsageScreen> {
  @override
  void initState() {
    super.initState();
    TokenUsageProvider.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<TokenUsageProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final groupProvider = context.watch<GroupChatProvider>();
    final characterProvider = context.watch<CharacterProvider>();

    // 分类：朋友圈固定 id → 朋友圈；群聊 id 命中群列表 → 群聊；其余归私聊（含已删除的私聊会话）
    final groupIds = groupProvider.groups.map((g) => g.id).toSet();
    final momentUsage = usage.allUsages[TokenUsageProvider.kMomentUsageId];
    final privateEntries = <MapEntry<String, TokenUsage>>[];
    final groupEntries = <MapEntry<String, TokenUsage>>[];
    usage.allUsages.forEach((id, u) {
      if (u.isEmpty) return;
      if (id == TokenUsageProvider.kMomentUsageId) return; // 朋友圈单独展示
      if (groupIds.contains(id)) {
        groupEntries.add(MapEntry(id, u));
      } else {
        privateEntries.add(MapEntry(id, u));
      }
    });
    _sortByTotal(privateEntries);
    _sortByTotal(groupEntries);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('累计消耗tokens')),
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 40),
        children: [
          // 汇总
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('汇总'),
            children: [
              _SummaryRow(label: '累计输入 tokens', value: usage.sentTotal),
              Container(height: 0.5, color: context.separatorColor),
              _SummaryRow(label: '累计输出 tokens', value: usage.receivedTotal),
              Container(height: 0.5, color: context.separatorColor),
              _SummaryRow(label: '累计消耗', value: usage.total, highlight: true),
              Container(height: 0.5, color: context.separatorColor),
              _SummaryRow(
                label: '累计朋友圈 tokens',
                value: momentUsage?.totalTokens ?? 0,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              '累计输入 = Σ 每轮实际发送给 API 的 prompt_tokens（已含系统提示词与多轮历史上下文回传）；'
              '累计输出 = Σ 每轮 API 返回的 completion_tokens',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if ((momentUsage == null || momentUsage.isEmpty) &&
              privateEntries.isEmpty &&
              groupEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                '暂无记录\n去和角色私聊、在群里说话或产生朋友圈互动后，这里会展示消耗的 token',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
          if (momentUsage != null && !momentUsage.isEmpty)
            CupertinoListSection.insetGrouped(
              backgroundColor: context.scaffoldColor,
              decoration: BoxDecoration(
                color: context.listBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              header: const Text('朋友圈'),
              children: [
                _UsageTile(
                  title: '朋友圈互动',
                  leadingIcon: CupertinoIcons.photo_on_rectangle,
                  usage: momentUsage,
                ),
              ],
            ),
          if (privateEntries.isNotEmpty)
            CupertinoListSection.insetGrouped(
              backgroundColor: context.scaffoldColor,
              decoration: BoxDecoration(
                color: context.listBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              header: const Text('私聊'),
              children: [
                for (final e in privateEntries)
                  _buildPrivateTile(context, e, chatProvider, characterProvider),
              ],
            ),
          if (groupEntries.isNotEmpty)
            CupertinoListSection.insetGrouped(
              backgroundColor: context.scaffoldColor,
              decoration: BoxDecoration(
                color: context.listBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              header: const Text('群聊'),
              children: [
                for (final e in groupEntries)
                  _buildGroupTile(context, e, groupProvider),
              ],
            ),
          if (usage.hasAny) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoButton(
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: const Color.fromRGBO(204, 102, 0, 100),
                onPressed: () => _confirmReset(context),
                child: const Text(
                  '重置 tokens 计数',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color.fromRGBO(250, 250, 250, 100)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '重置后所有私聊与群聊的累计消耗统计将清空（仅影响本页统计，不影响聊天记录）',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrivateTile(
    BuildContext context,
    MapEntry<String, TokenUsage> e,
    ChatProvider chatProvider,
    CharacterProvider characterProvider,
  ) {
    final conversation = _firstById(
        chatProvider.conversations, e.key, (c) => c.id);
    final character = conversation != null
        ? characterProvider.getCharacterById(conversation.characterId)
        : null;
    final title = character?.displayName ??
        conversation?.characterName ??
        '已删除的会话';
    final avatar = conversation?.characterAvatar ?? '';
    return _UsageTile(
      title: title,
      avatar: avatar,
      usage: e.value,
      subtitle: conversation == null ? '会话已删除' : null,
    );
  }

  Widget _buildGroupTile(
    BuildContext context,
    MapEntry<String, TokenUsage> e,
    GroupChatProvider groupProvider,
  ) {
    final group = _firstById(groupProvider.groups, e.key, (g) => g.id);
    final title = group == null ? '已删除的群聊' : '${group.name}（${group.memberCount}）';
    return _UsageTile(
      title: title,
      avatar: group?.avatar ?? '',
      usage: e.value,
      subtitle: group == null ? '群聊已删除' : null,
    );
  }

  void _sortByTotal(List<MapEntry<String, TokenUsage>> list) {
    list.sort((a, b) => b.value.totalTokens.compareTo(a.value.totalTokens));
  }

  /// 按 id 在列表中查找首个匹配项，未找到返回 null
  T? _firstById<T>(List<T> list, String id, String Function(T) idOf) {
    for (final item in list) {
      if (idOf(item) == id) return item;
    }
    return null;
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('重置 tokens 计数'),
        content: const Text('确定要清空所有私聊与群聊的累计消耗统计吗？此操作不可恢复。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('重置'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await TokenUsageProvider.instance.resetAll();
    if (mounted) showAppToast('已重置 tokens 计数');
  }
}

/// 千分位格式化：1234567 → 1,234,567
String _fmtTokens(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int value;
  final bool highlight;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: context.textPrimaryColor,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            _fmtTokens(value),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: highlight ? context.accentColor : context.textPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageTile extends StatelessWidget {
  final String title;
  final String? avatar;
  final TokenUsage usage;
  final String? subtitle;

  /// 无头像场景（如朋友圈聚合）用图标占位
  final IconData? leadingIcon;

  const _UsageTile({
    required this.title,
    this.avatar,
    required this.usage,
    this.subtitle,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final sub = subtitle ??
        '输入 ${_fmtTokens(usage.sentTokens)} · 输出 ${_fmtTokens(usage.receivedTokens)}';
    return CupertinoListTile(
      leading: leadingIcon != null
          ? Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                leadingIcon,
                size: 20,
                color: context.accentColor,
              ),
            )
          : CharacterAvatar(base64: avatar ?? '', size: 40),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 16, color: context.textPrimaryColor),
      ),
      subtitle: Text(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
      ),
      trailing: Text(
        _fmtTokens(usage.totalTokens),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: context.accentColor,
        ),
      ),
    );
  }
}
