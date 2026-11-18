import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/api_profile.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/character_profile.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/conversation.dart';
import '../repositories/character_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/moments_repository.dart';
import 'context_compaction_service.dart';
import 'openai_chat_service.dart';

/// Result returned by an autonomous proactive-messaging evaluation cycle.
class AutonomousTriggerResult {
  const AutonomousTriggerResult({
    required this.sent,
    this.skipped = false,
    this.conversationTitle = '',
    this.preview = '',
    this.reason = '',
  });

  final bool sent;
  final bool skipped;
  final String conversationTitle;
  final String preview;
  final String reason;
}

/// Manages background residency service, periodic time/context evaluation, and proactive WeChat messages.
class AutonomousService {
  AutonomousService({
    required OpenAiChatService openAiChatService,
    required ChatRepository chatRepository,
    required CharacterRepository characterRepository,
    MomentsRepository? momentsRepository,
    ContextCompactionService? contextCompactionService,
    Random? random,
    Uuid? uuid,
  })  : _openAi = openAiChatService,
        _chatRepo = chatRepository,
        _charRepo = characterRepository,
        _momentsRepo = momentsRepository,
        _compaction = contextCompactionService ??
            ContextCompactionService(
              chatRepository: chatRepository,
              openAiChatService: openAiChatService,
            ),
        _random = random ?? Random(),
        _uuid = uuid ?? const Uuid();

  static const MethodChannel _channel = MethodChannel('com.hoilai.mm.astide/background');

  final OpenAiChatService _openAi;
  final ChatRepository _chatRepo;
  final CharacterRepository _charRepo;
  final MomentsRepository? _momentsRepo;
  final ContextCompactionService _compaction;
  final Uuid _uuid;
  final Random _random;

  Timer? _timer;
  bool _isRunningCheck = false;
  DateTime? _lastTriggerAt;

  /// Syncs Android Foreground Service and periodic Dart evaluation timer with [settings].
  Future<void> syncWithSettings({
    required AppSettings settings,
    required Future<void> Function() onScheduledTick,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        if (settings.keepAliveEnabled) {
          await _channel.invokeMethod<bool>('requestNotificationPermission');
          await _channel.invokeMethod<bool>('startKeepAlive');
        } else {
          await _channel.invokeMethod<bool>('stopKeepAlive');
        }
      } on MissingPluginException {
        // Ignore in headless unit/widget tests.
      } catch (_) {}
    }

    _timer?.cancel();
    _timer = null;

    if (settings.autonomousEnabled) {
      final intervalMin = settings.autonomousIntervalMinutes.clamp(5, 720);
      _timer = Timer.periodic(Duration(minutes: intervalMin), (_) {
        unawaited(onScheduledTick());
      });
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel.invokeMethod<bool>('requestNotificationPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  Future<void> triggerPokeVibration() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<bool>('pokeHaptic');
    } catch (_) {}
  }

  Future<void> showNotification({
    required String title,
    required String body,
    required int notificationId,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<bool>('showMessageNotification', {
        'title': title,
        'body': body,
        'notificationId': notificationId,
      });
    } catch (_) {}
  }

  static const String continuationUserPrompt =
      '（微信连发消息判断：你刚发送了上面那条消息。像真人在微信里连续发两三条短消息那样，如果你还想紧接着立刻补充发送下一条简短自然的话，请直接写出下一条消息正文；如果话已经说完了，请只回复 [DONE]）';

