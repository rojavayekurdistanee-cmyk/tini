import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Non-destructive lightweight Flutter preview for Basic video effects.
/// FFmpeg is authoritative for export. Exact edge kernels, RGB channel shifts
/// and temporal frame accumulation cannot be reproduced by these UI layers.
class TiniBasicEffectsPreview {
  static Widget apply({required String name, required Widget child,
      required double elapsed, required double start, required double end}) {
    final duration = math.max(.1, end - start);
    final p = ((elapsed - start) / duration).clamp(0.0, 1.0).toDouble();
    final beat = math.sin(p * math.pi * 2);
    switch (name) {
      case 'Chrome Blur':
        return _tone(_blur(child, 2.2), 1.16, .018,
            tint: const Color(0x2248AFFF));
      case 'Screenshot ...':
        return Stack(fit: StackFit.expand, children: [
          child,
          Container(margin: const EdgeInsets.all(13), decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2))),
          if (p > .25 && p < .45)
            ColoredBox(color: Colors.white.withValues(alpha: .24)),
        ]);
      case 'Chromatic A...':
        return _channelEcho(child, 5, red: const Color(0x66FF3853),
            blue: const Color(0x6653AFFF));
      case 'Noise':
        return _grain(child, 0.24, (elapsed * 23).floor());
      case 'Halo Blur':
        return Stack(fit: StackFit.expand, children: [child,
          Opacity(opacity: .28, child: _blur(child, 10)),
          ColoredBox(color: const Color(0x16FFFFFF))]);
      case 'Hazy':
        return _tone(_blur(child, 2.8), .75, .10,
            tint: const Color(0x22F6DBB4));
      case 'Rotary Focus':
        return Transform.rotate(angle: .13 * math.sin(p * 2 * math.pi),
            child: _blur(child, 1.3));
      case 'Vertical Blur':
        return ImageFiltered(imageFilter: ui.ImageFilter.blur(
            sigmaX: .7, sigmaY: 12), child: child);
      case 'Zoom Lens':
        return _vignette(Transform.scale(scale: 1.02 + .49 * p,
            child: child), .63);
      case 'Blurry Focus':
        return Stack(fit: StackFit.expand, children: [
          child,
          ClipPath(clipper: const _OutsideCircleClipper(.36),
              child: BackdropFilter(filter: ui.ImageFilter.blur(
                  sigmaX: 12, sigmaY: 12), child: const ColoredBox(
                      color: Colors.transparent))),
        ]);
      case 'Blur Close':
        return Stack(fit: StackFit.expand, children: [child,
          Opacity(opacity: p, child: _blur(child, 16))]);
      case 'Rebound Swi...':
        return Transform.scale(scale: 1.08 + .33 * math.sin(math.pi * p) +
            .08 * math.sin(4 * math.pi * p), child: child);
      case 'Vignette':
        return _vignette(child, .84);
      case 'Blur':
        return _blur(child, 11);
      case 'Fisheye III':
        // Flutter's 2D transform approximates the bounding geometry only;
        // the FFmpeg export applies the actual nonlinear lens correction.
        return Transform.scale(scale: 1.13, child: _vignette(child, .45));
      case 'Diamond Zoo...':
        return Stack(fit: StackFit.expand, children: [child,
          ClipPath(clipper: _DiamondClipper(.18 + .42 * p),
              child: Transform.scale(scale: 1.60, child: child))]);
      case 'Motion Blur':
        return Stack(fit: StackFit.expand, children: [
          Transform.translate(offset: const Offset(-5, 0),
              child: Opacity(opacity: .30, child: child)),
          Transform.translate(offset: const Offset(4, 0),
              child: Opacity(opacity: .30, child: child)),
          Opacity(opacity: .55, child: child),
        ]);
      case 'Magnifying ...':
        return Stack(fit: StackFit.expand, children: [child,
          Center(child: FractionallySizedBox(widthFactor: .54,
              heightFactor: .54, child: ClipOval(child: Transform.scale(
                  scale: 1.86, child: child)))),
          Center(child: FractionallySizedBox(widthFactor: .54,
              heightFactor: .54, child: DecoratedBox(decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 1.5))))),
        ]);
      case 'Mini Zoom':
        return Transform.scale(scale: 1.02 + .15 * p, child: child);
      case 'Slanted Blur':
        return Transform.rotate(angle: .035 * beat, child: _blur(child, 5));
      case 'TV Jitter':
        return _grain(Transform.translate(offset: Offset(4 * math.sin(elapsed * 41),
            3 * math.cos(elapsed * 35)), child: _channelEcho(
                child, 3, red: const Color(0x44FF4141),
                blue: const Color(0x44419EFF))), .14, (elapsed * 24).floor());
      case 'Window':
        return ColoredBox(color: Colors.black, child: Padding(
            padding: const EdgeInsets.all(17), child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(
                    color: Colors.white30, width: 2)), child: child)));
      case 'Zoom':
        return Transform.scale(scale: 1.02 + .76 * p, child: child);
      case 'Background ...':
        return Stack(fit: StackFit.expand, children: [
          _tone(_blur(child, 16), .85, -.09),
          Center(child: FractionallySizedBox(widthFactor: .75,
              heightFactor: .75, child: child)),
        ]);
      case 'HDR':
        return _tone(child, 1.28, .02);
      case 'Zoom Sketch':
        return Transform.scale(scale: 1.02 + .37 * p, child: _tone(
            child, .15, .07, tint: const Color(0x18E6D6C5)));
      default:
        return child;
    }
  }

  static Widget _blur(Widget child, double radius) => ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: radius, sigmaY: radius),
      child: child);

  static Widget _tone(Widget child, double saturation, double brightness,
      {Color? tint}) {
    final k = 1 - saturation;
    final b = brightness * 255;
    Widget output = ColorFiltered(colorFilter: ColorFilter.matrix([
      .2126 * k + saturation, .7152 * k, .0722 * k, 0, b,
      .2126 * k, .7152 * k + saturation, .0722 * k, 0, b,
      .2126 * k, .7152 * k, .0722 * k + saturation, 0, b,
      0, 0, 0, 1, 0,
    ]), child: child);
    if (tint != null) {
      output = Stack(fit: StackFit.expand, children: [output,
        ColoredBox(color: tint)]);
    }
    return output;
  }

  static Widget _vignette(Widget child, double strength) => Stack(
      fit: StackFit.expand, children: [child,
        DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
            colors: [Colors.transparent, Colors.black.withValues(alpha: strength)],
            stops: const [.27, 1], radius: .79))),
      ]);

  static Widget _channelEcho(Widget child, double offset,
      {required Color red, required Color blue}) => Stack(
        fit: StackFit.expand, children: [child,
          Transform.translate(offset: Offset(-offset, 0),
              child: ColorFiltered(colorFilter: ColorFilter.mode(
                  red, BlendMode.srcATop), child: Opacity(opacity: .16, child: child))),
          Transform.translate(offset: Offset(offset, 0),
              child: ColorFiltered(colorFilter: ColorFilter.mode(
                  blue, BlendMode.srcATop), child: Opacity(opacity: .16, child: child))),
        ]);

  static Widget _grain(Widget child, double opacity, int seed) => Stack(
      fit: StackFit.expand, children: [child,
        IgnorePointer(child: CustomPaint(painter: _GrainPainter(seed, opacity))),
      ]);
}

