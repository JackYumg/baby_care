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
    return Material(
      color: color.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
  final pickedTime = await _showTimeGridPicker(
    context,
    initialTime: TimeOfDay(hour: hour, minute: minute),
  );
  if (pickedTime == null) return null;
  return combineStatDateTime(
    DateTime.utc(pickedDate.year, pickedDate.month, pickedDate.day),
    pickedTime.hour,
    pickedTime.minute,
  );
}

/// 底部弹窗大按钮时间选择器，适合老年人操作。
Future<TimeOfDay?> _showTimeGridPicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) async {
  int hour = initialTime.hour;
  // 分钟对齐到最近的 5 步长
  int minute = (initialTime.minute / 5).round() * 5;
  if (minute >= 60) minute = 55;

  final theme = Theme.of(context);

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 标题
                  Text(
                    '选择时间',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 当前选中时间大显示
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: AppColors.greenSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        color: AppColors.greenDark,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 小时选择 4 列 x 6 行
                  Text(
                    '小时',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildTimeGrid(
                    sheetContext,
                    itemCount: 24,
                    crossAxisCount: 4,
                    selectedIndex: hour,
                    labelBuilder: (i) => i.toString().padLeft(2, '0'),
                    onTap: (i) => setSheetState(() => hour = i),
                  ),
                  const SizedBox(height: 20),
                  // 分钟选择 0,5,10...55 共 12 个
                  Text(
                    '分钟（步长 5）',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildTimeGrid(
                    sheetContext,
                    itemCount: 12,
                    crossAxisCount: 4,
                    selectedIndex: minute ~/ 5,
                    labelBuilder: (i) => (i * 5).toString().padLeft(2, '0'),
                    onTap: (i) => setSheetState(() => minute = i * 5),
                  ),
                  const SizedBox(height: 28),
                  // 底部按钮
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(
                            sheetContext,
                          ).pop(TimeOfDay(hour: hour, minute: minute)),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('确定'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _buildTimeGrid(
  BuildContext context, {
  required int itemCount,
  required int crossAxisCount,
  required int selectedIndex,
  required String Function(int i) labelBuilder,
  required ValueChanged<int> onTap,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  return GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
    ),
    itemCount: itemCount,
    itemBuilder: (_, i) {
      final selected = i == selectedIndex;
      return GestureDetector(
        onTap: () => onTap(i),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Text(
            labelBuilder(i),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: selected
                  ? colorScheme.onPrimary
                  : theme.textTheme.bodyLarge?.color,
            ),
          ),
        ),
      );
    },
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
