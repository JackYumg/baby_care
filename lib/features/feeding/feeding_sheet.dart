import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/feeding_reminder.dart';
import '../../domain/models.dart';
import '../../domain/time_rules.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

Future<void> showFeedingSheet(BuildContext context, AppState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => FeedingSheet(state: state),
  );
}

class FeedingSheet extends StatefulWidget {
  const FeedingSheet({super.key, required this.state});

  final AppState state;

  @override
  State<FeedingSheet> createState() => _FeedingSheetState();
}

class _FeedingSheetState extends State<FeedingSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late int _timeMs;
  MilkType _milkType = MilkType.formula;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _showManual = false;
  int? _manualStart;
  final _leftController = TextEditingController();
  final _rightController = TextEditingController();
  bool _saving = false;
  bool _remindEnabled = true;
  bool _remindManual = false;
  int? _remindAt;

  AppState get state => widget.state;

  int? get _amountMl => int.tryParse(_amountController.text.trim());

  /// 奶量或喝奶时间变化时，按建议间隔刷新提醒时间（用户手动改过则保持不变）。
  void _refreshSuggestedRemind() {
    final amount = _amountMl;
    if (_remindManual || amount == null || amount <= 0) return;
    _remindAt = _timeMs + estimateFeedRemindMinutes(amount) * 60 * 1000;
  }

  Future<void> _pickRemindTime() async {
    final initial =
        _remindAt ?? _timeMs + kDefaultDirectRemindMinutes * 60 * 1000;
    final picked = await pickStatDateTime(
      context,
      initialMs: initial,
      lastDate: DateTime.now().add(const Duration(days: 2)),
    );
    if (picked == null) return;
    setState(() {
      _remindAt = picked;
      _remindManual = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _timeMs = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _leftController.dispose();
    _rightController.dispose();
    super.dispose();
  }

  Future<void> _saveBottle() async {
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      showSuccessSnack(context, '请输入有效的奶量（毫升）');
      return;
    }
    if (amount > 2000) {
      showSuccessSnack(context, '奶量看起来过大，请确认');
      return;
    }
    if (_timeMs > DateTime.now().millisecondsSinceEpoch) {
      showSuccessSnack(context, '时间不能晚于当前时间');
      return;
    }
    setState(() => _saving = true);
    try {
      final remindAt = _remindEnabled
          ? (_remindAt ??
                _timeMs + estimateFeedRemindMinutes(amount) * 60 * 1000)
          : null;
      await state.addBottleFeeding(
        startedAt: _timeMs,
        amountMl: amount,
        milkType: _milkType,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        remindAt: remindAt,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnack(
        context,
        remindAt != null
            ? '已记录 ${amount}ml，将在 ${formatClock(remindAt)} 提醒'
            : '已记录 ${amount}ml',
      );
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveManual() async {
    final left = int.tryParse(_leftController.text.trim()) ?? 0;
    final right = int.tryParse(_rightController.text.trim()) ?? 0;
    if (left < 0 || right < 0) {
      showSuccessSnack(context, '时长不能为负数');
      return;
    }
    if (left == 0 && right == 0) {
      showSuccessSnack(context, '请填写左侧或右侧的分钟数');
      return;
    }
    final start = _manualStart ?? DateTime.now().millisecondsSinceEpoch;
    final end = start + (left + right) * 60 * 1000;
    if (end > DateTime.now().millisecondsSinceEpoch) {
      showSuccessSnack(context, '补录时间不能晚于当前时间');
      return;
    }
    setState(() => _saving = true);
    try {
      await state.addManualDirectFeeding(
        startedAt: start,
        leftMinutes: left,
        rightMinutes: right,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnack(context, '已补录亲喂记录');
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
        listenable: state,
        builder: (context, _) {
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                  child: Row(
                    children: [
                      Text(
                        '记录喝奶 · ${state.currentBaby?.nickname ?? ''}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabs,
                  tabs: const [
                    Tab(text: '瓶喂'),
                    Tab(text: '亲喂'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [_buildBottleTab(), _buildDirectTab()],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottleTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        TimeField(
          label: '喝奶时间',
          valueMs: _timeMs,
          onChanged: (value) => setState(() {
            _timeMs = value;
            _refreshSuggestedRemind();
          }),
        ),
        const SizedBox(height: 16),
        Text('奶种', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            ChoiceChip(
              label: const Text('配方奶'),
              selected: _milkType == MilkType.formula,
              onSelected: (_) => setState(() => _milkType = MilkType.formula),
            ),
            ChoiceChip(
              label: const Text('母乳'),
              selected: _milkType == MilkType.breastMilk,
              onSelected: (_) =>
                  setState(() => _milkType = MilkType.breastMilk),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '奶量',
            suffixText: 'ml',
            hintText: '例如 120',
          ),
          onChanged: (_) => setState(_refreshSuggestedRemind),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final amount in const [60, 90, 120, 150])
              ActionChip(
                label: Text('$amount ml'),
                onPressed: () {
                  _amountController.text = '$amount';
                  setState(_refreshSuggestedRemind);
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        _buildReminderCard(),
        const SizedBox(height: 16),
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
          onPressed: _saving ? null : _saveBottle,
          child: const Text('保存瓶喂记录'),
        ),
      ],
    );
  }

  Widget _buildReminderCard() {
    final theme = Theme.of(context);
    final amount = _amountMl;
    final suggested = amount != null && amount > 0
        ? estimateFeedRemindMinutes(amount)
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.alarm_rounded,
                  size: 20,
                  color: AppColors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  '喂奶提醒',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _remindEnabled,
                  onChanged: (value) => setState(() => _remindEnabled = value),
                ),
              ],
            ),
            if (_remindEnabled) ...[
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickRemindTime,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        '提醒时间',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.subtle,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _remindAt == null
                            ? '输入奶量后自动计算'
                            : _remindLabel(_remindAt!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.edit_rounded,
                        size: 16,
                        color: AppColors.subtle,
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                suggested == null
                    ? '按奶量估算下次喂奶时间，可点击手动调整'
                    : '按 ${amount}ml 建议间隔约 ${formatDuration(suggested * 60)}'
                          '${_remindManual ? '，已手动调整' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.subtle,
                ),
              ),
              if (_remindManual)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _remindManual = false;
                      _refreshSuggestedRemind();
                    }),
                    child: const Text('恢复建议时间'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _remindLabel(int ms) {
    final (date, hour, minute) = splitStatDateTime(ms);
    final dayText = date == todayStatDate() ? '今天' : formatMonthDay(date);
    return '$dayText ${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  Widget _buildDirectTab() {
    final active = state.activeFeeding;
    if (_showManual) return _buildManualForm();
    if (active == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          const EmptyState(
            icon: Icons.front_hand_rounded,
            title: '尚未开始亲喂',
            subtitle: '开始后会实时计时，可随时暂停或切换侧别',
          ),
          FilledButton.icon(
            onPressed: () async {
              try {
                await state.startDirectFeeding();
              } catch (error) {
                if (mounted) showErrorSnack(context, error);
              }
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('开始亲喂（左侧）'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() {
              _showManual = true;
              _manualStart = DateTime.now().millisecondsSinceEpoch;
            }),
            child: const Text('手动补录亲喂'),
          ),
        ],
      );
    }
    final side = active.currentSide;
    final seconds = state.nowMs - active.startedAt;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  side == null
                      ? '已暂停'
                      : '亲喂中 · ${side == BreastSide.left ? '左侧' : '右侧'}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: side == null ? AppColors.subtle : AppColors.green,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  formatStopwatch(seconds ~/ 1000),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '左 ${formatDuration(state.activeSideSeconds(BreastSide.left))}'
                  ' · 右 ${formatDuration(state.activeSideSeconds(BreastSide.right))}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.subtle),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: side == BreastSide.left
                    ? null
                    : () => state.switchDirectSide(BreastSide.left),
                child: const Text('换到左侧'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: side == BreastSide.right
                    ? null
                    : () => state.switchDirectSide(BreastSide.right),
                child: const Text('换到右侧'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (side == null)
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => state.resumeDirectFeeding(BreastSide.left),
                  child: const Text('继续左侧'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => state.resumeDirectFeeding(BreastSide.right),
                  child: const Text('继续右侧'),
                ),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: state.pauseDirectFeeding,
            icon: const Icon(Icons.pause_rounded),
            label: const Text('暂停'),
          ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () async {
            try {
              await state.finishDirectFeeding();
              if (!mounted) return;
              Navigator.of(context).pop();
              showSuccessSnack(context, '亲喂记录已保存');
            } catch (error) {
              if (mounted) showErrorSnack(context, error);
            }
          },
          icon: const Icon(Icons.stop_rounded),
          label: const Text('结束并保存'),
        ),
        TextButton(
          onPressed: () async {
            final ok = await showConfirmDialog(
              context,
              title: '放弃本次亲喂？',
              message: '本次计时将被删除，不会计入统计。',
              confirmText: '放弃',
              destructive: true,
            );
            if (!ok) return;
            await state.discardDirectFeeding();
            if (mounted) Navigator.of(context).pop();
          },
          child: const Text('放弃本次计时'),
        ),
      ],
    );
  }

  Widget _buildManualForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        TimeField(
          label: '开始时间',
          valueMs: _manualStart ?? DateTime.now().millisecondsSinceEpoch,
          onChanged: (value) => setState(() => _manualStart = value),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _leftController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '左侧',
                  suffixText: '分钟',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _rightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '右侧',
                  suffixText: '分钟',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '补录会按左侧、右侧的顺序生成连续时间段，仅用于分配时长。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.subtle),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : _saveManual,
          child: const Text('保存补录'),
        ),
        TextButton(
          onPressed: () => setState(() => _showManual = false),
          child: const Text('返回'),
        ),
      ],
    );
  }
}
