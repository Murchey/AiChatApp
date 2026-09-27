import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'platform_support.dart';

/// 选择的文件信息
class PickedFileInfo {
  final String path;
  final String name;

  const PickedFileInfo({required this.path, required this.name});
}

/// 系统文件选择 / 保存。
///
/// - Android：MainActivity 原生通道（自定义保存 / 打开方式）
/// - Windows / macOS / Linux：file_picker 桌面实现
class FilePickerHelper {
  static const MethodChannel _channel =
      MethodChannel('com.aichat.ai_chat/files');

  /// 打开系统文件选择器，返回选中的文件；用户取消返回 null
  static Future<PickedFileInfo?> pickFile() async {
    if (PlatformSupport.isDesktop) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return null;
      final f = result.files.first;
      final path = f.path;
      if (path == null || path.isEmpty) return null;
      return PickedFileInfo(path: path, name: f.name);
    }
    try {
      final result = await _channel.invokeMethod('pickFile');
      if (result == null) return null;
      final map = result as Map<dynamic, dynamic>;
      return PickedFileInfo(
        path: map['path'] as String? ?? '',
        name: map['name'] as String? ?? 'file',
      );
    } on MissingPluginException {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return null;
      final f = result.files.first;
      final path = f.path;
      if (path == null) return null;
      return PickedFileInfo(path: path, name: f.name);
    }
  }

  /// 打开系统"保存文件"选择器，写入 [bytes]。
  /// 返回保存的文件名；用户取消返回 null。
  static Future<String?> saveFile({
    required String suggestedName,
    String mimeType = 'application/octet-stream',
    required Uint8List bytes,
  }) async {
    if (PlatformSupport.isDesktop) {
      final output = await FilePicker.platform.saveFile(
        dialogTitle: '保存文件',
        fileName: suggestedName,
        type: FileType.any,
        bytes: bytes,
      );
      if (output == null) return null;
      return output.split(RegExp(r'[/\\]')).last;
    }
    try {
      final result = await _channel.invokeMethod('saveFile', {
        'suggestedName': suggestedName,
        'mimeType': mimeType,
        'bytes': bytes,
      });
      if (result == null) return null;
      final map = result as Map<dynamic, dynamic>;
      return map['name'] as String? ?? suggestedName;
    } on MissingPluginException {
      final output = await FilePicker.platform.saveFile(
        fileName: suggestedName,
        bytes: bytes,
      );
      return output?.split(RegExp(r'[/\\]')).last;
    }
  }

  /// 从本地文件路径保存到系统"保存文件"选择器。
  /// 大文件走路径拷贝，避免字节经 Android Binder 触发大小限制。
  static Future<String?> saveFileFromPath({
    required String suggestedName,
    required String sourcePath,
    String mimeType = 'application/octet-stream',
  }) async {
    if (PlatformSupport.isDesktop) {
      final bytes = await File(sourcePath).readAsBytes();
      return saveFile(
        suggestedName: suggestedName,
        mimeType: mimeType,
        bytes: bytes,
      );
    }
    try {
      final result = await _channel.invokeMethod('saveFileFromPath', {
        'suggestedName': suggestedName,
        'sourcePath': sourcePath,
        'mimeType': mimeType,
      });
      if (result == null) return null;
      final map = result as Map<dynamic, dynamic>;
      return map['name'] as String? ?? suggestedName;
    } on MissingPluginException {
      final bytes = await File(sourcePath).readAsBytes();
      return saveFile(
        suggestedName: suggestedName,
        mimeType: mimeType,
        bytes: bytes,
      );
    }
  }

  /// 调用系统"打开方式"打开本地文件。
  /// 返回 null 表示打开成功，否则返回错误提示。
  static Future<String?> openFile(String path) async {
    if (PlatformSupport.isDesktop) {
      try {
        await FilePicker.platform.pickFiles(
          dialogTitle: '查看文件位置',
          initialDirectory: File(path).parent.path,
        );
        return null;
      } catch (_) {
        return '请在系统文件管理器中打开：$path';
      }
    }
    try {
      final ok = await _channel.invokeMethod('openFile', {'path': path});
      return ok == true ? null : '打开文件失败';
    } on PlatformException catch (e) {
      return e.message ?? '打开文件失败';
    } on MissingPluginException {
      return '当前平台暂不支持打开文件';
    }
  }
}
