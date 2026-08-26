import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/sticker_pack.dart';
import '../providers/sticker_provider.dart';

class StickerSelection {
  final String imagePath;
  final String? label;

  const StickerSelection({required this.imagePath, this.label});
}

/// 聊天输入栏上方的表情包底部面板，不是独立二级页面。
class StickerPickerScreen extends StatefulWidget {
  final Future<void> Function(StickerSelection selection)? onSelected;
  final VoidCallback? onClose;

  const StickerPickerScreen({
    super.key,
    this.onSelected,
    this.onClose,
  });

  const StickerPickerScreen.embedded({
    super.key,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<StickerPickerScreen> createState() => _StickerPickerScreenState();
}

class _StickerPickerScreenState extends State<StickerPickerScreen> {
  final _picker = ImagePicker();
  StickerEntry? _selected;
  final _labelController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _addFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final label = await _askImportLabel();
    if (label == null || !mounted) return;
    final sticker = await context.read<StickerProvider>().addUserSticker(
          imagePath: file.path,
          label: label,
        );
    if (!mounted) return;
    setState(() {
      _selected = StickerEntry(
        imagePath: sticker.imagePath,
        label: sticker.label,
        stickerId: sticker.id,
      );
      _labelController.text = sticker.label;
    });
  }

  /// 相册导入时先收集备注，再一次性持久化。
  /// 取消输入不会把图片以空备注写入表情包库，也不会触发发送。
  Future<String?> _askImportLabel() async {
    final controller = TextEditingController();
    final label = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('添加表情包'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: '备注（用于检索和非视觉模型理解）',
            maxLines: 2,
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
    return label;
  }

  void _select(StickerEntry sticker) {
    setState(() {
      _selected = sticker;
      _labelController.text = sticker.label ?? '';
    });
  }

  void _send() {
    final sticker = _selected;
    if (sticker == null) return;
    final selection = StickerSelection(
      imagePath: sticker.imagePath,
      label: _labelController.text.trim().isEmpty
          ? null
          : _labelController.text.trim(),
    );
    if (widget.onSelected != null) {
      widget.onSelected!(selection);
    } else {
      Navigator.pop(context, selection);
    }
  }

  Future<void> _showStickerMenu(StickerEntry sticker) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('删除'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'front'),
            child: const Text('移到最前'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
    if (!mounted || action == null) return;
    final provider = context.read<StickerProvider>();
    if (action == 'delete') {
      if (sticker.stickerId != null) {
        await provider.removeUserSticker(sticker.stickerId!);
      } else {
        await provider.removePackSticker(sticker);
      }
    } else if (action == 'front') {
      await provider.moveToFront(sticker);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stickers = context.watch<StickerProvider>().availableStickers;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final fallbackHeight = MediaQuery.sizeOf(context).height * 0.4;
    final panelHeight = keyboardHeight > 0
        ? keyboardHeight.clamp(280.0, 420.0)
        : fallbackHeight.clamp(280.0, 320.0);

    return Container(
      height: panelHeight,
      decoration: BoxDecoration(
        color: context.scaffoldColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.separatorColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: [
                  Text('表情包',
                      style: TextStyle(color: context.textPrimaryColor)),
                  const Spacer(),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: _selected == null ? null : _send,
                    child: const Text('发送'),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: widget.onClose ?? () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                physics: const AlwaysScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: stickers.length + 1,
                itemBuilder: (_, index) {
                  if (index == 0) {
                    return GestureDetector(
                      onTap: _addFromGallery,
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.fieldBgColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Icon(CupertinoIcons.add,
                            color: context.textSecondaryColor, size: 30),
                      ),
                    );
                  }
                  final sticker = stickers[index - 1];
                  final selected = _selected?.imagePath == sticker.imagePath;
                  return GestureDetector(
                    onTap: () => _select(sticker),
                    onLongPress: () => _showStickerMenu(sticker),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? context.accentColor
                              : CupertinoColors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(sticker.imagePath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            CupertinoIcons.photo,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_selected != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: CupertinoTextField(
                  controller: _labelController,
                  placeholder: '备注（非视觉模型需要）',
                  maxLines: 2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
