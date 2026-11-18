import 'dart:math';

import 'package:astide_flutter/app_scope.dart';
import 'package:astide_flutter/data/repositories/character_repository.dart';
import 'package:astide_flutter/data/repositories/chat_repository.dart';
import 'package:astide_flutter/data/repositories/moments_repository.dart';
import 'package:astide_flutter/data/repositories/settings_repository.dart';
import 'package:astide_flutter/data/services/autonomous_service.dart';
import 'package:astide_flutter/data/services/context_compaction_service.dart';
import 'package:astide_flutter/data/services/database_service.dart';
import 'package:astide_flutter/data/services/deepseek_import_service.dart';
import 'package:astide_flutter/data/services/file_extractor_service.dart';
import 'package:astide_flutter/data/services/media_storage_service.dart';
import 'package:astide_flutter/data/services/openai_chat_service.dart';
import 'package:astide_flutter/domain/models/api_profile.dart';
import 'package:astide_flutter/domain/models/app_settings.dart';
import 'package:astide_flutter/domain/models/chat_message.dart';
import 'package:astide_flutter/ui/features/chat_detail/view_models/chat_detail_view_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FixedRandom implements Random {
  _FixedRandom(this.sequence);
  final List<double> sequence;
  int _idx = 0;

  @override
  double nextDouble() {
    final val = sequence[_idx % sequence.length];
    _idx++;
    return val;
  }

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => nextDouble() < 0.5;
}

class _StubOpenAiService extends OpenAiChatService {
  _StubOpenAiService(this.replies);

  final List<String> replies;
  int callCount = 0;

  @override
  Stream<ChatStreamDelta> streamChatCompletion({
    required ApiProfile profile,
    required List<ChatMessage> history,
    String systemPrompt = '',
    String? modelOverride,
    int? maxTokens,
    bool? forceNonStreaming,
    CancelToken? cancelToken,
  }) async* {
    final text = replies[callCount < replies.length ? callCount : replies.length - 1];
    callCount++;
    if (text.isNotEmpty) {
      yield ChatStreamDelta(contentDelta: text);
    }
    yield const ChatStreamDelta(isDone: true);
  }
}

