import 'workshop_asset.dart';

/// 创意工坊配置的角色卡仓库
class WorkshopRepository {
  final String id;

  /// 显示名（owner/repo）
  final String name;

  /// 用户输入的仓库路径（owner/repo 或完整仓库 URL）
  final String url;

  /// 下载代理前缀（空串 = 不使用代理；Gitee 仓库固定为不使用代理）
  final String proxyUrl;

  /// 检查后可用的 Release tag（V1.1.0 / V1.0.0）
  final List<String> availableTags;

  /// 检查失败原因（非空表示不可用）
  final String? error;

  const WorkshopRepository({
    required this.id,
    required this.name,
    required this.url,
    required this.proxyUrl,
    this.availableTags = const [],
    this.error,
  });

  /// 是否有可用的资产 tag
  bool get isAvailable => error == null && availableTags.isNotEmpty;

  /// 是否可用「角色分类」（V1.1.0）
  bool get hasCharacter => availableTags.contains(kCharacterPackTag);

  /// 是否可用「游戏分类」（V1.0.0）
  bool get hasGame => availableTags.contains(kGamePackTag);

  /// 是否有「更新通知」tag（V1.2.0）
  bool get hasUpdateNotify => availableTags.contains(kUpdateNotifyTag);

  static const _unset = Object();

  WorkshopRepository copyWith({
    List<String>? availableTags,
    Object? error = _unset,
  }) {
    return WorkshopRepository(
      id: id,
      name: name,
      url: url,
      proxyUrl: proxyUrl,
      availableTags: availableTags ?? this.availableTags,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'proxyUrl': proxyUrl,
        'availableTags': availableTags,
        'error': error,
      };

  factory WorkshopRepository.fromJson(Map<String, dynamic> json) {
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
    );
  }
}
