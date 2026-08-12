import 'moment.dart';

/// 从朋友圈数据包 zip 中解析出的单个角色条目
class MomentsPackEntry {
  /// 用于匹配已有角色的角色名（文件夹名或 moments.json 中的 character_name）
  final String characterName;

  /// 解析出的朋友圈动态（图片已提取到本地，images 为绝对路径）
  final List<Moment> moments;

  /// 解析失败原因（非空表示该目录不可导入）
  final String? error;

  MomentsPackEntry({
    required this.characterName,
    required this.moments,
    this.error,
  });
}
