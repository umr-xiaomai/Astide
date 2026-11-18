import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/repositories/character_repository.dart';
import 'data/repositories/chat_repository.dart';
import 'data/repositories/moments_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/autonomous_service.dart';
import 'data/services/character_generator_service.dart';
import 'data/services/chat_export_service.dart';
import 'data/services/context_compaction_service.dart';
import 'data/services/database_service.dart';
import 'data/services/deepseek_import_service.dart';
import 'data/services/file_extractor_service.dart';
import 'data/services/media_storage_service.dart';
import 'data/services/moments_ai_service.dart';
import 'data/services/openai_chat_service.dart';
import 'domain/models/api_profile.dart';
import 'domain/models/app_settings.dart';
import 'domain/models/character_profile.dart';
import 'domain/models/conversation.dart';
import 'domain/models/moment_post.dart';

/// Holds singleton services, repositories, and global reactive app state.
class AppController extends ChangeNotifier {
  AppController({
    required this.databaseService,
    required this.mediaStorage,
    required this.fileExtractor,
    required this.openAiChatService,
    required this.deepSeekImportService,
    required this.settingsRepository,
    required this.characterRepository,
    required this.chatRepository,
    MomentsRepository? momentsRepository,
    AutonomousService? autonomousService,
    CharacterGeneratorService? characterGeneratorService,
    ChatExportService? chatExportService,
    ContextCompactionService? contextCompactionService,
    MomentsAiService? momentsAiService,
  })  : momentsRepository = momentsRepository ?? MomentsRepository(databaseService: databaseService),
        contextCompactionService = contextCompactionService ??
            ContextCompactionService(
              chatRepository: chatRepository,
              openAiChatService: openAiChatService,
            ),
        characterGeneratorService = characterGeneratorService ??
            CharacterGeneratorService(openAiChatService: openAiChatService),
        chatExportService = chatExportService ??
            ChatExportService(sqliteFactoryOverride: databaseService.factoryOverride),
        momentsAiService = momentsAiService ??
            MomentsAiService(
              openAiChatService: openAiChatService,
              momentsRepository:
                  momentsRepository ?? MomentsRepository(databaseService: databaseService),
              characterRepository: characterRepository,
              chatRepository: chatRepository,
              mediaStorage: mediaStorage,
            ),
        autonomousService = autonomousService ??
            AutonomousService(
              openAiChatService: openAiChatService,
              chatRepository: chatRepository,
              characterRepository: characterRepository,
              momentsRepository:
                  momentsRepository ?? MomentsRepository(databaseService: databaseService),
              contextCompactionService: contextCompactionService ??
                  ContextCompactionService(
                    chatRepository: chatRepository,
                    openAiChatService: openAiChatService,
                  ),
            );

  factory AppController.createDefault() {
    final dbService = DatabaseService();
    final mediaStorage = MediaStorageService();
    final fileExtractor = FileExtractorService();
    final openAiChatService = OpenAiChatService(fileExtractor: fileExtractor);
    final deepSeekImportService = DeepSeekImportService(
      mediaStorage: mediaStorage,
      fileExtractor: fileExtractor,
    );
    final settingsRepo = SettingsRepository(databaseService: dbService);
    final charRepo = CharacterRepository(databaseService: dbService);
    final chatRepo = ChatRepository(databaseService: dbService);
    final momentsRepo = MomentsRepository(databaseService: dbService);
    final compaction = ContextCompactionService(
      chatRepository: chatRepo,
      openAiChatService: openAiChatService,
    );
    return AppController(
      databaseService: dbService,
      mediaStorage: mediaStorage,
      fileExtractor: fileExtractor,
      openAiChatService: openAiChatService,
      deepSeekImportService: deepSeekImportService,
      settingsRepository: settingsRepo,
      characterRepository: charRepo,
      chatRepository: chatRepo,
      momentsRepository: momentsRepo,
      contextCompactionService: compaction,
      momentsAiService: MomentsAiService(
        openAiChatService: openAiChatService,
        momentsRepository: momentsRepo,
        characterRepository: charRepo,
        chatRepository: chatRepo,
        mediaStorage: mediaStorage,
      ),
      autonomousService: AutonomousService(
        openAiChatService: openAiChatService,
        chatRepository: chatRepo,
        characterRepository: charRepo,
        momentsRepository: momentsRepo,
        contextCompactionService: compaction,
      ),
      characterGeneratorService: CharacterGeneratorService(
        openAiChatService: openAiChatService,
      ),
    );
  }

