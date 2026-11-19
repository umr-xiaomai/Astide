import 'dart:math';

/// Outcome of validating one sequential follow-up bubble produced by an LLM.
class FollowUpEvaluation {
  const FollowUpEvaluation({
    required this.accepted,
    required this.stopChain,
    this.text = '',
    this.rejectReason = '',
  });

  final bool accepted;
  final bool stopChain;
  final String text;
  final String rejectReason;
}

/// Coordinates natural WeChat multi-request cadence, anti-repetition prompting,
/// and strict multi-layer duplicate / meta-leak filtering across chat & autonomous turns.
class MultiReplyGuard {
  const MultiReplyGuard._();

  static const int maxExtraBubbles = 2;

  static final RegExp _doneOrSkipTokenRe = RegExp(
    r'\[(?:DONE|SKIP)\]',
    caseSensitive: false,
  );

  static final RegExp _bareDoneOrSkipRe = RegExp(
    r'^[`"\s（(【\[\-—•]*(?:DONE|SKIP)[`"\s）)】\]\.。!！~～]*$',
    caseSensitive: false,
  );

  static final RegExp _leadingNumberPrefixRe = RegExp(
    r'^(?:第\s*[1-9]\s*条\s*[:：]|(?:[1-9])\s*[\.、)]\s*)',
  );

  static final RegExp _metaLeakRe = RegExp(
    r'(?:无需补[充发]|不用补[充发]|不再补[充发]|不需要补[充发]|没有(?:什么)?(?:新内容|要补充|可补充)|'
    r'话已(?:经)?说完|已经说完了|结束发言|不再发送|停止连发|'
    r'微信连发|微信多气泡|系统连发判断|对方[暂尚]未回复|禁止重复已发|严禁重复|只回复\s*\[?DONE\]?)',
    caseSensitive: false,
  );

  static final RegExp _metaFillerWithDoneRe = RegExp(
    r'^(?:好的|好哒|明白|收到|了解|没问题|ok|okay|done|skip|无|暂无|没有了|没有|不需要|不用了|算了)[呀啦呢吧嘛哦~～.。!！,，\s]*$',
    caseSensitive: false,
  );

  static final RegExp _markdownStructRe = RegExp(
    r'(?:```|^#{1,6}\s|^\s*(?:[-*+]|\d+\.)\s|\|[^|\n]+\|)',
    multiLine: true,
  );

  static final RegExp _sentenceTerminatorRe = RegExp(r'[。！？!?]+');

  /// Matches characters stripped during duplicate/similarity comparison:
  /// whitespace, punctuation, quotes, brackets, symbols, and emojis outside letters/digits/CJK.
  static final RegExp _nonContentCharRe = RegExp(
    r'[^\u4E00-\u9FFF\u3400-\u4DBFa-z0-9]',
  );

  /// Decides whether to issue sequential follow-up request #[extraIndex] (1 = 2nd bubble, 2 = 3rd bubble).
  static bool shouldRequestFollowUp({
    required bool segmentedReplyEnabled,
    required List<String> sentBubbles,
    required int extraIndex,
    required Random random,
  }) {
    if (!segmentedReplyEnabled) return false;
    if (sentBubbles.isEmpty || extraIndex < 1 || extraIndex > maxExtraBubbles) {
      return false;
    }

    final lastBubble = sentBubbles.last.trim();
    if (lastBubble.isEmpty) return false;

    // Technical / structured / long answers should stay a single clean bubble.
    if (_markdownStructRe.hasMatch(lastBubble)) return false;
    if (lastBubble.length >= 110) return false;

    final totalChars = sentBubbles.fold<int>(0, (sum, item) => sum + item.trim().length);
    if (totalChars >= 150) return false;

    final sentenceCount = _sentenceTerminatorRe.allMatches(lastBubble).length;
    if (extraIndex == 1 && sentenceCount >= 3 && lastBubble.length >= 45) {
      return false;
    }

    final endsWithQuestion = lastBubble.endsWith('？') || lastBubble.endsWith('?');
    final double probability;
    if (extraIndex == 1) {
      if (lastBubble.length <= 24) {
        probability = endsWithQuestion ? 0.45 : 0.85;
      } else if (lastBubble.length <= 65) {
        probability = endsWithQuestion ? 0.25 : 0.60;
      } else {
        probability = 0.20;
      }
    } else {
      probability = (lastBubble.length <= 45 && !endsWithQuestion) ? 0.40 : 0.15;
    }

    return random.nextDouble() < probability;
  }

