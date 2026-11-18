import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/moment_post.dart';
import '../services/database_service.dart';

/// Persists WeChat Moments posts, likes, comments, and unseen badge tracking in SQLite.
class MomentsRepository {
  MomentsRepository({
    required DatabaseService databaseService,
    Uuid? uuid,
  })  : _dbService = databaseService,
        _uuid = uuid ?? const Uuid();

  final DatabaseService _dbService;
  final Uuid _uuid;

  static const _kLastSeenMomentsMs = 'last_seen_moments_ms';

  /// Seeds an authentic initial Moment from 星汐 Astide on first launch.
  Future<void> ensureInitialMoments() async {
    final db = await _dbService.database;
    await db.update(
      'moments',
      {'author_avatar_path': 'asset:assets/images/astide_avatar.jpg'},
      where: "author_id = 'astide_core' AND (author_avatar_path IS NULL OR author_avatar_path = '')",
    );
    await db.rawUpdate(
      "UPDATE moments SET content = REPLACE(content, '|||', '') WHERE content LIKE '%|||%'",
    );

    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM moments'),
        ) ??
        0;
    if (count > 0) return;

    final now = DateTime.now();
    await insertMoment(
      MomentPost(
        id: _uuid.v4(),
        authorId: 'astide_core',
        authorName: '星汐 Astide',
        authorAvatarPath: 'asset:assets/images/astide_avatar.jpg',
        authorAvatarColor: 0xFF07C160,
        content: '刚泡好一杯热乌龙茶，窗外风挺舒服的 🌿\n今天也记得好好照顾自己呀。',
        likedByNames: const ['星汐 Astide'],
        createdAt: now.subtract(const Duration(minutes: 42)),
      ),
    );
  }

  Future<List<MomentPost>> listMoments({int limit = 60}) async {
    final db = await _dbService.database;
    final postRows = await db.query(
      'moments',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    if (postRows.isEmpty) return [];

    final ids = postRows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final commentRows = await db.query(
      'moment_comments',
      where: 'moment_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'created_at ASC',
    );
    final commentsByMoment = <String, List<MomentComment>>{};
    for (final row in commentRows) {
      final c = MomentComment.fromMap(row);
      commentsByMoment.putIfAbsent(c.momentId, () => []).add(c);
    }

    return postRows
        .map((r) => MomentPost.fromMap(
              r,
              comments: commentsByMoment[r['id'] as String] ?? const [],
            ))
        .toList();
  }

  Future<MomentPost?> getMoment(String momentId) async {
    final db = await _dbService.database;
    final rows = await db.query('moments', where: 'id = ?', whereArgs: [momentId], limit: 1);
    if (rows.isEmpty) return null;
    final commentRows = await db.query(
      'moment_comments',
      where: 'moment_id = ?',
      whereArgs: [momentId],
      orderBy: 'created_at ASC',
    );
    return MomentPost.fromMap(
      rows.first,
      comments: commentRows.map(MomentComment.fromMap).toList(),
    );
  }

  Future<MomentPost> insertMoment(MomentPost post) async {
    final db = await _dbService.database;
    final toSave = post.copyWith(id: post.id.isEmpty ? _uuid.v4() : post.id);
    await db.insert(
      'moments',
      toSave.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return toSave;
  }

  Future<void> deleteMoment(String momentId) async {
    final db = await _dbService.database;
    await db.delete('moments', where: 'id = ?', whereArgs: [momentId]);
  }

  Future<MomentPost?> toggleLike({
    required String momentId,
    required String likerName,
  }) async {
    final post = await getMoment(momentId);
    if (post == null) return null;
    final likes = List<String>.from(post.likedByNames);
    if (likes.contains(likerName)) {
      likes.remove(likerName);
    } else {
      likes.add(likerName);
    }
    final db = await _dbService.database;
    await db.update(
      'moments',
      {'liked_by_names_json': jsonEncode(likes)},
      where: 'id = ?',
      whereArgs: [momentId],
    );
    return post.copyWith(likedByNames: likes);
  }

  Future<MomentComment> addComment(MomentComment comment) async {
    final db = await _dbService.database;
    final saved = MomentComment(
      id: comment.id.isEmpty ? _uuid.v4() : comment.id,
      momentId: comment.momentId,
      authorId: comment.authorId,
      authorName: comment.authorName,
      replyToName: comment.replyToName,
      content: comment.content,
      createdAt: comment.createdAt,
    );
    await db.insert(
      'moment_comments',
      saved.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return saved;
  }

  Future<int> getLastSeenMomentsMs() async {
    final db = await _dbService.database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [_kLastSeenMomentsMs],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
  }

  Future<void> markMomentsSeen(int timestampMs) async {
    final db = await _dbService.database;
    await db.insert(
      'app_settings',
      {'key': _kLastSeenMomentsMs, 'value': timestampMs.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Builds a concise prompt snippet of this character's & the user's recent Moments for chat continuity.
  Future<String> buildMomentsContextSnippet({String? characterId}) async {
    final targetAuthorId = characterId ?? 'astide_core';
    final all = await listMoments(limit: 20);
    final ownMoments = all.where((m) => m.authorId == targetAuthorId).take(4).toList();
    final userMoments = all.where((m) => m.isByUser).take(3).toList();
    if (ownMoments.isEmpty && userMoments.isEmpty) return '';

    final buf = StringBuffer();
    if (ownMoments.isNotEmpty) {
      buf.writeln('【你近期自己发过的朋友圈动态（请牢记自己发过这些内容）】');
      for (final m in ownMoments) {
        buf.writeln(_formatMomentLine(m));
      }
    }
    if (userMoments.isNotEmpty) {
      buf.writeln('【对方近期发的朋友圈动态】');
      for (final m in userMoments) {
        buf.writeln(_formatMomentLine(m));
      }
    }
    return buf.toString().trim();
  }

  String _formatMomentLine(MomentPost m) {
    final timeStr = DateFormat('MM-dd HH:mm').format(m.createdAt);
    final body = m.content.trim().replaceAll('\n', ' ');
    final clipped = body.length > 120 ? '${body.substring(0, 120)}…' : body;
    final parts = <String>[
      '- [$timeStr] $clipped',
      if (m.imagePaths.isNotEmpty) '(附带${m.imagePaths.length}张图)',
      if (m.likedByNames.isNotEmpty) '点赞:${m.likedByNames.join("、")}',
      if (m.comments.isNotEmpty)
        '评论:${m.comments.take(3).map((c) => "${c.authorName}:${c.content}").join(" | ")}',
    ];
    return parts.join(' ');
  }
}
