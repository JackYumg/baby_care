import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../../domain/time_rules.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'growth_form_sheet.dart';

class GrowthPage extends StatefulWidget {
  const GrowthPage({super.key, required this.state});

  final AppState state;

  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends State<GrowthPage> {
  _Metric _metric = _Metric.height;
  int _selectedPoint = -1;

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('生长记录'),
        actions: [
          IconButton(
            tooltip: '添加测量',
            onPressed: () => showGrowthFormSheet(context, state),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final records = state.growthRecords;
          if (records.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                const EmptyState(
                  icon: Icons.show_chart_rounded,
                  title: '还没有生长记录',
                  subtitle: '记录身高、体重和头围，看看宝宝的生长趋势',
                ),
                FilledButton.icon(
                  onPressed: () => showGrowthFormSheet(context, state),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加测量'),
                ),
              ],
            );
          }
          final points = _chartPoints(records);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _latestCard(context, records),
              const SectionHeader('生长曲线'),
              SegmentedButton<_Metric>(
                expandedInsets: EdgeInsets.zero,
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Metric.height, label: Text('身高')),
                  ButtonSegment(value: _Metric.weight, label: Text('体重')),
                  ButtonSegment(value: _Metric.head, label: Text('头围')),
                ],
                selected: {_metric},
                onSelectionChanged: (value) => setState(() {
                  _metric = value.first;
                  _selectedPoint = -1;
                }),
              ),
              const SizedBox(height: 12),
              _chartCard(context, points),
              SectionHeader(
                '全部记录',
                trailing: Text(
                  '${records.length} 条',
                  style: const TextStyle(fontSize: 12, color: AppColors.subtle),
                ),
              ),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < records.length; i++) ...[
                      if (i > 0) const Divider(indent: 68, endIndent: 16),
                      _recordTile(context, records[i]),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _latestCard(BuildContext context, List<GrowthRecord> records) {
    final theme = Theme.of(context);
    final latest = records.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.monitor_weight_outlined,
                  size: 18,
                  color: AppColors.green,
                ),
                const SizedBox(width: 6),
                Text(
                  '最新测量',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  _dateText(latest.measuredAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.subtle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _Metric.values.length; i++) ...[
                  if (i > 0)
                    Container(width: 1, height: 44, color: AppColors.border),
                  Expanded(
                    child: _metricCell(context, _Metric.values[i], records),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCell(
    BuildContext context,
    _Metric metric,
    List<GrowthRecord> records,
  ) {
    final theme = Theme.of(context);
    final value = metric.valueOf(records.first);
    final previous = _previousValue(records, metric);
    final delta = value == null || previous == null ? null : value - previous;
    final String deltaText;
    if (value == null) {
      deltaText = '';
    } else if (previous == null) {
      deltaText = '首次记录';
    } else if (delta!.abs() < 0.05) {
      deltaText = '持平';
    } else {
      final sign = delta > 0 ? '+' : '-';
      deltaText = '$sign${delta.abs().toStringAsFixed(1)}${metric.unit}';
    }
    final deltaColor = delta != null && delta > 0.049
        ? AppColors.green
        : AppColors.subtle;
    return Column(
      children: [
        Text(
          metric.label,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.subtle),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value == null ? '--' : value.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              metric.unit,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: AppColors.subtle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(deltaText, style: TextStyle(fontSize: 11, color: deltaColor)),
      ],
    );
  }

  Widget _chartCard(BuildContext context, List<_ChartPoint> points) {
    final theme = Theme.of(context);
    final metric = _metric;
    final selected = _selectedPoint >= 0 && _selectedPoint < points.length
        ? points[_selectedPoint]
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${metric.label}随月龄变化',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '单位：${metric.unit}',
                  style: const TextStyle(fontSize: 11, color: AppColors.subtle),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected == null
                    ? AppColors.apricot.withValues(alpha: 0.45)
                    : AppColors.greenSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                selected == null
                    ? '点击数据点，查看那次测量的日期与数值'
                    : '${_dateText(selected.measuredAt)} · '
                          '${metric.label} ${selected.value.toStringAsFixed(1)} '
                          '${metric.unit}',
                style: TextStyle(
                  fontSize: 12,
                  color: selected == null
                      ? AppColors.subtle
                      : AppColors.greenDark,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (points.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    '这个指标还没有数据',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.subtle,
                    ),
                  ),
                ),
              )
            else ...[
              _GrowthChart(
                points: points,
                color: metric.color,
                selectedIndex: selected == null ? -1 : _selectedPoint,
                onTap: (index) => setState(() => _selectedPoint = index),
              ),
              if (points.length < 2)
                Center(
                  child: Text(
                    '再记录一次即可看到趋势',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.subtle,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recordTile(BuildContext context, GrowthRecord record) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.greenSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.straighten_rounded,
          size: 20,
          color: AppColors.greenDark,
        ),
      ),
      title: Text(
        _dateText(record.measuredAt),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _recordSummary(record),
        style: const TextStyle(fontSize: 12, color: AppColors.subtle),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.subtle,
      ),
      onTap: () => showGrowthFormSheet(context, state, record: record),
    );
  }

  List<_ChartPoint> _chartPoints(List<GrowthRecord> records) {
    final birth = state.currentBaby?.birthDate;
    final birthDate = birth == null
        ? null
        : DateTime.utc(birth.year, birth.month, birth.day);
    final points = <_ChartPoint>[];
    for (final record in records.reversed) {
      final value = _metric.valueOf(record);
      if (value == null) continue;
      var month = 0.0;
      if (birthDate != null) {
        final (date, _, _) = splitStatDateTime(record.measuredAt);
        month = date.difference(birthDate).inDays / 30.4375;
      }
      points.add(
        _ChartPoint(month: month, value: value, measuredAt: record.measuredAt),
      );
    }
    return points;
  }

  static double? _previousValue(List<GrowthRecord> records, _Metric metric) {
    for (var i = 1; i < records.length; i++) {
      final value = metric.valueOf(records[i]);
      if (value != null) return value;
    }
    return null;
  }

  static String _dateText(int ms) {
    final (date, _, _) = splitStatDateTime(ms);
    if (date.year == todayStatDate().year) return formatMonthDay(date);
    return '${date.year}年${date.month}月${date.day}日';
  }

  static String _recordSummary(GrowthRecord record) {
    final parts = <String>[
      if (record.heightCm != null)
        '身高 ${record.heightCm!.toStringAsFixed(1)}cm',
      if (record.weightKg != null)
        '体重 ${record.weightKg!.toStringAsFixed(1)}kg',
      if (record.headCm != null) '头围 ${record.headCm!.toStringAsFixed(1)}cm',
    ];
    return parts.isEmpty ? '已记录' : parts.join(' · ');
  }
}

enum _Metric {
  height('身高', 'cm', AppColors.green),
  weight('体重', 'kg', Color(0xFFB98A5E)),
  head('头围', 'cm', Color(0xFF6C86B8));

  const _Metric(this.label, this.unit, this.color);

  final String label;
  final String unit;
  final Color color;

  double? valueOf(GrowthRecord record) => switch (this) {
    _Metric.height => record.heightCm,
    _Metric.weight => record.weightKg,
    _Metric.head => record.headCm,
  };
}

class _ChartPoint {
  const _ChartPoint({
    required this.month,
    required this.value,
    required this.measuredAt,
  });

  final double month;
  final double value;
  final int measuredAt;
}

class _GrowthChart extends StatelessWidget {
  const _GrowthChart({
    required this.points,
    required this.color,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<_ChartPoint> points;
  final Color color;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  static const double _height = 190;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, _height);
          final geometry = _ChartGeometry(size: size, points: points);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final index = geometry.nearestIndex(details.localPosition);
              if (index != null) onTap(index);
            },
            child: CustomPaint(
              size: size,
              painter: _GrowthChartPainter(
                geometry: geometry,
                color: color,
                selectedIndex: selectedIndex,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChartGeometry {
  _ChartGeometry({required this.size, required this.points}) {
    if (points.isEmpty) return;
    var minMonth = points.first.month;
    var maxMonth = points.first.month;
    var minValue = points.first.value;
    var maxValue = points.first.value;
    for (final point in points) {
      minMonth = math.min(minMonth, point.month);
      maxMonth = math.max(maxMonth, point.month);
      minValue = math.min(minValue, point.value);
      maxValue = math.max(maxValue, point.value);
    }
    if (maxMonth - minMonth < 0.5) {
      minMonth -= 0.5;
      maxMonth += 0.5;
    } else {
      final padding = (maxMonth - minMonth) * 0.08;
      minMonth -= padding;
      maxMonth += padding;
    }
    final valueSpan = maxValue - minValue;
    final valuePadding = valueSpan < 0.001
        ? math.max(maxValue.abs() * 0.05, 1.0)
        : valueSpan * 0.2;
    xMin = minMonth;
    xMax = maxMonth;
    yMin = minValue - valuePadding;
    yMax = maxValue + valuePadding;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    offsets = [
      for (final point in points)
        Offset(
          left + (point.month - xMin) / (xMax - xMin) * chartWidth,
          top + (yMax - point.value) / (yMax - yMin) * chartHeight,
        ),
    ];
  }

  static const double left = 42;
  static const double right = 14;
  static const double top = 14;
  static const double bottom = 28;

  final Size size;
  final List<_ChartPoint> points;

  double xMin = 0;
  double xMax = 1;
  double yMin = 0;
  double yMax = 1;
  List<Offset> offsets = const [];

  int? nearestIndex(Offset position) {
    if (offsets.isEmpty) return null;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < offsets.length; i++) {
      final distance = (offsets[i] - position).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return bestDistance <= 40 * 40 ? best : null;
  }
}

class _GrowthChartPainter extends CustomPainter {
  _GrowthChartPainter({
    required this.geometry,
    required this.color,
    required this.selectedIndex,
  });

  final _ChartGeometry geometry;
  final Color color;
  final int selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final points = geometry.points;
    if (points.isEmpty) return;
    final rect = Rect.fromLTRB(
      _ChartGeometry.left,
      _ChartGeometry.top,
      size.width - _ChartGeometry.right,
      size.height - _ChartGeometry.bottom,
    );

    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    const yTicks = 4;
    for (var i = 0; i < yTicks; i++) {
      final t = i / (yTicks - 1);
      final y = rect.top + t * rect.height;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
      final value = geometry.yMax - t * (geometry.yMax - geometry.yMin);
      final label = _textPainter(value.toStringAsFixed(1));
      label.paint(
        canvas,
        Offset(rect.left - 8 - label.width, y - label.height / 2),
      );
    }

    final axisPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, axisPaint);
    canvas.drawLine(rect.topLeft, rect.bottomLeft, axisPaint);

    const xTicks = 3;
    for (var i = 0; i < xTicks; i++) {
      final t = i / (xTicks - 1);
      final x = rect.left + t * rect.width;
      final month = geometry.xMin + t * (geometry.xMax - geometry.xMin);
      final label = _textPainter(_monthLabel(month));
      final dx = switch (i) {
        0 => x,
        2 => x - label.width,
        _ => x - label.width / 2,
      };
      label.paint(canvas, Offset(dx, rect.bottom + 8));
    }

    if (geometry.offsets.length > 1) {
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()
        ..moveTo(geometry.offsets.first.dx, geometry.offsets.first.dy);
      for (final offset in geometry.offsets.skip(1)) {
        path.lineTo(offset.dx, offset.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    for (var i = 0; i < geometry.offsets.length; i++) {
      final selected = i == selectedIndex;
      final radius = selected ? 4.5 : 3.2;
      final haloPaint = Paint()..color = color.withValues(alpha: 0.16);
      final fillPaint = Paint()..color = selected ? color : Colors.white;
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(geometry.offsets[i], radius + 3, haloPaint);
      canvas.drawCircle(geometry.offsets[i], radius, fillPaint);
      canvas.drawCircle(geometry.offsets[i], radius, strokePaint);
    }
  }

  TextPainter _textPainter(String text) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 10, color: AppColors.subtle),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  static String _monthLabel(double month) {
    final rounded = month.roundToDouble();
    if (month.abs() >= 10) return month.toStringAsFixed(0);
    return month.toStringAsFixed(month == rounded ? 0 : 1);
  }

  @override
  bool shouldRepaint(covariant _GrowthChartPainter oldDelegate) => true;
}
