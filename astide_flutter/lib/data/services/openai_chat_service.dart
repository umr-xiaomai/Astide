import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../domain/models/api_profile.dart';
import '../../domain/models/chat_attachment.dart';
import '../../domain/models/chat_message.dart';
import 'file_extractor_service.dart';

/// Incremental chunk emitted during an OpenAI-compatible chat completion call.
class ChatStreamDelta {
  const ChatStreamDelta({
    this.contentDelta = '',
    this.reasoningDelta = '',
    this.isDone = false,
  });

  final String contentDelta;
  final String reasoningDelta;
  final bool isDone;
}

/// Client for OpenAI-compatible `/chat/completions` and `/models` endpoints.
class OpenAiChatService {
  OpenAiChatService({
    Dio? dio,
    FileExtractorService? fileExtractor,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 25),
                receiveTimeout: const Duration(minutes: 3),
                sendTimeout: const Duration(seconds: 45),
              ),
            ),
        _fileExtractor = fileExtractor ?? FileExtractorService();

  final Dio _dio;
  final FileExtractorService _fileExtractor;

  /// Fetches available model IDs from the OpenAI-compatible `/models` endpoint.
  Future<List<String>> fetchAvailableModels(ApiProfile profile) async {
    if (profile.baseUrl.trim().isEmpty || profile.apiKey.trim().isEmpty) {
      throw const FormatException('请先填写 API 地址和 API Key');
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        profile.modelsUri.toString(),
        options: Options(
          headers: {
            'Authorization': 'Bearer ${profile.apiKey.trim()}',
          },
          validateStatus: (code) => code != null && code < 500,
        ),
      );
      if (response.statusCode != 200) {
        throw HttpException(_extractApiError(response.data, response.statusCode));
      }
      final data = response.data?['data'] as List<dynamic>? ?? const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map((e) => e['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throw HttpException(_formatDioError(e));
    }
  }

  /// Tests connectivity and credentials with a minimal chat completion check.
  Future<String> testConnection(ApiProfile profile) async {
    if (!profile.isConfigured) {
      throw const FormatException('请先填写完整的 API 地址、API Key 和模型名称');
    }
    try {
      final payload = <String, dynamic>{
        'model': profile.model.trim(),
        'messages': [
          {'role': 'user', 'content': 'Hi'},
        ],
        'max_tokens': 8,
        'stream': false,
      };
      if (_isDeepSeekEndpoint(profile)) {
        payload['thinking'] = {'type': 'disabled'};
      }
      final response = await _dio.post<Map<String, dynamic>>(
        profile.chatCompletionsUri.toString(),
        options: Options(
          headers: {
            'Authorization': 'Bearer ${profile.apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          validateStatus: (code) => code != null && code < 500,
        ),
        data: payload,
      );

      if (response.statusCode == 200) {
        return '连接成功，模型 ${profile.model} 响应正常';
      }
      final errMsg = _extractApiError(response.data, response.statusCode);
      throw HttpException(errMsg);
    } on DioException catch (e) {
      throw HttpException(_formatDioError(e));
    }
  }

  /// Streams completion deltas (content + optional reasoning) for a conversation history.
  Stream<ChatStreamDelta> streamChatCompletion({
    required ApiProfile profile,
    required List<ChatMessage> history,
    String systemPrompt = '',
    String? modelOverride,
    int? maxTokens,
    bool? forceNonStreaming,
    CancelToken? cancelToken,
  }) async* {
    if (!profile.isConfigured) {
      throw const FormatException('请先在“我 -> API 与模型设置”中填写 API 地址和 Key');
    }

    final payloadMessages = await _buildPayloadMessages(
      history: history,
      systemPrompt: systemPrompt,
      supportsVision: profile.supportsVision,
    );

    final effectiveModel = (modelOverride != null && modelOverride.trim().isNotEmpty)
        ? modelOverride.trim()
        : profile.model.trim();
    final useStream = forceNonStreaming == true ? false : profile.streamEnabled;

    final body = <String, dynamic>{
      'model': effectiveModel,
      'messages': payloadMessages,
      'stream': useStream,
    };
    if (maxTokens != null) {
      body['max_tokens'] = maxTokens;
    }

    if (_isDeepSeekEndpoint(profile, modelOverride: effectiveModel)) {
      body['thinking'] = {
        'type': profile.supportsReasoning ? 'enabled' : 'disabled',
      };
    }

    if (!profile.supportsReasoning && !effectiveModel.contains('reasoner')) {
      body['temperature'] = profile.temperature;
    }

    if (!useStream) {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          profile.chatCompletionsUri.toString(),
          cancelToken: cancelToken,
          options: Options(
            headers: {
              'Authorization': 'Bearer ${profile.apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            validateStatus: (code) => code != null && code < 600,
          ),
          data: body,
        );
        if (response.statusCode != 200) {
          throw HttpException(_extractApiError(response.data, response.statusCode));
        }
        final choices = response.data?['choices'] as List<dynamic>?;
        final first = choices != null && choices.isNotEmpty
            ? choices.first as Map<String, dynamic>
            : null;
        final msg = first?['message'] as Map<String, dynamic>?;
        final reasoning = msg?['reasoning_content'] as String? ?? '';
        final content = msg?['content'] as String? ?? '';
        yield ChatStreamDelta(
          reasoningDelta: reasoning,
          contentDelta: content,
          isDone: true,
        );
        return;
      } on DioException catch (e) {
        throw HttpException(_formatDioError(e));
      }
    }

    try {
      final response = await _dio.post<ResponseBody>(
        profile.chatCompletionsUri.toString(),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Authorization': 'Bearer ${profile.apiKey.trim()}',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          validateStatus: (code) => code != null && code < 600,
        ),
        data: body,
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode != 200) {
        final rawBytes = await _readStreamBytes(response.data?.stream);
        final rawText = utf8.decode(rawBytes, allowMalformed: true);
        Map<String, dynamic>? parsed;
        try {
          final decoded = jsonDecode(rawText);
          if (decoded is Map<String, dynamic>) parsed = decoded;
        } catch (_) {}
        throw HttpException(_extractApiError(parsed, statusCode, fallback: rawText));
      }

      final stream = response.data?.stream;
      if (stream == null) {
        yield const ChatStreamDelta(isDone: true);
        return;
      }

      final lineStream = utf8.decoder
          .bind(stream.cast<List<int>>())
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
        final dataPayload = trimmed.substring(5).trim();
        if (dataPayload == '[DONE]') {
          yield const ChatStreamDelta(isDone: true);
          return;
        }
        Map<String, dynamic>? jsonChunk;
        try {
          final decoded = jsonDecode(dataPayload);
          if (decoded is Map<String, dynamic>) {
            jsonChunk = decoded;
          }
        } catch (_) {
          continue;
        }
        if (jsonChunk == null) continue;
        if (jsonChunk['error'] != null) {
          throw HttpException(_extractApiError(jsonChunk, statusCode));
        }

        final choices = jsonChunk['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final first = choices.first as Map<String, dynamic>;
        final delta = first['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        final contentDelta = delta['content'] as String? ?? '';
        final reasoningDelta = delta['reasoning_content'] as String? ?? '';
        if (contentDelta.isNotEmpty || reasoningDelta.isNotEmpty) {
          yield ChatStreamDelta(
            contentDelta: contentDelta,
            reasoningDelta: reasoningDelta,
          );
        }
      }

      yield const ChatStreamDelta(isDone: true);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        yield const ChatStreamDelta(isDone: true);
        return;
      }
      throw HttpException(_formatDioError(e));
    }
  }

  /// Builds normalized, alternating OpenAI `messages` entries (merging consecutive same-role turns).
  Future<List<Map<String, dynamic>>> _buildPayloadMessages({
    required List<ChatMessage> history,
    required String systemPrompt,
    required bool supportsVision,
  }) async {
    final result = <Map<String, dynamic>>[];
    if (systemPrompt.trim().isNotEmpty) {
      result.add({'role': 'system', 'content': systemPrompt.trim()});
    }

    // Keep the recent conversation window bounded to avoid blowing context windows on long imports.
    final window = history.length > 36 ? history.sublist(history.length - 36) : history;

    // Only include image base64 payloads for the latest user message + recent 2 images to save bandwidth.
    final recentImageOwnerIds = <String>{};
    for (final m in window.reversed) {
      if (m.isUser && m.attachments.any((a) => a.isImage && a.filePath != null)) {
        recentImageOwnerIds.add(m.id);
        if (recentImageOwnerIds.length >= 2) break;
      }
    }

    for (final msg in window) {
      if (msg.status == MessageStatus.error || msg.role == MessageRole.system) {
        continue;
      }

      final textBuffer = StringBuffer(msg.content.trim());
      final imageParts = <Map<String, dynamic>>[];

      for (final att in msg.attachments) {
        if (att.type == AttachmentType.file) {
          if (textBuffer.isNotEmpty) textBuffer.writeln('\n');
          if (att.extractedText.trim().isNotEmpty) {
            textBuffer.writeln('[用户发送文件: ${att.fileName} (${att.formattedSize})]');
            textBuffer.writeln(att.extractedText.trim());
          } else {
            textBuffer.writeln('[用户发送文件: ${att.fileName} (${att.formattedSize})，未能提取文本]');
          }
        } else if (att.type == AttachmentType.image) {
          final canSendPixels = supportsVision &&
              recentImageOwnerIds.contains(msg.id) &&
              att.filePath != null &&
              await File(att.filePath!).exists();
          if (canSendPixels) {
            final dataUrl = await _fileExtractor.encodeImageDataUrl(
              att.filePath!,
              mimeType: att.mimeType,
            );
            imageParts.add({
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            });
          } else {
            if (textBuffer.isNotEmpty) textBuffer.writeln();
            textBuffer.write('[附带图片: ${att.fileName}]');
          }
        }
      }

      final textStr = textBuffer.toString().trim();
      if (textStr.isEmpty && imageParts.isEmpty) continue;

      final roleStr = msg.isUser ? 'user' : 'assistant';

      if (imageParts.isNotEmpty && msg.isUser) {
        final contentParts = <Map<String, dynamic>>[
          if (textStr.isNotEmpty) {'type': 'text', 'text': textStr},
          ...imageParts,
        ];
        result.add({'role': roleStr, 'content': contentParts});
      } else {
        // Merge consecutive same-role text messages (e.g., segmented WeChat RP replies).
        if (result.isNotEmpty &&
            result.last['role'] == roleStr &&
            result.last['content'] is String) {
          final prev = result.last['content'] as String;
          result.last['content'] = '$prev\n$textStr';
        } else {
          result.add({'role': roleStr, 'content': textStr});
        }
      }
    }

    return result;
  }

  Future<List<int>> _readStreamBytes(Stream<List<int>>? stream) async {
    if (stream == null) return const [];
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  String _extractApiError(
    Map<String, dynamic>? body,
    int? statusCode, {
    String? fallback,
  }) {
    final err = body?['error'];
    if (err is Map<String, dynamic>) {
      final message = err['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return 'API 错误 ($statusCode): $message';
      }
    }
    if (body?['message'] != null) {
      return 'API 错误 ($statusCode): ${body!['message']}';
    }
    if (fallback != null && fallback.trim().isNotEmpty) {
      final snippet = fallback.trim();
      return 'API 错误 ($statusCode): ${snippet.length > 180 ? snippet.substring(0, 180) : snippet}';
    }
    return 'API 请求失败 (HTTP $statusCode)';
  }

  String _formatDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '网络请求超时，请检查 API 地址或网络连接';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '无法连接到 API 服务器，请检查网络或 URL 是否正确';
    }
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      return _extractApiError(data, status);
    }
    return e.message ?? '网络请求异常';
  }

  bool _isDeepSeekEndpoint(ApiProfile profile, {String? modelOverride}) {
    final base = profile.baseUrl.toLowerCase();
    final model = (modelOverride ?? profile.model).toLowerCase();
    return base.contains('deepseek.com') ||
        model.startsWith('deepseek-flash') ||
        model.startsWith('deepseek-v4');
  }
}
