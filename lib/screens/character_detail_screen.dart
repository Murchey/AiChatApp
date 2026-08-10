import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import 'character_prompt_screen.dart';

class CharacterDetailScreen extends StatelessWidget {
  final String characterId;

  const CharacterDetailScreen({super.key, required this.characterId});

  @override
  Widget build(BuildContext context) {
    return Consumer2<CharacterProvider, ChatProvider>(
      builder: (context, characterProvider, chatProvider, _) {
        final character = characterProvider.getCharacterById(characterId);

        if (character == null) {
          return CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(middle: Text('角色详情')),
            child: Center(
              child: Text(
                '角色不存在',
                style: TextStyle(color: context.textSecondaryColor),
              ),
            ),
          );
        }

        return CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            middle: Text(character.name),
          ),
          child: Column(
            children: [
              // 角色资料卡头部
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      context.accentColor,
                      context.accentColor.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: CupertinoColors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        character.name.isNotEmpty ? character.name[0] : '?',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      character.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      character.personality,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              // 资料信息
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (character.description.isNotEmpty) ...[
                      _sectionTitle(context, '角色介绍'),
                      _infoCard(context, character.description),
                      const SizedBox(height: 16),
                    ],
                    if (character.greeting.isNotEmpty) ...[
                      _sectionTitle(context, '开场白'),
                      _infoCard(context, character.greeting),
                      const SizedBox(height: 16),
                    ],
                    if (character.tags.isNotEmpty) ...[
                      _sectionTitle(context, '标签'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: character.tags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: context.accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 14,
                                color: context.accentColor,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              // 底部操作：设置 + 开始聊天
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          borderRadius: BorderRadius.circular(12),
                          color: context.listBgColor,
                          child: Text(
                            '设置',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.accentColor,
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (_) => CharacterPromptScreen(
                                  characterId: character.id,
                                  characterName: character.name,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: CupertinoButton.filled(
                          onPressed: () {
                            final conversation =
                                chatProvider.getOrCreateConversation(
                              characterId: character.id,
                              characterName: character.name,
                              characterAvatar: character.avatar,
                            );

                            Navigator.pushNamed(
                              context,
                              AppRoutes.chat,
                              arguments: {
                                'conversationId': conversation.id,
                                'characterName': character.name,
                                'characterAvatar': character.avatar,
                              },
                            );
                          },
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          child: const Text(
                            '开始聊天',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: context.textPrimaryColor,
        ),
      ),
    );
  }

  Widget _infoCard(BuildContext context, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        content,
        style: TextStyle(
          fontSize: 15,
          height: 1.6,
          color: context.textPrimaryColor,
        ),
      ),
    );
  }
}
