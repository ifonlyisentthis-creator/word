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
  // 1c. NEBULA HEART (Free) — Magnetic Ferrofluid
  //     A dark metallic sphere bristling with sharp spikes
  //     that cluster around two slowly rotating magnetic
  //     poles. Spikes rise and fall organically as the field
  //     sweeps past. Bright white-hot tips. Visible dipole
  //     field lines on hold. Spike storm burst on completion.
  //     Colors: deep blue-black, orchid, teal, white-hot.
  // ═══════════════════════════════════════════════════════
  void _paintNebulaHeart(
      Canvas canvas, Offset center, double r, double bs) {
    const orchid = Color(0xFFDA70D6);
    const teal = Color(0xFF00BFA5);
    const blueBlack = Color(0xFF060818);
    const hotWhite = Color(0xFFF0F0FF);

    // Magnetic aura — shifts with pole orientation
    final poleAngle = orbit * 2 * pi * 0.15;
    for (int g = 0; g < 2; g++) {
      final auraR = r * (1.6 + g * 0.35) * bs;
      final auraA = (0.04 + hold * 0.08) / (1 + g);
      final auraColor = g == 0 ? orchid : teal;
      canvas.drawCircle(center, auraR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(auraColor, _amber).withValues(alpha: auraA),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: auraR)));
    }

    // Main body — dark metallic sphere
    canvas.drawCircle(center, r * bs, Paint()
      ..shader = RadialGradient(colors: [
        blueBlack,
        _lerpHold(const Color(0xFF0C0A1E), const Color(0xFF0A0500)),
        _lerpHold(const Color(0xFF1A1040), _amber).withValues(alpha: 0.55),
      ], stops: const [0.0, 0.60, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r)));

    // FERROFLUID SPIKES — sharp projections that cluster at magnetic poles
    final spikeCount = 28 + (hold * 14).round();
    for (int i = 0; i < spikeCount; i++) {
      final angle = (i / spikeCount) * 2 * pi;

      // Two magnetic poles create a dipole field
      final pole1 = (cos(angle - poleAngle) * 0.5 + 0.5);
      final pole2 = (cos(angle - poleAngle - pi) * 0.5 + 0.5);
      final field = max(pole1 * pole1, pole2 * pole2);

      // Spike height: field strength + pulsation + hold amplification
      final breathMod = sin(breath * pi + i * 0.4) * 0.12;
      final spikeH = r * (0.04 + field * 0.32 + hold * field * 0.35
          + breathMod * 0.08) * bs;
      if (spikeH < r * 0.03) continue;

      // Base on sphere surface
      final bx = center.dx + cos(angle) * r * 0.90 * bs;
      final by = center.dy + sin(angle) * r * 0.90 * bs;
      // Tip
      final tx = center.dx + cos(angle) * (r * 0.90 * bs + spikeH);
      final ty = center.dy + sin(angle) * (r * 0.90 * bs + spikeH);

      final sAlpha = (0.25 + field * 0.55 + hold * 0.20).clamp(0.0, 1.0);
      final sWidth = 1.8 + field * 3.5 + hold * 2.0;

      // Glow layer
      canvas.drawLine(Offset(bx, by), Offset(tx, ty), Paint()
        ..color = _lerpHold(orchid, _gold).withValues(alpha: sAlpha * 0.25)
        ..strokeWidth = sWidth + 4
        ..strokeCap = StrokeCap.round);
      // Sharp spike
      canvas.drawLine(Offset(bx, by), Offset(tx, ty), Paint()
        ..color = _lerpHold(teal, _warmWhite).withValues(alpha: sAlpha)
        ..strokeWidth = max(sWidth * 0.35, 0.6)
        ..strokeCap = StrokeCap.round);
      // White-hot tip
      if (field > 0.4) {
        canvas.drawCircle(Offset(tx, ty), 1.2 + field * 2.0 + hold * 1.5,
            Paint()..color = _lerpHold(hotWhite, _warmWhite)
                .withValues(alpha: sAlpha * 0.75));
      }
    }

    // SURFACE SHIMMER — metallic reflection band that rotates
    canvas.drawCircle(center, r * 0.92 * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.10
      ..shader = SweepGradient(colors: [
        Colors.transparent,
        _lerpHold(const Color(0xFF2A2848), _amber).withValues(alpha: 0.20),
        Colors.transparent,
        _lerpHold(const Color(0xFF2A2848), _amber).withValues(alpha: 0.12),
        Colors.transparent,
      ], stops: const [0.0, 0.15, 0.4, 0.65, 1.0],
        transform: GradientRotation(poleAngle + pi * 0.5),
      ).createShader(Rect.fromCircle(center: center, radius: r * 0.92)));

    // DIPOLE FIELD LINES — visible on hold
    if (hold > 0.06) {
      for (int i = 0; i < 8; i++) {
        final fieldPath = Path();
        final spread = (i - 3.5) * 0.12;
        const steps = 36;
        for (int j = 0; j <= steps; j++) {
          final t = j / steps;
          final theta = poleAngle + t * pi;
          final dipoleR = r * (1.02 + sin(t * pi) *
              (0.25 + (i - 3.5).abs() * 0.06) * hold + spread * 0.3) * bs;
          final pt = center + Offset(cos(theta) * dipoleR, sin(theta) * dipoleR);
          if (j == 0) { fieldPath.moveTo(pt.dx, pt.dy); }
          else { fieldPath.lineTo(pt.dx, pt.dy); }
        }
        final fAlpha = (hold * 0.18 * (1 - (i - 3.5).abs() / 5)).clamp(0.0, 1.0);
        canvas.drawPath(fieldPath, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 + hold * 0.6
          ..color = _lerpHold(orchid, _gold).withValues(alpha: fAlpha)
          ..strokeCap = StrokeCap.round);
      }
    }

    // Core glow
    final coreR = r * (0.14 + breath * 0.04 + hold * 0.22);
    canvas.drawCircle(center, coreR, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(hotWhite, _warmWhite).withValues(alpha: 0.85),
        _lerpHold(orchid, _amber).withValues(alpha: 0.30),
        Colors.transparent,
      ], stops: const [0.0, 0.4, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: coreR)));

    // Specular — metallic top-left highlight
    final specR = r * 0.28;
    final specC = center + Offset(-r * 0.16, -r * 0.22);
    canvas.drawCircle(specC, specR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.12 + hold * 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: specC, radius: specR)));

    // SPIKE STORM on completion — all spikes fire outward then dissolve
    if (flash > 0) {
      final burstR = r * (1.0 + flash * 1.8) * bs;
      for (int i = 0; i < 24; i++) {
        final a = (i / 24) * 2 * pi + flash * 0.25;
        final start = center + Offset(cos(a) * r * 0.85, sin(a) * r * 0.85);
        final end = center + Offset(cos(a) * burstR, sin(a) * burstR);
        final bAlpha = ((1 - flash) * 0.55).clamp(0.0, 1.0);
        // Glow
        canvas.drawLine(start, end, Paint()
          ..color = _lerpHold(orchid, _gold).withValues(alpha: bAlpha * 0.3)
          ..strokeWidth = 4.0 * (1 - flash) + 1
          ..strokeCap = StrokeCap.round);
        // Sharp line
        canvas.drawLine(start, end, Paint()
          ..color = _lerpHold(teal, _warmWhite).withValues(alpha: bAlpha)
          ..strokeWidth = 1.5 * (1 - flash) + 0.3
          ..strokeCap = StrokeCap.round);
      }
      // Central flash
      final fR = r * (0.4 + flash * 0.6) * bs;
      canvas.drawCircle(center, fR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(hotWhite, _warmWhite).withValues(alpha: (1 - flash) * 0.55),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: fR)));
    }

    // Metallic rim — sweeping gradient
    canvas.drawCircle(center, r * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + hold * 2.0 + breath * 0.5
      ..shader = SweepGradient(colors: [
        _lerpHold(orchid, _gold).withValues(alpha: 0.0),
        _lerpHold(teal, _gold).withValues(alpha: 0.14 + hold * 0.22),
        _lerpHold(orchid, _amber).withValues(alpha: 0.06),
        _lerpHold(orchid, _gold).withValues(alpha: 0.0),
      ], stops: const [0.0, 0.3, 0.7, 1.0],
        transform: GradientRotation(poleAngle),
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
  // 4. PLASMA CELL (Pro) — Symbiotic Binary
  //     Two luminous sub-orbs orbit each other inside the
  //     sphere, connected by stretching plasma bridges.
  //     Interference patterns shimmer where halos overlap.
  //     On hold, the pair spirals inward and bridges multiply.
  //     On completion, they merge in a fusion explosion.
  //     Colors: rose-pink, electric coral, warm ivory.
  //     ★ PERFORMANCE: No MaskFilter.blur.
  // ═══════════════════════════════════════════════════════
  void _paintPlasmaCell(
      Canvas canvas, Offset center, double r, double bs) {
    const rosePink = Color(0xFFFF6B9D);
    const coral = Color(0xFFFF7F7F);
    const ivory = Color(0xFFFFF5EB);
    const deepRose = Color(0xFF200A12);
    const hotPink = Color(0xFFFF3388);
    const peach = Color(0xFFFFAA85);

    // Warm aura
    canvas.drawCircle(center, r * 1.7 * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(rosePink, _amber).withValues(alpha: 0.05 + hold * 0.10),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: r * 1.7)));

    // Main body — deep rose-black sphere
    canvas.drawCircle(center, r * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(deepRose, const Color(0xFF0A0500)),
        _lerpHold(const Color(0xFF25080F), const Color(0xFF1A0800)),
        _lerpHold(rosePink, _amber).withValues(alpha: 0.45),
      ], stops: const [0.0, 0.60, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r)));

    // BINARY ORBIT — two sub-orbs circling each other
    final orbitAngle = orbit * 2 * pi * 0.18;
    final orbitDist = r * (0.32 - hold * 0.18) * bs; // spirals inward on hold
    final orbA = center + Offset(cos(orbitAngle) * orbitDist,
        sin(orbitAngle) * orbitDist);
    final orbB = center + Offset(cos(orbitAngle + pi) * orbitDist,
        sin(orbitAngle + pi) * orbitDist);
    final subR = r * (0.16 + breath * 0.02) * bs;

    // Sub-orb halos (interference zone where they overlap glows brighter)
    final overlap = (1.0 - (orbA - orbB).distance / (subR * 4)).clamp(0.0, 1.0);
    for (final orb in [orbA, orbB]) {
      final isA = orb == orbA;
      final haloColor = isA
          ? _lerpHold(rosePink, _gold)
          : _lerpHold(coral, _amber);
      // Outer halo
      canvas.drawCircle(orb, subR * 2.5, Paint()
        ..shader = RadialGradient(colors: [
          haloColor.withValues(alpha: 0.12 + hold * 0.10 + overlap * 0.08),
          haloColor.withValues(alpha: 0.04),
          Colors.transparent,
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: orb, radius: subR * 2.5)));
      // Body
      canvas.drawCircle(orb, subR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(ivory, _warmWhite).withValues(alpha: 0.75),
          haloColor.withValues(alpha: 0.45),
          Colors.transparent,
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: orb, radius: subR)));
    }

    // INTERFERENCE SHIMMER — bright zone at the midpoint between orbs
    final midPt = Offset((orbA.dx + orbB.dx) / 2, (orbA.dy + orbB.dy) / 2);
    final interR = subR * (0.8 + overlap * 1.2 + hold * 0.5);
    final interAlpha = (0.06 + overlap * 0.18 + hold * 0.12).clamp(0.0, 1.0);
    canvas.drawCircle(midPt, interR, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(ivory, _warmWhite).withValues(alpha: interAlpha),
        _lerpHold(hotPink, _gold).withValues(alpha: interAlpha * 0.3),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: midPt, radius: interR)));

    // PLASMA BRIDGES — stretching arcs connecting the two orbs
    final bridgeCount = 3 + (hold * 4).round();
    for (int i = 0; i < bridgeCount; i++) {
      final spread = (i - (bridgeCount - 1) / 2.0) * 0.12;
      final bridgePath = Path();
      const steps = 24;
      for (int j = 0; j <= steps; j++) {
        final t = j / steps;
        // Quadratic Bezier between orbA and orbB with perpendicular offset
        final lerped = Offset(
          orbA.dx + (orbB.dx - orbA.dx) * t,
          orbA.dy + (orbB.dy - orbA.dy) * t,
        );
        // Perpendicular bulge — each bridge has different curvature
        final perpAngle = orbitAngle + pi / 2;
        final bulge = sin(t * pi) * r * (0.10 + spread + hold * 0.06);
        // Add a living wave along the bridge
        final wave = sin(t * pi * 4 + orbit * 8 + i * 1.5) * r * 0.03;
        final pt = Offset(
          lerped.dx + cos(perpAngle) * (bulge + wave),
          lerped.dy + sin(perpAngle) * (bulge + wave),
        );
        if (j == 0) { bridgePath.moveTo(pt.dx, pt.dy); }
        else { bridgePath.lineTo(pt.dx, pt.dy); }
      }
      final bColor = i.isEven
          ? _lerpHold(rosePink, _gold)
          : _lerpHold(peach, _amber);
      final bAlpha = (0.08 + hold * 0.20).clamp(0.0, 1.0);
      // Glow
      canvas.drawPath(bridgePath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 + hold * 3.0
        ..color = bColor.withValues(alpha: bAlpha * 0.3)
        ..strokeCap = StrokeCap.round);
      // Core
      canvas.drawPath(bridgePath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + hold * 1.0
        ..color = _lerpHold(ivory, _warmWhite).withValues(alpha: bAlpha)
        ..strokeCap = StrokeCap.round);
    }

    // ENERGY PARTICLES — bright motes traveling along bridges
    for (int i = 0; i < 10; i++) {
      final phase = (orbit * (1.2 + i * 0.13) + i * 0.37) % 1.0;
      final t = phase;
      final lerped = Offset(
        orbA.dx + (orbB.dx - orbA.dx) * t,
        orbA.dy + (orbB.dy - orbA.dy) * t,
      );
      final perpAngle = orbitAngle + pi / 2;
      final bulge = sin(t * pi) * r * 0.10;
      final pt = Offset(
        lerped.dx + cos(perpAngle) * bulge,
        lerped.dy + sin(perpAngle) * bulge,
      );
      final fadeIn = (phase * 4).clamp(0.0, 1.0);
      final fadeOut = ((1 - phase) * 4).clamp(0.0, 1.0);
      final pAlpha = (fadeIn * fadeOut * (0.30 + hold * 0.40)).clamp(0.0, 1.0);
      if (pAlpha > 0.02) {
        canvas.drawCircle(pt, 1.5 + hold * 1.0,
            Paint()..color = _lerpHold(ivory, _warmWhite).withValues(alpha: pAlpha));
      }
    }

    // ORBITAL TRAIL — ghostly afterimage ring showing the orbit path
    canvas.drawCircle(center, orbitDist, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6 + hold * 0.8
      ..color = _lerpHold(rosePink, _gold)
          .withValues(alpha: 0.04 + hold * 0.08));

    // TIDAL RIPPLES on hold — expanding rings from each sub-orb
    if (hold > 0.08) {
      for (final orb in [orbA, orbB]) {
        for (int rp = 0; rp < 2; rp++) {
          final rpPhase = (orbit * 1.8 + rp * 0.5) % 1.0;
          final rpR = subR * (1.0 + rpPhase * 2.5 * hold);
          final rpAlpha = ((1 - rpPhase) * hold * 0.22).clamp(0.0, 1.0);
          canvas.drawCircle(orb, rpR, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 * (1 - rpPhase) + 0.3
            ..color = _lerpHold(hotPink, _gold).withValues(alpha: rpAlpha));
        }
      }
    }

    // Specular highlight
    final specR = r * 0.26;
    final specC = center + Offset(-r * 0.18, -r * 0.22);
    canvas.drawCircle(specC, specR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.10 + hold * 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: specC, radius: specR)));

    // FUSION EXPLOSION on completion — orbs merge at center
    if (flash > 0) {
      final mergeR = r * (0.2 + flash * 1.6) * bs;
      // Brilliant merger flash
      canvas.drawCircle(center, mergeR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(ivory, _warmWhite).withValues(alpha: (1 - flash) * 0.55),
          _lerpHold(rosePink, _gold).withValues(alpha: (1 - flash) * 0.25),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: mergeR)));
      // Twin expanding rings from merge point
      for (int i = 0; i < 2; i++) {
        final ringPhase = (flash + i * 0.12).clamp(0.0, 1.0);
        final ringR = r * (0.3 + ringPhase * 1.5) * bs;
        final ringAlpha = ((1 - ringPhase) * 0.40).clamp(0.0, 1.0);
        final ringColor = i == 0 ? rosePink : coral;
        canvas.drawCircle(center, ringR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - ringPhase) + 0.5
          ..color = _lerpHold(ringColor, _gold).withValues(alpha: ringAlpha));
      }
    }

    // Soft rose rim
    canvas.drawCircle(center, r * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + hold * 2.0 + breath * 0.5
      ..color = _lerpHold(rosePink, _gold)
          .withValues(alpha: 0.10 + hold * 0.22 + breath * 0.04));
  }

  // ═══════════════════════════════════════════════════════
  // 5. TOXIC CORE (Lifetime) — Gyroscopic Containment
  //     Three luminous rings at orthogonal angles spin around
  //     a volatile, pulsing energy core like a gyroscope.
  //     Containment breaches create flares between ring gaps.
  //     On hold, rings wobble and core destabilizes.
  //     On completion, total breach then re-collapse.
  //     Colors: molten orange, warning red, containment cyan.
  // ═══════════════════════════════════════════════════════
  void _paintToxicCore(
      Canvas canvas, Offset center, double r, double bs) {
    const moltenOrange = Color(0xFFFF6600);
    const warningRed = Color(0xFFFF2200);
    const containCyan = Color(0xFF00E5FF);
    const coreWhite = Color(0xFFFFF8F0);

    // Danger aura — pulsing warm glow
    final dangerPulse = sin(breath * pi) * 0.04;
    canvas.drawCircle(center, r * 1.8 * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(moltenOrange, _amber).withValues(alpha: 0.08 + hold * 0.14 + dangerPulse),
        _lerpHold(warningRed, _gold).withValues(alpha: 0.03),
        Colors.transparent,
      ], stops: const [0.0, 0.45, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r * 1.8)));

    // Main body — dark containment vessel
    canvas.drawCircle(center, r * bs, Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF080808),
        _lerpHold(const Color(0xFF100808), const Color(0xFF0A0500)),
        _lerpHold(const Color(0xFF2A1208), _amber).withValues(alpha: 0.50),
      ], stops: const [0.0, 0.55, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r)));

    // GYROSCOPIC RINGS — three containment rings at different angles
    // Each ring is an ellipse (circle scaled on one axis) rotating independently
    final wobble = hold * 0.15; // rings destabilize on hold
    final ringConfigs = [
      // [speed, tiltX, tiltY, color]
      [0.20, 0.35 + wobble * sin(orbit * 5), 1.0, containCyan],
      [0.14, 1.0, 0.30 + wobble * cos(orbit * 4.3), moltenOrange],
      [0.17, 0.70 + wobble * sin(orbit * 6.1), 0.70 + wobble * cos(orbit * 3.7), warningRed],
    ];

    for (int ring = 0; ring < 3; ring++) {
      final speed = ringConfigs[ring][0] as double;
      final scaleX = ringConfigs[ring][1] as double;
      final scaleY = ringConfigs[ring][2] as double;
      final ringColor = ringConfigs[ring][3] as Color;
      final rotation = orbit * 2 * pi * speed + ring * pi / 3;

      final ringR = r * (0.82 + ring * 0.04) * bs;
      final ringAlpha = (0.18 + hold * 0.28 + breath * 0.04).clamp(0.0, 1.0);
      final ringWidth = 1.2 + hold * 1.8;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      canvas.scale(scaleX, scaleY);

      // Glow ring
      canvas.drawCircle(Offset.zero, ringR, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth + 4.0
        ..color = _lerpHold(ringColor, _gold).withValues(alpha: ringAlpha * 0.20));
      // Sharp ring
      canvas.drawCircle(Offset.zero, ringR, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..color = _lerpHold(ringColor, _gold).withValues(alpha: ringAlpha));

      // Ring nodes — bright points at cardinal positions
      for (int n = 0; n < 4; n++) {
        final nodeAngle = (n / 4) * 2 * pi;
        final nodePos = Offset(cos(nodeAngle) * ringR, sin(nodeAngle) * ringR);
        canvas.drawCircle(nodePos, 2.0 + hold * 1.5, Paint()
          ..color = _lerpHold(coreWhite, _warmWhite).withValues(alpha: ringAlpha * 0.7));
      }

      canvas.restore();
    }

    // CONTAINMENT BREACHES — energy flares escaping between ring gaps
    final breachCount = 4 + (hold * 8).round();
    final bRng = Random(42);
    for (int i = 0; i < breachCount; i++) {
      final bAngle = (i / breachCount) * 2 * pi + orbit * 1.3 + bRng.nextDouble();
      final bPhase = (orbit * (0.8 + bRng.nextDouble() * 0.6) + i * 0.31) % 1.0;
      final bDist = r * (0.80 + bPhase * 0.5 * (0.3 + hold * 0.7)) * bs;
      final bPos = center + Offset(cos(bAngle) * bDist, sin(bAngle) * bDist);
      final fadeIn = (bPhase * 3).clamp(0.0, 1.0);
      final fadeOut = ((1 - bPhase) * 2.5).clamp(0.0, 1.0);
      final bAlpha = (fadeIn * fadeOut * (0.10 + hold * 0.50)).clamp(0.0, 1.0);
      if (bAlpha > 0.02) {
        // Flare glow
        canvas.drawCircle(bPos, 3.0 + hold * 2.5, Paint()
          ..color = _lerpHold(moltenOrange, _gold).withValues(alpha: bAlpha * 0.25));
        // Bright spark
        canvas.drawCircle(bPos, 1.0 + bRng.nextDouble() * 1.5, Paint()
          ..color = _lerpHold(coreWhite, _warmWhite).withValues(alpha: bAlpha));
      }
    }

    // VOLATILE CORE — pulsing dangerously, bigger pulse on hold
    final coreR = r * (0.18 + breath * 0.05 + hold * 0.22 + dangerPulse * 2);
    // Core outer glow
    canvas.drawCircle(center, coreR * 2.5, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(moltenOrange, _gold).withValues(alpha: 0.15 + hold * 0.12),
        _lerpHold(warningRed, _amber).withValues(alpha: 0.05),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: coreR * 2.5)));
    // Core body
    canvas.drawCircle(center, coreR, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(coreWhite, _warmWhite).withValues(alpha: 0.90),
        _lerpHold(moltenOrange, _gold).withValues(alpha: 0.50),
        Colors.transparent,
      ], stops: const [0.0, 0.45, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: coreR)));

    // Specular
    final specR = r * 0.22;
    final specC = center + Offset(-r * 0.18, -r * 0.22);
    canvas.drawCircle(specC, specR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.08 + hold * 0.05),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: specC, radius: specR)));

    // WARNING PULSE RINGS on hold — concentric alarm waves
    if (hold > 0.06) {
      for (int i = 0; i < 3; i++) {
        final pulsePhase = (orbit * 1.8 + i * 0.33) % 1.0;
        final pulseR = r * (0.25 + pulsePhase * 0.65 * hold) * bs;
        final pulseAlpha = ((1 - pulsePhase) * hold * 0.25).clamp(0.0, 1.0);
        final pulseColor = i == 1 ? containCyan : warningRed;
        canvas.drawCircle(center, pulseR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * (1 - pulsePhase) + 0.3
          ..color = _lerpHold(pulseColor, _gold).withValues(alpha: pulseAlpha));
      }
    }

    // TOTAL BREACH on completion — rings explode outward, core flashes
    if (flash > 0) {
      // Expanding containment rings shatter outward
      for (int ring = 0; ring < 3; ring++) {
        final shatterR = r * (0.85 + flash * 1.5 + ring * 0.1) * bs;
        final shatterAlpha = ((1 - flash) * 0.45).clamp(0.0, 1.0);
        final shatterColor = ring == 0 ? containCyan : ring == 1 ? moltenOrange : warningRed;
        canvas.drawCircle(center, shatterR, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - flash) + 0.3
          ..color = _lerpHold(shatterColor, _gold).withValues(alpha: shatterAlpha));
      }
      // Core energy burst
      final burstR = r * (0.3 + flash * 1.2) * bs;
      canvas.drawCircle(center, burstR, Paint()
        ..shader = RadialGradient(colors: [
          _lerpHold(coreWhite, _warmWhite).withValues(alpha: (1 - flash) * 0.60),
          _lerpHold(moltenOrange, _gold).withValues(alpha: (1 - flash) * 0.25),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: burstR)));
    }

    // Containment rim — alternating cyan/orange sweep
    canvas.drawCircle(center, r * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 + hold * 2.5
      ..shader = SweepGradient(colors: [
        _lerpHold(containCyan, _gold).withValues(alpha: 0.0),
        _lerpHold(containCyan, _gold).withValues(alpha: 0.18 + hold * 0.25),
        _lerpHold(moltenOrange, _amber).withValues(alpha: 0.08),
        _lerpHold(containCyan, _gold).withValues(alpha: 0.0),
      ], stops: const [0.0, 0.3, 0.7, 1.0],
        transform: GradientRotation(orbit * 2 * pi * 0.35),
      ).createShader(Rect.fromCircle(center: center, radius: r * bs)));
  }

  // ═══════════════════════════════════════════════════════
  // 6. CRYSTAL ASCEND (Lifetime) — Sacred Geometry Bloom
  //     Nested rotating polyhedra (triangle, square, pentagon,
  //     hexagon) at different scales and speeds, each with
  //     prismatic edges. Vertices glow and connect with light
  //     beams. On hold, geometry unfolds/flowers outward.
  //     On completion, all vertices burst with rainbow rays.
  //     Colors: prismatic spectrum, ice-blue, violet, gold.
  // ═══════════════════════════════════════════════════════
  void _paintCrystalAscend(
      Canvas canvas, Offset center, double r, double bs) {
    const iceBlue = Color(0xFF87CEEB);
    const crystalViolet = Color(0xFF9370DB);
    const prismGold = Color(0xFFFFD700);
    const deepCrystal = Color(0xFF0A1020);

    // Prismatic aura — hue-shifting
    final hueBase = orbit * 2 * pi;
    final auraColor = HSLColor.fromAHSL(1, (hueBase * 180 / pi) % 360, 0.55, 0.60).toColor();
    canvas.drawCircle(center, r * 1.7 * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(auraColor, _amber).withValues(alpha: 0.06 + hold * 0.12),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: r * 1.7)));

    // Main body — deep crystal with glassy edge
    canvas.drawCircle(center, r * bs, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(deepCrystal, const Color(0xFF0A0500)),
        _lerpHold(const Color(0xFF141830), const Color(0xFF1A0800)),
        _lerpHold(iceBlue, _amber).withValues(alpha: 0.55),
      ], stops: const [0.0, 0.55, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: r)));

    // NESTED POLYHEDRA — 4 shapes rotating independently
    // [sides, speed, scale, hueOffset]
    final shapes = [
      [3, 0.22, 0.28 + hold * 0.08, 0.0],    // triangle (innermost)
      [4, -0.16, 0.42 + hold * 0.10, 90.0],   // square
      [5, 0.12, 0.58 + hold * 0.12, 180.0],   // pentagon
      [6, -0.09, 0.76 + hold * 0.14, 270.0],  // hexagon (outermost)
    ];

    // Collect all vertex positions for inter-shape light beams
    final allVertices = <Offset>[];
    final allHues = <double>[];

    for (int s = 0; s < shapes.length; s++) {
      final sides = (shapes[s][0] as int);
      final speed = shapes[s][1] as double;
      final scale = shapes[s][2] as double;
      final hueOff = shapes[s][3] as double;

      final rotation = orbit * 2 * pi * speed + breath * 0.15;
      final shapeR = r * scale * bs;
      final shapeAlpha = (0.15 + hold * 0.25 + breath * 0.03).clamp(0.0, 1.0);

      final path = Path();
      final vertices = <Offset>[];
      for (int v = 0; v < sides; v++) {
        final va = (v / sides) * 2 * pi + rotation;
        final vp = center + Offset(cos(va) * shapeR, sin(va) * shapeR);
        vertices.add(vp);
        allVertices.add(vp);
        final vHue = (hueOff + v * (360 / sides) + orbit * 60) % 360;
        allHues.add(vHue);
        if (v == 0) { path.moveTo(vp.dx, vp.dy); }
        else { path.lineTo(vp.dx, vp.dy); }
      }
      path.close();

      // Edge hue — shifts per shape
      final edgeHue = (hueOff + orbit * 90) % 360;
      final edgeColor = HSLColor.fromAHSL(1, edgeHue, 0.65, 0.65).toColor();

      // Fill — very subtle prismatic
      canvas.drawPath(path, Paint()
        ..color = _lerpHold(edgeColor, _gold).withValues(alpha: shapeAlpha * 0.08));

      // Edge glow
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 + hold * 2.0
        ..color = _lerpHold(edgeColor, _gold).withValues(alpha: shapeAlpha * 0.25)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
      // Sharp edge
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 + hold * 0.8
        ..color = _lerpHold(edgeColor, _gold).withValues(alpha: shapeAlpha)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);

      // Vertex dots — bright prismatic points
      for (int v = 0; v < vertices.length; v++) {
        final vHue = (hueOff + v * (360 / sides) + orbit * 60) % 360;
        final vColor = HSLColor.fromAHSL(1, vHue, 0.7, 0.75).toColor();
        // Glow
        canvas.drawCircle(vertices[v], 3.0 + hold * 2.0, Paint()
          ..color = _lerpHold(vColor, _gold).withValues(alpha: shapeAlpha * 0.30));
        // Bright dot
        canvas.drawCircle(vertices[v], 1.2 + hold * 0.8, Paint()
          ..color = _lerpHold(vColor, _warmWhite).withValues(alpha: shapeAlpha * 0.85));
      }
    }

    // INTER-SHAPE LIGHT BEAMS — connect nearest vertices between layers
    if (hold > 0.04) {
      final beamAlpha = (hold * 0.22).clamp(0.0, 1.0);
      // Connect vertices of adjacent shapes
      int idx = 0;
      for (int s = 0; s < shapes.length - 1; s++) {
        final sides1 = shapes[s][0] as int;
        final sides2 = shapes[s + 1][0] as int;
        final start1 = idx;
        final start2 = idx + sides1;
        // Connect each vertex of inner shape to nearest vertex of outer shape
        for (int v = 0; v < sides1; v++) {
          final from = allVertices[start1 + v];
          // Find nearest vertex in next shape
          var minDist = double.infinity;
          var nearest = start2;
          for (int w = 0; w < sides2; w++) {
            final d = (from - allVertices[start2 + w]).distance;
            if (d < minDist) { minDist = d; nearest = start2 + w; }
          }
          final to = allVertices[nearest];
          final beamHue = (allHues[start1 + v] + allHues[nearest]) / 2;
          final beamColor = HSLColor.fromAHSL(1, beamHue % 360, 0.6, 0.70).toColor();
          canvas.drawLine(from, to, Paint()
            ..color = _lerpHold(beamColor, _gold).withValues(alpha: beamAlpha)
            ..strokeWidth = 0.5 + hold * 0.6
            ..strokeCap = StrokeCap.round);
        }
        idx += sides1;
      }
    }

    // ORBITING PRISMATIC MOTES — tiny spectrum particles circling the geometry
    final gRng = Random(88);
    for (int i = 0; i < 16; i++) {
      final seed = gRng.nextDouble();
      final moteAngle = orbit * 2 * pi * (0.15 + seed * 0.12) + i * (2 * pi / 16);
      final moteDist = r * (0.30 + seed * 0.50 + sin(orbit * 4 + i) * 0.05) * bs;
      final motePos = center + Offset(cos(moteAngle) * moteDist, sin(moteAngle) * moteDist);
      final moteHue = (seed * 360 + orbit * 120) % 360;
      final moteColor = HSLColor.fromAHSL(1, moteHue, 0.65, 0.75).toColor();
      final moteAlpha = (0.15 + hold * 0.30 + breath * 0.05).clamp(0.0, 1.0);
      canvas.drawCircle(motePos, 1.0 + seed * 1.0, Paint()
        ..color = _lerpHold(moteColor, _gold).withValues(alpha: moteAlpha));
    }

    // Core — white with prismatic tint
    final coreR = r * (0.14 + breath * 0.04 + hold * 0.18);
    canvas.drawCircle(center, coreR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.85),
        _lerpHold(auraColor, _gold).withValues(alpha: 0.30),
        Colors.transparent,
      ], stops: const [0.0, 0.45, 1.0])
          .createShader(Rect.fromCircle(center: center, radius: coreR)));

    // Specular
    final specR = r * 0.24;
    final specC = center + Offset(-r * 0.16, -r * 0.20);
    canvas.drawCircle(specC, specR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.14 + hold * 0.08),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: specC, radius: specR)));

    // RAINBOW VERTEX BURST on completion — all vertices shoot rays outward
    if (flash > 0) {
      for (int i = 0; i < allVertices.length; i++) {
        final v = allVertices[i];
        final dir = v - center;
        final dirLen = dir.distance;
        if (dirLen < 0.01) continue;
        final norm = dir / dirLen;
        final rayLen = r * (0.3 + flash * 1.2) * bs;
        final rayEnd = v + norm * rayLen;
        final rayHue = allHues[i];
        final rayColor = HSLColor.fromAHSL(1, rayHue % 360, 0.75, 0.70).toColor();
        final rayAlpha = ((1 - flash) * 0.50).clamp(0.0, 1.0);
        canvas.drawLine(v, rayEnd, Paint()
          ..color = _lerpHold(rayColor, _gold).withValues(alpha: rayAlpha)
          ..strokeWidth = 2.0 * (1 - flash) + 0.3
          ..strokeCap = StrokeCap.round);
      }
      // Central white flash
      final burstR = r * (0.3 + flash * 0.7) * bs;
      canvas.drawCircle(center, burstR, Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: (1 - flash) * 0.55),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: burstR)));
    }

    // Prismatic rim — spectrum sweep
    canvas.drawCircle(center, r * bs, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 + hold * 2.0
      ..shader = SweepGradient(colors: [
        _lerpHold(iceBlue, _gold).withValues(alpha: 0.0),
        _lerpHold(crystalViolet, _amber).withValues(alpha: 0.15 + hold * 0.22),
        _lerpHold(prismGold, _gold).withValues(alpha: 0.10 + hold * 0.15),
        _lerpHold(iceBlue, _gold).withValues(alpha: 0.0),
      ], stops: const [0.0, 0.3, 0.65, 1.0],
        transform: GradientRotation(orbit * 2 * pi * 0.8),
      ).createShader(Rect.fromCircle(center: center, radius: r * bs)));
  }

  // ═══════════════════════════════════════════════════════
  // 7. INFINITY WELL (Pro) — Tesseract Projection
  //     A true 4D hypercube rotating through 3D→2D space.
  //     16 vertices connected by 32 edges, color-coded by
  //     dimension (X=pink, Y=blue, Z=violet, W=cyan).
  //     Rotates in XW and YZ planes simultaneously, creating
  //     impossible folding geometry. Edge-traveling particles.
  //     Square-shaped dimensional ripples on hold.
  //     Dimensional collapse/rebirth on completion.
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

    // TESSERACT — 4D hypercube projected to 2D
    // 16 vertices: all combinations of (±1, ±1, ±1, ±1)
    final rotSpeed = 0.12 + hold * 0.08;
    final aXW = orbit * 2 * pi * rotSpeed;
    final aYZ = orbit * 2 * pi * rotSpeed * 0.7 + pi * 0.3;
    final aXY = orbit * 2 * pi * rotSpeed * 0.4;

    final projected = <Offset>[];
    for (int i = 0; i < 16; i++) {
      var x = ((i & 1) == 0) ? -1.0 : 1.0;
      var y = ((i & 2) == 0) ? -1.0 : 1.0;
      var z = ((i & 4) == 0) ? -1.0 : 1.0;
      var w = ((i & 8) == 0) ? -1.0 : 1.0;

      // Rotate XW plane
      final nx = x * cos(aXW) - w * sin(aXW);
      final nw = x * sin(aXW) + w * cos(aXW);
      x = nx; w = nw;
      // Rotate YZ plane
      final ny = y * cos(aYZ) - z * sin(aYZ);
      final nz = y * sin(aYZ) + z * cos(aYZ);
      y = ny; z = nz;
      // Rotate XY plane
      final nx2 = x * cos(aXY) - y * sin(aXY);
      final ny2 = x * sin(aXY) + y * cos(aXY);
      x = nx2; y = ny2;

      // Perspective projection 4D → 2D
      const camDist = 3.5;
      final pw = 1.0 / (camDist - w);
      final pz = 1.0 / (camDist - z * 0.3);
      final scale = r * 0.34 * bs * pw * pz;
      projected.add(center + Offset(x * scale, y * scale));
    }

    // Build edge list: vertices differing by exactly 1 bit = adjacent
    final edges = <List<int>>[];
    for (int i = 0; i < 16; i++) {
      for (int j = i + 1; j < 16; j++) {
        final xor = i ^ j;
        if (xor != 0 && (xor & (xor - 1)) == 0) {
          edges.add([i, j, xor]);
        }
      }
    }

    // Draw edges — colored by dimension
    final edgeAlpha = (0.15 + hold * 0.30 + breath * 0.03).clamp(0.0, 1.0);
    for (final edge in edges) {
      final a = projected[edge[0]];
      final b = projected[edge[1]];
      final dim = edge[2];

      final Color edgeColor;
      if (dim == 1) { edgeColor = _lerpHold(neonPink, _gold); }
      else if (dim == 2) { edgeColor = _lerpHold(electricBlue, _amber); }
      else if (dim == 4) { edgeColor = _lerpHold(deepViolet, _warmWhite); }
      else { edgeColor = _lerpHold(dimensionCyan, _gold); }

      // Glow
      canvas.drawLine(a, b, Paint()
        ..color = edgeColor.withValues(alpha: edgeAlpha * 0.22)
        ..strokeWidth = 3.0 + hold * 2.5
        ..strokeCap = StrokeCap.round);
      // Sharp edge
      canvas.drawLine(a, b, Paint()
        ..color = edgeColor.withValues(alpha: edgeAlpha)
        ..strokeWidth = 0.7 + hold * 0.8
        ..strokeCap = StrokeCap.round);
    }

    // Vertex dots — bright points at each 4D corner
    for (int i = 0; i < projected.length; i++) {
      final v = projected[i];
      if ((v - center).distance > r * 1.5) continue;
      canvas.drawCircle(v, 2.2 + hold * 1.5, Paint()
        ..color = _lerpHold(dimensionCyan, _gold)
            .withValues(alpha: edgeAlpha * 0.28));
      canvas.drawCircle(v, 0.9 + hold * 0.5, Paint()
        ..color = Colors.white.withValues(alpha: edgeAlpha * 0.80));
    }

    // EDGE TRAVELERS — bright particles moving along tesseract edges
    final tRng = Random(77);
    for (int i = 0; i < 14; i++) {
      final eIdx = (i * 3 + (orbit * 40).floor()) % edges.length;
      final edge = edges[eIdx];
      final a = projected[edge[0]];
      final b = projected[edge[1]];
      final phase = (orbit * (1.5 + tRng.nextDouble() * 0.8) + i * 0.27) % 1.0;
      final pt = Offset(
        a.dx + (b.dx - a.dx) * phase,
        a.dy + (b.dy - a.dy) * phase,
      );
      final pAlpha = (0.22 + hold * 0.40).clamp(0.0, 1.0);
      canvas.drawCircle(pt, 1.5 + hold * 1.0, Paint()
        ..color = Colors.white.withValues(alpha: pAlpha));
    }

    // Core — bright dimensional singularity
    final coreR = r * (0.08 + breath * 0.03 + hold * 0.14);
    canvas.drawCircle(center, coreR * 2.5, Paint()
      ..shader = RadialGradient(colors: [
        _lerpHold(dimensionCyan, _warmWhite).withValues(alpha: 0.10 + hold * 0.08),
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

    // SQUARE-SHAPED DIMENSIONAL RIPPLES on hold
    if (hold > 0.06) {
      for (int i = 0; i < 3; i++) {
        final rpPhase = (orbit * 1.6 + i * 0.33) % 1.0;
        final rpR = r * (0.15 + rpPhase * 0.70 * hold) * bs;
        final rpAlpha = ((1 - rpPhase) * hold * 0.22).clamp(0.0, 1.0);
        final rpPath = Path();
        for (int v = 0; v < 4; v++) {
          final va = (v / 4) * 2 * pi + aXY + pi / 4;
          final vp = center + Offset(cos(va) * rpR, sin(va) * rpR);
          if (v == 0) { rpPath.moveTo(vp.dx, vp.dy); }
          else { rpPath.lineTo(vp.dx, vp.dy); }
        }
        rpPath.close();
        final rpColor = i.isEven ? neonPink : electricBlue;
        canvas.drawPath(rpPath, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * (1 - rpPhase) + 0.3
          ..color = _lerpHold(rpColor, _gold).withValues(alpha: rpAlpha)
          ..strokeJoin = StrokeJoin.round);
      }
    }

    // DIMENSIONAL COLLAPSE on completion
    if (flash > 0) {
      // Vertices converge then explode outward
      for (int i = 0; i < projected.length; i++) {
        final v = projected[i];
        final dir = v - center;
        final t = flash < 0.5 ? 1.0 - flash * 2 : (flash - 0.5) * 2;
        final flashPt = flash < 0.5
            ? center + dir * t
            : center + dir * t * 2.0;
        final fAlpha = ((1 - flash) * 0.55).clamp(0.0, 1.0);
        canvas.drawCircle(flashPt, 2.0 * (1 - flash) + 0.5, Paint()
          ..color = _lerpHold(dimensionCyan, _warmWhite)
              .withValues(alpha: fAlpha));
      }
      // Central white flash
      final fR = r * (0.5 * (1 - flash)) * bs;
      canvas.drawCircle(center, fR, Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: (1 - flash) * 0.80),
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
        _lerpHold(electricBlue, _gold).withValues(alpha: 0.14 + hold * 0.22),
        _lerpHold(deepViolet, _amber).withValues(alpha: 0.05),
        _lerpHold(neonPink, _gold).withValues(alpha: 0.0),
      ], stops: const [0.0, 0.3, 0.65, 1.0],
        transform: GradientRotation(orbit * 2 * pi * 0.25),
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
