import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/character_pack_entry.dart';
import '../providers/character_provider.dart';

/// 角色包导入二级页：勾选要导入的角色
class CharacterImportScreen extends StatefulWidget {
  final List<CharacterPackEntry> entries;
  final String zipName;

  const CharacterImportScreen({
    super.key,
    required this.entries,
    required this.zipName,
  });

  @override
  State<CharacterImportScreen> createState() => _CharacterImportScreenState();
}

class _CharacterImportScreenState extends State<CharacterImportScreen> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    // 默认全选可导入的角色
    _selected = widget.entries
        .where((e) => e.error == null)
        .map((e) => e.folderName)
        .toSet();
  }

  Future<void> _import() async {
    final provider = context.read<CharacterProvider>();
    const uuid = Uuid();
    var count = 0;
    for (final entry in widget.entries) {
      if (!_selected.contains(entry.folderName) || entry.error != null) continue;
      // 重新生成 id，避免与已导入角色冲突
      final json = entry.character.toJson()..['id'] = uuid.v4();
      await provider.addCharacter(Character.fromJson(json));
      count++;
    }
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('导入成功'),
        content: Text('已导入 $count 个角色，可在通讯录中查看'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validCount = widget.entries.where((e) => e.error == null).length;
    final selectedCount = _selected.length;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('选择导入的角色'),
        trailing: validCount > 0 && selectedCount < validCount
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() {
                    _selected = widget.entries
                        .where((e) => e.error == null)
                        .map((e) => e.folderName)
                        .toSet();
                  });
                },
                child: const Text('全选'),
              )
            : null,
      ),
      child: Column(
        children: [
          // 角色包说明
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(CupertinoIcons.archivebox,
                    size: 16, color: context.textSecondaryColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '来自 ${widget.zipName} 的角色包',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: widget.entries.length,
              itemBuilder: (context, index) {
                final entry = widget.entries[index];
                final isSelected = _selected.contains(entry.folderName);
                final hasError = entry.error != null;
                return CupertinoListTile(
                  leadingSize: 52,
                  leading: _buildAvatar(entry),
                  title: Text(
                    entry.folderName,
                    style: TextStyle(
                      fontSize: 17,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      hasError ? entry.error! : (entry.character.signature.isEmpty
                          ? entry.character.name
                          : entry.character.signature),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: hasError
                            ? CupertinoColors.systemRed
                            : context.textSecondaryColor,
                      ),
                    ),
                  ),
                  trailing: hasError
                      ? null
                      : CupertinoSwitch(
                          value: isSelected,
                          onChanged: (v) {
                            setState(() {
                              if (v) {
                                _selected.add(entry.folderName);
                              } else {
                                _selected.remove(entry.folderName);
                              }
                            });
                          },
                        ),
                  onTap: hasError
                      ? null
                      : () {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(entry.folderName);
                            } else {
                              _selected.add(entry.folderName);
                            }
                          });
                        },
                );
              },
            ),
          ),
          // 底部导入按钮
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoButton.filled(
                onPressed: selectedCount == 0 ? null : _import,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    selectedCount == 0 ? '请选择要导入的角色' : '确定导入 ($selectedCount)',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(CharacterPackEntry entry) {
    final hasError = entry.error != null;
    final avatar = entry.character.avatar;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: context.accentColor.withValues(alpha: 0.15),
        image: (!hasError && avatar.isNotEmpty)
            ? DecorationImage(
                image: MemoryImage(base64Decode(avatar)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: (!hasError && avatar.isNotEmpty)
          ? null
          : Icon(
              hasError
                  ? CupertinoIcons.exclamationmark_triangle
                  : CupertinoIcons.person_fill,
              size: 24,
              color: hasError
                  ? CupertinoColors.systemRed
                  : context.accentColor,
            ),
    );
  }
}
