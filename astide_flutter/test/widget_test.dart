import 'package:astide_flutter/app_scope.dart';
import 'package:astide_flutter/data/repositories/character_repository.dart';
import 'package:astide_flutter/data/repositories/chat_repository.dart';
import 'package:astide_flutter/data/repositories/settings_repository.dart';
import 'package:astide_flutter/data/services/database_service.dart';
import 'package:astide_flutter/data/services/deepseek_import_service.dart';
import 'package:astide_flutter/data/services/file_extractor_service.dart';
import 'package:astide_flutter/data/services/media_storage_service.dart';
import 'package:astide_flutter/data/services/openai_chat_service.dart';
import 'package:astide_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late DatabaseService dbService;
  late AppController controller;

  setUp(() async {
    dbService = DatabaseService(
      factoryOverride: databaseFactoryFfiNoIsolate,
      pathOverride: inMemoryDatabasePath,
    );
    final mediaStorage = MediaStorageService();
    final fileExtractor = FileExtractorService();
    controller = AppController(
      databaseService: dbService,
      mediaStorage: mediaStorage,
      fileExtractor: fileExtractor,
      openAiChatService: OpenAiChatService(fileExtractor: fileExtractor),
      deepSeekImportService: DeepSeekImportService(
        mediaStorage: mediaStorage,
        fileExtractor: fileExtractor,
      ),
      settingsRepository: SettingsRepository(databaseService: dbService),
      characterRepository: CharacterRepository(databaseService: dbService),
      chatRepository: ChatRepository(databaseService: dbService),
    );
    await controller.initialize();
  });

  tearDown(() async {
    await dbService.close();
  });

  testWidgets('WeChat 4-tab shell, AI character creation entries, swipe actions, and ChatDetail render cleanly',
      (WidgetTester tester) async {
    await controller.createDirectConversation(
      title: '小喵助手',
      openingLine: '主人好喵~',
    );
    await tester.pumpWidget(AstideApp(controller: controller));
    await tester.pumpAndSettle();

    // Tab 1: 星汐 chat list with forced-pinned Astide conversation + second conversation, no top-left dots
    expect(find.text('星汐'), findsAtLeastNWidgets(1));
    expect(find.text('星汐 Astide'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_StatusDot'), findsNothing);
    expect(find.text('小喵助手'), findsOneWidget);
    expect(find.text('通讯录'), findsOneWidget);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('我'), findsOneWidget);

    // Navigate to 通讯录 -> direct access to AI one-sentence creation & manual form
    await tester.tap(find.text('通讯录'));
    await tester.pumpAndSettle();
    expect(find.text('一句话 AI 自动创建人物'), findsOneWidget);
    expect(find.text('手动填表新建人物'), findsOneWidget);

    // Navigate to 发现 -> pure WeChat Discover page with 朋友圈 only
    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    expect(find.text('朋友圈'), findsOneWidget);
    expect(find.text('导入 DeepSeek 官方历史记录'), findsNothing);
    expect(find.text('从预设模板快速创建'), findsNothing);
    expect(find.text('视频通话'), findsNothing);

    await tester.tap(find.text('朋友圈'));
    await tester.pumpAndSettle();
    expect(find.text('星汐 Astide'), findsAtLeastNWidgets(1));
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Navigate to 我 -> settings, autonomous mode & AGPL info (no roleplay switch)
    await tester.tap(find.text('我'));
    await tester.pumpAndSettle();
    expect(find.text('开启角色扮演'), findsNothing);
    expect(find.text('API 与模型设置'), findsOneWidget);
    expect(find.text('AI 自主发消息与常驻后台'), findsOneWidget);
    expect(find.text('关于星汐 Astide'), findsOneWidget);

    // Return to 星汐 chat list, test left-swipe on non-core conversation reveals 置顶 and 删除
    await tester.tap(find.text('星汐').last);
    await tester.pumpAndSettle();

    await tester.drag(find.text('小喵助手'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    final updatedSecond = controller.conversations.firstWhere((c) => c.title == '小喵助手');
    expect(updatedSecond.isPinned, isTrue);

    await tester.tap(find.text('星汐 Astide'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // Focus the composer input (simulating IME focus) before tapping opponent avatar.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // Double-tap opponent avatar triggers WeChat "拍一拍"
    final opponentAvatar = find.descendant(
      of: find.byType(ListView),
      matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ChatInteractiveAvatar'),
    );
    expect(opponentAvatar, findsOneWidget);
    await tester.tap(opponentAvatar);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(opponentAvatar);
    await tester.pumpAndSettle();
    expect(find.text('你拍了拍“星汐 Astide”'), findsOneWidget);

    // Single-tap opponent avatar opens 对方主页, then 发消息 returns back
    await tester.tap(opponentAvatar);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('对方主页'), findsOneWidget);
    expect(find.text('发消息'), findsOneWidget);
    await tester.tap(find.text('发消息'));
    await tester.pumpAndSettle();

    // Navigate back to 我 -> 本地存储与数据管理 -> 导出本地会话
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地存储与数据管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出本地会话记录'));
    await tester.pumpAndSettle();
    expect(find.text('SQLite 数据库 (.sqlite)'), findsOneWidget);
    expect(find.text('XML 文档 (.xml)'), findsOneWidget);
    expect(find.text('JSON 数据 (.json)'), findsOneWidget);
    expect(find.text('纯文本记录 (.txt)'), findsOneWidget);
  });
}
