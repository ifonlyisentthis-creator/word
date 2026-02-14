import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_theme.dart';
import '../services/theme_provider.dart';

class AmbientBackground extends StatefulWidget {

  const AmbientBackground({super.key});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final td = tp.themeData;
    final id = tp.themeId;

    final orbs = _orbsForTheme(id, td);

    return IgnorePointer(
      child: SizedBox.expand(
        child: Stack(
          children: [
            _BaseGradient(td: td),
            for (final o in orbs)
              _GlowOrb(
                alignment: o.alignment,
                size: o.size,
                color: o.color,
                opacity: o.opacity,
              ),
            // Animated floating particles for depth
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _AmbientParticlePainter(
                    progress: _ctrl.value,
                    color1: td.primaryColor,
                    color2: td.accentGlow,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

}

List<_OrbData> _orbsForTheme(AppThemeId id, AppThemeData td) {
    switch (id) {
      case AppThemeId.oledVoid:
        return [
          _OrbData(const Alignment(-0.85, -0.9), 420, td.primaryColor, 0.22),
          _OrbData(const Alignment(0.9, -0.6), 320, td.secondaryColor, 0.18),
          _OrbData(const Alignment(0.2, 0.9), 460, const Color(0xFF3A6E68), 0.14),
        ];
      case AppThemeId.obsidianSteel:
        return [
          _OrbData(const Alignment(-0.7, -0.8), 400, const Color(0xFF4A6A8A), 0.20),
          _OrbData(const Alignment(0.8, -0.4), 350, td.primaryColor, 0.16),
          _OrbData(const Alignment(-0.3, 0.85), 480, const Color(0xFF2A3A50), 0.18),
        ];
      case AppThemeId.midnightEmber:
        return [
          _OrbData(const Alignment(-0.8, -0.7), 380, td.primaryColor, 0.22),
          _OrbData(const Alignment(0.7, -0.5), 300, const Color(0xFFCC4422), 0.16),
          _OrbData(const Alignment(0.1, 0.9), 450, const Color(0xFF1A0A20), 0.20),
        ];
      case AppThemeId.deepOcean:
        return [
          _OrbData(const Alignment(-0.6, -0.85), 420, td.primaryColor, 0.20),
          _OrbData(const Alignment(0.85, -0.3), 340, const Color(0xFF0A6060), 0.18),
          _OrbData(const Alignment(-0.2, 0.8), 480, td.secondaryColor, 0.12),
        ];
      case AppThemeId.auroraNight:
        return [
          _OrbData(const Alignment(-0.9, -0.6), 440, td.primaryColor, 0.18),
          _OrbData(const Alignment(0.6, -0.8), 360, td.secondaryColor, 0.22),
          _OrbData(const Alignment(0.3, 0.85), 400, const Color(0xFF225544), 0.16),
          _OrbData(const Alignment(-0.5, 0.4), 280, const Color(0xFF6644AA), 0.12),
        ];
      case AppThemeId.cosmicDusk:
        return [
          _OrbData(const Alignment(-0.75, -0.8), 400, td.primaryColor, 0.20),
          _OrbData(const Alignment(0.8, -0.5), 320, td.secondaryColor, 0.18),
          _OrbData(const Alignment(0.0, 0.9), 460, const Color(0xFF2A1440), 0.22),
        ];
    }
}

class _OrbData {
  const _OrbData(this.alignment, this.size, this.color, this.opacity);
  final Alignment alignment;
  final double size;
  final Color color;
  final double opacity;
}

class _BaseGradient extends StatelessWidget {
  const _BaseGradient({required this.td});
  final AppThemeData td;

  @override
  Widget build(BuildContext context) {
    final base = td.scaffoldColor;
    final mid = Color.lerp(base, td.surfaceColor, 0.5)!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            td.surfaceColor,
            mid,
            base,
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.alignment,
    required this.size,
    required this.color,
    required this.opacity,
  });

  final Alignment alignment;
  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmbientParticlePainter extends CustomPainter {
  _AmbientParticlePainter({
    required this.progress,
    required this.color1,
    required this.color2,
  });

  final double progress;
  final Color color1;
  final Color color2;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    const count = 18;
    for (int i = 0; i < count; i++) {
      final seed = rng.nextDouble();
      final speed = 0.3 + seed * 0.7;
      final phase = (progress * speed + seed) % 1.0;

      final x = rng.nextDouble() * size.width;
      final yStart = size.height + 10;
      final yEnd = -20.0;
      final y = yStart + (yEnd - yStart) * phase;

      final fadeIn = (phase * 4).clamp(0.0, 1.0);
      final fadeOut = ((1 - phase) * 3).clamp(0.0, 1.0);
      final alpha = (fadeIn * fadeOut * (0.06 + seed * 0.08)).clamp(0.0, 1.0);

      final r = 1.0 + seed * 2.5;
      final c = Color.lerp(color1, color2, seed)!;

      canvas.drawCircle(
        Offset(x, y),
        r * 3,
        Paint()..color = c.withValues(alpha: alpha * 0.3),
      );
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = c.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientParticlePainter old) =>
      old.progress != progress ||
      old.color1 != color1 ||
      old.color2 != color2;
}

