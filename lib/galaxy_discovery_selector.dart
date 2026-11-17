import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'galaxy_user_star.dart';

class GalaxyDiscoverySelector {
  static int hash(String value) {
    var hash = 2166136261;
    for (final code in value.codeUnits) {
      hash = ((hash ^ code) * 16777619) & 0xffffffff;
    }
    // Avalanche the seed so adjacent refresh counters do not choose
    // nearly identical starting ranks in smaller populations.
    hash ^= hash >> 16;
    hash = (hash * 0x85ebca6b) & 0xffffffff;
    hash ^= hash >> 13;
    hash = (hash * 0xc2b2ae35) & 0xffffffff;
    return (hash ^ (hash >> 16)) & 0xffffffff;
  }

  static int cycle(DateTime now) =>
      now.toUtc().millisecondsSinceEpoch ~/ 900000;
  static double pivot(String seed) => hash(seed) / 4294967296;

  static List<String> select({
    required Iterable<String> shared,
    required Iterable<String> personal,
    required bool Function(String) allowed,
  }) {
    final result = <String>{};
    for (final id in shared) {
      if (allowed(id)) result.add(id);
      if (result.length == 6) break;
    }
    for (final id in [...personal, ...shared]) {
      if (allowed(id)) result.add(id);
      if (result.length == 30) break;
    }
    return result.toList(growable: false);
  }

  /// One account per shuffled world cell; jitter cannot cross cell boundaries.
  static List<GalaxyUserStar> place(
    List<String> ids,
    Map<String, Map<String, dynamic>> profiles,
    String seed,
  ) {
    final random = math.Random(hash(seed));
    final cells = List.generate(36, (i) => i)..shuffle(random);
    return List.unmodifiable([
      for (var i = 0; i < ids.length; i++)
        GalaxyUserStar.fromProfile(
          ids[i],
          profiles[ids[i]]!,
          Offset(
            200 + (cells[i] % 6) * 400 + (random.nextDouble() - 0.5) * 120,
            200 + (cells[i] ~/ 6) * 400 + (random.nextDouble() - 0.5) * 120,
          ),
        ),
    ]);
  }
}