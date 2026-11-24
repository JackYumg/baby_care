import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/daily_statistics.dart';
import '../../domain/feeding_reminder.dart';
import '../../domain/models.dart';
import '../../domain/time_rules.dart';
import '../../platform/care_reminders.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../babies/baby_form_page.dart';
import '../feeding/feeding_sheet.dart';
import '../sleep/sleep_sheet.dart';
import '../stool/stool_sheet.dart';
import '../tasks/tasks_page.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final baby = state.currentBaby;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _showBabySwitcher(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.greenSoft,
                      child: Icon(
                        kAvatarIcons[baby?.avatarKey] ??
                            Icons.child_care_rounded,
                        size: 18,
                        color: AppColors.greenDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      baby?.nickname ?? '选择宝宝',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded, size: 20),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                tooltip: '记录',
                onPressed: () => showFeedingSheet(context, state),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _CareReminderSync(
                state: state,
                babyId: state.currentBaby?.id,
              ),
              _DateSwitcher(state: state),
              const SizedBox(height: 12),
              _RecentTaskCard(state: state),
              _SummaryGrid(summary: state.summary),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: QuickActionButton(
                      icon: Icons.local_drink_rounded,
                      label: '喝奶',
                      color: AppColors.green,
                      onTap: () => showFeedingSheet(context, state),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: QuickActionButton(
                      icon: Icons.baby_changing_station_rounded,
                      label: '排便',
                      color: const Color(0xFFB98A5E),
                      onTap: () => showStoolSheet(context, state),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: QuickActionButton(
                      icon: Icons.bedtime_rounded,
                      label: '睡眠',
                      color: const Color(0xFF6C86B8),
                      onTap: () => showSleepSheet(context, state),
                    ),
                  ),
                ],
              ),
              if (state.ongoingSleep != null || state.activeFeeding != null)
                _ActiveTimerCard(state: state),
              const SectionHeader('今日时间线'),
              if (!state.isToday) ...[
                Text(
                  '查看 ${formatMonthDay(state.selectedDate)} 的记录',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.subtle),
                ),
                const SizedBox(height: 8),
              ],
              if (state.timeline.isEmpty)
                const EmptyState(
                  icon: Icons.inbox_rounded,
                  title: '这一天还没有记录',
                  subtitle: '点击上方喝奶、排便或睡眠快速添加',
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < state.timeline.length; i++) ...[
                        if (i > 0) const Divider(indent: 64, endIndent: 16),
                        _TimelineTile(state: state, entry: state.timeline[i]),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showBabySwitcher(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '切换宝宝',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            for (final baby in state.babies)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.greenSoft,
                  child: Icon(
                    kAvatarIcons[baby.avatarKey] ?? Icons.child_care_rounded,
                    size: 20,
                    color: AppColors.greenDark,
                  ),
                ),
                title: Text(baby.nickname),
                trailing: state.currentBaby?.id == baby.id
                    ? const Icon(Icons.check_rounded, color: AppColors.green)
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  state.selectBaby(baby.id);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// 宝宝切换后重排儿保 / 疫苗提醒；不渲染任何内容。
class _CareReminderSync extends StatefulWidget {
  const _CareReminderSync({required this.state, required this.babyId});

  final AppState state;
  final String? babyId;

  @override
  State<_CareReminderSync> createState() => _CareReminderSyncState();
}

class _CareReminderSyncState extends State<_CareReminderSync> {
  @override
  void didUpdateWidget(covariant _CareReminderSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.babyId != widget.babyId) {
      syncCareReminders(widget.state);
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 今日页顶部的「最近的待办」卡片，可关闭且关闭状态持久化。
class _RecentTaskCard extends StatefulWidget {
  const _RecentTaskCard({required this.state});

  final AppState state;

  @override
  State<_RecentTaskCard> createState() => _RecentTaskCardState();
}

class _RecentTaskCardState extends State<_RecentTaskCard> {
  static const String _hiddenKey = 'hidden_task_tip_id';

  String? _hiddenId;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadHidden();
  }

  Future<void> _loadHidden() async {
    String? hidden;
    try {
      hidden = await widget.state.settingsRepo.get(_hiddenKey);
    } catch (_) {
      hidden = null;
    }
    if (!mounted) return;
    setState(() {
      _hiddenId = hidden;
      _loaded = true;
    });
  }

  Future<void> _dismiss(String taskId) async {
    setState(() => _hiddenId = taskId);
    try {
      await widget.state.settingsRepo.set(_hiddenKey, taskId);
    } catch (_) {
      // 持久化失败时本次仍保持关闭，下次进入会重新出现。
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = [
      for (final task in buildCareTaskItems(widget.state))
        if (task.isPending) task,
    ];
    if (pending.isEmpty || !_loaded) return const SizedBox.shrink();
    final task = pending.first;
    if (_hiddenId == task.id) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final nowMs = widget.state.nowMs;
    final overdue = careTaskOverdue(task.scheduledAt, nowMs);
    final today = careTaskToday(task.scheduledAt, nowMs);
    final badgeColor = overdue
        ? theme.colorScheme.error
        : today
        ? AppColors.greenDark
        : AppColors.subtle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TasksPage(state: widget.state),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: task.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(task.icon, color: task.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${task.isVaccine ? '疫苗' : '儿保'} · '
                        '${careTaskDateText(task.scheduledAt)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.subtle,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  careTaskDueText(task.scheduledAt, nowMs),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: badgeColor,
                  ),
                ),
                IconButton(
                  tooltip: '关闭提示',
                  onPressed: () => _dismiss(task.id),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateSwitcher extends StatelessWidget {
  const _DateSwitcher({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final date = state.selectedDate;
    return Row(
      children: [
        IconButton(
          onPressed: () => state.selectDate(addDays(date, -1)),
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: '前一天',
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime(date.year, date.month, date.day),
                firstDate: DateTime(2018, 1, 1),
                lastDate: DateTime.now(),
                helpText: '选择日期',
                cancelText: '取消',
                confirmText: '确定',
              );
              if (picked != null) {
                await state.selectDate(
                  DateTime.utc(picked.year, picked.month, picked.day),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    '${formatMonthDay(date)} · ${weekdayLabel(date)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    state.isToday ? '今天' : '历史日期',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.subtle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: state.isToday
              ? null
              : () => state.selectDate(addDays(date, 1)),
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: '后一天',
        ),
        if (!state.isToday)
          TextButton(
            onPressed: () => state.selectDate(todayStatDate()),
            child: const Text('今天'),
          ),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SummaryTile(
                icon: Icons.local_drink_rounded,
                label: '瓶喂奶量',
                value: '${summary.bottleMl}',
                unit: 'ml',
                color: AppColors.green,
                hint: '仅统计已记录的毫升数',
              ),
            ),
            const SizedBox(width: 10, height: 0),
            Expanded(
              child: SummaryTile(
                icon: Icons.front_hand_rounded,
                label: '亲喂',
                value: '${summary.directSeconds ~/ 60}',
                unit: '分钟',
                color: const Color(0xFFB98A5E),
                hint: '${summary.directSessions} 次',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SummaryTile(
                icon: Icons.bedtime_rounded,
                label: '睡眠时长',
                value: _hoursText(summary.sleepSeconds),
                unit: '',
                color: const Color(0xFF6C86B8),
                hint: summary.hasOngoingSleep ? '含进行中的睡眠' : null,
              ),
            ),
            const SizedBox(width: 10, height: 0),
            Expanded(
              child: SummaryTile(
                icon: Icons.baby_changing_station_rounded,
                label: '排便次数',
                value: '${summary.stoolCount}',
                unit: '次',
                color: const Color(0xFF8C7BAE),
                hint: '按北京时间统计',
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _hoursText(int seconds) {
    final minutes = seconds ~/ 60;
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '$rest';
    return '$hours小时${rest == 0 ? '' : '$rest分'}';
  }
}

class _ActiveTimerCard extends StatelessWidget {
  const _ActiveTimerCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final sleep = state.ongoingSleep;
    final feeding = state.activeFeeding;
    final children = <Widget>[];
    if (sleep != null) {
      children.add(
        _timerRow(
          context,
          icon: Icons.bedtime_rounded,
          color: const Color(0xFF6C86B8),
          title: '睡眠中',
          seconds: (state.nowMs - sleep.startedAt) ~/ 1000,
          actionLabel: '宝宝醒了',
          onAction: () async {
            try {
              await state.endSleep(sleep.id);
              if (context.mounted) showSuccessSnack(context, '睡眠记录已保存');
            } catch (error) {
              if (context.mounted) showErrorSnack(context, error);
            }
          },
        ),
      );
    }
    if (feeding != null) {
      if (children.isNotEmpty) const SizedBox(height: 0);
      children.add(
        _timerRow(
          context,
          icon: Icons.front_hand_rounded,
          color: const Color(0xFFB98A5E),
          title: feeding.currentSide == null
              ? '亲喂已暂停'
              : '亲喂中 · ${feeding.currentSide == BreastSide.left ? '左侧' : '右侧'}',
          seconds: (state.nowMs - feeding.startedAt) ~/ 1000,
          actionLabel: '去结束',
          onAction: () => showFeedingSheet(context, state),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: children),
        ),
      ),
    );
  }

  Widget _timerRow(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required int seconds,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, color: AppColors.subtle),
              ),
              Text(
                formatStopwatch(seconds),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: onAction,
          child: Text(actionLabel, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.state, required this.entry});

  final AppState state;
  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, subtitle) = _describe();
    final imagePath = entry.stool?.imagePath;
    const subtitleStyle = TextStyle(fontSize: 12, color: AppColors.subtle);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: imagePath == null || imagePath.isEmpty
          ? Text(subtitle, style: subtitleStyle)
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  StoolImageThumbnail(
                    relativePath: imagePath,
                    size: 44,
                    radius: 10,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(subtitle, style: subtitleStyle)),
                ],
              ),
            ),
      trailing: Text(
        formatClock(entry.timeMs),
        style: const TextStyle(fontSize: 13, color: AppColors.subtle),
      ),
      onTap: () => _openDetail(context),
    );
  }

  (IconData, Color, String, String) _describe() {
    switch (entry.kind) {
      case TimelineKind.feeding:
        final feeding = entry.feeding!;
        if (feeding.mode == FeedMode.bottle) {
          final milk = feeding.milkType == MilkType.formula ? '配方奶' : '母乳';
          return (
            Icons.local_drink_rounded,
            AppColors.green,
            '$milk ${feeding.amountMl ?? 0}ml',
            feeding.note ?? '瓶喂',
          );
        }
        var left = 0;
        var right = 0;
        for (final segment in entry.segments) {
          if (segment.side == BreastSide.left) {
            left += segment.seconds;
          } else {
            right += segment.seconds;
          }
        }
        return (
          Icons.front_hand_rounded,
          const Color(0xFFB98A5E),
          '亲喂',
          '左 ${formatDuration(left)} · 右 ${formatDuration(right)}',
        );
      case TimelineKind.sleep:
        final sleep = entry.sleep!;
        final endMs = sleep.endedAt ?? state.nowMs;
        final seconds = ((endMs - sleep.startedAt) / 1000).round();
        return (
          Icons.bedtime_rounded,
          const Color(0xFF6C86B8),
          sleep.isOngoing ? '睡眠中' : '睡眠',
          sleep.isOngoing
              ? '已睡 ${formatDuration(seconds)}'
              : '${formatClock(sleep.startedAt)} - ${formatClock(sleep.endedAt!)}'
                    ' · ${formatDuration(seconds)}',
        );
      case TimelineKind.stool:
        final stool = entry.stool!;
        final parts = <String>[
          if (stool.color != null) kStoolColorLabels[stool.color]!,
          if (stool.consistency != null) stool.consistency!,
        ];
        return (
          Icons.baby_changing_station_rounded,
          const Color(0xFF8C7BAE),
          '排便',
          parts.isEmpty ? '已记录' : parts.join(' · '),
        );
    }
  }

  void _openDetail(BuildContext context) {
    switch (entry.kind) {
      case TimelineKind.feeding:
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => _FeedingDetailSheet(
            state: state,
            feeding: entry.feeding!,
            segments: entry.segments,
          ),
        );
      case TimelineKind.sleep:
        showSleepSheet(context, state, sleep: entry.sleep);
      case TimelineKind.stool:
        showStoolSheet(context, state, stool: entry.stool);
    }
  }
}

class _FeedingDetailSheet extends StatefulWidget {
  const _FeedingDetailSheet({
    required this.state,
    required this.feeding,
    required this.segments,
  });

  final AppState state;
  final FeedingRecord feeding;
  final List<FeedingSegment> segments;

  @override
  State<_FeedingDetailSheet> createState() => _FeedingDetailSheetState();
}

class _FeedingDetailSheetState extends State<_FeedingDetailSheet> {
  late int _timeMs;
  late MilkType _milkType;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  bool _saving = false;

  bool get isBottle => widget.feeding.mode == FeedMode.bottle;

  @override
  void initState() {
    super.initState();
    _timeMs = widget.feeding.startedAt;
    _milkType = widget.feeding.milkType ?? MilkType.formula;
    _amount = TextEditingController(
      text: widget.feeding.amountMl?.toString() ?? '',
    );
    _note = TextEditingController(text: widget.feeding.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!isBottle) return;
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      showSuccessSnack(context, '请输入有效的奶量');
      return;
    }
    if (_timeMs > DateTime.now().millisecondsSinceEpoch) {
      showSuccessSnack(context, '时间不能晚于当前时间');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.state.updateBottleFeeding(
        id: widget.feeding.id,
        startedAt: _timeMs,
        amountMl: amount,
        milkType: _milkType,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        remindAt: widget.feeding.remindAt == null
            ? null
            : _timeMs + estimateFeedRemindMinutes(amount) * 60 * 1000,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnack(context, '已保存修改');
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这条记录？',
      message: '删除后统计会立即更新，且无法恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok) return;
    await widget.state.deleteFeeding(widget.feeding.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    var left = 0;
    var right = 0;
    for (final segment in widget.segments) {
      if (segment.side == BreastSide.left) {
        left += segment.seconds;
      } else {
        right += segment.seconds;
      }
    }
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  isBottle ? '编辑瓶喂' : '亲喂详情',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isBottle) ...[
              TimeField(
                label: '喝奶时间',
                valueMs: _timeMs,
                onChanged: (value) => setState(() => _timeMs = value),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  ChoiceChip(
                    label: const Text('配方奶'),
                    selected: _milkType == MilkType.formula,
                    onSelected: (_) =>
                        setState(() => _milkType = MilkType.formula),
                  ),
                  ChoiceChip(
                    label: const Text('母乳'),
                    selected: _milkType == MilkType.breastMilk,
                    onSelected: (_) =>
                        setState(() => _milkType = MilkType.breastMilk),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '奶量',
                  suffixText: 'ml',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('保存修改'),
              ),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Text(
                        '${formatClock(widget.feeding.startedAt)}'
                        ' - ${formatClock(widget.feeding.endedAt ?? widget.feeding.startedAt)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '左侧 ${formatDuration(left)} · 右侧 ${formatDuration(right)}',
                        style: const TextStyle(color: AppColors.subtle),
                      ),
                      if (widget.feeding.note != null) ...[
                        const SizedBox(height: 8),
                        Text(widget.feeding.note!),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(onPressed: _delete, child: const Text('删除记录')),
          ],
        ),
      ),
    );
  }
}
