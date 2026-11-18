/// Origin type of a chat conversation.
enum ConversationSourceType {
  direct('direct'),
  roleplay('roleplay'),
  deepseekImport('deepseek_import');

  const ConversationSourceType(this.value);
  final String value;

  static ConversationSourceType fromValue(String? value) {
    return ConversationSourceType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ConversationSourceType.direct,
    );
  }
}

/// Summary record for a chat thread shown on the WeChat-style chat list.
class Conversation {
  const Conversation({
    required this.id,
    this.externalId,
    required this.title,
    this.characterId,
    this.sourceType = ConversationSourceType.direct,
    this.avatarPath,
    this.avatarColor = 0xFF07C160,
    this.isPinned = false,
    this.isMuted = false,
    this.unreadCount = 0,
    this.lastMessagePreview = '',
    this.contextSummary = '',
    this.contextSummarizedUntilMs = 0,
    required this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? externalId;
  final String title;
  final String? characterId;
  final ConversationSourceType sourceType;
  final String? avatarPath;
  final int avatarColor;
  final bool isPinned;
  final bool isMuted;
  final int unreadCount;
  final String lastMessagePreview;
  final String contextSummary;
  final int contextSummarizedUntilMs;
  final DateTime lastMessageAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation copyWith({
    String? id,
    String? Function()? externalId,
    String? title,
    String? Function()? characterId,
    ConversationSourceType? sourceType,
    String? Function()? avatarPath,
    int? avatarColor,
    bool? isPinned,
    bool? isMuted,
    int? unreadCount,
    String? lastMessagePreview,
    String? contextSummary,
    int? contextSummarizedUntilMs,
    DateTime? lastMessageAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      externalId: externalId != null ? externalId() : this.externalId,
      title: title ?? this.title,
      characterId: characterId != null ? characterId() : this.characterId,
      sourceType: sourceType ?? this.sourceType,
      avatarPath: avatarPath != null ? avatarPath() : this.avatarPath,
      avatarColor: avatarColor ?? this.avatarColor,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      contextSummary: contextSummary ?? this.contextSummary,
      contextSummarizedUntilMs: contextSummarizedUntilMs ?? this.contextSummarizedUntilMs,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'external_id': externalId,
      'title': title,
      'character_id': characterId,
      'source_type': sourceType.value,
      'avatar_path': avatarPath,
      'avatar_color': avatarColor,
      'is_pinned': isPinned ? 1 : 0,
      'is_muted': isMuted ? 1 : 0,
      'unread_count': unreadCount,
      'last_message_preview': lastMessagePreview,
      'context_summary': contextSummary,
      'context_summarized_until_ms': contextSummarizedUntilMs,
      'last_message_at': lastMessageAt.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Conversation.fromMap(Map<String, Object?> map) {
    return Conversation(
      id: map['id'] as String,
      externalId: map['external_id'] as String?,
      title: map['title'] as String,
      characterId: map['character_id'] as String?,
      sourceType: ConversationSourceType.fromValue(map['source_type'] as String?),
      avatarPath: map['avatar_path'] as String?,
      avatarColor: map['avatar_color'] as int? ?? 0xFF07C160,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      isMuted: (map['is_muted'] as int? ?? 0) == 1,
      unreadCount: map['unread_count'] as int? ?? 0,
      lastMessagePreview: map['last_message_preview'] as String? ?? '',
      contextSummary: map['context_summary'] as String? ?? '',
      contextSummarizedUntilMs: map['context_summarized_until_ms'] as int? ?? 0,
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(map['last_message_at'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}
