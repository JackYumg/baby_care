import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';

const _uuid = Uuid();

class BabyRepository {
  BabyRepository(this.db);

  final Database db;

  Future<List<Baby>> list() async {
    final rows = await db.query('babies', orderBy: 'created_at ASC');
    return rows.map(Baby.fromMap).toList();
  }

  Future<Baby?> byId(String id) async {
    final rows = await db.query('babies', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Baby.fromMap(rows.first);
  }

  Future<void> insert(Baby baby) async {
    await db.insert('babies', baby.toMap());
  }

  Future<void> update(Baby baby) async {
    await db.update(
      'babies',
      baby.toMap(),
      where: 'id = ?',
      whereArgs: [baby.id],
    );
  }

  Future<void> delete(String id) async {
    await db.delete('babies', where: 'id = ?', whereArgs: [id]);
  }
}

class SettingsRepository {
  SettingsRepository(this.db);

  final Database db;

  Future<String?> get(String key) async {
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> set(String key, String? value) async {
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

class RecordRepository {
  RecordRepository(this.db);

  final Database db;

  // ---------- 喝奶 ----------

  Future<List<FeedingRecord>> feedingsOverlapping(
    String babyId,
    int start,
    int end,
  ) async {
    final rows = await db.query(
      'feeding_records',
      where:
          'baby_id = ? AND started_at < ? AND (ended_at IS NULL OR ended_at > ?)',
      whereArgs: [babyId, end, start],
      orderBy: 'started_at DESC',
    );
    return rows.map(FeedingRecord.fromMap).toList();
  }

  Future<Map<String, List<FeedingSegment>>> segmentsFor(
    List<String> feedingIds,
  ) async {
    if (feedingIds.isEmpty) return {};
    final placeholders = List.filled(feedingIds.length, '?').join(',');
    final rows = await db.query(
      'breastfeeding_segments',
      where: 'feeding_id IN ($placeholders)',
      whereArgs: feedingIds,
      orderBy: 'started_at ASC',
    );
    final result = <String, List<FeedingSegment>>{};
    for (final row in rows) {
      final segment = FeedingSegment.fromMap(row);
      result.putIfAbsent(segment.feedingId, () => []).add(segment);
    }
    return result;
  }

  Future<String> insertBottleFeeding({
    required String babyId,
    required int startedAt,
    required int amountMl,
    required MilkType milkType,
    String? note,
    int? remindAt,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await db.insert('feeding_records', {
      'id': id,
      'baby_id': babyId,
      'mode': FeedMode.bottle.name,
      'started_at': startedAt,
      'ended_at': startedAt,
      'amount_ml': amountMl,
      'milk_type': milkType.name,
      'note': note,
      'remind_at': remindAt,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<void> updateBottleFeeding({
    required String id,
    required int startedAt,
    required int amountMl,
    required MilkType milkType,
    String? note,
    int? remindAt,
  }) async {
    await db.update(
      'feeding_records',
      {
        'started_at': startedAt,
        'ended_at': startedAt,
        'amount_ml': amountMl,
        'milk_type': milkType.name,
        'note': note,
        'remind_at': remindAt,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 最近一条已完成的喂奶记录（排除进行中的亲喂）。
  Future<FeedingRecord?> latestFeeding(String babyId) async {
    final rows = await db.rawQuery(
      '''
      SELECT f.* FROM feeding_records f
      WHERE f.baby_id = ?
        AND NOT EXISTS (
          SELECT 1 FROM active_feeding_sessions a WHERE a.feeding_id = f.id
        )
      ORDER BY COALESCE(f.ended_at, f.started_at) DESC
      LIMIT 1
      ''',
      [babyId],
    );
    if (rows.isEmpty) return null;
    return FeedingRecord.fromMap(rows.first);
  }

  Future<void> setFeedingRemindAt(String id, int? remindAt) async {
    await db.update(
      'feeding_records',
      {
        'remind_at': remindAt,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 手动补录亲喂：按左侧、右侧顺序生成连续分段。
  Future<String> insertManualDirectFeeding({
    required String babyId,
    required int startedAt,
    required int leftMinutes,
    required int rightMinutes,
    String? note,
  }) async {
    if (leftMinutes <= 0 && rightMinutes <= 0) {
      throw ArgumentError('左右侧时长不能同时为 0');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final feedingId = _uuid.v4();
    var cursor = startedAt;
    final segments = <Map<String, Object?>>[];
    for (final entry in [
      (BreastSide.left, leftMinutes),
      (BreastSide.right, rightMinutes),
    ]) {
      if (entry.$2 <= 0) continue;
      final end = cursor + entry.$2 * 60 * 1000;
      segments.add({
        'id': _uuid.v4(),
        'feeding_id': feedingId,
        'side': entry.$1.name,
        'started_at': cursor,
        'ended_at': end,
      });
      cursor = end;
    }
    await db.transaction((txn) async {
      await txn.insert('feeding_records', {
        'id': feedingId,
        'baby_id': babyId,
        'mode': FeedMode.direct.name,
        'started_at': startedAt,
        'ended_at': cursor,
        'amount_ml': null,
        'milk_type': null,
        'note': note,
        'created_at': now,
        'updated_at': now,
      });
      for (final segment in segments) {
        await txn.insert('breastfeeding_segments', segment);
      }
    });
    return feedingId;
  }

  Future<void> deleteFeeding(String id) async {
    await db.delete('feeding_records', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 亲喂计时 ----------

  Future<ActiveFeeding?> activeFeeding(String babyId) async {
    final rows = await db.query(
      'active_feeding_sessions',
      where: 'baby_id = ?',
      whereArgs: [babyId],
    );
    if (rows.isEmpty) return null;
    return ActiveFeeding.fromMap(rows.first);
  }

  Future<void> startDirectFeeding(String babyId, int nowMs) async {
    await db.transaction((txn) async {
      final existing = await txn.query(
        'active_feeding_sessions',
        where: 'baby_id = ?',
        whereArgs: [babyId],
      );
      if (existing.isNotEmpty) {
        throw StateError('该宝宝已有进行中的亲喂');
      }
      final feedingId = _uuid.v4();
      final segmentId = _uuid.v4();
      await txn.insert('feeding_records', {
        'id': feedingId,
        'baby_id': babyId,
        'mode': FeedMode.direct.name,
        'started_at': nowMs,
        'ended_at': nowMs,
        'amount_ml': null,
        'milk_type': null,
        'note': null,
        'created_at': nowMs,
        'updated_at': nowMs,
      });
      await txn.insert('breastfeeding_segments', {
        'id': segmentId,
        'feeding_id': feedingId,
        'side': BreastSide.left.name,
        'started_at': nowMs,
        'ended_at': nowMs,
      });
      await txn.insert('active_feeding_sessions', {
        'baby_id': babyId,
        'feeding_id': feedingId,
        'started_at': nowMs,
        'current_side': BreastSide.left.name,
        'active_segment_id': segmentId,
      });
    });
  }

  Future<void> switchDirectSide(
    String babyId,
    BreastSide side,
    int nowMs,
  ) async {
    await db.transaction((txn) async {
      final active = await _activeInTxn(txn, babyId);
      if (active == null) throw StateError('没有进行中的亲喂');
      if (active.currentSide == side && active.activeSegmentId != null) return;
      if (active.activeSegmentId != null) {
        await txn.update(
          'breastfeeding_segments',
          {'ended_at': nowMs},
          where: 'id = ?',
          whereArgs: [active.activeSegmentId],
        );
      }
      final segmentId = _uuid.v4();
      await txn.insert('breastfeeding_segments', {
        'id': segmentId,
        'feeding_id': active.feedingId,
        'side': side.name,
        'started_at': nowMs,
        'ended_at': nowMs,
      });
      await txn.update(
        'active_feeding_sessions',
        {'current_side': side.name, 'active_segment_id': segmentId},
        where: 'baby_id = ?',
        whereArgs: [babyId],
      );
      await txn.update(
        'feeding_records',
        {'ended_at': nowMs},
        where: 'id = ?',
        whereArgs: [active.feedingId],
      );
    });
  }

  Future<void> pauseDirectFeeding(String babyId, int nowMs) async {
    await db.transaction((txn) async {
      final active = await _activeInTxn(txn, babyId);
      if (active == null || active.isPaused) return;
      if (active.activeSegmentId != null) {
        await txn.update(
          'breastfeeding_segments',
          {'ended_at': nowMs},
          where: 'id = ?',
          whereArgs: [active.activeSegmentId],
        );
      }
      await txn.update(
        'active_feeding_sessions',
        {'current_side': null, 'active_segment_id': null},
        where: 'baby_id = ?',
        whereArgs: [babyId],
      );
      await txn.update(
        'feeding_records',
        {'ended_at': nowMs},
        where: 'id = ?',
        whereArgs: [active.feedingId],
      );
    });
  }

  Future<void> resumeDirectFeeding(
    String babyId,
    BreastSide side,
    int nowMs,
  ) async {
    await db.transaction((txn) async {
      final active = await _activeInTxn(txn, babyId);
      if (active == null) throw StateError('没有进行中的亲喂');
      final segmentId = _uuid.v4();
      await txn.insert('breastfeeding_segments', {
        'id': segmentId,
        'feeding_id': active.feedingId,
        'side': side.name,
        'started_at': nowMs,
        'ended_at': nowMs,
      });
      await txn.update(
        'active_feeding_sessions',
        {'current_side': side.name, 'active_segment_id': segmentId},
        where: 'baby_id = ?',
        whereArgs: [babyId],
      );
      await txn.update(
        'feeding_records',
        {'ended_at': nowMs},
        where: 'id = ?',
        whereArgs: [active.feedingId],
      );
    });
  }

  Future<String> finishDirectFeeding(String babyId, int nowMs) async {
    return db.transaction((txn) async {
      final active = await _activeInTxn(txn, babyId);
      if (active == null) throw StateError('没有进行中的亲喂');
      if (nowMs <= active.startedAt) {
        throw ArgumentError('结束时间必须晚于开始时间');
      }
      if (active.activeSegmentId != null) {
        await txn.update(
          'breastfeeding_segments',
          {'ended_at': nowMs},
          where: 'id = ?',
          whereArgs: [active.activeSegmentId],
        );
      }
      await txn.update(
        'feeding_records',
        {'ended_at': nowMs, 'updated_at': nowMs},
        where: 'id = ?',
        whereArgs: [active.feedingId],
      );
      await txn.delete(
        'active_feeding_sessions',
        where: 'baby_id = ?',
        whereArgs: [babyId],
      );
      return active.feedingId;
    });
  }

  Future<void> discardDirectFeeding(String babyId) async {
    await db.transaction((txn) async {
      final active = await _activeInTxn(txn, babyId);
      if (active == null) return;
      await txn.delete(
        'active_feeding_sessions',
        where: 'baby_id = ?',
        whereArgs: [babyId],
      );
      await txn.delete(
        'feeding_records',
        where: 'id = ?',
        whereArgs: [active.feedingId],
      );
    });
  }

  Future<ActiveFeeding?> _activeInTxn(Transaction txn, String babyId) async {
    final rows = await txn.query(
      'active_feeding_sessions',
      where: 'baby_id = ?',
      whereArgs: [babyId],
    );
    if (rows.isEmpty) return null;
    return ActiveFeeding.fromMap(rows.first);
  }

  // ---------- 排便 ----------

  Future<List<StoolRecord>> stoolsBetween(
    String babyId,
    int start,
    int end,
  ) async {
    final rows = await db.query(
      'stool_records',
      where: 'baby_id = ? AND occurred_at >= ? AND occurred_at < ?',
      whereArgs: [babyId, start, end],
      orderBy: 'occurred_at DESC',
    );
    return rows.map(StoolRecord.fromMap).toList();
  }

  Future<String> insertStool({
    required String babyId,
    required int occurredAt,
    StoolColor? color,
    String? consistency,
    String? note,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await db.insert('stool_records', {
      'id': id,
      'baby_id': babyId,
      'occurred_at': occurredAt,
      'color': color?.name,
      'consistency': consistency,
      'note': note,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<void> updateStool({
    required String id,
    required int occurredAt,
    StoolColor? color,
    String? consistency,
    String? note,
  }) async {
    await db.update(
      'stool_records',
      {
        'occurred_at': occurredAt,
        'color': color?.name,
        'consistency': consistency,
        'note': note,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteStool(String id) async {
    await db.delete('stool_records', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 睡眠 ----------

  Future<List<SleepRecord>> sleepsOverlapping(
    String babyId,
    int start,
    int end,
  ) async {
    final rows = await db.query(
      'sleep_records',
      where:
          'baby_id = ? AND started_at < ? AND (ended_at IS NULL OR ended_at > ?)',
      whereArgs: [babyId, end, start],
      orderBy: 'started_at DESC',
    );
    return rows.map(SleepRecord.fromMap).toList();
  }

  Future<SleepRecord?> ongoingSleep(String babyId) async {
    final rows = await db.query(
      'sleep_records',
      where: 'baby_id = ? AND ended_at IS NULL',
      whereArgs: [babyId],
    );
    if (rows.isEmpty) return null;
    return SleepRecord.fromMap(rows.first);
  }

  Future<bool> hasSleepOverlap({
    required String babyId,
    required int start,
    required int end,
    String? excludeId,
  }) async {
    final rows = await db.query(
      'sleep_records',
      columns: ['id'],
      where: excludeId == null
          ? 'baby_id = ? AND started_at < ? AND (ended_at IS NULL OR ended_at > ?)'
          : 'baby_id = ? AND id <> ? AND started_at < ? AND (ended_at IS NULL OR ended_at > ?)',
      whereArgs: excludeId == null
          ? [babyId, end, start]
          : [babyId, excludeId, end, start],
    );
    return rows.isNotEmpty;
  }

  Future<String> startSleep(String babyId, int nowMs) async {
    if (await ongoingSleep(babyId) != null) {
      throw StateError('该宝宝已有进行中的睡眠');
    }
    if (await hasSleepOverlap(babyId: babyId, start: nowMs, end: nowMs + 1)) {
      throw StateError('睡眠时间与已有记录重叠');
    }
    final id = _uuid.v4();
    await db.insert('sleep_records', {
      'id': id,
      'baby_id': babyId,
      'started_at': nowMs,
      'ended_at': null,
      'note': null,
      'created_at': nowMs,
      'updated_at': nowMs,
    });
    return id;
  }

  Future<void> endSleep(String id, int nowMs) async {
    final rows = await db.query(
      'sleep_records',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('睡眠记录不存在');
    final record = SleepRecord.fromMap(rows.first);
    if (nowMs <= record.startedAt) {
      throw ArgumentError('结束时间必须晚于开始时间');
    }
    await db.update(
      'sleep_records',
      {'ended_at': nowMs, 'updated_at': nowMs},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<String> insertManualSleep({
    required String babyId,
    required int startedAt,
    required int endedAt,
    String? note,
  }) async {
    if (endedAt <= startedAt) {
      throw ArgumentError('结束时间必须晚于开始时间');
    }
    if (await hasSleepOverlap(babyId: babyId, start: startedAt, end: endedAt)) {
      throw StateError('睡眠时间与已有记录重叠');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await db.insert('sleep_records', {
      'id': id,
      'baby_id': babyId,
      'started_at': startedAt,
      'ended_at': endedAt,
      'note': note,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<void> updateSleep({
    required String id,
    required String babyId,
    required int startedAt,
    required int endedAt,
    String? note,
  }) async {
    if (endedAt <= startedAt) {
      throw ArgumentError('结束时间必须晚于开始时间');
    }
    if (await hasSleepOverlap(
      babyId: babyId,
      start: startedAt,
      end: endedAt,
      excludeId: id,
    )) {
      throw StateError('睡眠时间与已有记录重叠');
    }
    await db.update(
      'sleep_records',
      {
        'started_at': startedAt,
        'ended_at': endedAt,
        'note': note,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSleep(String id) async {
    await db.delete('sleep_records', where: 'id = ?', whereArgs: [id]);
  }
}