  /// Parses optional `[POKE_BACK]` and `[DONE]` / `[SKIP]` control tokens from one single-bubble AI reply.
  static ({bool pokedBack, bool isDoneOrSkip, String text}) parseSingleReply(String rawReply) {
    final trimmed = rawReply.trim();
    if (trimmed.isEmpty) {
      return (pokedBack: false, isDoneOrSkip: true, text: '');
    }
    final upper = trimmed.toUpperCase();
    if (upper == '[SKIP]' || upper == '[DONE]' || upper == 'SKIP' || upper == 'DONE') {
      return (pokedBack: false, isDoneOrSkip: true, text: '');
    }
    final pokedBack = RegExp(r'\[POKE_BACK\]', caseSensitive: false).hasMatch(trimmed);
    var cleaned = trimmed
        .replaceAll(RegExp(r'\[POKE_BACK\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[DONE\]|\[SKIP\]', caseSensitive: false), '')
        .trim();
    final isDoneOrSkip = cleaned.isEmpty && !pokedBack;
    return (pokedBack: pokedBack, isDoneOrSkip: isDoneOrSkip, text: cleaned);
  }

  /// Evaluates time-of-day, silence duration, and conversation context using sequential requests (1..3 bubbles).
  Future<AutonomousTriggerResult> evaluateAndSend({
    required AppSettings settings,
    required ApiProfile? activeProfile,
    String? activeConversationId,
    bool appInBackground = false,
    String? targetConversationId,
    bool forceSend = false,
  }) async {
    if (_isRunningCheck) {
      return const AutonomousTriggerResult(sent: false, reason: '已有自主思考任务正在执行中');
    }
    if (activeProfile == null || !activeProfile.isConfigured) {
      return const AutonomousTriggerResult(sent: false, reason: '尚未配置有效的 API Key');
    }

    final now = DateTime.now();
    if (!forceSend && settings.quietHoursEnabled && now.hour >= 0 && now.hour < 7) {
      return const AutonomousTriggerResult(sent: false, skipped: true, reason: '当前处于夜间免打扰时段');
    }

    if (!forceSend &&
        _lastTriggerAt != null &&
        now.difference(_lastTriggerAt!).inMinutes <
            (settings.autonomousIntervalMinutes - 1).clamp(1, 720)) {
      return const AutonomousTriggerResult(sent: false, skipped: true, reason: '距离上次触发间隔较短');
    }

    if (!forceSend) {
      final prob = settings.autonomousProbability.clamp(0.0, 1.0);
      if (prob <= 0 || _random.nextDouble() >= prob) {
        return AutonomousTriggerResult(
          sent: false,
          skipped: true,
          reason: '本次未命中自主触发概率 (${(prob * 100).round()}%)',
        );
      }
    }

    _isRunningCheck = true;
    try {
      final allConvs = await _chatRepo.listConversations();
      final eligible = allConvs.where((c) {
        if (targetConversationId != null) return c.id == targetConversationId;
        if (c.isMuted) return false;
        return c.sourceType == ConversationSourceType.direct ||
            c.sourceType == ConversationSourceType.roleplay;
      }).toList();

      if (eligible.isEmpty) {
        return const AutonomousTriggerResult(sent: false, reason: '暂无可主动发消息的活跃联系人');
      }

      // Prefer conversations that haven't had recent messages, with a bit of randomness.
      eligible.sort((a, b) => a.lastMessageAt.compareTo(b.lastMessageAt));
      final poolSize = eligible.length > 3 ? 3 : eligible.length;
      final picked = targetConversationId != null
          ? eligible.first
          : eligible[_random.nextInt(poolSize)];

      // Skip automatic check if user literally just chatted within 5 minutes.
      if (!forceSend && now.difference(picked.lastMessageAt).inMinutes < 5) {
        return const AutonomousTriggerResult(sent: false, skipped: true, reason: '刚刚才聊过');
      }

      CharacterProfile? character;
      if (picked.characterId != null) {
        character = await _charRepo.getCharacter(picked.characterId!);
      }

      final compacted = await _compaction.prepareContext(
        conversationId: picked.id,
        profile: activeProfile,
      );
      final momentsSnippet = _momentsRepo != null
          ? await _momentsRepo.buildMomentsContextSnippet(characterId: character?.id)
          : '';
      var systemPrompt = ContextCompactionService.mergeSystemPrompt(
        _buildSystemPrompt(settings, character),
        compacted.summary,
      );
      if (momentsSnippet.isNotEmpty) {
        systemPrompt = '$systemPrompt\n\n$momentsSnippet';
      }
      final triggerPrompt = _buildTriggerPrompt(
        now: now,
        conversation: picked,
        forceSend: forceSend,
      );

      final fastProfile = activeProfile.copyWith(supportsReasoning: false, streamEnabled: false);
      final ephemeralHistory = <ChatMessage>[
        ...compacted.recentMessages,
        ChatMessage(
          id: 'auto_trigger_${now.millisecondsSinceEpoch}',
          conversationId: picked.id,
          role: MessageRole.user,
          content: triggerPrompt,
          createdAt: now,
        ),
      ];

      final firstRaw = await _requestSingleReply(
        profile: fastProfile,
        history: ephemeralHistory,
        systemPrompt: systemPrompt,
        modelOverride: character?.modelOverride,
      );

      _lastTriggerAt = now;
      if (firstRaw.toUpperCase().contains('[SKIP]')) {
        return AutonomousTriggerResult(
          sent: false,
          skipped: true,
          conversationTitle: picked.title,
          reason: 'AI 判断当前无需打扰',
        );
      }

      final firstParsed = parseSingleReply(firstRaw);
      if (firstParsed.isDoneOrSkip && !firstParsed.pokedBack) {
        return AutonomousTriggerResult(
          sent: false,
          skipped: true,
          conversationTitle: picked.title,
          reason: 'AI 判断当前无需打扰',
        );
      }

      final targetLabel = character?.displayName ?? picked.title;
      final segments = <String>[];
      var insertedCount = 0;

      if (firstParsed.pokedBack) {
        await _chatRepo.insertMessage(
          ChatMessage(
            id: _uuid.v4(),
            conversationId: picked.id,
            role: MessageRole.system,
            content: '“$targetLabel” 拍了拍你',
            status: MessageStatus.sent,
            createdAt: now,
          ),
        );
        insertedCount++;
      }

      if (firstParsed.text.isNotEmpty) {
        segments.add(firstParsed.text);
        final firstMsg = ChatMessage(
          id: _uuid.v4(),
          conversationId: picked.id,
          role: MessageRole.assistant,
          content: firstParsed.text,
          status: MessageStatus.sent,
          createdAt: now.add(const Duration(milliseconds: 15)),
        );
        await _chatRepo.insertMessage(firstMsg);
        ephemeralHistory.add(firstMsg);
        insertedCount++;

        // Sequential follow-up requests (up to 2 extra short bubbles) without any delimiter hacks.
        for (var extra = 1; extra <= 2; extra++) {
          if (_random.nextDouble() >= 0.65) break;
          final followAt = now.add(Duration(milliseconds: (extra + 1) * 15));
          final followHistory = <ChatMessage>[
            ...ephemeralHistory,
            ChatMessage(
              id: 'auto_cont_${now.millisecondsSinceEpoch}_$extra',
              conversationId: picked.id,
              role: MessageRole.user,
              content: continuationUserPrompt,
              createdAt: followAt,
            ),
          ];
          final nextRaw = await _requestSingleReply(
            profile: fastProfile,
            history: followHistory,
            systemPrompt: systemPrompt,
            modelOverride: character?.modelOverride,
          );
          final nextParsed = parseSingleReply(nextRaw);
          if (nextParsed.isDoneOrSkip || nextParsed.text.isEmpty) break;

          segments.add(nextParsed.text);
          final nextMsg = ChatMessage(
            id: _uuid.v4(),
            conversationId: picked.id,
            role: MessageRole.assistant,
            content: nextParsed.text,
            status: MessageStatus.sent,
            createdAt: followAt,
          );
          await _chatRepo.insertMessage(nextMsg);
          ephemeralHistory.add(nextMsg);
          insertedCount++;
        }
      }

      final previewBody = segments.isNotEmpty
          ? segments.join(' ')
          : '“$targetLabel” 拍了拍你';
      final isCurrentlyViewing = !appInBackground && activeConversationId == picked.id;
      if (!isCurrentlyViewing) {
        final fresh = await _chatRepo.getConversation(picked.id);
        if (fresh != null) {
          await _chatRepo.updateConversation(
            fresh.copyWith(unreadCount: fresh.unreadCount + insertedCount),
          );
        }
        await showNotification(
          title: picked.title,
          body: previewBody,
          notificationId: picked.id.hashCode & 0x7FFFFFFF,
        );
      }

      return AutonomousTriggerResult(
        sent: true,
        conversationTitle: picked.title,
        preview: segments.isNotEmpty ? segments.join(' / ') : previewBody,
      );
    } catch (e) {
      return AutonomousTriggerResult(
        sent: false,
        reason: e.toString().replaceFirst('HttpException: ', ''),
      );
    } finally {
      _isRunningCheck = false;
    }
  }

