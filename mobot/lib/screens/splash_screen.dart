import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Branded splash (always dark). Fades into the app when [onDone] navigates.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});
  final WidgetBuilder next;
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (ctx, _, __) => widget.next(ctx),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeInOut),
          child: child,
        ),
      ));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = CurvedAnimation(parent: _c, curve: const Interval(0, 0.7, curve: Curves.easeOutCubic));
    final tag = CurvedAnimation(parent: _c, curve: const Interval(0.55, 1, curve: Curves.easeOut));
    return Scaffold(
      backgroundColor: MoColors.navy,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(alignment: Alignment.center, children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: MoColors.teal.withValues(alpha: 0.22 * _c.value), blurRadius: 90, spreadRadius: 10)],
                ),
              ),
            ),
            FadeTransition(
              opacity: logo,
              child: ScaleTransition(
                scale: Tween(begin: 0.8, end: 1.0).animate(logo),
                child: Image.asset('assets/logo_dark.png', width: 240, height: 240),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          FadeTransition(
            opacity: tag,
            child: Text('HUMAN · ROBOT · ASSISTANT',
                style: TextStyle(fontSize: 12, letterSpacing: 4, color: Colors.white.withValues(alpha: 0.55))),
          ),
        ]),
      ),
    );
  }
}
