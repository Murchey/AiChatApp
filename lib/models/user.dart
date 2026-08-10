class User {
  final String id;
  final String nickname;
  final String avatar;
  final DateTime createdAt;

  User({
    required this.id,
    required this.nickname,
    this.avatar = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      avatar: json['avatar'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nickname': nickname,
      'avatar': avatar,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
