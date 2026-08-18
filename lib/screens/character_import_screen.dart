import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/character_pack_entry.dart';
import '../models/moment.dart';
import '../providers/chat_provider.dart';
import '../providers/character_provider.dart';
import '../providers/memory_point_provider.dart';
import '../utils/conversation_relink.dart';
import '../widgets/character_avatar.dart';

/// 角色包导入二级页：勾选要导入的角色
class CharacterImportScreen extends StatefulWidget {
  final List<CharacterPackEntry> entries;
  final String zipName;

  const CharacterImportScreen({
    super.key,
    required this.entries,
    required this.zipName,
  });

  /// 同名角色覆盖时的朋友圈合并：
  /// - 本地已有动态全部保留（含角色自己新发的、包内没有的动态）；
  /// - 包内与本地 id 一致的动态 → 用包内版本覆盖（更新）；
  /// - 包内新增（本地没有的 id）的动态 → 追加。
  static List<Moment> mergeMomentsOnOverwrite(
    List<Moment> local,
    List<Moment> pack,
  ) {
    final packIds = pack.map((m) => m.id).toSet();
    final merged = <Moment>[
      for (final m in local)
        if (!packIds.contains(m.id)) m,
    ];
    final used = <String>{};
    for (final m in pack) {
      // 包内 id 去重兜底（parsePack 已保证全唯一，此处防御重复）
      if (m.id.isNotEmpty && !used.add(m.id)) continue;
      merged.add(m);
    }
    return merged;
  }

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
    // 记忆点写入器：循环中多次 await，提前取引用避免 async gap
    final memoryProvider = context.read<MemoryPointProvider>();
    const uuid = Uuid();
    var count = 0;
    // 已存在角色的名称集合：同名角色需选择「覆盖当前角色数据」或改名
    final usedNames = provider.characters
        .map((c) => c.name.trim())
        .where((n) => n.isNotEmpty)
        .toSet();

    for (final entry in widget.entries) {
      if (!_selected.contains(entry.folderName) || entry.error != null) continue;

      var name = entry.character.name.trim();
      // 与已有角色重名：弹出「覆盖 / 改名」选择，取消则跳过该角色
      if (usedNames.contains(name)) {
        if (!mounted) return;
        final decision = await _promptDuplicate(context, name, usedNames);
        if (!mounted) return;
        if (decision == null) continue;

        if (decision.overwrite) {
          // 覆盖当前角色数据：保留原 id（聊天记录不覆盖），替换资料/提示词；
          // 朋友圈合并覆盖：包内与本地 id 一致的动态用包内版本覆盖，
          // 本地已有的动态（含角色自己新发的）保留，包内新增的动态追加
          final existing = provider.findCharacterByName(name);
          if (existing == null) continue;
          final json = entry.character.toJson()
            ..['id'] = existing.id
            ..['name'] = name;
          var character = Character.fromJson(json);
          if (existing.moments.isNotEmpty || character.moments.isNotEmpty) {
            character = character.copyWith(
              moments: CharacterImportScreen.mergeMomentsOnOverwrite(
                existing.moments,
                character.moments,
              ),
            );
          }
          await provider.overwriteCharacter(character);
          // 角色包覆盖导入：用包内记忆点替换该角色的持久化记忆
          await memoryProvider.replacePoints(character.id, entry.memoryPoints);
          if (!mounted) return;
          // 同步会话中的角色头像快照，保证首页列表头像一致
          context
              .read<ChatProvider>()
              .updateCharacterAvatar(existing.id, character.avatar);
          usedNames.add(name);
          count++;
          continue;
        }
        name = decision.newName ?? name;
      }
      usedNames.add(name);

      // 重新生成 id，避免与已导入角色冲突；重名角色写入修改后的名称
      final json = entry.character.toJson()
        ..['id'] = uuid.v4()
        ..['name'] = name;
      final character = Character.fromJson(json);
      await provider.addCharacter(character);
      // 写入随角色包带来的持久化记忆点（新角色无旧记忆，等价于追加）
      if (entry.memoryPoints.isNotEmpty) {
        await memoryProvider.replacePoints(character.id, entry.memoryPoints);
      }
      // 角色删除后重新导入：把指向旧角色的孤儿会话重新关联到新角色
      if (!mounted) return;
      relinkOrphanedConversations(context: context, character: character);
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

  /// 弹窗处理已有同名角色：勾选「覆盖当前角色数据」则直接覆盖（隐藏重命名框），
  /// 不勾选则显示重命名框。返回 (是否覆盖, 新名称)；用户取消返回 null。
  Future<({bool overwrite, String? newName})?> _promptDuplicate(
    BuildContext context,
    String originalName,
    Set<String> usedNames,
  ) {
    return showCupertinoDialog<({bool overwrite, String? newName})>(
      context: context,
      builder: (_) => _DuplicateCharacterDialog(
        originalName: originalName,
        usedNames: usedNames,
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
    // 解析失败的目录用红色警示图标标识（不适用全局头像框样式）
    if (hasError) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: context.accentColor.withValues(alpha: 0.15),
        ),
        alignment: Alignment.center,
        child: const Icon(
          CupertinoIcons.exclamationmark_triangle,
          size: 24,
          color: CupertinoColors.systemRed,
        ),
      );
    }
    return CharacterAvatar(
      base64: avatar,
      size: 52,
      borderRadius: BorderRadius.circular(10),
      iconSize: 24,
    );
  }
}

