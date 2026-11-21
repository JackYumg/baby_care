/// 统计时区固定为北京时间（UTC+8，无夏令时）。
const Duration kStatOffset = Duration(hours: 8);

/// 将 UTC 毫秒转换为「统计日」，返回值只承载年月日（UTC 零点）。
DateTime statDateFromMs(int utcMs) {
  final shifted = DateTime.fromMillisecondsSinceEpoch(
    utcMs,
    isUtc: true,
  ).add(kStatOffset);
  return DateTime.utc(shifted.year, shifted.month, shifted.day);
}

DateTime todayStatDate([DateTime? now]) =>
    statDateFromMs((now ?? DateTime.now()).millisecondsSinceEpoch);

/// 统计日左闭区间起点（UTC 毫秒）。
int dayStartMs(DateTime statDate) => DateTime.utc(
  statDate.year,
  statDate.month,
  statDate.day,
).subtract(kStatOffset).millisecondsSinceEpoch;

/// 统计日右开区间终点（UTC 毫秒）。
int dayEndMs(DateTime statDate) => DateTime.utc(
  statDate.year,
  statDate.month,
  statDate.day + 1,
).subtract(kStatOffset).millisecondsSinceEpoch;

DateTime addDays(DateTime statDate, int days) =>
    DateTime.utc(statDate.year, statDate.month, statDate.day + days);

/// 计算 [startMs, endMs) 与 [dayStart, dayEnd) 的交集秒数。
int intersectSeconds(int startMs, int endMs, int dayStart, int dayEnd) {
  final from = startMs > dayStart ? startMs : dayStart;
  final to = endMs < dayEnd ? endMs : dayEnd;
  if (to <= from) return 0;
  return (to - from) ~/ 1000;
}

bool rangesOverlap(int aStart, int aEnd, int bStart, int bEnd) =>
    aStart < bEnd && bStart < aEnd;

/// 将 UTC 毫秒格式化为北京时间 HH:mm。
String formatClock(int utcMs) {
  final t = DateTime.fromMillisecondsSinceEpoch(
    utcMs,
    isUtc: true,
  ).add(kStatOffset);
  return '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// 将秒数格式化为「x小时y分」或「y分钟」。
String formatDuration(int seconds) {
  final totalMinutes = seconds ~/ 60;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '$minutes分钟';
  if (minutes == 0) return '$hours小时';
  return '$hours小时$minutes分';
}

/// 计时器显示 HH:mm:ss。
String formatStopwatch(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}

String formatMonthDay(DateTime statDate) =>
    '${statDate.month}月${statDate.day}日';

/// 将统计日与北京时间时分组合为 UTC 毫秒。
int combineStatDateTime(DateTime statDate, int hour, int minute) =>
    DateTime.utc(
      statDate.year,
      statDate.month,
      statDate.day,
      hour,
      minute,
    ).subtract(kStatOffset).millisecondsSinceEpoch;

/// 将 UTC 毫秒拆为北京时间统计日与时分。
(DateTime, int, int) splitStatDateTime(int utcMs) {
  final t = DateTime.fromMillisecondsSinceEpoch(
    utcMs,
    isUtc: true,
  ).add(kStatOffset);
  return (DateTime.utc(t.year, t.month, t.day), t.hour, t.minute);
}

const List<String> kWeekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

String weekdayLabel(DateTime statDate) =>
    '周${kWeekdayNames[statDate.weekday - 1]}';
