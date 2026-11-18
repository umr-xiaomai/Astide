import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:astide_flutter/data/services/deepseek_import_service.dart';
import 'package:astide_flutter/data/services/file_extractor_service.dart';
import 'package:astide_flutter/data/services/media_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _TempMediaStorageService extends MediaStorageService {
  _TempMediaStorageService(this.baseDir);

  final Directory baseDir;

  @override
  Future<String> saveFileCopy(String sourcePath, {String category = 'files'}) async {
    final destDir = Directory(p.join(baseDir.path, category));
    if (!await destDir.exists()) await destDir.create(recursive: true);
    final dest = p.join(destDir.path, p.basename(sourcePath));
    await File(sourcePath).copy(dest);
    return dest;
  }
}

void main() {
  group('DeepSeekImportService', () {
    late Directory tempExportDir;
    late Directory tempMediaDir;

    setUp(() async {
      tempExportDir = await Directory.systemTemp.createTemp('ds_export_test_');
      tempMediaDir = await Directory.systemTemp.createTemp('ds_media_test_');
    });

    tearDown(() async {
      if (await tempExportDir.exists()) await tempExportDir.delete(recursive: true);
      if (await tempMediaDir.exists()) await tempMediaDir.delete(recursive: true);
    });

    test('parses branching messages, THINK fragments, webp images, and file metadata', () async {
      await File(p.join(tempExportDir.path, 'user.json')).writeAsString(jsonEncode({
        'user_id': 'Wechat-test',
        'oauth_profiles': [
          {
            'provider': 'WECHAT',
            'profile_json': jsonEncode({'name': '测试用户'}),
          },
        ],
      }));

      await File(p.join(tempExportDir.path, 'chat_session_index.json')).writeAsString(jsonEncode([
        {'id': 'sess-1', 'title': '测试会话', 'pinned': true},
      ]));

      final sessionsDir = Directory(p.join(tempExportDir.path, 'chat_sessions'));
      await sessionsDir.create(recursive: true);
      final filesDir = Directory(p.join(sessionsDir.path, 'sess-1_files'));
      await filesDir.create(recursive: true);
      await File(p.join(filesDir.path, 'photo.webp')).writeAsBytes([1, 2, 3, 4]);

      await File(p.join(sessionsDir.path, 'sess-1.json')).writeAsString(jsonEncode({
        'id': 'sess-1',
        'title': '测试会话',
        'pinned': true,
        'current_message_id': 3,
        'inserted_at': '2026-10-01T10:00:00Z',
        'updated_at': '2026-10-01T10:05:00Z',
        'messages': [
          {
            'id': 1,
            'parent_id': null,
            'role': 'USER',
            'inserted_at': '2026-10-01T10:00:00Z',
            'fragments': [
              {
                'type': 'FILE',
                'files': [
                  {
                    'file_name': 'photo.webp',
                    'file_size': 4,
                    'export_path': 'chat_sessions/sess-1_files/photo.webp',
                    'is_image': true,
                    'width': 100,
                    'height': 100,
                  },
                  {
                    'file_name': 'spec.pdf',
                    'file_size': 20480,
                    'export_path': null,
                    'is_image': false,
                  },
                ],
              },
              {'type': 'REQUEST', 'content': '帮我看下这张图'},
            ],
          },
          {
            'id': 2,
            'parent_id': 1,
            'role': 'ASSISTANT',
            'inserted_at': '2026-10-01T10:01:00Z',
            'fragments': [
              {'type': 'RESPONSE', 'content': '被放弃的旧分支回答'},
            ],
          },
          {
            'id': 3,
            'parent_id': 1,
            'role': 'ASSISTANT',
            'inserted_at': '2026-10-01T10:02:00Z',
            'fragments': [
              {'type': 'THINK', 'content': '先分析题目条件', 'elapsed_secs': 1.8},
              {'type': 'RESPONSE', 'content': '这是当前分支的正式回答'},
            ],
          },
        ],
      }));

      final importer = DeepSeekImportService(
        mediaStorage: _TempMediaStorageService(tempMediaDir),
      );
      final parsed = await importer.parseFromExtractedDirectory(tempExportDir.path);

      expect(parsed.userInfo.nickname, equals('测试用户'));
      expect(parsed.sessions.length, equals(1));

      final session = parsed.sessions.first;
      expect(session.conversation.isPinned, isTrue);
      // Branch id=2 must be excluded when walking from current_message_id=3 -> 1.
      expect(session.messages.length, equals(2));
      expect(session.messages[0].content, equals('帮我看下这张图'));
      expect(session.messages[0].attachments.length, equals(2));
      expect(session.messages[0].attachments[0].isImage, isTrue);
      expect(session.messages[0].attachments[1].isImage, isFalse);
      expect(session.messages[0].attachments[1].fileName, equals('spec.pdf'));

      expect(session.messages[1].reasoningContent, equals('先分析题目条件'));
      expect(session.messages[1].thinkingSeconds, closeTo(1.8, 0.01));
      expect(session.messages[1].content, equals('这是当前分支的正式回答'));
    });
  });

  group('FileExtractorService', () {
    test('extracts UTF-8 text and JSON files cleanly', () async {
      final extractor = FileExtractorService();
      final bytes = Uint8List.fromList(utf8.encode('{"project":"Astide","lang":"zh"}'));
      final text = await extractor.extractTextFromBytes(bytes, extension: '.json');
      expect(text, contains('Astide'));
    });
  });
}
