import 'dart:convert';

/// Comment posted on a [MomentPost].
class MomentComment {
  const MomentComment({
    required this.id,
    required this.momentId,
    required this.authorId,
    required this.authorName,
    this.replyToName = '',
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String momentId;
  final String authorId;
  final String authorName;
  final String replyToName;
  final String content;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'moment_id': momentId,
      'author_id': authorId,
      'author_name': authorName,
      'reply_to_name': replyToName,
      'content': content,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory MomentComment.fromMap(Map<String, Object?> map) {
    return MomentComment(
      id: map['id'] as String,
      momentId: map['moment_id'] as String,
      authorId: map['author_id'] as String,
      authorName: map['author_name'] as String,
      replyToName: map['reply_to_name'] as String? ?? '',
      content: map['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

/// A WeChat Moments post authored by the user, 星汐 Astide, or a created character.
class MomentPost {
  const MomentPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.authorAvatarPath,
    this.authorAvatarColor = 0xFF07C160,
    required this.content,
    this.imagePaths = const [],
    this.likedByNames = const [],
    this.comments = const [],
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarPath;
  final int authorAvatarColor;
  final String content;
  final List<String> imagePaths;
  final List<String> likedByNames;
  final List<MomentComment> comments;
  final DateTime createdAt;

  bool get isByUser => authorId == 'user';

  MomentPost copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? Function()? authorAvatarPath,
    int? authorAvatarColor,
    String? content,
    List<String>? imagePaths,
    List<String>? likedByNames,
    List<MomentComment>? comments,
    DateTime? createdAt,
  }) {
    return MomentPost(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorAvatarPath:
          authorAvatarPath != null ? authorAvatarPath() : this.authorAvatarPath,
      authorAvatarColor: authorAvatarColor ?? this.authorAvatarColor,
      content: content ?? this.content,
      imagePaths: imagePaths ?? this.imagePaths,
      likedByNames: likedByNames ?? this.likedByNames,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'author_id': authorId,
      'author_name': authorName,
      'author_avatar_path': authorAvatarPath,
      'author_avatar_color': authorAvatarColor,
      'content': content,
      'image_paths_json': jsonEncode(imagePaths),
      'liked_by_names_json': jsonEncode(likedByNames),
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory MomentPost.fromMap(
    Map<String, Object?> map, {
    List<MomentComment> comments = const [],
  }) {
    List<String> decodeStringList(String? raw) {
      if (raw == null || raw.isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List<dynamic>) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
      return const [];
    }

    return MomentPost(
      id: map['id'] as String,
      authorId: map['author_id'] as String,
      authorName: map['author_name'] as String,
      authorAvatarPath: map['author_avatar_path'] as String?,
      authorAvatarColor: map['author_avatar_color'] as int? ?? 0xFF07C160,
      content: map['content'] as String? ?? '',
      imagePaths: decodeStringList(map['image_paths_json'] as String?),
      likedByNames: decodeStringList(map['liked_by_names_json'] as String?),
      comments: comments,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}
