import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SoulFireButton extends StatefulWidget {
  const SoulFireButton({
    super.key,
    required this.enabled,
    required this.onConfirmed,
  });

  final bool enabled;
  final VoidCallback onConfirmed;

  @override
  State<SoulFireButton> createState() => _SoulFireButtonState();
}

class _SoulFireButtonState extends State<SoulFireButton>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 1800);
  static const _size = 180.0;

  late final AnimationController _breathController;
  late final AnimationController _holdController;
  late final AnimationController _orbitController;
  late final AnimationController _flashController;

  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _holdController = AnimationController(
      vsync: this,
      duration: _holdDuration,
    );

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_completed) {
        _completed = true;
        HapticFeedback.heavyImpact();
        _flashController.forward(from: 0);
        widget.onConfirmed();
        Future.delayed(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _completed = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _breathController.dispose();
    _holdController.dispose();
    _orbitController.dispose();
    _flashController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) {
    if (!widget.enabled || _completed) return;
    _holdController.forward(from: 0);
    HapticFeedback.lightImpact();
  }

  void _onPointerUp(PointerUpEvent _) {
    if (_completed) return;
    _holdController.stop();
    _holdController.reset();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + 60,
      height: _size + 60,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _breathController,
          _holdController,
          _orbitController,
          _flashController,
        ]),
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // The magical orb — painted entirely with CustomPainter
              CustomPaint(
                size: Size(_size + 60, _size + 60),
                painter: _OrbPainter(
                  breath: _breathController.value,
                  hold: _holdController.value,
                  orbit: _orbitController.value,
                  flash: _flashController.value,
                  completed: _completed,
                ),
              ),

              // Hold progress ring
              if (_holdController.value > 0)
                SizedBox(
                  width: _size + 8,
                  height: _size + 8,
                  child: CircularProgressIndicator(
                    value: _holdController.value,
                    strokeWidth: 2.5,
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.85),
                    backgroundColor: Colors.white10,
                  ),
                ),

              // Completion text
              if (_completed)
                Positioned(
                  bottom: 2,
                  child: Text(
                    'SIGNAL VERIFIED',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFFFFB85C),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                ),

              // Touch target
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerUp: _onPointerUp,
                onPointerCancel: (_) =>
                    _onPointerUp(const PointerUpEvent()),
                child: SizedBox(width: _size, height: _size),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.breath,
    required this.hold,
    required this.orbit,
    required this.flash,
    required this.completed,
  });

  final double breath;
  final double hold;
  final double orbit;
  final double flash;
  final bool completed;

  static const _cyanLight = Color(0xFF00E5FF);
  static const _deepBlue = Color(0xFF0077BE);
  static const _paleCore = Color(0xFFCDFCFF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final orbRadius = size.width / 2 - 30;
    final breathScale = 0.93 + breath * 0.07;
    final holdBoost = hold;

    // ── 1. Light rays emanating outward ──
    _drawLightRays(canvas, center, orbRadius, breathScale);

    // ── 2. Wide ambient halo ──
    final haloAlpha = 0.06 + holdBoost * 0.25;
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          _deepBlue.withValues(alpha: haloAlpha),
          _cyanLight.withValues(alpha: haloAlpha * 0.4),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(
          Rect.fromCircle(center: center, radius: orbRadius * 1.9));
    canvas.drawCircle(
        center, orbRadius * 1.9 * breathScale, haloPaint);

    // ── 3. Inner glow ring ──
    final ringAlpha = 0.10 + holdBoost * 0.35;
    final ringPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          _cyanLight.withValues(alpha: ringAlpha),
          _deepBlue.withValues(alpha: ringAlpha * 0.5),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(
          Rect.fromCircle(center: center, radius: orbRadius * 1.3));
    canvas.drawCircle(
        center, orbRadius * 1.3 * breathScale, ringPaint);

    // ── 4. Main orb body ──
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(
              const Color(0xFF010812), const Color(0xFF0A2050), hold)!,
          Color.lerp(
              const Color(0xFF061430), const Color(0xFF1060B0), hold)!,
          Color.lerp(
              const Color(0xFF0070B0), const Color(0xFF00D4FF), hold)!,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(
          Rect.fromCircle(center: center, radius: orbRadius));
    canvas.drawCircle(center, orbRadius * breathScale, bodyPaint);

    // ── 5. Luminous core (grows dramatically on hold) ──
    final coreRadius =
        orbRadius * (0.22 + breath * 0.06 + hold * 0.42);
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(Colors.white, _paleCore, hold)!
              .withValues(alpha: 0.95),
          Color.lerp(const Color(0xFF90E4FF), const Color(0xFFC0F4FF), hold)!
              .withValues(alpha: 0.6 + hold * 0.3),
          _cyanLight.withValues(alpha: 0.15 + hold * 0.25),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.65, 1.0],
      ).createShader(
          Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, corePaint);

    // ── 6. Orbiting energy wisps ──
    _drawWisps(canvas, center, orbRadius, breathScale);

    // ── 7. Floating particles (small bright dots) ──
    _drawParticles(canvas, center, orbRadius, breathScale);

    // ── 8. Specular highlight ──
    final specOff = center + Offset(-orbRadius * 0.22, -orbRadius * 0.28);
    final specPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.18 + hold * 0.12),
          Colors.transparent,
        ],
      ).createShader(
          Rect.fromCircle(center: specOff, radius: orbRadius * 0.35));
    canvas.drawCircle(specOff, orbRadius * 0.35, specPaint);

    // ── 9. Edge rim light ──
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + hold * 1.5
      ..shader = SweepGradient(
        colors: [
          _cyanLight.withValues(alpha: 0.0),
          _cyanLight.withValues(alpha: 0.15 + hold * 0.35),
          _deepBlue.withValues(alpha: 0.08 + hold * 0.2),
          _cyanLight.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
        transform: GradientRotation(orbit * 2 * pi),
      ).createShader(
          Rect.fromCircle(center: center, radius: orbRadius * breathScale));
    canvas.drawCircle(
        center, orbRadius * breathScale, rimPaint);

    // ── 10. Flash on completion ──
    if (flash > 0) {
      final flashPaint = Paint()
        ..color = Colors.white.withValues(alpha: (1 - flash) * 0.8);
      canvas.drawCircle(center, orbRadius * 2.0, flashPaint);
    }
  }

  void _drawLightRays(
      Canvas canvas, Offset center, double orbRadius, double breathScale) {
    const rayCount = 12;
    final rayLength = orbRadius * (0.6 + hold * 1.2) * breathScale;
    final baseAlpha = 0.03 + hold * 0.12;
    final rng = Random(77);

    for (int i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * 2 * pi + orbit * 2 * pi * 0.3;
      final spread = 0.04 + rng.nextDouble() * 0.03;
      final alpha = (baseAlpha + rng.nextDouble() * 0.02).clamp(0.0, 1.0);
      final rayEnd = orbRadius * 0.85 + rayLength;

      final path = Path();
      final p1 = center +
          Offset(cos(angle - spread) * orbRadius * 0.7,
              sin(angle - spread) * orbRadius * 0.7);
      final p2 = center +
          Offset(cos(angle + spread) * orbRadius * 0.7,
              sin(angle + spread) * orbRadius * 0.7);
      final tip = center +
          Offset(cos(angle) * rayEnd, sin(angle) * rayEnd);
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(tip.dx, tip.dy);
      path.lineTo(p2.dx, p2.dy);
      path.close();

      final rayPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          colors: [
            _cyanLight.withValues(alpha: alpha),
            _cyanLight.withValues(alpha: alpha * 0.3),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: rayEnd));
      canvas.drawPath(path, rayPaint);
    }
  }

  void _drawWisps(
      Canvas canvas, Offset center, double orbRadius, double breathScale) {
    final rng = Random(42);
    const wispCount = 10;

    for (int i = 0; i < wispCount; i++) {
      final baseAngle = (i / wispCount) * 2 * pi;
      final angle = baseAngle + orbit * 2 * pi + rng.nextDouble() * 0.4;
      final dist =
          orbRadius * (0.5 + rng.nextDouble() * 0.4) * breathScale;
      final wc =
          center + Offset(cos(angle) * dist, sin(angle) * dist);
      final wr =
          orbRadius * (0.07 + rng.nextDouble() * 0.09 + hold * 0.08);
      final alpha =
          (0.2 + rng.nextDouble() * 0.25 + hold * 0.4).clamp(0.0, 1.0);

      final wPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            _cyanLight.withValues(alpha: alpha),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: wc, radius: wr));
      canvas.drawCircle(wc, wr, wPaint);
    }
  }

  void _drawParticles(
      Canvas canvas, Offset center, double orbRadius, double breathScale) {
    final rng = Random(123);
    final particleCount = 16 + (hold * 12).toInt();

    for (int i = 0; i < particleCount; i++) {
      final angle = rng.nextDouble() * 2 * pi + orbit * pi * 0.5;
      final dist =
          orbRadius * (0.3 + rng.nextDouble() * 0.75) * breathScale;
      final pc =
          center + Offset(cos(angle) * dist, sin(angle) * dist);
      final pr = 1.0 + rng.nextDouble() * 1.5 + hold * 1.0;
      final alpha =
          (0.2 + rng.nextDouble() * 0.4 + hold * 0.3).clamp(0.0, 1.0);

      canvas.drawCircle(
        pc,
        pr,
        Paint()..color = _paleCore.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) {
    return oldDelegate.breath != breath ||
        oldDelegate.hold != hold ||
        oldDelegate.orbit != orbit ||
        oldDelegate.flash != flash ||
        oldDelegate.completed != completed;
  }
}
