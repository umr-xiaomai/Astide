import 'package:astide_flutter/data/repositories/character_repository.dart';
import 'package:astide_flutter/data/repositories/chat_repository.dart';
import 'package:astide_flutter/data/repositories/settings_repository.dart';
import 'package:astide_flutter/data/services/database_service.dart';
import 'package:astide_flutter/domain/models/api_profile.dart';
import 'package:astide_flutter/domain/models/character_profile.dart';
import 'package:astide_flutter/domain/models/chat_attachment.dart';
import 'package:astide_flutter/domain/models/chat_message.dart';
import 'package:astide_flutter/domain/models/conversation.dart';
import 'package:astide_flutter/domain/models/deepseek_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late DatabaseService dbService;
  late SettingsRepository settingsRepo;
  late CharacterRepository characterRepo;
  late ChatRepository chatRepo;

  setUp(() async {
    dbService = DatabaseService(
      factoryOverride: databaseFactoryFfiNoIsolate,
      pathOverride: inMemoryDatabasePath,
    );
    settingsRepo = SettingsRepository(databaseService: dbService);
    characterRepo = CharacterRepository(databaseService: dbService);
    chatRepo = ChatRepository(databaseService: dbService);
  });

  tearDown(() async {
    await dbService.close();
  });

  group('SettingsRepository', () {
    test('defaults to human-persona Astide prompt and persists autonomous toggles', () async {
      final settings = await settingsRepo.loadSettings();
      expect(settings.autonomousEnabled, isFalse);
      expect(settings.defaultAssistantPrompt, contains('星汐'));
      expect(settings.defaultAssistantPrompt, contains('Astide'));
      expect(settings.defaultAssistantPrompt, contains('真实存在的人类'));

      await settingsRepo.saveSettings(
        settings.copyWith(autonomousEnabled: true, keepAliveEnabled: true),
      );
      final reloaded = await settingsRepo.loadSettings();
      expect(reloaded.autonomousEnabled, isTrue);
      expect(reloaded.keepAliveEnabled, isTrue);
    });

    test('seeds default DeepSeek V4.1 Flash profile and switches active profile', () async {
      final profiles = await settingsRepo.listApiProfiles();
      expect(profiles.length, equals(1));
      expect(profiles.where((p) => p.isActive).length, equals(1));
      expect(profiles.first.model, equals('deepseek-flash'));
      expect(profiles.first.supportsVision, isTrue);

      final custom = ApiProfile(
        id: 'custom-1',
        name: '测试配置',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test-placeholder',
        model: 'deepseek-flash',
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await settingsRepo.saveApiProfile(custom);

      final active = await settingsRepo.getActiveApiProfile();
      expect(active?.id, equals('custom-1'));
      expect(active?.chatCompletionsUri.toString(), equals('https://api.deepseek.com/chat/completions'));
    });
  });

  group('CharacterRepository', () {
    test('saves character and compiles human roleplay prompt', () async {
      final now = DateTime.now();
      final char = CharacterProfile(
        id: 'char-1',
        name: '林知夏',
        gender: '女',
        age: '24岁',
        occupation: '研究生',
        relationship: '直系学姐',
        personality: '温柔细腻',
        speechStyle: '微信短句口语',
        openingLine: '刚下课呀|||吃晚饭了吗？',
        segmentedReply: true,
        createdAt: now,
        updatedAt: now,
      );

      await characterRepo.saveCharacter(char);
      final loaded = await characterRepo.getCharacter('char-1');
      expect(loaded?.name, equals('林知夏'));

      final prompt = loaded!.buildEffectiveSystemPrompt(userNickname: '小埋');
      expect(prompt, contains('真实的人类'));
      expect(prompt, contains('林知夏'));
      expect(prompt, contains('|||'));
    });
  });

  group('ChatRepository', () {
    test('creates initial conversation, character chats, and searches messages', () async {
      await chatRepo.ensureInitialConversation();
      final list = await chatRepo.listConversations();
      expect(list.length, equals(1));
      expect(list.first.title, equals('星汐 Astide'));

      final now = DateTime.now();
      final char = CharacterProfile(
        id: 'c-2',
        name: '苏念',
        openingLine: '猜猜我在哪|||给你带了烤红薯',
        createdAt: now,
        updatedAt: now,
      );
      await characterRepo.saveCharacter(char);
      final charConv = await chatRepo.openOrCreateCharacterConversation(char);
      final msgs = await chatRepo.listMessages(charConv.id);
      expect(msgs.length, equals(2));
      expect(msgs[0].content, equals('猜猜我在哪'));
      expect(msgs[1].content, equals('给你带了烤红薯'));

      final hits = await chatRepo.searchAll('烤红薯');
      expect(hits.messageHits.length, equals(1));
      expect(hits.messageHits.first.conversation.id, equals(charConv.id));
    });

    test('deduplicates imported DeepSeek sessions by externalId', () async {
      final now = DateTime.now();
      final session = ParsedDeepSeekSession(
        conversation: Conversation(
          id: 'conv-ds-1',
          externalId: 'ds-ext-1',
          title: '平面投影测试',
          sourceType: ConversationSourceType.deepseekImport,
          lastMessagePreview: '侧垂面',
          lastMessageAt: now,
          createdAt: now,
          updatedAt: now,
        ),
        messages: [
          ChatMessage(
            id: 'm-1',
            conversationId: 'conv-ds-1',
            role: MessageRole.user,
            content: '直接回答我',
            attachments: const [
              ChatAttachment(
                id: 'a-1',
                messageId: 'm-1',
                type: AttachmentType.file,
                fileName: 'drawing.pdf',
                fileSize: 1024,
              ),
            ],
            createdAt: now,
          ),
        ],
      );

      final firstRun = await chatRepo.importDeepSeekSessions(
        userInfo: const DeepSeekUserInfo(nickname: '小埋'),
        sessions: [session],
      );
      expect(firstRun.importedConversations, equals(1));
      expect(firstRun.skippedDuplicates, equals(0));

      final secondRun = await chatRepo.importDeepSeekSessions(
        userInfo: const DeepSeekUserInfo(nickname: '小埋'),
        sessions: [session],
      );
      expect(secondRun.importedConversations, equals(0));
      expect(secondRun.skippedDuplicates, equals(1));
    });

    test('paginates long conversations chronologically without missing or duplicating rows',
        () async {
      final conv = await chatRepo.createConversation(title: '长会话测试');
      final baseTime = DateTime(2026, 11, 1, 10, 0);
      for (var i = 0; i < 65; i++) {
        await chatRepo.insertMessage(ChatMessage(
          id: 'm_${i.toString().padLeft(3, '0')}',
          conversationId: conv.id,
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          content: 'msg $i',
          createdAt: baseTime.add(Duration(seconds: i)),
        ));
      }

      final page1 = await chatRepo.listMessagesPage(conv.id, limit: 40);
      expect(page1.hasMore, isTrue);
      expect(page1.messages.length, equals(40));
      expect(page1.messages.first.content, equals('msg 25'));
      expect(page1.messages.last.content, equals('msg 64'));

      final page2 = await chatRepo.listMessagesPage(
        conv.id,
        limit: 40,
        beforeMessage: page1.messages.first,
      );
      expect(page2.hasMore, isFalse);
      expect(page2.messages.length, equals(25));
      expect(page2.messages.first.content, equals('msg 0'));
      expect(page2.messages.last.content, equals('msg 24'));
    });
  });
}
