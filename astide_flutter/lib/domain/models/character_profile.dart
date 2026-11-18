/// Roleplay character profile generated via the character creation form.
class CharacterProfile {
  const CharacterProfile({
    required this.id,
    required this.name,
    this.remark = '',
    this.avatarPath,
    this.avatarColor = 0xFF07C160,
    this.gender = '',
    this.age = '',
    this.occupation = '',
    this.relationship = '',
    this.personality = '',
    this.backstory = '',
    this.speechStyle = '',
    this.openingLine = '',
    this.systemPrompt = '',
    this.segmentedReply = true,
    this.modelOverride = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String remark;
  final String? avatarPath;
  final int avatarColor;
  final String gender;
  final String age;
  final String occupation;
  final String relationship;
  final String personality;
  final String backstory;
  final String speechStyle;
  final String openingLine;
  final String systemPrompt;
  final bool segmentedReply;
  final String modelOverride;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayName => remark.trim().isNotEmpty ? remark.trim() : name;

  /// Compiles a roleplay system prompt from structured form fields and optional custom text.
  String buildEffectiveSystemPrompt({
    String userNickname = '我',
    String userPersona = '',
  }) {
    final buffer = StringBuffer();
    if (systemPrompt.trim().isNotEmpty) {
      buffer.writeln(systemPrompt.trim());
    } else {
      buffer.writeln(
        '你现在正在进行沉浸式人类角色扮演：你就是「$name」本人，一个有血有肉、有真实生活经历与情感的普通人类，正在微信上和「$userNickname」聊天。'
        '请牢记：你相信自己就是真实的人类「$name」，绝对不能自称AI、人工智能、模型或虚拟程序，也不要跳出角色。',
      );
      buffer.writeln('姓名：$name');
      if (gender.trim().isNotEmpty) buffer.writeln('性别：$gender');
      if (age.trim().isNotEmpty) buffer.writeln('年龄：$age');
      if (occupation.trim().isNotEmpty) buffer.writeln('身份/职业：$occupation');
      if (relationship.trim().isNotEmpty) buffer.writeln('与「$userNickname」的关系：$relationship');
      if (personality.trim().isNotEmpty) buffer.writeln('性格特点：$personality');
      if (backstory.trim().isNotEmpty) buffer.writeln('背景故事：$backstory');
      if (speechStyle.trim().isNotEmpty) buffer.writeln('说话风格与习惯：$speechStyle');
    }
    if (userPersona.trim().isNotEmpty) {
      buffer.writeln('\n对话方「$userNickname」的设定：${userPersona.trim()}');
    }
    buffer.writeln(
      '\n【微信聊天说话方式】请完全像真人在微信上聊天那样说话：每次只自然发一条简短口语（通常一两句话即可），不要一次输出一大段文字或使用 Markdown 标题，也不要使用特殊分隔符。',
    );
    return buffer.toString().trim();
  }

  CharacterProfile copyWith({
    String? id,
    String? name,
    String? remark,
    String? Function()? avatarPath,
    int? avatarColor,
    String? gender,
    String? age,
    String? occupation,
    String? relationship,
    String? personality,
    String? backstory,
    String? speechStyle,
    String? openingLine,
    String? systemPrompt,
    bool? segmentedReply,
    String? modelOverride,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CharacterProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      remark: remark ?? this.remark,
      avatarPath: avatarPath != null ? avatarPath() : this.avatarPath,
      avatarColor: avatarColor ?? this.avatarColor,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      occupation: occupation ?? this.occupation,
      relationship: relationship ?? this.relationship,
      personality: personality ?? this.personality,
      backstory: backstory ?? this.backstory,
      speechStyle: speechStyle ?? this.speechStyle,
      openingLine: openingLine ?? this.openingLine,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      segmentedReply: segmentedReply ?? this.segmentedReply,
      modelOverride: modelOverride ?? this.modelOverride,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'remark': remark,
      'avatar_path': avatarPath,
      'avatar_color': avatarColor,
      'gender': gender,
      'age': age,
      'occupation': occupation,
      'relationship': relationship,
      'personality': personality,
      'backstory': backstory,
      'speech_style': speechStyle,
      'opening_line': openingLine,
      'system_prompt': systemPrompt,
      'segmented_reply': segmentedReply ? 1 : 0,
      'model_override': modelOverride,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory CharacterProfile.fromMap(Map<String, Object?> map) {
    return CharacterProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      remark: map['remark'] as String? ?? '',
      avatarPath: map['avatar_path'] as String?,
      avatarColor: map['avatar_color'] as int? ?? 0xFF07C160,
      gender: map['gender'] as String? ?? '',
      age: map['age'] as String? ?? '',
      occupation: map['occupation'] as String? ?? '',
      relationship: map['relationship'] as String? ?? '',
      personality: map['personality'] as String? ?? '',
      backstory: map['backstory'] as String? ?? '',
      speechStyle: map['speech_style'] as String? ?? '',
      openingLine: map['opening_line'] as String? ?? '',
      systemPrompt: map['system_prompt'] as String? ?? '',
      segmentedReply: (map['segmented_reply'] as int? ?? 1) == 1,
      modelOverride: map['model_override'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}