  Future<String> _requestSingleReply({
    required ApiProfile profile,
    required List<ChatMessage> history,
    required String systemPrompt,
    String? modelOverride,
  }) async {
    final buf = StringBuffer();
    await for (final delta in _openAi.streamChatCompletion(
      profile: profile,
      history: history,
      systemPrompt: systemPrompt,
      modelOverride: modelOverride,
      maxTokens: 150,
      forceNonStreaming: true,
    )) {
      buf.write(delta.contentDelta);
    }
    return buf.toString().trim();
  }

  String _buildSystemPrompt(AppSettings settings, CharacterProfile? character) {
    if (character != null) {
      return character.buildEffectiveSystemPrompt(
        userNickname: settings.userNickname,
        userPersona: settings.userPersona,
      );
    }
    return settings.defaultAssistantPrompt;
  }

  String _buildTriggerPrompt({
    required DateTime now,
    required Conversation conversation,
    required bool forceSend,
  }) {
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final timeStr = '${DateFormat('yyyy年MM月dd日 HH:mm').format(now)}（${weekdays[now.weekday - 1]}）';
    final period = _timePeriodLabel(now.hour);
    final gap = now.difference(conversation.lastMessageAt);
    final gapText = _formatGap(gap);

    if (forceSend) {
      return '【系统自主意识触发】现在时间是 $timeStr（$period），距离你们上次聊天过去了 $gapText。'
          '请完全以你自己的真实人类身份主动给对方发一条简短自然的微信消息（如结合当前时间问候、分享你手头刚刚发生的小事、或顺着上次聊过的话题关心对方）。'
          '一次只发一条短句即可（如需先在微信里“拍一拍”对方再开口，可在最开头加上 [POKE_BACK]）。不要说你是AI，不要解释原因。';
    }

    return '【系统自主意识巡检】现在时间是 $timeStr（$period），距离你们上次聊天已经过去了 $gapText。'
        '请结合当前时间点、你们的关系和上方聊天上下文，自主决定此刻是否应该主动给对方发微信：'
        '如果你觉得现在适合发消息（比如早晨问安、饭点关心、晚间分享生活琐事、夜深提醒休息或惦记对方），请直接发送一条自然真实的微信短消息（可选在开头加 [POKE_BACK] 拍一拍对方）；'
        '如果你觉得此时发消息不太合适（比如刚聊完没多久或深夜不打扰），请仅回复 [SKIP]。';
  }

  String _timePeriodLabel(int hour) {
    if (hour < 6) return '凌晨';
    if (hour < 9) return '早晨';
    if (hour < 12) return '上午';
    if (hour < 14) return '中午';
    if (hour < 18) return '下午';
    if (hour < 22) return '晚上';
    return '深夜';
  }

  String _formatGap(Duration d) {
    if (d.inMinutes < 1) return '不到1分钟';
    if (d.inHours < 1) return '${d.inMinutes}分钟';
    if (d.inDays < 1) return '${d.inHours}小时${d.inMinutes % 60}分钟';
    return '${d.inDays}天${d.inHours % 24}小时';
  }

  void dispose() {
    _timer?.cancel();
  }
}
