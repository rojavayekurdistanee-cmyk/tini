import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Reference-led live effects for the Dynamic tab. This code intentionally
/// mirrors the temporal/motion families in TiniDynamicEffectsExport.
/// Frame-history operations (Delay, Stuck Frame, Astral, ظل, Soul) need
/// decoded-frame buffering for frame-exact previews: here their live visuals
/// approximate layering, while the video export uses actual prior frames.
class TiniDynamicEffectsPreview {
  static const category = 'ديناميكية';

  /// Avoid sampling every grid item at the same zero-motion/keyframe instant.
  /// These are display instants, not changes to the effect itself.
  static double thumbnailSeconds(String name) => switch (name) {
    'White Flash' || 'Flash I' => .32,
    'Flash II' => .17,
    'Flash' => .215,
    'Beat' => .20,
    'Throb' => .125,
    'Black Flash' || 'Black Flash II' => .13,
    'RGB Border' || 'Neon' => .25,
    'Bounce Cam...' || 'Pulse' || 'Chromo-zoom' => .35,
    'Club lights' || 'Club Mood' => .65,
    'Strobe' => .26,
    'Orange Nega...' => .45,
    'Flicker' => .20,
    'Disco' || 'Colorful' => .74,
    _ => .42,
  };

  static double _positive(double n) => math.max(0, n);
  static double _beat(double t, double frequency, int exponent) =>
      math.pow(_positive(math.sin(t * frequency)), exponent).toDouble();

