import 'package:flutter/material.dart';

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: Stack(
          children: const [
            _BaseGradient(),
            _GlowOrb(
              alignment: Alignment(-0.85, -0.9),
              size: 420,
              color: Color(0xFFFFB85C),
              opacity: 0.28,
            ),
            _GlowOrb(
              alignment: Alignment(0.9, -0.6),
              size: 320,
              color: Color(0xFF5BC0B4),
              opacity: 0.22,
            ),
            _GlowOrb(
              alignment: Alignment(0.2, 0.9),
              size: 460,
              color: Color(0xFF3A6E68),
              opacity: 0.18,
            ),
          ],
        ),
      ),
    );
  }
}

class _BaseGradient extends StatelessWidget {
  const _BaseGradient();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0E0E0E),
            Color(0xFF090909),
            Color(0xFF050505),
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
              color.withOpacity(opacity),
              color.withOpacity(0),
            ],
          ),
        ),
      ),
    );
  }
}
