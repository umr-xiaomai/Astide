import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/chat_attachment.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/conversation.dart';
import '../../domain/models/deepseek_import.dart';
import 'file_extractor_service.dart';
import 'media_storage_service.dart';

/// Parses and imports DeepSeek official export `.zip` archives (v3 format) from URLs or local files.
class DeepSeekImportService {
  DeepSeekImportService({
    Dio? dio,
    MediaStorageService? mediaStorage,
    FileExtractorService? fileExtractor,
    Uuid? uuid,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 5),
              ),
            ),
        _mediaStorage = mediaStorage ?? MediaStorageService(),
        _fileExtractor = fileExtractor ?? FileExtractorService(),
        _uuid = uuid ?? const Uuid();

  final Dio _dio;
  final MediaStorageService _mediaStorage;
  final FileExtractorService _fileExtractor;
  final Uuid _uuid;

  /// Downloads a DeepSeek export `.zip` from [url] and parses all sessions & image assets.
  Future<({DeepSeekUserInfo userInfo, List<ParsedDeepSeekSession> sessions})> parseFromUrl(
    String url, {
    void Function(DeepSeekImportProgress progress)? onProgress,
  }) async {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw const FormatException('请输入有效的 HTTP / HTTPS 导出链接');
    }

    final tempDir = await getTemporaryDirectory();
    final workId = _uuid.v4();
    final zipPath = p.join(tempDir.path, 'deepseek_import_$workId.zip');

    try {
      onProgress?.call(const DeepSeekImportProgress(
        stage: '正在下载 DeepSeek 导出压缩包...',
        progress: 0.05,
      ));

      await _dio.download(
        trimmed,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final ratio = (received / total).clamp(0.0, 1.0);
            onProgress?.call(DeepSeekImportProgress(
              stage: '正在下载 DeepSeek 导出压缩包...',
              progress: 0.05 + ratio * 0.35,
              detail: '${(received / 1024).toStringAsFixed(0)} KB / ${(total / 1024).toStringAsFixed(0)} KB',
            ));
          } else {
            onProgress?.call(DeepSeekImportProgress(
              stage: '正在下载 DeepSeek 导出压缩包...',
              progress: 0.2,
              detail: '已下载 ${(received / 1024).toStringAsFixed(0)} KB',
            ));
          }
        },
      );

      return await parseFromZipFile(zipPath, onProgress: onProgress);
    } finally {
      final zipFile = File(zipPath);
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
    }
  }

  /// Extracts and parses a local DeepSeek export `.zip` file.
  Future<({DeepSeekUserInfo userInfo, List<ParsedDeepSeekSession> sessions})> parseFromZipFile(
    String zipPath, {
    void Function(DeepSeekImportProgress progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final extractDir = Directory(p.join(tempDir.path, 'deepseek_extract_${_uuid.v4()}'));

    try {
      onProgress?.call(const DeepSeekImportProgress(
        stage: '正在解压导出文件...',
        progress: 0.45,
      ));

      await extractDir.create(recursive: true);
      await extractFileToDisk(zipPath, extractDir.path);

      return await parseFromExtractedDirectory(
        extractDir.path,
        onProgress: onProgress,
      );
    } finally {
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
    }
  }

  /// Parses an already-extracted DeepSeek export directory (exposed for deterministic unit tests).
  Future<({DeepSeekUserInfo userInfo, List<ParsedDeepSeekSession> sessions})>
      parseFromExtractedDirectory(
    String rootDirPath, {
    void Function(DeepSeekImportProgress progress)? onProgress,
  }) async {
    final rootDir = Directory(rootDirPath);
    final indexFile = File(p.join(rootDir.path, 'chat_session_index.json'));
    final sessionsDir = Directory(p.join(rootDir.path, 'chat_sessions'));
    if (!await sessionsDir.exists()) {
      throw const FormatException('压缩包格式不正确：缺少 chat_sessions 目录');
    }

    final userInfo = await _parseUserInfo(File(p.join(rootDir.path, 'user.json')));

    // Load index metadata first to preserve sort order & pinned flags.
    final indexList = <Map<String, dynamic>>[];
    if (await indexFile.exists()) {
      final decoded = jsonDecode(await indexFile.readAsString());
      if (decoded is List<dynamic>) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) indexList.add(item);
        }
      }
    }

    final sessionFiles = <File>[];
    if (indexList.isNotEmpty) {
      for (final entry in indexList) {
        final id = entry['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final file = File(p.join(sessionsDir.path, '$id.json'));
        if (await file.exists()) {
          sessionFiles.add(file);
        }
      }
    } else {
      await for (final entity in sessionsDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          sessionFiles.add(entity);
        }
      }
    }

    final parsedSessions = <ParsedDeepSeekSession>[];
    final total = sessionFiles.length;

    for (var i = 0; i < total; i++) {
      if (i % 10 == 0 || i == total - 1) {
        onProgress?.call(DeepSeekImportProgress(
          stage: '正在解析历史会话...',
          progress: 0.55 + (total == 0 ? 0.35 : (i + 1) / total * 0.35),
          detail: '${i + 1} / $total 个会话',
        ));
      }
      final file = sessionFiles[i];
      final rawJson = jsonDecode(await file.readAsString());
      if (rawJson is! Map<String, dynamic>) continue;
      final session = await _parseSingleSession(rawJson, rootDirPath);
      if (session != null) {
        parsedSessions.add(session);
      }
    }

    return (userInfo: userInfo, sessions: parsedSessions);
  }

  Future<DeepSeekUserInfo> _parseUserInfo(File userFile) async {
    if (!await userFile.exists()) return const DeepSeekUserInfo();
    try {
      final map = jsonDecode(await userFile.readAsString()) as Map<String, dynamic>;
      var nickname = '';
      var picture = '';
      final profiles = map['oauth_profiles'];
      if (profiles is List<dynamic> && profiles.isNotEmpty) {
        final first = profiles.first as Map<String, dynamic>;
        final rawProfileJson = first['profile_json']?.toString();
        if (rawProfileJson != null && rawProfileJson.isNotEmpty) {
          final parsed = jsonDecode(rawProfileJson) as Map<String, dynamic>;
          nickname = parsed['name']?.toString() ?? '';
          picture = parsed['picture']?.toString() ?? '';
        }
      }
      return DeepSeekUserInfo(
        userId: map['user_id']?.toString() ?? '',
        nickname: nickname,
        pictureUrl: picture,
      );
    } catch (_) {
      return const DeepSeekUserInfo();
    }
  }

  Future<ParsedDeepSeekSession?> _parseSingleSession(
    Map<String, dynamic> sessionMap,
    String rootDirPath,
  ) async {
    final externalId = sessionMap['id']?.toString() ?? _uuid.v4();
    final title = (sessionMap['title']?.toString() ?? '').trim();
    final isPinned = sessionMap['pinned'] == true;
    final insertedAt = _parseDate(sessionMap['inserted_at']?.toString()) ?? DateTime.now();
    final updatedAt = _parseDate(sessionMap['updated_at']?.toString()) ?? insertedAt;

    final rawMessages = (sessionMap['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (rawMessages.isEmpty) return null;

    final activeBranch = _resolveActiveThread(
      rawMessages,
      currentMessageId: sessionMap['current_message_id'],
    );
    if (activeBranch.isEmpty) return null;

    final conversationId = _uuid.v4();
    final messages = <ChatMessage>[];

    for (final rawMsg in activeBranch) {
      final roleStr = (rawMsg['role']?.toString() ?? 'ASSISTANT').toUpperCase();
      final role = roleStr == 'USER' ? MessageRole.user : MessageRole.assistant;
      final createdAt = _parseDate(rawMsg['inserted_at']?.toString()) ?? updatedAt;
      final messageId = _uuid.v4();

      final contentBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      final linksBuffer = StringBuffer();
      double thinkingSecs = 0;
      final attachments = <ChatAttachment>[];

      final fragments = (rawMsg['fragments'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();

      for (final frag in fragments) {
        final type = (frag['type']?.toString() ?? '').toUpperCase();
        switch (type) {
          case 'REQUEST':
          case 'RESPONSE':
          case 'TEMPLATE_RESPONSE':
            final text = frag['content']?.toString() ?? '';
            if (text.trim().isNotEmpty) {
              if (contentBuffer.isNotEmpty) contentBuffer.writeln('\n');
              contentBuffer.write(text.trimRight());
            }
          case 'THINK':
            final thought = frag['content']?.toString() ?? '';
            if (thought.trim().isNotEmpty) {
              if (reasoningBuffer.isNotEmpty) reasoningBuffer.writeln('\n');
              reasoningBuffer.write(thought.trimRight());
            }
            final elapsed = (frag['elapsed_secs'] as num?)?.toDouble();
            if (elapsed != null && elapsed > thinkingSecs) {
              thinkingSecs = elapsed;
            }
          case 'FILE':
            final files = (frag['files'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>();
            for (final f in files) {
              final att = await _parseExportFile(f, messageId: messageId, rootDirPath: rootDirPath);
              if (att != null) attachments.add(att);
            }
          case 'TOOL_SEARCH':
          case 'READ_LINK':
            final results = (frag['results'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>();
            for (final r in results.take(3)) {
              final rTitle = r['title']?.toString() ?? '';
              final rUrl = r['url']?.toString() ?? '';
              if (rUrl.isNotEmpty) {
                linksBuffer.writeln('- ${rTitle.isNotEmpty ? rTitle : rUrl} ($rUrl)');
              }
            }
          case 'CONTENT_RISK':
          case 'TOOL_OPEN':
          case 'TOOL_IMAGE_SEARCH':
          default:
            break;
        }
      }

      if (linksBuffer.isNotEmpty && contentBuffer.isNotEmpty) {
        contentBuffer.writeln('\n\n> 参考来源：\n$linksBuffer');
      }

      final finalContent = contentBuffer.toString().trim();
      final finalReasoning = reasoningBuffer.toString().trim();
      if (finalContent.isEmpty && finalReasoning.isEmpty && attachments.isEmpty) {
        continue;
      }

      messages.add(ChatMessage(
        id: messageId,
        conversationId: conversationId,
        role: role,
        content: finalContent,
        reasoningContent: finalReasoning,
        thinkingSeconds: thinkingSecs,
        status: MessageStatus.sent,
        attachments: attachments,
        createdAt: createdAt,
      ));
    }

    if (messages.isEmpty) return null;

    final lastMsg = messages.last;
    final conversation = Conversation(
      id: conversationId,
      externalId: externalId,
      title: title.isNotEmpty ? title : 'DeepSeek 对话',
      sourceType: ConversationSourceType.deepseekImport,
      avatarColor: 0xFF4D6BFE,
      isPinned: isPinned,
      lastMessagePreview: lastMsg.previewText,
      lastMessageAt: lastMsg.createdAt,
      createdAt: insertedAt,
      updatedAt: updatedAt,
    );

    return ParsedDeepSeekSession(
      conversation: conversation,
      messages: messages,
    );
  }

  /// Reconstructs the active linear conversation path from `parent_id` + `current_message_id`.
  List<Map<String, dynamic>> _resolveActiveThread(
    List<Map<String, dynamic>> rawMessages, {
    dynamic currentMessageId,
  }) {
    final byId = <dynamic, Map<String, dynamic>>{};
    for (final m in rawMessages) {
      if (m['id'] != null) {
        byId[m['id']] = m;
      }
    }

    if (currentMessageId != null && byId.containsKey(currentMessageId)) {
      final reversed = <Map<String, dynamic>>[];
      final visited = <dynamic>{};
      dynamic cursor = currentMessageId;
      while (cursor != null && byId.containsKey(cursor) && !visited.contains(cursor)) {
        visited.add(cursor);
        final msg = byId[cursor]!;
        reversed.add(msg);
        cursor = msg['parent_id'];
      }
      return reversed.reversed.toList();
    }

    return rawMessages;
  }

  Future<ChatAttachment?> _parseExportFile(
    Map<String, dynamic> fileMeta, {
    required String messageId,
    required String rootDirPath,
  }) async {
    final fileName = fileMeta['file_name']?.toString() ?? '未命名文件';
    final fileSize = (fileMeta['file_size'] as num?)?.toInt() ?? 0;
    final isImage = fileMeta['is_image'] == true;
    final width = (fileMeta['width'] as num?)?.toInt();
    final height = (fileMeta['height'] as num?)?.toInt();
    final exportPath = fileMeta['export_path']?.toString();

    String? savedLocalPath;
    if (exportPath != null && exportPath.isNotEmpty) {
      // DeepSeek uses forward-slash paths relative to archive root.
      final normalizedRel = exportPath.replaceAll('/', p.separator);
      final sourceFile = File(p.join(rootDirPath, normalizedRel));
      if (await sourceFile.exists()) {
        savedLocalPath = await _mediaStorage.saveFileCopy(
          sourceFile.path,
          category: isImage ? 'images' : 'files',
        );
      }
    }

    return ChatAttachment(
      id: _uuid.v4(),
      messageId: messageId,
      type: isImage && savedLocalPath != null ? AttachmentType.image : AttachmentType.file,
      fileName: fileName,
      filePath: savedLocalPath,
      mimeType: _fileExtractor.guessMimeType(fileName),
      fileSize: fileSize,
      extractedText: savedLocalPath == null ? '[DeepSeek 历史文件未打包原始二进制，仅保留文件名与大小记录]' : '',
      width: width,
      height: height,
    );
  }

  DateTime? _parseDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso)?.toLocal();
  }
}
