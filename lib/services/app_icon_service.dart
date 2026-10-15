import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppIconService extends ChangeNotifier with WidgetsBindingObserver {
  AppIconService({bool? android}) : _android = android;
  final bool? _android;
  static final instance = AppIconService();
  static const channel = MethodChannel('com.aichat.ai_chat/icons');
  String mode = 'system';
  String? imagePath;
  String shortcutStatus = '';
  bool get supported => _android ?? Platform.isAndroid;
  bool _observing = false;
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    mode = prefs.getString('app_icon_mode') ?? 'system';
    final file = File(
        '${(await getApplicationDocumentsDirectory()).path}/app_icons/custom.png');
    imagePath = await file.exists() ? file.path : null;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (supported) {
      try {
        await channel.invokeMethod('setIcon', {'mode': mode});
      } catch (e) {
        debugPrint('图标初始化失败: $e');
      }
    }
    notifyListeners();
  }

  Future<void> select(String value) async {
    if (!supported) throw UnsupportedError('仅支持 Android');
    final applied =
        await channel.invokeMethod<bool>('setIcon', {'mode': value});
    if (applied != true) throw StateError('应用图标切换失败');
    await (await SharedPreferences.getInstance())
        .setString('app_icon_mode', value);
    mode = value;
    notifyListeners();
  }

  Future<String> createShortcut(String source) async {
    final dest = File(
        '${(await getApplicationDocumentsDirectory()).path}/app_icons/custom.png');
    await dest.parent.create(recursive: true);
    final codec = await ui.instantiateImageCodec(
        await File(source).readAsBytes(),
        targetWidth: 512,
        targetHeight: 512);
    try {
      final frame = await codec.getNextFrame();
      try {
        final bytes =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('图片编码失败');
        await dest.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
    imagePath = dest.path;
    notifyListeners();
    return await channel
            .invokeMethod<String>('pinShortcut', {'path': dest.path}) ??
        'failed';
  }

  Future<String> refresh() async {
    if (!supported) return 'unsupported';
    return await channel.invokeMethod<String>(
            'refresh', {'mode': mode, 'path': imagePath}) ??
        'failed';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (supported && state == AppLifecycleState.resumed && imagePath != null) {
      channel.invokeMethod<String>('shortcutStatus').then((value) {
        shortcutStatus = value == 'pinned' ? '自选桌面快捷方式已添加' : '自选桌面快捷方式尚未添加或已取消';
        notifyListeners();
      }).catchError((Object e) {
        debugPrint('快捷方式状态检查失败: $e');
      });
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (supported && mode == 'system') {
      channel.invokeMethod('setIcon', {'mode': mode}).catchError((Object e) {
        debugPrint('图标更新失败: $e');
      });
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