  static Widget apply({
    required String name,
    required Widget child,
    required double elapsed,
    required double start,
    required double end,
  }) {
    final t = math.max(0.0, elapsed - start);
    Widget result = child;
    Color? overlay;
    double opacity = 0;
    double saturation = 1;
    double brightness = 0;
    double contrast = 1;
    double sigma = 0;
    double zoom = 1;
    double roll = 0;
    Offset fraction = Offset.zero;
    bool negate = false;
    bool channelEcho = false;
    bool imageEcho = false;
    double echoOpacity = 0;
    Offset echoShift = Offset.zero;

    switch (name) {
      case 'Disco':
        saturation = 1.35;
        contrast = 1.13;
        overlay = HSLColor.fromAHSL(1, 295 + 28 * math.sin(t * 2.5), 1, .49).toColor();
        opacity = .46 + .09 * math.sin(t * 7.2).abs();
        break;
      case 'Club Mood':
        overlay = const Color(0xFF7185DF);
        opacity = .48;
        saturation = .78;
        imageEcho = true;
        echoOpacity = .24;
        echoShift = Offset(.025 * math.sin(t * 2.4), -.023);
        break;
      case 'Club lights':
        saturation = 1.12;
        brightness = .04;
        break; // Tapered travelling light shafts in the foreground painter.
      case 'Orange Nega...':
        negate = true;
        contrast = 1.45;
        saturation = 1.75;
        overlay = const Color(0xFFFF5400);
        opacity = .50;
        break;
      case 'Shake + Scre...':
        zoom = 1.30;
        fraction = Offset(.09 * math.sin(t * 35) * math.sin(t * 9),
            .07 * math.cos(t * 27));
        sigma = 3.0;
        brightness = .16 * _beat(t, 7.5, 8);
        channelEcho = true;
        contrast = 1.17;
        break;
      case 'Shaky Camer...':
        zoom = 1.26;
        fraction = Offset(.10 * math.sin(t * 13.1) + .016 * math.sin(t * 43),
            .10 * math.cos(t * 16.2));
        sigma = 2.1;
        break;
      case 'Shake 1':
        zoom = 1.25;
        fraction = Offset(.10 * math.sin(t * 19) * math.sin(t * 6),
            .025 * math.sin(t * 11));
        sigma = 1.3;
        break;
      case 'Shake 2':
        zoom = 1.33;
        fraction = Offset(.037 * math.sin(t * 9), .11 * math.sin(t * 15.5));
        contrast = 1.06;
        break;
      case 'Shake':
        zoom = 1.22;
        final hit = _beat(t, 4.3, 4);
        fraction = Offset(.08 * math.sin(t * 26) * hit,
            .072 * math.cos(t * 22) * hit);
        break;
      case 'Trembling':
        zoom = 1.026;
        fraction = Offset(.011 * math.sin(t * 80), .011 * math.cos(t * 74));
        contrast = 1.07;
        break;
      case 'Colorful':
        contrast = 1.27;
        saturation = 2.5;
        overlay = HSLColor.fromAHSL(1, 37 + 23 * math.sin(t * 2.0), 1, .52).toColor();
        opacity = .29;
        break;
      case 'RGB Border':
        break;
      case 'Neon':
        saturation = 1.14;
        contrast = 1.04;
        break;
      case 'Chromatic':
        channelEcho = true;
        saturation = 1.19;
        contrast = 1.09;
        break;
      case 'Delay':
        imageEcho = true;
        echoOpacity = .32;
        echoShift = Offset(.032 * math.sin(t * 3.1), 0);
        break;
      case 'Stuck Frame':
        // The player owns video decoding; a live freeze requires a player-frame
        // buffer. Export freezes at 4 fps instead of pretending a blur is one.
        break;
      case 'Flash II':
        brightness = .50 * (math.sin(t * 11.8) > .52 ? 1 : 0) +
            .14 * (math.sin(t * 23.6) > .82 ? 1 : 0);
        break;
      case 'Flash I':
        brightness = .52 * _beat(t, 5, 18);
        break;
      case 'Black Flash II':
        brightness = -.72 * (math.sin(t * 18.5) > .18 ? 1 : 0);
        break;
      case 'Black Flash':
        brightness = -.82 * (math.sin(t * 5.1) > .35 ? 1 : 0);
        break;
      case 'White Flash':
        brightness = .88 * _beat(t, 4.7, 12);
        break;
      case 'Flicker':
        brightness = .13 * math.sin(t * 61) + .10 * math.sin(t * 93.7) +
            .06 * math.sin(t * 18.3);
        break;
      case 'Chromo-zoom':
        zoom = 1.025 + .49 * math.pow(_positive(math.sin(t * 4.6)), 2);
        sigma = .9;
        channelEcho = true;
        break;
      case 'Astral':
        saturation = .76;
        overlay = const Color(0xFF9EBAFF);
        opacity = .25;
        imageEcho = true;
        echoOpacity = .40;
        echoShift = const Offset(.048, -.02);
        sigma = 1.2;
        break;
      case 'Unreal II':
        brightness = .22;
        saturation = .58;
        sigma = 3.0;
        overlay = Colors.white;
        opacity = .23;
        break;
      case 'ظل':
        saturation = .55;
        brightness = -.19;
        imageEcho = true;
        echoOpacity = .32;
        echoShift = const Offset(.078, 0);
        break;
      case 'Bounce Cam...':
        zoom = 1.015 + .58 * math.pow(math.sin(t * 5.2).abs(), 6);
        fraction = Offset(0, .035 * math.sin(t * 5.2));
        contrast = 1.08;
        break;
      case 'Play Pendulu...':
        roll = .21 * math.sin(t * 3.35);
        break;
      case 'Throb':
        zoom = 1 + .15 * _beat(t, 12.4, 6);
        brightness = .04 * _beat(t, 12.4, 6);
        saturation = 1.38;
        break;
      case 'Beat':
        final strike = _beat(t, 8, 10);
        contrast = 1 + .20 * strike;
        brightness = .09 * strike;
        break;
      case 'Pulse':
        zoom = 1.035 + .46 * math.pow(_positive(math.sin(t * 3.9)), 2);
        sigma = 1.9;
        break;
      case 'Strobe':
        brightness = math.sin(t * 27) > .25 ? .68 : -.46;
        break;
      case 'Sway':
        roll = .072 * math.sin(t * 3.8);
        break;
      case 'Soul':
        imageEcho = true;
        echoOpacity = .37;
        echoShift = Offset(.055 * math.sin(t * 2), -.028);
        overlay = const Color(0xFFEEEFFF);
        opacity = .05;
        saturation = .83;
        break;
      case 'Flash':
        brightness = .64 * _beat(t, 7.3, 28);
        break;
    }

    // The echo is a copy of the live picture, not a dummy edge stripe.
    if (imageEcho) {
      result = Stack(fit: StackFit.passthrough, children: [
        result,
        IgnorePointer(child: Opacity(opacity: echoOpacity.clamp(0, 1).toDouble(),
          child: FractionalTranslation(translation: echoShift, child: child))),
      ]);
    }
    if (channelEcho) {
      final separation = name == 'Shake + Scre...' ? .028 :
          name == 'Chromo-zoom' ? .034 : .020;
      result = Stack(fit: StackFit.passthrough, children: [
        result,
        IgnorePointer(child: Opacity(opacity: .34, child: FractionalTranslation(
          translation: Offset(-separation, .004),
          child: ColorFiltered(colorFilter: const ColorFilter.matrix([
            1, 0, 0, 0, 0,
            0, 0, 0, 0, 0,
            0, 0, 0, 0, 0,
            0, 0, 0, 1, 0,
          ]), child: child)))),
        IgnorePointer(child: Opacity(opacity: .30, child: FractionalTranslation(
          translation: Offset(separation, -.004),
          child: ColorFiltered(colorFilter: const ColorFilter.matrix([
            0, 0, 0, 0, 0,
            0, 1, 0, 0, 0,
            0, 0, 1, 0, 0,
            0, 0, 0, 1, 0,
          ]), child: child)))),
      ]);
    }
    if (negate) {
      result = ColorFiltered(colorFilter: const ColorFilter.matrix([
        -1, 0, 0, 0, 255,
        0, -1, 0, 0, 255,
        0, 0, -1, 0, 255,
        0, 0, 0, 1, 0,
      ]), child: result);
    }
    if (saturation != 1 || brightness != 0 || contrast != 1) {
      result = _tone(result, saturation, brightness, contrast);
    }
    if (sigma > 0) {
      result = ImageFiltered(imageFilter: ui.ImageFilter.blur(
          sigmaX: sigma, sigmaY: sigma), child: result);
    }
    if (roll != 0) {
      result = ColoredBox(color: Colors.black,
          child: Transform.rotate(angle: roll, child: result));
    }
    if (zoom != 1) result = Transform.scale(scale: zoom, child: result);
    if (fraction != Offset.zero) {
      result = FractionalTranslation(translation: fraction, child: result);
    }
    if (overlay != null && opacity > 0) {
      result = Stack(fit: StackFit.passthrough, children: [
        result,
        Positioned.fill(child: IgnorePointer(child: ColoredBox(
          color: overlay.withValues(alpha: opacity.clamp(0, 1).toDouble())))),
      ]);
    }
    if ({'Club lights', 'RGB Border', 'Neon', 'Disco', 'Colorful'}
        .contains(name)) {
      result = CustomPaint(
        foregroundPainter: _DynamicOverlayPainter(name, t), child: result);
    }
    return ClipRect(child: result);
  }

