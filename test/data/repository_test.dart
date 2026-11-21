import 'package:baby_care/data/app_database.dart';
import 'package:baby_care/data/backup_service.dart';
import 'package:baby_care/data/repositories.dart';
import 'package:baby_care/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Baby _baby(String id, String nickname, int createdAt) => Baby(
  id: id,
  nickname: nickname,
  birthDate: DateTime(2025, 1, 1),
  createdAt: createdAt,
  updatedAt: createdAt,
);

void main() {
  sqfliteFfiInit();

  late Database db;
  late BabyRepository babyRepo;
  late RecordRepository recordRepo;

  setUp(() async {
    db = await AppDatabase.open(
      filePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    babyRepo = BabyRepository(db);
    recordRepo = RecordRepository(db);
    await babyRepo.insert(_baby('a', '小满', 1));
    await babyRepo.insert(_baby('b', '小安', 2));
  });

  tearDown(() => db.close());

  test('记录按宝宝隔离', () async {
    final dayStart = DateTime.utc(2026, 11, 20, 16).millisecondsSinceEpoch;
    final dayEnd = dayStart + const Duration(days: 1).inMilliseconds;
    await recordRepo.insertBottleFeeding(
      babyId: 'a',
      startedAt: dayStart + 3600000,
      amountMl: 90,
      milkType: MilkType.breastMilk,
    );
    await recordRepo.insertBottleFeeding(
      babyId: 'b',
      startedAt: dayStart + 3600000,
      amountMl: 60,
      milkType: MilkType.formula,
    );

    final a = await recordRepo.feedingsOverlapping('a', dayStart, dayEnd);
    final b = await recordRepo.feedingsOverlapping('b', dayStart, dayEnd);
    expect(a.single.amountMl, 90);
    expect(b.single.amountMl, 60);
  });

  test('亲喂计时按侧累计，暂停时间不计入', () async {
    const start = 1000000;
    await recordRepo.startDirectFeeding('a', start);
    await recordRepo.switchDirectSide('a', BreastSide.right, start + 60000);
    await recordRepo.pauseDirectFeeding('a', start + 120000);
    await recordRepo.resumeDirectFeeding('a', BreastSide.left, start + 180000);
    final feedingId = await recordRepo.finishDirectFeeding('a', start + 240000);

    expect(await recordRepo.activeFeeding('a'), isNull);
    final segments = (await recordRepo.segmentsFor([feedingId]))[feedingId]!;
    expect(segments, hasLength(3));
    int total(BreastSide side) => segments
        .where((s) => s.side == side)
        .fold(0, (sum, s) => sum + s.seconds);
    expect(total(BreastSide.left), 120);
    expect(total(BreastSide.right), 60);
  });

  test('同一宝宝不能重复开始亲喂', () async {
    await recordRepo.startDirectFeeding('a', 1000);
    await expectLater(
      recordRepo.startDirectFeeding('a', 2000),
      throwsStateError,
    );
  });

  test('亲喂结束时间必须晚于开始时间', () async {
    await recordRepo.startDirectFeeding('a', 1000);
    await expectLater(
      recordRepo.finishDirectFeeding('a', 1000),
      throwsArgumentError,
    );
  });

  test('睡眠重叠被拒绝，首尾相接允许', () async {
    await recordRepo.insertManualSleep(
      babyId: 'a',
      startedAt: 0,
      endedAt: 3600000,
    );
    await expectLater(
      recordRepo.insertManualSleep(
        babyId: 'a',
        startedAt: 1800000,
        endedAt: 5400000,
      ),
      throwsStateError,
    );
    final adjacent = await recordRepo.insertManualSleep(
      babyId: 'a',
      startedAt: 3600000,
      endedAt: 7200000,
    );
    expect(adjacent, isNotEmpty);
  });

  test('同一宝宝只允许一段进行中睡眠', () async {
    await recordRepo.startSleep('a', 1000);
    await expectLater(recordRepo.startSleep('a', 2000), throwsStateError);
    expect(await recordRepo.ongoingSleep('a'), isNotNull);
  });

  test('删除宝宝级联清理记录与亲喂分段', () async {
    const t = 1000000;
    await recordRepo.insertBottleFeeding(
      babyId: 'a',
      startedAt: t,
      amountMl: 100,
      milkType: MilkType.formula,
    );
    await recordRepo.insertManualDirectFeeding(
      babyId: 'a',
      startedAt: t,
      leftMinutes: 5,
      rightMinutes: 5,
    );
    await recordRepo.insertStool(babyId: 'a', occurredAt: t);
    await recordRepo.insertManualSleep(
      babyId: 'a',
      startedAt: t,
      endedAt: t + 60000,
    );
    await recordRepo.startSleep('b', t);

    await babyRepo.delete('a');

    expect(
      await db.query('feeding_records', where: 'baby_id = ?', whereArgs: ['a']),
      isEmpty,
    );
    expect(await db.query('breastfeeding_segments'), isEmpty);
    expect(await db.query('stool_records'), isEmpty);
    expect(await db.query('sleep_records'), hasLength(1));
    expect(await recordRepo.ongoingSleep('b'), isNotNull);
  });

  test('备份导出后校验并覆盖恢复', () async {
    final backup = BackupService(db);
    await recordRepo.insertBottleFeeding(
      babyId: 'a',
      startedAt: 1000,
      amountMl: 90,
      milkType: MilkType.breastMilk,
    );
    final json = await backup.exportJson(nowMs: 2000);
    final payload = backup.parseAndValidate(json);
    expect(payload.babies, hasLength(2));
    expect(payload.feedings, hasLength(1));

    await recordRepo.insertStool(babyId: 'a', occurredAt: 3000);
    await recordRepo.insertBottleFeeding(
      babyId: 'b',
      startedAt: 4000,
      amountMl: 60,
      milkType: MilkType.formula,
    );
    await backup.restore(payload);

    expect(await db.query('feeding_records'), hasLength(1));
    expect(await db.query('stool_records'), isEmpty);
    expect(await babyRepo.list(), hasLength(2));
  });

  test('拒绝损坏与版本过新的备份', () {
    final backup = BackupService(db);
    expect(
      () => backup.parseAndValidate('not-json'),
      throwsA(isA<BackupException>()),
    );
    expect(
      () => backup.parseAndValidate(
        '{"format":"yuying-backup","version":99,"babies":[]}',
      ),
      throwsA(isA<BackupException>()),
    );
    expect(
      () => backup.parseAndValidate(
        '{"format":"yuying-backup","version":1,"babies":[]}',
      ),
      throwsA(isA<BackupException>()),
    );
  });
}
