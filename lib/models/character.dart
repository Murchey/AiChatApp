import 'moment.dart';

class Character {
  final String id;
  final String name; // 昵称
  final String remark; // 备注（显示名优先使用）
  final String signature; // 个性签名
  final String region; // 定位地区
  final String avatar;
  final String background; // 详情页背景图（base64，空表示默认渐变）
  final String description;
  final String personality;
  final String greeting;
  final String systemPrompt;
  final String userRelationship; // 用户与角色的关系
  final List<String> tags;
  final List<Moment> moments; // 朋友圈动态（详情页展示）

  Character({
    required this.id,
    required this.name,
    this.remark = '',
    this.signature = '',
    this.region = '',
    this.avatar = '',
    this.background = '',
    this.description = '',
    this.personality = '',
    this.greeting = '',
    this.systemPrompt = '',
    this.userRelationship = '',
    this.tags = const [],
    this.moments = const [],
  });

  /// 显示名称：备注优先，其次昵称（类似微信联系人）
  String get displayName => remark.trim().isNotEmpty ? remark : name;

  factory Character.fromJson(Map<String, dynamic> json) {
    return Character(
      id: json['id'] as String,
      name: json['name'] as String,
      remark: json['remark'] as String? ?? '',
      signature: json['signature'] as String? ?? '',
      region: json['region'] as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
      background: json['background'] as String? ?? '',
      description: json['description'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      greeting: json['greeting'] as String? ?? '',
      systemPrompt: json['system_prompt'] as String? ?? '',
      userRelationship: json['user_relationship'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      moments: (json['moments'] as List<dynamic>?)
              ?.map((e) => Moment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'remark': remark,
      'signature': signature,
      'region': region,
      'avatar': avatar,
      'background': background,
      'description': description,
      'personality': personality,
      'greeting': greeting,
      'system_prompt': systemPrompt,
      'user_relationship': userRelationship,
      'tags': tags,
      'moments': moments.map((e) => e.toJson()).toList(),
    };
  }

  Character copyWith({
    String? name,
    String? remark,
    String? signature,
    String? region,
    String? avatar,
    String? background,
    String? description,
    String? personality,
    String? greeting,
    String? systemPrompt,
    String? userRelationship,
    List<String>? tags,
    List<Moment>? moments,
  }) {
    return Character(
      id: id,
      name: name ?? this.name,
      remark: remark ?? this.remark,
      signature: signature ?? this.signature,
      region: region ?? this.region,
      avatar: avatar ?? this.avatar,
      background: background ?? this.background,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      greeting: greeting ?? this.greeting,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      userRelationship: userRelationship ?? this.userRelationship,
      tags: tags ?? this.tags,
      moments: moments ?? this.moments,
    );
  }
}
