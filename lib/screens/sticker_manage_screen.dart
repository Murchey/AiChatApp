import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/sticker_pack.dart';
import '../providers/sticker_provider.dart';

class StickerManageScreen extends StatefulWidget {
  const StickerManageScreen({super.key});

  @override
  State<StickerManageScreen> createState() => _StickerManageScreenState();
}

class _StickerManageScreenState extends State<StickerManageScreen> {
  final Set<String> _selected = {};
  bool _editing = false;

  Future<void> _deleteSelected() async {
    final provider = context.read<StickerProvider>();
    final selected = provider.userStickers
        .where((sticker) => _selected.contains(sticker.id))
        .toList();
    if (selected.isEmpty) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除表情包'),
        content: Text('确定删除选中的 ${selected.length} 张表情包吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
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
    for (final sticker in selected) {
      await provider.removeUserSticker(sticker.id);
    }
    if (mounted) setState(() => _selected.clear());
  }

  Future<void> _editLabel(UserSticker sticker) async {
    final controller = TextEditingController(text: sticker.label);
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('编辑备注'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: '表情包备注',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    await context.read<StickerProvider>().updateUserStickerLabel(
          sticker.id,
          value,
        );
  }

  Future<void> _deletePack(StickerPack pack) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除表情包包'),
        content: Text('确定删除「${pack.name}」及其中 ${pack.imagePaths.length} 张图片吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<StickerProvider>().removeStickerPack(pack.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StickerProvider>();
    final stickers = provider.userStickers;
    final packs = provider.packs;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('管理表情包'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => setState(() {
            _editing = !_editing;
            if (!_editing) _selected.clear();
          }),
          child: Text(_editing ? '完成' : '编辑'),
        ),
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: () async => provider.init(),
            ),
            SliverToBoxAdapter(
              child: _buildPackSection(context, packs),
            ),
            SliverToBoxAdapter(
              child: _buildUserSection(context, stickers),
            ),
            if (_editing && _selected.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CupertinoButton.filled(
                    onPressed: _deleteSelected,
                    child: Text('删除选中（${_selected.length}）'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackSection(BuildContext context, List<StickerPack> packs) {
    return CupertinoListSection.insetGrouped(
      backgroundColor: context.scaffoldColor,
      header: Text('创意工坊表情包（${packs.length} 个包）'),
      children: packs.isEmpty
          ? [const CupertinoListTile(title: Text('暂无创意工坊表情包'))]
          : [
              for (final pack in packs)
                CupertinoListTile(
                  leading: _buildThumbnail(pack.coverImagePath),
                  title: Text(pack.name),
                  subtitle:
                      Text('${pack.imagePaths.length} 张 · ${pack.author}'),
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _deletePack(pack),
                    child: const Icon(CupertinoIcons.delete,
                        color: CupertinoColors.systemRed),
                  ),
                ),
            ],
    );
  }

  Widget _buildUserSection(BuildContext context, List<UserSticker> stickers) {
    return CupertinoListSection.insetGrouped(
      backgroundColor: context.scaffoldColor,
      header: Text('我的表情包（${stickers.length} 张）'),
      children: stickers.isEmpty
          ? [const CupertinoListTile(title: Text('暂无自定义表情包'))]
          : [
              Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: stickers.length,
                  itemBuilder: (_, index) {
                    final sticker = stickers[index];
                    final selected = _selected.contains(sticker.id);
                    return GestureDetector(
                      onTap: () {
                        if (!_editing) {
                          _editLabel(sticker);
                          return;
                        }
                        setState(() {
                          if (selected) {
                            _selected.remove(sticker.id);
                          } else {
                            _selected.add(sticker.id);
                          }
                        });
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(sticker.imagePath),
                                  fit: BoxFit.cover),
                            ),
                          ),
                          if (_editing)
                            Positioned(
                              top: 4,
                              left: 4,
                              child: Icon(
                                selected
                                    ? CupertinoIcons.check_mark_circled_solid
                                    : CupertinoIcons.circle,
                                color: selected
                                    ? context.accentColor
                                    : CupertinoColors.white,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
    );
  }

  Widget _buildThumbnail(String path) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(path),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(CupertinoIcons.photo),
      ),
    );
  }
}
