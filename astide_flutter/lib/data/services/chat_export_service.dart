import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/models/character_profile.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/conversation.dart';
import '../repositories/chat_repository.dart';
import 'database_service.dart';

/// Supported export formats for local Astide conversations.
enum ChatExportFormat {
  sqlite(
    extension: 'sqlite',
    label: 'SQLite 数据库 (.sqlite)',
    shortLabel: 'SQLite',
    mimeType: 'application/octet-stream',
    description: '独立标准 SQLite 数据库文件，完整包含会话、消息、附件与关联人物表，不含敏感 Key',
    isBinary: true,
  ),
  xml(
    extension: 'xml',
    label: 'XML 文档 (.xml)',
    shortLabel: 'XML',
    mimeType: 'text/xml',
    description: '规范缩进的结构化 XML 文档，适合归档迁移与跨工具解析',
    isBinary: false,
  ),
  json(
    extension: 'json',
    label: 'JSON 数据 (.json)',
    shortLabel: 'JSON',
    mimeType: 'application/json',
    description: '通用 UTF-8 结构化 JSON，完整保存消息、深度思考与附件信息',
    isBinary: false,
  ),
  txt(
    extension: 'txt',
    label: '纯文本记录 (.txt)',
    shortLabel: 'TXT',
    mimeType: 'text/plain',
    description: '高可读性的微信风格纯文本聊天记录，按日期分组展示',
    isBinary: false,
  ),
  markdown(
    extension: 'md',
    label: 'Markdown 笔记 (.md)',
    shortLabel: 'Markdown',
    mimeType: 'text/plain',
    description: '整洁排版文档，适合导入 Obsidian、Notion 等笔记软件阅读',
    isBinary: false,
  ),
  html(
    extension: 'html',
    label: '离线网页 (.html)',
    shortLabel: 'HTML',
    mimeType: 'text/html',
    description: '仿微信气泡的离线单文件网页，可直接在手机或电脑浏览器浏览',
    isBinary: false,
  );

  const ChatExportFormat({
    required this.extension,
    required this.label,
    required this.shortLabel,
    required this.mimeType,
    required this.description,
    required this.isBinary,
  });

  final String extension;
  final String label;
  final String shortLabel;
  final String mimeType;
  final String description;
  final bool isBinary;
}

/// Generated export file payload ready for system save dialog, preview, or external open.
class ChatExportArtifact {
  const ChatExportArtifact({
    required this.format,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.conversationCount,
    required this.messageCount,
    required this.attachmentCount,
    this.textPreview = '',
  });

  final ChatExportFormat format;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final int conversationCount;
  final int messageCount;
  final int attachmentCount;
  final String textPreview;
}