  /// Appends an ephemeral anti-repetition instruction block to [baseSystemPrompt] for one follow-up call.
  static String buildFollowUpSystemPrompt({
    required String baseSystemPrompt,
    required List<String> sentBubbles,
    required int nextBubbleIndex,
  }) {
    final enumerated = StringBuffer();
    for (var i = 0; i < sentBubbles.length; i++) {
      final clean = sentBubbles[i].trim().replaceAll('\n', ' ');
      enumerated.writeln('${i + 1}. 「$clean」');
    }

    final addon = '''
【微信多气泡连发判定（仅本次补发请求生效）】
你刚刚已经连续向对方发出了以下消息气泡（对方屏幕上已经显示，绝对禁止重复）：
${enumerated.toString().trimRight()}

现在判断：像真人在微信里刚发完上一句、趁热顺口补发第 $nextBubbleIndex 条简短新气泡那样，你是否还要立刻补发一条内容全新的短消息？
严格规则：
1. 若上面的话已经说完整、或没有必须立刻补充的新信息，请只回复 `[DONE]`（不要带任何标点、引号或解释）。
2. 若要补发，必须提供全新的内容角度（例如：补充具体细节、分享眼下小事、换个轻松追问、或自然的情绪转折）；严禁重复、复述、同义改写、拼接或总结上面已经发过的任何句子。
3. 只输出这一条新气泡的正文（口语简短，通常 4～40 字），不要带序号、引号、括号说明或 `[DONE]`。''';

    final base = baseSystemPrompt.trim();
    if (base.isEmpty) return addon;
    return '$base\n\n$addon';
  }

  /// Builds the short ephemeral user turn cue required by OpenAI/DeepSeek alternating roles.
  static String buildFollowUpUserCue({
    required List<String> sentBubbles,
  }) {
    final last = sentBubbles.isEmpty ? '' : sentBubbles.last.trim().replaceAll('\n', ' ');
    final snippet = last.length > 36 ? '${last.substring(0, 36)}…' : last;
    if (snippet.isEmpty) {
      return '[系统连发判断：对方暂未回复。若要补发一条内容完全不同的简短微信气泡请直接输出正文，否则仅回复 [DONE]。禁止重复已发内容。]';
    }
    return '[系统连发判断：对方暂未回复，你刚才已发出「$snippet」。若要紧接着补发一条内容完全不同的简短新气泡请直接输出正文，否则仅回复 [DONE]。禁止重复或复述已发内容。]';
  }

  /// Evaluates a raw follow-up reply, rejecting `[DONE]`/`[SKIP]`, meta-leaks,
  /// self-duplicates, user echoes, and exact/substring/paraphrase duplicates of prior bubbles.
  static FollowUpEvaluation evaluateFollowUp({
    required String rawReply,
    required List<String> sentBubblesInTurn,
    String lastUserText = '',
  }) {
    var text = rawReply.trim();
    if (text.isEmpty) {
      return const FollowUpEvaluation(
        accepted: false,
        stopChain: true,
        rejectReason: 'empty',
      );
    }

    if (_bareDoneOrSkipRe.hasMatch(text)) {
      return const FollowUpEvaluation(
        accepted: false,
        stopChain: true,
        rejectReason: 'done_token',
      );
    }

    final hasExplicitDone = _doneOrSkipTokenRe.hasMatch(text);
    text = text.replaceAll(_doneOrSkipTokenRe, '').trim();
    text = text.replaceAll(RegExp(r'\[POKE_BACK\]', caseSensitive: false), '').trim();
    text = _stripOuterQuotes(text);
    text = text.replaceFirst(_leadingNumberPrefixRe, '').trim();
    text = _deduplicateSelfLines(text);

    if (text.isEmpty) {
      return const FollowUpEvaluation(
        accepted: false,
        stopChain: true,
        rejectReason: 'empty_after_strip',
      );
    }

    if (_metaLeakRe.hasMatch(text)) {
      return const FollowUpEvaluation(
        accepted: false,
        stopChain: true,
        rejectReason: 'meta_leak',
      );
    }

    if (hasExplicitDone && _metaFillerWithDoneRe.hasMatch(text)) {
      return const FollowUpEvaluation(
        accepted: false,
        stopChain: true,
        rejectReason: 'done_filler',
      );
    }

    final normCandidate = normalizeForComparison(text);
    if (normCandidate.isEmpty) {
      return const FollowUpEvaluation(
        accepted: false,
        stopChain: true,
        rejectReason: 'punctuation_only',
      );
    }

    // Never echo the user's message verbatim as a follow-up bubble.
    final normUser = normalizeForComparison(lastUserText);
    if (normUser.length >= 2 && normCandidate == normUser) {
      return const FollowUpEvaluation(
        accepted: false,
        stopChain: true,
        rejectReason: 'echo_user',
      );
    }

    // Reject exact, substring, or high-similarity duplicates of any bubble already sent in this turn.
    for (final prev in sentBubblesInTurn) {
      if (isDuplicateOrTooSimilar(text, prev)) {
        return const FollowUpEvaluation(
          accepted: false,
          stopChain: true,
          rejectReason: 'duplicate',
        );
      }
    }

    return FollowUpEvaluation(
      accepted: true,
      stopChain: hasExplicitDone,
      text: text,
    );
  }

