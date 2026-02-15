import 'package:flutter/material.dart';

/// A smooth fade-through page route that prevents the brief "flash"
/// visible with the default MaterialPageRoute slide transition.
class FadeRoute<T> extends PageRouteBuilder<T> {
  FadeRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 150),
        );

  final Widget page;
}
