import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../../domain/time_rules.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

Future<void> showSleepSheet(
  BuildContext context,
  AppState state, {
  SleepRecord? sleep,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => SleepSheet(state: state, sleep: sleep),
  );
}

class SleepSheet extends StatefulWidget {
  const SleepSheet({super.key, required this.state, this.sleep});

  final AppState state;
  final SleepRecord? sleep;

  @override
  State<SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends State<SleepSheet> {
  late int _startMs;
  late int _endMs;
  final _noteController = TextEditingController();
  bool _manual = false;
  bool _saving = false;

  bool get isEdit => widget.sleep != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().millisecondsSinceEpoch;
    final sleep = widget.sleep;
    _startMs = sleep?.startedAt ?? now - Duration.millisecondsPerHour;
    _endMs = sleep?.endedAt ?? now;
    _noteController.text = sleep?.note ?? '';
    _manual = isEdit || widget.state.ongoingSleep == null;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _startSleep() async {
    setState(() => _saving = true);
    try {
      await widget.state.startSleep();
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnack(context, '开始记录睡眠');
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _endSleep(SleepRecord sleep) async {
    setState(() => _saving = true);
    try {
      await widget.state.endSleep(sleep.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnack(context, '睡眠记录已保存');
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveManual() async {
    if (_endMs <= _startMs) {
      showSuccessSnack(context, '结束时间必须晚于开始时间');
      return;
    }
    if (_endMs > DateTime.now().millisecondsSinceEpoch) {
      showSuccessSnack(context, '结束时间不能晚于当前时间');
      return;
    }
    setState(() => _saving = true);
    try {
      final note = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();
      if (isEdit) {
        await widget.state.updateSleep(
          id: widget.sleep!.id,
          startedAt: _startMs,
          endedAt: _endMs,
          note: note,
        );
      } else {
        await widget.state.addManualSleep(
          startedAt: _startMs,
          endedAt: _endMs,
          note: note,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnack(context, isEdit ? '已保存修改' : '已补录睡眠');
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final ongoing = widget.state.ongoingSleep;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      isEdit ? '编辑睡眠' : '记录睡眠',
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
                if (ongoing != null && !isEdit) ...[
                  const SizedBox(height: 4),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Text(
                            '睡眠中',
                            style: TextStyle(
                              color: AppColors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            formatStopwatch(
                              (widget.state.nowMs - ongoing.startedAt) ~/ 1000,
                            ),
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '开始于 ${formatClock(ongoing.startedAt)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.subtle),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _endSleep(ongoing),
                    icon: const Icon(Icons.bedtime_rounded),
                    label: const Text('宝宝醒了'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => setState(() => _manual = true),
                    child: const Text('改为补录一段时间'),
                  ),
                ] else if (!isEdit && !_manual) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _startSleep,
                    icon: const Icon(Icons.bedtime_rounded),
                    label: const Text('开始睡觉'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => setState(() => _manual = true),
                    child: const Text('补录睡眠时间'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '计时会持久保存，退出应用或重启后仍可继续。跨天睡眠按每天实际重叠时长统计。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.subtle,
                      height: 1.5,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  TimeField(
                    label: '开始时间',
                    valueMs: _startMs,
                    onChanged: (value) => setState(() => _startMs = value),
                  ),
                  const SizedBox(height: 12),
                  TimeField(
                    label: '结束时间',
                    valueMs: _endMs,
                    onChanged: (value) => setState(() => _endMs = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _saveManual,
                    child: Text(isEdit ? '保存修改' : '保存睡眠记录'),
                  ),
                  if (isEdit) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () async {
                        final ok = await showConfirmDialog(
                          context,
                          title: '删除这条睡眠记录？',
                          message: '删除后统计会立即更新，且无法恢复。',
                          confirmText: '删除',
                          destructive: true,
                        );
                        if (!ok) return;
                        await widget.state.deleteSleep(widget.sleep!.id);
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      },
                      child: const Text('删除记录'),
                    ),
                  ] else if (widget.state.ongoingSleep == null) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => _manual = false),
                      child: const Text('返回开始计时'),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
