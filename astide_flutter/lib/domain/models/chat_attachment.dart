/// Attachment type inside a chat message.
enum AttachmentType {
  image('image'),
  file('file');

  const AttachmentType(this.value);
  final String value;

  static AttachmentType fromValue(String? value) {
    return AttachmentType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AttachmentType.file,
    );
  }
}

/// Image or document attachment associated with a [ChatMessage].
class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.messageId,
    required this.type,
    required this.fileName,
    this.filePath,
    this.mimeType = 'application/octet-stream',
    this.fileSize = 0,
    this.extractedText = '',
    this.width,
    this.height,
  });

  final String id;
  final String messageId;
  final AttachmentType type;
  final String fileName;
  final String? filePath;
  final String mimeType;
  final int fileSize;
  final String extractedText;
  final int? width;
  final int? height;

  bool get isImage => type == AttachmentType.image;

  String get formattedSize {
    if (fileSize <= 0) return '未知大小';
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get fileExtension {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) return 'FILE';
    return fileName.substring(dotIndex + 1).toUpperCase();
  }

  ChatAttachment copyWith({
    String? id,
    String? messageId,
    AttachmentType? type,
    String? fileName,
    String? Function()? filePath,
    String? mimeType,
    int? fileSize,
    String? extractedText,
    int? width,
    int? height,
  }) {
    return ChatAttachment(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      type: type ?? this.type,
      fileName: fileName ?? this.fileName,
      filePath: filePath != null ? filePath() : this.filePath,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      extractedText: extractedText ?? this.extractedText,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'message_id': messageId,
      'type': type.value,
      'file_name': fileName,
      'file_path': filePath,
      'mime_type': mimeType,
      'file_size': fileSize,
      'extracted_text': extractedText,
      'width': width,
      'height': height,
    };
  }

  factory ChatAttachment.fromMap(Map<String, Object?> map) {
    return ChatAttachment(
      id: map['id'] as String,
      messageId: map['message_id'] as String,
      type: AttachmentType.fromValue(map['type'] as String?),
      fileName: map['file_name'] as String,
      filePath: map['file_path'] as String?,
      mimeType: map['mime_type'] as String? ?? 'application/octet-stream',
      fileSize: map['file_size'] as int? ?? 0,
      extractedText: map['extracted_text'] as String? ?? '',
      width: map['width'] as int?,
      height: map['height'] as int?,
    );
  }
}
