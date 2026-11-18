import 'dart:async';

import '../../domain/models/api_profile.dart';
import '../../domain/models/chat_message.dart';
import '../repositories/chat_repository.dart';
import 'openai_chat_service.dart';

/// Prepared conversation context combining a rolling silent summary with recent verbatim turns.
class CompactedContext {
  const CompactedContext({
    required this.summary,
    required this.recentMessages,
  });

  final String summary;
  final List<ChatMessage> recentMessages;
}

/// Silently compacts overflowing conversation history into a persistent SQLite summary
/// without altering visible chat bubbles or showing any UI interruption.
class ContextCompactionService {
  ContextCompactionService({
    required ChatRepository chatRepository,
    required OpenAiChatService openAiChatService,
  })  : _chatRepo = chatRepository,
        _openAi = openAiChatService;

  final ChatRepository _chatRepo;
  final OpenAiChatService _openAi;

  static const int triggerMessageCount = 28;
  static const int triggerCharCount = 12000;
  static const int keepRecentCount = 14;

  /// Silently checks if [conversationId] exceeds context thresholds, compacts older turns if needed,
  /// and returns the resulting summary + recent verbatim messages.
  Future<CompactedContext> prepareContext({
    required String conversationId,
    required ApiProfile profile,
  }) async {
    final conv = await _chatRepo.getConversation(conversationId);
    if (conv == null) {
      return const CompactedContext(summary: '', recentMessages: []);
    }

    final unsummarized = (await _chatRepo.listMessagesAfter(
      conversationId,
      afterCreatedAtMs: conv.contextSummarizedUntilMs,
    ))
        .where((m) => m.status != MessageStatus.error && m.status != MessageStatus.streaming)
        .toList();

    final totalChars = unsummarized.fold<int>(
      0,
      (sum, m) => sum + m.content.length,
    );

    if (unsummarized.length <= triggerMessageCount && totalChars <= triggerCharCount) {
      return CompactedContext(
        summary: conv.contextSummary,
        recentMessages: unsummarized,
      );
    }

    final safeKeep = unsummarized.length > keepRecentCount ? keepRecentCount : (unsummarized.length ~/ 2);
    final splitIndex = unsummarized.length - safeKeep;
    if (splitIndex <= 0) {
      return CompactedContext(
        summary: conv.contextSummary,
        recentMessages: unsummarized,
      );
    }

    final olderSlice = unsummarized.sublist(0, splitIndex);
    final recentSlice = unsummarized.sublist(splitIndex);

    try {
      final newSummary = await _summarizeSlice(
        profile: profile,
        existingSummary: conv.contextSummary,
        olderMessages: olderSlice,
      );
      if (newSummary.isNotEmpty) {
        final untilMs = olderSlice.last.createdAt.millisecondsSinceEpoch;
        await _chatRepo.saveContextSummary(
          conversationId: conversationId,
          summary: newSummary,
          summarizedUntilMs: untilMs,
        );
        return CompactedContext(
          summary: newSummary,
          recentMessages: recentSlice,
        );
      }
    } catch (_) {
      // Compaction is strictly silent and best-effort; never interrupt user chatting.
    }

    return CompactedContext(
      summary: conv.contextSummary,
      recentMessages: recentSlice,
    );
  }

  /// Appends [summary] cleanly onto [baseSystemPrompt] when non-empty.
  static String mergeSystemPrompt(String baseSystemPrompt, String summary) {
    final trimmedSummary = summary.trim();
    if (trimmedSummary.isEmpty) return baseSystemPrompt;
    final trimmedBase = baseSystemPrompt.trim();
    if (trimmedBase.isEmpty) {
      return '【长期对话记忆摘要】\n$trimmedSummary';
    }
    return '$trimmedBase\n\n【长期对话记忆摘要】\n$trimmedSummary';
  }

  Future<String> _summarizeSlice({
    required ApiProfile profile,
    required String existingSummary,
    required List<ChatMessage> olderMessages,
  }) async {
    final transcript = StringBuffer();
    if (existingSummary.trim().isNotEmpty) {
      transcript.writeln('【已有早期记忆摘要】');
      transcript.writeln(existingSummary.trim());
      transcript.writeln();
    }
    transcript.writeln('【待合并压缩的较早对话片段】');
    for (final msg in olderMessages) {
      final speaker = msg.isUser ? '对方' : '我方';
      final body = msg.content.trim().isNotEmpty
          ? msg.content.trim()
          : (msg.attachments.isNotEmpty ? '[附件: ${msg.attachments.first.fileName}]' : '');
      if (body.isEmpty) continue;
      final clipped = body.length > 500 ? '${body.substring(0, 500)}…' : body;
      transcript.writeln('$speaker：$clipped');
    }

    final compactProfile = profile.copyWith(supportsReasoning: false, streamEnabled: false);
    final now = DateTime.now();
    final outBuf = StringBuffer();

    await for (final delta in _openAi.streamChatCompletion(
      profile: compactProfile,
      systemPrompt:
          '你是一个静默的对话记忆压缩器。请将已有摘要与新出现的对话片段合并成一段紧凑、客观、信息密度高的第三人称记忆摘要（控制在 350 字以内）。'
          '重点保留：双方的称呼习惯、重要个人信息、约定、情绪事件、待办事项与核心话题脉络；直接输出摘要正文，不要加标题或解释。',
      history: [
        ChatMessage(
          id: 'compact_${now.millisecondsSinceEpoch}',
          conversationId: 'compact',
          role: MessageRole.user,
          content: transcript.toString(),
          createdAt: now,
        ),
      ],
      maxTokens: 500,
      forceNonStreaming: true,
    )) {
      outBuf.write(delta.contentDelta);
    }

    return outBuf.toString().trim();
  }
}
