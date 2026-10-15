import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../services/app_icon_service.dart';
import '../services/widget_sync_service.dart';
import '../providers/chat_provider.dart';
import '../providers/token_usage_provider.dart';
import '../config/theme.dart';
import '../utils/app_toast.dart';
import '../widgets/settings/settings_ui.dart';
import 'image_crop_screen.dart';

class WidgetIconSettingsScreen extends StatefulWidget {
  const WidgetIconSettingsScreen({super.key});
  @override
  State<WidgetIconSettingsScreen> createState() =>
      _WidgetIconSettingsScreenState();
}

class _WidgetIconSettingsScreenState extends State<WidgetIconSettingsScreen> {
  final icons = AppIconService.instance;
  bool _busy = false;
  Uint8List? _preview;
  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    if (!icons.supported) return;
    try {
      final bytes = await AppIconService.channel
          .invokeMethod<Uint8List>('preview', {'mode': icons.mode});
      if (mounted) setState(() => _preview = bytes);
    } catch (e) {
      debugPrint('图标预览失败: $e');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _loadPreview();
    } catch (e) {
      if (mounted) showAppToast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() => _run(() async {
        final picked =
            await ImagePicker().pickImage(source: ImageSource.gallery);
        if (picked == null) return;
        if (!RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false)
            .hasMatch(picked.path)) {
          throw const FormatException('请选择 PNG/JPG/WebP 静态图片');
        }
        final file = File(picked.path);
        if (await file.length() > 5 * 1024 * 1024) {
          throw const FormatException('图片不能超过 5 MiB');
        }
        final codec = await ui.instantiateImageCodec(await file.readAsBytes());
        try {
          if (codec.frameCount != 1) throw const FormatException('不支持动态图片');
          final frame = await codec.getNextFrame();
          final w = frame.image.width, h = frame.image.height;
          frame.image.dispose();
          if (w < 192 || h < 192) {
            throw const FormatException('图片至少为 192×192 像素');
          }
        } finally {
          codec.dispose();
        }
        if (!mounted) return;
        final path = await Navigator.push<String>(
            context,
            CupertinoPageRoute(
                builder: (_) => ImageCropScreen(
                    imagePath: picked.path,
                    squareCrop: true,
                    maxOutputSide: 512,
                    title: '裁剪快捷方式图标')));
        if (path == null) return;
        try {
          final status = await icons.createShortcut(path);
          if (mounted) {
            showAppToast(status == 'requested'
                ? '已请求系统添加，请在桌面确认；取消则不会添加'
                : status == 'unsupported'
                    ? '当前桌面不支持固定快捷方式'
                    : '添加请求失败');
          }
        } finally {
          final temp = File(path);
          if (await temp.exists()) await temp.delete();
        }
      });
  Future<void> _refresh() => _run(() async {
        final token = context.read<TokenUsageProvider>();
        final chat = context.read<ChatProvider>();
        await token.init();
        await WidgetSyncService.refreshNow(token, chat);
        final status = await icons.refresh();
        if (status == 'failed') throw StateError('快捷方式更新失败');
        if (status == 'unsupported') {
          throw UnsupportedError('当前桌面不支持图标或快捷方式刷新');
        }
        if (mounted) {
          showAppToast(status == 'not_pinned'
              ? '小组件及应用图标已刷新；自选快捷方式尚未添加，请重新确认创建'
              : '已提交刷新，桌面显示可能稍有延迟');
        }
      });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: icons,
      builder: (context, _) => CupertinoPageScaffold(
            navigationBar: settingsNavigationBar(context, '小组件和应用图标'),
            child: SafeArea(
                child: ListView(children: [
              if (!icons.supported)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('应用图标切换和桌面小组件目前仅支持 Android。')),
              if (_preview != null)
                Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                        child: Image.memory(_preview!, width: 80, height: 80))),
              SettingsSection(title: '预置应用图标', children: [
                for (final entry in const {
                  'system': '跟随系统',
                  'light': '浅色图标',
                  'dark': '深色图标'
                }.entries)
                  CupertinoListTile(
                      title: Text(entry.value),
                      trailing: icons.mode == entry.key
                          ? const Icon(CupertinoIcons.checkmark)
                          : null,
                      onTap: _busy || !icons.supported
                          ? null
                          : () => _run(() => icons.select(entry.key))),
              ]),
              SettingsSection(
                  title: '自选桌面快捷方式',
                  footer: const Text(
                      'PNG/JPG/WebP 静态方图，至少 192×192，建议 512×512，不超过 5 MiB。可裁剪预览。创建的是桌面快捷方式，原应用图标会保留。恢复备份后需重新确认创建。'),
                  children: [
                    if (icons.imagePath != null)
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: Image.file(File(icons.imagePath!),
                              width: 80,
                              height: 80,
                              cacheWidth: 192,
                              errorBuilder: (context, error, stack) =>
                                  const SizedBox())),
                    if (icons.shortcutStatus.isNotEmpty)
                      Text(icons.shortcutStatus),
                    CupertinoButton(
                        onPressed: _busy || !icons.supported ? null : _pick,
                        child: const Text('使用图片创建桌面快捷方式')),
                  ]),
              CupertinoButton(
                  onPressed: _busy || !icons.supported ? null : _refresh,
                  child: const Text('立刻刷新小组件和应用图标')),
              if (_busy) const CupertinoActivityIndicator(),
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('部分桌面启动器会缓存图标，刷新后可能稍有延迟。',
                      style: TextStyle(color: context.textSecondaryColor))),
            ])),
          ));
}
