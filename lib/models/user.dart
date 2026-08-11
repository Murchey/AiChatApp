class User {
  final String id;
  final String nickname;
  final String avatar;
  final String region; // 地区定位
  final String signature; // 个性签名
  final String gender; // 性别（男/女/保密）
  final DateTime createdAt;

  User({
    required this.id,
    required this.nickname,
    this.avatar = '',
    this.region = '',
    this.signature = '',
    this.gender = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      avatar: json['avatar'] as String? ?? '',
      region: json['region'] as String? ?? '',
      signature: json['signature'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nickname': nickname,
      'avatar': avatar,
      'region': region,
      'signature': signature,
      'gender': gender,
      'created_at': createdAt.toIso8601String(),
    };
  }

  User copyWith({
    String? nickname,
    String? avatar,
    String? region,
    String? signature,
    String? gender,
  }) {
    return User(
      id: id,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      region: region ?? this.region,
      signature: signature ?? this.signature,
      gender: gender ?? this.gender,
      createdAt: createdAt,
    );
  }
}
