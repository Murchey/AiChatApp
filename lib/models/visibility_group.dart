/// 朋友圈展示范围的特殊 id
class VisibilityScope {
  /// 仅自己可见
  static const String onlyMe = 'only_me';

  /// 全部角色可见（默认）
  static const String all = 'all';
}

/// 朋友圈展示范围自定义分组：一组联系人（角色 id 列表）。
///
/// 分组由用户创建，用于发布朋友圈时选择可见范围；
/// 固定选项【仅自己可见】【全部角色可见】不在此模型中，由特殊 id 表示。
class VisibilityGroup {
  final String id;
  final String name;
  final List<String> memberIds;

  const VisibilityGroup({
    required this.id,
    required this.name,
    this.memberIds = const [],
  });

  factory VisibilityGroup.fromJson(Map<String, dynamic> json) {
    return VisibilityGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      memberIds: (json['member_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'member_ids': memberIds,
      };

  VisibilityGroup copyWith({String? name, List<String>? memberIds}) {
    return VisibilityGroup(
      id: id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
    );
  }
}
