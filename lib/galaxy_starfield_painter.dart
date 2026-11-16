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
    // CustomPainter does not clip automatically: keep the sky below the tabs.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
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
      final extent = radius * (star.hasRays ? 10 : 4);
      if (point.dx < -extent ||
          point.dy < -extent ||
          point.dx > size.width + extent ||
          point.dy > size.height + extent) {
        continue;
      }
      // Gentle 8–24 second cycles, each with its own phase.
      final twinkle =
          0.86 + 0.14 * math.sin(time * star.twinkleSpeed + star.phase);
      final alpha = (star.brightness * twinkle).clamp(0.0, 1.0);
      if (star.hasRays || star.radius > 1.1) {
        final haloRadius = radius * (star.hasRays ? 7 : 3.5);
        canvas.drawCircle(
          point,
          haloRadius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                star.color.withValues(
                  alpha: alpha * (star.hasRays ? 0.4 : 0.18),
                ),
                star.color.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: point, radius: haloRadius)),
        );
      }
      if (star.hasRays) {
        final length = radius * (7 + twinkle * 2);
        _drawRay(canvas, point, Offset(length, 0), alpha * 0.85, zoom);
        _drawRay(canvas, point, Offset(0, length * 1.2), alpha * 0.85, zoom);
        if (star.hasDiagonalRays) {
          _drawRay(
            canvas,
            point,
            Offset(length * 0.45, length * 0.45),
            alpha * 0.3,
            zoom,
          );
          _drawRay(
            canvas,
            point,
            Offset(length * 0.45, -length * 0.45),
            alpha * 0.3,
            zoom,
          );
        }
      }
      // The colored halo surrounds a white photographic point of light.
      canvas.drawCircle(
        point,
        radius,
        paint
          ..color = Colors.white.withValues(
            alpha: star.hasRays ? 0.95 + 0.05 * twinkle : alpha,
          ),
      );
      if (star.hasRays) {
        canvas.drawCircle(point, radius * 0.5, paint..color = Colors.white);
      }
    }
    canvas.restore();
  }

  void _drawRay(
    Canvas canvas,
    Offset center,
    Offset vector,
    double alpha,
    double zoom,
  ) {
    final start = center - vector;
    final end = center + vector;
    canvas.drawLine(
      start,
      end,
      Paint()
        ..strokeWidth = (0.6 * zoom).clamp(0.5, 1.2)
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
          ],
          begin: Alignment(-vector.dx.sign, -vector.dy.sign),
          end: Alignment(vector.dx.sign, vector.dy.sign),
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromPoints(start, end).inflate(0.01)),
    );
  }

  @override
  bool shouldRepaint(covariant GalaxyStarfieldPainter oldDelegate) =>
      oldDelegate.stars != stars ||
      oldDelegate.camera != camera ||
      oldDelegate.zoom != zoom ||
      oldDelegate.reduceMotion != reduceMotion ||
      oldDelegate.clock != clock;
}