/// 同名角色处理弹窗：
/// 勾选「覆盖当前角色数据」则隐藏重命名框（直接覆盖已有角色，保留聊天记录）；
/// 不勾选则显示重命名输入框，校验非空且不与已有名称冲突。
class _DuplicateCharacterDialog extends StatefulWidget {
  final String originalName;
  final Set<String> usedNames;

  const _DuplicateCharacterDialog({
    required this.originalName,
    required this.usedNames,
  });

  @override
  State<_DuplicateCharacterDialog> createState() =>
      _DuplicateCharacterDialogState();
}

class _DuplicateCharacterDialogState extends State<_DuplicateCharacterDialog> {
  late final TextEditingController _controller;
  bool _overwrite = false; // 勾选「覆盖当前角色数据」
  String? _hint;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.originalName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // 勾选覆盖：无需重命名，直接返回覆盖标记
    if (_overwrite) {
      Navigator.pop(context, (overwrite: true, newName: null));
      return;
    }
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _hint = '名称不能为空');
      return;
    }
    if (widget.usedNames.contains(name)) {
      setState(() => _hint = '该名称已被使用，请更换一个');
      return;
    }
    Navigator.pop(context, (overwrite: false, newName: name));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('已有同名角色'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '「${widget.originalName}」已存在，请选择处理方式：',
            style: const TextStyle(fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // 覆盖当前角色数据勾选项
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _overwrite = !_overwrite;
                _hint = null;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _overwrite
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    size: 22,
                    color: _overwrite
                        ? context.accentColor
                        : CupertinoColors.systemGrey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '覆盖当前角色数据',
                          style: TextStyle(
                            fontSize: 15,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '覆盖资料与提示词，朋友圈仅覆盖包内动态',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (_overwrite)
            Text(
              '将用角色包覆盖「${widget.originalName}」的资料与提示词；'
              '朋友圈仅覆盖包内已有的动态，角色自己发的动态保留，聊天记录不受影响',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: context.textSecondaryColor,
              ),
            )
          else ...[
            CupertinoTextField(
              controller: _controller,
              autofocus: true,
              onChanged: (_) {
                if (_hint != null) setState(() => _hint = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            if (_hint != null) ...[
              const SizedBox(height: 8),
              Text(
                _hint!,
                style: const TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemRed,
                ),
              ),
            ],
          ],
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: Text(_overwrite ? '覆盖导入' : '确定'),
        ),
      ],
    );
  }
}
