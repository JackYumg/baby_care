import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'data/app_database.dart';
import 'features/babies/babies_page.dart';
import 'features/babies/baby_form_page.dart';
import 'features/splash/splash_page.dart';
import 'features/statistics/statistics_page.dart';
import 'features/tasks/tasks_page.dart';
import 'features/today/today_page.dart';
import 'platform/alarm_scheduler.dart';
import 'platform/care_reminders.dart';
import 'platform/feed_notifications.dart';
import 'state/app_state.dart';

class YuyingApp extends StatelessWidget {
  const YuyingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '育婴',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashGate(),
    );
  }
}

/// 先展示启动过渡页，初始化完成后再淡入主界面。
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  static const Duration _minimumSplash = Duration(milliseconds: 950);

  AppState? _state;
  Object? _error;
  bool _booting = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (_booting) return;
    _booting = true;
    final startedAt = DateTime.now();
    try {
      // 清理可能残留的响铃服务，避免重启后一直响。
      unawaited(AlarmScheduler.stopRinging());
      await FeedNotifications.init();
      final db = await AppDatabase.open();
      final state = AppState(db);
      await state.init();
      // 启动时补排未来待办提醒，不阻塞进入主界面。
      unawaited(syncCareReminders(state));
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < _minimumSplash) {
        await Future<void>.delayed(_minimumSplash - elapsed);
      }
      if (!mounted) return;
      setState(() => _state = state);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      _booting = false;
    }
  }

  void _retry() {
    setState(() => _error = null);
    _boot();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: state == null
          ? SplashView(
              key: const ValueKey('splash'),
              error: _error,
              onRetry: _retry,
            )
          : AppRoot(key: const ValueKey('app'), state: state),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        if (state.babies.isEmpty) return OnboardingPage(state: state);
        return HomeShell(state: state);
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// 待办页在首次切换过去时才创建，避免启动即触发生成默认计划。
  bool _tasksOpened = false;

  void _selectTab(int value) {
    setState(() {
      _index = value;
      if (value == 1) _tasksOpened = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          TodayPage(state: widget.state),
          _tasksOpened
              ? TasksPage(state: widget.state)
              : const SizedBox.shrink(),
          StatisticsPage(state: widget.state),
          BabiesPage(state: widget.state),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_rounded),
            selectedIcon: Icon(Icons.today),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_rounded),
            selectedIcon: Icon(Icons.event_note),
            label: '待办',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_rounded),
            selectedIcon: Icon(Icons.insights),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.child_care_rounded),
            selectedIcon: Icon(Icons.child_care),
            label: '宝宝',
          ),
        ],
      ),
    );
  }
}

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.greenSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.child_care_rounded,
                  size: 44,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '欢迎使用育婴',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '记录喝奶、排便和睡眠，数据只保存在本机。\n先创建一个宝宝档案开始吧。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.subtle,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BabyFormPage(state: state)),
                ),
                child: const Text('创建宝宝档案'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
