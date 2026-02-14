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
                  styleId: widget.styleId,
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

              // Touch target — translucent so taps outside orb pass through
              ClipOval(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: (_) => _cancelHold(),
                  child: SizedBox(width: _size, height: _size),
                ),
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
    required this.styleId,
  });

  final double breath;
  final double hold;
  final double orbit;
  final double flash;
  final bool completed;
  final SoulFireStyleId styleId;

  // Warm palette for hold → confirm (shared across all styles)
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

    switch (styleId) {
      case SoulFireStyleId.etherealOrb:
        _paintEtherealOrb(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.voidPortal:
        _paintVoidPortal(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.plasmaBurst:
        _paintPlasmaBurst(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.plasmaCell:
        _paintPlasmaCell(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.toxicCore:
        _paintToxicCore(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.crystalAscend:
        _paintCrystalAscend(canvas, center, orbRadius, breathScale);
    }

    // Shared: flash on completion
    if (flash > 0) {
      final fc = styleId.primaryColor;
      final flashAlpha = (1 - flash) * 0.85;
      canvas.drawCircle(
        center,
        orbRadius * (1.5 + flash * 0.8),
        Paint()
          ..shader = RadialGradient(
            colors: [
              _warmWhite.withValues(alpha: flashAlpha),
              fc.withValues(alpha: flashAlpha * 0.5),
              Colors.transparent,
            ],
            stops: const [0.0, 0.4, 1.0],
          ).createShader(Rect.fromCircle(
              center: center, radius: orbRadius * (1.5 + flash * 0.8))),
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  // 1. ETHEREAL ORB (Free) — glowing purple/cyan energy sphere
  //    Bright white core, particle ring, pink/purple outer glow
  // ═══════════════════════════════════════════════════════
  void _paintEtherealOrb(
      Canvas canvas, Offset center, double r, double bs) {
    const cyan = Color(0xFF00E5FF);
    const purple = Color(0xFFAA00FF);
    const pink = Color(0xFFFF44CC);
    final deepBlue = HSLColor.fromColor(cyan).withLightness(0.25).toColor();

    // Outer pink/purple glow halo
    canvas.drawCircle(
      center, r * 1.8 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(purple, _amber).withValues(alpha: 0.08 + hold * 0.15),
          _lerpHold(pink, _gold).withValues(alpha: 0.04 + hold * 0.06),
          Colors.transparent,
        ], stops: const [0.0, 0.45, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 1.8)),
    );

    // Mid glow ring
    canvas.drawCircle(
      center, r * 1.3 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(cyan, _gold).withValues(alpha: 0.10 + hold * 0.25),
          _lerpHold(deepBlue, _amber).withValues(alpha: 0.04),
          Colors.transparent,
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 1.3)),
    );

    // Main orb body — deep dark → bright edge
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(const Color(0xFF010A14), const Color(0xFF1A0800)),
          _lerpHold(const Color(0xFF062040), const Color(0xFF4A2000)),
          _lerpHold(const Color(0xFF0080C0), const Color(0xFFDD8800)),
        ], stops: const [0.0, 0.55, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // Luminous core
    final coreR = r * (0.22 + breath * 0.06 + hold * 0.35);
    canvas.drawCircle(
      center, coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(Colors.white, _warmWhite).withValues(alpha: 0.95),
          _lerpHold(const Color(0xFF90E4FF), const Color(0xFFFFD080))
              .withValues(alpha: 0.65 + hold * 0.25),
          _lerpHold(cyan, _amber).withValues(alpha: 0.12),
          Colors.transparent,
        ], stops: const [0.0, 0.25, 0.6, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // Particle ring orbiting around the sphere
    _drawParticleRing(canvas, center, r, bs, cyan, purple);

    // Orbiting wisps
    _drawOrbitalWisps(canvas, center, r, bs, _lerpHold(cyan, _gold), 12);

    // Specular
    _drawSpecular(canvas, center, r);

    // Rim light
    _drawRimLight(canvas, center, r, bs, _lerpHold(cyan, _gold));
  }

  // ═══════════════════════════════════════════════════════
  // 2. VOID PORTAL (Pro) — dark hollow center, swirling smoke
  //    No bright core — it's a vortex. Smoke trails spiral outward.
  // ═══════════════════════════════════════════════════════
  void _paintVoidPortal(
      Canvas canvas, Offset center, double r, double bs) {
    const purple = Color(0xFF7B68EE);
    const cyan = Color(0xFF00E5FF);
    const deepPurple = Color(0xFF1A0A30);

    // Outer ethereal glow
    canvas.drawCircle(
      center, r * 2.0 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(purple, _amber).withValues(alpha: 0.06 + hold * 0.12),
          _lerpHold(cyan, _gold).withValues(alpha: 0.02),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 2.0)),
    );

    // Main orb body — dark void
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFF000008), // Near-black center (void)
          _lerpHold(deepPurple, const Color(0xFF1A0800)),
          _lerpHold(const Color(0xFF3020A0), const Color(0xFF885500)),
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // Swirling smoke trails (large wispy arcs)
    final rng = Random(55);
    for (int i = 0; i < 8; i++) {
      final baseA = (i / 8) * 2 * pi;
      final angle = baseA + orbit * 2 * pi * 0.4 + rng.nextDouble() * 0.6;
      final dist = r * (0.35 + rng.nextDouble() * 0.55) * bs;
      final sc = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final sw = r * (0.18 + rng.nextDouble() * 0.22 + hold * 0.10);
      final sh = r * (0.06 + rng.nextDouble() * 0.08);
      final alpha = (0.08 + rng.nextDouble() * 0.12 + hold * 0.15).clamp(0.0, 1.0);
      final smokeColor = _lerpHold(
          i.isEven ? cyan : purple, i.isEven ? _gold : _amber);

      canvas.save();
      canvas.translate(sc.dx, sc.dy);
      canvas.rotate(angle);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: sw * 2, height: sh * 2),
        Paint()
          ..shader = RadialGradient(colors: [
            smokeColor.withValues(alpha: alpha),
            smokeColor.withValues(alpha: alpha * 0.3),
            Colors.transparent,
          ], stops: const [0.0, 0.5, 1.0])
              .createShader(Rect.fromCenter(
                  center: Offset.zero, width: sw * 2, height: sh * 2)),
      );
      canvas.restore();
    }

    // Small void core — dark ring with slight glow
    final voidR = r * (0.15 + hold * 0.10);
    canvas.drawCircle(
      center, voidR,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFF000000),
          _lerpHold(purple, _amber).withValues(alpha: 0.2 + hold * 0.3),
          Colors.transparent,
        ], stops: const [0.0, 0.7, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: voidR)),
    );

    // Rim — swirling sweep gradient
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + hold * 3.0
        ..shader = SweepGradient(
          colors: [
            _lerpHold(cyan, _gold).withValues(alpha: 0.0),
            _lerpHold(purple, _amber).withValues(alpha: 0.30 + hold * 0.35),
            _lerpHold(cyan, _gold).withValues(alpha: 0.15 + hold * 0.20),
            _lerpHold(purple, _amber).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.3, 0.6, 1.0],
          transform: GradientRotation(orbit * 2 * pi),
        ).createShader(Rect.fromCircle(center: center, radius: r * bs)),
    );

    // Floating particles
    _drawScatteredParticles(canvas, center, r, bs, _lerpHold(cyan, _gold), 16);
  }

  // ═══════════════════════════════════════════════════════
  // 3. PLASMA BURST (Pro) — intense cyan electric plasma
  //    Bright white center, jagged electric tendrils radiating out
  // ═══════════════════════════════════════════════════════
  void _paintPlasmaBurst(
      Canvas canvas, Offset center, double r, double bs) {
    const cyan = Color(0xFF00BFFF);
    const iceWhite = Color(0xFFCDFCFF);
    const deepCyan = Color(0xFF003060);

    // Outer electric glow
    canvas.drawCircle(
      center, r * 2.2 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(cyan, _amber).withValues(alpha: 0.08 + hold * 0.18),
          _lerpHold(deepCyan, _gold).withValues(alpha: 0.03),
          Colors.transparent,
        ], stops: const [0.0, 0.35, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 2.2)),
    );

    // Main orb — bright plasma body
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(iceWhite, _warmWhite).withValues(alpha: 0.85),
          _lerpHold(cyan, const Color(0xFFFFAA44)).withValues(alpha: 0.70),
          _lerpHold(deepCyan, const Color(0xFF4A2800)).withValues(alpha: 0.40),
          _lerpHold(const Color(0xFF001020), const Color(0xFF1A0800)),
        ], stops: const [0.0, 0.25, 0.6, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // Electric tendrils — jagged rays
    final rng = Random(31);
    const tendrilCount = 20;
    for (int i = 0; i < tendrilCount; i++) {
      final baseAngle = (i / tendrilCount) * 2 * pi;
      final angle = baseAngle + orbit * 2 * pi * 0.3 + rng.nextDouble() * 0.3;
      final tendrilLen = r * (0.6 + rng.nextDouble() * 0.8 + hold * 0.5) * bs;
      final alpha = (0.06 + rng.nextDouble() * 0.10 + hold * 0.15).clamp(0.0, 1.0);

      // Jagged path: start from orb edge, zigzag outward
      final path = Path();
      final start = center + Offset(cos(angle) * r * 0.7, sin(angle) * r * 0.7);
      path.moveTo(start.dx, start.dy);

      var current = start;
      const segments = 5;
      for (int j = 1; j <= segments; j++) {
        final t = j / segments;
        final jitter = (rng.nextDouble() - 0.5) * r * 0.15;
        final dx = cos(angle) * tendrilLen * t + cos(angle + pi / 2) * jitter;
        final dy = sin(angle) * tendrilLen * t + sin(angle + pi / 2) * jitter;
        current = start + Offset(dx, dy);
        path.lineTo(current.dx, current.dy);
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 + rng.nextDouble() * 1.5 + hold * 1.0
          ..color = _lerpHold(cyan, _gold).withValues(alpha: alpha)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Bright white core
    final coreR = r * (0.30 + breath * 0.05 + hold * 0.25);
    canvas.drawCircle(
      center, coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.95),
          _lerpHold(iceWhite, _warmWhite).withValues(alpha: 0.6),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // Scattered particles
    _drawScatteredParticles(canvas, center, r, bs, _lerpHold(iceWhite, _warmWhite), 24);
  }

  // ═══════════════════════════════════════════════════════
  // 4. PLASMA CELL (Pro) — solid blue sphere with cell membrane
  //    Voronoi-like web texture on surface, wispy blue edges
  // ═══════════════════════════════════════════════════════
  void _paintPlasmaCell(
      Canvas canvas, Offset center, double r, double bs) {
    const blue = Color(0xFF1E90FF);
    const deepBlue = Color(0xFF0044AA);
    const cyan = Color(0xFF40C0FF);

    // Outer wispy glow
    canvas.drawCircle(
      center, r * 1.6 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(blue, _amber).withValues(alpha: 0.10 + hold * 0.18),
          _lerpHold(deepBlue, _gold).withValues(alpha: 0.04),
          Colors.transparent,
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 1.6)),
    );

    // Main body — solid bright blue sphere
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(cyan, const Color(0xFFFFCC88)).withValues(alpha: 0.80),
          _lerpHold(blue, const Color(0xFFDD8800)).withValues(alpha: 0.90),
          _lerpHold(deepBlue, const Color(0xFF664400)),
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // Cell membrane web texture — network of lines on surface
    final rng = Random(77);
    const cellCount = 18;
    final cellPoints = <Offset>[];
    for (int i = 0; i < cellCount; i++) {
      final a = rng.nextDouble() * 2 * pi + orbit * pi * 0.2;
      final d = rng.nextDouble() * r * 0.85 * bs;
      cellPoints.add(center + Offset(cos(a) * d, sin(a) * d));
    }

    // Draw connections between nearby cell points
    final lineAlpha = (0.10 + hold * 0.20 + breath * 0.05).clamp(0.0, 1.0);
    final lineColor = _lerpHold(cyan, _gold);
    for (int i = 0; i < cellPoints.length; i++) {
      for (int j = i + 1; j < cellPoints.length; j++) {
        final dist = (cellPoints[i] - cellPoints[j]).distance;
        if (dist < r * 0.55) {
          canvas.drawLine(
            cellPoints[i], cellPoints[j],
            Paint()
              ..color = lineColor.withValues(alpha: lineAlpha * (1 - dist / (r * 0.55)))
              ..strokeWidth = 0.6 + hold * 0.8,
          );
        }
      }
    }

    // Glow nodes at cell points
    for (final pt in cellPoints) {
      final distFromCenter = (pt - center).distance;
      if (distFromCenter < r * bs) {
        canvas.drawCircle(
          pt, 2.0 + hold * 2.0,
          Paint()..color = lineColor.withValues(alpha: lineAlpha * 0.8),
        );
        canvas.drawCircle(
          pt, 5.0 + hold * 3.0,
          Paint()..color = lineColor.withValues(alpha: lineAlpha * 0.2),
        );
      }
    }

    // Wispy edge flames
    for (int i = 0; i < 10; i++) {
      final a = (i / 10) * 2 * pi + orbit * 2 * pi * 0.15;
      final edgePt = center + Offset(cos(a) * r * bs, sin(a) * r * bs);
      final wispLen = r * (0.15 + rng.nextDouble() * 0.20 + hold * 0.10);
      final wispEnd = edgePt + Offset(cos(a) * wispLen, sin(a) * wispLen);
      final alpha = (0.06 + rng.nextDouble() * 0.08 + hold * 0.10).clamp(0.0, 1.0);
      canvas.drawLine(
        edgePt, wispEnd,
        Paint()
          ..color = _lerpHold(blue, _amber).withValues(alpha: alpha)
          ..strokeWidth = 2.0 + hold * 2.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // Specular + rim
    _drawSpecular(canvas, center, r);
    _drawRimLight(canvas, center, r, bs, _lerpHold(cyan, _gold));
  }

  // ═══════════════════════════════════════════════════════
  // 5. TOXIC CORE (Lifetime) — green molten energy sphere
  //    Dark cracks/veins on surface, liquid metal look, strong glow
  // ═══════════════════════════════════════════════════════
  void _paintToxicCore(
      Canvas canvas, Offset center, double r, double bs) {
    const neonGreen = Color(0xFF39FF14);
    const springGreen = Color(0xFF00FF7F);
    const darkGreen = Color(0xFF003300);

    // Intense green outer glow
    canvas.drawCircle(
      center, r * 2.0 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(neonGreen, _amber).withValues(alpha: 0.12 + hold * 0.20),
          _lerpHold(darkGreen, _gold).withValues(alpha: 0.04),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 2.0)),
    );

    // Main body — molten green sphere
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(neonGreen, _warmWhite).withValues(alpha: 0.85),
          _lerpHold(springGreen, const Color(0xFFDD8800)).withValues(alpha: 0.75),
          _lerpHold(darkGreen, const Color(0xFF4A2800)),
        ], stops: const [0.0, 0.45, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // Dark cracks/veins on surface — organic lightning pattern
    final rng = Random(42);
    const crackCount = 14;
    for (int i = 0; i < crackCount; i++) {
      final startAngle = (i / crackCount) * 2 * pi + orbit * pi * 0.1;
      final startDist = r * (0.15 + rng.nextDouble() * 0.25) * bs;
      final start = center +
          Offset(cos(startAngle) * startDist, sin(startAngle) * startDist);

      final path = Path();
      path.moveTo(start.dx, start.dy);

      var current = start;
      final branchCount = 3 + rng.nextInt(3);
      for (int j = 0; j < branchCount; j++) {
        final jAngle = startAngle + (rng.nextDouble() - 0.5) * 1.2;
        final jDist = r * (0.12 + rng.nextDouble() * 0.20);
        current = current + Offset(cos(jAngle) * jDist, sin(jAngle) * jDist);
        // Keep within orb
        final fromCenter = (current - center).distance;
        if (fromCenter > r * 0.9 * bs) break;
        path.lineTo(current.dx, current.dy);
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 + hold * 1.5
          ..color = const Color(0xFF001A00).withValues(alpha: 0.5 + hold * 0.3)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Bright veins — glowing cracks
    for (int i = 0; i < 8; i++) {
      final a = (i / 8) * 2 * pi + orbit * 2 * pi * 0.08;
      final d = r * (0.2 + rng.nextDouble() * 0.50) * bs;
      final pt = center + Offset(cos(a) * d, sin(a) * d);
      final glowR = r * (0.04 + rng.nextDouble() * 0.06);
      canvas.drawCircle(
        pt, glowR,
        Paint()
          ..color = _lerpHold(neonGreen, _gold)
              .withValues(alpha: 0.4 + hold * 0.3 + breath * 0.1),
      );
    }

    // Hot core
    final coreR = r * (0.18 + breath * 0.04 + hold * 0.20);
    canvas.drawCircle(
      center, coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(Colors.white, _warmWhite).withValues(alpha: 0.7),
          _lerpHold(neonGreen, _gold).withValues(alpha: 0.4),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // Thick glowing rim
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 + hold * 3.0
        ..shader = SweepGradient(
          colors: [
            _lerpHold(neonGreen, _gold).withValues(alpha: 0.3 + hold * 0.4),
            _lerpHold(springGreen, _amber).withValues(alpha: 0.1),
            _lerpHold(neonGreen, _gold).withValues(alpha: 0.3 + hold * 0.4),
          ],
          stops: const [0.0, 0.5, 1.0],
          transform: GradientRotation(orbit * 2 * pi * 0.5),
        ).createShader(Rect.fromCircle(center: center, radius: r * bs)),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 6. CRYSTAL ASCEND (Lifetime) — crystal blue orb with
  //    ascending particles/wisps rising upward like a spirit
  // ═══════════════════════════════════════════════════════
  void _paintCrystalAscend(
      Canvas canvas, Offset center, double r, double bs) {
    const skyBlue = Color(0xFF87CEEB);
    const iceWhite = Color(0xFFE0F0FF);
    const deepBlue = Color(0xFF102040);

    // Soft wide glow
    canvas.drawCircle(
      center, r * 1.8 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(skyBlue, _amber).withValues(alpha: 0.08 + hold * 0.15),
          _lerpHold(deepBlue, _gold).withValues(alpha: 0.03),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 1.8)),
    );

    // Main crystal orb — translucent glassy sphere
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(iceWhite, _warmWhite).withValues(alpha: 0.60),
          _lerpHold(skyBlue, const Color(0xFFFFCC88)).withValues(alpha: 0.50),
          _lerpHold(deepBlue, const Color(0xFF4A2800)).withValues(alpha: 0.60),
          _lerpHold(const Color(0xFF050A14), const Color(0xFF0A0500)),
        ], stops: const [0.0, 0.3, 0.7, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // Inner crystal facets — diamond-like refractions
    final rng = Random(88);
    for (int i = 0; i < 6; i++) {
      final a = (i / 6) * 2 * pi + breath * 0.3;
      final d = r * (0.20 + rng.nextDouble() * 0.30) * bs;
      final pt = center + Offset(cos(a) * d, sin(a) * d);
      final facetR = r * (0.08 + rng.nextDouble() * 0.10);
      canvas.drawCircle(
        pt, facetR,
        Paint()
          ..shader = RadialGradient(colors: [
            _lerpHold(iceWhite, _warmWhite).withValues(alpha: 0.25 + hold * 0.15),
            Colors.transparent,
          ]).createShader(Rect.fromCircle(center: pt, radius: facetR)),
      );
    }

    // Core glow
    final coreR = r * (0.20 + breath * 0.05 + hold * 0.25);
    canvas.drawCircle(
      center, coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.80),
          _lerpHold(skyBlue, _gold).withValues(alpha: 0.40),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // ASCENDING PARTICLES — the signature effect
    // Particles rise from below the orb upward, like a spirit ascending
    for (int i = 0; i < 28; i++) {
      // Each particle has a unique phase based on orbit + seed
      final seed = rng.nextDouble();
      final phase = (orbit * (0.3 + seed * 0.4) + seed) % 1.0;

      // X spread: clustered near center, wider as they rise
      final xSpread = (rng.nextDouble() - 0.5) * r * (0.8 + phase * 0.6);
      // Y: from below orb bottom, ascending upward past top
      final yStart = center.dy + r * 1.2;
      final yEnd = center.dy - r * 2.0;
      final y = yStart + (yEnd - yStart) * phase;

      final pt = Offset(center.dx + xSpread, y);

      // Fade in from bottom, peak in middle, fade out at top
      final fadeIn = (phase * 3).clamp(0.0, 1.0);
      final fadeOut = ((1 - phase) * 2.5).clamp(0.0, 1.0);
      final alpha = (fadeIn * fadeOut * (0.3 + hold * 0.4)).clamp(0.0, 1.0);

      // Size: small at bottom, grow as they rise
      final pr = (1.0 + seed * 2.0 + phase * 2.0 + hold * 1.5);

      // Color shifts from blue to white as particles rise
      final pColor = Color.lerp(
        _lerpHold(skyBlue, _amber),
        _lerpHold(iceWhite, _warmWhite),
        phase,
      )!;

      // Soft glow
      canvas.drawCircle(
        pt, pr * 3,
        Paint()..color = pColor.withValues(alpha: alpha * 0.15),
      );
      canvas.drawCircle(
        pt, pr,
        Paint()..color = pColor.withValues(alpha: alpha),
      );
    }

    // Specular
    _drawSpecular(canvas, center, r);

    // Subtle rim
    _drawRimLight(canvas, center, r, bs, _lerpHold(skyBlue, _gold));
  }

  // ═══════════════════════════════════════════════════════
  // SHARED HELPERS
  // ═══════════════════════════════════════════════════════

  void _drawParticleRing(Canvas canvas, Offset center, double r, double bs,
      Color c1, Color c2) {
    final rng = Random(123);
    final count = 24 + (hold * 12).toInt();
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi + orbit * 2 * pi * 0.6;
      final dist = r * (0.75 + rng.nextDouble() * 0.35) * bs;
      final pt = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final pr = 0.8 + rng.nextDouble() * 1.8 + hold * 1.0;
      final alpha = (0.12 + rng.nextDouble() * 0.30 + hold * 0.30).clamp(0.0, 1.0);
      final c = Color.lerp(c1, c2, rng.nextDouble())!;
      canvas.drawCircle(pt, pr * 2.5,
          Paint()..color = c.withValues(alpha: alpha * 0.15));
      canvas.drawCircle(pt, pr, Paint()..color = c.withValues(alpha: alpha));
    }
  }

  void _drawOrbitalWisps(Canvas canvas, Offset center, double r, double bs,
      Color color, int count) {
    final rng = Random(42);
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi + orbit * 2 * pi + rng.nextDouble() * 0.4;
      final dist = r * (0.45 + rng.nextDouble() * 0.40) * bs;
      final wc = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final wr = r * (0.05 + rng.nextDouble() * 0.08 + hold * 0.06);
      final alpha = (0.12 + rng.nextDouble() * 0.18 + hold * 0.25).clamp(0.0, 1.0);
      canvas.drawCircle(
        wc, wr,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: alpha),
            Colors.transparent,
          ]).createShader(Rect.fromCircle(center: wc, radius: wr)),
      );
    }
  }

  void _drawScatteredParticles(Canvas canvas, Offset center, double r,
      double bs, Color color, int count) {
    final rng = Random(200);
    for (int i = 0; i < count; i++) {
      final angle = rng.nextDouble() * 2 * pi + orbit * pi * 0.5;
      final dist = r * (0.3 + rng.nextDouble() * 0.9) * bs;
      final pt = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final pr = 0.6 + rng.nextDouble() * 1.5 + hold * 0.8;
      final alpha = (0.10 + rng.nextDouble() * 0.25 + hold * 0.25).clamp(0.0, 1.0);
      canvas.drawCircle(pt, pr * 2.5,
          Paint()..color = color.withValues(alpha: alpha * 0.12));
      canvas.drawCircle(pt, pr,
          Paint()..color = color.withValues(alpha: alpha));
    }
  }

  void _drawSpecular(Canvas canvas, Offset center, double r) {
    final specOff = center + Offset(-r * 0.20, -r * 0.26);
    canvas.drawCircle(
      specOff, r * 0.28,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.18 + hold * 0.08),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: specOff, radius: r * 0.28)),
    );
  }

  void _drawRimLight(
      Canvas canvas, Offset center, double r, double bs, Color color) {
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 + hold * 2.0
        ..shader = SweepGradient(
          colors: [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.15 + hold * 0.35),
            color.withValues(alpha: 0.05),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.25, 0.65, 1.0],
          transform: GradientRotation(orbit * 2 * pi),
        ).createShader(Rect.fromCircle(center: center, radius: r * bs)),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) {
    return oldDelegate.breath != breath ||
        oldDelegate.hold != hold ||
        oldDelegate.orbit != orbit ||
        oldDelegate.flash != flash ||
        oldDelegate.completed != completed ||
        oldDelegate.styleId != styleId;
  }
}