  static Widget _tone(Widget child, double saturation,
      double brightness, double contrast) {
    final k = 1 - saturation;
    final b = (brightness * 255) + (1 - contrast) * 127.5;
    return ColorFiltered(colorFilter: ColorFilter.matrix([
      (.2126 * k + saturation) * contrast, .7152 * k * contrast, .0722 * k * contrast, 0, b,
      .2126 * k * contrast, (.7152 * k + saturation) * contrast, .0722 * k * contrast, 0, b,
      .2126 * k * contrast, .7152 * k * contrast, (.0722 * k + saturation) * contrast, 0, b,
      0, 0, 0, 1, 0,
    ]), child: child);
  }
}

class _DynamicOverlayPainter extends CustomPainter {
  final String name;
  final double t;
  const _DynamicOverlayPainter(this.name, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final minor = math.min(size.width, size.height);
    if (name == 'Club lights') {
      // The reference contains beams entering from the top and sweeping over
      // the subject. The beams widen towards the bottom of the frame.
      for (var i = 0; i < 3; i++) {
        final sourceX = size.width * (.18 + i * .32);
        final aimX = sourceX + size.width * .42 * math.sin(t * (1.55 + i * .19) + i);
        final beam = Path()
          ..moveTo(sourceX - minor * .025, 0)
          ..lineTo(sourceX + minor * .025, 0)
          ..lineTo(aimX + minor * .48, size.height)
          ..lineTo(aimX - minor * .48, size.height)
          ..close();
        final glow = i == 1 ? const Color(0xB8FFB1E3) :
            const Color(0xAAFFF8C9);
        canvas.drawPath(beam, Paint()
          ..shader = ui.Gradient.linear(Offset(sourceX, 0),
              Offset(aimX, size.height),
              [glow, glow.withValues(alpha: .01)]));
        canvas.drawCircle(Offset(sourceX, 0), minor * .055,
            Paint()..color = glow.withValues(alpha: .85));
      }
    } else if (name == 'RGB Border' || name == 'Neon') {
      final neon = name == 'Neon';
      final core = neon ? const Color(0xFFFF536C) : const Color(0xFF658EFF);
      for (var i = 0; i < 5; i++) {
        final wide = (neon ? 29.0 : 22.0) - i * (neon ? 5.0 : 4.0);
        final c = i < 3 ? core.withValues(alpha: .12 + i * .13) :
            (neon ? const Color(0xFFFFD6DF) : const Color(0xFF9BEEFF));
        canvas.drawRRect(RRect.fromRectAndRadius(
          rect.deflate(wide / 2 + i * 2.0), const Radius.circular(5)),
          Paint()..color = c..style = PaintingStyle.stroke
            ..strokeWidth = wide);
      }
    } else if (name == 'Disco') {
      for (var i = 0; i < 3; i++) {
        final p = Offset(size.width * (.2 + .6 * math.sin(t * 1.7 + i).abs()),
            size.height * (.22 + .55 * math.cos(t * 1.4 + i).abs()));
        final hue = (290 + 26 * math.sin(t * 2 + i)) % 360;
        final color = HSLColor.fromAHSL(1, hue, 1, .60).toColor();
        canvas.drawCircle(p, minor * .55, Paint()..shader = ui.Gradient.radial(
          p, minor * .55, [color.withValues(alpha: .28),
            color.withValues(alpha: 0)]));
      }
    } else if (name == 'Colorful') {
      final hue = 42 + 18 * math.sin(t * 2.0);
      final c = HSLColor.fromAHSL(1, hue, .95, .58).toColor();
      canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(
        Offset.zero, Offset(size.width, size.height),
        [c.withValues(alpha: .11), Colors.transparent,
         const Color(0xFFEDC52B).withValues(alpha: .24)]));
    }
  }

  @override
  bool shouldRepaint(covariant _DynamicOverlayPainter oldDelegate) =>
      oldDelegate.name != name || oldDelegate.t != t;
}
