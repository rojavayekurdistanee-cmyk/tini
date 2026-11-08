import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Dedicated visuals for the six Glitch tab effects. No other tab uses this
/// class, including the separate effect named خلل under Amazing.
class TiniGlitchEffectsPreview {
  static const category = 'خلل';
  static const supported = <String>{
    'Fuzzy', 'X-Signal', 'Edgy', 'Edge Glitch', 'خلل', "70's",
  };

  // A nonzero motion phase shows the relevant treatment on a static tile.
  static double thumbnailSeconds(String name) => switch (name) {
    'Fuzzy' => .31,
    'X-Signal' => .43,
    'Edgy' => .60,
    'Edge Glitch' => .39,
    'خلل' => .54,
    "70's" => .72,
    _ => .40,
  };

  static Widget _tint(Widget child, List<double> matrix) =>
      ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: child);

  static Widget apply({
    required String name,
    required Widget child,
    required double elapsed,
    required double start,
    required double end,
  }) {
    if (!supported.contains(name)) return child;
    final t = math.max(0.0, elapsed - start);
    Widget base = child;
    switch (name) {
      case 'Fuzzy':
        base = ImageFiltered(imageFilter: ui.ImageFilter.blur(
          sigmaX: 1.6 + .8 * math.sin(t * 21).abs(), sigmaY: .9),
          child: _tint(child, const <double>[
            .27,.58,.11,0,-8, .25,.60,.15,0,-8, .25,.58,.17,0,-8,
            0,0,0,1,0,
          ]));
        break;
      case 'X-Signal':
        base = Stack(fit: StackFit.passthrough, children: [
          child,
          ClipPath(clipper: _GlitchStrips(t, 0), child: Opacity(
            opacity: .79,
            child: Transform.translate(
              offset: Offset(17 * math.sin(t * 19), 0),
              child: ColorFiltered(colorFilter: const ColorFilter.mode(
                Color(0xFFFF3653), BlendMode.modulate), child: child)))),
          ClipPath(clipper: _GlitchStrips(t, 1), child: Opacity(
            opacity: .72,
            child: Transform.translate(
              offset: Offset(-20 * math.cos(t * 23), 0),
              child: ColorFiltered(colorFilter: const ColorFilter.mode(
                Color(0xFF36EDFF), BlendMode.modulate), child: child)))),
        ]);
        break;
      case 'Edgy':
        base = _tint(child, const <double>[
          1.63,-.21,-.13,0,-37, -.22,1.64,-.18,0,-39,
          -.13,-.22,1.72,0,-36, 0,0,0,1,0,
        ]);
        break;
      case 'Edge Glitch':
        base = Stack(fit: StackFit.passthrough, children: [
          _tint(child, const <double>[
            .67,.18,.10,0,-12, .14,.71,.13,0,-12,
            .10,.16,.73,0,-12, 0,0,0,1,0,
          ]),
          ClipPath(clipper: _GlitchStrips(t, 2), child: Opacity(
            opacity: .65,
            child: Transform.translate(
              offset: Offset(9 * math.sin(22 * t), 1),
              child: ColorFiltered(colorFilter: const ColorFilter.mode(
                Color(0xFF00E5FF), BlendMode.screen), child: child)))),
        ]);
        break;
      case 'خلل':
        base = Stack(fit: StackFit.passthrough, children: [
          child,
          ClipPath(clipper: _GlitchStrips(t, 3), child: Transform.translate(
            offset: Offset(27 * math.sin(t * 31), 0),
            child: _tint(child, const <double>[
              1.4,0,0,0,12, 0,.75,0,0,-18, 0,0,1.45,0,15,
              0,0,0,1,0,
            ]))),
        ]);
        break;
      case "70's":
        base = _tint(child, const <double>[
          .96,.15,.07,0,16, .08,.89,.07,0,7,
          .08,.17,.65,0,-13, 0,0,0,1,0,
        ]);
        break;
    }
    final painter = _GlitchTexture(name, t);
    return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
      base,
      Positioned.fill(child: IgnorePointer(child: CustomPaint(
        painter: painter))),
    ]));
  }
}

/// Clip only the translated frame strips; the untouched picture remains below.
class _GlitchStrips extends CustomClipper<Path> {
  final double time;
  final int mode;
  const _GlitchStrips(this.time, this.mode);

