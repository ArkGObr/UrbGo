import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Transição suave de página com fade + slide de baixo para cima.
/// Ideal para navegações "push" dentro do app.
CustomTransitionPage<T> slideUpFadeTransition<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurveTween(curve: Curves.easeOutCubic);
      final fadeTween = Tween<double>(begin: 0.0, end: 1.0).chain(curve);
      final slideTween =
          Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
              .chain(curve);

      return FadeTransition(
        opacity: animation.drive(fadeTween),
        child: SlideTransition(
          position: animation.drive(slideTween),
          child: child,
        ),
      );
    },
  );
}

/// Transição de fade puro (mais sutil) — usada para troca de auth screens.
CustomTransitionPage<T> fadeThroughTransition<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 400),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: child,
      );
    },
  );
}

/// Transição de escala + fade — ideal para modais/detalhes.
CustomTransitionPage<T> scaleFadeTransition<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurveTween(curve: Curves.easeOutCubic);
      final scaleTween =
          Tween<double>(begin: 0.94, end: 1.0).chain(curve);
      final fadeTween =
          Tween<double>(begin: 0.0, end: 1.0).chain(curve);

      return FadeTransition(
        opacity: animation.drive(fadeTween),
        child: ScaleTransition(
          scale: animation.drive(scaleTween),
          child: child,
        ),
      );
    },
  );
}
