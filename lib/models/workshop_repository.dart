import '../services/cos_auth.dart';
import 'workshop_asset.dart';

/// 创意工坊仓库来源类型
enum WorkshopRepoType {
  /// GitHub / Gitee Release 仓库
  git,

  /// COS 类对象储存（腾讯云 COS / 阿里云 OSS / AWS S3 / MinIO 等）
  cos,
}

/// 创意工坊配置的角色卡仓库
class WorkshopRepository {
  final String id;

  /// 显示名（owner/repo 或 COS host/末级路径）
  final String name;

  /// 用户输入的仓库路径（owner/repo、完整仓库 URL 或 COS BASE_URL）
  final String url;

  /// 下载代理前缀（空串 = 不使用代理；Gitee / COS 固定为不使用代理）
  final String proxyUrl;

  /// 检查后可用的 Release tag（V1.1.0 / V1.0.0 / V1.3.0 / V1.2.0）
  final List<String> availableTags;

  /// 检查失败原因（非空表示不可用）
  final String? error;

  /// 来源类型：Git Release 或 COS 对象储存
  final WorkshopRepoType type;

  /// COS 私有读访问密钥（仅 cos 类型有意义）
  final CosAuth cosAuth;

  const WorkshopRepository({
    required this.id,
    required this.name,
    required this.url,
    required this.proxyUrl,
    this.availableTags = const [],
    this.error,
    this.type = WorkshopRepoType.git,
    this.cosAuth = const CosAuth(),
  });

  /// 是否为 Git 来源
  bool get isGit => type == WorkshopRepoType.git;

  /// 是否为 COS 对象储存来源
  bool get isCos => type == WorkshopRepoType.cos;

  /// COS 是否启用私有读鉴权
  bool get hasCosAuth => isCos && cosAuth.isConfigured;

  /// 是否有可用的资产 tag
  bool get isAvailable => error == null && availableTags.isNotEmpty;

  /// 是否可用「角色分类」（V1.1.0）
  bool get hasCharacter => availableTags.contains(kCharacterPackTag);

  /// 是否可用「游戏分类」（V1.0.0）
  bool get hasGame => availableTags.contains(kGamePackTag);

  /// 是否可用「表情包分类」（V1.3.0）
  bool get hasSticker => availableTags.contains(kStickerPackTag);

  /// 是否有「更新通知」tag（V1.2.0）
  bool get hasUpdateNotify => availableTags.contains(kUpdateNotifyTag);

  static const _unset = Object();

  WorkshopRepository copyWith({
    List<String>? availableTags,
    Object? error = _unset,
    WorkshopRepoType? type,
    CosAuth? cosAuth,
  }) {
    return WorkshopRepository(
      id: id,
      name: name,
      url: url,
      proxyUrl: proxyUrl,
      availableTags: availableTags ?? this.availableTags,
      error: identical(error, _unset) ? this.error : error as String?,
      type: type ?? this.type,
      cosAuth: cosAuth ?? this.cosAuth,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'proxyUrl': proxyUrl,
        'availableTags': availableTags,
        'error': error,
        'type': type.name,
        'cosAuth': cosAuth.toJson(),
      };

  factory WorkshopRepository.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    return WorkshopRepository(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      proxyUrl: json['proxyUrl'] as String? ?? '',
      availableTags: (json['availableTags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      error: json['error'] as String?,
      // 旧数据无 type 字段时默认 git（向后兼容）
      type: WorkshopRepoType.values.firstWhere(
        (e) => e.name == typeName,
        orElse: () => WorkshopRepoType.git,
      ),
      cosAuth: CosAuth.fromJson(json['cosAuth'] as Map<String, dynamic>?),
    );
  }
}
