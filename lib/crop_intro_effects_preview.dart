import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Preview primitives for the first Effects category. Durations are local to
/// the selected clip, matching the time units used by the export filter graph.
/// Painting is clipped to the video, so other editor controls are unaffected.
class TiniIntroEffectsPreview {
  static Widget apply({required String name, required String id,
    required Widget child, required double elapsed,
    required double start, required double end}) {
    final duration = math.max(.1, end - start);
    final p = ((elapsed - start) / duration).clamp(0.0, 1.0).toDouble();
    final wave = math.sin(p * math.pi);
    Widget video = child;
    switch (name) {
      case 'Transform to Fall':
        video = Transform.rotate(angle: .32 * p,
          child: Transform.translate(offset: Offset(20 * p, 35 * p),
            child: Transform.scale(scale: 1 + .26 * p, child: video)));
        break;
      case 'Axis Rotation':
        final matrix = Matrix4.identity()..setEntry(3, 2, .001)
          ..rotateY(.84 * wave);
        video = Transform(alignment: Alignment.center, transform: matrix,
          child: Transform.scale(scale: 1 + .18 * wave, child: video));
        break;
      case 'Starry Zoom':
        video = Stack(fit: StackFit.expand, children: [
          Transform.scale(scale: 1 + .3 * p, child: video),
          IgnorePointer(child: CustomPaint(painter: _IntroStarsPainter(p))),
        ]);
        break;
      case 'Gradual Focusing':
        video = ImageFiltered(imageFilter: ui.ImageFilter.blur(
          sigmaX: 13 * (1 - p), sigmaY: 13 * (1 - p)), child: video);
        break;
      case 'Vertical Open':
        video = _mask(video, _IntroMaskMode.vertical, p);
        break;
      case 'Horizontal Close':
        video = _mask(video, _IntroMaskMode.horizontal, 1 - p);
        break;
      case 'Low Exposure':
        video = _brightness(video, -.42 * wave);
        break;
      case 'Camera Focus 1':
        video = Stack(fit: StackFit.expand, children: [
          ImageFiltered(imageFilter: ui.ImageFilter.blur(
            sigmaX: 3 * (1 - p), sigmaY: 3 * (1 - p)), child: video),
          IgnorePointer(child: CustomPaint(
            painter: const _IntroFramePainter(cornersOnly: true))),
        ]);
        break;
      case 'Zoom In':
        video = Transform.scale(scale: 1 + .58 * p, child: video);
        break;
      case 'Horizontal Open':
        final reveal = id.endsWith('#2') ? math.pow(p, 1.9).toDouble() : p;
        video = _mask(video, _IntroMaskMode.horizontal, reveal);
        break;
      case 'The End':
        video = Stack(fit: StackFit.expand, children: [
          _mask(video, _IntroMaskMode.circle, 1 - p,
            background: const Color(0xFF110020)),
          IgnorePointer(child: CustomPaint(
            painter: _IntroIrisRingPainter(1 - p))),
        ]);
        break;
      case 'Switch Off':
        video = _mask(video, _IntroMaskMode.crt,
          p >= .95 ? 0 : math.pow(1 - p, 3).toDouble(),
          drawLine: p < .95);
        break;
      case 'Switch On':
        video = _mask(video, _IntroMaskMode.crt,
          math.pow(p, .7).toDouble(), drawLine: true);
        break;
      case 'Shooting Frame':
        video = Stack(fit: StackFit.expand, children: [video,
          const IgnorePointer(child: CustomPaint(
            painter: _IntroFramePainter(cornersOnly: false))),
        ]);
        break;
      case 'Countdown':
        final digit = (3 - (p * 3).floor()).clamp(1, 3);
        video = Stack(fit: StackFit.expand, children: [video,
          IgnorePointer(child: Center(child: Text('$digit',
            style: const TextStyle(fontSize: 110, fontWeight: FontWeight.bold,
              color: Colors.white, shadows: [Shadow(color: Colors.black87,
                blurRadius: 14, offset: Offset(2, 2))])))),
        ]);
        break;
      case 'Slip':
        video = Transform.translate(
          offset: Offset(22 * math.sin(p * math.pi * 2), 0),
          child: Transform.scale(scale: 1.12, child: video));
        break;
      case 'Scroll':
        video = Transform.translate(offset: Offset(0, (p - .5) * 85),
          child: Transform.scale(scale: 1.12, child: video));
        break;
      case 'Rotate':
        video = Transform.rotate(angle: 2 * math.pi * p, child: video);
        break;
      case 'Circle':
        video = _mask(video, _IntroMaskMode.circle, p);
        break;
      case 'Vertical':
        video = Transform.translate(offset: Offset(0, (p - .5) * 120),
          child: Transform.scale(scale: 1.15, child: video));
        break;
      case 'Horizon':
        video = Transform.translate(offset: Offset((p - .5) * 95, 0),
          child: Transform.scale(scale: 1.15, child: video));
        break;
    }
    return ClipRect(child: video);
  }

