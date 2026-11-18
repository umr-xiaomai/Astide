import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/character_profile.dart';
import '../services/database_service.dart';

/// Manages user-created roleplay characters stored in local SQLite.
class CharacterRepository {
  CharacterRepository({
    required DatabaseService databaseService,
    Uuid? uuid,
  })  : _dbService = databaseService,
        _uuid = uuid ?? const Uuid();

  final DatabaseService _dbService;
  final Uuid _uuid;

  Future<List<CharacterProfile>> listCharacters() async {
    final db = await _dbService.database;
    final rows = await db.query('characters', orderBy: 'updated_at DESC');
    return rows.map(CharacterProfile.fromMap).toList();
  }

  Future<CharacterProfile?> getCharacter(String id) async {
    final db = await _dbService.database;
    final rows = await db.query('characters', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return CharacterProfile.fromMap(rows.first);
  }

  Future<CharacterProfile> saveCharacter(CharacterProfile character) async {
    final db = await _dbService.database;
    final now = DateTime.now();
    final toSave = character.copyWith(
      id: character.id.isEmpty ? _uuid.v4() : character.id,
      updatedAt: now,
    );
    await db.insert(
      'characters',
      toSave.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return toSave;
  }

  Future<void> deleteCharacter(String id) async {
    final db = await _dbService.database;
    await db.delete('characters', where: 'id = ?', whereArgs: [id]);
  }
}
