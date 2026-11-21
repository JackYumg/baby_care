import 'package:baby_care/domain/daily_statistics.dart';
import 'package:baby_care/domain/models.dart';
import 'package:baby_care/domain/time_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const _babyId = 'baby-a';
final _day = DateTime.utc(2026, 11, 21);

FeedingRecord _bottle(String id, int startedAt, int ml) => FeedingRecord(
  id: id,
  babyId: _babyId,
  mode: FeedMode.bottle,
  startedAt: startedAt,
  endedAt: startedAt,
  amountMl: ml,
  milkType: MilkType.formula,
  createdAt: 0,
  updatedAt: 0,
);

FeedingRecord _direct(String id, int startedAt, int endedAt) => FeedingRecord(
  id: id,
  babyId: _babyId,
  mode: FeedMode.direct,
  startedAt: startedAt,
  endedAt: endedAt,
  createdAt: 0,
  updatedAt: 0,
);

FeedingSegment _segment(
  String feedingId,
  BreastSide side,
  int startedAt,
  int endedAt,
) => FeedingSegment(
  id: '$feedingId-${side.name}-$startedAt',
  feedingId: feedingId,
  side: side,
  startedAt: startedAt,
  endedAt: endedAt,
);

SleepRecord _sleep(String id, int startedAt, int? endedAt) => SleepRecord(
  id: id,
  babyId: _babyId,
  startedAt: startedAt,
  endedAt: endedAt,
  createdAt: 0,
  updatedAt: 0,
);

StoolRecord _stool(String id, int occurredAt) => StoolRecord(
  id: id,
  babyId: _babyId,
  occurredAt: occurredAt,
  createdAt: 0,
  updatedAt: 0,
);

DailySummary _summary({
  List<FeedingRecord> feedings = const [],
  Map<String, List<FeedingSegment>> segments = const {},
  List<SleepRecord> sleeps = const [],
  List<StoolRecord> stools = const [],
  int? nowMs,
  DateTime? date,
}) => computeDailySummary(
  statDate: date ?? _day,
  feedings: feedings,
  segmentsByFeeding: segments,
  sleeps: sleeps,
  stools: stools,
  nowMs: nowMs ?? dayEndMs(date ?? _day),
);

void main() {
  group('每日汇总', () {
    test('瓶喂累加毫升，亲喂统计次数与左右时长', () {
      final feeding1 = _bottle('f1', combineStatDateTime(_day, 8, 0), 90);
      final feeding2 = _bottle('f2', combineStatDateTime(_day, 12, 0), 120);
      final direct = _direct(
        'f3',
        combineStatDateTime(_day, 15, 0),
        combineStatDateTime(_day, 15, 10),
      );
      final summary = _summary(
        feedings: [feeding1, feeding2, direct],
        segments: {
          'f3': [
            _segment(
              'f3',
              BreastSide.left,
              combineStatDateTime(_day, 15, 0),
              combineStatDateTime(_day, 15, 5),
            ),
            _segment(
              'f3',
              BreastSide.right,
              combineStatDateTime(_day, 15, 5),
              combineStatDateTime(_day, 15, 10),
            ),
          ],
        },
      );
      expect(summary.bottleMl, 210);
      expect(summary.directSessions, 1);
      expect(summary.directSeconds, 600);
    });

    test('亲喂跨日按分段拆分，次数归开始日', () {
      final start = combineStatDateTime(_day, 23, 55);
      final end = combineStatDateTime(addDays(_day, 1), 0, 5);
      final direct = _direct('f1', start, end);
      final segments = {
        'f1': [_segment('f1', BreastSide.left, start, end)],
      };
      expect(
        _summary(feedings: [direct], segments: segments).directSeconds,
        300,
      );
      expect(
        _summary(
          feedings: [direct],
          segments: segments,
          date: addDays(_day, 1),
        ).directSeconds,
        300,
      );
      expect(
        _summary(
          feedings: [direct],
          segments: segments,
          date: addDays(_day, 1),
        ).directSessions,
        0,
      );
    });

    test('睡眠按交集累计，跨日一致', () {
      final start = combineStatDateTime(_day, 23, 0);
      final end = combineStatDateTime(addDays(_day, 1), 2, 0);
      final sleep = _sleep('s1', start, end);
      expect(_summary(sleeps: [sleep]).sleepSeconds, 3600);
      expect(
        _summary(sleeps: [sleep], date: addDays(_day, 1)).sleepSeconds,
        7200,
      );
    });

    test('进行中睡眠按当前时间计入并标记', () {
      final start = combineStatDateTime(_day, 21, 0);
      final now = combineStatDateTime(_day, 22, 30);
      final summary = _summary(sleeps: [_sleep('s1', start, null)], nowMs: now);
      expect(summary.sleepSeconds, 5400);
      expect(summary.hasOngoingSleep, isTrue);
      expect(summary.ongoingSleepStartMs, start);
    });

    test('排便按发生时间归档，00:00 属于新一天', () {
      final lastSecond = combineStatDateTime(_day, 0, 0) - 1000;
      final dayStart = combineStatDateTime(_day, 0, 0);
      final nextDayStart = combineStatDateTime(addDays(_day, 1), 0, 0);
      expect(_summary(stools: [_stool('t1', lastSecond)]).stoolCount, 0);
      expect(
        _summary(
          stools: [_stool('t1', lastSecond), _stool('t2', dayStart)],
        ).stoolCount,
        1,
      );
      expect(
        _summary(
          stools: [_stool('t2', nextDayStart)],
          date: addDays(_day, 1),
        ).stoolCount,
        1,
      );
    });
  });

  group('近 7 天趋势', () {
    test('日期升序且数值对应各天', () {
      final series = computeTrend(
        endDate: _day,
        days: 7,
        feedings: [
          _bottle('f1', combineStatDateTime(_day, 9, 0), 150),
          _bottle('f2', combineStatDateTime(addDays(_day, -2), 9, 0), 90),
        ],
        segmentsByFeeding: const {},
        sleeps: [
          _sleep(
            's1',
            combineStatDateTime(addDays(_day, -1), 22, 0),
            combineStatDateTime(_day, 6, 0),
          ),
        ],
        stools: [
          _stool('t1', combineStatDateTime(_day, 10, 0)),
          _stool('t2', combineStatDateTime(_day, 18, 0)),
        ],
        nowMs: dayEndMs(_day),
      );
      expect(series.dates.length, 7);
      expect(series.dates.last, _day);
      expect(series.dates.first, addDays(_day, -6));
      expect(series.bottleMl.last, 150);
      expect(series.bottleMl[4], 90);
      expect(series.stoolCounts.last, 2);
      // 22:00 到次日 06:00，前一天 2 小时，后一天 6 小时。
      expect(series.sleepMinutes[5], 120);
      expect(series.sleepMinutes[6], 360);
    });
  });
}
