import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../providers/chat_provider.dart';
import '../providers/character_provider.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CupertinoTabController _tabController = CupertinoTabController();

  @override
  void initState() {
    super.initState();
    context.read<ChatProvider>().loadConversations();
    context.read<CharacterProvider>().loadCharacters();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      controller: _tabController,
      tabBar: CupertinoTabBar(
        backgroundColor: context.navBarColor,
        activeColor: context.accentColor,
        inactiveColor: context.textSecondaryColor,
        border: Border(
          top: BorderSide(color: context.separatorColor, width: 0.5),
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.chat_bubble),
            label: 'AiChat',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_2),
            label: '通讯录',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_crop_circle),
            label: '我',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return _buildChatList();
          case 1:
            return _buildCharacterList();
          default:
            return const ProfileScreen();
        }
      },
    );
  }

  Widget _buildChatList() {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('AiChat'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {},
          child: const Icon(CupertinoIcons.search),
        ),
      ),
      child: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          if (chatProvider.conversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.chat_bubble,
                    size: 80,
                    color: CupertinoColors.systemGrey4,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无会话',
                    style: TextStyle(
                      fontSize: 18,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '去"通讯录"找一个AI角色开始聊天吧',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.textSecondaryColor.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  CupertinoButton.filled(
                    onPressed: () => _tabController.index = 1,
                    child: const Text('打开通讯录'),
                  ),
                ],
              ),
            );
          }

          return Container(
            color: context.listBgColor,
            child: ListView.separated(
              itemCount: chatProvider.conversations.length,
              separatorBuilder: (_, __) => Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 72),
                color: context.separatorColor,
              ),
              itemBuilder: (context, index) {
                final conversation = chatProvider.conversations[index];
                return CupertinoListTile(
                  leading: _buildCircleAvatar(
                    context,
                    conversation.characterName,
                    conversation.characterAvatar,
                  ),
                  title: Text(
                    conversation.characterName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      conversation.lastMessage.isEmpty
                          ? '开始对话...'
                          : conversation.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ),
                  trailing: Text(
                    _formatTime(conversation.lastMessageTime),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.chat,
                      arguments: {
                        'conversationId': conversation.id,
                        'characterName': conversation.characterName,
                        'characterAvatar': conversation.characterAvatar,
                      },
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCharacterList() {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('通讯录'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {},
          child: const Icon(CupertinoIcons.search),
        ),
      ),
      child: Consumer<CharacterProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CupertinoActivityIndicator());
          }

          if (provider.characters.isEmpty) {
            return Center(
              child: Text(
                '暂无可用角色',
                style: TextStyle(color: context.textSecondaryColor),
              ),
            );
          }

          // 按拼音首字母分组排序（类似手机通讯录）
          final groups = provider.sortedCharactersGrouped;
          return Container(
            color: context.listBgColor,
            child: ListView(
              children: [
                for (final group in groups) ...[
                  _buildSectionHeader(context, group.key),
                  for (final character in group.value)
                    CupertinoListTile(
                      leading: _buildCircleAvatar(
                        context,
                        character.name,
                        character.avatar,
                      ),
                      title: Text(
                        character.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          character.description,
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
                          arguments: character.id,
                        );
                      },
                    ),
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 72),
                    color: context.separatorColor,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String letter) {
    return Container(
      width: double.infinity,
      color: context.scaffoldColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: context.textSecondaryColor,
        ),
      ),
    );
  }

  Widget _buildCircleAvatar(BuildContext context, String name, String avatar) {
    if (avatar.isNotEmpty) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.accentColor.withValues(alpha: 0.15),
          image: DecorationImage(
            image: MemoryImage(base64Decode(avatar)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.accentColor.withValues(alpha: 0.15),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0] : '?',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: context.accentColor,
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  }
}
