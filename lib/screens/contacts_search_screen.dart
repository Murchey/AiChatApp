import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../providers/character_provider.dart';
import '../utils/pinyin_util.dart';
import '../widgets/character_avatar.dart';

/// 通讯录搜索页：按昵称 / 备注 / 签名 / 地区 / 标签搜索角色，
/// 支持汉字与拼音（忽略大小写），点击结果进入角色详情页。
class ContactsSearchScreen extends StatefulWidget {
  const ContactsSearchScreen({super.key});

  @override
  State<ContactsSearchScreen> createState() => _ContactsSearchScreenState();
}

class _ContactsSearchScreenState extends State<ContactsSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final kw = value.trim();
    if (kw == _keyword) return;
    setState(() => _keyword = kw);
  }

  /// 命中判定：原文（昵称/备注/签名/地区/标签）或完整拼音包含关键词
  bool _matches(Character c, String query) {
    final haystack = [
      c.displayName,
      c.name,
      c.remark,
      c.signature,
      c.region,
      c.description,
      ...c.tags,
    ].join(' ').toLowerCase();
    if (haystack.contains(query)) return true;
    // 拼音匹配：如查「zhangsan」可命中「张三」
    return PinyinUtil.fullPinyin(c.displayName).contains(query);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('搜索通讯录'),
      ),
      child: Column(
        children: [
          // 搜索输入框（自动聚焦，输入即搜）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: CupertinoSearchTextField(
              controller: _controller,
              autofocus: true,
              placeholder: '搜索昵称、备注（支持中文或拼音）',
              onChanged: _onChanged,
            ),
          ),
          Expanded(
            child: _keyword.isEmpty
                ? _buildHint()
                : Consumer<CharacterProvider>(
                    builder: (context, provider, _) {
                      final query = _keyword.toLowerCase();
                      // "自己"排最前，其余按显示名拼音排序
                      final results = <Character>[
                        if (provider.selfCharacter != null)
                          provider.selfCharacter!,
                        ...provider.manageableCharacters,
                      ]
                          .where((c) => _matches(c, query))
                          .toList()
                        ..sort((a, b) => a.id == CharacterProvider.selfCharacterId
                            ? -1
                            : (b.id == CharacterProvider.selfCharacterId
                                ? 1
                                : PinyinUtil.fullPinyin(a.displayName)
                                    .compareTo(
                                        PinyinUtil.fullPinyin(b.displayName))));
                      if (results.isEmpty) return _buildEmpty();
                      return _buildResultList(results);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 未输入关键词时的引导提示
  Widget _buildHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.search,
            size: 48,
            color: context.textSecondaryColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '输入昵称或备注搜索联系人',
            style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
          ),
        ],
      ),
    );
  }

  /// 无匹配结果
  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.person_crop_circle_badge_xmark,
            size: 48,
            color: context.textSecondaryColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '未找到匹配的联系人',
            style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
          ),
        ],
      ),
    );
  }

  /// 结果列表
  Widget _buildResultList(List<Character> results) {
    return Container(
      color: context.scaffoldColor,
      child: ListView.separated(
        itemCount: results.length,
        separatorBuilder: (_, __) => Container(
          height: 0.5,
          margin: const EdgeInsets.only(left: 61),
          color: context.separatorColor,
        ),
        itemBuilder: (context, index) {
          final c = results[index];
          final subtitle = c.id == CharacterProvider.selfCharacterId
              ? (c.signature.isEmpty ? '我的朋友圈' : c.signature)
              : (c.signature.isEmpty
                  ? (c.description.isEmpty ? c.region : c.description)
                  : c.signature);
          return CupertinoListTile(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leadingSize: 45,
            leading: CharacterAvatar(base64: c.avatar, size: 45),
            title: Text(
              c.displayName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: context.textPrimaryColor,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: context.textSecondaryColor,
            ),
            onTap: () {
              Navigator.pushNamed(
                context,
                AppRoutes.characterDetail,
                arguments: c.id,
              );
            },
          );
        },
      ),
    );
  }
}
