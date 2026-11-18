import 'package:astide_flutter/data/repositories/chat_repository.dart';
import 'package:astide_flutter/data/services/context_compaction_service.dart';
import 'package:astide_flutter/data/services/database_service.dart';
import 'package:astide_flutter/data/services/openai_chat_service.dart';
import 'package:astide_flutter/domain/models/api_profile.dart';
import 'package:astide_flutter/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeOpenAiChatService extends OpenAiChatService {
  _FakeOpenAiChatService(this.cannedSummary);

  final String cannedSummary;
  int callCount = 0;

  @override
  Stream<ChatStreamDelta> streamChatCompletion({
    required ApiProfile profile,
    required List<ChatMessage> history,
    String systemPrompt = '',
    String? modelOverride,
    int? maxTokens,
    bool? forceNonStreaming,
    dynamic cancelToken,
  }) async* {
    callCount++;
    yield ChatStreamDelta(contentDelta: cannedSummary, isDone: true);
  }
}

void main() {
  sqfliteFfiInit();

  late DatabaseService dbService;
  late ChatRepository chatRepo;

  setUp(() async {
    dbService = DatabaseService(
      factoryOverride: databaseFactoryFfiNoIsolate,
      pathOverride: inMemoryDatabasePath,
    );
    chatRepo = ChatRepository(databaseService: dbService);
  });

  tearDown(() async {
    await dbService.close();
  });

  test('silently compacts long conversations without modifying visible messages', () async {
    final conv = await chatRepo.createConversation(title: '长期对话');
    final baseTime = DateTime(2026, 11, 10, 9, 0);

    for (var i = 0; i < 36; i++) {
      await chatRepo.insertMessage(ChatMessage(
        id: 'c_msg_${i.toString().padLeft(2, '0')}',
        conversationId: conv.id,
        role: i.isEven ? MessageRole.user : MessageRole.assistant,
        content: '对话第 $i 句内容，讨论周末计划与喜欢喝的乌龙茶',
        createdAt: baseTime.add(Duration(minutes: i)),
      ));
    }

    final fakeAi = _FakeOpenAiChatService('对方喜欢喝乌龙茶，双方约定周末一起逛书店。');
    final compactor = ContextCompactionService(
      chatRepository: chatRepo,
      openAiChatService: fakeAi,
    );
    final profile = ApiProfile(
      id: 'p1',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      apiKey: 'sk-test-placeholder',
      model: 'deepseek-flash',
      createdAt: baseTime,
      updatedAt: baseTime,
    );

    final result = await compactor.prepareContext(
      conversationId: conv.id,
      profile: profile,
    );

    expect(fakeAi.callCount, equals(1));
    expect(result.summary, contains('乌龙茶'));
    expect(result.recentMessages.length, equals(ContextCompactionService.keepRecentCount));

    // Visible UI history in SQLite remains completely intact!
    final allVisible = await chatRepo.listMessages(conv.id);
    expect(allVisible.length, equals(36));

    // Calling prepareContext again while tail <= threshold skips redundant compaction.
    final second = await compactor.prepareContext(
      conversationId: conv.id,
      profile: profile,
    );
    expect(fakeAi.callCount, equals(1));
    expect(second.summary, equals(result.summary));
    expect(second.recentMessages.length, equals(ContextCompactionService.keepRecentCount));
  });
}
