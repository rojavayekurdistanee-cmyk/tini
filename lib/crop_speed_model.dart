import 'dart:math' as math;

/// Time coordinates always remain in the original media source.
/// Speed affects playback/project duration, never source boundaries.
class CropSpeedPoint {
  final double at; // normalized source position 0..1
  final double speed;
  const CropSpeedPoint(this.at, this.speed);
}

class CropSpeed {
  final bool isCurve;
  final double normal;
  final List<CropSpeedPoint> points;

  const CropSpeed.normal([this.normal = 1.0])
      : isCurve = false, points = const [];

  CropSpeed.curve(List<CropSpeedPoint> values)
      : isCurve = true,
        normal = 1.0,
        points = List.unmodifiable(_sanitize(values));

  static List<CropSpeedPoint> _sanitize(List<CropSpeedPoint> values) {
    final sorted = values.map((p) => CropSpeedPoint(
      p.at.clamp(0.0, 1.0).toDouble(), p.speed.clamp(0.1, 10.0).toDouble(),
    )).toList()..sort((a, b) => a.at.compareTo(b.at));
    if (sorted.isEmpty) return [const CropSpeedPoint(0, 1), const CropSpeedPoint(1, 1)];
    final distinct = <CropSpeedPoint>[];
    for (final p in sorted) {
      if (distinct.isNotEmpty && (p.at - distinct.last.at).abs() < 0.00001) {
        distinct[distinct.length - 1] = p;
      } else {
        distinct.add(p);
      }
    }
    if (distinct.first.at > 0) distinct.insert(0, CropSpeedPoint(0, distinct.first.speed));
    if (distinct.last.at < 1) distinct.add(CropSpeedPoint(1, distinct.last.speed));
    return distinct;
  }

  bool get isDefault => !isCurve && (normal - 1.0).abs() < 0.00001;

  double speedAt(double normalizedSource) {
    if (!isCurve) return normal.clamp(0.1, 10.0);
    final t = normalizedSource.clamp(0.0, 1.0).toDouble();
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (t <= b.at) {
        final d = b.at - a.at;
        if (d <= 0) return b.speed;
        return a.speed + (b.speed - a.speed) * (t - a.at) / d;
      }
    }
    return points.last.speed;
  }

  // Exact integral of 1 / linear speed on a source-normalized interval.
  double playbackFraction(double until) {
    final t = until.clamp(0.0, 1.0).toDouble();
    if (!isCurve) return t / normal.clamp(0.1, 10.0);
    double total = 0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (t <= a.at) break;
      final stop = math.min(t, b.at);
      final width = stop - a.at;
      final fullWidth = b.at - a.at;
      if (width <= 0 || fullWidth <= 0) continue;
      final v0 = a.speed;
      final v1 = v0 + (b.speed - v0) * width / fullWidth;
      final gradient = (b.speed - v0) / fullWidth;
      total += gradient.abs() < 0.000001 ? width / v0 : math.log(v1 / v0) / gradient;
    }
    return total;
  }

  double sourceFractionAtPlayback(double elapsedFraction) {
    final target = elapsedFraction.clamp(0.0, playbackFraction(1)).toDouble();
    var low = 0.0, high = 1.0;
    for (var i = 0; i < 30; i++) {
      final middle = (low + high) / 2;
      if (playbackFraction(middle) < target) { low = middle; } else { high = middle; }
    }
    return (low + high) / 2;
  }

  /// Carry a velocity curve across a split, re-normalizing its source domain.
  CropSpeed slice(double from, double to) {
    if (!isCurve) return CropSpeed.normal(normal);
    final start = from.clamp(0.0, 1.0).toDouble();
    final end = to.clamp(start, 1.0).toDouble();
    if (end - start < 0.000001) return CropSpeed.normal(speedAt(start));
    final values = <CropSpeedPoint>[CropSpeedPoint(0, speedAt(start))];
    for (final point in points) {
      if (point.at > start && point.at < end) {
        values.add(CropSpeedPoint((point.at - start) / (end - start), point.speed));
      }
    }
    values.add(CropSpeedPoint(1, speedAt(end)));
    return CropSpeed.curve(values);
  }

  static CropSpeed preset(String name) {
    switch (name) {
      case 'speedUp': return CropSpeed.curve(const [
        CropSpeedPoint(0, .6), CropSpeedPoint(.45, 1), CropSpeedPoint(.8, 3), CropSpeedPoint(1, 3)]);
      case 'slowDown': return CropSpeed.curve(const [
        CropSpeedPoint(0, 3), CropSpeedPoint(.45, 1), CropSpeedPoint(.8, .5), CropSpeedPoint(1, .5)]);
      case 'montage': return CropSpeed.curve(const [
        CropSpeedPoint(0, 1), CropSpeedPoint(.2, 3), CropSpeedPoint(.4, .5),
        CropSpeedPoint(.6, 4), CropSpeedPoint(.8, .5), CropSpeedPoint(1, 1)]);
      case 'hero': return CropSpeed.curve(const [
        CropSpeedPoint(0, 2), CropSpeedPoint(.35, .35),
        CropSpeedPoint(.65, .35), CropSpeedPoint(1, 2)]);
      default: return CropSpeed.curve(const [CropSpeedPoint(0, 1), CropSpeedPoint(1, 1)]);
    }
  }
}
