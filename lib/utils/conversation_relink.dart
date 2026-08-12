import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../models/character.dart';
import '../providers/chat_provider.dart';
import '../providers/character_provider.dart';

/// 角色删除后重新导入同名角色时，把仍指向旧角色 id 的孤儿会话重新关联到新角色，
/// 避免聊天中的角色卡显示「角色不存在」。
///
/// 仅调整会话指向的角色 id 与名称/头像快照，不覆盖任何聊天记录。
void relinkOrphanedConversations({
  required BuildContext context,
  required Character character,
}) {
  final chatProvider = context.read<ChatProvider>();
  final charProvider = context.read<CharacterProvider>();
  final validIds = charProvider.characters.map((c) => c.id).toSet();
  for (final conv in chatProvider.conversations) {
    // 会话指向的角色已不存在，且名称与新导入的角色一致 → 重新关联
    if (conv.characterId != character.id &&
        !validIds.contains(conv.characterId) &&
        conv.characterName == character.name) {
      chatProvider.relinkConversation(
        oldCharacterId: conv.characterId,
        newCharacterId: character.id,
        name: character.name,
        avatar: character.avatar,
      );
    }
  }
}