class _OutsideCircleClipper extends CustomClipper<Path> {
  final double radius;
  const _OutsideCircleClipper(this.radius);
  @override
  Path getClip(Size size) {
    final cutout = Path()..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: size.center(Offset.zero),
          radius: size.shortestSide * radius));
    return cutout;
  }
  @override
  bool shouldReclip(_OutsideCircleClipper oldClipper) => oldClipper.radius != radius;
}

class _DiamondClipper extends CustomClipper<Path> {
  final double extent;
  const _DiamondClipper(this.extent);
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .5, size.height * (.5 - extent))
    ..lineTo(size.width * (.5 + extent), size.height * .5)
    ..lineTo(size.width * .5, size.height * (.5 + extent))
    ..lineTo(size.width * (.5 - extent), size.height * .5)
    ..close();
  @override
  bool shouldReclip(_DiamondClipper oldClipper) => oldClipper.extent != extent;
}

class _GrainPainter extends CustomPainter {
  final int seed;
  final double opacity;
  const _GrainPainter(this.seed, this.opacity);
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final paint = Paint();
    for (var i = 0; i < 150; i++) {
      paint.color = (i.isEven ? Colors.white : Colors.black)
          .withValues(alpha: opacity * random.nextDouble());
      canvas.drawRect(Rect.fromLTWH(random.nextDouble() * size.width,
          random.nextDouble() * size.height, 1.2, 1.2), paint);
    }
  }
  @override
  bool shouldRepaint(_GrainPainter old) => old.seed != seed || old.opacity != opacity;
}
