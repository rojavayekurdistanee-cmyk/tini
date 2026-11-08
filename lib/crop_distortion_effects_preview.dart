import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Live distortion preview for the five reference effects in the تشويه tab.
/// Video is clipped into rings or strips; each region has independent motion.
/// This is a low-overhead geometric approximation of the pixel-accurate
/// FFmpeg displacement export, not a static colour filter.
class TiniDistortionEffectsPreview {
  static const category = 'تشويه';
  static const supported = <String>{
    'Waves 2', 'Concentric C...', 'Stretched W...',
    'Ripple Distor...', 'Ripples',
  };

  static double thumbnailSeconds(String name) => switch (name) {
    'Waves 2' => .37,
    'Concentric C...' => .45,
    'Stretched W...' => .51,
    'Ripple Distor...' => .34,
    'Ripples' => .62,
    _ => .43,
  };

  static Widget apply({
    required String name,
    required Widget child,
    required double elapsed,
    required double start,
    required double end,
  }) {
    if (!supported.contains(name)) return child;
    final t = math.max(0.0, elapsed - start);
    return LayoutBuilder(builder: (context, bounds) {
      final w = bounds.maxWidth;
      final h = bounds.maxHeight;
      if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) return child;

      if (name == 'Concentric C...' || name == 'Ripples') {
        const rings = 16;
        final layers = <Widget>[child];
        for (var i = 0; i < rings; i++) {
          final r = (i + .5) / rings;
          final angle = name == 'Concentric C...'
              ? .55 * math.sin(39 * r * .78 - 5.7 * t) * math.exp(-.85 * r)
              : 0.0;
          final zoom = name == 'Ripples'
              ? 1 + .072 * math.sin(101 * r * .66 - 11.4 * t) *
                  math.exp(-1.9 * r)
              : 1.0;
          layers.add(Positioned.fill(child: ClipPath(
            clipper: _DistortionRing(i, rings),
            child: Transform.rotate(angle: angle, child: Transform.scale(
              scale: zoom, child: child)),
          )));
        }
        return ClipRect(child: Stack(fit: StackFit.passthrough,
            children: layers));
      }

      final bands = name == 'Ripple Distor...' ? 25 : 30;
      final layers = <Widget>[child];
      for (var i = 0; i < bands; i++) {
        final value = (i + .5) / bands;
        if (name == 'Ripple Distor...') {
          final distance = (value - (.5 + .18 * math.sin(1.25 * t))).abs();
          final fade = math.exp(-3 * distance);
          final dx = w * .036 * math.cos(58 * distance - 10 * t) * fade;
          final dy = h * .086 * math.sin(58 * distance - 10 * t) * fade;
          layers.add(Positioned.fill(child: ClipPath(
            clipper: _DistortionBand(i, bands, vertical: true),
            child: Transform.translate(offset: Offset(dx, dy), child: child),
          )));
        } else {
          final waves = name == 'Waves 2';
          final dx = waves
              ? .118 * math.sin(2 * math.pi * (2.35 * value - 1.20 * t))
              : .024 * math.sin(2 * math.pi * (1.6 * value - .74 * t));
          final scaleX = waves ? 1.12 :
              1 + .48 * math.sin(3 * math.pi * value - 4.3 * t);
          layers.add(Positioned.fill(child: ClipPath(
            clipper: _DistortionBand(i, bands, vertical: false),
            child: Transform.translate(
              offset: Offset(w * dx, waves ? 0 :
                  h * .01 * math.sin(3.6 * t)),
              child: Transform.scale(scaleX: scaleX, scaleY: 1,
                child: child),
            ),
          )));
        }
      }
      return ClipRect(child: Stack(fit: StackFit.passthrough,
          children: layers));
    });
  }
}

class _DistortionBand extends CustomClipper<Path> {
  final int index;
  final int count;
  final bool vertical;
  const _DistortionBand(this.index, this.count,
      {required this.vertical});

  @override
  Path getClip(Size size) {
    if (vertical) {
      return Path()..addRect(Rect.fromLTRB(
        size.width * index / count, 0,
        size.width * (index + 1) / count + .6, size.height));
    }
    return Path()..addRect(Rect.fromLTRB(
      0, size.height * index / count,
      size.width, size.height * (index + 1) / count + .6));
  }

  @override
  bool shouldReclip(covariant _DistortionBand oldClipper) =>
      index != oldClipper.index || count != oldClipper.count ||
      vertical != oldClipper.vertical;
}

class _DistortionRing extends CustomClipper<Path> {
  final int index;
  final int count;
  const _DistortionRing(this.index, this.count);

  @override
  Path getClip(Size size) {
    final center = Offset(size.width * .5, size.height * .5);
    final maxRadius = math.sqrt(size.width * size.width +
        size.height * size.height) * .55;
    final outerRadius = maxRadius * (index + 1) / count + .6;
    final path = Path()..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: center, radius: outerRadius));
    if (index > 0) {
      final innerRadius = maxRadius * index / count - .5;
      path.addOval(Rect.fromCircle(center: center,
          radius: math.max(0.0, innerRadius)));
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _DistortionRing oldClipper) =>
      oldClipper.index != index || oldClipper.count != count;
}
