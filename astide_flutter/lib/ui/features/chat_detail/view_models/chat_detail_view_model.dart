import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../../app_scope.dart';
import '../../../../data/services/autonomous_service.dart';
import '../../../../data/services/context_compaction_service.dart';
import '../../../../data/services/multi_reply_guard.dart';
import '../../../../domain/models/api_profile.dart';
import '../../../../domain/models/character_profile.dart';
import '../../../../domain/models/chat_attachment.dart';
import '../../../../domain/models/chat_message.dart';
import '../../../../domain/models/conversation.dart';

/// Staged image or document attachment waiting in the chat composer.
class PendingAttachment {
  const PendingAttachment({
    required this.id,
    required this.type,
    required this.fileName,
    required this.filePath,
    required this.mimeType,
    required this.fileSize,
    this.extractedText = '',
  });

  final String id;
  final AttachmentType type;
  final String fileName;
  final String filePath;
  final String mimeType;
  final int fileSize;
  final String extractedText;

  bool get isImage => type == AttachmentType.image;
}

/// Manages messages, streaming AI replies, attachments, and RP persona context for a chat room.
class ChatDetailViewModel extends ChangeNotifier {
  ChatDetailViewModel({
    required AppController appController,
    required Conversation conversation,
    Random? random,
    this.followUpDelayOverride,
  })  : _app = appController,
        _conversation = conversation, // ignore: prefer_initializing_formals
        _random = random ?? Random();

  final AppController _app;
  final ImagePicker _imagePicker = ImagePicker();
  final Random _random;
  final Duration? followUpDelayOverride;

  Conversation _conversation;
  Conversation get conversation => _conversation;

  CharacterProfile? _character;
  CharacterProfile? get character => _character;

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  final List<PendingAttachment> _pendingAttachments = [];
  List<PendingAttachment> get pendingAttachments => List.unmodifiable(_pendingAttachments);

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _isLoadingOlder = false;
  bool get isLoadingOlder => _isLoadingOlder;

  bool _hasMoreHistory = false;
  bool get hasMoreHistory => _hasMoreHistory;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  String? _statusNotice;
  String? get statusNotice => _statusNotice;

  CancelToken? _cancelToken;
  StreamSubscription<dynamic>? _streamSub;
  Completer<ChatMessage?>? _activePrimaryCompleter;
  int _generationToken = 0;
  bool _disposed = false;
  bool _pokeReplyInFlight = false;
  DateTime? _lastPokeReplyAt;

  static const int _pageSize = 40;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    final freshConv = await _app.chatRepository.getConversation(_conversation.id);
    if (freshConv != null) {
      _conversation = freshConv;
      if (freshConv.unreadCount > 0) {
        final cleared = freshConv.copyWith(unreadCount: 0);
        await _app.chatRepository.updateConversation(cleared);
        _conversation = cleared;
        unawaited(_app.reloadConversations());
      }
    }

    if (_conversation.characterId != null) {
      _character = await _app.characterRepository.getCharacter(_conversation.characterId!);
    } else {
      _character = null;
    }