void main() {
  sqfliteFfiInit();

  late DatabaseService dbService;
  late ChatRepository chatRepo;
  late CharacterRepository charRepo;
  late SettingsRepository settingsRepo;
  late MomentsRepository momentsRepo;

  final configuredProfile = ApiProfile(
    id: 'test-prof',
    name: 'Test Flash',
    baseUrl: 'https://api.deepseek.com',
    apiKey: 'sk-test-placeholder',
    model: 'deepseek-flash',
    isActive: true,
    createdAt: DateTime(2026, 11, 18),
    updatedAt: DateTime(2026, 11, 18),
  );

  setUp(() async {
    dbService = DatabaseService(
      factoryOverride: databaseFactoryFfiNoIsolate,
      pathOverride: inMemoryDatabasePath,
    );
    chatRepo = ChatRepository(databaseService: dbService);
    charRepo = CharacterRepository(databaseService: dbService);
    settingsRepo = SettingsRepository(databaseService: dbService);
    momentsRepo = MomentsRepository(databaseService: dbService);
    await settingsRepo.saveApiProfile(configuredProfile);
  });

  tearDown(() async {
    await dbService.close();
  });

  test('AutonomousService skips when probability misses and sends multi-request bubbles when hit',
      () async {
    final conv = await chatRepo.createConversation(
      title: '星汐测试',
      openingLine: '嗨',
    );
    await chatRepo.updateConversation(
      conv.copyWith(lastMessageAt: DateTime.now().subtract(const Duration(hours: 2))),
    );

    final stubAiMiss = _StubOpenAiService(['[POKE_BACK] 在干嘛呀', '刚泡好热茶', '[DONE]']);
    final missService = AutonomousService(
      openAiChatService: stubAiMiss,
      chatRepository: chatRepo,
      characterRepository: charRepo,
      momentsRepository: momentsRepo,
      contextCompactionService: ContextCompactionService(
        chatRepository: chatRepo,
        openAiChatService: stubAiMiss,
      ),
      random: _FixedRandom([0.85]),
    );

    final missRes = await missService.evaluateAndSend(
      settings: const AppSettings(
        autonomousEnabled: true,
        quietHoursEnabled: false,
        autonomousProbability: 0.35,
      ),
      activeProfile: configuredProfile,
      targetConversationId: conv.id,
      forceSend: false,
    );
    expect(missRes.sent, isFalse);
    expect(missRes.skipped, isTrue);
    expect(stubAiMiss.callCount, equals(0));

    final stubAiHit = _StubOpenAiService(['[POKE_BACK] 在干嘛呀', '刚泡好热茶', '[DONE]']);
    final hitService = AutonomousService(
      openAiChatService: stubAiHit,
      chatRepository: chatRepo,
      characterRepository: charRepo,
      momentsRepository: momentsRepo,
      contextCompactionService: ContextCompactionService(
        chatRepository: chatRepo,
        openAiChatService: stubAiHit,
      ),
      random: _FixedRandom([0.10, 0.20, 0.90]),
    );

    final hitRes = await hitService.evaluateAndSend(
      settings: const AppSettings(
        autonomousEnabled: true,
        quietHoursEnabled: false,
        autonomousProbability: 0.35,
      ),
      activeProfile: configuredProfile,
      targetConversationId: conv.id,
      forceSend: false,
    );
    expect(hitRes.sent, isTrue);
    expect(stubAiHit.callCount, greaterThanOrEqualTo(2));

    final stored = await chatRepo.listMessages(conv.id);
    expect(stored.any((m) => m.role == MessageRole.system && m.content.contains('拍了拍你')), isTrue);
    expect(stored.any((m) => m.content == '在干嘛呀'), isTrue);
    expect(stored.any((m) => m.content == '刚泡好热茶'), isTrue);
    expect(stored.any((m) => m.content.contains('[DONE]')), isFalse);
  });

  test('ChatDetailViewModel streams multi-request replies without ||| and supports probabilistic poke',
      () async {
    final stubAi = _StubOpenAiService([
      '刚回来呀',
      '外面风好大',
      '[DONE]',
      '[POKE_BACK] 干嘛突然拍我呀',
    ]);
    final fileExtractor = FileExtractorService();
    final mediaStorage = MediaStorageService();
    final controller = AppController(
      databaseService: dbService,
      mediaStorage: mediaStorage,
      fileExtractor: fileExtractor,
      openAiChatService: stubAi,
      deepSeekImportService: DeepSeekImportService(
        mediaStorage: mediaStorage,
        fileExtractor: fileExtractor,
      ),
      settingsRepository: settingsRepo,
      characterRepository: charRepo,
      chatRepository: chatRepo,
      momentsRepository: momentsRepo,
    );
    await controller.initialize();
    await controller.updateSettings(
      controller.settings.copyWith(pokeReplyProbability: 0.55),
    );

    final coreConv = await controller.getCoreAstideConversation();

    // First verify multi-request conversational flow.
    final vmHit = ChatDetailViewModel(
      appController: controller,
      conversation: coreConv,
      random: _FixedRandom([0.10]),
    );
    await vmHit.load();
    await vmHit.sendMessage('在吗');

    expect(stubAi.callCount, equals(3));
    expect(vmHit.messages.any((m) => m.content == '刚回来呀'), isTrue);
    expect(vmHit.messages.any((m) => m.content == '外面风好大'), isTrue);
    expect(vmHit.messages.any((m) => m.content.contains('[DONE]')), isFalse);

    // Trigger probabilistic poke hit -> inserts "你拍了拍“星汐 Astide”", poke back, and AI bubble.
    final pokeReplied = await vmHit.pokeOpponent();
    expect(pokeReplied, isTrue);
    expect(vmHit.messages.any((m) => m.role == MessageRole.system && m.content == '你拍了拍“星汐 Astide”'), isTrue);
    expect(vmHit.messages.any((m) => m.role == MessageRole.system && m.content == '“星汐 Astide” 拍了拍你'), isTrue);
    expect(vmHit.messages.any((m) => m.content == '干嘛突然拍我呀'), isTrue);

    vmHit.dispose();

    // Verify poke miss still records "你拍了拍..." without forcing an AI reply.
    final vmMiss = ChatDetailViewModel(
      appController: controller,
      conversation: coreConv,
      random: _FixedRandom([0.92]),
    );
    await vmMiss.load();
    final prevCalls = stubAi.callCount;
    final pokeMissed = await vmMiss.pokeOpponent();
    expect(pokeMissed, isFalse);
    expect(stubAi.callCount, equals(prevCalls));
    vmMiss.dispose();
  });
}
