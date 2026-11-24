import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// App 启动过渡页：初始化数据期间展示品牌图标与名称。
class SplashView extends StatefulWidget {
  const SplashView({super.key, this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..forward();
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.75, curve: Curves.easeOut),
    );
    _slide = Tween(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = theme.colorScheme.surface;
    final hasError = widget.error != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: background,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: background,
        body: Stack(
          children: [
            // 顶部柔和光晕，避免大面积纯色显得空。
            Positioned(
              top: -140,
              left: -80,
              right: -80,
              height: 460,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.10),
                        background.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: _slide,
                      child: Column(
                        children: [
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C3A2F)
                                  : AppColors.greenSoft,
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Icon(
                              Icons.child_care_rounded,
                              size: 52,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            '育婴',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 8,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            hasError ? '启动遇到问题' : '记录每一次喝奶、睡眠与成长',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.subtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(flex: 4),
                  FadeTransition(
                    opacity: _fade,
                    child: hasError
                        ? _buildError(theme)
                        : Text(
                            '数据仅保存在本机',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.subtle,
                            ),
                          ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            '${widget.error}',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.subtle),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: widget.onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
