import 'package:flutter/services.dart';

/// 选择的文件信息
class PickedFileInfo {
  final String path;
  final String name;

  const PickedFileInfo({required this.path, required this.name});
}

/// 调用 Android 原生文件选择器（MainActivity 中实现，Android 专用）
class FilePickerHelper {
  static const MethodChannel _channel = MethodChannel('com.aichat.ai_chat/files');

  /// 打开系统文件选择器，返回选中的文件；用户取消返回 null
  static Future<PickedFileInfo?> pickFile() async {
    final result = await _channel.invokeMethod('pickFile');
    if (result == null) return null;
    final map = result as Map<dynamic, dynamic>;
    return PickedFileInfo(
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? 'file',
    );
  }

  /// 打开系统"保存文件"选择器（Android ACTION_CREATE_DOCUMENT），
  /// 由用户自选保存位置与文件名后写入 [bytes]。
  /// 返回保存的文件名；用户取消返回 null。
  static Future<String?> saveFile({
    required String suggestedName,
    String mimeType = 'application/octet-stream',
    required Uint8List bytes,
  }) async {
    final result = await _channel.invokeMethod('saveFile', {
      'suggestedName': suggestedName,
      'mimeType': mimeType,
      'bytes': bytes,
    });
    if (result == null) return null;
    final map = result as Map<dynamic, dynamic>;
    return map['name'] as String? ?? suggestedName;
  }

  /// 调用系统"打开方式"打开本地文件（Android ACTION_VIEW + FileProvider）。
  /// 返回 null 表示打开成功（已交给其他应用），否则返回错误提示信息。
  static Future<String?> openFile(String path) async {
    try {
      final ok = await _channel.invokeMethod('openFile', {'path': path});
      return ok == true ? null : '打开文件失败';
    } on PlatformException catch (e) {
      return e.message ?? '打开文件失败';
    }
  }
}
