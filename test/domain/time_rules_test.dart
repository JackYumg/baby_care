import 'package:baby_care/domain/time_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('北京时间日界线', () {
    test('统计日起点是前一日 UTC 16:00', () {
      final start = dayStartMs(DateTime.utc(2026, 11, 21));
      expect(
        DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
        DateTime.utc(2026, 11, 20, 16),
      );
    });

    test('00:00 归入新一天，23:59:59 归入旧一天', () {
      final newDayStart = combineStatDateTime(DateTime.utc(2026, 11, 21), 0, 0);
      expect(statDateFromMs(newDayStart), DateTime.utc(2026, 11, 21));
      expect(statDateFromMs(newDayStart - 1), DateTime.utc(2026, 11, 20));
    });

    test('日期加减跨月跨年正确', () {
      expect(addDays(DateTime.utc(2026, 12, 31), 1), DateTime.utc(2027, 1, 1));
      expect(addDays(DateTime.utc(2026, 3, 1), -1), DateTime.utc(2026, 2, 28));
    });
  });

  group('区间拆分', () {
    test('23:00 到次日 02:00 拆为 1 小时与 2 小时', () {
      final day = DateTime.utc(2026, 11, 21);
      final start = combineStatDateTime(day, 23, 0);
      final end = combineStatDateTime(addDays(day, 1), 2, 0);
      expect(
        intersectSeconds(start, end, dayStartMs(day), dayEndMs(day)),
        3600,
      );
      final next = addDays(day, 1);
      expect(
        intersectSeconds(start, end, dayStartMs(next), dayEndMs(next)),
        7200,
      );
    });

    test('完全不相交的区间返回 0', () {
      final day = DateTime.utc(2026, 11, 21);
      final start = combineStatDateTime(day, 8, 0);
      final end = combineStatDateTime(day, 9, 0);
      expect(
        intersectSeconds(start, end, dayStartMs(day), dayEndMs(day)),
        3600,
      );
      expect(
        intersectSeconds(
          start,
          end,
          dayStartMs(addDays(day, 1)),
          dayEndMs(addDays(day, 1)),
        ),
        0,
      );
    });

    test('首尾相接不算重叠', () {
      expect(rangesOverlap(0, 1000, 1000, 2000), isFalse);
      expect(rangesOverlap(0, 1001, 1000, 2000), isTrue);
    });
  });

  group('格式化', () {
    test('时长按小时与分钟展示', () {
      expect(formatDuration(600), '10分钟');
      expect(formatDuration(3600), '1小时');
      expect(formatDuration(5460), '1小时31分');
    });

    test('计时器固定 HH:mm:ss', () {
      expect(formatStopwatch(0), '00:00:00');
      expect(formatStopwatch(3661), '01:01:01');
    });

    test('时间展示为北京时间', () {
      final ms = combineStatDateTime(DateTime.utc(2026, 11, 21), 7, 5);
      expect(formatClock(ms), '07:05');
      expect(weekdayLabel(DateTime.utc(2026, 11, 21)), '周六');
    });
  });
}