/// Serializes local conversations into SQLite, XML, JSON, TXT, Markdown, or standalone HTML.
class ChatExportService {
  ChatExportService({
    this.sqliteFactoryOverride,
    this.tempDirOverride,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final DatabaseFactory? sqliteFactoryOverride;
  final Directory? tempDirOverride;
  final Uuid _uuid;

  static const String appVersion = '0.1.0';
  static final RegExp _invalidXmlChars =
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]');
  static const HtmlEscape _htmlEscape = HtmlEscape(HtmlEscapeMode.element);

  /// Exports [bundles] into the requested [format] without exposing local API secrets.
  Future<ChatExportArtifact> buildExport({
    required ChatExportFormat format,
    required List<ConversationExportBundle> bundles,
    required AppSettings settings,
    bool includeReasoning = true,
    DateTime? exportedAt,
  }) async {
    if (bundles.isEmpty) {
      throw const FormatException('请至少选择一个要导出的会话');
    }

    final timestamp = exportedAt ?? DateTime.now();
    final msgCount = bundles.fold<int>(0, (sum, b) => sum + b.messages.length);
    final attCount = bundles.fold<int>(
      0,
      (sum, b) => sum + b.messages.fold<int>(0, (mSum, m) => mSum + m.attachments.length),
    );
    final fileName = _buildFileName(
      format: format,
      bundles: bundles,
      exportedAt: timestamp,
    );

    late final Uint8List bytes;
    var preview = '';

    if (format == ChatExportFormat.sqlite) {
      bytes = await _buildSqliteBytes(
        bundles: bundles,
        settings: settings,
        includeReasoning: includeReasoning,
        exportedAt: timestamp,
      );
    } else {
      final text = switch (format) {
        ChatExportFormat.json => _buildJsonText(
            bundles: bundles,
            settings: settings,
            includeReasoning: includeReasoning,
            exportedAt: timestamp,
            messageCount: msgCount,
            attachmentCount: attCount,
          ),
        ChatExportFormat.xml => _buildXmlText(
            bundles: bundles,
            settings: settings,
            includeReasoning: includeReasoning,
            exportedAt: timestamp,
            messageCount: msgCount,
          ),
        ChatExportFormat.txt => _buildPlainText(
            bundles: bundles,
            settings: settings,
            includeReasoning: includeReasoning,
            exportedAt: timestamp,
            messageCount: msgCount,
          ),
        ChatExportFormat.markdown => _buildMarkdownText(
            bundles: bundles,
            settings: settings,
            includeReasoning: includeReasoning,
            exportedAt: timestamp,
            messageCount: msgCount,
          ),
        ChatExportFormat.html => _buildHtmlText(
            bundles: bundles,
            settings: settings,
            includeReasoning: includeReasoning,
            exportedAt: timestamp,
            messageCount: msgCount,
          ),
        ChatExportFormat.sqlite => '',
      };
      preview = text;
      bytes = Uint8List.fromList(utf8.encode(text));
    }

    return ChatExportArtifact(
      format: format,
      fileName: fileName,
      mimeType: format.mimeType,
      bytes: bytes,
      conversationCount: bundles.length,
      messageCount: msgCount,
      attachmentCount: attCount,
      textPreview: preview,
    );
  }

  /// Writes [artifact] to a temporary cache file suitable for system preview / sharing.
  Future<String> writeTempArtifactFile(ChatExportArtifact artifact) async {
    final dir = await _resolveTempDir();
    final safeName = artifact.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File(p.join(dir.path, safeName));
    await file.writeAsBytes(artifact.bytes, flush: true);
    return file.path;
  }

  Future<Directory> _resolveTempDir() async {
    if (tempDirOverride != null) {
      if (!await tempDirOverride!.exists()) {
        await tempDirOverride!.create(recursive: true);
      }
      return tempDirOverride!;
    }
    try {
      final cache = await getTemporaryDirectory();
      final exportDir = Directory(p.join(cache.path, 'astide_exports'));
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      return exportDir;
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  Future<Uint8List> _buildSqliteBytes({
    required List<ConversationExportBundle> bundles,
    required AppSettings settings,
    required bool includeReasoning,
    required DateTime exportedAt,
  }) async {
    final dir = await _resolveTempDir();
    final tempPath = p.join(dir.path, 'export_${_uuid.v4()}.sqlite');
    final exportDbService = DatabaseService(
      factoryOverride: sqliteFactoryOverride,
      pathOverride: tempPath,
    );

    try {
      final db = await exportDbService.database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS export_meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      final totalMsgs = bundles.fold<int>(0, (s, b) => s + b.messages.length);
      final uniqueChars = <String, CharacterProfile>{};
      for (final b in bundles) {
        if (b.character != null) {
          uniqueChars[b.character!.id] = b.character!;
        }
      }

      await db.transaction((txn) async {
        final metaEntries = {
          'app_name': '星汐 Astide',
          'app_version': appVersion,
          'exported_at': exportedAt.toIso8601String(),
          'user_nickname': settings.userNickname,
          'user_persona': settings.userPersona,
          'conversation_count': bundles.length.toString(),
          'message_count': totalMsgs.toString(),
        };
        for (final entry in metaEntries.entries) {
          await txn.insert('export_meta', {'key': entry.key, 'value': entry.value});
        }

        for (final char in uniqueChars.values) {
          await txn.insert('characters', char.toMap());
        }

        for (final bundle in bundles) {
          await txn.insert('conversations', bundle.conversation.toMap());
          for (final msg in bundle.messages) {
            final sanitizedMsg = includeReasoning
                ? msg
                : msg.copyWith(reasoningContent: '', thinkingSeconds: 0);
            await txn.insert('messages', sanitizedMsg.toMap());
            for (final att in msg.attachments) {
              await txn.insert('attachments', att.toMap());
            }
          }
        }
      });

      try {
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}
      await exportDbService.close();

      final file = File(tempPath);
      return await file.readAsBytes();
    } finally {
      await exportDbService.close();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final candidate = File('$tempPath$suffix');
        if (await candidate.exists()) {
          await candidate.delete();
        }
      }
    }
  }

  String _buildJsonText({
    required List<ConversationExportBundle> bundles,
    required AppSettings settings,
    required bool includeReasoning,
    required DateTime exportedAt,
    required int messageCount,
    required int attachmentCount,
  }) {
    final root = <String, dynamic>{
      'format': 'astide_chat_export',
      'version': '1.0',
      'app': '星汐 Astide',
      'appVersion': appVersion,
      'exportedAt': exportedAt.toIso8601String(),
      'user': {
        'nickname': settings.userNickname,
        'persona': settings.userPersona,
      },
      'stats': {
        'conversationCount': bundles.length,
        'messageCount': messageCount,
        'attachmentCount': attachmentCount,
      },
      'conversations': [
        for (final bundle in bundles)
          {
            'id': bundle.conversation.id,
            'externalId': bundle.conversation.externalId,
            'title': bundle.conversation.title,
            'sourceType': bundle.conversation.sourceType.value,
            'sourceLabel': _sourceLabel(bundle.conversation.sourceType),
            'isPinned': bundle.conversation.isPinned,
            'isMuted': bundle.conversation.isMuted,
            'contextSummary': bundle.conversation.contextSummary,
            'lastMessageAt': bundle.conversation.lastMessageAt.toIso8601String(),
            'createdAt': bundle.conversation.createdAt.toIso8601String(),
            'updatedAt': bundle.conversation.updatedAt.toIso8601String(),
            if (bundle.character != null)
              'character': {
                'id': bundle.character!.id,
                'name': bundle.character!.name,
                'remark': bundle.character!.remark,
                'gender': bundle.character!.gender,
                'age': bundle.character!.age,
                'occupation': bundle.character!.occupation,
                'relationship': bundle.character!.relationship,
                'personality': bundle.character!.personality,
                'backstory': bundle.character!.backstory,
                'speechStyle': bundle.character!.speechStyle,
              },
            'messages': [
              for (final msg in bundle.messages)
                {
                  'id': msg.id,
                  'role': msg.role.value,
                  'sender': _senderLabel(msg, bundle, settings),
                  'content': msg.content,
                  if (includeReasoning && msg.hasReasoning)
                    'reasoningContent': msg.reasoningContent,
                  if (includeReasoning && msg.thinkingSeconds > 0)
                    'thinkingSeconds': msg.thinkingSeconds,
                  'status': msg.status.value,
                  if (msg.errorMessage.isNotEmpty) 'errorMessage': msg.errorMessage,
                  'createdAt': msg.createdAt.toIso8601String(),
                  'createdAtMs': msg.createdAt.millisecondsSinceEpoch,
                  if (msg.attachments.isNotEmpty)
                    'attachments': [
                      for (final att in msg.attachments)
                        {
                          'id': att.id,
                          'type': att.type.value,
                          'fileName': att.fileName,
                          'mimeType': att.mimeType,
                          'fileSize': att.fileSize,
                          if (att.filePath != null) 'filePath': att.filePath,
                          if (att.extractedText.isNotEmpty) 'extractedText': att.extractedText,
                          if (att.width != null) 'width': att.width,
                          if (att.height != null) 'height': att.height,
                        },
                    ],
                },
            ],
          },
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(root);
  }

  String _buildXmlText({
    required List<ConversationExportBundle> bundles,
    required AppSettings settings,
    required bool includeReasoning,
    required DateTime exportedAt,
    required int messageCount,
  }) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'astide_export',
      attributes: {
        'app': '星汐 Astide',
        'version': appVersion,
        'exported_at': exportedAt.toIso8601String(),
        'conversation_count': bundles.length.toString(),
        'message_count': messageCount.toString(),
      },
      nest: () {
        builder.element(
          'user',
          attributes: {
            'nickname': _xmlSafe(settings.userNickname),
            if (settings.userPersona.trim().isNotEmpty)
              'persona': _xmlSafe(settings.userPersona.trim()),
          },
        );
        builder.element('conversations', nest: () {
          for (final bundle in bundles) {
            final conv = bundle.conversation;
            builder.element(
              'conversation',
              attributes: {
                'id': _xmlSafe(conv.id),
                if (conv.externalId != null) 'external_id': _xmlSafe(conv.externalId!),
                'title': _xmlSafe(conv.title),
                'source_type': conv.sourceType.value,
                'created_at': conv.createdAt.toIso8601String(),
                'updated_at': conv.updatedAt.toIso8601String(),
                'last_message_at': conv.lastMessageAt.toIso8601String(),
              },
              nest: () {
                if (bundle.character != null) {
                  final char = bundle.character!;
                  builder.element(
                    'character',
                    attributes: {
                      'id': _xmlSafe(char.id),
                      'name': _xmlSafe(char.name),
                      if (char.remark.isNotEmpty) 'remark': _xmlSafe(char.remark),
                      if (char.gender.isNotEmpty) 'gender': _xmlSafe(char.gender),
                      if (char.age.isNotEmpty) 'age': _xmlSafe(char.age),
                      if (char.occupation.isNotEmpty) 'occupation': _xmlSafe(char.occupation),
                      if (char.relationship.isNotEmpty)
                        'relationship': _xmlSafe(char.relationship),
                    },
                    nest: () {
                      if (char.personality.isNotEmpty) {
                        builder.element('personality', nest: () => builder.text(_xmlSafe(char.personality)));
                      }
                      if (char.backstory.isNotEmpty) {
                        builder.element('backstory', nest: () => builder.text(_xmlSafe(char.backstory)));
                      }
                      if (char.speechStyle.isNotEmpty) {
                        builder.element('speech_style', nest: () => builder.text(_xmlSafe(char.speechStyle)));
                      }
                    },
                  );
                }
                if (conv.contextSummary.trim().isNotEmpty) {
                  builder.element(
                    'context_summary',
                    nest: () => builder.text(_xmlSafe(conv.contextSummary.trim())),
                  );
                }
                builder.element(
                  'messages',
                  attributes: {'count': bundle.messages.length.toString()},
                  nest: () {
                    for (final msg in bundle.messages) {
                      builder.element(
                        'message',
                        attributes: {
                          'id': _xmlSafe(msg.id),
                          'role': msg.role.value,
                          'sender': _xmlSafe(_senderLabel(msg, bundle, settings)),
                          'status': msg.status.value,
                          'created_at': msg.createdAt.toIso8601String(),
                          if (includeReasoning && msg.thinkingSeconds > 0)
                            'thinking_seconds': msg.thinkingSeconds.toStringAsFixed(1),
                        },
                        nest: () {
                          if (includeReasoning && msg.hasReasoning) {
                            builder.element(
                              'reasoning',
                              nest: () => builder.text(_xmlSafe(msg.reasoningContent)),
                            );
                          }
                          builder.element(
                            'content',
                            nest: () => builder.text(_xmlSafe(msg.content)),
                          );
                          if (msg.errorMessage.isNotEmpty) {
                            builder.element(
                              'error_message',
                              nest: () => builder.text(_xmlSafe(msg.errorMessage)),
                            );
                          }
                          if (msg.attachments.isNotEmpty) {
                            builder.element('attachments', nest: () {
                              for (final att in msg.attachments) {
                                builder.element(
                                  'attachment',
                                  attributes: {
                                    'id': _xmlSafe(att.id),
                                    'type': att.type.value,
                                    'file_name': _xmlSafe(att.fileName),
                                    'mime_type': _xmlSafe(att.mimeType),
                                    'file_size': att.fileSize.toString(),
                                    if (att.filePath != null) 'file_path': _xmlSafe(att.filePath!),
                                  },
                                  nest: () {
                                    if (att.extractedText.isNotEmpty) {
                                      builder.element(
                                        'extracted_text',
                                        nest: () => builder.text(_xmlSafe(att.extractedText)),
                                      );
                                    }
                                  },
                                );
                              }
                            });
                          }
                        },
                      );
                    }
                  },
                );
              },
            );
          }
        });
      },
    );

    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  String _buildPlainText({
    required List<ConversationExportBundle> bundles,
    required AppSettings settings,
    required bool includeReasoning,
    required DateTime exportedAt,
    required int messageCount,
  }) {
    final buf = StringBuffer();
    final fullFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final dateFmt = DateFormat('yyyy-MM-dd');
    final timeFmt = DateFormat('HH:mm:ss');

    buf.writeln('==================================================');
    buf.writeln('星汐 Astide 本地会话导出记录');
    buf.writeln('导出时间：${fullFmt.format(exportedAt)}');
    buf.writeln('账号昵称：${settings.userNickname}');
    buf.writeln('会话数量：${bundles.length} 个  |  消息总数：$messageCount 条');
    buf.writeln('==================================================');

    for (final bundle in bundles) {
      final conv = bundle.conversation;
      buf.writeln();
      buf.writeln('【会话】${conv.title}');
      buf.writeln('类型：${_sourceLabel(conv.sourceType)}  |  消息数：${bundle.messages.length}');
      if (bundle.character != null) {
        final c = bundle.character!;
        final traits = [
          if (c.relationship.isNotEmpty) '关系: ${c.relationship}',
          if (c.occupation.isNotEmpty) '职业: ${c.occupation}',
          if (c.personality.isNotEmpty) '性格: ${c.personality}',
        ].join(' | ');
        if (traits.isNotEmpty) buf.writeln('人物设定：$traits');
      }
      if (conv.contextSummary.trim().isNotEmpty) {
        buf.writeln('历史摘要：${conv.contextSummary.trim().replaceAll('\n', ' ')}');
      }
      buf.writeln('--------------------------------------------------');

      String? currentDay;
      for (final msg in bundle.messages) {
        final day = dateFmt.format(msg.createdAt);
        if (day != currentDay) {
          currentDay = day;
          buf.writeln('--- $day ---');
        }
        final time = timeFmt.format(msg.createdAt);
        if (msg.role == MessageRole.system) {
          buf.writeln('[$time] [系统提示] ${msg.content}');
          continue;
        }
        final sender = _senderLabel(msg, bundle, settings);
        buf.writeln('[$time] $sender：');
        if (includeReasoning && msg.hasReasoning) {
          final secs = msg.thinkingSeconds > 0
              ? ' (${msg.thinkingSeconds.toStringAsFixed(1)}s)'
              : '';
          buf.writeln('  <深度思考$secs>');
          for (final line in msg.reasoningContent.split('\n')) {
            buf.writeln('  | $line');
          }
        }
        if (msg.content.trim().isNotEmpty) {
          for (final line in msg.content.split('\n')) {
            buf.writeln('  $line');
          }
        }
        for (final att in msg.attachments) {
          final tag = att.isImage ? '图片' : '文件';
          buf.writeln('  [$tag附件] ${att.fileName} (${att.formattedSize})');
        }
        if (msg.status == MessageStatus.error && msg.errorMessage.isNotEmpty) {
          buf.writeln('  [状态异常] ${msg.errorMessage}');
        }
      }
    }

    return buf.toString();
  }

  String _buildMarkdownText({
    required List<ConversationExportBundle> bundles,
    required AppSettings settings,
    required bool includeReasoning,
    required DateTime exportedAt,
    required int messageCount,
  }) {
    final buf = StringBuffer();
    final fullFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final msgFmt = DateFormat('yyyy-MM-dd HH:mm');

    buf.writeln('# 星汐 Astide 会话导出');
    buf.writeln();
    buf.writeln('- **导出时间**：${fullFmt.format(exportedAt)}');
    buf.writeln('- **我的昵称**：${settings.userNickname}');
    buf.writeln('- **导出范围**：${bundles.length} 个会话，共 $messageCount 条消息');
    buf.writeln();

    for (final bundle in bundles) {
      final conv = bundle.conversation;
      buf.writeln('---');
      buf.writeln();
      buf.writeln('## ${conv.title}');
      buf.writeln();
      buf.writeln('- **来源**：${_sourceLabel(conv.sourceType)}');
      buf.writeln('- **创建时间**：${fullFmt.format(conv.createdAt)}');
      buf.writeln('- **消息总数**：${bundle.messages.length}');
      if (conv.contextSummary.trim().isNotEmpty) {
        buf.writeln();
        buf.writeln('> **记忆摘要**：${conv.contextSummary.trim().replaceAll('\n', '\n> ')}');
      }
      buf.writeln();

      for (final msg in bundle.messages) {
        final ts = msgFmt.format(msg.createdAt);
        if (msg.role == MessageRole.system) {
          buf.writeln('*$ts · ${msg.content}*');
          buf.writeln();
          continue;
        }
        final sender = _senderLabel(msg, bundle, settings);
        buf.writeln('### $sender · `$ts`');
        buf.writeln();
        if (includeReasoning && msg.hasReasoning) {
          final secs = msg.thinkingSeconds > 0
              ? '（用时 ${msg.thinkingSeconds.toStringAsFixed(1)}s）'
              : '';
          buf.writeln('<details>');
          buf.writeln('<summary>深度思考过程$secs</summary>');
          buf.writeln();
          for (final line in msg.reasoningContent.split('\n')) {
            buf.writeln('> $line');
          }
          buf.writeln();
          buf.writeln('</details>');
          buf.writeln();
        }
        if (msg.content.trim().isNotEmpty) {
          buf.writeln(msg.content);
          buf.writeln();
        }
        for (final att in msg.attachments) {
          final icon = att.isImage ? '🖼' : '📎';
          buf.writeln('- $icon `${att.fileName}` (${att.formattedSize})');
        }
        if (msg.attachments.isNotEmpty) buf.writeln();
      }
    }

    return buf.toString();
  }

  String _buildHtmlText({
    required List<ConversationExportBundle> bundles,
    required AppSettings settings,
    required bool includeReasoning,
    required DateTime exportedAt,
    required int messageCount,
  }) {
    final fullFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final msgFmt = DateFormat('yyyy-MM-dd HH:mm');
    final buf = StringBuffer();

    buf.writeln('''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>星汐 Astide 会话导出</title>
<style>
  body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", Arial, sans-serif; background: #EDEDED; color: #191919; }
  .wrap { max-width: 780px; margin: 0 auto; padding: 20px 14px 48px; }
  .header { background: #FFFFFF; border-radius: 10px; padding: 18px 20px; margin-bottom: 16px; border: 1px solid #E5E5E5; }
  .header h1 { margin: 0 0 8px; font-size: 20px; }
  .meta { color: #666; font-size: 13px; line-height: 1.6; }
  .toc { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
  .toc a { background: #F7F7F7; color: #576B95; text-decoration: none; padding: 5px 10px; border-radius: 6px; font-size: 13px; }
  .conv { margin-top: 22px; background: #F5F5F5; border-radius: 10px; overflow: hidden; border: 1px solid #DFDFDF; }
  .conv-title { background: #EDEDED; padding: 12px 16px; font-weight: 600; font-size: 16px; border-bottom: 1px solid #DCDCDC; display: flex; justify-content: space-between; align-items: center; }
  .conv-title span { font-size: 12.5px; color: #777; font-weight: 400; }
  .summary { background: #FFFBE6; padding: 10px 16px; font-size: 12.5px; color: #7A5618; border-bottom: 1px solid #EEE3B8; }
  .msgs { padding: 16px; display: flex; flex-direction: column; gap: 12px; }
  .sys { text-align: center; font-size: 12px; color: #888; padding: 2px 10px; }
  .row { display: flex; flex-direction: column; max-width: 82%; }
  .row.user { align-self: flex-end; align-items: flex-end; }
  .row.ai { align-self: flex-start; align-items: flex-start; }
  .sender { font-size: 11.5px; color: #888; margin: 0 4px 4px; }
  .bubble { padding: 10px 13px; border-radius: 7px; font-size: 14.5px; line-height: 1.55; white-space: pre-wrap; word-break: break-word; }
  .user .bubble { background: #95EC69; color: #000; }
  .ai .bubble { background: #FFFFFF; color: #191919; border: 1px solid #EAEAEA; }
  details { background: #F7F7F7; border-radius: 5px; padding: 6px 8px; margin-bottom: 8px; font-size: 12.5px; color: #555; }
  summary { cursor: pointer; font-weight: 500; }
  .att { margin-top: 6px; padding: 6px 10px; background: #F7F7F7; border-radius: 6px; font-size: 12.5px; color: #444; }
</style>
</head>
<body>
<div class="wrap">
  <div class="header">
    <h1>星汐 Astide 会话导出</h1>
    <div class="meta">导出时间：${_esc(fullFmt.format(exportedAt))} · 账号：${_esc(settings.userNickname)} · 会话：${bundles.length} 个 · 消息：$messageCount 条</div>
    <div class="toc">
''');

    for (var i = 0; i < bundles.length; i++) {
      final title = _esc(bundles[i].conversation.title);
      buf.writeln('      <a href="#conv_$i">$title (${bundles[i].messages.length})</a>');
    }
    buf.writeln('    </div>\n  </div>');

    for (var i = 0; i < bundles.length; i++) {
      final bundle = bundles[i];
      final conv = bundle.conversation;
      buf.writeln(
        '  <section class="conv" id="conv_$i">',
      );
      buf.writeln(
        '    <div class="conv-title">${_esc(conv.title)}<span>${_esc(_sourceLabel(conv.sourceType))} · ${bundle.messages.length} 条</span></div>',
      );
      if (conv.contextSummary.trim().isNotEmpty) {
        buf.writeln(
          '    <div class="summary">记忆摘要：${_esc(conv.contextSummary.trim())}</div>',
        );
      }
      buf.writeln('    <div class="msgs">');

      for (final msg in bundle.messages) {
        if (msg.role == MessageRole.system) {
          buf.writeln(
            '      <div class="sys">${_esc(msgFmt.format(msg.createdAt))} · ${_esc(msg.content)}</div>',
          );
          continue;
        }
        final cls = msg.isUser ? 'user' : 'ai';
        final sender = _senderLabel(msg, bundle, settings);
        buf.writeln('      <div class="row $cls">');
        buf.writeln(
          '        <div class="sender">${_esc(sender)} · ${_esc(msgFmt.format(msg.createdAt))}</div>',
        );
        buf.writeln('        <div class="bubble">');
        if (includeReasoning && msg.hasReasoning) {
          final secs = msg.thinkingSeconds > 0
              ? ' (${msg.thinkingSeconds.toStringAsFixed(1)}s)'
              : '';
          buf.writeln(
            '<details><summary>深度思考过程$secs</summary><div>${_esc(msg.reasoningContent)}</div></details>',
          );
        }
        if (msg.content.isNotEmpty) {
          buf.write(_esc(msg.content));
        }
        for (final att in msg.attachments) {
          final tag = att.isImage ? '图片' : '文件';
          buf.writeln(
            '<div class="att">[$tag] ${_esc(att.fileName)} (${_esc(att.formattedSize)})</div>',
          );
        }
        buf.writeln('</div>\n      </div>');
      }
      buf.writeln('    </div>\n  </section>');
    }

    buf.writeln('</div>\n</body>\n</html>');
    return buf.toString();
  }

  String _buildFileName({
    required ChatExportFormat format,
    required List<ConversationExportBundle> bundles,
    required DateTime exportedAt,
  }) {
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(exportedAt);
    final scopeSlug = bundles.length == 1
        ? _sanitizeFileSegment(bundles.first.conversation.title)
        : 'all_${bundles.length}chats';
    return 'astide_${scopeSlug}_$stamp.${format.extension}';
  }

  String _sanitizeFileSegment(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (cleaned.isEmpty) return 'chat';
    return cleaned.length > 24 ? cleaned.substring(0, 24) : cleaned;
  }

  String _sourceLabel(ConversationSourceType type) {
    return switch (type) {
      ConversationSourceType.direct => '星汐核心会话',
      ConversationSourceType.roleplay => '人物扮演会话',
      ConversationSourceType.deepseekImport => 'DeepSeek 导入历史',
    };
  }

  String _senderLabel(
    ChatMessage msg,
    ConversationExportBundle bundle,
    AppSettings settings,
  ) {
    return switch (msg.role) {
      MessageRole.user => settings.userNickname.trim().isEmpty ? '我' : settings.userNickname,
      MessageRole.assistant => bundle.character?.displayName ?? bundle.conversation.title,
      MessageRole.system => '系统提示',
    };
  }

  String _xmlSafe(String value) => value.replaceAll(_invalidXmlChars, '');

  String _esc(String value) => _htmlEscape.convert(value);
}
