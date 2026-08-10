class Character {
  final String id;
  final String name;
  final String avatar;
  final String description;
  final String personality;
  final String greeting;
  final String systemPrompt;
  final List<String> tags;

  Character({
    required this.id,
    required this.name,
    this.avatar = '',
    this.description = '',
    this.personality = '',
    this.greeting = '',
    this.systemPrompt = '',
    this.tags = const [],
  });

  factory Character.fromJson(Map<String, dynamic> json) {
    return Character(
      id: json['id'] as String,
      name: json['name'] as String,
      avatar: json['avatar'] as String? ?? '',
      description: json['description'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      greeting: json['greeting'] as String? ?? '',
      systemPrompt: json['system_prompt'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'description': description,
      'personality': personality,
      'greeting': greeting,
      'system_prompt': systemPrompt,
      'tags': tags,
    };
  }

  Character copyWithSystemPrompt(String prompt) {
    return Character(
      id: id,
      name: name,
      avatar: avatar,
      description: description,
      personality: personality,
      greeting: greeting,
      systemPrompt: prompt,
      tags: tags,
    );
  }
}