  final DatabaseService databaseService;
  final MediaStorageService mediaStorage;
  final FileExtractorService fileExtractor;
  final OpenAiChatService openAiChatService;
  final DeepSeekImportService deepSeekImportService;
  final SettingsRepository settingsRepository;
  final CharacterRepository characterRepository;
  final ChatRepository chatRepository;
  final MomentsRepository momentsRepository;
  final ContextCompactionService contextCompactionService;
  final MomentsAiService momentsAiService;
  final AutonomousService autonomousService;
  final CharacterGeneratorService characterGeneratorService;
  final ChatExportService chatExportService;

  final Uuid _uuid = const Uuid();

  bool _initialized = false;
  bool get initialized => _initialized;

  int _currentTabIndex = 0;
  int get currentTabIndex => _currentTabIndex;

  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;

  bool _appInBackground = false;
  bool get appInBackground => _appInBackground;

  int _autonomousUpdateEpoch = 0;
  int get autonomousUpdateEpoch => _autonomousUpdateEpoch;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  List<ApiProfile> _apiProfiles = const [];
  List<ApiProfile> get apiProfiles => _apiProfiles;

  ApiProfile? get activeApiProfile {
    for (final p in _apiProfiles) {
      if (p.isActive) return p;
    }
    return _apiProfiles.isNotEmpty ? _apiProfiles.first : null;
  }

  List<CharacterProfile> _characters = const [];
  List<CharacterProfile> get characters => _characters;

  List<Conversation> _conversations = const [];
  List<Conversation> get conversations => _conversations;

  List<MomentPost> _moments = const [];
  List<MomentPost> get moments => _moments;

  int _lastSeenMomentsMs = 0;

  MomentPost? get latestUnseenAiMoment {
    for (final m in _moments) {
      if (!m.isByUser && m.createdAt.millisecondsSinceEpoch > _lastSeenMomentsMs) {
        return m;
      }
    }
    return null;
  }

  int get totalUnreadCount =>
      _conversations.fold(0, (sum, c) => sum + (c.isMuted ? 0 : c.unreadCount));

  Future<void> initialize() async {
    await chatRepository.ensureInitialConversation();
    await momentsRepository.ensureInitialMoments();
    await reloadAll();
    await _syncAutonomousService();
    _initialized = true;
    notifyListeners();
  }

  void setActiveConversationId(String? conversationId) {
    _activeConversationId = conversationId;
  }

  void setAppInBackground(bool inBackground) {
    _appInBackground = inBackground;
  }

  Future<void> _syncAutonomousService() async {
    await autonomousService.syncWithSettings(
      settings: _settings,
      onScheduledTick: () async {
        await triggerAutonomousNow(forceSend: false);
        await maybePublishAutonomousMoment(forcePublish: false);
      },
    );
  }

  Future<MomentPost?> maybePublishAutonomousMoment({bool forcePublish = false}) async {
    final posted = await momentsAiService.maybePublishAiMoment(
      settings: _settings,
      activeProfile: activeApiProfile,
      forcePublish: forcePublish,
    );
    if (posted != null) {
      await reloadMoments();
    }
    return posted;
  }

  Future<void> reloadMoments() async {
    _moments = await momentsRepository.listMoments();
    _lastSeenMomentsMs = await momentsRepository.getLastSeenMomentsMs();
    notifyListeners();
  }

