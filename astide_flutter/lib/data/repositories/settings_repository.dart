import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/api_profile.dart';
import '../../domain/models/app_settings.dart';
import '../services/database_service.dart';

/// Persists global settings and OpenAI-compatible API profiles in local SQLite.
class SettingsRepository {
  SettingsRepository({
    required DatabaseService databaseService,
    Uuid? uuid,
  })  : _dbService = databaseService,
        _uuid = uuid ?? const Uuid();

  final DatabaseService _dbService;
  final Uuid _uuid;

  static const _kAutonomousEnabled = 'autonomous_enabled';
  static const _kKeepAliveEnabled = 'keep_alive_enabled';
  static const _kAutonomousInterval = 'autonomous_interval_minutes';
  static const _kAutonomousProbability = 'autonomous_probability';
  static const _kPokeReplyProbability = 'poke_reply_probability';
  static const _kQuietHoursEnabled = 'quiet_hours_enabled';
  static const _kUserNickname = 'user_nickname';
  static const _kUserAvatarPath = 'user_avatar_path';
  static const _kUserPersona = 'user_persona';
  static const _kDefaultPrompt = 'default_assistant_prompt';

  Future<AppSettings> loadSettings() async {
    final db = await _dbService.database;
    final rows = await db.query('app_settings');
    final map = <String, String>{
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    const defaults = AppSettings();
    var prompt = (map[_kDefaultPrompt] ?? '').isNotEmpty
        ? map[_kDefaultPrompt]!
        : defaults.defaultAssistantPrompt;
    // Upgrade legacy stored default prompts that contained old `|||` delimiter instructions.
    if (prompt.startsWith('你叫星汐，英文名 Astide。') &&
        (prompt.contains('|||') || prompt.endsWith('舒服地交流。'))) {
      prompt = defaults.defaultAssistantPrompt;
      await db.insert(
        'app_settings',
        {'key': _kDefaultPrompt, 'value': prompt},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return AppSettings(
      autonomousEnabled: map[_kAutonomousEnabled] == '1',
      keepAliveEnabled: map[_kKeepAliveEnabled] == '1',
      autonomousIntervalMinutes:
          int.tryParse(map[_kAutonomousInterval] ?? '') ?? defaults.autonomousIntervalMinutes,
      autonomousProbability: (double.tryParse(map[_kAutonomousProbability] ?? '') ??
              defaults.autonomousProbability)
          .clamp(0.0, 1.0),
      pokeReplyProbability: (double.tryParse(map[_kPokeReplyProbability] ?? '') ??
              defaults.pokeReplyProbability)
          .clamp(0.0, 1.0),
      quietHoursEnabled: map[_kQuietHoursEnabled] != '0',
      userNickname: (map[_kUserNickname] ?? '').isNotEmpty
          ? map[_kUserNickname]!
          : defaults.userNickname,
      userAvatarPath: (map[_kUserAvatarPath] ?? '').isNotEmpty ? map[_kUserAvatarPath] : null,
      userPersona: map[_kUserPersona] ?? '',
      defaultAssistantPrompt: prompt,
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    final db = await _dbService.database;
    final entries = <String, String>{
      _kAutonomousEnabled: settings.autonomousEnabled ? '1' : '0',
      _kKeepAliveEnabled: settings.keepAliveEnabled ? '1' : '0',
      _kAutonomousInterval: settings.autonomousIntervalMinutes.toString(),
      _kAutonomousProbability: settings.autonomousProbability.toStringAsFixed(2),
      _kPokeReplyProbability: settings.pokeReplyProbability.toStringAsFixed(2),
      _kQuietHoursEnabled: settings.quietHoursEnabled ? '1' : '0',
      _kUserNickname: settings.userNickname,
      _kUserAvatarPath: settings.userAvatarPath ?? '',
      _kUserPersona: settings.userPersona,
      _kDefaultPrompt: settings.defaultAssistantPrompt,
    };
    await db.transaction((txn) async {
      for (final entry in entries.entries) {
        await txn.insert(
          'app_settings',
          {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<ApiProfile>> listApiProfiles() async {
    final db = await _dbService.database;
    await _seedDefaultProfilesIfEmpty(db);
    final rows = await db.query('api_profiles', orderBy: 'created_at ASC');
    return rows.map(ApiProfile.fromMap).toList();
  }

  Future<ApiProfile?> getActiveApiProfile() async {
    final profiles = await listApiProfiles();
    if (profiles.isEmpty) return null;
    for (final p in profiles) {
      if (p.isActive) return p;
    }
    return profiles.first;
  }

  Future<ApiProfile> saveApiProfile(ApiProfile profile) async {
    final db = await _dbService.database;
    final now = DateTime.now();
    final updated = profile.copyWith(updatedAt: now);
    await db.transaction((txn) async {
      if (updated.isActive) {
        await txn.update('api_profiles', {'is_active': 0});
      }
      await txn.insert(
        'api_profiles',
        updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return updated;
  }

  Future<void> setActiveApiProfile(String profileId) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.update('api_profiles', {'is_active': 0});
      await txn.update(
        'api_profiles',
        {'is_active': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [profileId],
      );
    });
  }

  Future<void> deleteApiProfile(String profileId) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.delete('api_profiles', where: 'id = ?', whereArgs: [profileId]);
      final remaining = await txn.query('api_profiles', orderBy: 'created_at ASC');
      if (remaining.isNotEmpty && remaining.every((r) => (r['is_active'] as int? ?? 0) == 0)) {
        await txn.update(
          'api_profiles',
          {'is_active': 1},
          where: 'id = ?',
          whereArgs: [remaining.first['id']],
        );
      }
    });
  }

  Future<void> _seedDefaultProfilesIfEmpty(Database db) async {
    final rows = await db.query('api_profiles');
    if (rows.isNotEmpty) {
      // Remove legacy empty-key placeholder presets (e.g. deepseek-v4-pro / deepseek-chat / deepseek-reasoner)
      // while keeping any user-configured profiles intact.
      for (final row in rows) {
        final model = row['model'] as String? ?? '';
        final key = row['api_key'] as String? ?? '';
        if (key.isEmpty &&
            (model == 'deepseek-v4-pro' ||
                model == 'deepseek-chat' ||
                model == 'deepseek-reasoner' ||
                row['name'] == 'DeepSeek Flash (思考模式)')) {
          await db.delete('api_profiles', where: 'id = ?', whereArgs: [row['id']]);
        }
      }
      final remaining = await db.query('api_profiles', orderBy: 'created_at ASC');
      if (remaining.isNotEmpty) {
        if (remaining.every((r) => (r['is_active'] as int? ?? 0) == 0)) {
          await db.update(
            'api_profiles',
            {'is_active': 1},
            where: 'id = ?',
            whereArgs: [remaining.first['id']],
          );
        }
        return;
      }
    }

    final now = DateTime.now();
    await db.insert(
      'api_profiles',
      ApiProfile(
        id: _uuid.v4(),
        name: 'DeepSeek Flash (V4.1)',
        baseUrl: 'https://api.deepseek.com',
        apiKey: '',
        model: 'deepseek-flash',
        supportsVision: true,
        supportsReasoning: false,
        streamEnabled: true,
        temperature: 0.8,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    );
  }
}
