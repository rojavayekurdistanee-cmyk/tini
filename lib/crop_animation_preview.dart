import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'crop_animation_model.dart';

/// The same non-destructive video texture is used for both thumbnails and
/// timeline previews. Time is supplied by the real video playhead.
class CropAnimationPreview extends StatelessWidget {
  final CropAnimationSettings settings;
  final Duration elapsed;
  final Duration clipDuration;
  final Widget child;

  const CropAnimationPreview({super.key, required this.settings,
    required this.elapsed, required this.clipDuration, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!settings.hasEffects || clipDuration.inMicroseconds <= 0) return child;
    final length = clipDuration.inMicroseconds / 1000000.0;
    final time = (elapsed.inMicroseconds / 1000000.0).clamp(0.0, length).toDouble();
    var content = child;
    if (settings.group != null) {
      final period = settings.groupSeconds.clamp(.2, length > .2 ? length : .2).toDouble();
      content = animationVisual(settings.group!, (time % period) / period, content);
    }
    if (settings.start != null) {
      final duration = settings.startSeconds.clamp(.1, length).toDouble();
      if (time < duration) {
        content = animationVisual(settings.start!, time / duration, content);
      }
    }
    if (settings.end != null) {
      final duration = settings.endSeconds.clamp(.1, length).toDouble();
      if (time > length - duration) {
        content = animationVisual(settings.end!, (time - (length - duration)) / duration, content);
      }
    }
    return ClipRect(child: content);
  }


