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
        _uuid = uuid ?? const Uuid();

  static const MethodChannel _channel = MethodChannel('com.hoilai.mm.astide/background');

  final OpenAiChatService _openAi;
  final ChatRepository _chatRepo;
  final CharacterRepository _charRepo;
  final MomentsRepository? _momentsRepo;
  final ContextCompactionService _compaction;
  final Uuid _uuid;
  final Random _random = Random();

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

  /// Evaluates time-of-day, silence duration, and conversation context to optionally send 1..3 messages.
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

      final rawBuf = StringBuffer();
      await for (final delta in _openAi.streamChatCompletion(
        profile: activeProfile,
        history: ephemeralHistory,
        systemPrompt: systemPrompt,
        modelOverride: character?.modelOverride,
        maxTokens: 220,
        forceNonStreaming: true,
      )) {
        rawBuf.write(delta.contentDelta);
      }

      _lastTriggerAt = now;
      final reply = rawBuf.toString().trim();
      if (reply.isEmpty || reply.toUpperCase().contains('[SKIP]')) {
        return AutonomousTriggerResult(
          sent: false,
          skipped: true,
          conversationTitle: picked.title,
          reason: 'AI 判断当前无需打扰',
        );
      }

      final segments = reply
          .split('|||')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(4)
          .toList();
      if (segments.isEmpty) {
        return const AutonomousTriggerResult(sent: false, skipped: true, reason: '未生成有效消息');
      }

      for (var i = 0; i < segments.length; i++) {
        final msg = ChatMessage(
          id: _uuid.v4(),
          conversationId: picked.id,
          role: MessageRole.assistant,
          content: segments[i],
          status: MessageStatus.sent,
          createdAt: now.add(Duration(milliseconds: i * 15)),
        );
        await _chatRepo.insertMessage(msg);
      }

      final isCurrentlyViewing = !appInBackground && activeConversationId == picked.id;
      if (!isCurrentlyViewing) {
        final fresh = await _chatRepo.getConversation(picked.id);
        if (fresh != null) {
          await _chatRepo.updateConversation(
            fresh.copyWith(unreadCount: fresh.unreadCount + segments.length),
          );
        }
        await showNotification(
          title: picked.title,
          body: segments.join(' '),
          notificationId: picked.id.hashCode & 0x7FFFFFFF,
        );
      }

      return AutonomousTriggerResult(
        sent: true,
        conversationTitle: picked.title,
        preview: segments.join(' / '),
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
          '请完全以你自己的真实人类身份主动给对方发微信（如结合当前时间问候、分享你手头刚刚发生的小事、或顺着上次聊过的话题关心对方）。'
          '请自由选择发送 1~3 条自然的微信短气泡消息（多条用 ||| 分隔），不要说你是AI，不要解释原因。';
    }

    return '【系统自主意识巡检】现在时间是 $timeStr（$period），距离你们上次聊天已经过去了 $gapText。'
        '请结合当前时间点、你们的关系和上方聊天上下文，自主决定此刻是否应该主动给对方发微信：'
        '如果你觉得现在适合发消息（比如早晨问安、饭点关心、晚间分享生活琐事、夜深提醒休息或惦记对方），请直接发送 1~3 条自然真实的微信短消息（多条用 ||| 分隔）；'
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
