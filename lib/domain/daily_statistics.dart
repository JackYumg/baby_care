import 'models.dart';
import 'time_rules.dart';

class DailySummary {
  const DailySummary({
    required this.bottleMl,
    required this.directSeconds,
    required this.directSessions,
    required this.sleepSeconds,
    required this.stoolCount,
    this.hasOngoingSleep = false,
    this.ongoingSleepStartMs,
  });

  final int bottleMl;
  final int directSeconds;
  final int directSessions;
  final int sleepSeconds;
  final int stoolCount;
  final bool hasOngoingSleep;
  final int? ongoingSleepStartMs;

  static const empty = DailySummary(
    bottleMl: 0,
    directSeconds: 0,
    directSessions: 0,
    sleepSeconds: 0,
    stoolCount: 0,
  );
}

DailySummary computeDailySummary({
  required DateTime statDate,
  required List<FeedingRecord> feedings,
  required Map<String, List<FeedingSegment>> segmentsByFeeding,
  required List<SleepRecord> sleeps,
  required List<StoolRecord> stools,
  required int nowMs,
}) {
  final start = dayStartMs(statDate);
  final end = dayEndMs(statDate);

  var bottleMl = 0;
  var directSessions = 0;
  var directSeconds = 0;

  for (final feeding in feedings) {
    final startsToday = feeding.startedAt >= start && feeding.startedAt < end;
    if (feeding.mode == FeedMode.bottle) {
      if (startsToday) bottleMl += feeding.amountMl ?? 0;
    } else {
      if (startsToday) directSessions += 1;
      for (final segment in segmentsByFeeding[feeding.id] ?? const []) {
        directSeconds += intersectSeconds(
          segment.startedAt,
          segment.endedAt,
          start,
          end,
        );
      }
    }
  }

  var sleepSeconds = 0;
  var hasOngoingSleep = false;
  int? ongoingStart;
  for (final sleep in sleeps) {
    final endMs = sleep.endedAt ?? nowMs;
    if (endMs <= sleep.startedAt) continue;
    sleepSeconds += intersectSeconds(sleep.startedAt, endMs, start, end);
    if (sleep.isOngoing && sleep.startedAt < end && endMs > start) {
      hasOngoingSleep = true;
      ongoingStart ??= sleep.startedAt;
    }
  }

  var stoolCount = 0;
  for (final stool in stools) {
    if (stool.occurredAt >= start && stool.occurredAt < end) stoolCount += 1;
  }

  return DailySummary(
    bottleMl: bottleMl,
    directSeconds: directSeconds,
    directSessions: directSessions,
    sleepSeconds: sleepSeconds,
    stoolCount: stoolCount,
    hasOngoingSleep: hasOngoingSleep,
    ongoingSleepStartMs: ongoingStart,
  );
}

class TrendSeries {
  const TrendSeries({
    required this.dates,
    required this.bottleMl,
    required this.sleepMinutes,
    required this.stoolCounts,
  });

  final List<DateTime> dates;
  final List<int> bottleMl;
  final List<int> sleepMinutes;
  final List<int> stoolCounts;
}

/// 返回以 [endDate] 结束的最近 [days] 天趋势。
TrendSeries computeTrend({
  required DateTime endDate,
  required int days,
  required List<FeedingRecord> feedings,
  required Map<String, List<FeedingSegment>> segmentsByFeeding,
  required List<SleepRecord> sleeps,
  required List<StoolRecord> stools,
  required int nowMs,
}) {
  final dates = List<DateTime>.generate(
    days,
    (i) => addDays(endDate, i - (days - 1)),
  );
  final bottle = <int>[];
  final sleep = <int>[];
  final stools7 = <int>[];
  for (final date in dates) {
    final summary = computeDailySummary(
      statDate: date,
      feedings: feedings,
      segmentsByFeeding: segmentsByFeeding,
      sleeps: sleeps,
      stools: stools,
      nowMs: nowMs,
    );
    bottle.add(summary.bottleMl);
    sleep.add(summary.sleepSeconds ~/ 60);
    stools7.add(summary.stoolCount);
  }
  return TrendSeries(
    dates: dates,
    bottleMl: bottle,
    sleepMinutes: sleep,
    stoolCounts: stools7,
  );
}
