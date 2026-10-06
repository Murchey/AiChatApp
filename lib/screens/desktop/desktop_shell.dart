import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Tooltip;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/conversation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/character_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/group_chat_provider.dart';
import '../../models/group_chat.dart';
import '../../screens/character_detail_screen.dart';
import '../../screens/moments_screen.dart';
import '../../screens/lan_sync_screen.dart';
import '../../widgets/character_avatar.dart';
import 'desktop_chat_view.dart';
import 'desktop_group_chat_view.dart';
import 'desktop_settings_view.dart';
import 'desktop_context_menu.dart';
import 'desktop_theme.dart';

/// 电脑端微信风格主界面。
/// 布局：左栏 │ 列表 │ 主区；设置/同步/朋友圈为独立 Tab（全宽）。
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _rail = 0; // 0消息 1联系人 2朋友圈 3设置 4同步
  String? _selectedConversationId;
  String? _selectedGroupId;
  String? _selectedCharacterId;
  String _search = '';
  final _searchFocus = FocusNode();
  final _searchController = TextEditingController();

  bool get _fullWidthTab => _rail == 2 || _rail == 3 || _rail == 4;

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.keyF &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          if (_fullWidthTab) return KeyEventResult.ignored;
          _searchFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyK &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          if (_fullWidthTab) return KeyEventResult.ignored;
          _searchFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.comma &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          setState(() => _rail = 3);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape &&
            _search.isNotEmpty &&
            !_fullWidthTab) {
          _searchController.clear();
          setState(() => _search = '');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 920;
          return ColoredBox(
            color: p.shellBg,
            child: Row(
              children: [
                _buildRail(p, compact: compact),
                if (!_fullWidthTab) _buildListPanel(p, compact: compact),
                Expanded(child: _buildMainPanel(p)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRail(DesktopPalette p, {bool compact = false}) {
    return Container(
      width: compact ? 60 : 72,
      color: p.railBg,
      child: Column(
        children: [
          const SizedBox(height: 24),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              final name = auth.user?.nickname ?? '我';
              final avatar = auth.user?.avatar ?? '';
              return GestureDetector(
                onTap: () => setState(() => _rail = 3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: avatar.isEmpty
                        ? _letterAvatar(name, p)
                        : _avatarImage(avatar, p),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          _railBtn(p, 0, CupertinoIcons.chat_bubble_2_fill, '消息'),
          _railBtn(p, 1, CupertinoIcons.person_2_fill, '联系人'),
          _railBtn(p, 2, CupertinoIcons.photo_fill, '朋友圈'),
          _railBtn(p, 3, CupertinoIcons.gear_solid, '设置'),
          const Spacer(),
          _railBtn(p, 4, CupertinoIcons.arrow_2_circlepath, '局域网同步'),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _letterAvatar(String name, DesktopPalette p) {
    return Container(
      color: p.railAvatarBg,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '我' : name.characters.first,
        style: TextStyle(
          color: p.textSecondary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _avatarImage(String source, DesktopPalette p) {
    if (source.startsWith('http')) {
      return Image.network(
        source,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _letterAvatar('我', p),
      );
    }
    if (source.startsWith('/') ||
        source.contains('\\') ||
        source.contains(':')) {
      return Image.asset(
        source,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _letterAvatar('我', p),
      );
    }
    try {
      return Image.memory(base64Decode(source), fit: BoxFit.cover);
    } catch (_) {
      return _letterAvatar('我', p);
    }
  }

  Widget _railBtn(DesktopPalette p, int index, IconData icon, String tip) {
    final active = _rail == index;
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: () => setState(() => _rail = index),
        child: Container(
          width: 48,
          height: 48,
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: active ? p.railItemBg : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 24,
            color: active ? p.railIconActive : p.railIcon,
          ),
        ),
      ),
    );
  }

  Widget _buildListPanel(DesktopPalette p, {bool compact = false}) {
    return Container(
      width: compact ? 272 : 320,
      decoration: BoxDecoration(
        color: p.listBg,
        border: Border(right: BorderSide(color: p.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: CupertinoSearchTextField(
              controller: _searchController,
              focusNode: _searchFocus,
              placeholder: _rail == 0 ? '搜索会话（Ctrl+F）' : '搜索联系人（Ctrl+F）',
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
          ),
          Expanded(
            child:
                _rail == 0 ? _buildConversationList(p) : _buildContactList(p),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList(DesktopPalette p) {
    return Consumer2<ChatProvider, GroupChatProvider>(
      builder: (context, chat, groups, _) {
        final entries = <_DesktopConversationEntry>[
          ...chat.conversations.map(_DesktopConversationEntry.private),
          ...groups.groups.map(_DesktopConversationEntry.group),
        ]..sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return b.lastMessageTime.compareTo(a.lastMessageTime);
          });
        var filtered = entries;
        if (_search.isNotEmpty) {
          final q = _search.toLowerCase();
          filtered = entries.where((entry) {
            final name = entry.name.toLowerCase();
            final preview = entry.lastMessage.toLowerCase();
            return name.contains(q) || preview.contains(q);
          }).toList();
        }
        if (filtered.isEmpty) {
          return Center(
            child: Text('暂无会话',
                style: TextStyle(color: p.textSecondary, fontSize: 13)),
          );
        }
        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final entry = filtered[i];
            if (entry.conversation != null) {
              final conversation = entry.conversation!;
              return _conversationTile(
                p,
                conversation,
                conversation.id == _selectedConversationId,
              );
            }
            final group = entry.group!;
            return _groupTile(p, group, group.id == _selectedGroupId);
          },
        );
      },
    );
  }

  Widget _groupTile(DesktopPalette p, GroupChat group, bool selected) {
    return GestureDetector(
      onTap: () => _openGroup(group),
      onSecondaryTapUp: (e) {
        final groups = context.read<GroupChatProvider>();
        showDesktopContextMenu(
          context,
          globalPos: e.globalPosition,
          items: [
            DesktopMenuItem(
              label: group.pinned ? '取消置顶' : '置顶群聊',
              icon: CupertinoIcons.pin,
              onTap: () => groups.setPinned(group.id, !group.pinned),
            ),
            DesktopMenuItem(
              label: '标记已读',
              icon: CupertinoIcons.checkmark_circle,
              enabled: group.unreadCount > 0,
              onTap: () => groups.markGroupActive(group.id),
            ),
            DesktopMenuItem(
              label: '删除群聊',
              icon: CupertinoIcons.delete,
              destructive: true,
              dividerBefore: true,
              onTap: () async {
                final ok = await showCupertinoDialog<bool>(
                  context: context,
                  builder: (ctx) => CupertinoAlertDialog(
                    title: const Text('删除群聊'),
                    content: Text('确定删除「${group.name}」及其全部消息？'),
                    actions: [
                      CupertinoDialogAction(
                        child: const Text('取消'),
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                      CupertinoDialogAction(
                        isDestructiveAction: true,
                        child: const Text('删除'),
                        onPressed: () => Navigator.pop(ctx, true),
                      ),
                    ],
                  ),
                );
                if (ok == true && mounted) {
                  groups.deleteGroup(group.id);
                  if (_selectedGroupId == group.id) {
                    setState(() => _selectedGroupId = null);
                  }
                }
              },
            ),
          ],
        );
      },
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: selected ? p.selected : null,
        child: Row(
          children: [
            _groupAvatar(p, group, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (group.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(CupertinoIcons.pin_fill,
                              size: 11, color: p.textTertiary),
                        ),
                      Expanded(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: p.textPrimary),
                        ),
                      ),
                      Text(_formatTime(group.lastMessageTime),
                          style:
                              TextStyle(fontSize: 11, color: p.textTertiary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.lastMessage.isEmpty
                        ? '${group.memberCount} 位成员'
                        : group.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                ],
              ),
            ),
            if (group.unreadCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _unreadBadge(p, group.unreadCount),
              ),
          ],
        ),
      ),
    );
  }

  Widget _groupAvatar(DesktopPalette p, GroupChat group, {double size = 48}) {
    if (group.avatar.isNotEmpty) {
      return CharacterAvatar(base64: group.avatar, size: size);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: p.selected, borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: Icon(CupertinoIcons.person_3_fill,
          size: size * 0.5, color: p.textSecondary),
    );
  }

  Widget _unreadBadge(DesktopPalette p, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
          color: p.danger, borderRadius: BorderRadius.circular(10)),
      child: Text(count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style:
              const TextStyle(color: Colors.white, fontSize: 11, height: 1.3)),
    );
  }

  Widget _conversationTile(DesktopPalette p, Conversation c, bool selected) {
    final time = _formatTime(c.lastMessageTime);
    return GestureDetector(
      onTap: () => _openConversation(c),
      onSecondaryTapUp: (e) {
        final chat = context.read<ChatProvider>();
        showDesktopContextMenu(
          context,
          globalPos: e.globalPosition,
          items: [
            DesktopMenuItem(
              label: c.pinned ? '取消置顶' : '置顶会话',
              icon: CupertinoIcons.pin,
              onTap: () {
                chat.setPinned(c.id, !c.pinned);
                setState(() {});
              },
            ),
            DesktopMenuItem(
              label: '标记已读',
              icon: CupertinoIcons.checkmark_circle,
              enabled: c.unreadCount > 0,
              onTap: () => chat.markConversationActive(c.id),
            ),
            DesktopMenuItem(
              label: '删除会话',
              icon: CupertinoIcons.delete,
              destructive: true,
              dividerBefore: true,
              onTap: () => _confirmDeleteConversation(c),
            ),
          ],
        );
      },
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: selected ? p.selected : null,
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CharacterAvatar(base64: c.characterAvatar, size: 48),
                if (c.unreadCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: p.danger,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(minWidth: 18),
                      child: Text(
                        c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (c.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            CupertinoIcons.pin_fill,
                            size: 11,
                            color: p.textTertiary,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          c.characterName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 11,
                          color: p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openConversation(Conversation c) {
    setState(() {
      _selectedConversationId = c.id;
      _selectedGroupId = null;
      _selectedCharacterId = null;
    });
    context.read<ChatProvider>().markConversationActive(c.id);
  }

  void _openGroup(GroupChat group) {
    setState(() {
      _selectedGroupId = group.id;
      _selectedConversationId = null;
      _selectedCharacterId = null;
    });
    context.read<GroupChatProvider>().markGroupActive(group.id);
  }

  Future<void> _confirmDeleteConversation(Conversation c) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除与「${c.characterName}」的会话？聊天记录将一并删除。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    context.read<ChatProvider>().deleteConversation(c.id);
    if (_selectedConversationId == c.id) {
      setState(() => _selectedConversationId = null);
    }
  }

  Widget _buildContactList(DesktopPalette p) {
    return Consumer2<CharacterProvider, GroupChatProvider>(
      builder: (context, chars, groups, _) {
        var list = [...chars.characters];
        var groupList = [...groups.groups];
        if (_search.isNotEmpty) {
          final q = _search.toLowerCase();
          list = list
              .where((c) =>
                  c.displayName.toLowerCase().contains(q) ||
                  c.name.toLowerCase().contains(q))
              .toList();
          groupList = groupList
              .where((g) =>
                  g.name.toLowerCase().contains(q) ||
                  g.description.toLowerCase().contains(q))
              .toList();
        }
        return ListView.builder(
          itemCount: groupList.length + list.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) return _sectionLabel(p, '群聊', groupList.length);
            if (i <= groupList.length) {
              final group = groupList[i - 1];
              return _contactGroupTile(p, group, group.id == _selectedGroupId);
            }
            if (i == groupList.length + 1) {
              return _sectionLabel(p, '角色', list.length);
            }
            final c = list[i - groupList.length - 2];
            final selected = c.id == _selectedCharacterId;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedCharacterId = c.id;
                _selectedConversationId = null;
              }),
              child: Container(
                height: 64,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: selected ? p.selected : null,
                child: Row(
                  children: [
                    CharacterAvatar(base64: c.avatar, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            c.signature.isEmpty ? '暂无签名' : c.signature,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sectionLabel(DesktopPalette p, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        '$title  $count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: p.textTertiary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _contactGroupTile(DesktopPalette p, GroupChat group, bool selected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _rail = 0;
          _selectedGroupId = group.id;
          _selectedConversationId = null;
          _selectedCharacterId = null;
        });
      },
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: selected ? p.selected : null,
        child: Row(
          children: [
            _groupAvatar(p, group, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: p.textPrimary),
              ),
            ),
            Text('${group.memberCount}人',
                style: TextStyle(fontSize: 12, color: p.textTertiary)),
          ],
        ),
      ),
    );
  }

  Widget _buildMainPanel(DesktopPalette p) {
    if (_rail == 2) {
      return const ColoredBox(
        color: Color(0xFFEDEDED),
        child: MomentsScreen(),
      );
    }
    if (_rail == 3) {
      return const DesktopSettingsView();
    }
    if (_rail == 4) {
      return const LanSyncScreen();
    }
    if (_rail == 0 && _selectedConversationId != null) {
      final conv = context
          .read<ChatProvider>()
          .conversations
          .where((c) => c.id == _selectedConversationId)
          .firstOrNull;
      if (conv != null) {
        return DesktopChatView(
          key: ValueKey(conv.id),
          conversationId: conv.id,
          characterName: conv.characterName,
          characterAvatar: conv.characterAvatar,
        );
      }
    }
    if (_rail == 0 && _selectedGroupId != null) {
      final group =
          context.read<GroupChatProvider>().getGroupById(_selectedGroupId!);
      if (group != null) {
        return DesktopGroupChatView(
          key: ValueKey(group.id),
          groupId: group.id,
        );
      }
    }
    if (_rail == 1 && _selectedCharacterId != null) {
      return CharacterDetailScreen(
        key: ValueKey(_selectedCharacterId),
        characterId: _selectedCharacterId!,
      );
    }
    return _placeholder(p);
  }

  Widget _placeholder(DesktopPalette p) {
    return ColoredBox(
      color: p.chatBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.chat_bubble_2,
              size: 72,
              color: p.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              '选择左侧会话开始聊天',
              style: TextStyle(color: p.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Ctrl/Cmd+K 搜索 · 右键更多操作 · Enter 发送 · Esc 关闭',
              style: TextStyle(color: p.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    String two(int n) => n.toString().padLeft(2, '0');
    if (day == today) return '${two(t.hour)}:${two(t.minute)}';
    if (today.difference(day).inDays == 1) return '昨天';
    if (today.difference(day).inDays < 7) {
      const names = ['一', '二', '三', '四', '五', '六', '日'];
      return '周${names[t.weekday - 1]}';
    }
    return '${t.month}/${t.day}';
  }
}

/// 统一私聊与群聊列表的轻量条目模型。
/// 仅在桌面列表层使用，不改变手机版 Provider 的数据结构。
class _DesktopConversationEntry {
  final Conversation? conversation;
  final GroupChat? group;

  const _DesktopConversationEntry._({this.conversation, this.group});

  factory _DesktopConversationEntry.private(Conversation value) =>
      _DesktopConversationEntry._(conversation: value);

  factory _DesktopConversationEntry.group(GroupChat value) =>
      _DesktopConversationEntry._(group: value);

  bool get pinned => conversation?.pinned ?? group?.pinned ?? false;
  DateTime get lastMessageTime =>
      conversation?.lastMessageTime ?? group?.lastMessageTime ?? DateTime(1970);
  String get name => conversation?.characterName ?? group?.name ?? '';
  String get lastMessage =>
      conversation?.lastMessage ?? group?.lastMessage ?? '';
}
