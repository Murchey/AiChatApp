import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/settings_provider.dart';
import '../services/imported_font_storage.dart';
import '../utils/app_toast.dart';

/// 管理本地 TTF 文件，并分别选择我方/对方聊天气泡字体。
class BubbleFontScreen extends StatefulWidget {
  const BubbleFontScreen({super.key});

  @override
  State<BubbleFontScreen> createState() => _BubbleFontScreenState();
}

class _BubbleFontScreenState extends State<BubbleFontScreen> {
  final _storage = const ImportedFontStorage();
  List<ImportedFont> _fonts = const [];
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final fonts = await _storage.listFonts();
    if (!mounted) return;
    setState(() {
      _fonts = fonts;
      _loading = false;
    });
  }

  Future<void> _importFonts() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ttf'],
        withData: true,
        allowMultiple: true,
      );
      if (result == null) return;
      var imported = 0;
      for (final file in result.files) {
        final Uint8List? bytes = file.bytes;
        if (bytes == null || !isSupportedImportedFontFile(file.name)) continue;
        await _storage.saveFont(file.name, bytes);
        imported++;
      }
      await _reload();
      if (mounted && imported > 0) showAppToast('已导入 $imported 个字体文件');
    } on FormatException catch (error) {
      if (mounted) showAppToast(error.message);
    } catch (_) {
      if (mounted) showAppToast('导入字体失败，请确认文件可读取');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _selectFont(bool isUser) async {
    final settings = context.read<SettingsProvider>();
    final current = isUser ? settings.selfBubbleFontName : settings.otherBubbleFontName;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(isUser ? '我方气泡字体' : '对方气泡字体'),
        message: const Text('仅影响聊天正文；留在系统默认可避免字体缺字。'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: current.isEmpty,
            onPressed: () async {
              await settings.setBubbleFont(isUser: isUser, name: '');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('系统默认'),
          ),
          for (final font in _fonts)
            CupertinoActionSheetAction(
              isDefaultAction: current == font.name,
              onPressed: () async {
                try {
                  await settings.setBubbleFont(isUser: isUser, name: font.name);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (_) {
                  if (ctx.mounted) showAppToast('字体加载失败，请重新导入');
                }
              },
              child: Text(font.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _deleteFont(ImportedFont font) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除字体'),
        content: Text('删除「${font.name}」？已使用该字体的气泡会恢复系统默认字体。'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.deleteFont(font.name);
    if (!mounted) return;
    await context.read<SettingsProvider>().clearDeletedBubbleFont(font.name);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('气泡字体'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _importing ? null : _importFonts,
          child: _importing
              ? const CupertinoActivityIndicator(radius: 9)
              : const Icon(CupertinoIcons.add_circled),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                children: [
                  CupertinoListSection.insetGrouped(
                    backgroundColor: context.scaffoldColor,
                    header: const Text('显示设置'),
                    children: [
                      _fontTile('我方气泡字体', settings.selfBubbleFontName, true),
                      _fontTile('对方气泡字体', settings.otherBubbleFontName, false),
                    ],
                  ),
                  CupertinoListSection.insetGrouped(
                    backgroundColor: context.scaffoldColor,
                    header: Text('已导入字体（${_fonts.length}）'),
                    footer: const Text('仅保存 TTF 字体文件。删除后会同步解除气泡字体引用。'),
                    children: _fonts.isEmpty
                        ? const [CupertinoListTile(title: Text('暂无字体'), subtitle: Text('点击右上角 + 导入 TTF 文件'))]
                        : [
                            for (final font in _fonts)
                              CupertinoListTile(
                                title: Text(font.name, style: TextStyle(fontFamily: font.family)),
                                subtitle: Text('${_formatBytes(font.sizeBytes)} · TTF'),
                                trailing: CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _deleteFont(font),
                                  child: const Icon(CupertinoIcons.trash, color: CupertinoColors.systemRed, size: 20),
                                ),
                              ),
                          ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _fontTile(String title, String name, bool isUser) => CupertinoListTile(
        title: Text(title),
        subtitle: const Text('聊天正文单独设置，不影响界面文字'),
        additionalInfo: Text(name.isEmpty ? '系统默认' : name),
        trailing: Icon(CupertinoIcons.chevron_right, size: 16, color: context.textSecondaryColor),
        onTap: _fonts.isEmpty ? null : () => _selectFont(isUser),
      );

  String _formatBytes(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
