import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../../domain/time_rules.dart';
import '../../platform/care_reminders.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'checkup_detail_page.dart';
import 'vaccine_detail_page.dart';

enum CareTaskKind { checkup, vaccine }

/// 待办中心里统一展示的儿保 / 疫苗条目。
class CareTaskItem {
  const CareTaskItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.status,
    this.checkup,
    this.vaccine,
  });

  final CareTaskKind kind;
  final String id;
  final String title;
  final int scheduledAt;
  final CareTaskStatus status;
  final CheckupPlan? checkup;
  final VaccineRecord? vaccine;

  bool get isPending => status == CareTaskStatus.pending;

  bool get isVaccine => kind == CareTaskKind.vaccine;

  IconData get icon =>
      isVaccine ? Icons.vaccines_outlined : Icons.medical_services_outlined;

  Color get color => isVaccine ? const Color(0xFFB98A5E) : AppColors.green;

  String get statusLabel {
    switch (status) {
      case CareTaskStatus.done:
        return isVaccine ? '已接种' : '已完成';
      case CareTaskStatus.skipped:
        return '已跳过';
      case CareTaskStatus.pending:
        return '';
    }
  }
}

/// 合并当前宝宝的儿保与疫苗，按计划时间升序。
List<CareTaskItem> buildCareTaskItems(AppState state) {
  final items = <CareTaskItem>[
    for (final plan in state.checkups)
      CareTaskItem(
        kind: CareTaskKind.checkup,
        id: plan.id,
        title: plan.title,
        scheduledAt: plan.scheduledAt,
        status: plan.status,
        checkup: plan,
      ),
    for (final record in state.vaccines)
      CareTaskItem(
        kind: CareTaskKind.vaccine,
        id: record.id,
        title: '${record.name} · 第 ${record.dose} 剂',
        scheduledAt: record.scheduledAt,
        status: record.status,
        vaccine: record,
      ),
  ];
  items.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return items;
}

/// 计划日期相对今天的天数文案：今天 / 还剩 N 天 / 已逾期 N 天。
String careTaskDueText(int scheduledAt, int nowMs) {
  final due = statDateFromMs(scheduledAt);
  final today = statDateFromMs(nowMs);
  final days = due.difference(today).inDays;
  if (days == 0) return '今天';
  if (days > 0) return '还剩 $days 天';
  return '已逾期 ${-days} 天';
}

bool careTaskOverdue(int scheduledAt, int nowMs) =>
    statDateFromMs(scheduledAt).isBefore(statDateFromMs(nowMs));

bool careTaskToday(int scheduledAt, int nowMs) =>
    statDateFromMs(scheduledAt) == statDateFromMs(nowMs);

