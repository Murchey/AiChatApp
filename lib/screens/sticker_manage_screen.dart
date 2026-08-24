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

  Future<void> _showSearchTest() async {
    final controller = TextEditingController();
    var results = const <UserSticker>[];
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => CupertinoAlertDialog(
          title: const Text('测试表情包检索'),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('输入情绪或场景词，确认角色可检索到的本地表情包。'),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: controller,
                  autofocus: true,
                  placeholder: '例如：猫猫傲娇、无语吐槽',
                  onSubmitted: (_) => _runSearchTest(
                      controller, setDialogState, (value) => results = value),
                ),
                const SizedBox(height: 8),
                CupertinoButton.filled(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                  onPressed: () => _runSearchTest(
                      controller, setDialogState, (value) => results = value),
                  child: const Text('开始检索'),
                ),
                if (results.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 86,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, index) {
                        final sticker = results[index];
                        return SizedBox(
                          width: 72,
                          child: Column(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(File(sticker.imagePath),
                                  width: 52, height: 52, fit: BoxFit.cover),
                            ),
                            const SizedBox(height: 3),
                            Text(sticker.label.isEmpty ? '未备注' : sticker.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11)),
                          ]),
                        );
                      },
                    ),
                  ),
                ] else if (controller.text.trim().isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('未命中。请补充备注、关键词或情绪标签。'),
                  ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  void _runSearchTest(
    TextEditingController controller,
    StateSetter setDialogState,
    void Function(List<UserSticker>) updateResults,
  ) {
    setDialogState(() {
      updateResults(context
          .read<StickerProvider>()
          .searchUserStickers(controller.text, limit: 5));
    });
  }

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

  Future<void> _editMetadata(UserSticker sticker) async {
    final labelController = TextEditingController(text: sticker.label);
    final descriptionController =
        TextEditingController(text: sticker.description);
    final keywordsController =
        TextEditingController(text: sticker.keywords.join('、'));
    final emotionController =
        TextEditingController(text: sticker.emotionTags.join('、'));
    final saved = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('编辑表情包信息'),
        content: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                CupertinoTextField(
                    controller: labelController,
                    autofocus: true,
                    placeholder: '备注，如：熊猫头无语'),
                const SizedBox(height: 8),
                CupertinoTextField(
                    controller: descriptionController,
                    placeholder: '含义描述，如：面无表情地表达无奈',
                    maxLines: 2),
                const SizedBox(height: 8),
                CupertinoTextField(
                    controller: keywordsController,
                    placeholder: '关键词，用顿号或逗号分隔'),
                const SizedBox(height: 8),
                CupertinoTextField(
                    controller: emotionController, placeholder: '情绪标签，如：无语、吐槽'),
              ],
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      await context.read<StickerProvider>().updateUserStickerMetadata(
            stickerId: sticker.id,
            label: labelController.text,
            description: descriptionController.text,
            keywords: keywordsController.text.split(RegExp(r'[,，、\n]')),
            emotionTags: emotionController.text.split(RegExp(r'[,，、\n]')),
          );
    }
    labelController.dispose();
    descriptionController.dispose();
    keywordsController.dispose();
    emotionController.dispose();
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
      children: [
        CupertinoListTile(
          leading: Icon(CupertinoIcons.search, color: context.accentColor),
          title: const Text('测试表情包检索'),
          subtitle: const Text('输入关键词，确认角色可检索到的表情包'),
          trailing: Icon(CupertinoIcons.chevron_right,
              size: 16, color: context.textSecondaryColor),
          onTap: _showSearchTest,
        ),
        if (stickers.isEmpty)
          const CupertinoListTile(title: Text('暂无自定义表情包'))
        else
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
                      _editMetadata(sticker);
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
