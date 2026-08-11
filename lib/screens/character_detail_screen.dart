import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';

class CharacterDetailScreen extends StatefulWidget {
  final String characterId;

  const CharacterDetailScreen({super.key, required this.characterId});

  @override
  State<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends State<CharacterDetailScreen> {
  /// 点击头像选择图片（相册 / 拍照）
  Future<void> _pickAvatar(Character character) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await context
        .read<CharacterProvider>()
        .updateAvatar(character.id, base64Encode(bytes));
  }

  /// 头像选择弹窗
  void _showAvatarMenu(Character character) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('设置角色头像'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickAvatar(character);
            },
            child: const Text('从相册选择'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CharacterProvider, ChatProvider>(
      builder: (context, characterProvider, chatProvider, _) {
        final character = characterProvider.getCharacterById(widget.characterId);

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
              // 角色资料卡头部（头像可点击设置）
              GestureDetector(
                onTap: () => _showAvatarMenu(character),
                child: Container(
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
                      _buildAvatar(character),
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
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.photo,
                            size: 12,
                            color: CupertinoColors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '点击更换头像',
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
                  ],
                ),
              ),
              // 底部操作：开始聊天（提示词仅可在聊天页右上角菜单的折叠 panel 中编辑）
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CupertinoButton.filled(
                    onPressed: () {
                      final conversation =
                          chatProvider.getOrCreateConversation(
                        characterId: character.id,
                        characterName: character.displayName,
                        characterAvatar: character.avatar,
                      );

                      Navigator.pushNamed(
                        context,
                        AppRoutes.chat,
                        arguments: {
                          'conversationId': conversation.id,
                          'characterName': character.displayName,
                          'characterAvatar': character.avatar,
                        },
                      );
                    },
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: const Text(
                      '开始聊天',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 角色头像：已设置显示图片，未设置显示默认用户图标
  Widget _buildAvatar(Character character) {
    if (character.avatar.isNotEmpty) {
      return Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CupertinoColors.white.withValues(alpha: 0.5),
            width: 2,
          ),
          image: DecorationImage(
            image: MemoryImage(base64Decode(character.avatar)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CupertinoColors.white.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(
        CupertinoIcons.person_fill,
        size: 44,
        color: CupertinoColors.white,
      ),
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
