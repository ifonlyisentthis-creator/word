import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_theme.dart';
import '../services/soul_fire_haptics.dart';

class SoulFireButton extends StatefulWidget {
  const SoulFireButton({
    super.key,
    required this.enabled,
    required this.onConfirmed,
    this.styleId = SoulFireStyleId.etherealOrb,
    this.hapticsEnabled = false,
  });

  final bool enabled;
  final VoidCallback onConfirmed;
  final SoulFireStyleId styleId;
  final bool hapticsEnabled;

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

  // ── Multi-layer safety against false confirmation ──
  // Layer A: real wall-clock elapsed time must be >= 80% of hold duration
  DateTime? _holdStartedAt;
  // Layer B: pointer must still be physically down
  bool _pointerIsDown = false;
  // Layer C: one-shot lock — once consumed, no second fire until full reset
  bool _confirmationLocked = false;

  // Haptic milestone tracking for custom Soul Fire buzz
  final Set<int> _firedHapticMilestones = {};

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

    _holdController.addListener(() {
      if (widget.hapticsEnabled && _holdController.isAnimating && _holdController.value > 0) {
        SoulFireHaptics.onHoldProgress(
          widget.styleId, _holdController.value, _firedHapticMilestones,
        );
      }
    });

    _holdController.addStatusListener((status) {
      // ═══ MULTI-LAYER SAFETY GATE ═══
      // All 5 conditions must be true simultaneously:
      //   1. Animation status == completed
      //   2. Controller value == 1.0 (guards animateTo(0) which also fires .completed)
      //   3. _completed == false (not already confirmed this cycle)
      //   4. _pointerIsDown == true (finger still on screen)
      //   5. Real elapsed time >= 80% of hold duration (guards animation glitches)
      //   6. _confirmationLocked == false (one-shot debounce)
      if (status == AnimationStatus.completed &&
          _holdController.value == 1.0 &&
          !_completed &&
          _pointerIsDown &&
          !_confirmationLocked &&
          _holdStartedAt != null &&
          DateTime.now().difference(_holdStartedAt!).inMilliseconds >=
              (_holdDuration.inMilliseconds * 0.80).round()) {
        _completed = true;
        _confirmationLocked = true;
        if (widget.hapticsEnabled) {
          SoulFireHaptics.onCompletion(widget.styleId);
        } else {
          HapticFeedback.heavyImpact();
        }
        _flashController.forward(from: 0);
        widget.onConfirmed();
        Future.delayed(const Duration(milliseconds: 1400), () {
          if (mounted) {
            _holdController.reset();
            setState(() {
              _completed = false;
              _confirmationLocked = false;
            });
          }
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pause expensive continuous animations when a modal covers this route
    // (e.g. Add Entry sheet) — otherwise the painter ticks at 60fps behind
    // the sheet causing severe lag on slower devices.
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (isCurrent && widget.enabled) {
      if (!_breathController.isAnimating) _breathController.repeat(reverse: true);
      if (!_orbitController.isAnimating) _orbitController.repeat();
    } else {
      _breathController.stop();
      _orbitController.stop();
    }
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
    if (!widget.enabled || _completed || _confirmationLocked) return;
    _pointerStart = event.position;
    _pointerIsDown = true;
    _holdDelayTimer?.cancel();
    _holdDelayTimer = Timer(const Duration(milliseconds: 120), () {
      if (_pointerStart != null && !_completed && _pointerIsDown) {
        _holdStartedAt = DateTime.now();
        _firedHapticMilestones.clear();
        _holdController.forward(from: 0);
        if (widget.hapticsEnabled) {
          SoulFireHaptics.onHoldStart(widget.styleId);
        } else {
          HapticFeedback.lightImpact();
        }
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
    _pointerIsDown = false;
    _cancelHold();
  }

  void _cancelHold() {
    _holdDelayTimer?.cancel();
    _holdDelayTimer = null;
    _pointerStart = null;
    _holdStartedAt = null;
    if (_completed) return;
    // Smooth reverse back to starting state instead of harsh snap
    if (_holdController.value > 0) {
      _holdController.animateTo(
        0,
        duration: Duration(milliseconds: (350 * _holdController.value).round().clamp(100, 350)),
        curve: Curves.easeOutCubic,
      );
    } else {
      _holdController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + 60,
      height: _size + 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The magical orb — only this rebuilds at 60fps
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _breathController,
                _holdController,
                _orbitController,
                _flashController,
              ]),
              builder: (context, _) {
                return CustomPaint(
                  size: Size(_size + 60, _size + 60),
                  painter: _OrbPainter(
                    breath: _breathController.value,
                    hold: _holdController.value,
                    orbit: _orbitController.value,
                    flash: _flashController.value,
                    completed: _completed,
                    styleId: widget.styleId,
                  ),
                );
              },
            ),
          ),

          // Hold progress ring — only rebuilds when hold changes
          AnimatedBuilder(
            animation: _holdController,
            builder: (context, _) {
              if (_holdController.value <= 0) return const SizedBox.shrink();
              return SizedBox(
                width: _size + 8,
                height: _size + 8,
                child: CircularProgressIndicator(
                  value: _holdController.value,
                  strokeWidth: 2.5,
                  color: widget.styleId.primaryColor.withValues(alpha: 0.85),
                  backgroundColor: Colors.white10,
                ),
              );
            },
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
              onPointerCancel: (_) {
                _pointerIsDown = false;
                _cancelHold();
              },
              child: SizedBox(width: _size, height: _size),
            ),
          ),
        ],
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
      case SoulFireStyleId.goldenPulse:
        _paintGoldenPulse(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.nebulaHeart:
        _paintNebulaHeart(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.voidPortal:
        _paintVoidPortal(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.plasmaBurst:
        _paintPlasmaBurst(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.plasmaCell:
        _paintPlasmaCell(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.infinityWell:
        _paintInfinityWell(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.toxicCore:
        _paintToxicCore(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.crystalAscend:
        _paintCrystalAscend(canvas, center, orbRadius, breathScale);
      case SoulFireStyleId.phantomPulse:
        _paintPhantomPulse(canvas, center, orbRadius, breathScale);
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

    // SPIRIT VAPOR TRAILS — curling smoke paths spiral outward on hold
    if (hold > 0.05) {
      for (int i = 0; i < 8; i++) {
        final trailAngle = (i / 8) * 2 * pi + orbit * pi * 0.4;
        final trailColor = i.isEven ? _lerpHold(magenta, _gold) : _lerpHold(violet, _amber);
        final trailAlpha = (hold * 0.35 * (1 - i * 0.04)).clamp(0.0, 1.0);
        final path = Path();
        const steps = 18;
        for (int j = 0; j <= steps; j++) {
          final t = j / steps;
          // Spiral outward with curling motion
          final spiralR = r * (0.95 + t * 0.7 * hold) * bs;
          final curl = sin(t * pi * 3 + orbit * 5 + i * 0.8) * r * 0.12 * t;
          final a = trailAngle + t * 1.8 * hold;
          final pt = center + Offset(
            cos(a) * spiralR + cos(a + pi / 2) * curl,
            sin(a) * spiralR + sin(a + pi / 2) * curl,
          );
          if (j == 0) { path.moveTo(pt.dx, pt.dy); } else { path.lineTo(pt.dx, pt.dy); }
        }
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - hold * 0.3) + hold * 1.5
          ..color = trailColor.withValues(alpha: trailAlpha)
          ..strokeCap = StrokeCap.round);
      }
    }

    // VIOLET MIST NOVA — expanding ethereal fog on completion
    if (flash > 0) {
      final mistR = r * (1.0 + flash * 1.6) * bs;
      // Soft wide mist
      canvas.drawCircle(center, mistR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(lilac, _warmWhite).withValues(alpha: (1 - flash) * 0.45),
          _lerpHold(violet, _amber).withValues(alpha: (1 - flash) * 0.20),
          Colors.transparent,
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: mistR)));
      // Inner wisps radiating outward within the mist
      for (int i = 0; i < 6; i++) {
        final wA = (i / 6) * 2 * pi + flash * 0.5;
        final wStart = center + Offset(cos(wA) * r * 0.4, sin(wA) * r * 0.4);
        final wEnd = center + Offset(cos(wA) * mistR * 0.8, sin(wA) * mistR * 0.8);
        canvas.drawLine(wStart, wEnd, Paint()
          ..color = _lerpHold(lilac, _warmWhite).withValues(alpha: (1 - flash) * 0.25)
          ..strokeWidth = 3.0 * (1 - flash)
          ..strokeCap = StrokeCap.round);
      }
    }

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
  // 1b. GOLDEN PULSE (Free) — Sparkler Cascade
  //     Firework sparkler effect: hundreds of golden sparks
  //     fly outward in parabolic arcs leaving luminous trails.
  //     Crackling embers. Molten gold core. Celebratory.
  //     Colors: white-hot, gold, deep amber, copper trails.
  // ═══════════════════════════════════════════════════════
  void _paintGoldenPulse(
      Canvas canvas, Offset center, double r, double bs) {
    const hotWhite = Color(0xFFFFF8E1);
    const brightGold = Color(0xFFFFD54F);
    const deepAmber = Color(0xFFFF8F00);
    const copper = Color(0xFFBF6000);
    const darkCore = Color(0xFF1A0800);

    // Warm atmospheric glow
    canvas.drawCircle(
      center, r * 2.0 * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          deepAmber.withValues(alpha: 0.04 + hold * 0.08),
          copper.withValues(alpha: 0.02),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r * 2.0)),
    );

    // Main body — dark molten sphere
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..shader = RadialGradient(colors: [
          darkCore,
          const Color(0xFF2A1000),
          _lerpHold(copper, brightGold),
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // SPARKLER SPARKS — parabolic arcs radiating from the surface
    final sRng = Random(77);
    final sparkCount = 30 + (hold * 24).round();
    for (int i = 0; i < sparkCount; i++) {
      final baseAngle = (i / sparkCount) * 2 * pi + orbit * 2 * pi * 0.15;
      final sparkPhase = (orbit * 3.0 + i * 0.37 + sRng.nextDouble() * 0.5) % 1.0;
      final life = sparkPhase;
      // Parabolic arc: sparks fly out then curve down with gravity
      final outDist = r * (0.85 + life * 0.9 + hold * 0.5) * bs;
      final gravity = life * life * r * 0.35 * (i.isEven ? 1 : -1);
      final sparkX = center.dx + cos(baseAngle) * outDist;
      final sparkY = center.dy + sin(baseAngle) * outDist + gravity;
      final sparkPos = Offset(sparkX, sparkY);
      final fadeAlpha = ((1.0 - life) * (0.45 + hold * 0.5)).clamp(0.0, 1.0);
      final sparkSize = (2.0 + sRng.nextDouble() * 2.5) * (1.0 - life * 0.6);
      final sparkColor = i % 3 == 0
          ? hotWhite
          : i % 3 == 1
              ? brightGold
              : deepAmber;

      // Spark dot
      canvas.drawCircle(
        sparkPos, sparkSize,
        Paint()
          ..color = sparkColor.withValues(alpha: fadeAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sparkSize * 0.5),
      );

      // Short luminous trail behind each spark
      if (life > 0.05) {
        final trailDist = outDist - r * 0.12;
        final trailGravity = (life - 0.05) * (life - 0.05) * r * 0.35 * (i.isEven ? 1 : -1);
        final trailPos = Offset(
          center.dx + cos(baseAngle) * trailDist,
          center.dy + sin(baseAngle) * trailDist + trailGravity,
        );
        canvas.drawLine(
          trailPos, sparkPos,
          Paint()
            ..color = copper.withValues(alpha: fadeAlpha * 0.5)
            ..strokeWidth = sparkSize * 0.6
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // CRACKLING EMBERS — tiny bright flickers close to the surface
    for (int i = 0; i < 16; i++) {
      final emberAngle = (i / 16) * 2 * pi + orbit * 2 * pi * 0.4 + breath * 0.3;
      final flicker = (sin(orbit * 2 * pi * 5 + i * 2.3) * 0.5 + 0.5).clamp(0.0, 1.0);
      final emberDist = r * (0.70 + sRng.nextDouble() * 0.28 + hold * 0.08) * bs;
      final emberPos = center + Offset(cos(emberAngle) * emberDist, sin(emberAngle) * emberDist);
      final emberAlpha = (flicker * 0.6 + hold * 0.3).clamp(0.0, 1.0);
      canvas.drawCircle(
        emberPos, 1.5 + flicker * 1.5,
        Paint()..color = hotWhite.withValues(alpha: emberAlpha),
      );
    }

    // EXPANDING SPARK RINGS on hold — concentric bursts
    if (hold > 0.1) {
      for (int i = 0; i < 3; i++) {
        final ringPhase = (orbit * 2.0 + i * 0.33) % 1.0;
        final ringR = r * (0.9 + ringPhase * 0.8 * hold) * bs;
        final ringAlpha = ((1.0 - ringPhase) * hold * 0.3).clamp(0.0, 1.0);
        canvas.drawCircle(
          center, ringR,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 + hold
            ..color = brightGold.withValues(alpha: ringAlpha),
        );
      }
    }

    // White-hot core
    final coreR = r * (0.16 + breath * 0.05 + hold * 0.20);
    canvas.drawCircle(
      center, coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          hotWhite.withValues(alpha: 0.95),
          brightGold.withValues(alpha: 0.5),
          Colors.transparent,
        ], stops: const [0.0, 0.35, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // Specular highlight
    final specR = r * 0.25;
    final specC = center + Offset(-r * 0.14, -r * 0.18);
    canvas.drawCircle(
      specC, specR,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.12 + hold * 0.08),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: specC, radius: specR)),
    );

    // GRAND SPARKLER BURST on completion — massive outward explosion
    if (flash > 0) {
      final burstR = r * (1.0 + flash * 2.0) * bs;
      canvas.drawCircle(center, burstR, Paint()
        ..shader = RadialGradient(colors: [
          hotWhite.withValues(alpha: (1 - flash) * 0.6),
          brightGold.withValues(alpha: (1 - flash) * 0.3),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: burstR)));
      // Radial spark lines in the burst
      for (int i = 0; i < 16; i++) {
        final bAngle = (i / 16) * 2 * pi + flash * 0.3;
        final bStart = center + Offset(cos(bAngle) * r * 0.5, sin(bAngle) * r * 0.5);
        final bEnd = center + Offset(cos(bAngle) * burstR * 0.85, sin(bAngle) * burstR * 0.85);
        canvas.drawLine(bStart, bEnd, Paint()
          ..color = hotWhite.withValues(alpha: (1 - flash) * 0.4)
          ..strokeWidth = 2.5 * (1 - flash)
          ..strokeCap = StrokeCap.round);
      }
    }

    // Gold rim with sparkle
    canvas.drawCircle(
      center, r * bs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + hold * 2.0 + breath * 0.5
        ..color = brightGold.withValues(alpha: 0.12 + hold * 0.25 + breath * 0.06),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 1c. NEBULA HEART (Free) — Cosmic Jellyfish
  //     A bioluminescent deep-sea creature made of nebula gas.
  //     Translucent dome pulses with internal light, trailing
  //     stardust tentacles that flow downward and wave. Bio-
  //     luminescent pulses travel down the tendrils. On hold
  //     the bell contracts and tendrils curl. On completion a
  //     bioluminescent shockwave radiates outward.
  //     Colors: orchid, seafoam cyan, soft lilac, warm white.
  // ═══════════════════════════════════════════════════════
  void _paintNebulaHeart(
      Canvas canvas, Offset center, double r, double bs) {
    const orchid = Color(0xFFDA70D6);
    const seafoam = Color(0xFF66FFCC);
    const lilac = Color(0xFFB899E0);
    const bellCore = Color(0xFFF0E8FF);

    // Bioluminescent ambient haze
    final pulseGlow = sin(breath * pi) * 0.03;
    canvas.drawCircle(center, r * 1.8 * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(orchid, _amber).withValues(alpha: 0.06 + hold * 0.10 + pulseGlow),
        _lerpHold(seafoam, _gold).withValues(alpha: 0.02),
        Colors.transparent,
      ], stops: const [0.0, 0.5, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r * 1.8)));

    // Main body — translucent dome (jellyfish bell)
    final bellSquash = 1.0 - hold * 0.12; // contracts on hold
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.0, bellSquash);
    canvas.drawCircle(Offset.zero, r * bs, Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF080412),
        _lerpHold(const Color(0xFF120820), const Color(0xFF0A0500)),
        _lerpHold(lilac, _amber).withValues(alpha: 0.40),
      ], stops: const [0.0, 0.55, 1.0])
          .createShader(Rect.fromCircle(center: Offset.zero, radius: r)));
    canvas.restore();

    // INTERNAL LUMINOUS VEINS — radial lines inside the bell that pulse
    for (int i = 0; i < 12; i++) {
      final vAngle = (i / 12) * 2 * pi;
      final vPulse = sin(breath * pi * 2 + i * 0.5) * 0.5 + 0.5;
      final vLen = r * (0.3 + vPulse * 0.35 + hold * 0.15) * bs;
      final vStart = center + Offset(cos(vAngle) * r * 0.10, sin(vAngle) * r * 0.10);
      final vEnd = center + Offset(cos(vAngle) * vLen, sin(vAngle) * vLen * bellSquash);
      final vAlpha = (0.04 + vPulse * 0.10 + hold * 0.12).clamp(0.0, 1.0);
      final vColor = i.isEven
          ? _lerpHold(orchid, _gold)
          : _lerpHold(seafoam, _amber);
      canvas.drawLine(vStart, vEnd, Paint()
        ..color = vColor.withValues(alpha: vAlpha)
        ..strokeWidth = 1.5 + vPulse * 1.5 + hold * 1.0
        ..strokeCap = StrokeCap.round);
    }

    // STARDUST TENTACLES — organic tendrils flowing downward
    final tRng = Random(73);
    for (int t = 0; t < 7; t++) {
      final baseAngle = (t / 7) * pi * 1.2 + pi * 0.4; // mostly downward arc
      final seed = tRng.nextDouble();
      final tentPath = Path();
      const steps = 28;
      for (int j = 0; j <= steps; j++) {
        final frac = j / steps;
        // Tentacles hang downward with organic sway
        final sway = sin(frac * pi * 3 + orbit * 2 * pi * 0.3 + t * 1.7) *
            r * 0.12 * frac;
        final curl = hold * sin(frac * pi * 2 + t * 0.8) * r * 0.08 * frac;
        final tentLen = r * (0.5 + seed * 0.6 + hold * 0.3) * frac;
        final tx = center.dx + cos(baseAngle) * r * 0.88 * bs +
            cos(baseAngle + pi / 2) * (sway + curl) +
            cos(baseAngle) * tentLen * 0.3;
        final ty = center.dy + sin(baseAngle) * r * 0.88 * bs * bellSquash +
            tentLen + sin(baseAngle + pi / 2) * (sway + curl) * 0.3;
        if (j == 0) { tentPath.moveTo(tx, ty); }
        else { tentPath.lineTo(tx, ty); }
      }
      final tAlpha = (0.06 + seed * 0.08 + hold * 0.14).clamp(0.0, 1.0);
      final tColor = t % 3 == 0
          ? _lerpHold(orchid, _gold)
          : t % 3 == 1
              ? _lerpHold(seafoam, _amber)
              : _lerpHold(lilac, _warmWhite);
      // Glow
      canvas.drawPath(tentPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 + hold * 2.5
        ..color = tColor.withValues(alpha: tAlpha * 0.25)
        ..strokeCap = StrokeCap.round);
      // Core line
      canvas.drawPath(tentPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + hold * 0.8
        ..color = _lerpHold(bellCore, _warmWhite).withValues(alpha: tAlpha * 0.6)
        ..strokeCap = StrokeCap.round);
    }

    // BIO-LUMINESCENT PULSES — bright dots traveling down tentacles
    for (int i = 0; i < 10; i++) {
      final tIdx = i % 7;
      final baseAngle = (tIdx / 7) * pi * 1.2 + pi * 0.4;
      final phase = (orbit * (0.4 + tRng.nextDouble() * 0.3) + i * 0.29) % 1.0;
      final px = center.dx + cos(baseAngle) * r * 0.88 * bs +
          sin(phase * pi * 3 + orbit * 2 + i) * r * 0.06 * phase;
      final py = center.dy + sin(baseAngle) * r * 0.88 * bs * bellSquash +
          phase * r * (0.5 + tRng.nextDouble() * 0.4);
      final fadeIn = (phase * 3).clamp(0.0, 1.0);
      final fadeOut = ((1 - phase) * 2.5).clamp(0.0, 1.0);
      final pAlpha = (fadeIn * fadeOut * (0.20 + hold * 0.40)).clamp(0.0, 1.0);
      if (pAlpha > 0.02) {
        final pColor = i.isEven ? seafoam : orchid;
        canvas.drawCircle(Offset(px, py), 2.0 + hold * 1.5, Paint()
          ..color = _lerpHold(pColor, _gold).withValues(alpha: pAlpha * 0.30));
        canvas.drawCircle(Offset(px, py), 0.8 + hold * 0.5, Paint()
          ..color = _lerpHold(bellCore, _warmWhite).withValues(alpha: pAlpha));
      }
    }

    // DOME MEMBRANE RIPPLES on hold — concentric arcs across the bell
    if (hold > 0.06) {
      for (int i = 0; i < 3; i++) {
        final rpPhase = (orbit * 1.5 + i * 0.33) % 1.0;
        final rpR = r * (0.20 + rpPhase * 0.65 * hold) * bs;
        final rpAlpha = ((1 - rpPhase) * hold * 0.18).clamp(0.0, 1.0);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.scale(1.0, bellSquash);
        canvas.drawCircle(Offset.zero, rpR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * (1 - rpPhase) + 0.3
          ..color = _lerpHold(orchid, _gold).withValues(alpha: rpAlpha));
        canvas.restore();
      }
    }

    // Core heart — pulsing bioluminescent center
    final heartbeat = sin(breath * pi * 2) * 0.5 + 0.5;
    final coreR = r * (0.12 + heartbeat * 0.06 + hold * 0.18);
    canvas.drawCircle(center, coreR * 2.5, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(orchid, _gold).withValues(alpha: 0.10 + heartbeat * 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: coreR * 2.5)));
    canvas.drawCircle(center, coreR, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(bellCore, _warmWhite).withValues(alpha: 0.85),
        _lerpHold(orchid, _amber).withValues(alpha: 0.30),
        Colors.transparent,
      ], stops: const [0.0, 0.45, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: coreR)));

    // Specular
    final specR = r * 0.26;
    final specC = center + Offset(-r * 0.16, -r * 0.22);
    canvas.drawCircle(specC, specR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.10 + hold * 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: specC, radius: specR)));

    // BIOLUMINESCENT SHOCKWAVE on completion
    if (flash > 0) {
      // Expanding rings of bio-light
      for (int i = 0; i < 3; i++) {
        final ringPhase = (flash + i * 0.10).clamp(0.0, 1.0);
        final ringR = r * (0.3 + ringPhase * 1.6) * bs;
        final ringAlpha = ((1 - ringPhase) * 0.40).clamp(0.0, 1.0);
        final ringColor = i == 0 ? seafoam : i == 1 ? orchid : lilac;
        canvas.drawCircle(center, ringR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - ringPhase) + 0.5
          ..color = _lerpHold(ringColor, _gold).withValues(alpha: ringAlpha));
      }
      // Tentacle-like rays shooting outward
      for (int i = 0; i < 8; i++) {
        final rayAngle = (i / 8) * 2 * pi + flash * 0.4;
        final rayStart = center + Offset(cos(rayAngle) * r * 0.5, sin(rayAngle) * r * 0.5);
        final rayEnd = center + Offset(
          cos(rayAngle) * r * (0.5 + flash * 1.8),
          sin(rayAngle) * r * (0.5 + flash * 1.8));
        final rayAlpha = ((1 - flash) * 0.35).clamp(0.0, 1.0);
        canvas.drawLine(rayStart, rayEnd, Paint()
          ..color = _lerpHold(seafoam, _warmWhite).withValues(alpha: rayAlpha)
          ..strokeWidth = 1.5 * (1 - flash) + 0.3
          ..strokeCap = StrokeCap.round);
      }
      // Central flash
      final fR = r * (0.3 + flash * 0.6) * bs;
      canvas.drawCircle(center, fR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(bellCore, _warmWhite).withValues(alpha: (1 - flash) * 0.55),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: fR)));
    }

    // Translucent dome rim
    canvas.drawCircle(center, r * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 + hold * 1.8 + breath * 0.4
      ..shader = SweepGradient(colors: [
        _lerpHold(orchid, _gold).withValues(alpha: 0.0),
        _lerpHold(seafoam, _gold).withValues(alpha: 0.12 + hold * 0.18),
        _lerpHold(lilac, _amber).withValues(alpha: 0.05),
        _lerpHold(orchid, _gold).withValues(alpha: 0.0),
      ], stops: const [0.0, 0.3, 0.7, 1.0],
        transform: GradientRotation(orbit * 2 * pi * 0.15),
      ).createShader(Rect.fromCircle(center: center, radius: r * bs)));
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

    // SPACETIME DISTORTION — warped elliptical rings on hold (unique to void)
    if (hold > 0.05) {
      for (int i = 0; i < 3; i++) {
        final distortAngle = (i / 3) * pi + orbit * pi * 0.3;
        final distortAlpha = (hold * 0.30 - i * 0.04).clamp(0.0, 1.0);
        final distortR = r * (1.05 + i * 0.15 + hold * 0.2) * bs;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(distortAngle);
        canvas.scale(1.0, 0.25 + i * 0.10);
        canvas.drawCircle(Offset.zero, distortR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 + hold * 1.5
          ..color = _lerpHold(silver, _gold).withValues(alpha: distortAlpha));
        canvas.restore();
      }
    }

    // PHOTON RING — brilliant thin ring erupts from event horizon on completion
    if (flash > 0) {
      // Inner bright ring expanding fast
      final photonR = r * (0.15 + flash * 2.0) * bs;
      final photonAlpha = ((1 - flash) * 0.7).clamp(0.0, 1.0);
      canvas.drawCircle(center, photonR, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1 - flash) + 0.3
        ..color = _lerpHold(silver, _warmWhite).withValues(alpha: photonAlpha));
      // Second fainter ring trailing behind
      final trail = (flash - 0.15).clamp(0.0, 1.0);
      if (trail > 0) {
        final trailR = r * (0.15 + trail * 1.6) * bs;
        canvas.drawCircle(center, trailR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * (1 - trail)
          ..color = _lerpHold(dimViolet, _amber).withValues(alpha: (1 - trail) * 0.35));
      }
    }

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

    // CHAIN LIGHTNING — long forking bolts beyond the rim on hold (unique to plasma burst)
    if (hold > 0.05) {
      final lRng = Random(77);
      for (int i = 0; i < 5; i++) {
        final boltAngle = (i / 5) * 2 * pi + orbit * 2 * pi * 0.5;
        final boltLen = r * (0.4 + hold * 1.0) * bs;
        final boltAlpha = (hold * 0.45).clamp(0.0, 1.0);
        final boltStart = center + Offset(cos(boltAngle) * r * 0.9 * bs, sin(boltAngle) * r * 0.9 * bs);
        // Main bolt path
        final bolt = Path();
        bolt.moveTo(boltStart.dx, boltStart.dy);
        var cur = boltStart;
        const segs = 8;
        for (int j = 1; j <= segs; j++) {
          final t = j / segs;
          final jitter = (lRng.nextDouble() - 0.5) * r * 0.22;
          cur = boltStart + Offset(
            cos(boltAngle) * boltLen * t + cos(boltAngle + pi / 2) * jitter,
            sin(boltAngle) * boltLen * t + sin(boltAngle + pi / 2) * jitter,
          );
          bolt.lineTo(cur.dx, cur.dy);
        }
        canvas.drawPath(bolt, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 + hold * 1.5
          ..color = _lerpHold(cyan, _gold).withValues(alpha: boltAlpha)
          ..strokeCap = StrokeCap.round);
        // Fork branch from midpoint
        final midT = 0.4 + lRng.nextDouble() * 0.2;
        final midJitter = (lRng.nextDouble() - 0.5) * r * 0.15;
        final midPt = boltStart + Offset(
          cos(boltAngle) * boltLen * midT + cos(boltAngle + pi / 2) * midJitter,
          sin(boltAngle) * boltLen * midT + sin(boltAngle + pi / 2) * midJitter,
        );
        final forkAngle = boltAngle + (lRng.nextDouble() - 0.5) * 1.2;
        final forkLen = boltLen * 0.4;
        final fork = Path();
        fork.moveTo(midPt.dx, midPt.dy);
        var fCur = midPt;
        for (int j = 1; j <= 4; j++) {
          final t = j / 4;
          final fj = (lRng.nextDouble() - 0.5) * r * 0.14;
          fCur = midPt + Offset(
            cos(forkAngle) * forkLen * t + cos(forkAngle + pi / 2) * fj,
            sin(forkAngle) * forkLen * t + sin(forkAngle + pi / 2) * fj,
          );
          fork.lineTo(fCur.dx, fCur.dy);
        }
        canvas.drawPath(fork, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 + hold * 0.8
          ..color = _lerpHold(iceWhite, _warmWhite).withValues(alpha: boltAlpha * 0.7)
          ..strokeCap = StrokeCap.round);
      }
    }

    // EMP ZIGZAG SHOCKWAVE — jagged expanding ring on completion (unique to plasma burst)
    if (flash > 0) {
      final empR = r * (0.8 + flash * 1.8) * bs;
      final empAlpha = ((1 - flash) * 0.55).clamp(0.0, 1.0);
      final empPath = Path();
      const empSegs = 36;
      for (int j = 0; j <= empSegs; j++) {
        final a = (j / empSegs) * 2 * pi;
        final jag = (j % 2 == 0 ? 1.0 : -1.0) * r * 0.04 * (1 - flash);
        final d = empR + jag;
        final pt = center + Offset(cos(a) * d, sin(a) * d);
        if (j == 0) { empPath.moveTo(pt.dx, pt.dy); } else { empPath.lineTo(pt.dx, pt.dy); }
      }
      empPath.close();
      canvas.drawPath(empPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1 - flash) + 0.5
        ..color = _lerpHold(cyan, _gold).withValues(alpha: empAlpha));
    }

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
  // 4. PLASMA CELL (Pro) — Living Aurora
  //     Northern lights trapped inside a sphere. Vertical
  //     curtains of shifting color wave and shimmer at
  //     different depths. Charged particles rain downward
  //     like luminous snow. Multiple aurora bands overlap.
  //     On hold, aurora intensifies and bands merge.
  //     On completion, coronal mass ejection shoots ribbons.
  //     Colors: aurora green, magenta, electric violet, ice.
  //     ★ PERFORMANCE: No MaskFilter.blur.
  // ═══════════════════════════════════════════════════════
  void _paintPlasmaCell(
      Canvas canvas, Offset center, double r, double bs) {
    const auroraGreen = Color(0xFF40FF90);
    const auroraMagenta = Color(0xFFFF40AA);
    const auroraViolet = Color(0xFF8844FF);
    const iceWhite = Color(0xFFE8F4FF);
    const deepNight = Color(0xFF020810);

    // Atmospheric glow — faint aurora wash
    canvas.drawCircle(center, r * 1.8 * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(auroraGreen, _amber).withValues(alpha: 0.05 + hold * 0.08),
        _lerpHold(auroraViolet, _gold).withValues(alpha: 0.02),
        Colors.transparent,
      ], stops: const [0.0, 0.5, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r * 1.8)));

    // Main body — deep arctic night sky
    canvas.drawCircle(center, r * bs, Paint()
      ..shader = RadialGradient(colors: [
        deepNight,
        _lerpHold(const Color(0xFF04081A), const Color(0xFF0A0500)),
        _lerpHold(auroraViolet, _amber).withValues(alpha: 0.30),
      ], stops: const [0.0, 0.60, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r)));

    // AURORA CURTAINS — vertical bands of light that wave and shimmer
    final aRng = Random(61);
    for (int band = 0; band < 5; band++) {
      final bandX = (band - 2) * r * 0.32 * bs; // spread across orb
      final bandColor = band % 3 == 0
          ? _lerpHold(auroraGreen, _gold)
          : band % 3 == 1
              ? _lerpHold(auroraMagenta, _amber)
              : _lerpHold(auroraViolet, _warmWhite);
      final bandAlpha = (0.05 + aRng.nextDouble() * 0.04 +
          hold * 0.12 + breath * 0.02).clamp(0.0, 1.0);
      final curtainPath = Path();
      const steps = 20;
      for (int j = 0; j <= steps; j++) {
        final t = j / steps;
        // Vertical position within orb (top to bottom)
        final y = center.dy - r * 0.75 * bs + t * r * 1.5 * bs;
        // Horizontal wavering — organic curtain motion
        final wave1 = sin(t * pi * 2 + orbit * 2 * pi * 0.25 + band * 1.4) *
            r * 0.12 * (1 + hold * 0.5);
        final wave2 = sin(t * pi * 4 + orbit * 2 * pi * 0.4 + band * 2.3) *
            r * 0.05;
        final x = center.dx + bandX + wave1 + wave2;
        if (j == 0) { curtainPath.moveTo(x, y); }
        else { curtainPath.lineTo(x, y); }
      }
      // Broad glow
      canvas.drawPath(curtainPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.18 + hold * r * 0.10
        ..color = bandColor.withValues(alpha: bandAlpha * 0.20)
        ..strokeCap = StrokeCap.round);
      // Inner bright core
      canvas.drawPath(curtainPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.04 + hold * r * 0.03
        ..color = _lerpHold(iceWhite, _warmWhite).withValues(alpha: bandAlpha * 0.40)
        ..strokeCap = StrokeCap.round);
    }

    // AURORA SHIMMER HIGHLIGHTS — bright nodes along curtain peaks
    for (int i = 0; i < 8; i++) {
      final band = i % 5;
      final bandX = (band - 2) * r * 0.32 * bs;
      final phase = (orbit * (0.3 + aRng.nextDouble() * 0.2) + i * 0.35) % 1.0;
      final y = center.dy - r * 0.6 * bs + phase * r * 1.2 * bs;
      final wave = sin(phase * pi * 2 + orbit * 2 * pi * 0.25 + band * 1.4) *
          r * 0.12;
      final x = center.dx + bandX + wave;
      final dist = (Offset(x, y) - center).distance;
      if (dist > r * 0.85) continue; // clip to orb
      final nAlpha = (0.15 + hold * 0.25).clamp(0.0, 1.0);
      final nColor = i.isEven ? auroraGreen : auroraMagenta;
      canvas.drawCircle(Offset(x, y), 2.0 + hold * 1.5, Paint()
        ..color = _lerpHold(nColor, _gold).withValues(alpha: nAlpha * 0.30));
      canvas.drawCircle(Offset(x, y), 0.8 + hold * 0.5, Paint()
        ..color = _lerpHold(iceWhite, _warmWhite).withValues(alpha: nAlpha));
    }

    // CHARGED PARTICLES — luminous snow falling downward
    for (int i = 0; i < 14; i++) {
      final seed = aRng.nextDouble();
      final phase = (orbit * (0.25 + seed * 0.3) + seed * 3.0) % 1.0;
      final xSpread = (seed - 0.5) * r * 1.4;
      // Fall downward
      final y = center.dy - r * 0.8 + phase * r * 1.6;
      final x = center.dx + xSpread + sin(phase * pi * 2 + i * 1.3) * r * 0.04;
      final dist = (Offset(x, y) - center).distance;
      if (dist > r * 0.88) continue;
      final fadeIn = (phase * 3).clamp(0.0, 1.0);
      final fadeOut = ((1 - phase) * 2.5).clamp(0.0, 1.0);
      final pAlpha = (fadeIn * fadeOut * (0.12 + hold * 0.30)).clamp(0.0, 1.0);
      if (pAlpha > 0.02) {
        final pColor = i % 3 == 0 ? auroraGreen : i % 3 == 1 ? auroraMagenta : iceWhite;
        canvas.drawCircle(Offset(x, y), 1.0 + seed * 1.0, Paint()
          ..color = _lerpHold(pColor, _warmWhite).withValues(alpha: pAlpha));
      }
    }

    // MAGNETIC FIELD ARCS on hold — curved lines showing magnetic geometry
    if (hold > 0.06) {
      for (int i = 0; i < 4; i++) {
        final arcPath = Path();
        final arcAngle = (i / 4) * pi + orbit * 2 * pi * 0.08;
        const steps = 24;
        for (int j = 0; j <= steps; j++) {
          final t = j / steps;
          final theta = -pi / 2 + t * pi; // top to bottom arc
          final arcR = r * (0.50 + i * 0.10 + sin(t * pi) * 0.15 * hold) * bs;
          final ax = center.dx + cos(arcAngle) * arcR * cos(theta);
          final ay = center.dy + arcR * sin(theta);
          if (j == 0) { arcPath.moveTo(ax, ay); }
          else { arcPath.lineTo(ax, ay); }
        }
        final arcAlpha = (hold * 0.16 * (1 - i * 0.15)).clamp(0.0, 1.0);
        final arcColor = i.isEven ? auroraGreen : auroraViolet;
        canvas.drawPath(arcPath, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 + hold * 0.8
          ..color = _lerpHold(arcColor, _gold).withValues(alpha: arcAlpha)
          ..strokeCap = StrokeCap.round);
      }
    }

    // Core — bright polar light source
    final coreR = r * (0.10 + breath * 0.04 + hold * 0.16);
    canvas.drawCircle(center, coreR * 2.5, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(auroraGreen, _gold).withValues(alpha: 0.08 + hold * 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: coreR * 2.5)));
    canvas.drawCircle(center, coreR, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(iceWhite, _warmWhite).withValues(alpha: 0.80),
        _lerpHold(auroraGreen, _amber).withValues(alpha: 0.30),
        Colors.transparent,
      ], stops: const [0.0, 0.45, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: coreR)));

    // Specular
    final specR = r * 0.24;
    final specC = center + Offset(-r * 0.16, -r * 0.20);
    canvas.drawCircle(specC, specR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.10 + hold * 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: specC, radius: specR)));

    // CORONAL MASS EJECTION on completion — aurora ribbons erupt outward
    if (flash > 0) {
      // Ribbons shooting out in all directions
      for (int i = 0; i < 6; i++) {
        final ribAngle = (i / 6) * 2 * pi + flash * 0.5;
        final ribColor = i % 3 == 0 ? auroraGreen : i % 3 == 1 ? auroraMagenta : auroraViolet;
        final ribPath = Path();
        const steps = 16;
        for (int j = 0; j <= steps; j++) {
          final t = j / steps;
          final dist = r * (0.3 + t * flash * 1.6);
          final wave = sin(t * pi * 3 + i * 1.5) * r * 0.08 * (1 - flash);
          final rx = center.dx + cos(ribAngle) * dist + cos(ribAngle + pi / 2) * wave;
          final ry = center.dy + sin(ribAngle) * dist + sin(ribAngle + pi / 2) * wave;
          if (j == 0) { ribPath.moveTo(rx, ry); }
          else { ribPath.lineTo(rx, ry); }
        }
        final ribAlpha = ((1 - flash) * 0.40).clamp(0.0, 1.0);
        canvas.drawPath(ribPath, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 * (1 - flash) + 0.5
          ..color = _lerpHold(ribColor, _gold).withValues(alpha: ribAlpha * 0.30)
          ..strokeCap = StrokeCap.round);
        canvas.drawPath(ribPath, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 * (1 - flash) + 0.3
          ..color = _lerpHold(iceWhite, _warmWhite).withValues(alpha: ribAlpha)
          ..strokeCap = StrokeCap.round);
      }
      // Central flash
      final fR = r * (0.3 + flash * 0.5) * bs;
      canvas.drawCircle(center, fR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(iceWhite, _warmWhite).withValues(alpha: (1 - flash) * 0.55),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: fR)));
    }

    // Aurora rim — shifting green/magenta sweep
    canvas.drawCircle(center, r * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 + hold * 1.8 + breath * 0.4
      ..shader = SweepGradient(colors: [
        _lerpHold(auroraGreen, _gold).withValues(alpha: 0.0),
        _lerpHold(auroraGreen, _gold).withValues(alpha: 0.12 + hold * 0.18),
        _lerpHold(auroraMagenta, _amber).withValues(alpha: 0.06),
        _lerpHold(auroraGreen, _gold).withValues(alpha: 0.0),
      ], stops: const [0.0, 0.3, 0.65, 1.0],
        transform: GradientRotation(orbit * 2 * pi * 0.20),
      ).createShader(Rect.fromCircle(center: center, radius: r * bs)));
  }

  // ═══════════════════════════════════════════════════════
  // 5. TOXIC CORE (Lifetime) — Volcanic Caldera
  //     A molten lava lake viewed from above. Churning magma
  //     with cooling dark crust that cracks to reveal glowing
  //     orange beneath. Tectonic plates drift apart slowly.
  //     Eruption sparks rise from crack lines. On hold, crust
  //     breaks further and magma brightens. On completion,
  //     full eruption — lava fountain outward burst.
  //     Colors: molten orange, deep red, obsidian, hot white.
  // ═══════════════════════════════════════════════════════
  void _paintToxicCore(
      Canvas canvas, Offset center, double r, double bs) {
    const moltenOrange = Color(0xFFFF6600);
    const deepRed = Color(0xFFCC2200);
    const obsidian = Color(0xFF1A1008);
    const hotWhite = Color(0xFFFFF0D0);

    // Heat shimmer aura
    final heatPulse = sin(breath * pi) * 0.03;
    canvas.drawCircle(center, r * 1.8 * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(moltenOrange, _amber).withValues(alpha: 0.06 + hold * 0.12 + heatPulse),
        _lerpHold(deepRed, _gold).withValues(alpha: 0.02),
        Colors.transparent,
      ], stops: const [0.0, 0.5, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r * 1.8)));

    // Main body — dark obsidian crust over magma
    canvas.drawCircle(center, r * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(obsidian, const Color(0xFF0A0500)),
        _lerpHold(const Color(0xFF201008), const Color(0xFF180800)),
        _lerpHold(moltenOrange, _amber).withValues(alpha: 0.35),
      ], stops: const [0.0, 0.60, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r)));

    // MAGMA GLOW UNDERNEATH — hot spots visible through crust
    final mRng = Random(53);
    for (int i = 0; i < 6; i++) {
      final seed = mRng.nextDouble();
      final magmaAngle = (i / 6) * 2 * pi + orbit * 2 * pi * 0.05 + seed * 0.5;
      final magmaDist = r * (0.20 + seed * 0.45) * bs;
      final magmaPos = center + Offset(
        cos(magmaAngle) * magmaDist,
        sin(magmaAngle) * magmaDist);
      final magmaR = r * (0.08 + seed * 0.12 + hold * 0.06);
      final magmaPulse = sin(breath * pi * 2 + i * 1.2) * 0.5 + 0.5;
      final magmaAlpha = (0.06 + magmaPulse * 0.10 + hold * 0.18).clamp(0.0, 1.0);
      canvas.drawCircle(magmaPos, magmaR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(hotWhite, _warmWhite).withValues(alpha: magmaAlpha * 0.7),
          _lerpHold(moltenOrange, _gold).withValues(alpha: magmaAlpha * 0.4),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: magmaPos, radius: magmaR)));
    }

    // TECTONIC CRACKS — dark lines that reveal glowing magma beneath
    for (int i = 0; i < 8; i++) {
      final crackPath = Path();
      final startAngle = (i / 8) * 2 * pi + orbit * 2 * pi * 0.03;
      final startDist = r * (0.10 + mRng.nextDouble() * 0.15);
      final endDist = r * (0.60 + mRng.nextDouble() * 0.28 + hold * 0.12);
      const steps = 12;
      for (int j = 0; j <= steps; j++) {
        final t = j / steps;
        final dist = startDist + (endDist - startDist) * t;
        // Jagged crack path — irregular zigzag
        final jag = sin(t * pi * 5 + i * 2.3 + orbit * 1.5) * r * 0.04 * (1 + hold * 0.5);
        final angle = startAngle + jag / dist;
        final pt = center + Offset(cos(angle) * dist * bs, sin(angle) * dist * bs);
        if (j == 0) { crackPath.moveTo(pt.dx, pt.dy); }
        else { crackPath.lineTo(pt.dx, pt.dy); }
      }
      final crackAlpha = (0.10 + hold * 0.25 + breath * 0.03).clamp(0.0, 1.0);
      // Magma glow through crack
      canvas.drawPath(crackPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 + hold * 3.0
        ..color = _lerpHold(moltenOrange, _gold).withValues(alpha: crackAlpha * 0.30)
        ..strokeCap = StrokeCap.round);
      // Bright crack core
      canvas.drawPath(crackPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 + hold * 1.2
        ..color = _lerpHold(hotWhite, _warmWhite).withValues(alpha: crackAlpha * 0.6)
        ..strokeCap = StrokeCap.round);
    }

    // DRIFTING TECTONIC PLATES — dark arcs of cooled crust
    for (int i = 0; i < 4; i++) {
      final plateAngle = (i / 4) * 2 * pi + orbit * 2 * pi * 0.02;
      final plateR = r * (0.55 + i * 0.08) * bs;
      final arcStart = plateAngle - 0.4;
      final arcSweep = 0.6 + mRng.nextDouble() * 0.3;
      final platePath = Path();
      const steps = 16;
      for (int j = 0; j <= steps; j++) {
        final a = arcStart + (j / steps) * arcSweep;
        final pr = plateR + sin(j * 0.8 + orbit * 3) * r * 0.02;
        final pt = center + Offset(cos(a) * pr, sin(a) * pr);
        if (j == 0) { platePath.moveTo(pt.dx, pt.dy); }
        else { platePath.lineTo(pt.dx, pt.dy); }
      }
      final plateAlpha = (0.08 + hold * 0.12).clamp(0.0, 1.0);
      canvas.drawPath(platePath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = _lerpHold(obsidian, const Color(0xFF0A0500))
            .withValues(alpha: plateAlpha)
        ..strokeCap = StrokeCap.round);
    }

    // ERUPTION SPARKS — bright particles rising from cracks
    for (int i = 0; i < 12; i++) {
      final seed = mRng.nextDouble();
      final phase = (orbit * (0.4 + seed * 0.3) + seed * 3.0) % 1.0;
      final sparkAngle = (i / 12) * 2 * pi + seed * 0.5;
      final sparkDist = r * (0.3 + seed * 0.4) * bs;
      // Rise outward from crack positions
      final sx = center.dx + cos(sparkAngle) * (sparkDist + phase * r * 0.5);
      final sy = center.dy + sin(sparkAngle) * (sparkDist + phase * r * 0.5)
          - phase * r * 0.3; // float upward
      final dist = (Offset(sx, sy) - center).distance;
      if (dist > r * 1.3) continue;
      final fadeIn = (phase * 3).clamp(0.0, 1.0);
      final fadeOut = ((1 - phase) * 2.0).clamp(0.0, 1.0);
      final sAlpha = (fadeIn * fadeOut * (0.10 + hold * 0.40)).clamp(0.0, 1.0);
      if (sAlpha > 0.02) {
        final sColor = i.isEven ? moltenOrange : hotWhite;
        canvas.drawCircle(Offset(sx, sy), 1.5 + seed * 1.5, Paint()
          ..color = _lerpHold(sColor, _gold).withValues(alpha: sAlpha * 0.30));
        canvas.drawCircle(Offset(sx, sy), 0.6 + seed * 0.6, Paint()
          ..color = _lerpHold(hotWhite, _warmWhite).withValues(alpha: sAlpha));
      }
    }

    // HEAT DISTORTION RINGS on hold
    if (hold > 0.06) {
      for (int i = 0; i < 3; i++) {
        final rpPhase = (orbit * 1.5 + i * 0.33) % 1.0;
        final rpR = r * (0.20 + rpPhase * 0.70 * hold) * bs;
        final rpAlpha = ((1 - rpPhase) * hold * 0.20).clamp(0.0, 1.0);
        final rpColor = i == 1 ? deepRed : moltenOrange;
        canvas.drawCircle(center, rpR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * (1 - rpPhase) + 0.3
          ..color = _lerpHold(rpColor, _gold).withValues(alpha: rpAlpha));
      }
    }

    // Volatile core — the magma heart
    final coreR = r * (0.14 + breath * 0.05 + hold * 0.20 + heatPulse * 2);
    canvas.drawCircle(center, coreR * 2.5, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(moltenOrange, _gold).withValues(alpha: 0.12 + hold * 0.10),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: coreR * 2.5)));
    canvas.drawCircle(center, coreR, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(hotWhite, _warmWhite).withValues(alpha: 0.90),
        _lerpHold(moltenOrange, _gold).withValues(alpha: 0.45),
        Colors.transparent,
      ], stops: const [0.0, 0.45, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: coreR)));

    // Specular
    final specR = r * 0.22;
    final specC = center + Offset(-r * 0.16, -r * 0.20);
    canvas.drawCircle(specC, specR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.08 + hold * 0.05),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: specC, radius: specR)));

    // FULL ERUPTION on completion — lava fountain burst
    if (flash > 0) {
      // Radial lava streams
      for (int i = 0; i < 10; i++) {
        final eAngle = (i / 10) * 2 * pi + flash * 0.3;
        final eStart = center + Offset(cos(eAngle) * r * 0.3, sin(eAngle) * r * 0.3);
        final eEnd = center + Offset(
          cos(eAngle) * r * (0.3 + flash * 1.8),
          sin(eAngle) * r * (0.3 + flash * 1.8));
        final eAlpha = ((1 - flash) * 0.45).clamp(0.0, 1.0);
        canvas.drawLine(eStart, eEnd, Paint()
          ..color = _lerpHold(moltenOrange, _gold).withValues(alpha: eAlpha * 0.35)
          ..strokeWidth = 3.0 * (1 - flash) + 0.5
          ..strokeCap = StrokeCap.round);
        canvas.drawLine(eStart, eEnd, Paint()
          ..color = _lerpHold(hotWhite, _warmWhite).withValues(alpha: eAlpha)
          ..strokeWidth = 1.0 * (1 - flash) + 0.3
          ..strokeCap = StrokeCap.round);
      }
      // Expanding heat wave
      for (int i = 0; i < 2; i++) {
        final ringPhase = (flash + i * 0.12).clamp(0.0, 1.0);
        final ringR = r * (0.3 + ringPhase * 1.5) * bs;
        final ringAlpha = ((1 - ringPhase) * 0.35).clamp(0.0, 1.0);
        canvas.drawCircle(center, ringR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - ringPhase) + 0.5
          ..color = _lerpHold(moltenOrange, _gold).withValues(alpha: ringAlpha));
      }
      // Central eruption flash
      final fR = r * (0.3 + flash * 0.7) * bs;
      canvas.drawCircle(center, fR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(hotWhite, _warmWhite).withValues(alpha: (1 - flash) * 0.60),
          _lerpHold(moltenOrange, _gold).withValues(alpha: (1 - flash) * 0.25),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: fR)));
    }

    // Magma rim — deep orange/red sweep
    canvas.drawCircle(center, r * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + hold * 2.2
      ..shader = SweepGradient(colors: [
        _lerpHold(moltenOrange, _gold).withValues(alpha: 0.0),
        _lerpHold(moltenOrange, _gold).withValues(alpha: 0.14 + hold * 0.22),
        _lerpHold(deepRed, _amber).withValues(alpha: 0.06),
        _lerpHold(moltenOrange, _gold).withValues(alpha: 0.0),
      ], stops: const [0.0, 0.3, 0.7, 1.0],
        transform: GradientRotation(orbit * 2 * pi * 0.12),
      ).createShader(Rect.fromCircle(center: center, radius: r * bs)));
  }

  // ═══════════════════════════════════════════════════════
  // 6. CRYSTAL ASCEND (Lifetime) — Ascending Double Helix
  //     Two intertwined helical strands of crystalline light
  //     spiral upward through the orb like luminous DNA.
  //     Prismatic nodes at crossover points refract light
  //     into rainbow beams. The helix rotates slowly. On
  //     hold the helix tightens and nodes brighten. On
  //     completion all nodes shatter into ascending diamond
  //     particles. Colors: prismatic spectrum, ice, violet.
  // ═══════════════════════════════════════════════════════
  void _paintCrystalAscend(
      Canvas canvas, Offset center, double r, double bs) {
    const iceBlue = Color(0xFF87CEEB);
    const crystalViolet = Color(0xFF9370DB);
    const prismGold = Color(0xFFFFD700);
    const deepCrystal = Color(0xFF0A1020);
    const diamondWhite = Color(0xFFF0F4FF);

    // Prismatic aura — hue-shifting
    final hueBase = orbit * 2 * pi;
    final auraColor = HSLColor.fromAHSL(1, (hueBase * 180 / pi) % 360, 0.55, 0.60).toColor();
    canvas.drawCircle(center, r * 1.7 * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(auraColor, _amber).withValues(alpha: 0.05 + hold * 0.10),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: r * 1.7)));

    // Main body — deep crystal void
    canvas.drawCircle(center, r * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(deepCrystal, const Color(0xFF0A0500)),
        _lerpHold(const Color(0xFF141830), const Color(0xFF1A0800)),
        _lerpHold(iceBlue, _amber).withValues(alpha: 0.45),
      ], stops: const [0.0, 0.55, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r)));

    // DOUBLE HELIX — two intertwined strands spiraling vertically
    final helixRotation = orbit * 2 * pi * 0.15;
    final helixTightness = 1.0 + hold * 0.6; // tightens on hold
    const helixSteps = 32;
    final nodePositions = <Offset>[];
    final nodeHues = <double>[];

    for (int strand = 0; strand < 2; strand++) {
      final strandPath = Path();
      final phaseOff = strand * pi; // 180° offset between strands
      final strandColor = strand == 0
          ? _lerpHold(iceBlue, _gold)
          : _lerpHold(crystalViolet, _amber);
      final strandAlpha = (0.10 + hold * 0.20 + breath * 0.03).clamp(0.0, 1.0);

      for (int j = 0; j <= helixSteps; j++) {
        final t = j / helixSteps;
        // Vertical position (bottom to top within orb)
        final y = center.dy + r * 0.75 * bs - t * r * 1.5 * bs;
        // Helical x-offset: sinusoidal with tightening
        final helixAngle = t * pi * 3 * helixTightness + helixRotation + phaseOff;
        final helixRadius = r * (0.30 + sin(t * pi) * 0.15) * bs; // wider in middle
        final x = center.dx + cos(helixAngle) * helixRadius;

        if (j == 0) { strandPath.moveTo(x, y); }
        else { strandPath.lineTo(x, y); }

        // Mark crossover nodes — where strands cross (every ~half turn)
        if (strand == 0 && j % 5 == 2 && j > 0 && j < helixSteps) {
          nodePositions.add(Offset(center.dx, y)); // crossover at center x
          final nodeHue = (t * 360 + orbit * 90) % 360;
          nodeHues.add(nodeHue);
        }
      }

      // Strand glow
      canvas.drawPath(strandPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 + hold * 2.5
        ..color = strandColor.withValues(alpha: strandAlpha * 0.25)
        ..strokeCap = StrokeCap.round);
      // Strand core
      canvas.drawPath(strandPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + hold * 0.8
        ..color = _lerpHold(diamondWhite, _warmWhite).withValues(alpha: strandAlpha * 0.60)
        ..strokeCap = StrokeCap.round);
    }

    // CROSSOVER BRIDGES — horizontal rungs connecting the two strands
    for (int j = 0; j <= helixSteps; j += 4) {
      if (j == 0 || j >= helixSteps) continue;
      final t = j / helixSteps;
      final y = center.dy + r * 0.75 * bs - t * r * 1.5 * bs;
      final helixAngle = t * pi * 3 * helixTightness + helixRotation;
      final helixRadius = r * (0.30 + sin(t * pi) * 0.15) * bs;
      final x1 = center.dx + cos(helixAngle) * helixRadius;
      final x2 = center.dx + cos(helixAngle + pi) * helixRadius;
      final bridgeHue = (t * 360 + orbit * 90) % 360;
      final bridgeColor = HSLColor.fromAHSL(1, bridgeHue, 0.65, 0.70).toColor();
      final bridgeAlpha = (0.08 + hold * 0.18).clamp(0.0, 1.0);
      // Glow
      canvas.drawLine(Offset(x1, y), Offset(x2, y), Paint()
        ..color = _lerpHold(bridgeColor, _gold).withValues(alpha: bridgeAlpha * 0.25)
        ..strokeWidth = 2.5 + hold * 2.0
        ..strokeCap = StrokeCap.round);
      // Core
      canvas.drawLine(Offset(x1, y), Offset(x2, y), Paint()
        ..color = _lerpHold(diamondWhite, _warmWhite).withValues(alpha: bridgeAlpha)
        ..strokeWidth = 0.6 + hold * 0.5
        ..strokeCap = StrokeCap.round);
    }

    // PRISMATIC NODES — bright rainbow points at crossover positions
    for (int i = 0; i < nodePositions.length; i++) {
      final np = nodePositions[i];
      final dist = (np - center).distance;
      if (dist > r * 0.85) continue;
      final nHue = nodeHues[i];
      final nColor = HSLColor.fromAHSL(1, nHue, 0.70, 0.75).toColor();
      final nAlpha = (0.20 + hold * 0.35 + breath * 0.05).clamp(0.0, 1.0);
      // Glow
      canvas.drawCircle(np, 3.5 + hold * 2.5, Paint()
        ..color = _lerpHold(nColor, _gold).withValues(alpha: nAlpha * 0.25));
      // Bright node
      canvas.drawCircle(np, 1.5 + hold * 1.0, Paint()
        ..color = _lerpHold(nColor, _warmWhite).withValues(alpha: nAlpha * 0.85));
    }

    // PRISMATIC LIGHT BEAMS on hold — refracted rays from nodes
    if (hold > 0.06) {
      for (int i = 0; i < nodePositions.length; i++) {
        final np = nodePositions[i];
        final dist = (np - center).distance;
        if (dist > r * 0.80) continue;
        // Short rays shooting left and right
        for (int side = 0; side < 2; side++) {
          final rayDir = side == 0 ? -1.0 : 1.0;
          final rayLen = r * 0.20 * hold;
          final rayEnd = np + Offset(rayDir * rayLen, 0);
          final rayHue = (nodeHues[i] + side * 60) % 360;
          final rayColor = HSLColor.fromAHSL(1, rayHue, 0.75, 0.70).toColor();
          final rayAlpha = (hold * 0.25).clamp(0.0, 1.0);
          canvas.drawLine(np, rayEnd, Paint()
            ..color = _lerpHold(rayColor, _gold).withValues(alpha: rayAlpha)
            ..strokeWidth = 0.5 + hold * 0.5
            ..strokeCap = StrokeCap.round);
        }
      }
    }

    // ASCENDING DIAMOND PARTICLES — tiny prisms floating upward
    final gRng = Random(88);
    for (int i = 0; i < 12; i++) {
      final seed = gRng.nextDouble();
      final phase = (orbit * (0.3 + seed * 0.25) + seed * 3.0) % 1.0;
      final xSpread = (seed - 0.5) * r * 1.0;
      final y = center.dy + r * 0.6 - phase * r * 1.8;
      final x = center.dx + xSpread + sin(phase * pi * 2 + i * 1.5) * r * 0.06;
      final pDist = (Offset(x, y) - center).distance;
      if (pDist > r * 0.88) continue;
      final fadeIn = (phase * 3).clamp(0.0, 1.0);
      final fadeOut = ((1 - phase) * 2.5).clamp(0.0, 1.0);
      final pAlpha = (fadeIn * fadeOut * (0.12 + hold * 0.30)).clamp(0.0, 1.0);
      if (pAlpha > 0.02) {
        final pHue = (seed * 360 + orbit * 120) % 360;
        final pColor = HSLColor.fromAHSL(1, pHue, 0.65, 0.75).toColor();
        canvas.drawCircle(Offset(x, y), 1.0 + seed * 1.0, Paint()
          ..color = _lerpHold(pColor, _gold).withValues(alpha: pAlpha));
      }
    }

    // Core — white with prismatic tint
    final coreR = r * (0.12 + breath * 0.04 + hold * 0.16);
    canvas.drawCircle(center, coreR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.85),
        _lerpHold(auraColor, _gold).withValues(alpha: 0.30),
        Colors.transparent,
      ], stops: const [0.0, 0.45, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: coreR)));

    // Specular
    final specR = r * 0.22;
    final specC = center + Offset(-r * 0.14, -r * 0.18);
    canvas.drawCircle(specC, specR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.12 + hold * 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: specC, radius: specR)));

    // DIAMOND SHATTER on completion — nodes burst into ascending particles
    if (flash > 0) {
      for (int i = 0; i < nodePositions.length; i++) {
        final np = nodePositions[i];
        // Expanding sparkle ring from each node
        final burstR = r * 0.08 + flash * r * 0.5;
        final burstAlpha = ((1 - flash) * 0.40).clamp(0.0, 1.0);
        final burstHue = nodeHues[i];
        final burstColor = HSLColor.fromAHSL(1, burstHue, 0.70, 0.70).toColor();
        canvas.drawCircle(np, burstR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * (1 - flash) + 0.3
          ..color = _lerpHold(burstColor, _gold).withValues(alpha: burstAlpha));
      }
      // Ascending diamond shower
      for (int i = 0; i < 12; i++) {
        final dAngle = (i / 12) * 2 * pi + flash * 0.8;
        final dDist = r * (0.2 + flash * 1.2);
        final dPos = center + Offset(
          cos(dAngle) * dDist * 0.6,
          -flash * r * 0.5 + sin(dAngle) * dDist * 0.3);
        final dAlpha = ((1 - flash) * 0.45).clamp(0.0, 1.0);
        final dHue = (i * 30.0 + orbit * 90) % 360;
        final dColor = HSLColor.fromAHSL(1, dHue, 0.70, 0.70).toColor();
        canvas.drawCircle(dPos, 1.5 * (1 - flash) + 0.5, Paint()
          ..color = _lerpHold(dColor, _warmWhite).withValues(alpha: dAlpha));
      }
      // Central white flash
      final fR = r * (0.3 + flash * 0.5) * bs;
      canvas.drawCircle(center, fR, Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: (1 - flash) * 0.50),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: fR)));
    }

    // Prismatic rim — spectrum sweep
    canvas.drawCircle(center, r * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 + hold * 1.8
      ..shader = SweepGradient(colors: [
        _lerpHold(iceBlue, _gold).withValues(alpha: 0.0),
        _lerpHold(crystalViolet, _amber).withValues(alpha: 0.12 + hold * 0.20),
        _lerpHold(prismGold, _gold).withValues(alpha: 0.08 + hold * 0.12),
        _lerpHold(iceBlue, _gold).withValues(alpha: 0.0),
      ], stops: const [0.0, 0.3, 0.65, 1.0],
        transform: GradientRotation(orbit * 2 * pi * 0.6),
      ).createShader(Rect.fromCircle(center: center, radius: r * bs)));
  }

  // ═══════════════════════════════════════════════════════
  // 7. INFINITY WELL (Pro) — Möbius Infinity
  //     A glowing infinity symbol (lemniscate) that rotates
  //     in 3D with particles flowing along its surface like
  //     a river of light. One loop passes in front, the other
  //     behind, creating depth. Trailing light echoes follow.
  //     On hold the figure tightens and glows brighter.
  //     On completion the infinity unravels into a spiral.
  //     Colors: deep violet, neon pink, electric blue, cyan.
  // ═══════════════════════════════════════════════════════
  void _paintInfinityWell(
      Canvas canvas, Offset center, double r, double bs) {
    const deepViolet = Color(0xFF6A0DAD);
    const neonPink = Color(0xFFFF6EC7);
    const electricBlue = Color(0xFF4488FF);
    const dimensionCyan = Color(0xFF00FFEE);
    const abyssBlack = Color(0xFF020008);

    // Dimensional glow — layered
    for (int g = 0; g < 2; g++) {
      final glowR = r * (1.6 + g * 0.4) * bs;
      final glowA = (0.04 + hold * 0.08) / (1 + g);
      canvas.drawCircle(center, glowR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(deepViolet, _amber).withValues(alpha: glowA),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: glowR)));
    }

    // Main body — absolute black void
    canvas.drawCircle(center, r * bs, Paint()
      ..shader = RadialGradient(colors: [
        abyssBlack,
        _lerpHold(const Color(0xFF06000F), const Color(0xFF060300)),
        _lerpHold(deepViolet, _amber).withValues(alpha: 0.30),
      ], stops: const [0.0, 0.65, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r)));

    // LEMNISCATE (∞) — parametric infinity curve rotating in 3D
    final infRotation = orbit * 2 * pi * 0.12;
    final infScale = r * (0.55 - hold * 0.08) * bs; // tightens on hold
    final tilt3D = orbit * 2 * pi * 0.07; // slow 3D rotation
    const infSteps = 64;

    // Compute lemniscate points with 3D depth
    final infPoints = <Offset>[];
    final infDepths = <double>[]; // z-depth for front/back ordering
    for (int j = 0; j <= infSteps; j++) {
      final t = (j / infSteps) * 2 * pi;
      // Lemniscate of Bernoulli: x = cos(t) / (1+sin²(t)), y = sin(t)cos(t) / (1+sin²(t))
      final denom = 1.0 + sin(t) * sin(t);
      final lx = cos(t) / denom;
      final ly = sin(t) * cos(t) / denom;

      // Apply 3D rotation around Y axis for depth effect
      final z3d = lx * sin(tilt3D);
      final x3d = lx * cos(tilt3D);

      // Apply main rotation
      final rx = x3d * cos(infRotation) - ly * sin(infRotation);
      final ry = x3d * sin(infRotation) + ly * cos(infRotation);

      infPoints.add(center + Offset(rx * infScale, ry * infScale));
      infDepths.add(z3d);
    }

    // Draw trailing echoes — ghostly past positions
    for (int echo = 2; echo >= 1; echo--) {
      final echoPath = Path();
      final echoRot = infRotation - echo * 0.15;
      final echoAlpha = (0.03 + hold * 0.04) / echo;
      for (int j = 0; j <= infSteps; j++) {
        final t = (j / infSteps) * 2 * pi;
        final denom = 1.0 + sin(t) * sin(t);
        final lx = cos(t) / denom;
        final ly = sin(t) * cos(t) / denom;
        final x3d = lx * cos(tilt3D);
        final rx = x3d * cos(echoRot) - ly * sin(echoRot);
        final ry = x3d * sin(echoRot) + ly * cos(echoRot);
        final pt = center + Offset(rx * infScale, ry * infScale);
        if (j == 0) { echoPath.moveTo(pt.dx, pt.dy); }
        else { echoPath.lineTo(pt.dx, pt.dy); }
      }
      final echoColor = echo == 1 ? deepViolet : neonPink;
      canvas.drawPath(echoPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + hold * 1.5
        ..color = _lerpHold(echoColor, _gold).withValues(alpha: echoAlpha)
        ..strokeCap = StrokeCap.round);
    }

    // Draw the main infinity — back half first, then front half
    // Split at crossover point (where z crosses zero)
    final backPath = Path();
    final frontPath = Path();
    var backStarted = false;
    var frontStarted = false;
    for (int j = 0; j <= infSteps; j++) {
      final pt = infPoints[j];
      final depth = infDepths[j];
      if (depth <= 0) {
        if (!backStarted) { backPath.moveTo(pt.dx, pt.dy); backStarted = true; }
        else { backPath.lineTo(pt.dx, pt.dy); }
      } else {
        if (!frontStarted) { frontPath.moveTo(pt.dx, pt.dy); frontStarted = true; }
        else { frontPath.lineTo(pt.dx, pt.dy); }
      }
    }

    final lineAlpha = (0.14 + hold * 0.28 + breath * 0.03).clamp(0.0, 1.0);

    // Back half — dimmer (behind)
    if (backStarted) {
      canvas.drawPath(backPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 + hold * 3.0
        ..color = _lerpHold(deepViolet, _gold).withValues(alpha: lineAlpha * 0.15)
        ..strokeCap = StrokeCap.round);
      canvas.drawPath(backPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + hold * 0.8
        ..color = _lerpHold(electricBlue, _warmWhite).withValues(alpha: lineAlpha * 0.50)
        ..strokeCap = StrokeCap.round);
    }

    // Front half — brighter (in front)
    if (frontStarted) {
      canvas.drawPath(frontPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 + hold * 3.5
        ..color = _lerpHold(neonPink, _gold).withValues(alpha: lineAlpha * 0.22)
        ..strokeCap = StrokeCap.round);
      canvas.drawPath(frontPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 + hold * 1.0
        ..color = _lerpHold(dimensionCyan, _warmWhite).withValues(alpha: lineAlpha * 0.70)
        ..strokeCap = StrokeCap.round);
    }

    // FLOWING PARTICLES — light motes traveling along the infinity curve
    final tRng = Random(77);
    for (int i = 0; i < 14; i++) {
      final phase = (orbit * (0.5 + tRng.nextDouble() * 0.4) + i * (1.0 / 14)) % 1.0;
      final idx = (phase * infSteps).floor().clamp(0, infSteps);
      final pt = infPoints[idx];
      final depth = infDepths[idx];
      final dist = (pt - center).distance;
      if (dist > r * 1.2) continue;
      final brightness = depth > 0 ? 1.0 : 0.5; // front particles brighter
      final pAlpha = ((0.20 + hold * 0.35) * brightness).clamp(0.0, 1.0);
      final pColor = i.isEven ? dimensionCyan : neonPink;
      canvas.drawCircle(pt, 2.0 + hold * 1.5, Paint()
        ..color = _lerpHold(pColor, _gold).withValues(alpha: pAlpha * 0.25));
      canvas.drawCircle(pt, 0.8 + hold * 0.5, Paint()
        ..color = Colors.white.withValues(alpha: pAlpha));
    }

    // CROSSOVER GLOW — bright node where the loops cross
    final crossAlpha = (0.12 + hold * 0.25 + sin(breath * pi) * 0.04).clamp(0.0, 1.0);
    canvas.drawCircle(center, r * 0.08 + hold * r * 0.06, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: crossAlpha * 0.8),
        _lerpHold(dimensionCyan, _warmWhite).withValues(alpha: crossAlpha * 0.3),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: r * 0.12)));

    // DIMENSIONAL RIPPLES on hold — expanding figure-8 shaped waves
    if (hold > 0.06) {
      for (int i = 0; i < 3; i++) {
        final rpPhase = (orbit * 1.5 + i * 0.33) % 1.0;
        final rpScale = infScale * (1.0 + rpPhase * 0.6 * hold);
        final rpPath = Path();
        for (int j = 0; j <= 32; j++) {
          final t = (j / 32) * 2 * pi;
          final denom = 1.0 + sin(t) * sin(t);
          final lx = cos(t) / denom;
          final ly = sin(t) * cos(t) / denom;
          final rx = lx * cos(infRotation) - ly * sin(infRotation);
          final ry = lx * sin(infRotation) + ly * cos(infRotation);
          final pt = center + Offset(rx * rpScale, ry * rpScale);
          if (j == 0) { rpPath.moveTo(pt.dx, pt.dy); }
          else { rpPath.lineTo(pt.dx, pt.dy); }
        }
        final rpAlpha = ((1 - rpPhase) * hold * 0.18).clamp(0.0, 1.0);
        final rpColor = i.isEven ? neonPink : electricBlue;
        canvas.drawPath(rpPath, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 * (1 - rpPhase) + 0.3
          ..color = _lerpHold(rpColor, _gold).withValues(alpha: rpAlpha)
          ..strokeCap = StrokeCap.round);
      }
    }

    // Core — bright singularity at crossover
    final coreR = r * (0.08 + breath * 0.03 + hold * 0.14);
    canvas.drawCircle(center, coreR * 2.5, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(dimensionCyan, _warmWhite).withValues(alpha: 0.08 + hold * 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: coreR * 2.5)));
    canvas.drawCircle(center, coreR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.90),
        _lerpHold(dimensionCyan, _warmWhite).withValues(alpha: 0.40),
        Colors.transparent,
      ], stops: const [0.0, 0.35, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: coreR)));

    // Specular
    final specR = r * 0.20;
    final specC = center + Offset(-r * 0.14, -r * 0.18);
    canvas.drawCircle(specC, specR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.08 + hold * 0.04),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: specC, radius: specR)));

    // INFINITY UNRAVEL on completion — loops spiral outward
    if (flash > 0) {
      // Expanding spiral fragments
      for (int i = 0; i < 10; i++) {
        final fragAngle = (i / 10) * 2 * pi + flash * pi;
        final fragDist = r * (0.2 + flash * 1.5);
        final fragStart = center + Offset(
          cos(fragAngle) * fragDist * 0.3,
          sin(fragAngle) * fragDist * 0.3);
        final fragEnd = center + Offset(
          cos(fragAngle) * fragDist,
          sin(fragAngle) * fragDist);
        final fragAlpha = ((1 - flash) * 0.45).clamp(0.0, 1.0);
        final fragColor = i.isEven ? neonPink : electricBlue;
        canvas.drawLine(fragStart, fragEnd, Paint()
          ..color = _lerpHold(fragColor, _gold).withValues(alpha: fragAlpha * 0.30)
          ..strokeWidth = 3.0 * (1 - flash) + 0.5
          ..strokeCap = StrokeCap.round);
        canvas.drawLine(fragStart, fragEnd, Paint()
          ..color = _lerpHold(dimensionCyan, _warmWhite).withValues(alpha: fragAlpha)
          ..strokeWidth = 1.0 * (1 - flash) + 0.3
          ..strokeCap = StrokeCap.round);
      }
      // Central white flash
      final fR = r * (0.4 * (1 - flash)) * bs;
      canvas.drawCircle(center, fR, Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: (1 - flash) * 0.75),
          _lerpHold(deepViolet, _warmWhite).withValues(alpha: (1 - flash) * 0.25),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: fR)));
    }

    // Neon dimensional rim
    canvas.drawCircle(center, r * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + hold * 2.0
      ..shader = SweepGradient(colors: [
        _lerpHold(neonPink, _gold).withValues(alpha: 0.0),
        _lerpHold(electricBlue, _gold).withValues(alpha: 0.12 + hold * 0.20),
        _lerpHold(deepViolet, _amber).withValues(alpha: 0.05),
        _lerpHold(neonPink, _gold).withValues(alpha: 0.0),
      ], stops: const [0.0, 0.3, 0.65, 1.0],
        transform: GradientRotation(orbit * 2 * pi * 0.20),
      ).createShader(Rect.fromCircle(center: center, radius: r * bs)));
  }

  // ═══════════════════════════════════════════════════════
  // 8. PHANTOM PULSE (Lifetime) — Phase-Shifting Specter
  //    Multiple ghost COPIES orbit independently at different
  //    phases, flickering between visible and invisible.
  //    Spectral tendrils REACH OUTWARD like ghost arms. A
  //    heartbeat rhythm where the orb PULSES with ghostly
  //    energy. Reverse-gravity particles float UPWARD.
  //    Eerie, otherworldly, unmistakable presence.
  //    Colors: spectral silver, phantom blue, ghostly white.
  // ═══════════════════════════════════════════════════════
  void _paintPhantomPulse(
      Canvas canvas, Offset center, double r, double bs) {
    const spectralSilver = Color(0xFFCCCCCC);
    const phantomBlue = Color(0xFF4488FF);
    const ghostWhite = Color(0xFFE8E8F0);
    const deepVoid = Color(0xFF040408);
    const eerieGreen = Color(0xFF40FF90);

    // Spectral aurora haze — eerie double-layered
    for (int g = 0; g < 2; g++) {
      final hazeR = r * (1.7 + g * 0.4) * bs;
      final hazeA = (0.03 + hold * 0.06) / (1 + g);
      final hazeColor = g == 0
          ? _lerpHold(phantomBlue, _gold)
          : _lerpHold(eerieGreen, _amber);
      canvas.drawCircle(center, hazeR, Paint()
        ..shader = RadialGradient(colors: [
          hazeColor.withValues(alpha: hazeA),
          _lerpHold(spectralSilver, _gold).withValues(alpha: hazeA * 0.3),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: hazeR)));
    }

    // Main body — void with ghostly edge
    canvas.drawCircle(center, r * bs, Paint()
      ..shader = RadialGradient(colors: [
        deepVoid,
        _lerpHold(const Color(0xFF0A0A14), const Color(0xFF0A0800)),
        _lerpHold(spectralSilver, _amber).withValues(alpha: 0.35),
      ], stops: const [0.0, 0.55, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r)));

    // INNER SPECTRAL AURORA — soft colored bands that shimmer inside the orb
    for (int i = 0; i < 3; i++) {
      final auroraAngle = (i / 3) * 2 * pi + orbit * 0.2 + i * 0.8;
      final auroraDist = r * (0.20 + i * 0.12) * bs;
      final auroraSize = r * (0.18 + i * 0.04);
      final auroraColor = i == 0
          ? _lerpHold(phantomBlue, _gold)
          : i == 1
              ? _lerpHold(eerieGreen, _amber)
              : _lerpHold(spectralSilver, _warmWhite);
      final auroraAlpha = (0.04 + hold * 0.05 + breath * 0.02).clamp(0.0, 1.0);
      canvas.drawCircle(
        center + Offset(cos(auroraAngle) * auroraDist, sin(auroraAngle) * auroraDist),
        auroraSize,
        Paint()
          ..color = auroraColor.withValues(alpha: auroraAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, auroraSize * 0.6),
      );
    }

    // ORBITING GHOST COPIES — 4 phantom echoes at independent phases
    for (int ghost = 0; ghost < 4; ghost++) {
      final ghostPhase = orbit * (0.12 + ghost * 0.03) + ghost * pi * 0.5;
      final ghostAngle = ghostPhase * 2 * pi;
      final ghostDist = r * (0.06 + ghost * 0.02 + hold * 0.04);
      final ghostCenter = center + Offset(cos(ghostAngle) * ghostDist, sin(ghostAngle) * ghostDist);
      final ghostR = r * (0.88 - ghost * 0.04) * bs;
      // Phase-shifting visibility: each ghost flickers independently
      final flicker = sin(orbit * 2 * pi * (3.0 + ghost * 1.7) + ghost * 2.1);
      final visible = (flicker * 0.5 + 0.5).clamp(0.0, 1.0);
      final ghostAlpha = (visible * (0.04 + hold * 0.06) - ghost * 0.005).clamp(0.0, 1.0);
      if (ghostAlpha > 0.01) {
        // Ghost ring
        canvas.drawCircle(ghostCenter, ghostR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 - ghost * 0.3 + hold
          ..color = _lerpHold(spectralSilver, _gold).withValues(alpha: ghostAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.0 + ghost * 0.5));
        // Ghost fill — very faint
        canvas.drawCircle(ghostCenter, ghostR * 0.5, Paint()
          ..color = _lerpHold(phantomBlue, _gold).withValues(alpha: ghostAlpha * 0.15)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, ghostR * 0.3));
      }
    }

    // SPECTRAL REACHING ARMS — tendrils that extend outward like ghost hands
    final gRng = Random(99);
    for (int i = 0; i < 6; i++) {
      final baseAngle = (i / 6) * 2 * pi + orbit * 2 * pi * 0.04;
      final armColor = i % 3 == 0
          ? _lerpHold(spectralSilver, _gold)
          : i % 3 == 1
              ? _lerpHold(phantomBlue, _amber)
              : _lerpHold(eerieGreen, _gold);
      final armAlpha = (0.04 + gRng.nextDouble() * 0.06 + hold * 0.14).clamp(0.0, 1.0);
      final armLen = r * (0.6 + gRng.nextDouble() * 0.4 + hold * 0.5);
      // Each arm reaches outward with organic waviness
      final path = Path();
      const steps = 20;
      for (int j = 0; j <= steps; j++) {
        final t = j / steps;
        final angle = baseAngle + sin(t * pi * 1.5 + orbit * 3 + i * 1.1) * 0.15;
        final dist = r * 0.85 * bs + t * armLen;
        // Ghostly wavering — arms shimmer side to side
        final waver = sin(t * pi * 3 + orbit * 5 + i * 2.0) * r * 0.06 * t;
        final pt = center + Offset(
          cos(angle) * dist + cos(angle + pi / 2) * waver,
          sin(angle) * dist + sin(angle + pi / 2) * waver,
        );
        if (j == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      // Blurred outer glow
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 + hold * 4.0
        ..color = armColor.withValues(alpha: armAlpha * 0.25)
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      // Sharp inner line
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + hold * 0.8
        ..color = ghostWhite.withValues(alpha: armAlpha * 0.5)
        ..strokeCap = StrokeCap.round);
    }

    // PHANTOM HEARTBEAT — slow, heavy thuds that expand and fade
    final heartbeatCycle = (orbit * 0.8) % 1.0;
    // Two beats per cycle like a real heartbeat: thump-thump ... thump-thump
    for (int beat = 0; beat < 2; beat++) {
      final beatStart = beat * 0.15;
      final beatPhase = ((heartbeatCycle - beatStart) % 1.0);
      if (beatPhase < 0.35) {
        final t = beatPhase / 0.35;
        final beatR = r * (0.3 + t * 0.65) * bs;
        final beatAlpha = ((1 - t) * (0.08 + hold * 0.18)).clamp(0.0, 1.0);
        canvas.drawCircle(center, beatR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * (1 - t) + 0.3
          ..color = _lerpHold(spectralSilver, _gold).withValues(alpha: beatAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
      }
    }

    // REVERSE-GRAVITY PARTICLES — motes that float UPWARD
    for (int i = 0; i < 14; i++) {
      final seed = gRng.nextDouble();
      final phase = (orbit * (0.3 + seed * 0.4) + seed * 3.0) % 1.0;
      final xSpread = (seed - 0.5) * r * 1.2;
      // Rise upward from orb surface
      final y = center.dy + r * 0.5 - phase * r * 2.5;
      final x = center.dx + xSpread + sin(phase * pi * 2 + i * 1.3) * r * 0.08;
      final fadeIn = (phase * 3).clamp(0.0, 1.0);
      final fadeOut = ((1 - phase) * 2.5).clamp(0.0, 1.0);
      final pAlpha = (fadeIn * fadeOut * (0.15 + hold * 0.35)).clamp(0.0, 1.0);
      final pSize = (1.0 + seed * 2.0) * (1 - phase * 0.4);
      final pColor = i % 3 == 0 ? ghostWhite : i % 3 == 1 ? phantomBlue : eerieGreen;
      if (pAlpha > 0.02) {
        // Soft glow
        canvas.drawCircle(Offset(x, y), pSize * 2.5, Paint()
          ..color = _lerpHold(pColor, _gold).withValues(alpha: pAlpha * 0.15)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, pSize));
        // Bright core
        canvas.drawCircle(Offset(x, y), pSize, Paint()
          ..color = _lerpHold(pColor, _warmWhite).withValues(alpha: pAlpha));
      }
    }

    // Ghostly core — eerie pulsing silver
    final coreR = r * (0.14 + breath * 0.05 + hold * 0.18);
    // Outer halo — ethereal glow around core
    canvas.drawCircle(center, coreR * 2.8, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(phantomBlue, _gold).withValues(alpha: 0.08 + hold * 0.06),
        _lerpHold(eerieGreen, _amber).withValues(alpha: 0.03),
        Colors.transparent,
      ], stops: const [0.0, 0.4, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: coreR * 2.8)));
    // Bright core
    canvas.drawCircle(center, coreR, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(ghostWhite, _warmWhite).withValues(alpha: 0.85),
        _lerpHold(phantomBlue, _amber).withValues(alpha: 0.25),
        Colors.transparent,
      ], stops: const [0.0, 0.4, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: coreR)));

    // Specular — cold highlight
    final specR = r * 0.22;
    final specC = center + Offset(-r * 0.14, -r * 0.18);
    canvas.drawCircle(specC, specR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.10 + hold * 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: specC, radius: specR)));

    // SPECTRAL DISPERSAL on completion — ghost shatters into many copies
    if (flash > 0) {
      for (int i = 0; i < 8; i++) {
        final disperseAngle = (i / 8) * 2 * pi + flash * 0.6;
        final disperseDist = r * flash * 1.8;
        final disperseCenter = center + Offset(
          cos(disperseAngle) * disperseDist,
          sin(disperseAngle) * disperseDist,
        );
        final disperseAlpha = ((1 - flash) * 0.20).clamp(0.0, 1.0);
        final disperseR = r * (0.25 - flash * 0.12) * bs;
        final dColor = i.isEven ? ghostWhite : phantomBlue;
        canvas.drawCircle(disperseCenter, disperseR, Paint()
          ..color = _lerpHold(dColor, _warmWhite).withValues(alpha: disperseAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + flash * 8));
      }
      // Central flash
      final flashR = r * (0.4 * (1 - flash)) * bs;
      canvas.drawCircle(center, flashR, Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: (1 - flash) * 0.7),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: flashR)));
    }

    // Silver rim — ethereal flicker
    final rimFlicker = (sin(orbit * 2 * pi * 2.5) * 0.5 + 0.5).clamp(0.0, 1.0);
    canvas.drawCircle(center, r * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 + hold * 1.5 + rimFlicker * 0.5
      ..color = _lerpHold(spectralSilver, _gold).withValues(
          alpha: 0.04 + hold * 0.14 + rimFlicker * 0.04));
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
