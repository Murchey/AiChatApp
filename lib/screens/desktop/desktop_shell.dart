import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Tooltip;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/conversation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/character_provider.dart';
import '../../providers/chat_provider.dart';
import '../../screens/character_detail_screen.dart';
import '../../screens/moments_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/lan_sync_screen.dart';
import '../../widgets/character_avatar.dart';
import 'desktop_chat_view.dart';
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
        if (event.logicalKey == LogicalKeyboardKey.escape &&
            _search.isNotEmpty &&
            !_fullWidthTab) {
          _searchController.clear();
          setState(() => _search = '');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ColoredBox(
        color: p.shellBg,
        child: Row(
          children: [
            _buildRail(p),
            if (!_fullWidthTab) _buildListPanel(p),
            Expanded(child: _buildMainPanel(p)),
          ],
        ),
      ),
    );
  }

  Widget _buildRail(DesktopPalette p) {
    return Container(
      width: 68,
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

  Widget _buildListPanel(DesktopPalette p) {
    return Container(
      width: 300,
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
            child: _rail == 0
                ? _buildConversationList(p)
                : _buildContactList(p),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList(DesktopPalette p) {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        var items = [...chat.conversations]
          ..sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return b.lastMessageTime.compareTo(a.lastMessageTime);
          });
        if (_search.isNotEmpty) {
          final q = _search.toLowerCase();
          items = items
              .where((c) =>
                  c.characterName.toLowerCase().contains(q) ||
                  c.lastMessage.toLowerCase().contains(q))
              .toList();
        }
        if (items.isEmpty) {
          return Center(
            child: Text(
              '暂无会话',
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
          );
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) => _conversationTile(
            p,
            items[i],
            items[i].id == _selectedConversationId,
          ),
        );
      },
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
      _selectedCharacterId = null;
    });
    context.read<ChatProvider>().markConversationActive(c.id);
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
    return Consumer<CharacterProvider>(
      builder: (context, chars, _) {
        var list = [...chars.characters];
        if (_search.isNotEmpty) {
          final q = _search.toLowerCase();
          list = list
              .where((c) =>
                  c.displayName.toLowerCase().contains(q) ||
                  c.name.toLowerCase().contains(q))
              .toList();
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final c = list[i];
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

  Widget _buildMainPanel(DesktopPalette p) {
    if (_rail == 2) {
      return const ColoredBox(
        color: Color(0xFFEDEDED),
        child: MomentsScreen(),
      );
    }
    if (_rail == 3) {
      // 设置：与手机端同一套页面，不再另做桌面壳
      return const SettingsScreen();
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
              'Ctrl+F 搜索 · 右键更多操作 · Enter 发送',
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