  Future<void> markMomentsSeen() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _lastSeenMomentsMs = nowMs;
    await momentsRepository.markMomentsSeen(nowMs);
    notifyListeners();
  }

  Future<AutonomousTriggerResult> triggerAutonomousNow({
    String? targetConversationId,
    bool forceSend = false,
  }) async {
    final res = await autonomousService.evaluateAndSend(
      settings: _settings,
      activeProfile: activeApiProfile,
      activeConversationId: _activeConversationId,
      appInBackground: _appInBackground,
      targetConversationId: targetConversationId,
      forceSend: forceSend,
    );
    if (res.sent) {
      _autonomousUpdateEpoch++;
      await reloadConversations();
    }
    return res;
  }

  Future<void> reloadAll() async {
    _settings = await settingsRepository.loadSettings();
    _apiProfiles = await settingsRepository.listApiProfiles();
    _characters = await characterRepository.listCharacters();
    _conversations = await chatRepository.listConversations();
    _moments = await momentsRepository.listMoments();
    _lastSeenMomentsMs = await momentsRepository.getLastSeenMomentsMs();
    notifyListeners();
  }

  Future<void> reloadConversations() async {
    _conversations = await chatRepository.listConversations();
    notifyListeners();
  }

  Future<void> reloadCharacters() async {
    _characters = await characterRepository.listCharacters();
    notifyListeners();
  }

  void setTabIndex(int index) {
    if (_currentTabIndex == index) return;
    _currentTabIndex = index;
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings updated) async {
    await settingsRepository.saveSettings(updated);
    _settings = updated;
    await _syncAutonomousService();
    notifyListeners();
  }

  /// Returns the single forced-pinned core 星汐 Astide conversation.
  Future<Conversation> getCoreAstideConversation() async {
    await chatRepository.ensureInitialConversation();
    await reloadConversations();
    for (final c in _conversations) {
      if (c.id == ChatRepository.coreAstideConversationId ||
          c.sourceType == ConversationSourceType.direct) {
        return c;
      }
    }
    return _conversations.first;
  }

  bool isCorePinnedConversation(Conversation conv) {
    if (conv.id == ChatRepository.coreAstideConversationId) return true;
    if (conv.sourceType != ConversationSourceType.direct) return false;
    final directConvs =
        _conversations.where((c) => c.sourceType == ConversationSourceType.direct).toList();
    return directConvs.isNotEmpty && directConvs.first.id == conv.id;
  }

  Future<void> saveApiProfile(ApiProfile profile) async {
    await settingsRepository.saveApiProfile(profile);
    _apiProfiles = await settingsRepository.listApiProfiles();
    notifyListeners();
  }

  Future<void> setActiveApiProfile(String id) async {
    await settingsRepository.setActiveApiProfile(id);
    _apiProfiles = await settingsRepository.listApiProfiles();
    notifyListeners();
  }

  Future<void> deleteApiProfile(String id) async {
    await settingsRepository.deleteApiProfile(id);
    _apiProfiles = await settingsRepository.listApiProfiles();
    notifyListeners();
  }

  Future<CharacterProfile> saveCharacter(CharacterProfile character) async {
    final saved = await characterRepository.saveCharacter(character);
    await reloadCharacters();
    await reloadConversations();
    return saved;
  }

  Future<void> deleteCharacter(String id) async {
    await characterRepository.deleteCharacter(id);
    await reloadCharacters();
  }

  Future<Conversation> createDirectConversation({
    String title = '星汐 Astide',
    String openingLine = '',
  }) async {
    final conv = await chatRepository.createConversation(
      title: title,
      sourceType: ConversationSourceType.direct,
      avatarColor: 0xFF07C160,
      openingLine: openingLine,
    );
    await reloadConversations();
    return conv;
  }

  Future<Conversation> openOrCreateCharacterConversation(CharacterProfile character) async {
    final conv = await chatRepository.openOrCreateCharacterConversation(character);
    await reloadConversations();
    return conv;
  }

  Future<void> togglePinConversation(Conversation conv) async {
    await chatRepository.updateConversation(conv.copyWith(isPinned: !conv.isPinned));
    await reloadConversations();
  }

  Future<void> toggleMuteConversation(Conversation conv) async {
    await chatRepository.updateConversation(conv.copyWith(isMuted: !conv.isMuted));
    await reloadConversations();
  }

  Future<void> deleteConversation(String id) async {
    await chatRepository.deleteConversation(id);
    await reloadConversations();
  }

  /// Exports selected (or all when [conversationIds] is null) conversations into [format].
  Future<ChatExportArtifact> exportConversations({
    required ChatExportFormat format,
    List<String>? conversationIds,
    bool includeReasoning = true,
  }) async {
    final bundles = await chatRepository.loadExportBundles(
      conversationIds: conversationIds,
    );
    return chatExportService.buildExport(
      format: format,
      bundles: bundles,
      settings: _settings,
      includeReasoning: includeReasoning,
    );
  }

  String newId() => _uuid.v4();
}

/// Exposes [AppController] to descendant widgets.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!.notifier!;
  }
}
