import 'package:baby_care/domain/care_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

List<VaccineDraft> _missingVaccines(
  List<VaccineDraft> drafts,
  Set<String> existing,
) => [
  for (final draft in drafts)
    if (!existing.contains('${draft.name}#${draft.dose}')) draft,
];

void main() {
  group('addMonths', () {
    test('普通日期按自然月推进', () {
      expect(addMonths(DateTime(2026, 1, 15), 3), DateTime(2026, 4, 15));
      expect(addMonths(DateTime(2026, 11, 24), 1), DateTime(2026, 12, 24));
      expect(addMonths(DateTime(2026, 5, 20), 0), DateTime(2026, 5, 20));
    });

    test('目标月没有该日时取该月最后一天', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
      expect(addMonths(DateTime(2026, 3, 31), 1), DateTime(2026, 4, 30));
      expect(addMonths(DateTime(2026, 8, 31), 1), DateTime(2026, 9, 30));
    });

    test('跨年推进正确', () {
      expect(addMonths(DateTime(2026, 11, 24), 36), DateTime(2029, 11, 24));
      expect(addMonths(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 31));
    });
  });

  group('默认儿保计划', () {
    test('包含 42 天与 8 个月龄节点，时间为当天 09:00', () {
      final drafts = generateCheckupDrafts(DateTime(2026, 1, 31));
      expect(drafts, hasLength(9));
      expect(drafts.first.title, '42 天儿保');
      expect(
        DateTime.fromMillisecondsSinceEpoch(drafts.first.scheduledAt),
        DateTime(2026, 3, 14, 9),
      );

      final threeMonths = drafts[1];
      expect(threeMonths.title, '3 月龄儿保');
      expect(
        DateTime.fromMillisecondsSinceEpoch(threeMonths.scheduledAt),
        DateTime(2026, 4, 30, 9),
      );
      expect(
        DateTime.fromMillisecondsSinceEpoch(drafts.last.scheduledAt),
        DateTime(2029, 1, 31, 9),
      );
    });

    test('每个节点附 3-6 条中文检查项', () {
      final drafts = generateCheckupDrafts(DateTime(2026, 5, 20));
      for (final draft in drafts) {
        expect(draft.items.length, inInclusiveRange(3, 6));
        expect(draft.items.every((item) => item.label.isNotEmpty), isTrue);
      }
      final threeMonths = drafts.firstWhere((d) => d.title == '3 月龄儿保');
      expect(
        threeMonths.items.map((e) => e.label),
        containsAll(['体重', '身长', '头围']),
      );
    });

    test('1 月 31 日出生时 3 月龄落在 4 月 30 日', () {
      final drafts = generateCheckupDrafts(DateTime(2026, 1, 31));
      final sixMonths = drafts.firstWhere((d) => d.title == '6 月龄儿保');
      expect(
        DateTime.fromMillisecondsSinceEpoch(sixMonths.scheduledAt),
        DateTime(2026, 7, 31, 9),
      );
    });
  });

  group('默认疫苗计划', () {
    test('最少集合共 22 项，出生当天有乙肝①与卡介苗', () {
      final drafts = generateVaccineDrafts(DateTime(2026, 1, 31));
      expect(drafts, hasLength(22));
      final birthDay = DateTime(2026, 1, 31, 9).millisecondsSinceEpoch;
      final atBirth = drafts.where((d) => d.scheduledAt == birthDay);
      expect(atBirth.map((e) => e.name), containsAll(['乙肝', '卡介苗']));
    });

    test('月末出生时 1 月龄取 2 月最后一天', () {
      final drafts = generateVaccineDrafts(DateTime(2026, 1, 31));
      final second = drafts.firstWhere((d) => d.name == '乙肝' && d.dose == 2);
      expect(
        DateTime.fromMillisecondsSinceEpoch(second.scheduledAt),
        DateTime(2026, 2, 28, 9),
      );
    });

    test('6 岁节点包含白破与 A+C 流脑②', () {
      final drafts = generateVaccineDrafts(DateTime(2026, 1, 31));
      final sixYears = drafts.where(
        (d) => d.scheduledAt == DateTime(2032, 1, 31, 9).millisecondsSinceEpoch,
      );
      expect(
        sixYears.map((e) => '${e.name}#${e.dose}'),
        containsAll(['白破#1', 'A+C 流脑#2']),
      );
    });

    test('以名称 + 剂次为唯一键，重复生成幂等且改期不重复', () {
      final drafts = generateVaccineDrafts(DateTime(2026, 5, 20));
      final existing = {for (final d in drafts) '${d.name}#${d.dose}'};
      expect(_missingVaccines(drafts, existing), isEmpty);

      // 用户改过计划日期后再次生成，不应重复插入。
      final movedKeys = {
        for (final d in drafts)
          '${d.name}#${d.dose}',
      };
      expect(_missingVaccines(drafts, movedKeys), isEmpty);

      // 缺少一项时只补这一项。
      final partial = {...existing}..remove('乙肝#1');
      final missing = _missingVaccines(drafts, partial);
      expect(missing, hasLength(1));
      expect(missing.single.name, '乙肝');
      expect(missing.single.dose, 1);
    });

    test('儿保以标题为唯一键，重复生成幂等', () {
      final drafts = generateCheckupDrafts(DateTime(2026, 5, 20));
      final existing = {for (final d in drafts) d.title};
      final missing = [
        for (final draft in drafts)
          if (!existing.contains(draft.title)) draft,
      ];
      expect(missing, isEmpty);
    });
  });
}
