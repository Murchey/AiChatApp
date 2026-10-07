import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/ui_spec.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../providers/character_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/character/moments_scroll_physics.dart';
import '../widgets/moment_card.dart';
import '../widgets/publish_moment_screen.dart';
import 'moment_detail_screen.dart';
import 'moment_notifications_screen.dart';

/// 朋友圈页：按发布时间倒序展示全部通讯录好友（含"自己"）的朋友圈动态。
/// 点击某条动态可进入动态详情页；右上角相机按钮可发布朋友圈；
/// 左上角铃铛图标查看角色互动通知（带未读红点角标）。
class MomentsScreen extends StatefulWidget {
  /// 首页传入当前导航样式，使页面在样式切换时同步更新底部安全留白。
  /// 桌面端没有悬浮导航时保持为空，沿用原有默认行为。
  final HomeNavigationStyle? navigationStyle;

  const MomentsScreen({super.key, this.navigationStyle});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  final ScrollController _scrollController = ScrollController();

  double? _pendingScrollOffset;
  bool _pendingWasAtEnd = false;
  bool _reconcileScheduled = false;

  /// 聚合 + 排序后的动态列表缓存：仅当角色数据真正变化（修订号变更）时重算，
  /// 避免每次 provider 通知（如选中角色等无关变更）都重新全量聚合排序
  List<(Character, Moment)> _feed = const [];
  int _lastRevision = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MomentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationStyle != widget.navigationStyle) {
      _scheduleScrollReconcile();
    }
  }

  /// 导航样式切换会改变列表底部留白和 viewport 高度。
  /// 记录切换前的锚点，待新布局完成后一次性校正，避免旧的惯性活动
  /// 与新的 maxScrollExtent 反复竞争造成位置抖动。
  void _scheduleScrollReconcile() {
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      _pendingScrollOffset = position.pixels;
      _pendingWasAtEnd = position.maxScrollExtent - position.pixels <= 24.0;
    }
    if (_reconcileScheduled) return;
    _reconcileScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reconcileScheduled = false;
      if (!mounted) return;
      final offset = _pendingScrollOffset;
      if (offset == null || !_scrollController.hasClients) return;
      _pendingScrollOffset = null;

      final position = _scrollController.position;
      final target = (_pendingWasAtEnd
              ? position.maxScrollExtent
              : offset.clamp(
                  position.minScrollExtent,
                  position.maxScrollExtent,
                ))
          .toDouble();

      // jumpTo 会结束旧的 ballistic activity；即使目标位置没有变化，
      // 也要执行一次以清掉因 viewport 变化而残留的惯性模拟。
      _scrollController.jumpTo(target);
    });
  }

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
    // 只监听数据修订号：角色数据真正变化才重建列表；
    // 选中角色/加载等不改变数据的通知不会触发全量重建。
    final revision = context.select<CharacterProvider, int>(
      (provider) => provider.dataRevision,
    );
    _rebuildFeed(context.read<CharacterProvider>(), revision);

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
      child: _feed.isEmpty
          ? Center(
              child: Text(
                '暂无朋友圈动态',
                style: TextStyle(
                  fontSize: 14,
                  color: context.textSecondaryColor,
                ),
              ),
            )
          : ListView.builder(
              key: const PageStorageKey<String>('home-moments-feed'),
              controller: _scrollController,
              // 首页没有封面下拉语义，顶部采用稳定硬边界，避免负向惯性
              // 穿透边界后反复重启弹簧造成快速手势抖动。
              physics: const MomentsScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
                allowTopOverscroll: false,
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 12,
                bottom: (widget.navigationStyle == null
                        ? context.homeContentBottomInset
                        : widget.navigationStyle == HomeNavigationStyle.floating
                            ? UiSpec.floatingContentBottomInset
                            : UiSpec.bottomPanelContentBottomInset) +
                    MediaQuery.viewPaddingOf(context).bottom +
                    24,
              ),
              itemCount: _feed.length,
              itemBuilder: (context, i) {
                final (character, moment) = _feed[i];
                return RepaintBoundary(
                  key: ValueKey('${character.id}_${moment.id}'),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 12,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => MomentDetailScreen(
                              characterId: character.id,
                              momentId: moment.id,
                            ),
                          ),
                        );
                      },
                      child: MomentCard(
                        character: character,
                        moment: moment,
                        onOpenDetail: () => _openMomentDetail(
                          context,
                          character.id,
                          moment.id,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _openMomentDetail(
    BuildContext context,
    String characterId,
    String momentId,
  ) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => MomentDetailScreen(
          characterId: characterId,
          momentId: momentId,
        ),
      ),
    );
  }
}
