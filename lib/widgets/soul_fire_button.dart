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
  // 1. ETHEREAL ORB (Free) — Mystical violet flame wreath
  //    Curving flame tendrils wrap AROUND the orb surface.
  //    Organic, sinusoidal paths — not straight rays.
  //    Colors: deep violet, magenta, pale lilac core.
  // ═══════════════════════════════════════════════════════
  void _paintEtherealOrb(
      Canvas canvas, Offset center, double r, double bs) {
    const violet = Color(0xFF7B2FBE);
    const magenta = Color(0xFFFF44CC);
    const lilac = Color(0xFFE6D0FF);
    const deepViolet = Color(0xFF1A0030);

    // Soft violet halo
    canvas.drawCircle(
      center, r * 1.7 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(violet, _amber).withValues(alpha: 0.07 + hold * 0.12),
          _lerpHold(magenta, _gold).withValues(alpha: 0.03),
          Colors.transparent,
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 1.7)),
    );

    // Main body — dark violet sphere
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(deepViolet, const Color(0xFF0A0500)),
          _lerpHold(const Color(0xFF2A0050), const Color(0xFF1A0800)),
          _lerpHold(violet, _amber),
        ], stops: const [0.0, 0.55, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // CURVING FLAME TENDRILS — wrap around the orb using sine waves
    final fRng = Random(66);
    for (int i = 0; i < 10; i++) {
      final baseAngle = (i / 10) * 2 * pi + orbit * 2 * pi * 0.12;
      final flameColor = i.isEven
          ? _lerpHold(magenta, _gold)
          : _lerpHold(violet, _amber);
      final alpha = (0.08 + fRng.nextDouble() * 0.12 + hold * 0.18).clamp(0.0, 1.0);
      final arcLen = 0.8 + fRng.nextDouble() * 1.2 + hold * 0.6;
      final dist = r * (0.85 + fRng.nextDouble() * 0.15 + hold * 0.08) * bs;

      final path = Path();
      const steps = 20;
      for (int j = 0; j <= steps; j++) {
        final t = j / steps;
        final angle = baseAngle + t * arcLen;
        final wave = sin(t * pi * 3 + orbit * 6) * r * (0.06 + hold * 0.04);
        final d = dist + wave + fRng.nextDouble() * r * 0.02;
        final pt = center + Offset(cos(angle) * d, sin(angle) * d);
        if (j == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 + fRng.nextDouble() * 3.0 + hold * 2.5
          ..color = flameColor.withValues(alpha: alpha)
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    // Inner flame wisps — smaller, faster, tighter curves inside
    for (int i = 0; i < 6; i++) {
      final baseAngle = (i / 6) * 2 * pi + orbit * 2 * pi * 0.3;
      final d = r * (0.4 + fRng.nextDouble() * 0.3) * bs;
      final alpha = (0.05 + fRng.nextDouble() * 0.08 + hold * 0.12).clamp(0.0, 1.0);
      final path = Path();
      const steps = 14;
      for (int j = 0; j <= steps; j++) {
        final t = j / steps;
        final angle = baseAngle + t * 1.5;
        final wave = sin(t * pi * 4 + orbit * 8) * r * 0.05;
        final pt = center + Offset(cos(angle) * (d + wave), sin(angle) * (d + wave));
        if (j == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 + hold * 1.5
          ..color = _lerpHold(lilac, _warmWhite).withValues(alpha: alpha)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Lilac core glow
    final coreR = r * (0.18 + breath * 0.05 + hold * 0.25);
    canvas.drawCircle(
      center, coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(lilac, _warmWhite).withValues(alpha: 0.85),
          _lerpHold(violet, _amber).withValues(alpha: 0.3),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // Specular highlight — top-left for 3D depth
    final specR1 = r * 0.30;
    final specC1 = center + Offset(-r * 0.18, -r * 0.22);
    canvas.drawCircle(
      specC1, specR1,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.10 + hold * 0.06),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: specC1, radius: specR1)),
    );

    // Pulsing violet rim
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + hold * 2.0 + breath * 0.5
        ..color = _lerpHold(magenta, _gold).withValues(alpha: 0.12 + hold * 0.25 + breath * 0.05),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 2. VOID PORTAL (Pro) — Gravitational vortex
  //    Spiral arms of dim gas being sucked INTO the center.
  //    Accretion disk ring. Everything pulls inward.
  //    Colors: deep indigo, dim violet, silver accretion.
  // ═══════════════════════════════════════════════════════
  void _paintVoidPortal(
      Canvas canvas, Offset center, double r, double bs) {
    const indigo = Color(0xFF2A0060);
    const dimViolet = Color(0xFF6B3FA0);
    const silver = Color(0xFFB8C0D0);

    // Faint outer haze
    canvas.drawCircle(
      center, r * 1.8 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(indigo, _amber).withValues(alpha: 0.05 + hold * 0.08),
          Colors.transparent,
        ], stops: const [0.0, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 1.8)),
    );

    // Main body — near-black vortex
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFF000004),
          _lerpHold(const Color(0xFF08001A), const Color(0xFF0A0500)),
          _lerpHold(indigo, const Color(0xFF3A2000)),
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // SPIRAL ARMS — Archimedean spirals being sucked inward
    final sRng = Random(44);
    for (int arm = 0; arm < 4; arm++) {
      final armOffset = (arm / 4) * 2 * pi;
      final armColor = arm.isEven
          ? _lerpHold(dimViolet, _amber)
          : _lerpHold(silver, _gold);
      final alpha = (0.06 + sRng.nextDouble() * 0.06 + hold * 0.12).clamp(0.0, 1.0);

      final path = Path();
      const steps = 30;
      for (int j = 0; j <= steps; j++) {
        final t = j / steps;
        // Spiral from outside inward (reverse Archimedean)
        final spiralR = r * (0.9 - t * 0.7) * bs;
        final angle = armOffset + t * 3.5 + orbit * 2 * pi * 0.6;
        final pt = center + Offset(cos(angle) * spiralR, sin(angle) * spiralR);
        if (j == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 + sRng.nextDouble() * 2.0 + hold * 2.0
          ..color = armColor.withValues(alpha: alpha)
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    // ACCRETION DISK — thin bright ellipse ring
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.0, 0.35);
    canvas.drawCircle(
      Offset.zero, r * 0.95 * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + hold * 3.0
        ..shader = SweepGradient(
          colors: [
            _lerpHold(silver, _gold).withValues(alpha: 0.0),
            _lerpHold(silver, _gold).withValues(alpha: 0.30 + hold * 0.40),
            _lerpHold(dimViolet, _amber).withValues(alpha: 0.10),
            _lerpHold(silver, _gold).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
          transform: GradientRotation(orbit * 2 * pi * 0.8),
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    canvas.restore();

    // Event horizon core — absolute darkness with faint ring
    final eventR = r * (0.12 + hold * 0.06);
    canvas.drawCircle(center, eventR,
        Paint()..color = const Color(0xFF000000));
    canvas.drawCircle(
      center, eventR * 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + hold * 1.5
        ..color = _lerpHold(dimViolet, _amber).withValues(alpha: 0.15 + hold * 0.25),
    );

    // Subtle rim glow — gives depth to the void edge
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + hold * 1.5
        ..shader = SweepGradient(
          colors: [
            _lerpHold(silver, _gold).withValues(alpha: 0.0),
            _lerpHold(silver, _gold).withValues(alpha: 0.08 + hold * 0.15),
            _lerpHold(indigo, _amber).withValues(alpha: 0.03),
            _lerpHold(silver, _gold).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.25, 0.65, 1.0],
          transform: GradientRotation(orbit * 2 * pi * 0.3),
        ).createShader(Rect.fromCircle(center: center, radius: r * bs)),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 3. PLASMA BURST (Pro) — Electric arc storm
  //    Jagged high-frequency lightning arcs + shockwave rings.
  //    Spark nodes at tendril tips. Fast crackle energy.
  //    Colors: electric cyan, ice white core, deep navy.
  // ═══════════════════════════════════════════════════════
  void _paintPlasmaBurst(
      Canvas canvas, Offset center, double r, double bs) {
    const cyan = Color(0xFF00E5FF);
    const iceWhite = Color(0xFFCDFCFF);
    const deepNavy = Color(0xFF001830);

    // Electric outer glow
    canvas.drawCircle(
      center, r * 2.0 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(cyan, _amber).withValues(alpha: 0.08 + hold * 0.18),
          Colors.transparent,
        ], stops: const [0.0, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 2.0)),
    );

    // Main body — bright plasma
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(iceWhite, _warmWhite).withValues(alpha: 0.80),
          _lerpHold(cyan, const Color(0xFFFFAA44)).withValues(alpha: 0.60),
          _lerpHold(deepNavy, const Color(0xFF1A0800)),
        ], stops: const [0.0, 0.3, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // JAGGED LIGHTNING ARCS — high-frequency zigzag from core outward
    final rng = Random(31);
    const arcCount = 22;
    for (int i = 0; i < arcCount; i++) {
      final angle = (i / arcCount) * 2 * pi + orbit * 2 * pi * 0.35 + rng.nextDouble() * 0.3;
      final arcLen = r * (0.5 + rng.nextDouble() * 0.8 + hold * 0.6) * bs;
      final alpha = (0.07 + rng.nextDouble() * 0.12 + hold * 0.18).clamp(0.0, 1.0);

      final path = Path();
      final start = center + Offset(cos(angle) * r * 0.6, sin(angle) * r * 0.6);
      path.moveTo(start.dx, start.dy);

      var current = start;
      const segs = 6;
      for (int j = 1; j <= segs; j++) {
        final t = j / segs;
        final jitter = (rng.nextDouble() - 0.5) * r * 0.18;
        final dx = cos(angle) * arcLen * t + cos(angle + pi / 2) * jitter;
        final dy = sin(angle) * arcLen * t + sin(angle + pi / 2) * jitter;
        current = start + Offset(dx, dy);
        path.lineTo(current.dx, current.dy);
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 + rng.nextDouble() * 1.5 + hold * 1.2
          ..color = _lerpHold(cyan, _gold).withValues(alpha: alpha)
          ..strokeCap = StrokeCap.round,
      );

      // Spark dot at tip
      canvas.drawCircle(current, 1.5 + hold * 2.0,
          Paint()..color = _lerpHold(iceWhite, _warmWhite).withValues(alpha: alpha));
    }

    // SHOCKWAVE RINGS — concentric expanding rings on hold
    if (hold > 0.05) {
      for (int ring = 0; ring < 3; ring++) {
        final ringPhase = (orbit * 2 + ring * 0.33) % 1.0;
        final ringR = r * (0.4 + ringPhase * 1.4) * bs;
        final ringAlpha = ((1 - ringPhase) * hold * 0.25).clamp(0.0, 1.0);
        if (ringAlpha > 0.01) {
          canvas.drawCircle(
            center, ringR,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 * (1 - ringPhase) + 0.5
              ..color = _lerpHold(cyan, _gold).withValues(alpha: ringAlpha),
          );
        }
      }
    }

    // Bright white core
    final coreR = r * (0.28 + breath * 0.04 + hold * 0.20);
    canvas.drawCircle(
      center, coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.95),
          _lerpHold(iceWhite, _warmWhite).withValues(alpha: 0.5),
          Colors.transparent,
        ], stops: const [0.0, 0.45, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // Specular highlight for depth
    final specR3 = r * 0.25;
    final specC3 = center + Offset(-r * 0.16, -r * 0.20);
    canvas.drawCircle(
      specC3, specR3,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.14 + hold * 0.08),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: specC3, radius: specR3)),
    );

    // Thin electric rim
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + hold * 1.5
        ..color = _lerpHold(cyan, _gold).withValues(alpha: 0.20 + hold * 0.30),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 4. PLASMA CELL (Pro) — Synaptic Network
  //    Neural dendrite branches that fork outward, firing
  //    synapses at junctions, pulse waves racing along paths.
  //    Colors: warm rose-pink, soft peach, ivory white core.
  // ═══════════════════════════════════════════════════════
  void _paintPlasmaCell(
      Canvas canvas, Offset center, double r, double bs) {
    const rosePink = Color(0xFFFF6B9D);
    const peach = Color(0xFFFFAA85);
    const ivory = Color(0xFFFFF5EB);
    const deepRose = Color(0xFF200A12);
    const hotPink = Color(0xFFFF3388);

    // Warm rose outer halo
    canvas.drawCircle(
      center, r * 1.8 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(rosePink, _amber).withValues(alpha: 0.06 + hold * 0.10),
          _lerpHold(hotPink, _gold).withValues(alpha: 0.02),
          Colors.transparent,
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 1.8)),
    );

    // Main body — deep rose-black sphere
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(deepRose, const Color(0xFF0A0500)),
          _lerpHold(const Color(0xFF30101A), const Color(0xFF1A0800)),
          _lerpHold(rosePink, _amber).withValues(alpha: 0.6),
        ], stops: const [0.0, 0.55, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // DENDRITE BRANCHES — fork outward from core like neurons
    final nRng = Random(93);
    for (int branch = 0; branch < 7; branch++) {
      final rootAngle = (branch / 7) * 2 * pi + orbit * pi * 0.08;
      _drawDendrite(canvas, center, rootAngle, r * 0.12 * bs,
          r * (0.55 + nRng.nextDouble() * 0.30 + hold * 0.15) * bs,
          nRng, 0, rosePink, peach);
    }

    // SYNAPSE FIRES — bright pulse dots at random junctions
    for (int s = 0; s < 12; s++) {
      final sAngle = (s / 12) * 2 * pi + orbit * 2 * pi * 0.25;
      final sDist = r * (0.20 + nRng.nextDouble() * 0.55) * bs;
      final spt = center + Offset(cos(sAngle) * sDist, sin(sAngle) * sDist);
      final firePhase = (sin(orbit * 2 * pi * 3 + s * 2.3) + 1) / 2;
      final sAlpha = (firePhase * (0.15 + hold * 0.45)).clamp(0.0, 1.0);
      if (sAlpha > 0.02) {
        // Glow halo
        canvas.drawCircle(spt, r * 0.06 * firePhase,
            Paint()..color = _lerpHold(hotPink, _gold).withValues(alpha: sAlpha * 0.4)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        // Bright dot
        canvas.drawCircle(spt, r * 0.015 + firePhase * r * 0.015,
            Paint()..color = _lerpHold(ivory, _warmWhite).withValues(alpha: sAlpha));
      }
    }

    // PULSE WAVES — rings that expand along the network
    for (int pw = 0; pw < 3; pw++) {
      final pulsePhase = (orbit * 1.5 + pw * 0.33) % 1.0;
      final pulseR = r * (0.08 + pulsePhase * 0.85) * bs;
      final pAlpha = ((1 - pulsePhase) * (0.06 + hold * 0.18)).clamp(0.0, 1.0);
      if (pAlpha > 0.01) {
        canvas.drawCircle(
          center, pulseR,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * (1 - pulsePhase) + 0.5
            ..color = _lerpHold(rosePink, _gold).withValues(alpha: pAlpha),
        );
      }
    }

    // Warm ivory core glow
    final coreR = r * (0.16 + breath * 0.04 + hold * 0.18);
    canvas.drawCircle(
      center, coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(ivory, _warmWhite).withValues(alpha: 0.85),
          _lerpHold(peach, _gold).withValues(alpha: 0.35),
          Colors.transparent,
        ], stops: const [0.0, 0.45, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // Specular highlight — top-left
    final specR = r * 0.28;
    final specC = center + Offset(-r * 0.20, -r * 0.22);
    canvas.drawCircle(
      specC, specR,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.12 + hold * 0.08),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: specC, radius: specR)),
    );

    // Soft rose rim
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + hold * 2.5 + breath * 0.5
        ..color = _lerpHold(rosePink, _gold).withValues(alpha: 0.10 + hold * 0.22 + breath * 0.04),
    );
  }

  // Recursive dendrite branch drawer for Plasma Cell
  void _drawDendrite(Canvas canvas, Offset from, double angle,
      double dist, double maxDist, Random rng, int depth,
      Color mainColor, Color tipColor) {
    if (depth > 3 || dist > maxDist) return;

    final segLen = maxDist * (0.18 + rng.nextDouble() * 0.12);
    final to = from + Offset(cos(angle) * segLen, sin(angle) * segLen);
    final alpha = (0.08 + hold * 0.20 - depth * 0.02 + breath * 0.03).clamp(0.0, 1.0);
    final width = (2.5 - depth * 0.5 + hold * 1.5).clamp(0.5, 4.0);

    // Glow under the branch
    canvas.drawLine(from, to,
      Paint()
        ..color = _lerpHold(mainColor, _gold).withValues(alpha: alpha * 0.3)
        ..strokeWidth = width + 3
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    // Branch line
    canvas.drawLine(from, to,
      Paint()
        ..color = _lerpHold(depth < 2 ? mainColor : tipColor, depth < 2 ? _amber : _gold)
            .withValues(alpha: alpha)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round);

    // Fork into 2 sub-branches
    final forkSpread = 0.4 + rng.nextDouble() * 0.5;
    _drawDendrite(canvas, to, angle - forkSpread + rng.nextDouble() * 0.2,
        dist + segLen, maxDist, rng, depth + 1, mainColor, tipColor);
    _drawDendrite(canvas, to, angle + forkSpread - rng.nextDouble() * 0.2,
        dist + segLen, maxDist, rng, depth + 1, mainColor, tipColor);
  }

  // ═══════════════════════════════════════════════════════
  // 5. TOXIC CORE (Lifetime) — Molten forge / volcanic core
  //    Dark obsidian orb with glowing LAVA VEINS crisscrossing.
  //    Magma bubbles, heat shimmer halo. Erupting on press.
  //    Colors: molten orange, lava red, obsidian black.
  // ═══════════════════════════════════════════════════════
  void _paintToxicCore(
      Canvas canvas, Offset center, double r, double bs) {
    const moltenOrange = Color(0xFFFF6600);
    const lavaRed = Color(0xFFFF2200);
    const obsidian = Color(0xFF0A0A0A);

    // Heat shimmer halo — warm orange/red
    canvas.drawCircle(
      center, r * 1.9 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(moltenOrange, _amber).withValues(alpha: 0.10 + hold * 0.18),
          _lerpHold(lavaRed, _gold).withValues(alpha: 0.04),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 1.9)),
    );

    // Main body — dark obsidian with slight warm edge
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          obsidian,
          _lerpHold(const Color(0xFF1A0A00), const Color(0xFF0A0500)),
          _lerpHold(const Color(0xFF3A1500), const Color(0xFF4A2000)),
        ], stops: const [0.0, 0.6, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // LAVA VEINS — glowing cracks that slowly drift across the surface
    final vRng = Random(42);
    for (int i = 0; i < 12; i++) {
      final startAngle = (i / 12) * 2 * pi + orbit * pi * 0.08;
      final startDist = r * (0.10 + vRng.nextDouble() * 0.15) * bs;
      final start = center + Offset(cos(startAngle) * startDist, sin(startAngle) * startDist);

      final path = Path();
      path.moveTo(start.dx, start.dy);

      var current = start;
      final segCount = 3 + vRng.nextInt(4);
      for (int j = 0; j < segCount; j++) {
        final jAngle = startAngle + (vRng.nextDouble() - 0.5) * 1.4;
        final jDist = r * (0.10 + vRng.nextDouble() * 0.20);
        current = current + Offset(cos(jAngle) * jDist, sin(jAngle) * jDist);
        if ((current - center).distance > r * 0.88 * bs) break;
        path.lineTo(current.dx, current.dy);
      }

      // Glow layer
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0 + hold * 4.0
          ..color = _lerpHold(moltenOrange, _gold).withValues(alpha: 0.08 + hold * 0.12)
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Core vein
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 + hold * 1.5
          ..color = _lerpHold(moltenOrange, _warmWhite).withValues(alpha: 0.40 + hold * 0.40 + breath * 0.1)
          ..strokeCap = StrokeCap.round,
      );
    }

    // MAGMA BUBBLES — bright spots that pulse
    for (int i = 0; i < 6; i++) {
      final a = (i / 6) * 2 * pi + orbit * pi * 0.3;
      final d = r * (0.25 + vRng.nextDouble() * 0.45) * bs;
      final pt = center + Offset(cos(a) * d, sin(a) * d);
      final bubblePhase = (sin(orbit * 2 * pi * 2 + i * 1.2) + 1) / 2;
      final bubR = r * (0.03 + bubblePhase * 0.04 + hold * 0.03);
      final bAlpha = (0.3 + bubblePhase * 0.4 + hold * 0.3).clamp(0.0, 1.0);

      canvas.drawCircle(pt, bubR * 3,
          Paint()..color = _lerpHold(moltenOrange, _gold).withValues(alpha: bAlpha * 0.15));
      canvas.drawCircle(pt, bubR,
          Paint()..color = _lerpHold(lavaRed, _warmWhite).withValues(alpha: bAlpha));
    }

    // Specular highlight — subtle warm shine
    final specR5 = r * 0.22;
    final specC5 = center + Offset(-r * 0.20, -r * 0.24);
    canvas.drawCircle(
      specC5, specR5,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.08 + hold * 0.05),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: specC5, radius: specR5)),
    );

    // Hot core — deep red/orange
    final coreR = r * (0.15 + breath * 0.03 + hold * 0.18);
    canvas.drawCircle(
      center, coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(Colors.white, _warmWhite).withValues(alpha: 0.6),
          _lerpHold(moltenOrange, _gold).withValues(alpha: 0.35),
          Colors.transparent,
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // ASCENDING EMBERS on hold — sparks rising upward
    if (hold > 0.1) {
      for (int i = 0; i < 14; i++) {
        final seed = vRng.nextDouble();
        final phase = (orbit * (0.4 + seed * 0.5) + seed) % 1.0;
        final xSpread = (vRng.nextDouble() - 0.5) * r * 0.6;
        final y = center.dy + r * 0.5 - phase * r * 2.5;
        final fadeIn = (phase * 3).clamp(0.0, 1.0);
        final fadeOut = ((1 - phase) * 2).clamp(0.0, 1.0);
        final eAlpha = (fadeIn * fadeOut * hold * 0.5).clamp(0.0, 1.0);
        final eR = 0.8 + seed * 1.5;
        canvas.drawCircle(Offset(center.dx + xSpread, y), eR,
            Paint()..color = _lerpHold(moltenOrange, _warmWhite).withValues(alpha: eAlpha));
      }
    }

    // Warm glowing rim
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + hold * 3.0
        ..shader = SweepGradient(
          colors: [
            _lerpHold(moltenOrange, _gold).withValues(alpha: 0.0),
            _lerpHold(moltenOrange, _gold).withValues(alpha: 0.25 + hold * 0.35),
            _lerpHold(lavaRed, _amber).withValues(alpha: 0.08),
            _lerpHold(moltenOrange, _gold).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
          transform: GradientRotation(orbit * 2 * pi * 0.4),
        ).createShader(Rect.fromCircle(center: center, radius: r * bs)),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 6. CRYSTAL ASCEND (Lifetime) — Prismatic crystal
  //    Geometric hexagonal facets, rainbow prismatic refractions,
  //    ascending diamond-shaped shimmer particles.
  //    Colors: shifts through spectrum, dominant ice-blue to violet.
  // ═══════════════════════════════════════════════════════
  void _paintCrystalAscend(
      Canvas canvas, Offset center, double r, double bs) {
    const iceBlue = Color(0xFF87CEEB);
    const crystalViolet = Color(0xFF9370DB);
    const prismGold = Color(0xFFFFD700);
    const deepCrystal = Color(0xFF0A1020);

    // Prismatic outer glow — shifts hue
    final hueShift = orbit * 2 * pi;
    final shiftedColor = HSLColor.fromAHSL(1, (hueShift * 180 / pi) % 360, 0.6, 0.6).toColor();
    canvas.drawCircle(
      center, r * 1.7 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(shiftedColor, _amber).withValues(alpha: 0.06 + hold * 0.12),
          Colors.transparent,
        ], stops: const [0.0, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 1.7)),
    );

    // Main body — deep crystal with glassy edge
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(deepCrystal, const Color(0xFF0A0500)),
          _lerpHold(const Color(0xFF1A2040), const Color(0xFF1A0800)),
          _lerpHold(iceBlue, _amber).withValues(alpha: 0.7),
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // HEXAGONAL FACETS — geometric crystal structure visible on surface
    final fRng = Random(88);
    for (int i = 0; i < 7; i++) {
      final a = (i / 7) * 2 * pi + breath * 0.2;
      final d = r * (0.15 + fRng.nextDouble() * 0.40) * bs;
      final fc = center + Offset(cos(a) * d, sin(a) * d);
      final facetR = r * (0.08 + fRng.nextDouble() * 0.08);

      // Draw hexagon
      final hexPath = Path();
      for (int v = 0; v < 6; v++) {
        final va = (v / 6) * 2 * pi + a * 0.3;
        final vp = fc + Offset(cos(va) * facetR, sin(va) * facetR);
        if (v == 0) {
          hexPath.moveTo(vp.dx, vp.dy);
        } else {
          hexPath.lineTo(vp.dx, vp.dy);
        }
      }
      hexPath.close();

      // Facet fill — prismatic color based on position
      final facetHue = ((a + orbit * 2) * 180 / pi) % 360;
      final facetColor = HSLColor.fromAHSL(1, facetHue, 0.5, 0.65).toColor();
      canvas.drawPath(hexPath,
          Paint()..color = _lerpHold(facetColor, _gold).withValues(alpha: 0.08 + hold * 0.15));

      // Facet edge
      canvas.drawPath(hexPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 + hold * 0.8
          ..color = _lerpHold(iceBlue, _gold).withValues(alpha: 0.12 + hold * 0.18));
    }

    // RAINBOW EDGE REFRACTIONS — short prismatic streaks along rim
    for (int i = 0; i < 12; i++) {
      final a = (i / 12) * 2 * pi + orbit * 2 * pi * 0.18;
      final edgePt = center + Offset(cos(a) * r * 0.88 * bs, sin(a) * r * 0.88 * bs);
      final streakLen = r * (0.10 + fRng.nextDouble() * 0.15 + hold * 0.10);
      final streakEnd = edgePt + Offset(cos(a) * streakLen, sin(a) * streakLen);
      final streakHue = ((a + orbit * 3) * 180 / pi) % 360;
      final streakColor = HSLColor.fromAHSL(1, streakHue, 0.7, 0.7).toColor();
      final sAlpha = (0.08 + fRng.nextDouble() * 0.10 + hold * 0.15).clamp(0.0, 1.0);

      canvas.drawLine(edgePt, streakEnd,
        Paint()
          ..color = _lerpHold(streakColor, _gold).withValues(alpha: sAlpha)
          ..strokeWidth = 1.5 + hold * 1.5
          ..strokeCap = StrokeCap.round);
    }

    // Specular highlight — prismatic shine
    final specR6 = r * 0.26;
    final specC6 = center + Offset(-r * 0.18, -r * 0.22);
    canvas.drawCircle(
      specC6, specR6,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.15 + hold * 0.10),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: specC6, radius: specR6)),
    );

    // Crystal core — white with prismatic tint
    final coreR = r * (0.18 + breath * 0.04 + hold * 0.22);
    canvas.drawCircle(
      center, coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.85),
          _lerpHold(shiftedColor, _gold).withValues(alpha: 0.3),
          Colors.transparent,
        ], stops: const [0.0, 0.45, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // ASCENDING DIAMOND PARTICLES — shimmer as they rise
    for (int i = 0; i < 20; i++) {
      final seed = fRng.nextDouble();
      final phase = (orbit * (0.25 + seed * 0.35) + seed) % 1.0;
      final xSpread = (fRng.nextDouble() - 0.5) * r * (0.7 + phase * 0.5);
      final y = center.dy + r * 1.0 - phase * r * 2.8;
      final fadeIn = (phase * 3).clamp(0.0, 1.0);
      final fadeOut = ((1 - phase) * 2.5).clamp(0.0, 1.0);
      final pAlpha = (fadeIn * fadeOut * (0.25 + hold * 0.35)).clamp(0.0, 1.0);
      final pHue = ((seed * 360 + orbit * 180) % 360);
      final pColor = HSLColor.fromAHSL(1, pHue, 0.6, 0.75).toColor();
      final pR = 1.0 + seed * 1.5 + phase * 1.5;

      // Diamond shape
      final pt = Offset(center.dx + xSpread, y);
      final diamond = Path();
      diamond.moveTo(pt.dx, pt.dy - pR * 1.5);
      diamond.lineTo(pt.dx + pR, pt.dy);
      diamond.lineTo(pt.dx, pt.dy + pR * 1.5);
      diamond.lineTo(pt.dx - pR, pt.dy);
      diamond.close();

      canvas.drawPath(diamond,
          Paint()..color = _lerpHold(pColor, _gold).withValues(alpha: pAlpha));
    }

    // Crystalline rim — prismatic sweep
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 + hold * 2.0
        ..shader = SweepGradient(
          colors: [
            _lerpHold(iceBlue, _gold).withValues(alpha: 0.0),
            _lerpHold(crystalViolet, _amber).withValues(alpha: 0.15 + hold * 0.25),
            _lerpHold(prismGold, _gold).withValues(alpha: 0.10 + hold * 0.15),
            _lerpHold(iceBlue, _gold).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.3, 0.65, 1.0],
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
