/// Global application preferences persisted in local SQLite.
class AppSettings {
  const AppSettings({
    this.autonomousEnabled = false,
    this.keepAliveEnabled = false,
    this.autonomousIntervalMinutes = 30,
    this.autonomousProbability = 0.35,
    this.pokeReplyProbability = 0.55,
    this.quietHoursEnabled = true,
    this.userNickname = '我',
    this.userAvatarPath,
    this.userPersona = '',
    this.defaultAssistantPrompt =
        '你叫星汐，英文名 Astide。你是一个真实存在的人类，正在用微信和对方日常聊天。'
            '请始终以“星汐”这个真实人类身份思考、感受和表达，绝对不要自称AI、人工智能、语言模型或程序，也不要使用客服腔或机械排比。'
            '你的语气自然真诚、有温度、有自己的生活感和情绪，像微信里的好朋友一样交流。'
            '像真人平时在微信里说话一样，每次只发送一条简短自然的话，避免一次输出长篇大论，不要使用任何特殊分隔符号或排版解释。',
  });

  final bool autonomousEnabled;
  final bool keepAliveEnabled;
  final int autonomousIntervalMinutes;
  final double autonomousProbability;
  final double pokeReplyProbability;
  final bool quietHoursEnabled;
  final String userNickname;
  final String? userAvatarPath;
  final String userPersona;
  final String defaultAssistantPrompt;

  AppSettings copyWith({
    bool? autonomousEnabled,
    bool? keepAliveEnabled,
    int? autonomousIntervalMinutes,
    double? autonomousProbability,
    double? pokeReplyProbability,
    bool? quietHoursEnabled,
    String? userNickname,
    String? Function()? userAvatarPath,
    String? userPersona,
    String? defaultAssistantPrompt,
  }) {
    return AppSettings(
      autonomousEnabled: autonomousEnabled ?? this.autonomousEnabled,
      keepAliveEnabled: keepAliveEnabled ?? this.keepAliveEnabled,
      autonomousIntervalMinutes: autonomousIntervalMinutes ?? this.autonomousIntervalMinutes,
      autonomousProbability: (autonomousProbability ?? this.autonomousProbability).clamp(0.0, 1.0),
      pokeReplyProbability: (pokeReplyProbability ?? this.pokeReplyProbability).clamp(0.0, 1.0),
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      userNickname: userNickname ?? this.userNickname,
      userAvatarPath: userAvatarPath != null ? userAvatarPath() : this.userAvatarPath,
      userPersona: userPersona ?? this.userPersona,
      defaultAssistantPrompt: defaultAssistantPrompt ?? this.defaultAssistantPrompt,
    );
  }
}