  static const _grey = <double>[
    .2126, .7152, .0722, 0, 0,
    .2126, .7152, .0722, 0, 0,
    .2126, .7152, .0722, 0, 0,
    0, 0, 0, 1, 0,
  ];
  static const _negative = <double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ];

  static Widget _tint(Widget child, Color color, double amount) =>
      ColorFiltered(colorFilter: ColorFilter.mode(
          color.withOpacity(amount.clamp(0.0, 1.0)), BlendMode.screen),
        child: child);

  /// Continuous saturation/brightness changes mirror the export timing.
  static Widget _saturate(Widget child, double saturation) {
    final s = saturation.clamp(0.0, 1.0);
    final k = 1 - s;
    return ColorFiltered(colorFilter: ColorFilter.matrix([
      .2126 * k + s, .7152 * k, .0722 * k, 0, 0,
      .2126 * k, .7152 * k + s, .0722 * k, 0, 0,
      .2126 * k, .7152 * k, .0722 * k + s, 0, 0,
      0, 0, 0, 1, 0,
    ]), child: child);
  }

  static Widget _brightness(Widget child, double amount) {
    final delta = amount.clamp(-1.0, 1.0) * 255;
    return ColorFiltered(colorFilter: ColorFilter.matrix([
      1, 0, 0, 0, delta,
      0, 1, 0, 0, delta,
      0, 0, 1, 0, delta,
      0, 0, 0, 1, 0,
    ]), child: child);
  }

  static Widget _rotateHue(Widget child, double radians) {
    final c = math.cos(radians);
    final si = math.sin(radians);
    return ColorFiltered(colorFilter: ColorFilter.matrix([
      .213 + .787 * c - .213 * si, .715 - .715 * c - .715 * si,
          .072 - .072 * c + .928 * si, 0, 0,
      .213 - .213 * c + .143 * si, .715 + .285 * c + .140 * si,
          .072 - .072 * c - .283 * si, 0, 0,
      .213 - .213 * c - .787 * si, .715 - .715 * c + .715 * si,
          .072 + .928 * c + .072 * si, 0, 0,
      0, 0, 0, 1, 0,
    ]), child: child);
  }

  static Widget animationVisual(String id, double progress, Widget child) {
    final t = progress.clamp(0.0, 1.0).toDouble();
    final wave = math.sin(t * math.pi * 2);
    switch (id) {
      case 'fade_in': return Opacity(opacity: t, child: child);
      case 'fade_out': return Opacity(opacity: 1 - t, child: child);
      case 'slide_in':
        return FractionalTranslation(translation: Offset(1 - t, 0), child: child);
      case 'slide_in_left':
        return FractionalTranslation(translation: Offset(t - 1, 0), child: child);
      case 'slide_out':
        return FractionalTranslation(translation: Offset(t, 0), child: child);
      case 'slide_out_left':
        return FractionalTranslation(translation: Offset(-t, 0), child: child);
      case 'rise_in':
        return Opacity(opacity: t, child: FractionalTranslation(
          translation: Offset(0, 1 - t), child: child));
      case 'fall_out':
        return Opacity(opacity: 1 - t, child: FractionalTranslation(
          translation: Offset(0, t), child: child));
      case 'zoom_in':
        return Transform.scale(scale: .55 + t * .45, child: Opacity(opacity: t, child: child));
      case 'zoom_out':
        return Transform.scale(scale: 1 - .45 * t,
            child: Opacity(opacity: 1 - t, child: child));
      case 'fold_in':
        return Transform.scale(scaleX: .02 + .98 * t,
            child: Opacity(opacity: t, child: child));
      case 'fold_out':
        return Transform.scale(scaleX: 1 - .98 * t,
            child: Opacity(opacity: 1 - t, child: child));
      case 'dynamic_shake':
        return Transform.translate(offset: Offset(8 * math.sin(t * math.pi * 16),
            5 * math.cos(t * math.pi * 22)),
            child: Transform.scale(scale: 1.06, child: child));
      case 'vertical_glitch':
        return Transform.translate(offset: Offset(2 * wave,
            11 * math.sin(t * math.pi * 12)),
            child: Transform.scale(scale: 1.06, child: child));
      case 'pendulum':
        return Transform.rotate(angle: .13 * wave, child: child);
      case 'pulse':
        return Transform.scale(scale: 1 + .085 * (1 + wave) / 2, child: child);
      case 'float':
        return Transform.translate(offset: Offset(0, wave * 10), child: child);
      case 'rock':
        return Transform.rotate(angle: .045 * math.sin(t * math.pi * 4), child: child);
      // Additional start effects. Fade/shutter/blur approximations use the
      // same temporal boundaries as the exported FFmpeg filters.
      case 'spin_in': return Opacity(opacity: t,
        child: Transform.rotate(angle: 2 * math.pi * (1 - t), child: child));
      case 'drop_in': return FractionalTranslation(
        translation: Offset(0, t - 1), child: child);
      case 'diagonal_in': return FractionalTranslation(
        translation: Offset(1 - t, 1 - t), child: child);
      case 'mirror_in': return Opacity(opacity: t, child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..setEntry(3, 2, .001)
          ..rotateY(math.pi * (1 - t)), child: child));
      case 'blur_in': return Opacity(opacity: t,
        child: ImageFiltered(imageFilter: ui.ImageFilter.blur(
          sigmaX: t < .55 ? 7 : 0, sigmaY: t < .55 ? 7 : 0), child: child));
      case 'flash_in': return _brightness(child, .55 * (1 - t));
      case 'mono_in': return _saturate(child, t);
      case 'negative_in': return Opacity(opacity: t,
        child: t < .55 ? ColorFiltered(
          colorFilter: const ColorFilter.matrix(_negative), child: child) : child);
      case 'bounce_in': return Transform.scale(
        scale: 1 + .45 * (1 - t) - .08 * math.sin(2 * math.pi * t), child: child);
      case 'shutter_in': return Opacity(opacity: t, child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..setEntry(3, 2, .001)
          ..rotateX(math.pi * (1 - t)), child: child));
      // Additional end effects.
      case 'spin_out': return Opacity(opacity: 1 - t,
        child: Transform.rotate(angle: 2 * math.pi * t, child: child));
      case 'lift_out': return FractionalTranslation(
        translation: Offset(0, -t), child: child);
      case 'diagonal_out': return FractionalTranslation(
        translation: Offset(t, t), child: child);
      case 'mirror_out': return Opacity(opacity: 1 - t, child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..setEntry(3, 2, .001)
          ..rotateY(math.pi * t), child: child));
      case 'blur_out': return Opacity(opacity: 1 - t,
        child: ImageFiltered(imageFilter: ui.ImageFilter.blur(
          sigmaX: t > .45 ? 7 : 0, sigmaY: t > .45 ? 7 : 0), child: child));
      case 'flash_out': return _brightness(child, .55 * t);
      case 'mono_out': return _saturate(child, 1 - t);
      case 'negative_out': return Opacity(opacity: 1 - t,
        child: t > .45 ? ColorFiltered(
          colorFilter: const ColorFilter.matrix(_negative), child: child) : child);
      case 'bounce_out': return Opacity(opacity: 1 - t,
        child: Transform.scale(scale: 1 + .45 * t, child: child));
      case 'shutter_out': return Opacity(opacity: 1 - t, child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..setEntry(3, 2, .001)
          ..rotateX(math.pi * t), child: child));
      // Additional loop effects. The phase repeats with groupSeconds.
      case 'orbit': return Transform.translate(offset: Offset(12 * math.cos(2 * math.pi * t),
          12 * math.sin(2 * math.pi * t)),
        child: Transform.scale(scale: 1.08, child: child));
      case 'full_spin': return Transform.rotate(angle: 2 * math.pi * t, child: child);
      case 'rainbow': return _rotateHue(child, 2 * math.pi * t);
      case 'strobe': return _tint(child, Colors.white, t < 1 / 6 ? .65 : 0);
      case 'flip_h_loop': return Transform.scale(scaleX: t < .5 ? -1 : 1, child: child);
      case 'flip_v_loop': return Transform.scale(scaleY: t < .5 ? -1 : 1, child: child);
      case 'negative_loop': return t < .5 ? ColorFiltered(
        colorFilter: const ColorFilter.matrix(_negative), child: child) : child;
      case 'greyscale_loop': return t < .5 ? ColorFiltered(
        colorFilter: const ColorFilter.matrix(_grey), child: child) : child;
      case 'grid_flash': return t < .5 ? CustomPaint(
        foregroundPainter: const _AnimationGridPainter(), child: child) : child;
      case 'exposure_wave': return _brightness(child, .22 * wave);
      default: return child;
    }
  }
}

/// Grid is painted on top of the current video frame; it never changes layout.
class _AnimationGridPainter extends CustomPainter {
  const _AnimationGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(.45)..strokeWidth = 2;
    for (var x = 0.0; x < size.width; x += size.width / 12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += size.height / 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
