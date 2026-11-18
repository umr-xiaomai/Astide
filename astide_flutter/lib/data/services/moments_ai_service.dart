import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../../domain/models/api_profile.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/character_profile.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/moment_post.dart';
import '../repositories/character_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/moments_repository.dart';
import 'media_storage_service.dart';
import 'openai_chat_service.dart';

/// Drives AI autonomous Moment publishing (with web image / AI-drawn SVG), likes, and comment replies.
class MomentsAiService {
  MomentsAiService({
    required OpenAiChatService openAiChatService,
    required MomentsRepository momentsRepository,
    required CharacterRepository characterRepository,
    required ChatRepository chatRepository,
    MediaStorageService? mediaStorage,
    Dio? dio,
    Uuid? uuid,
  })  : _openAi = openAiChatService,
        _momentsRepo = momentsRepository,
        _charRepo = characterRepository,
        _chatRepo = chatRepository,
        _mediaStorage = mediaStorage ?? MediaStorageService(),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 8),
              ),
            ),
        _uuid = uuid ?? const Uuid();

  final OpenAiChatService _openAi;
  final MomentsRepository _momentsRepo;
  final CharacterRepository _charRepo;
  final ChatRepository _chatRepo;
  final MediaStorageService _mediaStorage;
  final Dio _dio;
  final Uuid _uuid;
  final Random _random = Random();

  bool _isPublishing = false;
  DateTime? _lastAutoPostCheck;

  /// Evaluates time-of-day, recent chats, and character mood to optionally publish an AI Moment.
  Future<MomentPost?> maybePublishAiMoment({
    required AppSettings settings,
    required ApiProfile? activeProfile,
    bool forcePublish = false,
  }) async {
    if (_isPublishing) return null;
    if (activeProfile == null || !activeProfile.isConfigured) return null;

    final now = DateTime.now();
    if (!forcePublish && settings.quietHoursEnabled && now.hour >= 1 && now.hour < 7) {
      return null;
    }

    if (!forcePublish &&
        _lastAutoPostCheck != null &&
        now.difference(_lastAutoPostCheck!).inMinutes < 60) {
      return null;
    }

    final existing = await _momentsRepo.listMoments(limit: 20);
    final aiPosts = existing.where((m) => !m.isByUser).toList();
    final recentAiPost = aiPosts.firstOrNull;
    if (!forcePublish &&
        recentAiPost != null &&
        now.difference(recentAiPost.createdAt).inHours < 4) {
      return null;
    }
    final todayCount = aiPosts.where((m) {
      final t = m.createdAt;
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).length;
    if (!forcePublish && todayCount >= 3) {
      return null;
    }

    _isPublishing = true;
    _lastAutoPostCheck = now;
    try {
      final characters = await _charRepo.listCharacters();
      // Candidate pool includes core 星汐 Astide + user-created characters.
      final useCore = characters.isEmpty || _random.nextInt(characters.length + 1) == 0;
      final CharacterProfile? chosenChar =
          useCore ? null : characters[_random.nextInt(characters.length)];

      final authorId = chosenChar?.id ?? 'astide_core';
      final authorName = chosenChar?.displayName ?? '星汐 Astide';
      final authorAvatar = chosenChar != null
          ? chosenChar.avatarPath
          : 'asset:assets/images/astide_avatar.jpg';
      final authorColor = chosenChar?.avatarColor ?? 0xFF07C160;

      // Load recent chat context if available so the Moment reflects lived continuity.
      var chatContextSnippet = '';
      if (chosenChar != null) {
        final conv = await _chatRepo.findConversationByCharacterId(chosenChar.id);
        if (conv != null) {
          final page = await _chatRepo.listMessagesPage(conv.id, limit: 6);
          chatContextSnippet = page.messages
              .map((m) => '${m.isUser ? settings.userNickname : authorName}: ${m.content}')
              .join('\n');
        }
      } else {
        final page =
            await _chatRepo.listMessagesPage(ChatRepository.coreAstideConversationId, limit: 6);
        chatContextSnippet = page.messages
            .map((m) => '${m.isUser ? settings.userNickname : authorName}: ${m.content}')
            .join('\n');
      }

      final systemPrompt = chosenChar != null
          ? chosenChar.buildEffectiveSystemPrompt(
              userNickname: settings.userNickname,
              userPersona: settings.userPersona,
            )
          : settings.defaultAssistantPrompt;

      final prompt = _buildMomentPrompt(
        now: now,
        authorName: authorName,
        recentChat: chatContextSnippet,
        forcePublish: forcePublish,
      );

      final fastProfile = activeProfile.copyWith(supportsReasoning: false, streamEnabled: false);
      final buf = StringBuffer();
      await for (final delta in _openAi.streamChatCompletion(
        profile: fastProfile,
        systemPrompt: systemPrompt,
        history: [
          ChatMessage(
            id: 'moment_gen_${now.millisecondsSinceEpoch}',
            conversationId: 'moments',
            role: MessageRole.user,
            content: prompt,
            createdAt: now,
          ),
        ],
        maxTokens: 1200,
        forceNonStreaming: true,
      )) {
        buf.write(delta.contentDelta);
      }

      final raw = buf.toString().trim();
      if (raw.isEmpty || raw.toUpperCase().contains('[SKIP]')) {
        return null;
      }

      var content = raw;
      var selfComment = '';
      var imageUrl = '';
      var imageSvg = '';
      try {
        final cleaned = _extractJsonObject(raw);
        if (cleaned != null) {
          final map = jsonDecode(cleaned) as Map<String, dynamic>;
          content = (map['content']?.toString() ?? '').trim();
          selfComment = (map['self_comment']?.toString() ?? '').trim();
          imageUrl = (map['image_url']?.toString() ?? '').trim();
          imageSvg = (map['image_svg']?.toString() ?? '').trim();
        }
      } catch (_) {}

      content = content.replaceAll('|||', '').trim();
      selfComment = selfComment.replaceAll('|||', '').trim();
      if (content.isEmpty || content.toUpperCase().contains('[SKIP]')) return null;

      final attachedImages = <String>[];
      final savedImage = await _resolveMomentImage(
        imageUrl: imageUrl,
        imageSvg: imageSvg,
      );
      if (savedImage != null) {
        attachedImages.add(savedImage);
      }

      final momentId = _uuid.v4();
      final post = MomentPost(
        id: momentId,
        authorId: authorId,
        authorName: authorName,
        authorAvatarPath: authorAvatar,
        authorAvatarColor: authorColor,
        content: content,
        imagePaths: attachedImages,
        likedByNames: _random.nextBool() ? [authorName] : const [],
        createdAt: now,
      );
      await _momentsRepo.insertMoment(post);

      if (selfComment.isNotEmpty) {
        await _momentsRepo.addComment(MomentComment(
          id: _uuid.v4(),
          momentId: momentId,
          authorId: authorId,
          authorName: authorName,
          content: selfComment,
          createdAt: now.add(const Duration(seconds: 2)),
        ));
      }

      return await _momentsRepo.getMoment(momentId);
    } catch (_) {
      return null;
    } finally {
      _isPublishing = false;
    }
  }

  /// Generates natural likes & comments from 星汐 / characters when the user posts a Moment.
  Future<void> reactToUserMoment({
    required MomentPost userPost,
    required AppSettings settings,
    required ApiProfile? activeProfile,
  }) async {
    if (activeProfile == null || !activeProfile.isConfigured) return;

    final characters = await _charRepo.listCharacters();
    final responders = <({String id, String name, String prompt})>[
      (id: 'astide_core', name: '星汐 Astide', prompt: settings.defaultAssistantPrompt),
      for (final c in characters.take(2))
        (
          id: c.id,
          name: c.displayName,
          prompt: c.buildEffectiveSystemPrompt(
            userNickname: settings.userNickname,
            userPersona: settings.userPersona,
          ),
        ),
    ];

    final fastProfile = activeProfile.copyWith(supportsReasoning: false, streamEnabled: false);

    for (final actor in responders) {
      try {
        final now = DateTime.now();
        final buf = StringBuffer();
        await for (final delta in _openAi.streamChatCompletion(
          profile: fastProfile,
          systemPrompt: actor.prompt,
          history: [
            ChatMessage(
              id: 'm_react_${now.millisecondsSinceEpoch}',
              conversationId: 'moments',
              role: MessageRole.user,
              content: '对方刚发了一条微信朋友圈：「${userPost.content}」'
                  '${userPost.imagePaths.isNotEmpty ? '（附带了 ${userPost.imagePaths.length} 张照片）' : ''}。'
                  '请以你的人设决定是否点赞并留一条简短真实的微信朋友圈评论（不超过40字）。'
                  '严格输出 JSON：{"like": true, "comment": "你的评论，不评论则留空字符串"}',
              createdAt: now,
            ),
          ],
          maxTokens: 120,
          forceNonStreaming: true,
        )) {
          buf.write(delta.contentDelta);
        }
        final jsonStr = _extractJsonObject(buf.toString());
        if (jsonStr == null) continue;
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final like = map['like'] == true;
        final commentText = (map['comment']?.toString() ?? '').trim();

        if (like) {
          final current = await _momentsRepo.getMoment(userPost.id);
          if (current != null && !current.likedByNames.contains(actor.name)) {
            await _momentsRepo.toggleLike(momentId: userPost.id, likerName: actor.name);
          }
        }
        if (commentText.isNotEmpty) {
          await _momentsRepo.addComment(MomentComment(
            id: _uuid.v4(),
            momentId: userPost.id,
            authorId: actor.id,
            authorName: actor.name,
            content: commentText,
            createdAt: DateTime.now(),
          ));
        }
      } catch (_) {}
    }
  }

  /// Generates an in-character reply when the user comments on an AI character's Moment.
  Future<void> replyToUserComment({
    required MomentPost post,
    required MomentComment userComment,
    required AppSettings settings,
    required ApiProfile? activeProfile,
  }) async {
    if (post.isByUser || activeProfile == null || !activeProfile.isConfigured) return;

    CharacterProfile? character;
    if (post.authorId != 'astide_core') {
      character = await _charRepo.getCharacter(post.authorId);
    }

    final sysPrompt = character != null
        ? character.buildEffectiveSystemPrompt(
            userNickname: settings.userNickname,
            userPersona: settings.userPersona,
          )
        : settings.defaultAssistantPrompt;

    try {
      final fastProfile = activeProfile.copyWith(supportsReasoning: false, streamEnabled: false);
      final now = DateTime.now();
      final buf = StringBuffer();
      await for (final delta in _openAi.streamChatCompletion(
        profile: fastProfile,
        systemPrompt: sysPrompt,
        history: [
          ChatMessage(
            id: 'm_reply_${now.millisecondsSinceEpoch}',
            conversationId: 'moments',
            role: MessageRole.user,
            content: '你在朋友圈发了一条动态：「${post.content}」。'
                '现在「${settings.userNickname}」评论了你：「${userComment.content}」。'
                '请以你自己的微信好友身份简短自然地回复他一条朋友圈评论（直接输出回复文字，不要带引号，35字以内）。',
            createdAt: now,
          ),
        ],
        maxTokens: 100,
        forceNonStreaming: true,
      )) {
        buf.write(delta.contentDelta);
      }

      final text = buf.toString().trim();
      if (text.isEmpty) return;
      await _momentsRepo.addComment(MomentComment(
        id: _uuid.v4(),
        momentId: post.id,
        authorId: post.authorId,
        authorName: post.authorName,
        replyToName: settings.userNickname,
        content: text,
        createdAt: DateTime.now(),
      ));
    } catch (_) {}
  }

  String _buildMomentPrompt({
    required DateTime now,
    required String authorName,
    required String recentChat,
    required bool forcePublish,
  }) {
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final timeStr = '${DateFormat('yyyy年MM月dd日 HH:mm').format(now)}（${weekdays[now.weekday - 1]}）';
    final period = _momentMoodHint(now.hour);

    return '现在时间是 $timeStr（$period）。你是「$authorName」，想发一条真实自然的微信朋友圈。\n'
        '${recentChat.isNotEmpty ? '【最近和对方的聊天参考】\n$recentChat\n\n' : ''}'
        '创作场景建议：$period。\n'
        '${forcePublish ? '请一定生成一条适合现在发的朋友圈动态。' : '如果当前确实适合发一条生活感慨或日常分享就生成，否则回复 [SKIP]。'}\n'
        '你还可以选择给这条朋友圈配一张图片（约60%概率配图）：\n'
        '- 推荐在 `image_svg` 字段里直接手绘一张精美且有氛围感的 SVG 矢量插画（`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300">...</svg>`，可用渐变、月亮/晚霞/茶杯/窗户/猫咪/耳机/星空等简洁形状营造生活画面，纯标准 SVG 元素，不要 `<image>` 外链）；\n'
        '- 或者如果你确认有一个公开可直连访问的图片直链，也可填在 `image_url`（若不需要配图两项都留空字符串）。\n'
        '严格输出 JSON（不要额外文字）：\n'
        '{"content": "朋友圈正文（真实口语/心情碎片/生活细节，1~4句话，绝不出现AI字样）", "self_comment": "可选的作者自己补刀评论，不需要就留空字符串", "image_url": "", "image_svg": ""}';
  }

  Future<String?> _resolveMomentImage({
    required String imageUrl,
    required String imageSvg,
  }) async {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      try {
        final resp = await _dio.get<List<int>>(
          imageUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        final contentType = (resp.headers.value('content-type') ?? '').toLowerCase();
        final data = resp.data;
        if (resp.statusCode == 200 &&
            data != null &&
            data.length > 512 &&
            (contentType.startsWith('image/') ||
                imageUrl.toLowerCase().endsWith('.jpg') ||
                imageUrl.toLowerCase().endsWith('.png') ||
                imageUrl.toLowerCase().endsWith('.webp'))) {
          final ext = contentType.contains('png')
              ? '.png'
              : (contentType.contains('webp') ? '.webp' : '.jpg');
          return await _mediaStorage.saveBytes(
            Uint8List.fromList(data),
            fileName: 'moment$ext',
            category: 'images',
          );
        }
      } catch (_) {}
    }

    if (imageSvg.isNotEmpty) {
      final start = imageSvg.indexOf('<svg');
      final end = imageSvg.lastIndexOf('</svg>');
      if (start >= 0 && end > start) {
        final cleanSvg = imageSvg.substring(start, end + '</svg>'.length);
        try {
          // Ensure valid XML so flutter_svg renders reliably.
          XmlDocument.parse(cleanSvg);
          return await _mediaStorage.saveBytes(
            Uint8List.fromList(utf8.encode(cleanSvg)),
            fileName: 'moment.svg',
            category: 'images',
          );
        } catch (_) {}
      }
    }
    return null;
  }

  String _momentMoodHint(int hour) {
    if (hour >= 0 && hour < 6) return '凌晨夜深人静，适合微小的失眠感叹、听歌情绪或熬夜日常';
    if (hour < 9) return '早晨刚醒或出门路上，适合早安、早餐、天气或今天的小计划';
    if (hour < 12) return '上午忙碌间隙，适合摸鱼吐槽、咖啡/茶或手头的小事';
    if (hour < 14) return '中午饭点与午休，适合分享午饭、犯困或阳光';
    if (hour < 18) return '下午时光，适合偶遇的趣事、歌单或期待下班/放学';
    if (hour < 21) return '傍晚与晚饭后，适合落日、散步、追剧或一天总结';
    return '夜晚临睡前，适合柔软碎碎念、反思或和世界道晚安';
  }

  String? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return raw.substring(start, end + 1);
    }
    return null;
  }
}
