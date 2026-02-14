import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_theme.dart';

class SoulFireButton extends StatefulWidget {
  const SoulFireButton({
    super.key,
    required this.enabled,
    required this.onConfirmed,
    this.styleId = SoulFireStyleId.etherealOrb,
  });

  final bool enabled;
  final VoidCallback onConfirmed;
  final SoulFireStyleId styleId;

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
  Offset? _pointerStart;
  Timer? _holdDelayTimer;

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
    _holdDelayTimer?.cancel();
    _breathController.dispose();
    _holdController.dispose();
    _orbitController.dispose();
    _flashController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || _completed) return;
    _pointerStart = event.position;
    _holdDelayTimer?.cancel();
    _holdDelayTimer = Timer(const Duration(milliseconds: 120), () {
      if (_pointerStart != null && !_completed) {
        _holdController.forward(from: 0);
        HapticFeedback.lightImpact();
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerStart == null || _completed) return;
    final distance = (event.position - _pointerStart!).distance;
    if (distance > 10) {
      _cancelHold();
    }
  }

  void _onPointerUp(PointerUpEvent _) {
    _cancelHold();
  }

  void _cancelHold() {
    _holdDelayTimer?.cancel();
    _holdDelayTimer = null;
    _pointerStart = null;
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
                  primaryColor: widget.styleId.primaryColor,
                  secondaryColor: widget.styleId.secondaryColor,
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
                    color: widget.styleId.primaryColor.withValues(alpha: 0.85),
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
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: (_) => _cancelHold(),
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
    required this.primaryColor,
    required this.secondaryColor,
  });

  final double breath;
  final double hold;
  final double orbit;
  final double flash;
  final bool completed;
  final Color primaryColor;
  final Color secondaryColor;

  // Derived cool palette from style
  Color get _cyan => primaryColor;
  Color get _deepBlue => HSLColor.fromColor(primaryColor).withLightness(0.25).toColor();
  Color get _paleBlue => Color.lerp(primaryColor, Colors.white, 0.75)!;
  // Warm palette (hold → confirm)
  static const _amber = Color(0xFFFFB85C);
  static const _gold = Color(0xFFFFD700);
  static const _warmWhite = Color(0xFFFFF8E7);

  Color _lerpHold(Color cool, Color warm) =>
      Color.lerp(cool, warm, Curves.easeIn.transform(hold))!;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final orbRadius = size.width / 2 - 30;
    final breathScale = 0.94 + breath * 0.06;

    // ── 1. Outer light rays ──
    _drawLightRays(canvas, center, orbRadius, breathScale);

    // ── 2. Wide ethereal halo (shifts warm on hold) ──
    final haloAlpha = 0.05 + hold * 0.20;
    final haloColor = _lerpHold(_deepBlue, _amber);
    canvas.drawCircle(
      center,
      orbRadius * 2.0 * breathScale,
      Paint()
        ..shader = RadialGradient(
          colors: [
            haloColor.withValues(alpha: haloAlpha),
            _lerpHold(_cyan, _gold).withValues(alpha: haloAlpha * 0.3),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: orbRadius * 2.0)),
    );

    // ── 3. Inner glow ring ──
    final ringAlpha = 0.08 + hold * 0.30;
    final ringColor = _lerpHold(_cyan, _gold);
    canvas.drawCircle(
      center,
      orbRadius * 1.35 * breathScale,
      Paint()
        ..shader = RadialGradient(
          colors: [
            ringColor.withValues(alpha: ringAlpha),
            _lerpHold(_deepBlue, _amber).withValues(alpha: ringAlpha * 0.4),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: orbRadius * 1.35)),
    );

    // ── 4. Main orb body (deep nebula → blazing core) ──
    canvas.drawCircle(
      center,
      orbRadius * breathScale,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _lerpHold(const Color(0xFF010A14), const Color(0xFF1A0800)),
            _lerpHold(const Color(0xFF062040), const Color(0xFF4A2000)),
            _lerpHold(const Color(0xFF0080C0), const Color(0xFFDD8800)),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: orbRadius)),
    );

    // ── 5. Nebula texture layer (subtle swirl) ──
    _drawNebulaSwirls(canvas, center, orbRadius, breathScale);

    // ── 6. Luminous core (grows + shifts color on hold) ──
    final coreR = orbRadius * (0.20 + breath * 0.05 + hold * 0.40);
    canvas.drawCircle(
      center,
      coreR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _lerpHold(Colors.white, _warmWhite).withValues(alpha: 0.95),
            _lerpHold(const Color(0xFF90E4FF), const Color(0xFFFFD080))
                .withValues(alpha: 0.65 + hold * 0.25),
            _lerpHold(_cyan, _amber).withValues(alpha: 0.12 + hold * 0.20),
            Colors.transparent,
          ],
          stops: const [0.0, 0.22, 0.60, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // ── 7. Orbiting energy wisps ──
    _drawWisps(canvas, center, orbRadius, breathScale);

    // ── 8. Floating particles with glow ──
    _drawParticles(canvas, center, orbRadius, breathScale);

    // ── 9. Specular highlight (top-left) ──
    final specOff = center + Offset(-orbRadius * 0.20, -orbRadius * 0.26);
    canvas.drawCircle(
      specOff,
      orbRadius * 0.30,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.20 + hold * 0.10),
            Colors.transparent,
          ],
        ).createShader(
            Rect.fromCircle(center: specOff, radius: orbRadius * 0.30)),
    );

    // ── 10. Edge rim light (rotating sweep) ──
    final rimColor = _lerpHold(_cyan, _gold);
    canvas.drawCircle(
      center,
      orbRadius * breathScale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 + hold * 2.0
        ..shader = SweepGradient(
          colors: [
            rimColor.withValues(alpha: 0.0),
            rimColor.withValues(alpha: 0.18 + hold * 0.40),
            _lerpHold(_deepBlue, _amber).withValues(alpha: 0.06 + hold * 0.18),
            rimColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.25, 0.65, 1.0],
          transform: GradientRotation(orbit * 2 * pi),
        ).createShader(
            Rect.fromCircle(center: center, radius: orbRadius * breathScale)),
    );

    // ── 11. Second counter-rotating rim (subtler) ──
    canvas.drawCircle(
      center,
      orbRadius * breathScale * 0.98,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 + hold * 1.0
        ..shader = SweepGradient(
          colors: [
            _lerpHold(_paleBlue, _warmWhite).withValues(alpha: 0.0),
            _lerpHold(_paleBlue, _warmWhite).withValues(alpha: 0.08 + hold * 0.15),
            _lerpHold(_paleBlue, _warmWhite).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
          transform: GradientRotation(-orbit * 2 * pi * 0.7),
        ).createShader(
            Rect.fromCircle(center: center, radius: orbRadius * breathScale)),
    );

    // ── 12. Flash on completion ──
    if (flash > 0) {
      final flashAlpha = (1 - flash) * 0.85;
      canvas.drawCircle(
        center,
        orbRadius * (1.5 + flash * 0.8),
        Paint()
          ..shader = RadialGradient(
            colors: [
              _warmWhite.withValues(alpha: flashAlpha),
              _gold.withValues(alpha: flashAlpha * 0.5),
              Colors.transparent,
            ],
            stops: const [0.0, 0.4, 1.0],
          ).createShader(Rect.fromCircle(
              center: center, radius: orbRadius * (1.5 + flash * 0.8))),
      );
    }
  }

  void _drawLightRays(
      Canvas canvas, Offset center, double orbRadius, double breathScale) {
    const rayCount = 16;
    final rayLength = orbRadius * (0.5 + hold * 1.4) * breathScale;
    final baseAlpha = 0.025 + hold * 0.10;
    final rng = Random(77);
    final rayColor = _lerpHold(_cyan, _gold);

    for (int i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * 2 * pi + orbit * 2 * pi * 0.25;
      final spread = 0.03 + rng.nextDouble() * 0.025;
      final alpha = (baseAlpha + rng.nextDouble() * 0.015).clamp(0.0, 1.0);
      final rayEnd = orbRadius * 0.85 + rayLength;

      final path = Path();
      final p1 = center +
          Offset(cos(angle - spread) * orbRadius * 0.75,
              sin(angle - spread) * orbRadius * 0.75);
      final p2 = center +
          Offset(cos(angle + spread) * orbRadius * 0.75,
              sin(angle + spread) * orbRadius * 0.75);
      final tip = center +
          Offset(cos(angle) * rayEnd, sin(angle) * rayEnd);
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(tip.dx, tip.dy);
      path.lineTo(p2.dx, p2.dy);
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              rayColor.withValues(alpha: alpha),
              rayColor.withValues(alpha: alpha * 0.2),
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(
              Rect.fromCircle(center: center, radius: rayEnd)),
      );
    }
  }

  void _drawNebulaSwirls(
      Canvas canvas, Offset center, double orbRadius, double breathScale) {
    final rng = Random(99);
    const count = 6;
    final swirlColor = _lerpHold(
        const Color(0xFF1090DD), const Color(0xFFCC7700));

    for (int i = 0; i < count; i++) {
      final baseAngle = (i / count) * 2 * pi;
      final angle = baseAngle + orbit * 2 * pi * 0.15 + rng.nextDouble() * 0.5;
      final dist = orbRadius * (0.25 + rng.nextDouble() * 0.45) * breathScale;
      final sc = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final sr = orbRadius * (0.15 + rng.nextDouble() * 0.20);
      final alpha = (0.04 + rng.nextDouble() * 0.04 + hold * 0.06).clamp(0.0, 1.0);

      canvas.drawOval(
        Rect.fromCenter(
            center: sc, width: sr * 2.2, height: sr * 1.2),
        Paint()
          ..shader = RadialGradient(
            colors: [
              swirlColor.withValues(alpha: alpha),
              Colors.transparent,
            ],
          ).createShader(
              Rect.fromCircle(center: sc, radius: sr * 1.2)),
      );
    }
  }

  void _drawWisps(
      Canvas canvas, Offset center, double orbRadius, double breathScale) {
    final rng = Random(42);
    const wispCount = 12;
    final wispColor = _lerpHold(_cyan, _gold);

    for (int i = 0; i < wispCount; i++) {
      final baseAngle = (i / wispCount) * 2 * pi;
      final angle = baseAngle + orbit * 2 * pi + rng.nextDouble() * 0.4;
      final dist =
          orbRadius * (0.45 + rng.nextDouble() * 0.45) * breathScale;
      final wc = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final wr = orbRadius * (0.06 + rng.nextDouble() * 0.10 + hold * 0.08);
      final alpha =
          (0.15 + rng.nextDouble() * 0.20 + hold * 0.35).clamp(0.0, 1.0);

      canvas.drawCircle(
        wc,
        wr,
        Paint()
          ..shader = RadialGradient(
            colors: [
              wispColor.withValues(alpha: alpha),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: wc, radius: wr)),
      );
    }
  }

  void _drawParticles(
      Canvas canvas, Offset center, double orbRadius, double breathScale) {
    final rng = Random(123);
    final particleCount = 20 + (hold * 16).toInt();
    final pColor = _lerpHold(_paleBlue, _warmWhite);

    for (int i = 0; i < particleCount; i++) {
      final angle = rng.nextDouble() * 2 * pi + orbit * pi * 0.6;
      final dist =
          orbRadius * (0.25 + rng.nextDouble() * 0.80) * breathScale;
      final pc = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final pr = 0.8 + rng.nextDouble() * 1.8 + hold * 1.2;
      final alpha =
          (0.15 + rng.nextDouble() * 0.35 + hold * 0.35).clamp(0.0, 1.0);

      // Soft glow around each particle
      canvas.drawCircle(
        pc,
        pr * 2.5,
        Paint()..color = pColor.withValues(alpha: alpha * 0.15),
      );
      canvas.drawCircle(
        pc,
        pr,
        Paint()..color = pColor.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) {
    return oldDelegate.breath != breath ||
        oldDelegate.hold != hold ||
        oldDelegate.orbit != orbit ||
        oldDelegate.flash != flash ||
        oldDelegate.completed != completed ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
