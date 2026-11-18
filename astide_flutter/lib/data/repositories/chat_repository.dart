import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/character_profile.dart';
import '../../domain/models/chat_attachment.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/conversation.dart';
import '../../domain/models/deepseek_import.dart';
import '../services/database_service.dart';

/// Aggregated search hits across conversations, characters, and message contents.
class GlobalSearchResults {
  const GlobalSearchResults({
    this.conversations = const [],
    this.characters = const [],
    this.messageHits = const [],
  });

  final List<Conversation> conversations;
  final List<CharacterProfile> characters;
  final List<({Conversation conversation, ChatMessage message})> messageHits;

  bool get isEmpty => conversations.isEmpty && characters.isEmpty && messageHits.isEmpty;
}

/// Summary statistics of local SQLite storage.
class StorageStats {
  const StorageStats({
    required this.conversationCount,
    required this.importedConversationCount,
    required this.characterCount,
    required this.messageCount,
    required this.attachmentCount,
  });

  final int conversationCount;
  final int importedConversationCount;
  final int characterCount;
  final int messageCount;
  final int attachmentCount;
}

/// Complete snapshot of one conversation, optional linked character, and hydrated messages.
class ConversationExportBundle {
  const ConversationExportBundle({
    required this.conversation,
    this.character,
    required this.messages,
  });

  final Conversation conversation;
  final CharacterProfile? character;
  final List<ChatMessage> messages;
}

/// Persists conversations, messages, and attachments in local SQLite.
class ChatRepository {
  ChatRepository({
    required DatabaseService databaseService,
    Uuid? uuid,
  })  : _dbService = databaseService,
        _uuid = uuid ?? const Uuid();

  final DatabaseService _dbService;
  final Uuid _uuid;

  static const String coreAstideConversationId = 'astide_core_chat';
  static const String coreAstideAvatarPath = 'asset:assets/images/astide_avatar.jpg';

