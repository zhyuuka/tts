class Conversation {
  final String id;
  final String name;
  final String systemPrompt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String avatarBase64;
  final String wallpaperBase64;

  Conversation({
    required this.id,
    required this.name,
    this.systemPrompt = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.avatarBase64 = '',
    this.wallpaperBase64 = '',
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'systemPrompt': systemPrompt,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'avatarBase64': avatarBase64,
      'wallpaperBase64': wallpaperBase64,
    };
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    // 空安全读取：key 缺失或类型不符时用默认值兜底，避免整个加载失败
    return Conversation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      avatarBase64: json['avatarBase64'] as String? ?? '',
      wallpaperBase64: json['wallpaperBase64'] as String? ?? '',
    );
  }

  Conversation copyWith({
    String? name,
    String? systemPrompt,
    DateTime? updatedAt,
    String? avatarBase64,
    String? wallpaperBase64,
  }) {
    return Conversation(
      id: id,
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      avatarBase64: avatarBase64 ?? this.avatarBase64,
      wallpaperBase64: wallpaperBase64 ?? this.wallpaperBase64,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Conversation && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
