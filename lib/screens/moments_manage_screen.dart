import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../models/moments_pack_entry.dart';
import '../providers/character_provider.dart';
import '../services/character_pack_service.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/character_avatar.dart';
import 'character_detail_screen.dart';

/// 管理当前朋友圈：二级菜单页。
/// 顶部为「导入朋友圈数据包」入口，下方为已有朋友圈的角色列表（可勾选），
/// 底部「导出选中」将所选角色的全部朋友圈打包为 zip 数据包。
class MomentsManageScreen extends StatefulWidget {
  const MomentsManageScreen({super.key});

  @override
  State<MomentsManageScreen> createState() => _MomentsManageScreenState();
}

class _MomentsManageScreenState extends State<MomentsManageScreen> {
  final Set<String> _selected = {};
  bool _busy = false; // 正在解析/导出中

  List<Character> get _selectedCharacters {
    final provider = context.read<CharacterProvider>();
    return provider.characters
        .where((c) => _selected.contains(c.id) && c.moments.isNotEmpty)
        .toList();
  }

  /// 选择 zip 朋友圈数据包并解析导入
  Future<void> _pickAndImportPack() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await FilePickerHelper.pickFile();
      if (file == null || !mounted) return;
      if (!file.name.toLowerCase().endsWith('.zip')) {
        _showTip('请选择 .zip 格式的朋友圈数据包文件');
        return;
      }
      final entries = await CharacterPackService.parseMomentsPack(file.path);
      if (!mounted) return;
      if (entries.isEmpty) {
        _showTip('该 zip 中没有找到朋友圈数据（需包含 moments.json 的角色文件夹）');
        return;
      }
      await _confirmImport(entries);
    } catch (e) {
      if (mounted) _showTip('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 确认导入：匹配已有角色则更新其朋友圈，未匹配则新建角色
  Future<void> _confirmImport(List<MomentsPackEntry> entries) async {
    final valid = entries
        .where((e) => e.error == null && e.moments.isNotEmpty)
        .toList();
    if (valid.isEmpty) {
      _showTip('该 zip 中没有可导入的朋友圈数据');
      return;
    }

    final provider = context.read<CharacterProvider>();
    final existing = <String, Character>{
      for (final c in provider.characters) c.displayName: c,
    };
    var updateCount = 0;
    final createNames = <String>[];
    for (final e in valid) {
      if (existing.containsKey(e.characterName)) {
        updateCount++;
      } else {
        createNames.add(e.characterName);
      }
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('导入朋友圈数据'),
        content: Text(
          '将导入 ${valid.length} 个角色的朋友圈：'
          '$updateCount 个更新到已有角色'
          '${createNames.isEmpty ? '' : '，${createNames.length} 个将新建角色（${createNames.join('、')}）'}。',
          textAlign: TextAlign.center,
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    var count = 0;
    for (final e in valid) {
      final hit = existing[e.characterName];
      if (hit != null) {
        await provider.updateMoments(hit.id, e.moments);
      } else {
        await provider.addCharacter(Character(
          id: const Uuid().v4(),
          name: e.characterName,
          moments: e.moments,
        ));
      }
      count++;
    }
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('导入成功'),
        content: Text('已导入 $count 个角色的朋友圈数据'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 导出选中的角色为 zip 朋友圈数据包
  Future<void> _exportSelected() async {
    final list = _selectedCharacters;
    if (list.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await CharacterPackService.exportMomentsPack(list);
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('导出成功'),
          content: Text(
            '已将 ${list.length} 个角色的朋友圈打包为 zip，可分享给他人：\n\n$path',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _showTip('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 删除选中角色的全部朋友圈数据（带确认，角色本身与聊天记录不受影响）
  Future<void> _confirmDelete() async {
    final count = _selected.length;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除朋友圈数据'),
        content: Text('确定删除选中的 $count 个角色的全部朋友圈数据吗？角色与聊天记录不会受影响。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final provider = context.read<CharacterProvider>();
    for (final id in _selected) {
      final list = provider.characters.where((c) => c.id == id).toList();
      if (list.isEmpty) continue;
      // 清理该角色朋友圈在 user_moments/ 下的图片文件
      for (final m in list.first.moments) {
        for (final p in m.images) {
          try {
            if (p.replaceAll('\\', '/').contains('/user_moments/')) {
              final f = File(p);
              if (f.existsSync()) f.deleteSync();
            }
          } catch (_) {}
        }
      }
      await provider.updateMoments(id, []);
    }
    if (!mounted) return;
    setState(() => _selected.clear());
    _showTip('已删除 $count 个角色的朋友圈数据');
  }

  void _showTip(String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CharacterProvider>();
    // 列表最上方固定显示"自己"的朋友圈，其余角色按通讯录顺序排列
    final self = provider.selfCharacter;
    final momentsCharacters = <Character>[
      if (self != null && self.moments.isNotEmpty) self,
      ...provider.characters.where((c) =>
          c.moments.isNotEmpty && c.id != CharacterProvider.selfCharacterId),
    ];
    final selectedCount = _selected.length;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('管理朋友圈'),
        trailing: momentsCharacters.isNotEmpty &&
                selectedCount < momentsCharacters.length
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() {
                    _selected
                      ..clear()
                      ..addAll(momentsCharacters.map((c) => c.id));
                  });
                },
                child: const Text('全选'),
              )
            : null,
      ),
      child: Column(
        children: [
          // 导入朋友圈数据包入口
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const SizedBox.shrink(),
            children: [
              CupertinoListTile(
                leading: Icon(
                  CupertinoIcons.archivebox,
                  color: context.accentColor,
                ),
                title: const Text('导入朋友圈数据包'),
                subtitle: Text(
                  '从 zip 文件导入朋友圈数据',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: _busy
                    ? const CupertinoActivityIndicator()
                    : Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: context.textSecondaryColor,
                      ),
                onTap: _pickAndImportPack,
              ),
            ],
          ),
          // 角色列表（仅展示已有朋友圈的角色，可勾选）
          Expanded(
            child: momentsCharacters.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        '暂无朋友圈数据，点击上方「导入朋友圈数据包」导入',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: momentsCharacters.length,
                    separatorBuilder: (context, index) => Container(
                      height: 0.5,
                      margin: const EdgeInsets.only(left: 100),
                      color: context.separatorColor,
                    ),
                    itemBuilder: (context, index) {
                      final character = momentsCharacters[index];
                      final isSelected = _selected.contains(character.id);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // 点击角色条目进入其空间页查看朋友圈
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => CharacterDetailScreen(
                                characterId: character.id,
                                // 管理模式下允许编辑/删除任意角色的动态与评论
                                manageMode: true,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          color: context.listBgColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              // 勾选框（点击只切换选中状态）
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selected.remove(character.id);
                                    } else {
                                      _selected.add(character.id);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    isSelected
                                        ? CupertinoIcons.checkmark_circle_fill
                                        : CupertinoIcons.circle,
                                    size: 24,
                                    color: isSelected
                                        ? context.accentColor
                                        : CupertinoColors.systemGrey,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              _buildAvatar(character),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      character.id ==
                                              CharacterProvider.selfCharacterId
                                          ? '${character.displayName}（自己）'
                                          : character.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 17,
                                        color: context.textPrimaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${character.moments.length} 条动态',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: context.textSecondaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                CupertinoIcons.chevron_right,
                                size: 16,
                                color: context.textSecondaryColor,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // 底部操作栏：删除选中 / 导出选中的角色朋友圈
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: selectedCount == 0 ? null : _confirmDelete,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        selectedCount == 0 ? '删除' : '删除选中',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: selectedCount == 0 ? null : _exportSelected,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        selectedCount == 0 ? '导出选中' : '导出选中 ($selectedCount)',
                        style: const TextStyle(
                          fontSize: 16,
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
  }

  Widget _buildAvatar(Character character) {
    return CharacterAvatar(base64: character.avatar, size: 44);
  }
}