  /// Normalizes a message down to lowercase alphanumeric + CJK content characters for dedup checks.
  static String normalizeForComparison(String input) {
    return input.toLowerCase().replaceAll(_nonContentCharRe, '');
  }

  /// Returns true when [candidate] repeats or closely paraphrases [existing].
  static bool isDuplicateOrTooSimilar(String candidate, String existing) {
    final a = normalizeForComparison(candidate);
    final b = normalizeForComparison(existing);
    if (a.isEmpty || b.isEmpty) return a == b;

    // 1. Exact normalized match (ignores punctuation, spacing, emojis, casing).
    if (a == b) return true;

    final minLen = min(a.length, b.length);

    // 2. Containment / substring duplication (e.g., repeating part or wrapping the whole bubble).
    if (minLen >= 4 && (a.contains(b) || b.contains(a))) {
      return true;
    }

    // 3. Short-text character multiset Dice similarity (catches "好呀" vs "好的呀").
    if (minLen <= 6) {
      final charDice = _multisetDice(_charCounts(a), _charCounts(b));
      if (charDice >= 0.65) return true;
    }

    // 4. Character bigram multiset Dice + overlap coefficient (catches CJK/mixed paraphrases).
    if (minLen >= 4) {
      final bigramsA = _bigramCounts(a);
      final bigramsB = _bigramCounts(b);
      final totalA = a.length - 1;
      final totalB = b.length - 1;
      final inter = _multisetIntersection(bigramsA, bigramsB);

      final dice = (2.0 * inter) / (totalA + totalB);
      if (dice >= 0.50) return true;

      final minBigrams = min(totalA, totalB);
      if (minBigrams >= 3) {
        final overlap = inter / minBigrams;
        if (overlap >= 0.60) return true;
      }
    }

    return false;
  }

  static String _stripOuterQuotes(String input) {
    var s = input.trim();
    const pairs = [
      ('「', '」'),
      ('『', '』'),
      ('“', '”'),
      ('"', '"'),
      ("'", "'"),
    ];
    for (final (open, close) in pairs) {
      if (s.length >= 2 && s.startsWith(open) && s.endsWith(close)) {
        final inner = s.substring(open.length, s.length - close.length).trim();
        if (!inner.contains(open) && !inner.contains(close)) {
          s = inner;
          break;
        }
      }
    }
    return s;
  }

  static String _deduplicateSelfLines(String input) {
    final lines = input
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length <= 1) return lines.isEmpty ? '' : lines.first;

    final kept = <String>[];
    for (final line in lines) {
      final dup = kept.any((prev) => isDuplicateOrTooSimilar(line, prev));
      if (!dup) kept.add(line);
    }
    return kept.join('\n');
  }

  static Map<String, int> _charCounts(String s) {
    final map = <String, int>{};
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      map[ch] = (map[ch] ?? 0) + 1;
    }
    return map;
  }

  static Map<String, int> _bigramCounts(String s) {
    final map = <String, int>{};
    for (var i = 0; i < s.length - 1; i++) {
      final bg = s.substring(i, i + 2);
      map[bg] = (map[bg] ?? 0) + 1;
    }
    return map;
  }

  static int _multisetIntersection(Map<String, int> a, Map<String, int> b) {
    var count = 0;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other != null) {
        count += min(entry.value, other);
      }
    }
    return count;
  }

  static double _multisetDice(Map<String, int> a, Map<String, int> b) {
    var totalA = 0;
    for (final v in a.values) {
      totalA += v;
    }
    var totalB = 0;
    for (final v in b.values) {
      totalB += v;
    }
    if (totalA + totalB == 0) return 1.0;
    return (2.0 * _multisetIntersection(a, b)) / (totalA + totalB);
  }
}
