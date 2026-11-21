import 'time_rules.dart';

/// 奶量对应提醒间隔的下限与上限（分钟）。
const int kMinFeedRemindMinutes = 90;
const int kMaxFeedRemindMinutes = 240;

/// 亲喂没有奶量，使用固定的建议间隔（分钟）。
const int kDefaultDirectRemindMinutes = 180;

/// 按瓶喂奶量估算下次喂奶间隔：基础 60 分钟 + 每 1ml 1 分钟，限制在 90~240 分钟。
int estimateFeedRemindMinutes(int amountMl) {
  final minutes = 60 + amountMl;
  if (minutes < kMinFeedRemindMinutes) return kMinFeedRemindMinutes;
  if (minutes > kMaxFeedRemindMinutes) return kMaxFeedRemindMinutes;
  return minutes;
}

/// 距离下次提醒的剩余时间文案，例如「还剩 2小时30分」「已超过 15分钟」。
String feedRemainText(int nextMs, int nowMs) {
  final diff = nextMs - nowMs;
  final minutes = diff.abs() ~/ 60000;
  if (diff >= 0) {
    if (minutes == 0) return '即将到点';
    return '还剩 ${formatDuration(minutes * 60)}';
  }
  if (minutes == 0) return '刚刚到点';
  return '已超过 ${formatDuration(minutes * 60)}';
}
