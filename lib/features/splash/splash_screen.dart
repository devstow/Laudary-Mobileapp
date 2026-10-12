import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';

/// Branded launch screen shown while the saved session is restored.
///
/// Blue brand gradient with slowly breathing "washing-machine door" rings, the app
/// mark on a white tile, the wordmark + tagline, and a bouncing amber loader.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoIn = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.7, curve: Curves.easeOutBack));
    final textIn = CurvedAnimation(parent: _intro, curve: const Interval(0.35, 1, curve: Curves.easeOutCubic));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Breathing concentric rings behind the logo.
              AnimatedBuilder(
                animation: _loop,
                builder: (context, _) => CustomPaint(
                  size: Size(size.width, size.height),
                  painter: _RingsPainter(_loop.value),
                ),
              ),
              // Soft amber bubbles for warmth.
              PositionedDirectional(top: size.height * 0.12, end: 36, child: _bubble(18, 0.9)),
              PositionedDirectional(top: size.height * 0.2, start: 42, child: _bubble(10, 0.6)),
              PositionedDirectional(bottom: size.height * 0.2, end: 58, child: _bubble(12, 0.5)),
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 5),
                    ScaleTransition(
                      scale: logoIn,
                      child: Container(
                        width: 104,
                        height: 104,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 30, offset: const Offset(0, 14)),
                          ],
                        ),
                        child: Image.asset('assets/brand/smartwash-mark.png', fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 26),
                    FadeTransition(
                      opacity: textIn,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(textIn),
                        child: Column(children: [
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8, color: Colors.white),
                              children: [
                                TextSpan(text: 'Smart'),
                                TextSpan(text: 'Wash', style: TextStyle(color: AppColors.goldBright)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.t('Fresh laundry, picked up & delivered'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82), fontSize: 14.5, fontWeight: FontWeight.w500),
                          ),
                        ]),
                      ),
                    ),
                    const Spacer(flex: 4),
                    _BouncingDots(controller: _loop),
                    const SizedBox(height: 34),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _bubble(double d, double alpha) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: alpha), shape: BoxShape.circle),
      );
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    for (var i = 0; i < 4; i++) {
      final phase = (t + i / 4) % 1.0;
      final radius = 70 + phase * size.width * 0.75;
      final alpha = (1 - phase) * 0.16;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14 * (1 - phase) + 2
        ..color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}

class _BouncingDots extends StatelessWidget {
  const _BouncingDots({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final v = math.sin(((controller.value * 2) - i * 0.18) * 2 * math.pi);
          final lift = v > 0 ? v * 7 : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Transform.translate(
              offset: Offset(0, -lift),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: i == 1 ? AppColors.gold : Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
