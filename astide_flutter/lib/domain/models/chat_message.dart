import 'chat_attachment.dart';

/// Role of a chat message sender.
enum MessageRole {
  user('user'),
  assistant('assistant'),
  system('system');

  const MessageRole(this.value);
  final String value;

  static MessageRole fromValue(String? value) {
    return MessageRole.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MessageRole.assistant,
    );
  }
}

/// Lifecycle status of a chat message.
enum MessageStatus {
  sending('sending'),
  streaming('streaming'),
  sent('sent'),
  error('error');

  const MessageStatus(this.value);
  final String value;

  static MessageStatus fromValue(String? value) {
    return MessageStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MessageStatus.sent,
    );
  }
}

/// Single chat message stored in SQLite, optionally with reasoning text and attachments.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.reasoningContent = '',
    this.thinkingSeconds = 0,
    this.status = MessageStatus.sent,
    this.errorMessage = '',
    this.attachments = const [],
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final String reasoningContent;
  final double thinkingSeconds;
  final MessageStatus status;
  final String errorMessage;
  final List<ChatAttachment> attachments;
  final DateTime createdAt;

  bool get isUser => role == MessageRole.user;
  bool get hasReasoning => reasoningContent.trim().isNotEmpty;

  String get previewText {
    final trimmed = content.trim();
    if (trimmed.isNotEmpty) {
      return trimmed.replaceAll('\n', ' ');
    }
    if (attachments.isNotEmpty) {
      final first = attachments.first;
      return first.isImage ? '[图片]' : '[文件] ${first.fileName}';
    }
    if (status == MessageStatus.streaming) return '对方正在输入...';
    if (status == MessageStatus.error) return '[发送失败]';
    return '';
  }

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    MessageRole? role,
    String? content,
    String? reasoningContent,
    double? thinkingSeconds,
    MessageStatus? status,
    String? errorMessage,
    List<ChatAttachment>? attachments,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      thinkingSeconds: thinkingSeconds ?? this.thinkingSeconds,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      attachments: attachments ?? this.attachments,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'role': role.value,
      'content': content,
      'reasoning_content': reasoningContent,
      'thinking_seconds': thinkingSeconds,
      'status': status.value,
      'error_message': errorMessage,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory ChatMessage.fromMap(
    Map<String, Object?> map, {
    List<ChatAttachment> attachments = const [],
  }) {
    return ChatMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      role: MessageRole.fromValue(map['role'] as String?),
      content: map['content'] as String? ?? '',
      reasoningContent: map['reasoning_content'] as String? ?? '',
      thinkingSeconds: (map['thinking_seconds'] as num? ?? 0).toDouble(),
      status: MessageStatus.fromValue(map['status'] as String?),
      errorMessage: map['error_message'] as String? ?? '',
      attachments: attachments,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}
