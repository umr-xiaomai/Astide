import 'chat_message.dart';
import 'conversation.dart';

/// Live progress update emitted while importing a DeepSeek export archive.
class DeepSeekImportProgress {
  const DeepSeekImportProgress({
    required this.stage,
    required this.progress,
    this.detail = '',
  });

  final String stage;
  final double progress;
  final String detail;
}

/// Parsed DeepSeek user metadata from `user.json`.
class DeepSeekUserInfo {
  const DeepSeekUserInfo({
    this.userId = '',
    this.nickname = '',
    this.pictureUrl = '',
  });

  final String userId;
  final String nickname;
  final String pictureUrl;
}

/// Parsed session bundle ready for transactional SQLite persistence.
class ParsedDeepSeekSession {
  const ParsedDeepSeekSession({
    required this.conversation,
    required this.messages,
  });

  final Conversation conversation;
  final List<ChatMessage> messages;
}

/// Final summary returned after importing a DeepSeek export archive.
class DeepSeekImportResult {
  const DeepSeekImportResult({
    required this.importedConversations,
    required this.skippedDuplicates,
    required this.importedMessages,
    required this.importedImages,
    required this.userInfo,
  });

  final int importedConversations;
  final int skippedDuplicates;
  final int importedMessages;
  final int importedImages;
  final DeepSeekUserInfo userInfo;
}
