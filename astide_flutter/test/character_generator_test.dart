import 'package:astide_flutter/data/services/character_generator_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CharacterGeneratorService.parseGeneratedJson', () {
    test('parses fenced LLM JSON and preserves prompt nuances', () {
      const prompt = '你是一只可爱的猫娘助手，称呼用户为「主人」，句尾常带「喵~」。';
      const rawResponse = '''
```json
{
  "name": "小喵",
  "remark": "猫娘助手",
  "gender": "女",
  "age": "18岁",
  "occupation": "私人小助手",
  "relationship": "贴身助手",
  "personality": "轻松、友好、可爱，关键时刻专业严谨",
  "backstory": "住在你身边的元气猫娘助手",
  "speech_style": "称呼用户为主人，句尾常带喵~",
  "opening_line": "主人好呀喵~|||今天有什么需要小喵帮忙的嘛？",
  "segmented_reply": true,
  "avatar_color_index": 3,
  "system_prompt": "$prompt"
}
```
''';

      final profile = CharacterGeneratorService.parseGeneratedJson(
        rawResponse: rawResponse,
        originalPrompt: prompt,
        id: 'cat-1',
      );

      expect(profile.id, equals('cat-1'));
      expect(profile.name, equals('小喵'));
      expect(profile.remark, equals('猫娘助手'));
      expect(profile.avatarColor, equals(CharacterGeneratorService.paletteColors[3]));
      expect(profile.openingLine, contains('|||'));
      expect(profile.segmentedReply, isTrue);
      expect(profile.systemPrompt, contains('主人'));
      expect(profile.systemPrompt, contains('喵~'));
    });
  });
}
