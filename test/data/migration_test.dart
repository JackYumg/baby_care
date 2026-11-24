import 'dart:io';

import 'package:baby_care/data/app_database.dart';
import 'package:baby_care/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 手写 v2 结构，用于验证真实升级路径。
Future<void> _createV2Schema(Database db) async {
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
    CREATE TABLE app_settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
  ''');
}

Future<void> _seedV2(Database db) async {
  await db.insert('babies', {
    'id': 'b1',
    'nickname': '小满',
    'birth_date': DateTime(2026, 1, 31).millisecondsSinceEpoch,
    'sex': 'girl',
    'avatar_key': 'default',
    'created_at': 1,
    'updated_at': 1,
  });
  await db.insert('feeding_records', {
    'id': 'f1',
    'baby_id': 'b1',
    'mode': 'bottle',
    'started_at': 1000,
    'ended_at': 1000,
    'amount_ml': 90,
    'milk_type': 'formula',
    'note': '旧喂奶',
    'remind_at': 123456,
    'created_at': 1000,
    'updated_at': 1000,
  });
  await db.insert('stool_records', {
    'id': 's1',
    'baby_id': 'b1',
    'occurred_at': 2000,
    'color': 'yellow',
    'consistency': 'soft',
    'note': '旧排便',
    'created_at': 2000,
    'updated_at': 2000,
  });
}

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('baby_care_migration');
    dbPath = p.join(tempDir.path, 'yuying.db');
    final oldDb = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) => _createV2Schema(db),
      ),
    );
    await _seedV2(oldDb);
    await oldDb.close();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('v2 升级到 v3：旧数据保留、新列与新表可用', () async {
    final db = await AppDatabase.open(
      filePath: dbPath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    expect((await db.getVersion()), 3);

    final feeding = (await db.query('feeding_records')).single;
    expect(feeding['note'], '旧喂奶');
    expect(feeding['remind_at'], 123456);

    final stool = (await db.query('stool_records')).single;
    expect(stool['note'], '旧排便');
    expect(stool['image_path'], isNull);

    // 新列可写。
    await db.update(
      'stool_records',
      {'image_path': 'stool/old.jpg'},
      where: 'id = ?',
      whereArgs: ['s1'],
    );
    expect(
      (await db.query('stool_records')).single['image_path'],
      'stool/old.jpg',
    );

    // 三张新表可写、可读。
    await db.insert('growth_records', {
      'id': 'g1',
      'baby_id': 'b1',
      'measured_at': 3000,
      'height_cm': 63.5,
      'weight_kg': 6.8,
      'head_cm': 41.0,
      'note': null,
      'created_at': 3000,
      'updated_at': 3000,
    });
    await db.insert('checkup_plans', {
      'id': 'c1',
      'baby_id': 'b1',
      'title': '42 天儿保',
      'scheduled_at': 4000,
      'status': 'pending',
      'items': '[{"label":"体重","done":false,"result":null}]',
      'created_at': 4000,
      'updated_at': 4000,
    });
    await db.insert('vaccine_records', {
      'id': 'v1',
      'baby_id': 'b1',
      'name': '乙肝',
      'dose': 1,
      'scheduled_at': 5000,
      'created_at': 5000,
      'updated_at': 5000,
    });

    final growth = GrowthRecord.fromMap(
      (await db.query('growth_records')).single,
    );
    expect(growth.weightKg, 6.8);
    expect(growth.heightCm, 63.5);

    final checkup = CheckupPlan.fromMap(
      (await db.query('checkup_plans')).single,
    );
    expect(checkup.title, '42 天儿保');
    expect(checkup.items.single.label, '体重');
    expect(checkup.status, CareTaskStatus.pending);

    final vaccine = VaccineRecord.fromMap(
      (await db.query('vaccine_records')).single,
    );
    expect(vaccine.name, '乙肝');
    expect(vaccine.dose, 1);
    expect(vaccine.fever, isFalse);

    // 新索引已建立。
    final indexes = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name LIKE ?',
      whereArgs: ['index', 'idx_%'],
    );
    final names = indexes.map((row) => row['name'] as String).toSet();
    expect(names, contains('idx_growth_baby_time'));
    expect(names, contains('idx_checkup_baby_time'));
    expect(names, contains('idx_vaccine_baby_time'));
  });

  test('删除宝宝时新表记录级联清理', () async {
    final db = await AppDatabase.open(
      filePath: dbPath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    await db.insert('growth_records', {
      'id': 'g1',
      'baby_id': 'b1',
      'measured_at': 3000,
      'created_at': 3000,
      'updated_at': 3000,
    });
    await db.insert('vaccine_records', {
      'id': 'v1',
      'baby_id': 'b1',
      'name': '乙肝',
      'dose': 1,
      'scheduled_at': 5000,
      'created_at': 5000,
      'updated_at': 5000,
    });

    await db.delete('babies', where: 'id = ?', whereArgs: ['b1']);

    expect(await db.query('growth_records'), isEmpty);
    expect(await db.query('vaccine_records'), isEmpty);
  });
}
