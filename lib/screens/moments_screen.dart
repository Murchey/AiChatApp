import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../providers/character_provider.dart';
import '../widgets/moment_card.dart';
import 'character_detail_screen.dart';

/// 朋友圈页：按发布时间倒序展示全部通讯录好友的朋友圈动态。
/// 点击某条动态可进入对应角色的空间页。
class MomentsScreen extends StatelessWidget {
  const MomentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('朋友圈'),
      ),
      backgroundColor: const Color(0xFF18181A),
      child: Consumer<CharacterProvider>(
        builder: (context, provider, _) {
          // 聚合所有角色的动态（含无时间字段的排到最后）
          final items = <(Character, Moment)>[];
          for (final c in provider.characters) {
            for (final m in c.moments) {
              items.add((c, m));
            }
          }
          items.sort((a, b) {
            final t1 = a.$2.createdAt;
            final t2 = b.$2.createdAt;
            if (t1 == null && t2 == null) return 0;
            if (t1 == null) return 1;
            if (t2 == null) return -1;
            return t2.compareTo(t1);
          });

          if (items.isEmpty) {
            return Center(
              child: Text(
                '暂无朋友圈动态',
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.systemGrey.withValues(alpha: 0.8),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final (character, moment) = items[i];
              return Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) =>
                            CharacterDetailScreen(characterId: character.id),
                      ),
                    );
                  },
                  child: MomentCard(character: character, moment: moment),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
