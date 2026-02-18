import 'package:flutter/material.dart';

/// A premium page transition that prevents the brief flash of the previous
/// screen on slow devices. An opaque black container covers the screen from
/// frame 1, then the destination page fades + slides in on top.
class PremiumPageRoute<T> extends PageRouteBuilder<T> {
  PremiumPageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            // Opaque black fills the screen instantly — no flash of underlying route
            return ColoredBox(
              color: Colors.black,
              child: FadeTransition(
                opacity: curved,
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          opaque: true,
        );

  final Widget page;
}
