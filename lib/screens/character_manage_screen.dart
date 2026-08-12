import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../providers/character_provider.dart';
import '../services/character_pack_service.dart';
import '../utils/character_pack_picker.dart';
import '../widgets/character_avatar.dart';
import 'chat_detail_screen.dart';
import 'character_import_screen.dart';

/// 管理当前角色：勾选删除 / 导出角色包 / 添加自定义角色 / 导入角色包
class CharacterManageScreen extends StatefulWidget {
  const CharacterManageScreen({super.key});

  @override
  State<CharacterManageScreen> createState() => _CharacterManageScreenState();
}

class _CharacterManageScreenState extends State<CharacterManageScreen> {
  final Set<String> _selected = {};
  bool _busy = false; // 正在解析/导出中

  List<Character> get _selectedCharacters {
    final provider = context.read<CharacterProvider>();
    return provider.manageableCharacters
        .where((c) => _selected.contains(c.id))
        .toList();
  }

  /// 选择 zip 角色包并解析，进入勾选导入页
  Future<void> _pickAndImportPack() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await pickAndParseCharacterPack();
      if (result == null || !mounted) return;
      if (result.entries.isEmpty) {
        _showTip('该 zip 中没有找到角色包（需包含 Profile.json 的角色文件夹）');
        return;
      }
      await Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => CharacterImportScreen(
            entries: result.entries,
            zipName: result.name,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showTip('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 导出选中的角色为 zip 角色包
  Future<void> _exportSelected() async {
    final list = _selectedCharacters;
    if (list.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await CharacterPackService.exportPack(list);
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('导出成功'),
          content: Text(
            '已将 ${list.length} 个角色打包为 zip，可分享给他人：\n\n$path',
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

  /// 删除选中的角色（带确认）
  Future<void> _confirmDelete() async {
    final count = _selected.length;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除角色'),
        content: Text('确定删除选中的 $count 个角色吗？相关聊天记录不会被删除。'),
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
    await context
        .read<CharacterProvider>()
        .removeCharacters(_selected.toList());
    if (!mounted) return;
    setState(() => _selected.clear());
  }

  /// 添加自定义角色（输入名称）
  Future<void> _addCustomCharacter() async {
    final controller = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('添加自定义角色'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            placeholder: '输入角色名称',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final provider = context.read<CharacterProvider>();
    await provider.addCharacter(Character(id: const Uuid().v4(), name: name));
    if (!mounted) return;
    _showTip('已创建角色「$name」，点击列表中的角色可编辑头像、提示词等资料');
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
    final hasSelection = _selected.isNotEmpty;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('管理角色'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _addCustomCharacter,
          child: Text(
            '添加',
            style: TextStyle(
              color: context.accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      child: Column(
        children: [
          // 导入角色包入口
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
                title: const Text('导入角色包'),
                subtitle: Text(
                  '从 zip 文件导入角色',
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
          // 角色列表（不含固定的"自己"账号）
          Expanded(
            child: provider.manageableCharacters.isEmpty
                ? Center(
                    child: Text(
                      '暂无角色',
                      style: TextStyle(color: context.textSecondaryColor),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: provider.manageableCharacters.length,
                    separatorBuilder: (context, index) => Container(
                      height: 0.5,
                      margin: const EdgeInsets.only(left: 100),
                      color: context.separatorColor,
                    ),
                    itemBuilder: (context, index) {
                      final character = provider.manageableCharacters[index];
                      final isSelected = _selected.contains(character.id);
                      final subtitle = character.signature.isEmpty
                          ? (character.description.isEmpty
                              ? (character.systemPrompt.isEmpty
                                  ? '点击进入编辑角色资料'
                                  : character.systemPrompt)
                              : character.description)
                          : character.signature;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // 进入角色卡片页，可编辑资料信息与提示词
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => ChatDetailScreen(
                                conversationId: '',
                                characterName: character.name,
                                characterId: character.id,
                                showChatManage: false,
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
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selected.remove(character.id);
                                    } else {
                                      _selected.add(character.id);
                                    }
                                  });
                                },
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
                              const SizedBox(width: 12),
                              _buildAvatar(character),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      character.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 17,
                                        color: context.textPrimaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
          // 底部操作栏
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: hasSelection ? _confirmDelete : null,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        hasSelection ? '删除选中' : '删除',
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
                      onPressed: hasSelection ? _exportSelected : null,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        hasSelection ? '导出选中' : '导出',
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