  /// Ensures the forced-pinned core 星汐 (Astide) conversation always exists.
  Future<void> ensureInitialConversation() async {
    final db = await _dbService.database;
    final existingDirect = await db.query(
      'conversations',
      where: 'source_type = ?',
      whereArgs: [ConversationSourceType.direct.value],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (existingDirect.isNotEmpty) {
      // Ensure the core 星汐 conversation remains forced-pinned and uses the latest avatar asset.
      final first = existingDirect.first;
      final firstId = first['id'] as String;
      final updates = <String, Object?>{};
      if ((first['is_pinned'] as int? ?? 0) == 0) {
        updates['is_pinned'] = 1;
      }
      if ((first['avatar_path'] as String? ?? '').isEmpty) {
        updates['avatar_path'] = coreAstideAvatarPath;
      }
      if (updates.isNotEmpty) {
        await db.update(
          'conversations',
          updates,
          where: 'id = ?',
          whereArgs: [firstId],
        );
      }
      return;
    }

    final now = DateTime.now();
    const greeting = '嗨，我是星汐（Astide）~ 你可以先去「我 -> API 与模型设置」填上 Key，之后就可以随时和我聊天啦。';
    final msgId = _uuid.v4();

    await db.transaction((txn) async {
      await txn.insert(
        'conversations',
        Conversation(
          id: coreAstideConversationId,
          title: '星汐 Astide',
          sourceType: ConversationSourceType.direct,
          avatarPath: coreAstideAvatarPath,
          avatarColor: 0xFF07C160,
          isPinned: true,
          lastMessagePreview: greeting,
          lastMessageAt: now,
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
      await txn.insert(
        'messages',
        ChatMessage(
          id: msgId,
          conversationId: coreAstideConversationId,
          role: MessageRole.assistant,
          content: greeting,
          status: MessageStatus.sent,
          createdAt: now,
        ).toMap(),
      );
    });
  }

  /// Returns true if [conv] is the single forced-pinned core 星汐 conversation.
  Future<bool> isCorePinnedAstide(Conversation conv) async {
    if (conv.id == coreAstideConversationId) return true;
    if (conv.sourceType != ConversationSourceType.direct) return false;
    final db = await _dbService.database;
    final rows = await db.query(
      'conversations',
      columns: ['id'],
      where: 'source_type = ?',
      whereArgs: [ConversationSourceType.direct.value],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['id'] == conv.id;
  }

  Future<List<Conversation>> listConversations() async {
    final db = await _dbService.database;
    final rows = await db.query(
      'conversations',
      orderBy: 'is_pinned DESC, last_message_at DESC',
    );
    return rows.map(Conversation.fromMap).toList();
  }

  Future<Conversation?> getConversation(String id) async {
    final db = await _dbService.database;
    final rows = await db.query('conversations', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Conversation.fromMap(rows.first);
  }

  Future<Conversation?> findConversationByCharacterId(String characterId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'conversations',
      where: 'character_id = ?',
      whereArgs: [characterId],
      orderBy: 'last_message_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Conversation.fromMap(rows.first);
  }

  Future<Conversation> createConversation({
    required String title,
    ConversationSourceType sourceType = ConversationSourceType.direct,
    String? characterId,
    String? avatarPath,
    int avatarColor = 0xFF07C160,
    String openingLine = '',
  }) async {
    final db = await _dbService.database;
    final now = DateTime.now();
    final convId = _uuid.v4();
    final parts = openingLine
        .split(RegExp(r'\r?\n|\|\|\|'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final preview = parts.isNotEmpty ? parts.last : '';
    final conv = Conversation(
      id: convId,
      title: title,
      characterId: characterId,
      sourceType: sourceType,
      avatarPath: avatarPath,
      avatarColor: avatarColor,
      lastMessagePreview: preview,
      lastMessageAt: now,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.insert('conversations', conv.toMap());
      for (var i = 0; i < parts.length; i++) {
        final msgTime = now.add(Duration(milliseconds: i * 10));
        await txn.insert(
          'messages',
          ChatMessage(
            id: _uuid.v4(),
            conversationId: convId,
            role: MessageRole.assistant,
            content: parts[i],
            status: MessageStatus.sent,
            createdAt: msgTime,
          ).toMap(),
        );
      }
    });

    return conv;
  }

  /// Finds existing conversation for [character] or creates one with its opening greeting.
  Future<Conversation> openOrCreateCharacterConversation(CharacterProfile character) async {
    final existing = await findConversationByCharacterId(character.id);
    if (existing != null) {
      // Keep title/avatar synced with character edits.
      final synced = existing.copyWith(
        title: character.displayName,
        avatarPath: () => character.avatarPath,
        avatarColor: character.avatarColor,
      );
      await updateConversation(synced);
      return synced;
    }
    return createConversation(
      title: character.displayName,
      sourceType: ConversationSourceType.roleplay,
      characterId: character.id,
      avatarPath: character.avatarPath,
      avatarColor: character.avatarColor,
      openingLine: character.openingLine,
    );
  }

  Future<void> updateConversation(Conversation conversation) async {
    final db = await _dbService.database;
    await db.update(
      'conversations',
      conversation.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [conversation.id],
    );
  }

  Future<void> deleteConversation(String conversationId) async {
    final db = await _dbService.database;
    await db.delete('conversations', where: 'id = ?', whereArgs: [conversationId]);
  }

  Future<void> clearConversationMessages(String conversationId) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'conversation_id = ?', whereArgs: [conversationId]);
      await txn.update(
        'conversations',
        {
          'last_message_preview': '',
          'context_summary': '',
          'context_summarized_until_ms': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
  }

  /// Loads all messages in [conversationId] strictly newer than [afterCreatedAtMs].
  Future<List<ChatMessage>> listMessagesAfter(
    String conversationId, {
    required int afterCreatedAtMs,
  }) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ? AND created_at > ?',
      whereArgs: [conversationId, afterCreatedAtMs],
      orderBy: 'created_at ASC, id ASC',
    );
    return _hydrateMessages(db, rows);
  }

  /// Silently persists rolling context compaction state without altering visible messages.
  Future<void> saveContextSummary({
    required String conversationId,
    required String summary,
    required int summarizedUntilMs,
  }) async {
    final db = await _dbService.database;
    await db.update(
      'conversations',
      {
        'context_summary': summary,
        'context_summarized_until_ms': summarizedUntilMs,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<List<ChatMessage>> listMessages(String conversationId) async {
    final db = await _dbService.database;
    final msgRows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC, id ASC',
    );
    return _hydrateMessages(db, msgRows);
  }

  /// Loads up to [limit] messages chronologically (`oldest -> newest`), optionally before [beforeMessage].
  Future<({List<ChatMessage> messages, bool hasMore})> listMessagesPage(
    String conversationId, {
    int limit = 40,
    ChatMessage? beforeMessage,
  }) async {
    final db = await _dbService.database;
    final fetchLimit = limit + 1;

    final List<Map<String, Object?>> rows;
    if (beforeMessage == null) {
      rows = await db.query(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'created_at DESC, id DESC',
        limit: fetchLimit,
      );
    } else {
      final ts = beforeMessage.createdAt.millisecondsSinceEpoch;
      rows = await db.query(
        'messages',
        where: 'conversation_id = ? AND (created_at < ? OR (created_at = ? AND id < ?))',
        whereArgs: [conversationId, ts, ts, beforeMessage.id],
        orderBy: 'created_at DESC, id DESC',
        limit: fetchLimit,
      );
    }

    final hasMore = rows.length > limit;
    final pageRows = hasMore ? rows.sublist(0, limit) : rows;
    final hydratedDesc = await _hydrateMessages(db, pageRows);
    return (
      messages: hydratedDesc.reversed.toList(),
      hasMore: hasMore,
    );
  }

  Future<List<ChatMessage>> _hydrateMessages(
    Database db,
    List<Map<String, Object?>> msgRows,
  ) async {
    if (msgRows.isEmpty) return [];

    final msgIds = msgRows.map((r) => r['id'] as String).toList();
    final byMsg = <String, List<ChatAttachment>>{};
    const chunkSize = 400;
    for (var start = 0; start < msgIds.length; start += chunkSize) {
      final end = (start + chunkSize) > msgIds.length ? msgIds.length : start + chunkSize;
      final chunk = msgIds.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final attRows = await db.query(
        'attachments',
        where: 'message_id IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in attRows) {
        final att = ChatAttachment.fromMap(row);
        byMsg.putIfAbsent(att.messageId, () => []).add(att);
      }
    }

    return msgRows
        .map((row) => ChatMessage.fromMap(
              row,
              attachments: byMsg[row['id'] as String] ?? const [],
            ))
        .toList();
  }

  Future<void> insertMessage(ChatMessage message) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final att in message.attachments) {
        await txn.insert(
          'attachments',
          att.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await _refreshConversationPreviewTxn(txn, message.conversationId);
    });
  }

  Future<void> updateMessage(ChatMessage message) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.update(
        'messages',
        message.toMap(),
        where: 'id = ?',
        whereArgs: [message.id],
      );
      await _refreshConversationPreviewTxn(txn, message.conversationId);
    });
  }

  Future<void> deleteMessage(String messageId, String conversationId) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'id = ?', whereArgs: [messageId]);
      await _refreshConversationPreviewTxn(txn, conversationId);
    });
  }

  Future<void> _refreshConversationPreviewTxn(DatabaseExecutor txn, String conversationId) async {
    final lastRows = await txn.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (lastRows.isEmpty) {
      await txn.update(
        'conversations',
        {
          'last_message_preview': '',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [conversationId],
      );
      return;
    }

    final lastMsgMap = lastRows.first;
    final attRows = await txn.query(
      'attachments',
      where: 'message_id = ?',
      whereArgs: [lastMsgMap['id']],
    );
    final lastMsg = ChatMessage.fromMap(
      lastMsgMap,
      attachments: attRows.map(ChatAttachment.fromMap).toList(),
    );

    await txn.update(
      'conversations',
      {
        'last_message_preview': lastMsg.previewText,
        'last_message_at': lastMsg.createdAt.millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  /// Imports parsed DeepSeek sessions transactionally, deduplicating by `external_id`.
  Future<DeepSeekImportResult> importDeepSeekSessions({
    required DeepSeekUserInfo userInfo,
    required List<ParsedDeepSeekSession> sessions,
  }) async {
    final db = await _dbService.database;
    final existingRows = await db.query(
      'conversations',
      columns: ['external_id'],
      where: 'external_id IS NOT NULL',
    );
    final existingExternalIds = existingRows
        .map((r) => r['external_id'] as String?)
        .whereType<String>()
        .toSet();

    var importedConvs = 0;
    var skippedDuplicates = 0;
    var importedMsgs = 0;
    var importedImgs = 0;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final item in sessions) {
        final extId = item.conversation.externalId;
        if (extId != null && existingExternalIds.contains(extId)) {
          skippedDuplicates++;
          continue;
        }
        if (extId != null) existingExternalIds.add(extId);
        importedConvs++;
        batch.insert(
          'conversations',
          item.conversation.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        for (final msg in item.messages) {
          importedMsgs++;
          batch.insert('messages', msg.toMap());
          for (final att in msg.attachments) {
            if (att.isImage) importedImgs++;
            batch.insert('attachments', att.toMap());
          }
        }
      }
      await batch.commit(noResult: true);
    });

    return DeepSeekImportResult(
      importedConversations: importedConvs,
      skippedDuplicates: skippedDuplicates,
      importedMessages: importedMsgs,
      importedImages: importedImgs,
      userInfo: userInfo,
    );
  }

  Future<GlobalSearchResults> searchAll(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return const GlobalSearchResults();
    final db = await _dbService.database;
    final likeArg = '%$query%';

    final convRows = await db.query(
      'conversations',
      where: 'title LIKE ? OR last_message_preview LIKE ?',
      whereArgs: [likeArg, likeArg],
      orderBy: 'is_pinned DESC, last_message_at DESC',
      limit: 30,
    );
    final charRows = await db.query(
      'characters',
      where: 'name LIKE ? OR remark LIKE ? OR personality LIKE ?',
      whereArgs: [likeArg, likeArg, likeArg],
      orderBy: 'updated_at DESC',
      limit: 20,
    );
    final msgRows = await db.query(
      'messages',
      where: 'content LIKE ?',
      whereArgs: [likeArg],
      orderBy: 'created_at DESC',
      limit: 40,
    );

    final convCache = <String, Conversation>{};
    for (final c in convRows) {
      final conv = Conversation.fromMap(c);
      convCache[conv.id] = conv;
    }

    final hits = <({Conversation conversation, ChatMessage message})>[];
    for (final mRow in msgRows) {
      final msg = ChatMessage.fromMap(mRow);
      var conv = convCache[msg.conversationId];
      if (conv == null) {
        final found = await db.query(
          'conversations',
          where: 'id = ?',
          whereArgs: [msg.conversationId],
          limit: 1,
        );
        if (found.isEmpty) continue;
        conv = Conversation.fromMap(found.first);
        convCache[conv.id] = conv;
      }
      hits.add((conversation: conv, message: msg));
    }

    return GlobalSearchResults(
      conversations: convRows.map(Conversation.fromMap).toList(),
      characters: charRows.map(CharacterProfile.fromMap).toList(),
      messageHits: hits,
    );
  }

  Future<StorageStats> getStorageStats() async {
    final db = await _dbService.database;
    final convCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM conversations'),
        ) ??
        0;
    final importedCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM conversations WHERE source_type = ?',
            [ConversationSourceType.deepseekImport.value],
          ),
        ) ??
        0;
    final charCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM characters'),
        ) ??
        0;
    final msgCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM messages'),
        ) ??
        0;
    final attCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM attachments'),
        ) ??
        0;

    return StorageStats(
      conversationCount: convCount,
      importedConversationCount: importedCount,
      characterCount: charCount,
      messageCount: msgCount,
      attachmentCount: attCount,
    );
  }

  Future<int> clearImportedConversations() async {
    final db = await _dbService.database;
    return db.delete(
      'conversations',
      where: 'source_type = ?',
      whereArgs: [ConversationSourceType.deepseekImport.value],
    );
  }

  /// Loads complete conversation snapshots (including linked characters and hydrated messages) for export.
  Future<List<ConversationExportBundle>> loadExportBundles({
    List<String>? conversationIds,
  }) async {
    final db = await _dbService.database;
    final List<Map<String, Object?>> convRows;
    if (conversationIds == null) {
      convRows = await db.query(
        'conversations',
        orderBy: 'is_pinned DESC, last_message_at DESC',
      );
    } else if (conversationIds.isEmpty) {
      return const [];
    } else {
      final placeholders = List.filled(conversationIds.length, '?').join(',');
      convRows = await db.query(
        'conversations',
        where: 'id IN ($placeholders)',
        whereArgs: conversationIds,
        orderBy: 'is_pinned DESC, last_message_at DESC',
      );
    }

    final conversations = convRows.map(Conversation.fromMap).toList();
    final charIds = conversations
        .map((c) => c.characterId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final charMap = <String, CharacterProfile>{};
    if (charIds.isNotEmpty) {
      final placeholders = List.filled(charIds.length, '?').join(',');
      final charRows = await db.query(
        'characters',
        where: 'id IN ($placeholders)',
        whereArgs: charIds,
      );
      for (final row in charRows) {
        final char = CharacterProfile.fromMap(row);
        charMap[char.id] = char;
      }
    }

    final bundles = <ConversationExportBundle>[];
    for (final conv in conversations) {
      final messages = await listMessages(conv.id);
      bundles.add(
        ConversationExportBundle(
          conversation: conv,
          character: conv.characterId != null ? charMap[conv.characterId!] : null,
          messages: messages,
        ),
      );
    }
    return bundles;
  }
}
