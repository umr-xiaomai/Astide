/// Configuration profile for an OpenAI-compatible AI provider endpoint.
class ApiProfile {
  const ApiProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.supportsVision = false,
    this.supportsReasoning = false,
    this.streamEnabled = true,
    this.temperature = 0.7,
    this.isActive = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool supportsVision;
  final bool supportsReasoning;
  final bool streamEnabled;
  final double temperature;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isConfigured => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  /// Normalizes [baseUrl] and builds the `/chat/completions` endpoint URI.
  Uri get chatCompletionsUri {
    var normalized = baseUrl.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/chat/completions')) {
      return Uri.parse(normalized);
    }
    return Uri.parse('$normalized/chat/completions');
  }

  /// Normalizes [baseUrl] and builds the `/models` endpoint URI for health checks.
  Uri get modelsUri {
    var normalized = baseUrl.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/chat/completions')) {
      normalized = normalized.substring(0, normalized.length - '/chat/completions'.length);
    }
    return Uri.parse('$normalized/models');
  }

  ApiProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? supportsVision,
    bool? supportsReasoning,
    bool? streamEnabled,
    double? temperature,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ApiProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      supportsVision: supportsVision ?? this.supportsVision,
      supportsReasoning: supportsReasoning ?? this.supportsReasoning,
      streamEnabled: streamEnabled ?? this.streamEnabled,
      temperature: temperature ?? this.temperature,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      'api_key': apiKey,
      'model': model,
      'supports_vision': supportsVision ? 1 : 0,
      'supports_reasoning': supportsReasoning ? 1 : 0,
      'stream_enabled': streamEnabled ? 1 : 0,
      'temperature': temperature,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ApiProfile.fromMap(Map<String, Object?> map) {
    return ApiProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      baseUrl: map['base_url'] as String,
      apiKey: map['api_key'] as String,
      model: map['model'] as String,
      supportsVision: (map['supports_vision'] as int? ?? 0) == 1,
      supportsReasoning: (map['supports_reasoning'] as int? ?? 0) == 1,
      streamEnabled: (map['stream_enabled'] as int? ?? 1) == 1,
      temperature: (map['temperature'] as num? ?? 0.7).toDouble(),
      isActive: (map['is_active'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}
