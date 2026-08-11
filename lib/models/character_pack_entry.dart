import 'character.dart';

/// 从角色包 zip 中解析出的单个角色条目
class CharacterPackEntry {
  /// zip 中的角色文件夹名（如"爱弥斯"）
  final String folderName;

  /// 解析出的角色数据（id 为占位，导入时需重新生成）
  final Character character;

  /// 解析失败原因（非空表示该目录不可导入）
  final String? error;

  CharacterPackEntry({
    required this.folderName,
    required this.character,
    this.error,
  });
}