  static Widget _brightness(Widget child, double brightness) => ColorFiltered(
    colorFilter: ColorFilter.matrix([
      1, 0, 0, 0, 255 * brightness,
      0, 1, 0, 0, 255 * brightness,
      0, 0, 1, 0, 255 * brightness,
      0, 0, 0, 1, 0,
    ]), child: child);

  static Widget _mask(Widget video, _IntroMaskMode mode, double reveal,
      {Color background = Colors.black, bool drawLine = false}) =>
    ColoredBox(color: background, child: Stack(fit: StackFit.expand, children: [
      ClipPath(clipper: _IntroClipper(mode, reveal), child: video),
      if (drawLine && reveal < .3) IgnorePointer(child: LayoutBuilder(
        builder: (context, bounds) => Center(child: Container(
          width: bounds.maxWidth * .75, height: 2.0,
          decoration: const BoxDecoration(color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.white70, blurRadius: 14)]),
        )),
      )),
    ]));
}

enum _IntroMaskMode { vertical, horizontal, circle, crt }

class _IntroClipper extends CustomClipper<Path> {
  final _IntroMaskMode mode;
  final double amount;
  const _IntroClipper(this.mode, this.amount);

  @override
  Path getClip(Size size) {
    final p = amount.clamp(0.0, 1.0).toDouble();
    switch (mode) {
      case _IntroMaskMode.vertical:
        return Path()..addRect(Rect.fromCenter(center: size.center(Offset.zero),
          width: size.width * p, height: size.height));
      case _IntroMaskMode.horizontal:
        return Path()..addRect(Rect.fromCenter(center: size.center(Offset.zero),
          width: size.width, height: size.height * p));
      case _IntroMaskMode.crt:
        return Path()..addRect(Rect.fromCenter(center: size.center(Offset.zero),
          width: size.width, height: size.height * p));
      case _IntroMaskMode.circle:
        final radius = math.sqrt(size.width * size.width +
            size.height * size.height) * .5 * p;
        return Path()..addOval(Rect.fromCircle(center: size.center(Offset.zero),
          radius: radius));
    }
  }

  @override
  bool shouldReclip(_IntroClipper old) => mode != old.mode || amount != old.amount;
}

class _IntroFramePainter extends CustomPainter {
  final bool cornersOnly;
  const _IntroFramePainter({required this.cornersOnly});

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()..color = Colors.white.withValues(alpha: .83)
      ..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final rect = Rect.fromLTWH(size.width * .14, size.height * .14,
      size.width * .72, size.height * .72);
    if (!cornersOnly) {
      canvas.drawRect(rect, pen);
      canvas.drawLine(Offset(size.width * .48, size.height * .5),
        Offset(size.width * .52, size.height * .5), pen);
      canvas.drawLine(Offset(size.width * .5, size.height * .48),
        Offset(size.width * .5, size.height * .52), pen);
      return;
    }
    final cw = size.width * .095;
    final ch = size.height * .08;
    final path = Path()
      ..moveTo(rect.left + cw, rect.top)..lineTo(rect.left, rect.top)
      ..lineTo(rect.left, rect.top + ch)
      ..moveTo(rect.right - cw, rect.top)..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + ch)
      ..moveTo(rect.left + cw, rect.bottom)..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.bottom - ch)
      ..moveTo(rect.right - cw, rect.bottom)..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right, rect.bottom - ch);
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(_IntroFramePainter old) => cornersOnly != old.cornersOnly;
}

class _IntroStarsPainter extends CustomPainter {
  final double phase;
  const _IntroStarsPainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 14; i++) {
      final u = (i * .618033988749895) % 1.0;
      final v = (i * .414213562373095) % 1.0;
      final dx = size.width * u + math.sin(phase * 12 + i * 2) * 9;
      final dy = size.height * v - phase * 32;
      final radius = (1.2 + (i % 4) * .85) * (.5 + .5 * phase);
      final paint = Paint()..color = Colors.white.withValues(alpha: .7)
        ..strokeWidth = 1.2..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(dx - radius * 1.8, dy),
        Offset(dx + radius * 1.8, dy), paint);
      canvas.drawLine(Offset(dx, dy - radius * 1.8),
        Offset(dx, dy + radius * 1.8), paint);
    }
  }

  @override
  bool shouldRepaint(_IntroStarsPainter old) => phase != old.phase;
}

/// A luminous edge around the shrinking outro iris, without external assets.
class _IntroIrisRingPainter extends CustomPainter {
  final double phase;
  const _IntroIrisRingPainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    if (phase <= .001) return;
    final radius = math.sqrt(size.width * size.width +
        size.height * size.height) * .5 * phase;
    final center = size.center(Offset.zero);
    final glow = Paint()
      ..color = const Color(0xAA963CFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11);
    final edge = Paint()
      ..color = const Color(0xFFCB9FFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, glow);
    canvas.drawCircle(center, radius, edge);
  }

  @override
  bool shouldRepaint(_IntroIrisRingPainter old) => phase != old.phase;
}
