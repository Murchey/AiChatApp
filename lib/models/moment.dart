/// 朋友圈单条评论
class MomentComment {
  final String sender;
  final String content;

  const MomentComment({required this.sender, required this.content});

  factory MomentComment.fromJson(Map<String, dynamic> json) {
    return MomentComment(
      sender: json['sender'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'sender': sender, 'content': content};
}

/// 角色朋友圈单条动态
///
/// 图片在导入时从角色包 `moments/files/` 提取到应用文档目录，[images]
/// 保存本地绝对路径；包内找不到对应图片时保留原相对路径字符串，展示层做容错。
class Moment {
  final String id;
  final String content;
  final String location; // 标记位置（如：北京市 · 朝阳区）
  final String visibility; // 展示范围（特殊 id 或分组 id，默认全部角色可见）
  final List<String> images;
  final List<String> likes;
  final List<MomentComment> comments;
  final DateTime? createdAt;

  const Moment({
    required this.id,
    this.content = '',
    this.location = '',
    this.visibility = 'all',
    this.images = const [],
    this.likes = const [],
    this.comments = const [],
    this.createdAt,
  });

  factory Moment.fromJson(Map<String, dynamic> json) {
    return Moment(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      location: json['location'] as String? ?? '',
      visibility: json['visibility'] as String? ?? 'all',
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      likes: (json['likes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      comments: (json['comments'] as List<dynamic>?)
              ?.map((e) => MomentComment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'location': location,
      'visibility': visibility,
      'images': images,
      'likes': likes,
      'comments': comments.map((e) => e.toJson()).toList(),
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
