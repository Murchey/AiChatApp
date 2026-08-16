import 'dart:io';

/// 静默删除本地文件（不存在或删除失败均不抛错）
void deleteFileQuietly(String path) {
  try {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}
