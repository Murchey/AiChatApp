import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../providers/group_chat_provider.dart';
import '../group_chat_detail_screen.dart';
import '../group_chat_screen.dart';
import '../group_chat_settings_screen.dart';
import 'desktop_theme.dart';

/// 桌面群聊容器。
///
/// 消息流、@成员、图片/文件、导入导出、记忆点和群回复调度全部复用手机端
/// [GroupChatScreen] 的实现；桌面只负责提供宽屏标题栏和导航入口，确保两端
/// 的业务行为长期保持一致。
class DesktopGroupChatView extends StatelessWidget {
  final String groupId;

  const DesktopGroupChatView({super.key, required this.groupId});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return ColoredBox(
      color: p.chatBg,
      child: Column(
        children: [
          SizedBox(
            height: 72,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.panelBg,
                border: Border(bottom: BorderSide(color: p.border)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Expanded(
                      child: Selector<GroupChatProvider, _GroupHeaderData>(
                        selector: (_, provider) {
                          final group = provider.getGroupById(groupId);
                          return _GroupHeaderData(
                            name: group?.name ?? '群聊',
                            description: group?.description ?? '',
                            memberCount: group?.memberCount ?? 0,
                            replying: provider.isReplying(groupId),
                            done: provider.replyDone,
                            total: provider.replyTotal,
                          );
                        },
                        builder: (context, data, _) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${data.name}（${data.memberCount}）',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              data.replying
                                  ? '群成员正在输入……（${data.done}/${data.total}）'
                                  : (data.description.trim().isEmpty
                                      ? '群聊 · 端到端保存在本机'
                                      : data.description.trim()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color:
                                    data.replying ? p.accent : p.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _headerButton(
                      p,
                      icon: CupertinoIcons.slider_horizontal_3,
                      label: '群聊设置',
                      onTap: () => _open(
                        context,
                        GroupChatSettingsScreen(groupId: groupId),
                      ),
                    ),
                    _headerButton(
                      p,
                      icon: CupertinoIcons.info_circle,
                      label: '群聊详情',
                      onTap: () => _open(
                        context,
                        GroupChatDetailScreen(groupId: groupId),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: _EmbeddedGroupBody(groupId: groupId)),
        ],
      ),
    );
  }

  Widget _headerButton(
    DesktopPalette p, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: p.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: p.textSecondary)),
        ],
      ),
    );
  }
}

class _EmbeddedGroupBody extends StatelessWidget {
  final String groupId;

  const _EmbeddedGroupBody({required this.groupId});

  @override
  Widget build(BuildContext context) {
    return GroupChatScreen(
      key: ValueKey(groupId),
      groupId: groupId,
      embedded: true,
    );
  }
}

class _GroupHeaderData {
  final String name;
  final String description;
  final int memberCount;
  final bool replying;
  final int done;
  final int total;

  const _GroupHeaderData({
    required this.name,
    required this.description,
    required this.memberCount,
    required this.replying,
    required this.done,
    required this.total,
  });
}
