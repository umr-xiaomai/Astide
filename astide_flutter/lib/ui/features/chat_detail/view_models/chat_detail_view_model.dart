import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../../app_scope.dart';
import '../../../../data/services/context_compaction_service.dart';
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
  })  : _app = appController,
        _conversation = conversation; // ignore: prefer_initializing_formals

  final AppController _app;
  final ImagePicker _imagePicker = ImagePicker();

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
  bool _disposed = false;

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
    _safeNotify();
    await _app.chatRepository.insertMessage(userMsg);
    unawaited(_app.reloadConversations());

    final profile = _app.activeApiProfile;
    if (hasImages && profile != null && !profile.supportsVision) {
      _statusNotice = '提示：当前模型（${profile.model}）未开启 Vision 视觉识别，图片已保存至本地但仅向模型发送文件名。可在 API 设置中开启 Vision。';
      _safeNotify();
    }

    await _generateAssistantReply();
  }

  Future<void> retryMessage(ChatMessage failedAssistantMsg) async {
    if (_isStreaming) return;
    _messages.removeWhere((m) => m.id == failedAssistantMsg.id);
    await _app.chatRepository.deleteMessage(failedAssistantMsg.id, _conversation.id);
    _safeNotify();
    await _generateAssistantReply();
  }

  Future<void> regenerateLastReply() async {
    if (_isStreaming || _messages.isEmpty) return;
    // Drop trailing assistant messages after the last user message.
    final lastUserIdx = _messages.lastIndexWhere((m) => m.isUser);
    if (lastUserIdx < 0) return;

    final toRemove = _messages.sublist(lastUserIdx + 1);
    for (final msg in toRemove) {
      await _app.chatRepository.deleteMessage(msg.id, _conversation.id);
    }
    _messages = _messages.sublist(0, lastUserIdx + 1);
    _safeNotify();
    await _generateAssistantReply();
  }

  Future<void> deleteMessage(ChatMessage msg) async {
    _messages = _messages.where((m) => m.id != msg.id).toList();
    _safeNotify();
    await _app.chatRepository.deleteMessage(msg.id, _conversation.id);
    unawaited(_app.reloadConversations());
  }

  Future<void> stopGenerating() async {
    _cancelToken?.cancel('stopped_by_user');
    await _streamSub?.cancel();
    _streamSub = null;
  }

  Future<void> _generateAssistantReply() async {
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

    // Silently compact overflowing history in the background before building prompt context.
    final compacted = await _app.contextCompactionService.prepareContext(
      conversationId: _conversation.id,
      profile: profile,
    );
    final momentsSnippet = _conversation.sourceType == ConversationSourceType.deepseekImport
        ? ''
        : await _app.momentsRepository.buildMomentsContextSnippet(
            characterId: _character?.id,
          );
    final historySnapshot = compacted.recentMessages.isNotEmpty
        ? compacted.recentMessages
        : _messages.where((m) => m.id != assistantId).toList();
    var systemPrompt = ContextCompactionService.mergeSystemPrompt(
      _buildSystemPrompt(),
      compacted.summary,
    );
    if (momentsSnippet.isNotEmpty) {
      systemPrompt = '$systemPrompt\n\n$momentsSnippet';
    }
    final modelOverride = _character?.modelOverride;
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    DateTime? thinkingStart;
    var thinkingSecs = 0.0;

    final completer = Completer<void>();

    void updateLiveBubble({
      MessageStatus status = MessageStatus.streaming,
      String errorMessage = '',
    }) {
      final allowSegment = _character != null ||
          _conversation.sourceType == ConversationSourceType.direct;
      final displayContent = allowSegment
          ? contentBuf.toString().replaceAll('|||', '\n')
          : contentBuf.toString();

      final idx = _messages.indexWhere((m) => m.id == assistantId);
      if (idx >= 0) {
        _messages[idx] = _messages[idx].copyWith(
          content: displayContent,
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
      history: historySnapshot,
      systemPrompt: systemPrompt,
      modelOverride: modelOverride,
      cancelToken: _cancelToken,
    );

    _streamSub = stream.listen(
      (delta) {
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
        _isStreaming = false;
        _streamSub = null;
        final errText = err.toString().replaceFirst('HttpException: ', '');
        updateLiveBubble(
          status: MessageStatus.error,
          errorMessage: errText,
        );
        final failedMsg = _messages.firstWhere(
          (m) => m.id == assistantId,
          orElse: () => streamingPlaceholder.copyWith(
            status: MessageStatus.error,
            errorMessage: errText,
          ),
        );
        await _app.chatRepository.insertMessage(failedMsg);
        unawaited(_app.reloadConversations());
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () async {
        _isStreaming = false;
        _streamSub = null;
        await _finalizeStreamedReply(
          assistantId: assistantId,
          rawContent: contentBuf.toString(),
          reasoning: reasoningBuf.toString(),
          thinkingSecs: thinkingSecs,
          createdAt: createdAt,
        );
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    await completer.future;
  }

  Future<void> _finalizeStreamedReply({
    required String assistantId,
    required String rawContent,
    required String reasoning,
    required double thinkingSecs,
    required DateTime createdAt,
  }) async {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty && reasoning.trim().isEmpty) {
      _messages.removeWhere((m) => m.id == assistantId);
      _safeNotify();
      return;
    }

    final allowMultiBubble = !trimmed.contains('```') &&
        trimmed.contains('|||') &&
        (_character != null || _conversation.sourceType == ConversationSourceType.direct);

    if (allowMultiBubble) {
      final segments = trimmed
          .split('|||')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (segments.length > 1) {
        _messages.removeWhere((m) => m.id == assistantId);
        _safeNotify();

        for (var i = 0; i < segments.length; i++) {
          final segMsg = ChatMessage(
            id: i == 0 ? assistantId : _app.newId(),
            conversationId: _conversation.id,
            role: MessageRole.assistant,
            content: segments[i],
            reasoningContent: i == 0 ? reasoning.trim() : '',
            thinkingSeconds: i == 0 ? thinkingSecs : 0,
            status: MessageStatus.sent,
            createdAt: createdAt.add(Duration(milliseconds: i * 15)),
          );
          _messages = [..._messages, segMsg];
          _safeNotify();
          await _app.chatRepository.insertMessage(segMsg);
          if (i < segments.length - 1 && !_disposed) {
            await Future<void>.delayed(const Duration(milliseconds: 220));
          }
        }
        unawaited(_app.reloadConversations());
        return;
      }
    }

    final finalMsg = ChatMessage(
      id: assistantId,
      conversationId: _conversation.id,
      role: MessageRole.assistant,
      content: trimmed.replaceAll('|||', '\n'),
      reasoningContent: reasoning.trim(),
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
    unawaited(_app.reloadConversations());
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
    _cancelToken?.cancel();
    _streamSub?.cancel();
    super.dispose();
  }
}
