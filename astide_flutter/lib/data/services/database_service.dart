import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Manages the local SQLite database (`astide.db`) for all app data.
class DatabaseService {
  DatabaseService({
    this.factoryOverride,
    this.pathOverride,
  });

  final DatabaseFactory? factoryOverride;
  final String? pathOverride;
  Database? _database;

  static const int _schemaVersion = 3;
  static const String _dbFileName = 'astide.db';

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    final opened = await _openDatabase();
    _database = opened;
    return opened;
  }

  Future<Database> _openDatabase() async {
    final factory = factoryOverride ?? databaseFactory;
    final dbPath = pathOverride ?? p.join(await getDatabasesPath(), _dbFileName);
    return factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE conversations ADD COLUMN context_summary TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'ALTER TABLE conversations ADD COLUMN context_summarized_until_ms INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await _createMomentsTables(db);
    }
  }

  Future<void> _createMomentsTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS moments (
        id TEXT PRIMARY KEY,
        author_id TEXT NOT NULL,
        author_name TEXT NOT NULL,
        author_avatar_path TEXT,
        author_avatar_color INTEGER NOT NULL DEFAULT 4278698336,
        content TEXT NOT NULL DEFAULT '',
        image_paths_json TEXT NOT NULL DEFAULT '[]',
        liked_by_names_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS moment_comments (
        id TEXT PRIMARY KEY,
        moment_id TEXT NOT NULL,
        author_id TEXT NOT NULL,
        author_name TEXT NOT NULL,
        reply_to_name TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (moment_id) REFERENCES moments(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_moments_created ON moments (created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_moment_comments_moment ON moment_comments (moment_id, created_at ASC)',
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE api_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        api_key TEXT NOT NULL,
        model TEXT NOT NULL,
        supports_vision INTEGER NOT NULL DEFAULT 0,
        supports_reasoning INTEGER NOT NULL DEFAULT 0,
        stream_enabled INTEGER NOT NULL DEFAULT 1,
        temperature REAL NOT NULL DEFAULT 0.7,
        is_active INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE characters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        remark TEXT NOT NULL DEFAULT '',
        avatar_path TEXT,
        avatar_color INTEGER NOT NULL DEFAULT 4278698336,
        gender TEXT NOT NULL DEFAULT '',
        age TEXT NOT NULL DEFAULT '',
        occupation TEXT NOT NULL DEFAULT '',
        relationship TEXT NOT NULL DEFAULT '',
        personality TEXT NOT NULL DEFAULT '',
        backstory TEXT NOT NULL DEFAULT '',
        speech_style TEXT NOT NULL DEFAULT '',
        opening_line TEXT NOT NULL DEFAULT '',
        system_prompt TEXT NOT NULL DEFAULT '',
        segmented_reply INTEGER NOT NULL DEFAULT 1,
        model_override TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        external_id TEXT,
        title TEXT NOT NULL,
        character_id TEXT,
        source_type TEXT NOT NULL DEFAULT 'direct',
        avatar_path TEXT,
        avatar_color INTEGER NOT NULL DEFAULT 4278698336,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_muted INTEGER NOT NULL DEFAULT 0,
        unread_count INTEGER NOT NULL DEFAULT 0,
        last_message_preview TEXT NOT NULL DEFAULT '',
        context_summary TEXT NOT NULL DEFAULT '',
        context_summarized_until_ms INTEGER NOT NULL DEFAULT 0,
        last_message_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        reasoning_content TEXT NOT NULL DEFAULT '',
        thinking_seconds REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'sent',
        error_message TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        type TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT,
        mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
        file_size INTEGER NOT NULL DEFAULT 0,
        extracted_text TEXT NOT NULL DEFAULT '',
        width INTEGER,
        height INTEGER,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_conversations_order ON conversations (is_pinned DESC, last_message_at DESC)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_conversations_external ON conversations (external_id) WHERE external_id IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX idx_messages_conv ON messages (conversation_id, created_at ASC)',
    );
    await db.execute(
      'CREATE INDEX idx_attachments_msg ON attachments (message_id)',
    );

    await _createMomentsTables(db);
  }

  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }
}
