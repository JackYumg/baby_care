import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/daily_statistics.dart';
import '../../domain/time_rules.dart';
import '../../state/app_state.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, required this.state});

  final AppState state;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  late Future<TrendSeries> _trend;
  DateTime? _date;
  int _version = -1;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _date = state.selectedDate;
    _version = state.dataVersion;
    _trend = state.loadTrend();
    state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (_date == state.selectedDate && _version == state.dataVersion) return;
    _date = state.selectedDate;
    _version = state.dataVersion;
    setState(() {
      _trend = state.loadTrend();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final summary = state.summary;
        return Scaffold(
          appBar: AppBar(titleSpacing: 20, title: const Text('统计')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _dateBar(context),
              const SizedBox(height: 12),
              Text(
                '按北京时间统计 · ${state.currentBaby?.nickname ?? ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.subtle),
              ),
              const SizedBox(height: 12),
              _dailySummaryCard(summary),
              const SizedBox(height: 16),
              FutureBuilder<TrendSeries>(
                future: _trend,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final data = snapshot.data!;
                  return Column(
                    children: [
                      _TrendCard(
                        title: '近 7 天瓶喂奶量',
                        unit: 'ml',
                        color: AppColors.green,
                        values: data.bottleMl,
                        dates: data.dates,
                      ),
                      const SizedBox(height: 12),
                      _TrendCard(
                        title: '近 7 天睡眠时长',
                        unit: '分钟',
                        color: const Color(0xFF6C86B8),
                        values: data.sleepMinutes,
                        dates: data.dates,
                      ),
                      const SizedBox(height: 12),
                      _TrendCard(
                        title: '近 7 天排便次数',
                        unit: '次',
                        color: const Color(0xFF8C7BAE),
                        values: data.stoolCounts,
                        dates: data.dates,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dateBar(BuildContext context) {
    final date = state.selectedDate;
    return Row(
      children: [
        IconButton(
          onPressed: () => state.selectDate(addDays(date, -1)),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Center(
            child: Text(
              '${formatMonthDay(date)} · ${weekdayLabel(date)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          onPressed: state.isToday
              ? null
              : () => state.selectDate(addDays(date, 1)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _dailySummaryCard(DailySummary summary) {
    final rows = [
      ('瓶喂奶量', '${summary.bottleMl} ml'),
      (
        '亲喂',
        '${formatDuration(summary.directSeconds)} · ${summary.directSessions} 次',
      ),
      (
        '睡眠',
        '${formatDuration(summary.sleepSeconds)}'
            '${summary.hasOngoingSleep ? '（含进行中）' : ''}',
      ),
      ('排便', '${summary.stoolCount} 次'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 20),
              Row(
                children: [
                  Text(
                    rows[i].$1,
                    style: const TextStyle(color: AppColors.subtle),
                  ),
                  const Spacer(),
                  Text(
                    rows[i].$2,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.unit,
    required this.color,
    required this.values,
    required this.dates,
  });

  final String title;
  final String unit;
  final Color color;
  final List<int> values;
  final List<DateTime> dates;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(0, (a, b) => b > a ? b : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '单位：$unit',
                  style: const TextStyle(fontSize: 11, color: AppColors.subtle),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 128,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${values[i]}',
                              style: TextStyle(
                                fontSize: 10,
                                color: values[i] == 0
                                    ? AppColors.subtle
                                    : AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              height: maxValue == 0
                                  ? 3
                                  : (values[i] / maxValue) * 86 + 3,
                              decoration: BoxDecoration(
                                color: values[i] == 0
                                    ? AppColors.border
                                    : color.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < dates.length; i++)
                  Expanded(
                    child: Text(
                      '${dates[i].month}/${dates[i].day}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.subtle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