  @override
  Path getClip(Size size) {
    final path = Path();
    final count = mode == 3 ? 7 : mode == 2 ? 8 : 5;
    for (var i = 0; i < count; i++) {
      final seed = math.sin(i * 19.19 + (time * 16).floor() * 3.17).abs();
      final y = ((i * .173 + .1 * seed) % 1) * size.height;
      final h = (mode == 3 ? .084 : .033) * size.height + seed * 9;
      path.addRect(Rect.fromLTWH(0, y, size.width, h));
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _GlitchStrips oldClipper) =>
      oldClipper.mode != mode || oldClipper.time != time;
}

class _GlitchTexture extends CustomPainter {
  final String name;
  final double time;
  const _GlitchTexture(this.name, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final paint = Paint()..style = PaintingStyle.fill;
    if (name == 'Fuzzy') {
      // Deterministic time-varying snow, with dense horizontal tracking.
      for (var i = 0; i < 175; i++) {
        final px = (i * 73 + (time * 117).floor() * 29) % 997 / 997 * w;
        final py = (i * 193 + (time * 79).floor() * 51) % 991 / 991 * h;
        paint.color = i.isEven ? Colors.white.withValues(alpha: .44) :
            Colors.black.withValues(alpha: .43);
        canvas.drawRect(Rect.fromLTWH(px, py, 2 + i % 4.0, 1.2), paint);
      }
      paint.color = Colors.white.withValues(alpha: .11);
      for (double y = 0; y < h; y += 4) {
        canvas.drawRect(Rect.fromLTWH(0, y, w, .8), paint);
      }
    } else if (name == 'X-Signal') {
      // Hard missing-signal bars interrupt the colored tearing.
      for (var i = 0; i < 5; i++) {
        final y = ((i * .19 + (time * 2.7).floor() * .071) % 1) * h;
        paint.color = (i.isEven ? Colors.black : const Color(0xFF44F7FF))
            .withValues(alpha: i.isEven ? .75 : .45);
        canvas.drawRect(Rect.fromLTWH(0, y, w, math.max(2, h * .012)), paint);
      }
    } else if (name == 'Edgy') {
      // Graphic angular ink accents: different from colored signal loss.
      final stroke = Paint()..color = const Color(0xFF15171E).withValues(alpha: .8)
        ..strokeWidth = math.max(1.4, w * .007)
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < 6; i++) {
        final y = (i + 1) * h / 7;
        final path = Path()..moveTo(-10, y - 16)
          ..lineTo(w * (.2 + .07 * i), y + 4)
          ..lineTo(w * (.55 + .03 * i), y - 8);
        canvas.drawPath(path, stroke);
      }
    } else if (name == 'Edge Glitch') {
      paint.color = const Color(0xFF18E5FF).withValues(alpha: .82);
      final inset = math.max(4.0, w * .026);
      final outlinePaint = Paint()
        ..color = paint.color
        ..strokeWidth = math.max(1.5, w * .007)
        ..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromLTWH(inset, inset, w - 2 * inset, h - 2 * inset),
          outlinePaint);
      paint.color = const Color(0xFFFF2456).withValues(alpha: .43);
      for (var i = 0; i < 6; i++) {
        final y = ((time * .8 + i * .23) % 1) * h;
        canvas.drawRect(Rect.fromLTWH(0, y, w, 1.5), paint);
      }
    } else if (name == 'خلل') {
      for (var i = 0; i < 16; i++) {
        final x = ((i * 101 + (time * 15).floor() * 33) % 251) / 251 * w;
        final y = ((i * 73 + (time * 13).floor() * 57) % 229) / 229 * h;
        paint.color = [const Color(0xFFE92B70),const Color(0xFF3EF8EC),
          Colors.black][i % 3].withValues(alpha: .47);
        canvas.drawRect(Rect.fromLTWH(x, y, w * (.06 + .05 * (i % 3)),
          h * (.012 + .012 * (i % 4))), paint);
      }
    } else if (name == "70's") {
      for (double y = (time * 19) % 6; y < h; y += 6) {
        paint.color = Colors.black.withValues(alpha: .22);
        canvas.drawRect(Rect.fromLTWH(0, y, w, 1.0), paint);
      }
      for (var i = 0; i < 22; i++) {
        paint.color = Colors.white.withValues(alpha: .18 + (i % 3) * .07);
        final x = (i * 83 + (time * 25).floor() * 11) % 211 / 211 * w;
        final y = (i * 137 + (time * 17).floor() * 23) % 257 / 257 * h;
        canvas.drawCircle(Offset(x,y), .6 + (i % 3) * .5, paint);
      }
      paint.shader = ui.Gradient.radial(Offset(w / 2, h / 2),
        math.max(w, h) * .72, [Colors.transparent,
          Colors.black.withValues(alpha: .48)]);
      canvas.drawRect(Offset.zero & size, paint);
      paint.shader = null;
    }
  }

  @override
  bool shouldRepaint(covariant _GlitchTexture old) =>
      old.name != name || old.time != time;
}
