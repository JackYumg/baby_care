import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../../domain/time_rules.dart';
import '../../platform/care_reminders.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 疫苗待办详情：改期、记录接种情况、跳过与删除。
class VaccineDetailPage extends StatefulWidget {
  const VaccineDetailPage({
    super.key,
    required this.state,
    required this.record,
  });

  final AppState state;
  final VaccineRecord record;

  @override
  State<VaccineDetailPage> createState() => _VaccineDetailPageState();
}

class _VaccineDetailPageState extends State<VaccineDetailPage> {
  late final TextEditingController _note;
  late final TextEditingController _temperature;
  late int _scheduledAt;
  late int _administeredAt;
  late bool _fever;
  bool _saving = false;

  VaccineRecord get _record => widget.record;

  bool get _isDone => _record.status == CareTaskStatus.done;

  @override
  void initState() {
    super.initState();
    _scheduledAt = _record.scheduledAt;
    _administeredAt =
        _record.administeredAt ?? DateTime.now().millisecondsSinceEpoch;
    _fever = _record.fever;
    _temperature = TextEditingController(
      text: _record.temperature == null
          ? ''
          : _record.temperature!.toStringAsFixed(1),
    );
    _note = TextEditingController(text: _record.note ?? '');
  }

  @override
  void dispose() {
    _temperature.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _noteText => _note.text.trim();

  double? _validatedTemperature() {
    if (!_fever) return null;
    final text = _temperature.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value < 37.0 || value > 42.0) {
      throw const FormatException('体温需在 37.0～42.0℃ 之间');
    }
    return value;
  }

  Future<void> _pickScheduledAt() async {
    final today = todayStatDate();
    final picked = await pickStatDateTime(
      context,
      initialMs: _scheduledAt,
      firstDate: DateTime(2018, 1, 1),
      lastDate: DateTime(today.year + 10, 12, 31),
    );
    if (picked != null && mounted) setState(() => _scheduledAt = picked);
  }

  Future<void> _pickAdministeredAt() async {
    final today = todayStatDate();
    final (date, _, _) = splitStatDateTime(_administeredAt);
    final initial = date.isAfter(today) ? today : date;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2018, 1, 1),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: '选择接种日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _administeredAt = combineStatDateTime(
        DateTime.utc(picked.year, picked.month, picked.day),
        9,
        0,
      );
    });
  }

  Future<void> _save() async {
    final double? temperature;
    try {
      temperature = _validatedTemperature();
    } on FormatException catch (error) {
      showSuccessSnack(context, error.message);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.state.updateVaccine(
        id: _record.id,
        scheduledAt: _scheduledAt,
        note: _noteText,
      );
      if (_isDone) {
        await widget.state.markVaccineDone(
          id: _record.id,
          administeredAt: _administeredAt,
          fever: _fever,
          temperature: temperature,
          note: _noteText,
        );
      }
      await syncCareReminders(widget.state);
      if (!mounted) return;
      showSuccessSnack(context, '已保存修改');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _markDone() async {
    final double? temperature;
    try {
      temperature = _validatedTemperature();
    } on FormatException catch (error) {
      showSuccessSnack(context, error.message);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.state.markVaccineDone(
        id: _record.id,
        administeredAt: _administeredAt,
        fever: _fever,
        temperature: temperature,
        note: _noteText,
      );
      await syncCareReminders(widget.state);
      if (!mounted) return;
      showSuccessSnack(context, '已记录接种');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skip() async {
    final reason = await _askSkipReason();
    if (reason == null) return;
    final trimmed = reason.trim();
    try {
      if (trimmed.isNotEmpty) {
        final existing = _record.note?.trim() ?? '';
        await widget.state.updateVaccine(
          id: _record.id,
          note: existing.isEmpty
              ? '跳过原因：$trimmed'
              : '$existing\n跳过原因：$trimmed',
        );
      }
      await widget.state.skipVaccine(_record.id);
      await syncCareReminders(widget.state);
      if (!mounted) return;
      showSuccessSnack(context, '已跳过这次接种');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<String?> _askSkipReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳过这次接种？'),
        content: TextField(
          controller: controller,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: '原因（可选）',
            hintText: '例如：宝宝发热，延后接种',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('跳过'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这条疫苗待办？',
      message: '删除后无法恢复，其他待办与记录不受影响。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok) return;
    try {
      await widget.state.deleteVaccine(_record.id);
      await syncCareReminders(widget.state);
      if (!mounted) return;
      showSuccessSnack(context, '已删除');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final administeredAt = _record.administeredAt;
    return Scaffold(
      appBar: AppBar(title: const Text('接种详情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          if (_isDone && administeredAt != null)
            _StatusBanner(
              icon: Icons.check_circle_rounded,
              color: AppColors.green,
              text:
                  '已接种 · ${formatMonthDay(statDateFromMs(administeredAt))}'
                  '${_record.fever ? ' · 发烧 ${_temperatureLabel(_record.temperature)}' : ' · 未发烧'}',
            ),
          if (_record.status == CareTaskStatus.skipped)
            const _StatusBanner(
              icon: Icons.remove_circle_outline_rounded,
              color: AppColors.subtle,
              text: '已跳过，不会发送提醒',
            ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB98A5E).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.vaccines_outlined,
                      color: Color(0xFFB98A5E),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _record.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '第 ${_record.dose} 剂',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.subtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader('接种安排'),
          _ScheduleField(valueMs: _scheduledAt, onTap: _pickScheduledAt),
          const SizedBox(height: 12),
          _ScheduleField(
            valueMs: _administeredAt,
            label: '实际接种日期',
            icon: Icons.event_available_rounded,
            onTap: _pickAdministeredAt,
          ),
          const SizedBox(height: 6),
          const Text(
            '实际接种日期与体温在「标记已接种」时生效',
            style: TextStyle(fontSize: 11, color: AppColors.subtle),
          ),
          Card(
            margin: const EdgeInsets.only(top: 16),
            child: Column(
              children: [
                SwitchListTile(
                  value: _fever,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _fever = value),
                  secondary: const Icon(Icons.thermostat_rounded),
                  title: const Text('发烧'),
                  subtitle: const Text('接种后出现发热时记录体温'),
                ),
                if (_fever) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: TextField(
                      controller: _temperature,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: '体温',
                        suffixText: '℃',
                        hintText: '37.0 ~ 42.0，可留空',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              counterText: '',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存修改'),
          ),
          if (!_isDone) ...[
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: _saving ? null : _markDone,
              child: const Text('标记已接种'),
            ),
          ],
          if (_record.status == CareTaskStatus.pending) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _saving ? null : _skip,
              child: const Text('跳过'),
            ),
          ],
          const SizedBox(height: 6),
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除待办'),
          ),
        ],
      ),
    );
  }

  String _temperatureLabel(double? value) =>
      value == null ? '未填写体温' : '${value.toStringAsFixed(1)}℃';
}

class _ScheduleField extends StatelessWidget {
  const _ScheduleField({
    required this.valueMs,
    required this.onTap,
    this.label = '计划接种日期',
    this.icon = Icons.event_rounded,
  });

  final int valueMs;
  final VoidCallback onTap;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final (date, hour, minute) = splitStatDateTime(valueMs);
    final isToday = date == todayStatDate();
    final showClock = label != '实际接种日期';
    final text =
        '${isToday ? '今天' : formatMonthDay(date)} · ${weekdayLabel(date)}'
        '${showClock ? ' ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}' : ''}';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Icon(icon, size: 20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}
