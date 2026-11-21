import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const int schemaVersion = 2;

  static Future<Database> open({
    String? filePath,
    DatabaseFactory? factory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final path =
        filePath ?? p.join(await dbFactory.getDatabasesPath(), 'yuying.db');
    return dbFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE feeding_records ADD COLUMN remind_at INTEGER',
      );
    }
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE babies (
        id TEXT PRIMARY KEY,
        nickname TEXT NOT NULL,
        birth_date INTEGER NOT NULL,
        sex TEXT,
        avatar_key TEXT NOT NULL DEFAULT 'default',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE feeding_records (
        id TEXT PRIMARY KEY,
        baby_id TEXT NOT NULL,
        mode TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        amount_ml INTEGER,
        milk_type TEXT,
        note TEXT,
        remind_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (baby_id) REFERENCES babies (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE breastfeeding_segments (
        id TEXT PRIMARY KEY,
        feeding_id TEXT NOT NULL,
        side TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER NOT NULL,
        FOREIGN KEY (feeding_id) REFERENCES feeding_records (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE stool_records (
        id TEXT PRIMARY KEY,
        baby_id TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        color TEXT,
        consistency TEXT,
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (baby_id) REFERENCES babies (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE sleep_records (
        id TEXT PRIMARY KEY,
        baby_id TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (baby_id) REFERENCES babies (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE active_feeding_sessions (
        baby_id TEXT PRIMARY KEY,
        feeding_id TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        current_side TEXT,
        active_segment_id TEXT,
        FOREIGN KEY (baby_id) REFERENCES babies (id) ON DELETE CASCADE,
        FOREIGN KEY (feeding_id) REFERENCES feeding_records (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_feeding_baby_start ON feeding_records (baby_id, started_at)',
    );
    await db.execute(
      'CREATE INDEX idx_segment_feeding ON breastfeeding_segments (feeding_id)',
    );
    await db.execute(
      'CREATE INDEX idx_stool_baby_time ON stool_records (baby_id, occurred_at)',
    );
    await db.execute(
      'CREATE INDEX idx_sleep_baby_start ON sleep_records (baby_id, started_at)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_sleep_ongoing ON sleep_records (baby_id) WHERE ended_at IS NULL',
    );
  }
}