    final page = await _app.chatRepository.listMessagesPage(
      _conversation.id,
      limit: _pageSize,
    );
    _messages = page.messages;
    _hasMoreHistory = page.hasMore;
    _isLoading = false;
    _safeNotify();
  }

  Future<void> loadOlderMessages() async {
    if (_isLoadingOlder || !_hasMoreHistory || _messages.isEmpty) return;
    _isLoadingOlder = true;
    _safeNotify();

    final oldest = _messages.first;
    final page = await _app.chatRepository.listMessagesPage(
      _conversation.id,
      limit: _pageSize,
      beforeMessage: oldest,
    );

    if (page.messages.isNotEmpty) {
      _messages = [...page.messages, ..._messages];
    }
    _hasMoreHistory = page.hasMore;
    _isLoadingOlder = false;
    _safeNotify();
  }

  Future<void> reloadMeta() async {
    final freshConv = await _app.chatRepository.getConversation(_conversation.id);
    if (freshConv != null) _conversation = freshConv;
    if (_conversation.characterId != null) {
      _character = await _app.characterRepository.getCharacter(_conversation.characterId!);
    } else {
      _character = null;
    }
    final page = await _app.chatRepository.listMessagesPage(
      _conversation.id,
      limit: _messages.length > _pageSize ? _messages.length : _pageSize,
    );
    _messages = page.messages;
    _hasMoreHistory = page.hasMore;
    _safeNotify();
  }

  void dismissStatusNotice() {
    _statusNotice = null;
    _safeNotify();
  }

  Future<void> pickFromGallery() async {
    final picked = await _imagePicker.pickMultiImage(imageQuality: 90);
    if (picked.isEmpty) return;
    for (final xFile in picked) {
      await _stageImageFile(xFile.path, xFile.name);
    }
    _safeNotify();
  }

  Future<void> pickFromCamera() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null) return;
    await _stageImageFile(picked.path, picked.name);
    _safeNotify();
  }

  Future<void> _stageImageFile(String sourcePath, String originalName) async {
    final savedPath = await _app.mediaStorage.saveFileCopy(sourcePath, category: 'images');
    final size = await File(savedPath).length();
    final name = originalName.isNotEmpty ? originalName : p.basename(sourcePath);
    _pendingAttachments.add(PendingAttachment(
      id: _app.newId(),
      type: AttachmentType.image,
      fileName: name,
      filePath: savedPath,
      mimeType: _app.fileExtractor.guessMimeType(name),
      fileSize: size,
    ));
  }

  Future<void> pickDocuments() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    for (final file in files) {
      final path = file.path;
      if (path == null) continue;
      final savedPath = await _app.mediaStorage.saveFileCopy(path, category: 'files');
      final info = await _app.fileExtractor.extractFromFile(savedPath);
      _pendingAttachments.add(PendingAttachment(
        id: _app.newId(),
        type: AttachmentType.file,
        fileName: file.name,
        filePath: savedPath,
        mimeType: info.mimeType,
        fileSize: info.fileSize,
        extractedText: info.extractedText,
      ));
    }
    _safeNotify();
  }

  void removePendingAttachment(String id) {
    _pendingAttachments.removeWhere((a) => a.id == id);
    _safeNotify();
  }

  Future<void> sendMessage(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    if (_isStreaming) return;

    // Lock synchronously before any await so rapid double-taps cannot spawn duplicate replies.
    final token = ++_generationToken;
    _isStreaming = true;

    final userMsgId = _app.newId();
    final now = DateTime.now();
    final attachments = _pendingAttachments
        .map((pending) => ChatAttachment(
              id: pending.id,
              messageId: userMsgId,
              type: pending.type,
              fileName: pending.fileName,
              filePath: pending.filePath,
              mimeType: pending.mimeType,
              fileSize: pending.fileSize,
              extractedText: pending.extractedText,
            ))
        .toList();

    final hasImages = attachments.any((a) => a.isImage);
    _pendingAttachments.clear();

    final userMsg = ChatMessage(
      id: userMsgId,
      conversationId: _conversation.id,
      role: MessageRole.user,
      content: text,
      status: MessageStatus.sent,
      attachments: attachments,
      createdAt: now,
    );

    _messages = [..._messages, userMsg];
    final profile = _app.activeApiProfile;
    if (hasImages && profile != null && !profile.supportsVision) {
      _statusNotice = '提示：当前模型（${profile.model}）未开启 Vision 视觉识别，图片已保存至本地但仅向模型发送文件名。可在 API 设置中开启 Vision。';
    }
    _safeNotify();

    try {
      await _app.chatRepository.insertMessage(userMsg);
      unawaited(_app.reloadConversations());
      if (!_isActiveToken(token)) return;
      await _generateAssistantReply(token);
    } finally {
      _finishGenerationIfActive(token);
    }
  }

  Future<void> retryMessage(ChatMessage failedAssistantMsg) async {
    if (_isStreaming) return;
    final token = ++_generationToken;
    _isStreaming = true;
    _messages = _messages.where((m) => m.id != failedAssistantMsg.id).toList();
    _safeNotify();
    try {
      await _app.chatRepository.deleteMessage(failedAssistantMsg.id, _conversation.id);
      if (!_isActiveToken(token)) return;
      await _generateAssistantReply(token);
    } finally {
      _finishGenerationIfActive(token);
    }
  }

  Future<void> regenerateLastReply() async {
    if (_isStreaming || _messages.isEmpty) return;
    // Drop trailing assistant messages after the last user message.
    final lastUserIdx = _messages.lastIndexWhere((m) => m.isUser);
    if (lastUserIdx < 0) return;

    final token = ++_generationToken;
    _isStreaming = true;
    final toRemove = _messages.sublist(lastUserIdx + 1);
    _messages = _messages.sublist(0, lastUserIdx + 1);
    _safeNotify();

    try {
      for (final msg in toRemove) {
        await _app.chatRepository.deleteMessage(msg.id, _conversation.id);
      }
      if (!_isActiveToken(token)) return;
      await _generateAssistantReply(token);
    } finally {
      _finishGenerationIfActive(token);
    }
  }

  Future<void> deleteMessage(ChatMessage msg) async {
    _messages = _messages.where((m) => m.id != msg.id).toList();
    _safeNotify();
    await _app.chatRepository.deleteMessage(msg.id, _conversation.id);
    unawaited(_app.reloadConversations());
  }

  Future<void> stopGenerating() async {
    _generationToken++;
    _cancelToken?.cancel('stopped_by_user');
    await _streamSub?.cancel();
    _streamSub = null;
    if (_activePrimaryCompleter != null && !_activePrimaryCompleter!.isCompleted) {
      _activePrimaryCompleter!.complete(null);
    }
    _activePrimaryCompleter = null;
    _messages = _messages
        .where((m) => !(m.status == MessageStatus.streaming && m.content.trim().isEmpty))
        .toList();
    if (_isStreaming) {
      _isStreaming = false;
      _safeNotify();
    }
  }

  bool _isActiveToken(int token) {
    return !_disposed && token == _generationToken && !(_cancelToken?.isCancelled ?? false);
  }

  void _finishGenerationIfActive(int token) {
    if (token == _generationToken) {
      _isStreaming = false;
      _streamSub = null;
      _activePrimaryCompleter = null;
      _safeNotify();
    }
  }

  /// Sends a WeChat-style "拍一拍" system notice and probabilistically triggers an AI response.
  Future<bool> pokeOpponent() async {
    final targetName = _character?.displayName ?? _conversation.title;
    final now = DateTime.now();
    final pokeNotice = ChatMessage(
      id: _app.newId(),
      conversationId: _conversation.id,
      role: MessageRole.system,
      content: '你拍了拍“$targetName”',
      status: MessageStatus.sent,
      createdAt: now,
    );

    _messages = [..._messages, pokeNotice];
    _safeNotify();
    await _app.chatRepository.insertMessage(pokeNotice);
    unawaited(_app.reloadConversations());

    if (_disposed || _isStreaming || _pokeReplyInFlight) return false;
    if (_conversation.sourceType == ConversationSourceType.deepseekImport) return false;

    final profile = _app.activeApiProfile;
    if (profile == null || !profile.isConfigured) return false;

    if (_lastPokeReplyAt != null && now.difference(_lastPokeReplyAt!).inSeconds < 12) {
      return false;
    }

    final prob = _app.settings.pokeReplyProbability.clamp(0.0, 1.0);
    if (prob <= 0 || _random.nextDouble() >= prob) {
      return false;
    }

    _pokeReplyInFlight = true;
    _lastPokeReplyAt = now;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 520));
      if (_disposed || _isStreaming) return false;
      return await _generatePokeReaction(profile: profile, targetName: targetName);
    } finally {
      _pokeReplyInFlight = false;
    }
  }

  Future<bool> _generatePokeReaction({
    required ApiProfile profile,
    required String targetName,
  }) async {
    final now = DateTime.now();
    final ctx = await _prepareLlmContext(profile, excludeMessageId: '');
    if (_disposed || _isStreaming) return false;

    final userNick = _app.settings.userNickname.trim().isEmpty
        ? '对方'
        : _app.settings.userNickname.trim();
    final fastProfile = profile.copyWith(supportsReasoning: false, streamEnabled: false);
    final ephemeralHistory = <ChatMessage>[
      ...ctx.history,
      ChatMessage(
        id: 'poke_event_${now.millisecondsSinceEpoch}',
        conversationId: _conversation.id,
        role: MessageRole.user,
        content: '（微信互动事件：$userNick 在聊天窗口轻轻双击你的头像，拍了拍你。'
            '请完全按你当前人设与聊天氛围自然回应一句，例如调侃、撒娇、好奇或关心，只发一条简短自然的话；'
            '如果你想顺手回拍对方，可在最开头加上 [POKE_BACK]。不要提及系统事件或AI。）',
        createdAt: now,
      ),
    ];

    try {
      final rawBuf = StringBuffer();
      await for (final delta in _app.openAiChatService.streamChatCompletion(
        profile: fastProfile,
        history: ephemeralHistory,
        systemPrompt: ctx.systemPrompt,
        modelOverride: _character?.modelOverride,
        maxTokens: 140,
        forceNonStreaming: true,
      )) {
        rawBuf.write(delta.contentDelta);
      }

      if (_disposed || _isStreaming) return false;
      final parsed = AutonomousService.parseSingleReply(rawBuf.toString());
      if (parsed.isDoneOrSkip && !parsed.pokedBack) return false;

      var replied = false;
      if (parsed.pokedBack) {
        final backNotice = ChatMessage(
          id: _app.newId(),
          conversationId: _conversation.id,
          role: MessageRole.system,
          content: '“$targetName” 拍了拍你',
          status: MessageStatus.sent,
          createdAt: DateTime.now(),
        );
        _messages = [..._messages, backNotice];
        _safeNotify();
        await _app.chatRepository.insertMessage(backNotice);
        replied = true;
      }

      if (parsed.text.isNotEmpty) {
        final replyMsg = ChatMessage(
          id: _app.newId(),
          conversationId: _conversation.id,
          role: MessageRole.assistant,
          content: parsed.text,
          status: MessageStatus.sent,
          createdAt: DateTime.now().add(const Duration(milliseconds: 20)),
        );
        _messages = [..._messages, replyMsg];
        _safeNotify();
        await _app.chatRepository.insertMessage(replyMsg);
        replied = true;
      }

      if (replied) {
        unawaited(_app.reloadConversations());
      }
      return replied;
    } catch (_) {
      return false;
    }
  }

  Future<({List<ChatMessage> history, String systemPrompt})> _prepareLlmContext(
    ApiProfile profile, {
    required String excludeMessageId,
  }) async {
    final compacted = await _app.contextCompactionService.prepareContext(
      conversationId: _conversation.id,
      profile: profile,
    );
    final momentsSnippet = _conversation.sourceType == ConversationSourceType.deepseekImport
        ? ''
        : await _app.momentsRepository.buildMomentsContextSnippet(
            characterId: _character?.id,
          );
    final baseHistory = compacted.recentMessages.isNotEmpty
        ? compacted.recentMessages
        : _messages.where((m) => m.id != excludeMessageId).toList();
    var systemPrompt = ContextCompactionService.mergeSystemPrompt(
      _buildSystemPrompt(),
      compacted.summary,
    );
    if (momentsSnippet.isNotEmpty) {
      systemPrompt = '$systemPrompt\n\n$momentsSnippet';
    }
    return (history: baseHistory, systemPrompt: systemPrompt);
  }

  Future<void> _generateAssistantReply(int token) async {
    final profile = _app.activeApiProfile;
    final assistantId = _app.newId();
    final createdAt = DateTime.now();

    if (profile == null || !profile.isConfigured) {
      final noticeMsg = ChatMessage(
        id: assistantId,
        conversationId: _conversation.id,
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.error,
        errorMessage: '尚未配置有效的 API 地址和 Key，请前往「我 -> API 与模型设置」完成配置后点击重试。',
        createdAt: createdAt,
      );
      _messages = [..._messages, noticeMsg];
      _safeNotify();
      await _app.chatRepository.insertMessage(noticeMsg);
      unawaited(_app.reloadConversations());
      return;
    }

    final streamingPlaceholder = ChatMessage(
      id: assistantId,
      conversationId: _conversation.id,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      createdAt: createdAt,
    );

    _messages = [..._messages, streamingPlaceholder];
    _isStreaming = true;
    _cancelToken = CancelToken();
    _safeNotify();

    final ctx = await _prepareLlmContext(profile, excludeMessageId: assistantId);
    if (!_isActiveToken(token)) {
      _messages = _messages.where((m) => m.id != assistantId).toList();
      _safeNotify();
      return;
    }

    final firstMsg = await _streamPrimaryReply(
      token: token,
      assistantId: assistantId,
      createdAt: createdAt,
      profile: profile,
      history: ctx.history,
      systemPrompt: ctx.systemPrompt,
      placeholder: streamingPlaceholder,
    );

    // For conversational personas with segmented replies enabled, issue natural sequential
    // buffered follow-up requests guarded against duplicates, echoes, and meta-chatter.
    final allowMultiBubble = (_character?.segmentedReply ?? true) &&
        _conversation.sourceType != ConversationSourceType.deepseekImport;
    if (allowMultiBubble &&
        firstMsg != null &&
        firstMsg.status == MessageStatus.sent &&
        firstMsg.content.isNotEmpty &&
        _isActiveToken(token)) {
      await _runSequentialContinuationRequests(
        token: token,
        profile: profile,
        initialHistory: [...ctx.history, firstMsg],
        systemPrompt: ctx.systemPrompt,
        firstBubbleText: firstMsg.content,
        baseTime: firstMsg.createdAt,
        segmentedReplyEnabled: allowMultiBubble,
      );
    }

    unawaited(_app.reloadConversations());
  }

  Future<ChatMessage?> _streamPrimaryReply({
    required int token,
    required String assistantId,
    required DateTime createdAt,
    required ApiProfile profile,
    required List<ChatMessage> history,
    required String systemPrompt,
    required ChatMessage placeholder,
  }) async {
    final modelOverride = _character?.modelOverride;
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    DateTime? thinkingStart;
    var thinkingSecs = 0.0;
    final completer = Completer<ChatMessage?>();
    _activePrimaryCompleter = completer;

    void updateLiveBubble({
      MessageStatus status = MessageStatus.streaming,
      String errorMessage = '',
    }) {
      if (!_isActiveToken(token) && status == MessageStatus.streaming) return;
      final idx = _messages.indexWhere((m) => m.id == assistantId);
      if (idx >= 0) {
        _messages[idx] = _messages[idx].copyWith(
          content: contentBuf.toString(),
          reasoningContent: reasoningBuf.toString(),
          thinkingSeconds: thinkingSecs,
          status: status,
          errorMessage: errorMessage,
        );
        _safeNotify();
      }
    }

    final stream = _app.openAiChatService.streamChatCompletion(
      profile: profile,
      history: history,
      systemPrompt: systemPrompt,
      modelOverride: modelOverride,
      cancelToken: _cancelToken,
    );

    _streamSub = stream.listen(
      (delta) {
        if (!_isActiveToken(token)) return;
        if (delta.reasoningDelta.isNotEmpty) {
          thinkingStart ??= DateTime.now();
          reasoningBuf.write(delta.reasoningDelta);
          thinkingSecs = DateTime.now().difference(thinkingStart!).inMilliseconds / 1000.0;
        }
        if (delta.contentDelta.isNotEmpty) {
          contentBuf.write(delta.contentDelta);
        }
        if (!delta.isDone) {
          updateLiveBubble();
        }
      },
      onError: (Object err) async {
        _streamSub = null;
        if (!_isActiveToken(token)) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }
        final errText = err.toString().replaceFirst('HttpException: ', '');
        updateLiveBubble(
          status: MessageStatus.error,
          errorMessage: errText,
        );
        final failedMsg = _messages.firstWhere(
          (m) => m.id == assistantId,
          orElse: () => placeholder.copyWith(
            status: MessageStatus.error,
            errorMessage: errText,
          ),
        );
        await _app.chatRepository.insertMessage(failedMsg);
        if (!completer.isCompleted) completer.complete(null);
      },
      onDone: () async {
        _streamSub = null;
        if (!_isActiveToken(token)) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }
        final trimmed = contentBuf.toString().trim();
        final trimmedReasoning = reasoningBuf.toString().trim();
        if (trimmed.isEmpty && trimmedReasoning.isEmpty) {
          _messages = _messages.where((m) => m.id != assistantId).toList();
          _safeNotify();
          if (!completer.isCompleted) completer.complete(null);
          return;
        }

        final finalMsg = ChatMessage(
          id: assistantId,
          conversationId: _conversation.id,
          role: MessageRole.assistant,
          content: trimmed,
          reasoningContent: trimmedReasoning,
          thinkingSeconds: thinkingSecs,
          status: MessageStatus.sent,
          createdAt: createdAt,
        );
        final idx = _messages.indexWhere((m) => m.id == assistantId);
        if (idx >= 0) {
          _messages[idx] = finalMsg;
        } else {
          _messages = [..._messages, finalMsg];
        }
        _safeNotify();
        await _app.chatRepository.insertMessage(finalMsg);
        if (!completer.isCompleted) completer.complete(finalMsg);
      },
      cancelOnError: true,
    );

    final result = await completer.future;
    if (identical(_activePrimaryCompleter, completer)) {
      _activePrimaryCompleter = null;
    }
    return result;
  }

  Future<void> _runSequentialContinuationRequests({
    required int token,
    required ApiProfile profile,
    required List<ChatMessage> initialHistory,
    required String systemPrompt,
    required String firstBubbleText,
    required DateTime baseTime,
    required bool segmentedReplyEnabled,
  }) async {
    final runningHistory = List<ChatMessage>.from(initialHistory);
    final sentBubbles = <String>[firstBubbleText];
    final lastUserText = initialHistory
        .lastWhere(
          (m) => m.isUser,
          orElse: () => ChatMessage(
            id: '',
            conversationId: _conversation.id,
            role: MessageRole.user,
            content: '',
            createdAt: baseTime,
          ),
        )
        .content;
    final followUpProfile = profile.copyWith(supportsReasoning: false, streamEnabled: false);

    for (var extra = 1; extra <= MultiReplyGuard.maxExtraBubbles; extra++) {
      if (!_isActiveToken(token)) break;

      final shouldContinue = MultiReplyGuard.shouldRequestFollowUp(
        segmentedReplyEnabled: segmentedReplyEnabled,
        sentBubbles: sentBubbles,
        extraIndex: extra,
        random: _random,
      );
      if (!shouldContinue) break;

      final pause = followUpDelayOverride ??
          Duration(milliseconds: 380 + _random.nextInt(320));
      if (pause > Duration.zero) {
        await Future<void>.delayed(pause);
      }
      if (!_isActiveToken(token)) break;

      final turnTime = baseTime.add(Duration(milliseconds: extra * 15));
      final followUpSystemPrompt = MultiReplyGuard.buildFollowUpSystemPrompt(
        baseSystemPrompt: systemPrompt,
        sentBubbles: sentBubbles,
        nextBubbleIndex: sentBubbles.length + 1,
      );
      final requestHistory = <ChatMessage>[
        ...runningHistory,
        ChatMessage(
          id: 'cont_${turnTime.millisecondsSinceEpoch}_$extra',
          conversationId: _conversation.id,
          role: MessageRole.user,
          content: MultiReplyGuard.buildFollowUpUserCue(sentBubbles: sentBubbles),
          createdAt: turnTime,
        ),
      ];

      final rawReply = await _requestBufferedFollowUp(
        token: token,
        profile: followUpProfile,
        history: requestHistory,
        systemPrompt: followUpSystemPrompt,
      );
      if (!_isActiveToken(token) || rawReply == null) break;

      final evaluation = MultiReplyGuard.evaluateFollowUp(
        rawReply: rawReply,
        sentBubblesInTurn: sentBubbles,
        lastUserText: lastUserText,
      );
      if (!evaluation.accepted || evaluation.text.isEmpty) break;

      final nowTime = DateTime.now();
      final lastTime = runningHistory.last.createdAt;
      final msgTime = nowTime.isAfter(lastTime)
          ? nowTime
          : lastTime.add(const Duration(milliseconds: 10));
      final nextMsg = ChatMessage(
        id: _app.newId(),
        conversationId: _conversation.id,
        role: MessageRole.assistant,
        content: evaluation.text,
        status: MessageStatus.sent,
        createdAt: msgTime,
      );
      _messages = [..._messages, nextMsg];
      _safeNotify();
      await _app.chatRepository.insertMessage(nextMsg);
      sentBubbles.add(evaluation.text);
      runningHistory.add(nextMsg);

      if (evaluation.stopChain) break;
    }
  }

  Future<String?> _requestBufferedFollowUp({
    required int token,
    required ApiProfile profile,
    required List<ChatMessage> history,
    required String systemPrompt,
  }) async {
    try {
      final buf = StringBuffer();
      await for (final delta in _app.openAiChatService.streamChatCompletion(
        profile: profile,
        history: history,
        systemPrompt: systemPrompt,
        modelOverride: _character?.modelOverride,
        maxTokens: 96,
        forceNonStreaming: true,
        cancelToken: _cancelToken,
      )) {
        if (!_isActiveToken(token)) return null;
        if (delta.contentDelta.isNotEmpty) {
          buf.write(delta.contentDelta);
        }
      }
      if (!_isActiveToken(token)) return null;
      return buf.toString();
    } catch (_) {
      return null;
    }
  }

  String _buildSystemPrompt() {
    final settings = _app.settings;
    if (_character != null) {
      return _character!.buildEffectiveSystemPrompt(
        userNickname: settings.userNickname,
        userPersona: settings.userPersona,
      );
    }
    if (_conversation.sourceType == ConversationSourceType.deepseekImport) {
      return '请延续上方对话历史上下文，自然、清晰地回答用户接下来的问题。';
    }
    final buffer = StringBuffer(settings.defaultAssistantPrompt);
    if (settings.userNickname.trim().isNotEmpty && settings.userNickname != '我') {
      buffer.write('\n对方的微信昵称是「${settings.userNickname.trim()}」。');
    }
    if (settings.userPersona.trim().isNotEmpty) {
      buffer.write('\n关于对方：${settings.userPersona.trim()}');
    }
    return buffer.toString();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generationToken++;
    _cancelToken?.cancel();
    _streamSub?.cancel();
    if (_activePrimaryCompleter != null && !_activePrimaryCompleter!.isCompleted) {
      _activePrimaryCompleter!.complete(null);
    }
    _activePrimaryCompleter = null;
    super.dispose();
  }
}
