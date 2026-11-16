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
  final bool hasRays;
  final bool hasDiagonalRays;

  const GalaxyStar({
    required this.id,
    required this.position,
    required this.radius,
    required this.color,
    required this.brightness,
    required this.depth,
    required this.twinkleSpeed,
    required this.phase,
    this.hasRays = false,
    this.hasDiagonalRays = false,
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
          radius: id % 19 == 0
              ? 1.8 + random.nextDouble() * 0.8
              : 0.45 + random.nextDouble() * 1.25,
          color: colors[random.nextInt(colors.length)],
          brightness: id % 19 == 0
              ? 0.9 + random.nextDouble() * 0.1
              : 0.5 + random.nextDouble() * 0.4,
          depth: 0.25 + random.nextDouble() * 0.75,
          twinkleSpeed: 1.0 + random.nextInt(3),
          phase: random.nextDouble() * math.pi * 2,
          hasRays: id % 19 == 0,
          hasDiagonalRays: id % 57 == 0,
        ),
      ),
    );
  }
}
