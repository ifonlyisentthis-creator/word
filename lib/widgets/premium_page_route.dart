import 'package:flutter/material.dart';

/// A premium fade+slide page transition that prevents the brief flash
/// of the previous screen on slow devices. The destination page fades in
/// with a subtle upward slide while the background stays dark.
class PremiumPageRoute<T> extends PageRouteBuilder<T> {
  PremiumPageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          opaque: true,
          barrierColor: Colors.black,
        );

  final Widget page;
}
