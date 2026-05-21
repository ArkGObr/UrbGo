import 'dart:math';

import 'package:flutter/material.dart';

class PitchMapPainter extends CustomPainter {
  final List<Offset> points;
  final double pulse;

  PitchMapPainter({required this.points, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y <= size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final routePaint = Paint()
      ..color = const Color(0xFF1BE7B8).withValues(alpha: 0.18)
      ..strokeWidth = 2;
    for (var i = 1; i < points.length; i++) {
      canvas.drawLine(points[i - 1], points[i], routePaint);
    }

    for (final point in points) {
      final glow = Paint()
        ..color = const Color(0xFF4FFFB0).withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawCircle(point, 8 + sin(pulse) * 4, glow);
      canvas.drawCircle(point, 3, Paint()..color = const Color(0xFF8DFF60));
    }
  }

  @override
  bool shouldRepaint(covariant PitchMapPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.pulse != pulse;
  }
}
