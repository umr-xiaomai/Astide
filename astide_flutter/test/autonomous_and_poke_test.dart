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
import 'package:astide_flutter/data/services/multi_reply_guard.dart';
import 'package:astide_flutter/data/services/openai_chat_service.dart';
import 'package:astide_flutter/domain/models/api_profile.dart';
import 'package:astide_flutter/domain/models/app_settings.dart';
import 'package:astide_flutter/domain/models/character_profile.dart';
import 'package:astide_flutter/domain/models/chat_message.dart';
import 'package:astide_flutter/domain/models/conversation.dart';
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
  final List<String> capturedSystemPrompts = [];
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
    capturedSystemPrompts.add(systemPrompt);
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

  test('MultiReplyGuard blocks exact duplicates, paraphrases, echoes, and meta-chatter', () {
    // Exact match & punctuation-only variant
    expect(
      MultiReplyGuard.evaluateFollowUp(
        rawReply: '辛苦啦，快去休息吧！',
        sentBubblesInTurn: ['辛苦啦，快去休息吧！'],
      ).accepted,
      isFalse,
    );
    expect(
      MultiReplyGuard.evaluateFollowUp(
        rawReply: '「辛苦啦 快去休息吧~」[DONE]',
        sentBubblesInTurn: ['辛苦啦，快去休息吧！'],
      ).accepted,
      isFalse,
    );

    // Substring containment & CJK paraphrase
    expect(
      MultiReplyGuard.evaluateFollowUp(
        rawReply: '外面风真的好大呀',
        sentBubblesInTurn: ['刚回来，今天外面风真的好大呀'],
      ).accepted,
      isFalse,
    );
    expect(
      MultiReplyGuard.evaluateFollowUp(
        rawReply: '辛苦啦，快歇会儿喝口水吧~',
        sentBubblesInTurn: ['辛苦啦，赶紧歇会儿喝口水！'],
      ).accepted,
      isFalse,
    );

    // Meta-chatter & user echo
    expect(
      MultiReplyGuard.evaluateFollowUp(
        rawReply: '好的，无需补充 [DONE]',
        sentBubblesInTurn: ['刚吃完饭'],
      ).accepted,
      isFalse,
    );
    expect(
      MultiReplyGuard.evaluateFollowUp(
        rawReply: '今晚去吃火锅吧',
        sentBubblesInTurn: ['好呀我超想吃'],
        lastUserText: '今晚去吃火锅吧',
      ).accepted,
      isFalse,
    );

    // Genuine distinct follow-up passes (and trailing [DONE] stops chain after accepting)
    final ok = MultiReplyGuard.evaluateFollowUp(
      rawReply: '你晚上想吃点啥呀 [DONE]',
      sentBubblesInTurn: ['辛苦啦，赶紧歇会儿喝口水！'],
    );
    expect(ok.accepted, isTrue);
    expect(ok.stopChain, isTrue);
    expect(ok.text, equals('你晚上想吃点啥呀'));

    // Self-duplicate lines collapsed
    final dedupSelf = MultiReplyGuard.evaluateFollowUp(
      rawReply: '外面风好大\n外面风好大！',
      sentBubblesInTurn: ['刚回来呀'],
    );
    expect(dedupSelf.accepted, isTrue);
    expect(dedupSelf.text, equals('外面风好大'));

    // Gating rules: disabled segmentedReply, code blocks, or long bubble stop follow-up
    expect(
      MultiReplyGuard.shouldRequestFollowUp(
        segmentedReplyEnabled: false,
        sentBubbles: ['嗨'],
        extraIndex: 1,
        random: _FixedRandom([0.0]),
      ),
      isFalse,
    );
    expect(
      MultiReplyGuard.shouldRequestFollowUp(
        segmentedReplyEnabled: true,
        sentBubbles: ['```dart\nprint(1);\n```'],
        extraIndex: 1,
        random: _FixedRandom([0.0]),
      ),
      isFalse,
    );
  });

  test('ChatDetailViewModel drops duplicate follow-ups, respects segmentedReply=false, and prevents concurrent double-send',
      () async {
    final stubAi = _StubOpenAiService([
      '刚回来呀',
      '刚回来呀', // Exact duplicate from model -> MUST be rejected and stop immediately (no 3rd call!)
      '不应该触发的第三条',
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
    final coreConv = await controller.getCoreAstideConversation();

    final vm = ChatDetailViewModel(
      appController: controller,
      conversation: coreConv,
      random: _FixedRandom([0.05]),
      followUpDelayOverride: Duration.zero,
    );
    await vm.load();

    // Rapid double-send without awaiting first -> second call must be ignored synchronously!
    await Future.wait([
      vm.sendMessage('回家了吗'),
      vm.sendMessage('回家了吗'),
    ]);

    expect(stubAi.callCount, equals(2));
    expect(stubAi.capturedSystemPrompts[1], contains('1. 「刚回来呀」'));
    final userCount = vm.messages.where((m) => m.isUser && m.content == '回家了吗').length;
    final replyCount = vm.messages.where((m) => !m.isUser && m.content == '刚回来呀').length;
    expect(userCount, equals(1));
    expect(replyCount, equals(1));
    expect(vm.messages.any((m) => m.content == '不应该触发的第三条'), isFalse);
    vm.dispose();

    // Character with segmentedReply == false must issue strictly 1 request.
    final now = DateTime.now();
    final singleChar = CharacterProfile(
      id: 'char-single-bubble',
      name: '单条角色',
      segmentedReply: false,
      createdAt: now,
      updatedAt: now,
    );
    await charRepo.saveCharacter(singleChar);
    final singleConv = await chatRepo.createConversation(
      title: '单条角色',
      characterId: singleChar.id,
      sourceType: ConversationSourceType.roleplay,
    );
    final singleStub = _StubOpenAiService(['收到啦', '第二条不该被请求']);
    final singleController = AppController(
      databaseService: dbService,
      mediaStorage: mediaStorage,
      fileExtractor: fileExtractor,
      openAiChatService: singleStub,
      deepSeekImportService: DeepSeekImportService(
        mediaStorage: mediaStorage,
        fileExtractor: fileExtractor,
      ),
      settingsRepository: settingsRepo,
      characterRepository: charRepo,
      chatRepository: chatRepo,
      momentsRepository: momentsRepo,
    );
    await singleController.initialize();
    final vmSingle = ChatDetailViewModel(
      appController: singleController,
      conversation: singleConv,
      random: _FixedRandom([0.0]),
      followUpDelayOverride: Duration.zero,
    );
    await vmSingle.load();
    await vmSingle.sendMessage('早安');
    expect(singleStub.callCount, equals(1));
    expect(vmSingle.messages.where((m) => !m.isUser).map((m) => m.content).toList(), equals(['收到啦']));
    vmSingle.dispose();
  });

  test('AutonomousService rejects duplicate follow-up bubble and does not save it', () async {
    final conv = await chatRepo.createConversation(
      title: '去重自主测试',
      openingLine: '嗨',
    );
    await chatRepo.updateConversation(
      conv.copyWith(lastMessageAt: DateTime.now().subtract(const Duration(hours: 3))),
    );

    final stubAi = _StubOpenAiService([
      '晚上记得多穿点衣服呀',
      '晚上记得多穿点衣服呀！', // Duplicate follow-up must be dropped
    ]);
    final autoService = AutonomousService(
      openAiChatService: stubAi,
      chatRepository: chatRepo,
      characterRepository: charRepo,
      momentsRepository: momentsRepo,
      contextCompactionService: ContextCompactionService(
        chatRepository: chatRepo,
        openAiChatService: stubAi,
      ),
      random: _FixedRandom([0.05, 0.05, 0.05]),
    );

    final res = await autoService.evaluateAndSend(
      settings: const AppSettings(
        autonomousEnabled: true,
        quietHoursEnabled: false,
        autonomousProbability: 0.35,
      ),
      activeProfile: configuredProfile,
      targetConversationId: conv.id,
      forceSend: false,
    );
    expect(res.sent, isTrue);
    expect(stubAi.callCount, equals(2));

    final stored = await chatRepo.listMessages(conv.id);
    final matches = stored.where((m) => m.content.contains('多穿点衣服')).toList();
    expect(matches.length, equals(1));
  });
}
