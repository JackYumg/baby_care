import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/time_rules.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class SummaryTile extends StatelessWidget {
  const SummaryTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.subtle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.subtle,
                  ),
                ),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.subtle,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.greenSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.green, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.subtle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选择北京时间日期与时分，返回 UTC 毫秒。
Future<int?> pickStatDateTime(
  BuildContext context, {
  required int initialMs,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final (date, hour, minute) = splitStatDateTime(initialMs);
  final today = todayStatDate();
  final pickedDate = await showDatePicker(
    context: context,
    initialDate: DateTime(date.year, date.month, date.day),
    firstDate: firstDate ?? DateTime(2018, 1, 1),
    lastDate: lastDate ?? DateTime(today.year, today.month, today.day),
    helpText: '选择日期',
    cancelText: '取消',
    confirmText: '确定',
  );
  if (pickedDate == null || !context.mounted) return null;
  final pickedTime = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: hour, minute: minute),
    helpText: '选择时间',
    cancelText: '取消',
    confirmText: '确定',
  );
  if (pickedTime == null) return null;
  return combineStatDateTime(
    DateTime.utc(pickedDate.year, pickedDate.month, pickedDate.day),
    pickedTime.hour,
    pickedTime.minute,
  );
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size(88, 44),
                )
              : FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showErrorSnack(BuildContext context, Object error) {
  final message = error is ArgumentError
      ? (error.message?.toString() ?? '输入内容不正确')
      : error is StateError
      ? error.message
      : error.toString();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message.replaceFirst('Exception: ', ''))),
  );
}

void showSuccessSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.label,
    required this.valueMs,
    required this.onChanged,
  });

  final String label;
  final int valueMs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final (date, hour, minute) = splitStatDateTime(valueMs);
    final isToday = date == todayStatDate();
    final text =
        '${isToday ? '今天' : formatMonthDay(date)} '
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final picked = await pickStatDateTime(context, initialMs: valueMs);
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.schedule_rounded, size: 20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
