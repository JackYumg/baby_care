import 'dart:convert';

import 'package:baby_care/data/app_database.dart';
import 'package:baby_care/data/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> _babyRow() => {
  'id': 'b1',
  'nickname': '小满',
  'birth_date': 1000,
  'sex': 'girl',
  'avatar_key': 'default',
  'created_at': 1,
  'updated_at': 1,
};

Map<String, Object?> _stoolRow({String? imagePath}) => {
  'id': 's1',
  'baby_id': 'b1',
  'occurred_at': 2000,
  'color': 'yellow',
  'consistency': 'soft',
  'note': '正常',
  'image_path': imagePath,
  'created_at': 2000,
  'updated_at': 2000,
};

void main() {
  sqfliteFfiInit();

  late Database db;
  late Map<String, String> files;

  BackupService service() => BackupService(
    db,
    readAttachments: () async => Map<String, String>.of(files),
    writeAttachments: (data) async {
      files
        ..clear()
        ..addAll(data);
    },
    pruneAttachments: (keep) async {
      files.removeWhere((path, _) => !keep.contains(path));
    },
  );

  setUp(() async {
    db = await AppDatabase.open(
      filePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    files = {};
  });

  tearDown(() => db.close());

  test('v2 导出解析恢复：新表与附件往返一致', () async {
    await db.insert('babies', _babyRow());
    await db.insert('stool_records', _stoolRow(imagePath: 'stool/s1.jpg'));
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
      'items': '[{"label":"体重","done":true,"result":"正常"}]',
      'note': null,
      'image_path': 'checkup/c1.jpg',
      'completed_at': null,
      'created_at': 4000,
      'updated_at': 4000,
    });
    await db.insert('vaccine_records', {
      'id': 'v1',
      'baby_id': 'b1',
      'name': '乙肝',
      'dose': 2,
      'scheduled_at': 5000,
      'status': 'done',
      'administered_at': 5100,
      'fever': 1,
      'temperature': 38.5,
      'note': '轻微发烧',
      'created_at': 5000,
      'updated_at': 5000,
    });
    files = {
      'stool/s1.jpg': base64Encode(const [1, 2, 3]),
      'checkup/c1.jpg': base64Encode(const [4, 5, 6, 7]),
      // 未被任何记录引用的孤儿图片，恢复后应被清理。
      'stool/orphan.jpg': base64Encode(const [9]),
    };

    final backup = service();
    final json = await backup.exportJson(nowMs: 6000);
    final root = jsonDecode(json) as Map<String, Object?>;
    expect(root['version'], 2);
    expect(root['growth_records'], hasLength(1));
    expect(root['checkup_plans'], hasLength(1));
    expect(root['vaccine_records'], hasLength(1));
    expect((root['attachments']! as Map), hasLength(3));

    final payload = backup.parseAndValidate(json);
    expect(payload.growths, hasLength(1));
    expect(payload.checkups, hasLength(1));
    expect(payload.vaccines, hasLength(1));
    expect(payload.attachments, hasLength(3));

    // 恢复前写入无关数据，恢复后应被清空。
    await db.insert('growth_records', {
      'id': 'g2',
      'baby_id': 'b1',
      'measured_at': 7000,
      'created_at': 7000,
      'updated_at': 7000,
    });

    await backup.restore(payload);

    expect((await db.query('growth_records')).single['id'], 'g1');
    final checkup = (await db.query('checkup_plans')).single;
    expect(checkup['title'], '42 天儿保');
    expect(checkup['image_path'], 'checkup/c1.jpg');
    final vaccine = (await db.query('vaccine_records')).single;
    expect(vaccine['dose'], 2);
    expect(vaccine['fever'], 1);
    expect(vaccine['temperature'], 38.5);
    expect(
      (await db.query('stool_records')).single['image_path'],
      'stool/s1.jpg',
    );

    // 附件已写回，孤儿文件被清理。
    expect(files.keys.toSet(), {'stool/s1.jpg', 'checkup/c1.jpg'});
    expect(base64Decode(files['stool/s1.jpg']!), [1, 2, 3]);
    expect(base64Decode(files['checkup/c1.jpg']!), [4, 5, 6, 7]);
  });

  test('新表字段在备份中恒存在，空数据也输出空列表', () async {
    await db.insert('babies', _babyRow());
    final json = await service().exportJson(nowMs: 1);
    final root = jsonDecode(json) as Map<String, Object?>;
    expect(root['growth_records'], isEmpty);
    expect(root['checkup_plans'], isEmpty);
    expect(root['vaccine_records'], isEmpty);
    expect(root['attachments'], isA<Map<Object?, Object?>>());
    expect(root['attachments'], isEmpty);
  });

  test('导入 v1 备份不报错，新表为空且排便图片路径为空', () async {
    final v1 = jsonEncode({
      'format': kBackupFormat,
      'version': 1,
      'exported_at': 1000,
      'timezone': 'Asia/Shanghai',
      'babies': [_babyRow()],
      'feeding_records': <Object?>[],
      'breastfeeding_segments': <Object?>[],
      'stool_records': [
        {
          'id': 's1',
          'baby_id': 'b1',
          'occurred_at': 2000,
          'color': 'yellow',
          'consistency': 'soft',
          'note': null,
          'created_at': 2000,
          'updated_at': 2000,
        },
      ],
      'sleep_records': <Object?>[],
      'active_feeding_sessions': <Object?>[],
      'app_settings': <Object?>[],
    });

    final backup = service();
    final payload = backup.parseAndValidate(v1);
    expect(payload.growths, isEmpty);
    expect(payload.checkups, isEmpty);
    expect(payload.vaccines, isEmpty);
    expect(payload.attachments, isEmpty);

    // 恢复前放入旧图片，v1 恢复后图片目录被清空。
    files = {
      'stool/old.jpg': base64Encode(const [1]),
    };
    await backup.restore(payload);

    expect(await db.query('growth_records'), isEmpty);
    expect(await db.query('checkup_plans'), isEmpty);
    expect(await db.query('vaccine_records'), isEmpty);
    expect((await db.query('stool_records')).single['image_path'], isNull);
    expect(files, isEmpty);
  });

  group('校验失败', () {
    Future<String> validJson() async {
      await db.insert('babies', _babyRow());
      await db.insert('checkup_plans', {
        'id': 'c1',
        'baby_id': 'b1',
        'title': '42 天儿保',
        'scheduled_at': 4000,
        'status': 'pending',
        'items': '[]',
        'created_at': 4000,
        'updated_at': 4000,
      });
      await db.insert('vaccine_records', {
        'id': 'v1',
        'baby_id': 'b1',
        'name': '乙肝',
        'dose': 1,
        'scheduled_at': 5000,
        'status': 'pending',
        'fever': 0,
        'created_at': 5000,
        'updated_at': 5000,
      });
      files = {
        'stool/x.jpg': base64Encode(const [1]),
      };
      return service().exportJson(nowMs: 1);
    }

    Map<String, Object?> decode(String json) =>
        jsonDecode(json) as Map<String, Object?>;

    void expectRejected(String json) {
      expect(
        () => service().parseAndValidate(json),
        throwsA(isA<BackupException>()),
      );
    }

    test('非法待办状态', () async {
      final root = decode(await validJson());
      ((root['vaccine_records']! as List).first
              as Map<String, Object?>)['status'] =
          'unknown';
      expectRejected(jsonEncode(root));
    });

    test('未知 baby_id', () async {
      final root = decode(await validJson());
      ((root['checkup_plans']! as List).first
              as Map<String, Object?>)['baby_id'] =
          'missing';
      expectRejected(jsonEncode(root));
    });

    test('疫苗剂次与体温非法', () async {
      final root = decode(await validJson());
      final vaccine =
          (root['vaccine_records']! as List).first as Map<String, Object?>;
      vaccine['dose'] = 0;
      expectRejected(jsonEncode(root));

      vaccine['dose'] = 1;
      vaccine['temperature'] = 50;
      expectRejected(jsonEncode(root));
    });

    test('儿保检查项不是数组', () async {
      final root = decode(await validJson());
      ((root['checkup_plans']! as List).first
              as Map<String, Object?>)['items'] =
          '{"label":"体重"}';
      expectRejected(jsonEncode(root));
    });

    test('非法图片路径', () async {
      final root = decode(await validJson());
      ((root['checkup_plans']! as List).first
              as Map<String, Object?>)['image_path'] =
          '../evil.jpg';
      expectRejected(jsonEncode(root));
    });

    test('附件路径非法或不是 base64', () async {
      final root = decode(await validJson());
      root['attachments'] = {
        '../evil.jpg': base64Encode(const [1]),
      };
      expectRejected(jsonEncode(root));

      root['attachments'] = {'stool/x.jpg': '@@@'};
      expectRejected(jsonEncode(root));
    });
  });

  test('导出超过体积上限时报错', () async {
    await db.insert('babies', _babyRow());
    await expectLater(
      service().exportJson(nowMs: 1, maxBytes: 16),
      throwsA(isA<BackupException>()),
    );
  });
}
