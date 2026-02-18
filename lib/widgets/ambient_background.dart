import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_theme.dart';
import '../services/theme_provider.dart';

class AmbientBackground extends StatelessWidget {

  const AmbientBackground({super.key});

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
            // Vignette: subtle edge darkening for depth
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.9,
                  colors: [
                    Colors.transparent,
                    td.scaffoldColor.withValues(alpha: 0.5),
                  ],
                  stops: const [0.45, 1.0],
                ),
              ),
            ),
            // Soft top highlight for lighting direction
            Align(
              alignment: const Alignment(0.0, -1.0),
              child: Container(
                width: double.infinity,
                height: 320,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      td.primaryColor.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
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
      case AppThemeId.midnightFrost:
        return [
          _OrbData(const Alignment(-0.8, -0.85), 400, const Color(0xFF4A7AAA), 0.18),
          _OrbData(const Alignment(0.85, -0.5), 340, td.primaryColor, 0.14),
          _OrbData(const Alignment(0.1, 0.85), 460, const Color(0xFF1A2A3A), 0.20),
        ];
      case AppThemeId.shadowRose:
        return [
          _OrbData(const Alignment(-0.75, -0.8), 380, td.primaryColor, 0.20),
          _OrbData(const Alignment(0.8, -0.4), 320, const Color(0xFF8A3050), 0.16),
          _OrbData(const Alignment(-0.2, 0.9), 450, const Color(0xFF2A0A18), 0.18),
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

