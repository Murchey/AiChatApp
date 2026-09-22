import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import '../screens/image_crop_screen.dart';

/// 头像选择：相册/拍照 → 方形裁剪 → 返回 JPEG 字节（未裁剪取消则为 null）。
///
/// 供角色资料、「自己」资料、聊天详情等处复用；调用方负责 base64 与写库。
Future<Uint8List?> pickAndCropAvatar(
  BuildContext context, {
  ImageSource source = ImageSource.gallery,
}) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: source,
    // 裁剪页会重新取景；这里只限制解码尺寸，避免超大图卡顿
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 92,
  );
  if (file == null) return null;
  if (!context.mounted) return null;
  final croppedPath = await Navigator.push<String>(
    context,
    CupertinoPageRoute(
      builder: (_) => ImageCropScreen(
        imagePath: file.path,
        squareCrop: true,
        maxOutputSide: 500,
        title: '裁剪头像',
      ),
    ),
  );
  if (croppedPath == null) return null;
  try {
    final bytes = await File(croppedPath).readAsBytes();
    return bytes;
  } finally {
    try {
      File(croppedPath).deleteSync();
    } catch (_) {}
  }
}

/// [pickAndCropAvatar] 的 base64 封装。
Future<String?> pickAndCropAvatarBase64(
  BuildContext context, {
  ImageSource source = ImageSource.gallery,
}) async {
  final bytes = await pickAndCropAvatar(context, source: source);
  if (bytes == null) return null;
  return base64Encode(bytes);
}
