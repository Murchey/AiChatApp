import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../providers/api_provider.dart';
import '../../providers/character_provider.dart';

  /// 3. 指定模型（该角色始终使用此模型）
  void showCharacterModelPicker(BuildContext context, String characterId) {
    if (characterId.isEmpty) return;
    final api = context.read<ApiProvider>();
    final character =
        context.read<CharacterProvider>().getCharacterById(characterId);
    final currentId = character?.modelId ?? '';
    final defaultId = character?.defaultModelId ?? '';

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: context.listBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  '选择角色使用的模型',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    CupertinoListTile(
                      leading: Icon(
                        currentId.isEmpty && defaultId.isEmpty
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.circle,
                        color: currentId.isEmpty && defaultId.isEmpty
                            ? context.accentColor
                            : context.textSecondaryColor,
                      ),
                      title: const Text('跟随全局模型'),
                      subtitle: Text(
                        '使用「聊天设置」中选中的全局聊天模型',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        final provider = context.read<CharacterProvider>();
                        provider.updateCharacterModel(characterId, '');
                        provider.updateCharacterDefaultModel(characterId, '');
                      },
                    ),
                    pickerSectionLabel(context, '缺省模型（全局模型未设置时的兜底）'),
                    for (final m in api.models)
                      CupertinoListTile(
                        leading: Icon(
                          currentId.isEmpty && m.id == defaultId
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          color: currentId.isEmpty && m.id == defaultId
                              ? context.accentColor
                              : context.textSecondaryColor,
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(
                          m.modelName,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          final provider = context.read<CharacterProvider>();
                          provider.updateCharacterDefaultModel(
                            characterId,
                            m.id,
                          );
                          provider.updateCharacterModel(characterId, '');
                        },
                      ),
                    pickerSectionLabel(context, '指定模型（始终使用该模型）'),
                    for (final m in api.models)
                      CupertinoListTile(
                        leading: Icon(
                          m.id == currentId
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          color: m.id == currentId
                              ? context.accentColor
                              : context.textSecondaryColor,
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(
                          m.modelName,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          final provider = context.read<CharacterProvider>();
                          provider.updateCharacterModel(characterId, m.id);
                          provider.updateCharacterDefaultModel(characterId, '');
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget pickerSectionLabel(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: context.textSecondaryColor,
        ),
      ),
    );
  }
