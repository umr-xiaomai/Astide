import 'dart:convert';

import '../../domain/models/api_profile.dart';
import '../../domain/models/character_profile.dart';
import '../../domain/models/chat_message.dart';
import 'openai_chat_service.dart';

/// Generates structured [CharacterProfile] fields from a one-sentence description or prompt via LLM.
class CharacterGeneratorService {
  CharacterGeneratorService({required OpenAiChatService openAiChatService})
      : _openAi = openAiChatService;

  final OpenAiChatService _openAi;

  static const List<int> paletteColors = [
    0xFF07C160,
    0xFF10AEFF,
    0xFF576B95,
    0xFFFA9D3B,
    0xFF6467F0,
    0xFFFA5151,
  ];

  /// Calls the active LLM to read [promptOrIdea] and fill out all character form fields.
  Future<CharacterProfile> generateFromPrompt({
    required ApiProfile profile,
    required String promptOrIdea,
    required String newId,
  }) async {
    if (!profile.isConfigured) {
      throw const FormatException('请先在“我 -> API 与模型设置”中填写 API Key 再使用 AI 自动填表');
    }
    final trimmed = promptOrIdea.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('请先输入一句话描述或角色提示词');
    }

    const systemInstruction = '''
你是一个专业的微信角色卡片设计师。用户会给你一句话或一段完整的人物提示词。
请你阅读并理解用户的全部要求（包括人设、称呼、口癖、边界规则和示例），然后提取并补全成一个结构化的微信角色表单 JSON。
必须严格只输出合法的 JSON 对象，不要输出任何额外说明或多余文字。字段要求如下：
{
  "name": "人物姓名或昵称（必填，简短好记）",
  "remark": "微信备注（可选，简短）",
  "gender": "性别",
  "age": "年龄",
  "occupation": "身份或职业",
  "relationship": "与用户的关系（如：可爱助手、朋友、学姐等）",
  "personality": "性格特点总结",
  "backstory": "背景设定与日常状态",
  "speech_style": "说话风格、口癖与对用户的称呼",
  "opening_line": "初次见面的微信开场白（可用 ||| 分成1~2条自然短句）",
  "segmented_reply": true,
  "avatar_color_index": 0,
  "system_prompt": "完整保留用户原提示词里的所有细节、规则、边界和示例，并整理成可直接用于对话的系统人设指令"
}
注意：avatar_color_index 为 0 到 5 的整数（0绿 1蓝 2青灰 3橙 4紫 5红）。''';

    // Temporarily ensure non-reasoning fast call when generating JSON form fields.
    final jsonProfile = profile.copyWith(supportsReasoning: false, streamEnabled: false);
    final rawBuf = StringBuffer();
    final now = DateTime.now();

    await for (final delta in _openAi.streamChatCompletion(
      profile: jsonProfile,
      systemPrompt: systemInstruction,
      history: [
        ChatMessage(
          id: 'gen_${now.millisecondsSinceEpoch}',
          conversationId: 'gen',
          role: MessageRole.user,
          content: trimmed,
          createdAt: now,
        ),
      ],
      maxTokens: 1000,
      forceNonStreaming: true,
    )) {
      rawBuf.write(delta.contentDelta);
    }

    return parseGeneratedJson(
      rawResponse: rawBuf.toString(),
      originalPrompt: trimmed,
      id: newId,
    );
  }

  /// Parses LLM JSON output (tolerating Markdown code fences) into a [CharacterProfile].
  static CharacterProfile parseGeneratedJson({
    required String rawResponse,
    required String originalPrompt,
    required String id,
  }) {
    var cleaned = rawResponse.trim();
    final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(cleaned);
    if (fenceMatch != null) {
      cleaned = fenceMatch.group(1)!.trim();
    } else {
      final startIdx = cleaned.indexOf('{');
      final endIdx = cleaned.lastIndexOf('}');
      if (startIdx >= 0 && endIdx > startIdx) {
        cleaned = cleaned.substring(startIdx, endIdx + 1);
      }
    }

    final decoded = jsonDecode(cleaned);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI 返回格式不是有效的角色 JSON');
    }

    final colorIdx = (decoded['avatar_color_index'] as num?)?.toInt() ?? 0;
    final safeIdx = colorIdx.clamp(0, paletteColors.length - 1);
    final now = DateTime.now();

    final parsedName = (decoded['name']?.toString() ?? '').trim();
    final sysPrompt = (decoded['system_prompt']?.toString() ?? '').trim();

    return CharacterProfile(
      id: id,
      name: parsedName.isNotEmpty ? parsedName : '新角色',
      remark: (decoded['remark']?.toString() ?? '').trim(),
      avatarColor: paletteColors[safeIdx],
      gender: (decoded['gender']?.toString() ?? '').trim(),
      age: (decoded['age']?.toString() ?? '').trim(),
      occupation: (decoded['occupation']?.toString() ?? '').trim(),
      relationship: (decoded['relationship']?.toString() ?? '').trim(),
      personality: (decoded['personality']?.toString() ?? '').trim(),
      backstory: (decoded['backstory']?.toString() ?? '').trim(),
      speechStyle: (decoded['speech_style']?.toString() ?? '').trim(),
      openingLine: (decoded['opening_line']?.toString() ?? '').trim(),
      segmentedReply: decoded['segmented_reply'] is bool
          ? decoded['segmented_reply'] as bool
          : true,
      systemPrompt: sysPrompt.isNotEmpty ? sysPrompt : originalPrompt.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }
}
