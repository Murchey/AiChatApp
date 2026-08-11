class Character {
  final String id;
  final String name; // 昵称
  final String remark; // 备注（显示名优先使用）
  final String signature; // 个性签名
  final String region; // 定位地区
  final String avatar;
  final String description;
  final String personality;
  final String greeting;
  final String systemPrompt;
  final String userRelationship; // 用户与角色的关系
  final List<String> tags;

  Character({
    required this.id,
    required this.name,
    this.remark = '',
    this.signature = '',
    this.region = '',
    this.avatar = '',
    this.description = '',
    this.personality = '',
    this.greeting = '',
    this.systemPrompt = '',
    this.userRelationship = '',
    this.tags = const [],
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
      description: json['description'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      greeting: json['greeting'] as String? ?? '',
      systemPrompt: json['system_prompt'] as String? ?? '',
      userRelationship: json['user_relationship'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
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
      'description': description,
      'personality': personality,
      'greeting': greeting,
      'system_prompt': systemPrompt,
      'user_relationship': userRelationship,
      'tags': tags,
    };
  }

  Character copyWith({
    String? name,
    String? remark,
    String? signature,
    String? region,
    String? avatar,
    String? description,
    String? personality,
    String? greeting,
    String? systemPrompt,
    String? userRelationship,
    List<String>? tags,
  }) {
    return Character(
      id: id,
      name: name ?? this.name,
      remark: remark ?? this.remark,
      signature: signature ?? this.signature,
      region: region ?? this.region,
      avatar: avatar ?? this.avatar,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      greeting: greeting ?? this.greeting,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      userRelationship: userRelationship ?? this.userRelationship,
      tags: tags ?? this.tags,
    );
  }
}
