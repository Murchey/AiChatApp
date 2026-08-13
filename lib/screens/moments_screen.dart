import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../providers/character_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../widgets/moment_card.dart';
import '../widgets/publish_moment_screen.dart';
import 'character_detail_screen.dart';
import 'moment_notifications_screen.dart';

/// 朋友圈页：按发布时间倒序展示全部通讯录好友（含"自己"）的朋友圈动态。
/// 点击某条动态可进入对应角色/自己的空间页；右上角相机按钮可发布朋友圈；
/// 左上角铃铛图标查看角色互动通知（带未读红点角标）。
class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  /// 聚合 + 排序后的动态列表缓存：仅当角色数据真正变化（修订号变更）时重算，
  /// 避免每次 provider 通知（如选中角色等无关变更）都重新全量聚合排序
  List<(Character, Moment)> _feed = const [];
  int _lastRevision = -1;

  /// 按修订号重建动态缓存；修订号未变化时直接复用，避免重复 O(N log N) 排序
  void _rebuildFeed(CharacterProvider provider, int revision) {
    if (revision == _lastRevision) return;
    _lastRevision = revision;
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
    _feed = items;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('朋友圈'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => const MomentNotificationsScreen(),
              ),
            );
          },
          // 仅监听未读状态：通知变化只重建铃铛红点，不重建整个朋友圈列表
          child: Selector<MomentNotificationProvider, bool>(
            selector: (_, p) => p.hasUnread,
            builder: (context, hasUnread, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(CupertinoIcons.bell),
                // 未读互动通知红点
                if (hasUnread)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemRed,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.navBarColor,
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (_) => const PublishMomentScreen()),
            );
          },
          child: const Icon(CupertinoIcons.camera_fill),
        ),
      ),
      backgroundColor: context.momentsBgColor,
      // 只监听数据修订号：角色数据真正变化才重建列表；
      // 选中角色/加载等不改变数据的通知不会触发全量重建
      child: Selector<CharacterProvider, int>(
        selector: (_, p) => p.dataRevision,
        builder: (context, revision, _) {
          _rebuildFeed(context.read<CharacterProvider>(), revision);
          if (_feed.isEmpty) {
            return Center(
              child: Text(
                '暂无朋友圈动态',
                style: TextStyle(
                  fontSize: 14,
                  color: context.textSecondaryColor,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            itemCount: _feed.length,
            itemBuilder: (context, i) {
              final (character, moment) = _feed[i];
              return RepaintBoundary(
                key: ValueKey('${character.id}_${moment.id}'),
                child: Padding(
                  padding:
                      const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => CharacterDetailScreen(
                            characterId: character.id,
                          ),
                        ),
                      );
                    },
                    child: MomentCard(character: character, moment: moment),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
