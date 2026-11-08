import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Visual previews for the Classic category only. Does not modify the video.
/// Export-time frame holds, edge noise and analogue chroma bleed are approximated
/// here because Flutter's video widget does not expose previous decoded frames.
class TiniClassicEffectsPreview {
  static const category = 'كلاسيكية';
  static const supported = <String>{
    'Slide Show', 'Black Noise', 'Vintage Film', 'Film Freeze', 'DV Tape',
    'Viewfinder', 'Memory Film', 'Retro Blue', 'To B&W', 'B&W Film',
    'Retro Burst', 'Black & White', 'FPS Lag', '1998', 'JVC', 'Retro DV 3',
    'Black Sprock...', 'Vintage Video', 'Saturated Fil...',
    'Out of Focus', 'Noise I', 'White Retro ...', '70s',
  };

  static double thumbnailSeconds(String name) => switch (name) {
    'Retro Burst' => .19,
    'Film Freeze' => .32,
    'Slide Show' => .68,
    'To B&W' => 1.6,
    'FPS Lag' => .84,
    _ => .77,
  };

  static Widget _tone(Widget child, {
    double saturation = 1,
    double contrast = 1,
    double brightness = 0,
    Color? tint,
  }) {
    final k = 1 - saturation;
    final b = 127.5 * (1 - contrast) + 255 * brightness;
    Widget base = ColorFiltered(colorFilter: ColorFilter.matrix(<double>[
      contrast * (.2126 * k + saturation), contrast * (.7152 * k),
      contrast * (.0722 * k), 0, b,
      contrast * (.2126 * k), contrast * (.7152 * k + saturation),
      contrast * (.0722 * k), 0, b,
      contrast * (.2126 * k), contrast * (.7152 * k),
      contrast * (.0722 * k + saturation), 0, b,
      0, 0, 0, 1, 0,
    ]), child: child);
    if (tint != null) {
      base = ColorFiltered(colorFilter: ColorFilter.mode(
        tint, BlendMode.screen), child: base);
    }
    return base;
  }

  static Widget apply({
    required String name,
    required Widget child,
    required double elapsed,
    required double start,
    required double end,
  }) {
    if (!supported.contains(name)) return child;
    final t = math.max(0.0, elapsed - start);
    final duration = math.max(.01, end - start);
    final p = (t / duration).clamp(0.0, 1.0).toDouble();
    Widget video = child;
    switch (name) {
      case 'Slide Show':
        // Source frame holds are applied in FFmpeg. UI indicates the snap cuts.
        video = _tone(video, saturation: 1.20, contrast: 1.13);
        video = Transform.scale(scale: 1.03 + ((t * 2).floor().isEven ? .015 : .0),
            child: video);
        break;
      case 'Black Noise':
        video = _tone(video, saturation: 0, contrast: 1.75, brightness: -.18);
        break;
      case 'Vintage Film':
        video = _tone(video, saturation: .48, contrast: .88,
            tint: const Color(0x40CB8B4B));
        break;
      case 'Film Freeze':
        video = _tone(video, saturation: .51, contrast: 1.06);
        break;
      case 'DV Tape':
        video = _tone(video, saturation: .94, contrast: 1.10);
        break;
      case 'Viewfinder':
        video = _tone(video, saturation: .53, contrast: 1.19,
            tint: const Color(0x1F70FF91));
        break;
      case 'Memory Film':
        video = _tone(ImageFiltered(imageFilter: ui.ImageFilter.blur(
          sigmaX: 1.7, sigmaY: 1.7), child: video), saturation: .55,
          contrast: .79, brightness: .055, tint: const Color(0x2BD7A36C));
        break;
      case 'Retro Blue':
        video = _tone(video, saturation: .72, contrast: 1.23,
            tint: const Color(0x694080D7));
        break;
      case 'To B&W':
        video = _tone(video, saturation: 1 - (t / .75).clamp(0.0, 1.0),
            contrast: 1.12);
        break;
      case 'B&W Film':
        video = _tone(video, saturation: 0, contrast: 1.33);
        break;
      case 'Retro Burst':
        final flash = math.pow(math.max(0.0, math.sin(t * 9)), 8).toDouble();
        video = _tone(video, saturation: 1.4, contrast: 1.22,
            brightness: .045 + .23 * flash, tint: const Color(0x22FF9A44));
        break;
      case 'Black & White':
        video = _tone(video, saturation: 0, contrast: 1.72, brightness: -.035);
        break;
      case 'FPS Lag':
        video = _tone(video, saturation: 1.22, contrast: 1.20);
        break;
      case '1998':
        video = _tone(video, saturation: .81, contrast: 1.08,
            tint: const Color(0x28E28198));
        break;
      case 'JVC':
        video = _tone(video, saturation: 1.11, contrast: 1.13);
        break;
      case 'Retro DV 3':
        video = Stack(fit: StackFit.passthrough, children: [
          _tone(child, saturation: 1.32, contrast: 1.05),
          Opacity(opacity: .23, child: Transform.translate(
            offset: Offset(4 * math.sin(t * 14), 0),
            child: ColorFiltered(colorFilter: const ColorFilter.mode(
              Color(0xFFFA408C), BlendMode.modulate), child: child))),
        ]);
        break;
      case 'Black Sprock...':
        video = _tone(video, saturation: .61, contrast: 1.08);
        break;
      case 'Vintage Video':
        video = _tone(video, saturation: .64, contrast: .87,
            brightness: -.02, tint: const Color(0x29EFC591));
        break;
      case 'Saturated Fil...':
        video = _tone(video, saturation: 2.15, contrast: 1.34,
            tint: const Color(0x21FF7943));
        break;
      case 'Out of Focus':
        video = ImageFiltered(imageFilter: ui.ImageFilter.blur(
          sigmaX: 13, sigmaY: 13), child: video);
        break;
      case 'Noise I':
        video = _tone(video, saturation: 1.3, contrast: 1.20);
        break;
      case 'White Retro ...':
        video = _tone(video, saturation: .43, contrast: .72,
            brightness: .18, tint: const Color(0x38FFFFFF));
        break;
      case '70s':
        video = _tone(video, saturation: .90, contrast: .92,
            tint: const Color(0x55ECAA4B));
        break;
    }
    return ClipRect(child: Stack(fit: StackFit.passthrough, children: [
      video,
      Positioned.fill(child: IgnorePointer(child: CustomPaint(
        painter: _ClassicTexture(name, t, p)))),
    ]));
  }
}

