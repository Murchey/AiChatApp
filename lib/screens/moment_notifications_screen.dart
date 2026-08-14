import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/moment_notification.dart';
import '../providers/character_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../widgets/character_avatar.dart';

/// 朋友圈消息页：展示「某角色给某动态点了赞 / 评论了什么，
/// 或回复了用户的评论」。
///
/// 从朋友圈左上角铃铛图标进入；进入即全部标记已读（铃铛角标与底部
/// tab 红点消失）。内容仅展示，无需点击跳转。
class MomentNotificationsScreen extends StatefulWidget {
  const MomentNotificationsScreen({super.key});

  @override
  State<MomentNotificationsScreen> createState() =>
      _MomentNotificationsScreenState();
}

class _MomentNotificationsScreenState extends State<MomentNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // 打开通知页即视为已读
    context.read<MomentNotificationProvider>().markAllRead();
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final d = time.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(d.hour)}:${two(d.minute)}';
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '昨天 $hm';
    if (d.year == now.year) return '${two(d.month)}-${two(d.day)} $hm';
    return '${d.year}-${two(d.month)}-${two(d.day)} $hm';
  }

  /// 通知内容摘要：动态文字截断
  String _momentPreview(MomentNotification n) {
    if (n.momentContent.trim().isEmpty) return '图片动态';
    final text = n.momentContent.trim().replaceAll('\n', ' ');
    return text.length > 24 ? '${text.substring(0, 24)}…' : text;
  }

  /// 底部「清除全部通知」：二次确认后清空
  Future<void> _confirmClear() async {
    final provider = context.read<MomentNotificationProvider>();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('清除通知'),
        content: const Text('确定要清除全部互动通知吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await provider.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('朋友圈消息'),
      ),
      child: Consumer<MomentNotificationProvider>(
        builder: (context, provider, _) {
          final characterProvider = context.watch<CharacterProvider>();
          final activities = provider.activities;
          if (activities.isEmpty) {
            return Center(
              child: Text(
                '暂无消息',
                style: TextStyle(
                  fontSize: 14,
                  color: context.textSecondaryColor,
                ),
              ),
            );
          }
          return Container(
            color: context.scaffoldColor,
            child: Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    itemCount: activities.length,
                    separatorBuilder: (_, __) => Container(
                      height: 0.5,
                      margin: const EdgeInsets.only(left: 61),
                      color: context.separatorColor,
                    ),
                    itemBuilder: (context, index) {
                      final n = activities[index];
                      final character = characterProvider
                          .getCharacterById(n.characterId);
                      // 动态发布者是「我」还是某个角色：决定「赞了你的动态」/「赞了 A 的朋友圈」
                      final isMine = n.ownerCharacterId.isEmpty ||
                          n.ownerCharacterId ==
                              CharacterProvider.selfCharacterId;
                      final target = isMine
                          ? '你的动态'
                          : '${n.ownerCharacterName.isEmpty ? '他' : n.ownerCharacterName}的朋友圈';
                      final actions = <String>[
                        if (n.liked) '赞了$target',
                        if (n.comment.isNotEmpty && !n.isReply) '评论了$target',
                        if (n.isReply) '回复了你的评论',
                      ];
                      final actionText =
                          actions.isEmpty ? '看了$target' : actions.join('、');
                      return CupertinoListTile(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        leadingSize: 42,
                        leading: CharacterAvatar(
                          base64: character?.avatar ?? '',
                          size: 42,
                          iconSize: 22,
                        ),
                        title: Text(
                          '${n.characterName} $actionText',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (n.comment.isNotEmpty)
                                Text(
                                  n.comment,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: context.textPrimaryColor,
                                  ),
                                ),
                              Text(
                                '动态：${_momentPreview(n)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.textSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: Text(
                          _formatTime(n.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // 底部：清除全部通知
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: CupertinoButton(
                      borderRadius: BorderRadius.circular(10),
                      color: context.listBgColor,
                      pressedOpacity: 0.7,
                      onPressed: () => _confirmClear(),
                      child: const Text(
                        '清除全部通知',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.systemRed,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
