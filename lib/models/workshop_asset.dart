/// 角色分类角色包 Release tag（zip 内含 Profile.json 的角色文件夹）
const String kCharacterPackTag = 'V1.1.0';

/// 游戏分类角色包 Release tag（zip 内含 moments.json 的朋友圈数据包）
const String kGamePackTag = 'V1.0.0';

/// 创意工坊支持的全部 Release tag
const List<String> kWorkshopPackTags = [kCharacterPackTag, kGamePackTag];

/// 创意工坊仓库 Release 中的资产（zip 下载项）
class WorkshopAsset {
  /// 所属 Release 的 tag（V1.1.0=角色分类 / V1.0.0=游戏分类）
  final String tag;

  /// zip 文件名
  final String name;

  /// 下载直链（GitHub 无资产记录时可由 tag + 文件名拼接）
  final String downloadUrl;

  /// 文件大小（字节），可能为 null
  final int? sizeBytes;

  const WorkshopAsset({
    required this.tag,
    required this.name,
    required this.downloadUrl,
    this.sizeBytes,
  });

  bool get isCharacter => tag == kCharacterPackTag;
  bool get isGame => tag == kGamePackTag;
}