/// Pixel density is scaled to the destination. The seeded particle positions
/// are repeatable for a given effect frame, preventing thumbnail flicker.
class _ClassicTexture extends CustomPainter {
  final String name;
  final double time;
  final double progress;
  const _ClassicTexture(this.name, this.time, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final random = math.Random((time * 24).floor() * 37 + name.hashCode);
    final paint = Paint();

    void grain(int count, double opacity, {bool bright = true}) {
      for (var i = 0; i < count; i++) {
        paint.color = (bright ? Colors.white : Colors.black).withValues(
            alpha: opacity * (.22 + random.nextDouble() * .78));
        final x = random.nextDouble() * w;
        final y = random.nextDouble() * h;
        canvas.drawRect(Rect.fromLTWH(x, y,
            .5 + random.nextDouble() * 2.2, .5 + random.nextDouble() * 2.2), paint);
      }
    }

    void scanlines(double stride, double alpha) {
      paint.color = Colors.black.withValues(alpha: alpha);
      paint.strokeWidth = 1;
      for (double y = (time * 11) % stride; y < h; y += stride) {
        canvas.drawLine(Offset(0, y), Offset(w, y), paint);
      }
    }

    void scratches(int count, double opacity) {
      paint.color = Colors.white.withValues(alpha: opacity);
      for (var i = 0; i < count; i++) {
        final x = ((i * .27 + (time * .19)) % 1) * w;
        paint.strokeWidth = .7 + i % 2;
        canvas.drawLine(Offset(x, 0), Offset(x + 3, h), paint);
      }
    }

    void vignette(double alpha) {
      paint.shader = ui.Gradient.radial(Offset(w / 2, h / 2),
          math.max(w, h) * .77,
          [Colors.transparent, Colors.black.withValues(alpha: alpha)],
          [.29, 1]);
      canvas.drawRect(Offset.zero & size, paint);
      paint.shader = null;
    }

    void frame({double inset = .055, Color color = Colors.white70}) {
      paint.color = color;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = math.max(1, w * .008);
      canvas.drawRect(Rect.fromLTWH(w * inset, h * inset,
          w * (1 - 2 * inset), h * (1 - 2 * inset)), paint);
      paint.style = PaintingStyle.fill;
    }

    void corners() {
      paint.color = Colors.white.withValues(alpha: .78);
      paint.strokeWidth = math.max(1, w * .006);
      final dx = w * .075, dy = h * .09;
      final len = w * .19, vlen = h * .105;
      for (final x in [dx, w - dx]) {
        for (final y in [dy, h - dy]) {
          canvas.drawLine(Offset(x, y),
              Offset(x + (x < w / 2 ? len : -len), y), paint);
          canvas.drawLine(Offset(x, y),
              Offset(x, y + (y < h / 2 ? vlen : -vlen)), paint);
        }
      }
    }

    switch (name) {
      case 'Slide Show':
        frame(inset: .028, color: const Color(0xE0FFFFFF));
        if ((time * 2) % 1 < .07) {
          paint.color = const Color(0x4AFFFFFF);
          canvas.drawRect(Offset.zero & size, paint);
        }
        break;
      case 'Black Noise':
        grain(420, .86);
        grain(210, .79, bright: false);
        scanlines(3.4, .35);
        break;
      case 'Vintage Film':
        vignette(.61);
        grain(170, .43);
        scratches(3, .55);
        break;
      case 'Film Freeze':
        frame(inset: .028);
        paint.color = const Color(0xA8FFFFFF);
        paint.strokeWidth = 2;
        canvas.drawLine(Offset(w * .5, h * .1), Offset(w * .5, h * .9), paint);
        break;
      case 'DV Tape':
        scanlines(3, .24);
        grain(180, .45);
        paint.color = const Color(0x6BFFFFFF);
        canvas.drawRect(Rect.fromLTWH(0, (time * 63) % h, w, 3), paint);
        break;
      case 'Viewfinder':
        corners();
        paint.color = const Color(0xAAFFFFFF);
        paint.strokeWidth = 1.5;
        canvas.drawLine(Offset(w * .46, h * .5), Offset(w * .54, h * .5), paint);
        canvas.drawLine(Offset(w * .5, h * .46), Offset(w * .5, h * .54), paint);
        break;
      case 'Memory Film':
        vignette(.35);
        grain(55, .22);
        break;
      case 'Retro Blue':
        vignette(.59);
        paint.color = const Color(0x3523B9FF);
        canvas.drawRect(Rect.fromLTWH(0, h * .73, w, h * .1), paint);
        break;
      case 'To B&W':
        break;
      case 'B&W Film':
        vignette(.56);
        grain(230, .59);
        scratches(4, .68);
        break;
      case 'Retro Burst':
        if (math.sin(time * 9) > .75) {
          paint.color = Colors.white.withValues(alpha: .38);
          canvas.drawRect(Offset.zero & size, paint);
        }
        break;
      case 'Black & White':
        break;
      case 'FPS Lag':
        paint.color = const Color(0xB6FFFFFF);
        paint.strokeWidth = 2;
        canvas.drawRect(Rect.fromLTWH(w * .05, h * .05, w * .04, h * .03), paint);
        break;
      case '1998':
        scanlines(5, .23);
        grain(110, .31);
        break;
      case 'JVC':
        corners();
        paint.color = Colors.redAccent;
        canvas.drawCircle(Offset(w * .09, h * .066), math.max(3, w * .016), paint);
        break;
      case 'Retro DV 3':
        scanlines(7, .24);
        grain(125, .37);
        break;
      case 'Black Sprock...':
        paint.color = Colors.black;
        canvas.drawRect(Rect.fromLTWH(0, 0, w * .105, h), paint);
        canvas.drawRect(Rect.fromLTWH(w * .895, 0, w * .105, h), paint);
        paint.color = const Color(0xFFE3D3B9);
        for (var i = 0; i < 9; i++) {
          final y = (i + .22) * h / 9;
          canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(w * .03, y, w * .043, h * .072),
            const Radius.circular(2)), paint);
          canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(w * .927, y, w * .043, h * .072),
            const Radius.circular(2)), paint);
        }
        break;
      case 'Vintage Video':
        scanlines(4, .32);
        grain(240, .47);
        break;
      case 'Saturated Fil...':
        vignette(.21);
        break;
      case 'Out of Focus':
        break;
      case 'Noise I':
        grain(570, .67);
        grain(110, .33, bright: false);
        break;
      case 'White Retro ...':
        frame(inset: .028, color: Colors.white);
        grain(130, .42);
        break;
      case '70s':
        vignette(.40);
        grain(78, .25);
        scratches(1, .28);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ClassicTexture oldDelegate) =>
      oldDelegate.name != name || oldDelegate.time != time ||
      oldDelegate.progress != progress;
}
