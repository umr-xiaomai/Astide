import 'dart:convert';
import 'dart:io';

import 'package:astide_flutter/data/repositories/character_repository.dart';
import 'package:astide_flutter/data/repositories/chat_repository.dart';
import 'package:astide_flutter/data/repositories/settings_repository.dart';
import 'package:astide_flutter/data/services/chat_export_service.dart';
import 'package:astide_flutter/data/services/database_service.dart';
import 'package:astide_flutter/domain/models/api_profile.dart';
import 'package:astide_flutter/domain/models/character_profile.dart';
import 'package:astide_flutter/domain/models/chat_attachment.dart';
import 'package:astide_flutter/domain/models/chat_message.dart';
import 'package:astide_flutter/domain/models/conversation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xml/xml.dart';

void main() {
  sqfliteFfiInit();

  late DatabaseService dbService;
  late ChatRepository chatRepo;
  late CharacterRepository charRepo;
  late SettingsRepository settingsRepo;
  late ChatExportService exportService;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('astide_export_test_');
    dbService = DatabaseService(
      factoryOverride: databaseFactoryFfiNoIsolate,
      pathOverride: inMemoryDatabasePath,
    );
    chatRepo = ChatRepository(databaseService: dbService);
    charRepo = CharacterRepository(databaseService: dbService);
    settingsRepo = SettingsRepository(databaseService: dbService);
    exportService = ChatExportService(
      sqliteFactoryOverride: databaseFactoryFfiNoIsolate,
      tempDirOverride: tempDir,
    );
  });

  tearDown(() async {
    await dbService.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<Conversation> seedRichConversation() async {
    await settingsRepo.saveApiProfile(
      ApiProfile(
        id: 'secret-profile',
        name: 'My Key',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-super-secret-do-not-export',
        model: 'deepseek-flash',
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final now = DateTime(2026, 11, 19, 10, 30);
    final char = await charRepo.saveCharacter(
      CharacterProfile(
        id: 'char-lin',
        name: '林知夏',
        occupation: '摄影师',
        relationship: '好朋友',
        personality: '温柔有趣',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final conv = await chatRepo.openOrCreateCharacterConversation(char);

    const msgUserId = 'msg-user-1';
    await chatRepo.insertMessage(
      ChatMessage(
        id: msgUserId,
        conversationId: conv.id,
        role: MessageRole.user,
        content: '帮我看看 <script>alert(1)</script> & 附件\x00控制符',
        attachments: [
          const ChatAttachment(
            id: 'att-1',
            messageId: msgUserId,
            type: AttachmentType.file,
            fileName: 'notes.txt',
            mimeType: 'text/plain',
            fileSize: 256,
            extractedText: '附件里的示例正文',
          ),
        ],
        createdAt: now.add(const Duration(minutes: 1)),
      ),
    );
    await chatRepo.insertMessage(
      ChatMessage(
        id: 'msg-sys-poke',
        conversationId: conv.id,
        role: MessageRole.system,
        content: '你拍了拍“林知夏”',
        createdAt: now.add(const Duration(minutes: 2)),
      ),
    );
    await chatRepo.insertMessage(
      ChatMessage(
        id: 'msg-ai-1',
        conversationId: conv.id,
        role: MessageRole.assistant,
        content: '收到啦！拍一拍我也看见啦',
        reasoningContent: '先友好回应用户附件，再带出轻松语气。',
        thinkingSeconds: 1.4,
        createdAt: now.add(const Duration(minutes: 3)),
      ),
    );
    return conv;
  }

  test('exports conversations cleanly to SQLite without API secrets', () async {
    final conv = await seedRichConversation();
    final settings = await settingsRepo.loadSettings();
    final bundles = await chatRepo.loadExportBundles(conversationIds: [conv.id]);

    final artifact = await exportService.buildExport(
      format: ChatExportFormat.sqlite,
      bundles: bundles,
      settings: settings,
      exportedAt: DateTime(2026, 11, 19, 12, 0),
    );

    expect(artifact.fileName, endsWith('.sqlite'));
    expect(artifact.conversationCount, equals(1));
    expect(artifact.messageCount, equals(3));
    expect(artifact.attachmentCount, equals(1));

    final verifyPath = p.join(tempDir.path, 'verify_export.sqlite');
    await File(verifyPath).writeAsBytes(artifact.bytes, flush: true);

    final verifyDbService = DatabaseService(
      factoryOverride: databaseFactoryFfiNoIsolate,
      pathOverride: verifyPath,
    );
    try {
      final db = await verifyDbService.database;
      final convRows = await db.query('conversations');
      final msgRows = await db.query('messages', orderBy: 'created_at ASC');
      final attRows = await db.query('attachments');
      final charRows = await db.query('characters');
      final profileRows = await db.query('api_profiles');
      final metaRows = await db.query('export_meta');

      expect(convRows.length, equals(1));
      expect(convRows.first['id'], equals(conv.id));
      expect(msgRows.length, equals(3));
      expect(attRows.length, equals(1));
      expect(attRows.first['file_name'], equals('notes.txt'));
      expect(charRows.length, equals(1));
      expect(profileRows, isEmpty);
      expect(metaRows.any((r) => r['key'] == 'app_name'), isTrue);
    } finally {
      await verifyDbService.close();
    }
  });

  test('exports valid XML, JSON, TXT, Markdown, and XSS-safe HTML', () async {
    final conv = await seedRichConversation();
    final settings = await settingsRepo.loadSettings();
    final bundles = await chatRepo.loadExportBundles(conversationIds: [conv.id]);

    final xmlArtifact = await exportService.buildExport(
      format: ChatExportFormat.xml,
      bundles: bundles,
      settings: settings,
    );
    final xmlDoc = XmlDocument.parse(utf8.decode(xmlArtifact.bytes));
    expect(xmlDoc.rootElement.name.local, equals('astide_export'));
    expect(xmlDoc.findAllElements('message').length, equals(3));
    expect(xmlDoc.findAllElements('reasoning').single.innerText, contains('轻松语气'));

    final jsonArtifact = await exportService.buildExport(
      format: ChatExportFormat.json,
      bundles: bundles,
      settings: settings,
      includeReasoning: false,
    );
    final decoded = jsonDecode(utf8.decode(jsonArtifact.bytes)) as Map<String, dynamic>;
    expect(decoded['format'], equals('astide_chat_export'));
    final exportedConvs = decoded['conversations'] as List<dynamic>;
    final msgs = (exportedConvs.first as Map<String, dynamic>)['messages'] as List<dynamic>;
    expect(msgs.length, equals(3));
    expect((msgs.last as Map<String, dynamic>).containsKey('reasoningContent'), isFalse);

    final txtArtifact = await exportService.buildExport(
      format: ChatExportFormat.txt,
      bundles: bundles,
      settings: settings,
    );
    final txtText = utf8.decode(txtArtifact.bytes);
    expect(txtText, contains('林知夏'));
    expect(txtText, contains('[系统提示] 你拍了拍“林知夏”'));
    expect(txtText, contains('[文件附件] notes.txt'));

    final mdArtifact = await exportService.buildExport(
      format: ChatExportFormat.markdown,
      bundles: bundles,
      settings: settings,
    );
    expect(utf8.decode(mdArtifact.bytes), contains('## 林知夏'));

    final htmlArtifact = await exportService.buildExport(
      format: ChatExportFormat.html,
      bundles: bundles,
      settings: settings,
    );
    final htmlText = utf8.decode(htmlArtifact.bytes);
    expect(htmlText, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
    expect(htmlText, isNot(contains('<script>alert(1)</script>')));
  });
}
