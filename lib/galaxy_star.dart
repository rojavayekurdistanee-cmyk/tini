import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Local scenery only; these stars do not represent user accounts.
@immutable
class GalaxyStar {
  final int id;
  final Offset position;
  final double radius;
  final Color color;
  final double brightness;
  final double depth;
  final double twinkleSpeed;
  final double phase;

  const GalaxyStar({
    required this.id,
    required this.position,
    required this.radius,
    required this.color,
    required this.brightness,
    required this.depth,
    required this.twinkleSpeed,
    required this.phase,
  });

  static const worldSize = Size(2400, 2400);

  /// Fixed seed and world coordinates keep the sky stable across visits.
  static List<GalaxyStar> generate({int seed = 73, int count = 600}) {
    final random = math.Random(seed);
    const colors = [
      Color(0xFFF1F5F9),
      Color(0xFFB2DFDB),
      Color(0xFF90CAF9),
      Color(0xFFD1C4E9),
    ];
    return List.unmodifiable(
      List.generate(
        count,
        (id) => GalaxyStar(
          id: id,
          position: Offset(
            random.nextDouble() * worldSize.width,
            random.nextDouble() * worldSize.height,
          ),
          radius: 0.6 + random.nextDouble() * 2,
          color: colors[random.nextInt(colors.length)],
          brightness: 0.35 + random.nextDouble() * 0.65,
          depth: 0.25 + random.nextDouble() * 0.75,
          twinkleSpeed: 1.0 + random.nextInt(3),
          phase: random.nextDouble() * math.pi * 2,
        ),
      ),
    );
  }
}