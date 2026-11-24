import 'models.dart';

/// 儿保计划草稿（尚未入库）。
class CheckupDraft {
  const CheckupDraft({
    required this.title,
    required this.scheduledAt,
    required this.items,
  });

  final String title;
  final int scheduledAt;
  final List<CheckupItem> items;
}

/// 疫苗计划草稿（尚未入库）。
class VaccineDraft {
  const VaccineDraft({
    required this.name,
    required this.dose,
    required this.scheduledAt,
  });

  final String name;
  final int dose;
  final int scheduledAt;
}

/// 按自然月推进日期；目标月没有该日时取该月最后一天。
///
/// 例如 1 月 31 日加 1 个月得到 2 月 28/29 日。
DateTime addMonths(DateTime date, int months) {
  final totalMonths = date.month - 1 + months;
  final year = date.year + totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;
  return DateTime(year, month, day);
}

/// 按自然日推进日期，不受夏令时影响。
DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

DateTime _atNine(DateTime date) =>
    DateTime(date.year, date.month, date.day, 9);

DateTime _birthday(DateTime birthDate) =>
    DateTime(birthDate.year, birthDate.month, birthDate.day);

/// 儿保节点月龄（42 天单独处理）。
const List<int> _checkupMonths = [3, 6, 8, 12, 18, 24, 30, 36];

List<CheckupItem> _checkupItems(int months) {
  switch (months) {
    case 0:
      return const [
        CheckupItem(label: '体重'),
        CheckupItem(label: '身长'),
        CheckupItem(label: '头围'),
        CheckupItem(label: '心肺听诊'),
        CheckupItem(label: '黄疸检查'),
      ];
    case 3:
      return const [
        CheckupItem(label: '体重'),
        CheckupItem(label: '身长'),
        CheckupItem(label: '头围'),
        CheckupItem(label: '心肺听诊'),
        CheckupItem(label: '髋关节检查'),
        CheckupItem(label: '生长发育评估'),
      ];
    case 6:
      return const [
        CheckupItem(label: '体重'),
        CheckupItem(label: '身长'),
        CheckupItem(label: '头围'),
        CheckupItem(label: '血常规'),
        CheckupItem(label: '生长发育评估'),
      ];
    case 8:
      return const [
        CheckupItem(label: '体重'),
        CheckupItem(label: '身长'),
        CheckupItem(label: '头围'),
        CheckupItem(label: '视力筛查'),
        CheckupItem(label: '生长发育评估'),
      ];
    case 12:
      return const [
        CheckupItem(label: '体重'),
        CheckupItem(label: '身长'),
        CheckupItem(label: '头围'),
        CheckupItem(label: '血常规'),
        CheckupItem(label: '牙齿检查'),
        CheckupItem(label: '生长发育评估'),
      ];
    case 18:
      return const [
        CheckupItem(label: '体重'),
        CheckupItem(label: '身长'),
        CheckupItem(label: '头围'),
        CheckupItem(label: '心肺听诊'),
        CheckupItem(label: '生长发育评估'),
      ];
    case 24:
      return const [
        CheckupItem(label: '体重'),
        CheckupItem(label: '身长'),
        CheckupItem(label: '头围'),
        CheckupItem(label: '视力筛查'),
        CheckupItem(label: '生长发育评估'),
      ];
    case 30:
      return const [
        CheckupItem(label: '体重'),
        CheckupItem(label: '身长'),
        CheckupItem(label: '头围'),
        CheckupItem(label: '心肺听诊'),
        CheckupItem(label: '生长发育评估'),
      ];
    default:
      return const [
        CheckupItem(label: '体重'),
        CheckupItem(label: '身长'),
        CheckupItem(label: '头围'),
        CheckupItem(label: '视力筛查'),
        CheckupItem(label: '牙齿检查'),
        CheckupItem(label: '生长发育评估'),
      ];
  }
}

/// 生成默认儿保计划草稿：42 天以及 3/6/8/12/18/24/30/36 月龄。
List<CheckupDraft> generateCheckupDrafts(DateTime birthDate) {
  final birth = _birthday(birthDate);
  return [
    CheckupDraft(
      title: '42 天儿保',
      scheduledAt: _atNine(_addDays(birth, 42)).millisecondsSinceEpoch,
      items: _checkupItems(0),
    ),
    for (final months in _checkupMonths)
      CheckupDraft(
        title: '$months 月龄儿保',
        scheduledAt: _atNine(addMonths(birth, months)).millisecondsSinceEpoch,
        items: _checkupItems(months),
      ),
  ];
}

/// 一类疫苗最小集合：[月龄, 名称, 剂次]。
const List<({int months, String name, int dose})> _vaccineNodes = [
  (months: 0, name: '乙肝', dose: 1),
  (months: 0, name: '卡介苗', dose: 1),
  (months: 1, name: '乙肝', dose: 2),
  (months: 2, name: '脊灰', dose: 1),
  (months: 3, name: '脊灰', dose: 2),
  (months: 3, name: '百白破', dose: 1),
  (months: 4, name: '脊灰', dose: 3),
  (months: 4, name: '百白破', dose: 2),
  (months: 5, name: '百白破', dose: 3),
  (months: 6, name: '乙肝', dose: 3),
  (months: 6, name: 'A 群流脑', dose: 1),
  (months: 8, name: '麻腮风', dose: 1),
  (months: 8, name: '乙脑减毒', dose: 1),
  (months: 9, name: 'A 群流脑', dose: 2),
  (months: 12, name: '甲肝减毒', dose: 1),
  (months: 18, name: '麻腮风', dose: 2),
  (months: 18, name: '百白破', dose: 4),
  (months: 24, name: '乙脑减毒', dose: 2),
  (months: 36, name: 'A+C 流脑', dose: 1),
  (months: 48, name: '脊灰', dose: 4),
  (months: 72, name: '白破', dose: 1),
  (months: 72, name: 'A+C 流脑', dose: 2),
];

/// 生成默认一类疫苗计划草稿，计划时间为对应日期 09:00。
List<VaccineDraft> generateVaccineDrafts(DateTime birthDate) {
  final birth = _birthday(birthDate);
  return [
    for (final node in _vaccineNodes)
      VaccineDraft(
        name: node.name,
        dose: node.dose,
        scheduledAt: _atNine(
          addMonths(birth, node.months),
        ).millisecondsSinceEpoch,
      ),
  ];
}
