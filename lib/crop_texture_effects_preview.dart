import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Six visually independent, deterministic Texture previews. No assets,
/// frame capture, network resources, animation timers or new dependencies.
/// Time is supplied by the editor so seeking/undo/redo remains deterministic.
class TiniTextureEffectsPreview {
  static const String category = 'ملمس';
  static const Set<String> supported = <String>{
    'Crease', 'Paper Border', 'Silkscreen',
    'blue mosaic', 'Grain', 'Blue Mosaic',
  };

  static double thumbnailSeconds(String name) => name == 'Crease' ? .42 : 1.12;

  static Widget apply({
    required String name,
    required Widget child,
    required double elapsed,
    required double start,
    required double end,
  }) {
    if (!supported.contains(name)) return child;
    final time = math.max(0.0, elapsed - start);
    Widget base = child;
    switch (name) {
      case 'Crease':
        base = ColorFiltered(colorFilter: const ColorFilter.matrix([
          1.04, 0, 0, 0, -4, 0, 1.04, 0, 0, -4,
          0, 0, 1.04, 0, -4, 0, 0, 0, 1, 0,
        ]), child: base);
        break;
      case 'Silkscreen':
        base = ColorFiltered(colorFilter: const ColorFilter.matrix([
          1.28, -.17, -.12, 0, 18,
          .03, .86, -.07, 0, 8,
          -.12, -.23, .65, 0, 21,
          0, 0, 0, 1, 0,
        ]), child: base);
        break;
      case 'blue mosaic':
        base = ColorFiltered(colorFilter: const ColorFilter.matrix([
          .46, .10, .05, 0, 0,
          .07, .71, .12, 0, 5,
          .15, .20, .93, 0, 16,
          0, 0, 0, 1, 0,
        ]), child: base);
        break;
      case 'Grain':
        base = ColorFiltered(colorFilter: const ColorFilter.matrix([
          .95, .03, .02, 0, 0, .02, .95, .03, 0, 0,
          .02, .03, .95, 0, 0, 0, 0, 0, 1, 0,
        ]), child: base);
        break;
      case 'Blue Mosaic':
        base = ColorFiltered(colorFilter: const ColorFilter.matrix([
          .23, .10, .03, 0, 2, .08, .39, .09, 0, 5,
          .25, .36, 1.1, 0, 30, 0, 0, 0, 1, 0,
        ]), child: base);
        break;
    }
    if (name == 'Paper Border') {
      return LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
          return child;
        }
        return ClipRect(child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Color(0xFFEEE1C8)),
          Positioned(left: w * .077, top: h * .086,
              width: w * .846, height: h * .828,
              child: DecoratedBox(decoration: const BoxDecoration(
                boxShadow: [BoxShadow(color: Color(0x66533F29),
                    blurRadius: 5, offset: Offset(2, 3))]),
                child: ClipPath(clipper: const _PaperEdgeClipper(),
                    child: FittedBox(fit: BoxFit.cover,
                        child: SizedBox(width: w, height: h, child: base))))),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(
              painter: _TexturePainter(name, time)))),
        ]));
      });
    }
    return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
      base,
      Positioned.fill(child: IgnorePointer(child: CustomPaint(
          painter: _TexturePainter(name, time)))),
    ]));
  }
}

class _PaperEdgeClipper extends CustomClipper<Path> {
  const _PaperEdgeClipper();
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()..moveTo(0, 0);
    for (var i = 1; i <= 36; i++) {
      final x = w * i / 36;
      path.lineTo(x, (i.isEven ? 0.0 : .006) * h);
    }
    for (var i = 1; i <= 42; i++) {
      final y = h * i / 42;
      path.lineTo(w - (i.isEven ? 0.0 : .007) * w, y);
    }
    for (var i = 35; i >= 0; i--) {
      final x = w * i / 36;
      path.lineTo(x, h - (i.isEven ? 0.0 : .008) * h);
    }
    for (var i = 41; i >= 0; i--) {
      final y = h * i / 42;
      path.lineTo((i.isEven ? 0.0 : .007) * w, y);
    }
    return path..close();
  }
  @override
  bool shouldReclip(covariant _PaperEdgeClipper oldClipper) => false;
}