String careTaskDateText(int scheduledAt) {
  final date = statDateFromMs(scheduledAt);
  return '${formatMonthDay(date)} · ${weekdayLabel(date)}';
}

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.state});

  final AppState state;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _expandedDone = false;
  bool _generating = false;
  bool _bootstrapped = false;
  String? _lastBabyId;

  @override
  void initState() {
    super.initState();
    _lastBabyId = widget.state.currentBaby?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// 首次进入且完全没有待办时，自动按出生日期生成默认计划。
  Future<void> _bootstrap() async {
    if (_bootstrapped || !mounted) return;
    _bootstrapped = true;
    final state = widget.state;
    if (state.currentBaby == null) return;
    if (state.checkups.isNotEmpty || state.vaccines.isNotEmpty) return;
    await _generate(manual: false);
  }

  Future<void> _generate({required bool manual}) async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final added = await widget.state.generateDefaultCareSchedule();
      await syncCareReminders(widget.state);
      if (!mounted) return;
      if (added > 0) {
        showSuccessSnack(context, '已生成 $added 项儿保 / 疫苗计划');
      } else if (manual) {
        showSuccessSnack(context, '计划已是最新，没有需要补充的待办');
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 切换宝宝后重排通知（页面常驻，build 时对比宝宝 id）。
  void _watchBabySwitch() {
    final babyId = widget.state.currentBaby?.id;
    if (_lastBabyId == babyId) return;
    _lastBabyId = babyId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) syncCareReminders(widget.state);
    });
  }

  Future<void> _openCheckup(CheckupPlan? plan) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CheckupDetailPage(state: widget.state, plan: plan),
    ),
  );

  Future<void> _openVaccine(VaccineRecord record) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VaccineDetailPage(state: widget.state, record: record),
    ),
  );

  @override
  Widget build(BuildContext context) {
    _watchBabySwitch();
    final state = widget.state;
    final tasks = buildCareTaskItems(state);
    final upcoming = [
      for (final task in tasks)
        if (task.isPending) task,
    ];
    final finished = [
      for (final task in tasks)
        if (!task.isPending) task,
    ]..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('待办'),
        actions: [
          IconButton(
            tooltip: '生成计划',
            onPressed: _generating ? null : () => _generate(manual: true),
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
          IconButton(
            tooltip: '新增儿保',
            onPressed: () => _openCheckup(null),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: AppColors.subtle,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '计划日期可在详情中手动调整，完成后可记录检查结果',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.subtle),
                ),
              ),
            ],
          ),
          if (tasks.isEmpty)
            ...[
              const EmptyState(
                icon: Icons.event_note_rounded,
                title: '还没有儿保或疫苗待办',
                subtitle: '按宝宝出生日期生成 42 天、3～36 月龄儿保与一类疫苗计划',
              ),
              FilledButton.icon(
                onPressed: _generating ? null : () => _generate(manual: true),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('生成儿保与疫苗计划'),
              ),
            ]
          else ...[
            const SectionHeader('即将到来'),
            if (upcoming.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    '暂时没有待办的儿保或疫苗，点击右上角可继续补充计划。',
                    style: TextStyle(fontSize: 13, color: AppColors.subtle),
                  ),
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < upcoming.length; i++) ...[
                      if (i > 0) const Divider(indent: 68, endIndent: 16),
                      _TaskTile(
                        state: state,
                        item: upcoming[i],
                        onTap: () => _openTask(upcoming[i]),
                      ),
                    ],
                  ],
                ),
              ),
            SectionHeader(
              '已完成（${finished.length}）',
              trailing: TextButton(
                onPressed: () =>
                    setState(() => _expandedDone = !_expandedDone),
                child: Text(_expandedDone ? '收起' : '展开'),
              ),
            ),
            if (_expandedDone)
              if (finished.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      '还没有已完成或已跳过的待办。',
                      style: TextStyle(fontSize: 13, color: AppColors.subtle),
                    ),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < finished.length; i++) ...[
                        if (i > 0) const Divider(indent: 68, endIndent: 16),
                        _TaskTile(
                          state: state,
                          item: finished[i],
                          onTap: () => _openTask(finished[i]),
                        ),
                      ],
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }

  void _openTask(CareTaskItem item) {
    final checkup = item.checkup;
    final vaccine = item.vaccine;
    if (checkup != null) {
      _openCheckup(checkup);
    } else if (vaccine != null) {
      _openVaccine(vaccine);
    }
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.state, required this.item, required this.onTap});

  final AppState state;
  final CareTaskItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nowMs = state.nowMs;
    final pending = item.isPending;
    final overdue = pending && careTaskOverdue(item.scheduledAt, nowMs);
    final today = pending && careTaskToday(item.scheduledAt, nowMs);
    final badgeColor = overdue
        ? Theme.of(context).colorScheme.error
        : today
        ? AppColors.greenDark
        : AppColors.subtle;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(item.icon, color: item.color, size: 20),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        careTaskDateText(item.scheduledAt),
        style: const TextStyle(fontSize: 12, color: AppColors.subtle),
      ),
      trailing: Text(
        pending ? careTaskDueText(item.scheduledAt, nowMs) : item.statusLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: badgeColor,
        ),
      ),
    );
  }
}
