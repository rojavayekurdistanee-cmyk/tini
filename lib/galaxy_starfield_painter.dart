import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'galaxy_star.dart';

class GalaxyStarfieldPainter extends CustomPainter {
  final List<GalaxyStar> stars;
  final Animation<double> clock;
  final Offset camera;
  final double zoom;
  final bool reduceMotion;

  GalaxyStarfieldPainter({
    required this.stars,
    required this.clock,
    required this.camera,
    required this.zoom,
    this.reduceMotion = false,
  }) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFF0F1720), BlendMode.src);
    final center = size.center(Offset.zero);
    // Fixed gradients are inexpensive soft nebulae, without image assets or blur.
    for (final cloud in [
      (const Offset(850, 1000), const Color(0xFF00695C), 500.0),
      (const Offset(1550, 1450), const Color(0xFF452780), 620.0),
      (const Offset(1250, 750), const Color(0xFF164C75), 400.0),
    ]) {
      final point = center + (cloud.$1 - camera) * zoom;
      final radius = cloud.$3 * zoom;
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              cloud.$2.withValues(alpha: 0.24),
              cloud.$2.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: point, radius: radius)),
      );
    }
    final time = reduceMotion ? 0.0 : clock.value * math.pi * 2;
    final paint = Paint();
    for (final star in stars) {
      final parallax = 0.7 + star.depth * 0.3;
      final drift = reduceMotion
          ? Offset.zero
          : Offset(
              math.sin(time + star.phase) * star.depth * 4,
              math.cos(time + star.phase) * star.depth * 3,
            );
      final point =
          center + (star.position - camera) * (zoom * parallax) + drift;
      final radius = star.radius * zoom * (0.6 + star.depth * 0.4);
      if (point.dx < -15 ||
          point.dy < -15 ||
          point.dx > size.width + 15 ||
          point.dy > size.height + 15) {
        continue;
      }
      final twinkle =
          0.7 + 0.3 * math.sin(time * star.twinkleSpeed + star.phase);
      final alpha = (star.brightness * twinkle).clamp(0.0, 1.0);
      if (star.radius > 2) {
        canvas.drawCircle(
          point,
          radius * 4,
          Paint()
            ..shader = RadialGradient(
              colors: [
                star.color.withValues(alpha: alpha * 0.22),
                star.color.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: point, radius: radius * 4)),
        );
      }
      canvas.drawCircle(
        point,
        radius,
        paint..color = star.color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant GalaxyStarfieldPainter oldDelegate) =>
      oldDelegate.stars != stars ||
      oldDelegate.camera != camera ||
      oldDelegate.zoom != zoom ||
      oldDelegate.reduceMotion != reduceMotion ||
      oldDelegate.clock != clock;
}