class _TexturePainter extends CustomPainter {
  final String name;
  final double time;
  const _TexturePainter(this.name, this.time);
  static double _random(int seed) {
    var value = (seed * 1103515245 + 12345) & 0x7fffffff;
    value ^= value >> 13;
    return (value & 0x7fffffff) / 2147483647.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final short = math.min(w, h);
    final frame = (time * 17).floor();
    switch (name) {
      case 'Crease':
        for (var fold = 0; fold < 2; fold++) {
          final x = w * (fold == 0 ? .33 : .70);
          final slant = fold == 0 ? .19 : -.095;
          final drift = 5 * math.sin(time * .8 + fold);
          final path = Path()
            ..moveTo(x + drift, 0)
            ..lineTo(x + drift + h * slant, h);
          final shadow = Paint()
            ..color = const Color(0x752C241F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = short * (fold == 0 ? .05 : .035);
          canvas.drawPath(path, shadow);
          canvas.drawPath(path.shift(Offset(-short * .018, 0)), Paint()
            ..color = const Color(0xB8FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, short * .012));
          canvas.drawPath(path.shift(Offset(short * .024, 0)), Paint()
            ..color = const Color(0x403C312A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, short * .018));
        }
        for (var i = 0; i < 27; i++) {
          final x = w * _random(i * 17 + 10);
          final y = h * _random(i * 23 + 30);
          canvas.drawLine(Offset(x, y), Offset(x + short * .045,
              y + short * .008), Paint()..color = const Color(0x1DFFFFFF)
              ..strokeWidth = .7);
        }
        break;
      case 'Paper Border':
        for (var i = 0; i < 180; i++) {
          final x = w * _random(i * 29 + 17);
          final y = h * _random(i * 37 + 97);
          if (x > w * .073 && x < w * .93 &&
              y > h * .082 && y < h * .92) continue;
          canvas.drawCircle(Offset(x, y), .3 + _random(i + 2) * 1.0,
              Paint()..color = const Color(0x5E8A775C));
        }
        break;
      case 'Silkscreen':
        // Print registration, worn ink and fine offset halftone dots.
        for (var y = 0.0; y < h; y += 7) {
          final row = (y / 7).floor();
          for (var x = (row.isEven ? 0.0 : 3.5); x < w; x += 7) {
            final seed = (x * 11 + y * 13).floor();
            canvas.drawCircle(Offset(x, y),
                .5 + _random(seed) * .95, Paint()
                    ..color = const Color(0x513B1E1A));
          }
        }
        for (var i = 0; i < 35; i++) {
          final x = w * _random(i * 43 + 4);
          final y = h * _random(i * 71 + 24);
          canvas.drawCircle(Offset(x, y), 1.3 + _random(i * 11) * 2.4,
              Paint()..color = const Color(0x31902928));
        }
        break;
      case 'blue mosaic':
        final cellW = math.max(3.0, w / 28);
        final cellH = math.max(3.0, h / 40);
        for (var y = 0.0; y < h; y += cellH) {
          for (var x = 0.0; x < w; x += cellW) {
            final seed = ((x / cellW).floor() * 59 +
                (y / cellH).floor() * 137);
            canvas.drawRect(Rect.fromLTWH(x + .4, y + .4,
                math.max(0, math.min(cellW - .8, w - x)),
                math.max(0, math.min(cellH - .8, h - y))),
                Paint()..color = Color.fromARGB(
                    (24 + _random(seed) * 76).round(), 30,
                    (110 + _random(seed + 3) * 100).round(), 244));
          }
        }
        break;
      case 'Grain':
        for (var i = 0; i < 900; i++) {
          final seed = i * 337 + frame * 7919;
          final x = w * _random(seed + 1);
          final y = h * _random(seed + 7);
          final opacity = 22 + (_random(seed + 9) * 107).round();
          canvas.drawRect(Rect.fromLTWH(x, y,
              .4 + _random(seed + 10) * 1.1,
              .4 + _random(seed + 11) * 1.1), Paint()
                  ..color = Color.fromARGB(opacity,
                      i.isEven ? 255 : 0,
                      i.isEven ? 255 : 0,
                      i.isEven ? 255 : 0));
        }
        break;
      case 'Blue Mosaic':
        final tileW = math.max(6.0, w / 14);
        final tileH = math.max(6.0, h / 24);
        final stroke = Paint()..color = const Color(0xBCD0E4FF)
          ..style = PaintingStyle.stroke..strokeWidth = 1.7;
        for (var y = 0.0; y < h; y += tileH) {
          for (var x = 0.0; x < w; x += tileW) {
            final tile = (x / tileW).floor() * 19 + (y / tileH).floor() * 31;
            final inset = 1.0 + _random(tile + 3) * 2;
            final bounds = Rect.fromLTWH(x + inset, y + inset,
                math.max(0, math.min(tileW - inset * 2, w - x - inset)),
                math.max(0, math.min(tileH - inset * 2, h - y - inset)));
            canvas.drawRect(bounds, Paint()..color = Color.fromARGB(
                32 + (_random(tile + 9) * 85).round(), 22, 42, 196));
            canvas.drawRect(bounds, stroke);
            canvas.drawLine(bounds.topLeft, bounds.center,
                Paint()..color = const Color(0x3DFFFFFF)
                    ..strokeWidth = .8);
          }
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TexturePainter other) =>
      name != other.name || (name == 'Grain' ?
          (time * 17).floor() != (other.time * 17).floor() :
          name == 'Crease' && time != other.time);
}
