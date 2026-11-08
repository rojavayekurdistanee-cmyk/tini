import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lightweight, bounded Magic feedback for the video editor.
///
/// The parent MUST give this widget the exact video dimensions (typically as
/// the child of an AspectRatio). Otherwise a frame would paint on letterboxing.
/// No decoder or FFmpeg job is created while the user previews a Magic choice.
/// Higher-quality versions are applied at export by crop_magic_effects.dart.
class CropMagicLivePreview extends StatefulWidget {
  final String? effectId;
  final Widget child;

  const CropMagicLivePreview({
    super.key,
    required this.effectId,
    required this.child,
  });

  @override
  State<CropMagicLivePreview> createState() => _CropMagicLivePreviewState();
}

class _CropMagicLivePreviewState extends State<CropMagicLivePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.effectId != null) _animation.repeat();
  }

  @override
  void didUpdateWidget(CropMagicLivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.effectId != oldWidget.effectId) {
      if (widget.effectId == null) {
        _animation.stop();
      } else {
        _animation.repeat();
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.effectId;
    if (id == null) return widget.child;
    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, video) => _paint(id, _animation.value, video!),
    );
  }

  Widget _paint(String id, double progress, Widget content) {
    final t = math.pi * 2 * progress;
    Widget? overlay;
    switch (id) {
      case 'cinematic_zoom':
        content = Transform.scale(
          scale: 1.04 + .25 * (1 - math.cos(t)) / 2,
          child: content,
        );
        break;
      case 'whip_pan':
        content = Transform.translate(
          offset: Offset(math.sin(t) * 29, 0),
          child: Transform.scale(scale: 1.26, child: content),
        );
        break;
      case 'impact_shake':
        content = Transform.translate(
          offset: Offset(math.sin(t * 17) * 9, math.sin(t * 23) * 7),
          child: Transform.scale(scale: 1.12, child: content),
        );
        break;
      case 'motion_echo':
        // Keep the live editor responsive: paint two offset ghost layers from
        // the existing video texture without starting another decoder. Ghosts
        // MUST be above the opaque source or they are entirely concealed.
        // The export graph uses actual earlier frames for temporal trailing.
        content = Stack(fit: StackFit.expand, children: [
          content,
          IgnorePointer(child: Opacity(
            opacity: .43,
            child: Transform.translate(
              offset: Offset(-20 - 7 * math.sin(t), -2),
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Color(0xFF00D8DB), BlendMode.screen),
                child: content,
              ),
            ),
          )),
          IgnorePointer(child: Opacity(
            opacity: .31,
            child: Transform.translate(
              offset: Offset(19 + 6 * math.sin(t - .7), 2),
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Color(0xFFFF397B), BlendMode.screen),
                child: content,
              ),
            ),
          )),
        ]);
        break;
      case 'rgb_glitch':
        content = ColorFiltered(
          colorFilter: ColorFilter.mode(
            progress < .5
                ? const Color(0x66FF244A)
                : const Color(0x66399FFF),
            BlendMode.screen,
          ),
          child: content,
        );
        overlay = CustomPaint(painter: _MagicGlitchPainter(progress));
        break;
      case 'flash_beat':
        overlay = ColoredBox(
          color: Colors.white.withOpacity(
            math.pow((1 + math.sin(t * 2)) / 2, 5).toDouble() * .36,
          ),
        );
        break;
      case 'freeze_focus':
        final focus = progress > .30 && progress < .62;
        content = Transform.scale(
          scale: focus ? 1.19 : 1.0,
          child: content,
        );
        if (focus) {
          overlay = DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 3),
            ),
          );
        }
        break;
      case 'kaleidoscope':
        content = Row(children: [
          Expanded(child: ClipRect(child: content)),
          Expanded(child: ClipRect(child: Transform.flip(
            flipX: true,
            child: content,
          ))),
        ]);
        break;
      case 'dynamic_split':
        content = Column(children: [
          Expanded(child: Row(children: [
            Expanded(child: ClipRect(child: content)),
            Expanded(child: ClipRect(child: Transform.flip(
              flipX: true,
              child: content,
            ))),
          ])),
          Expanded(child: Row(children: [
            Expanded(child: ClipRect(child: Transform.flip(
              flipY: true,
              child: content,
            ))),
            Expanded(child: ClipRect(child: Transform.flip(
              flipX: true,
              flipY: true,
              child: content,
            ))),
          ])),
        ]);
        overlay = CustomPaint(painter: _MagicGridPainter());
        break;
      case 'vhs_retro':
        content = ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Color(0x5590A0AE), BlendMode.srcATop,
          ),
          child: content,
        );
        overlay = CustomPaint(painter: _MagicScanlinePainter());
        break;
      case 'light_leak':
        overlay = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + progress * 2, -1),
              end: Alignment(1 - progress * 2, 1),
              colors: const [
                Color(0x00FF9000),
                Color(0x88FF951E),
                Color(0x00FF7000),
              ],
            ),
          ),
        );
        break;
      case 'cinema_frame':
        // Black on black was invisible on videos with existing letterboxing.
        // Apply a subtle cinema grade and paint visible picture-edge lines,
        // entirely inside the actual video rectangle.
        content = ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            1.06, 0, 0, 0, -9,
            0, 1.03, 0, 0, -7,
            0, 0, .94, 0, -4,
            0, 0, 0, 1, 0,
          ]),
          child: content,
        );
        overlay = const CustomPaint(painter: _MagicCinemaFramePainter());
        break;
      case 'neon_frame':
        final brightness = .70 + .30 * (1 + math.sin(t)) / 2;
        overlay = Container(
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.tealAccent.withOpacity(brightness),
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.tealAccent.withOpacity(.25 * brightness),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
        );
        break;
      case 'film_strip':
        overlay = CustomPaint(painter: _MagicFilmStripPainter());
        break;
      case 'floating_frame':
        return ClipRect(child: ColoredBox(
          color: const Color(0xFF1A222C),
          child: Center(child: FractionallySizedBox(
            widthFactor: .80,
            heightFactor: .80,
            child: Transform.translate(
              offset: Offset(0, math.sin(t) * 5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 9),
                  ],
                ),
                child: ClipRect(child: content),
              ),
            ),
          )),
        ));
    }

    if (overlay == null) return ClipRect(child: content);
    return ClipRect(child: Stack(fit: StackFit.expand, children: [
      content,
      IgnorePointer(child: overlay),
    ]));
  }
}


/// Letterbox and fine picture-edge lines, aligned to the *video* viewport.
/// The lines stay visible even when the source already has black borders.
class _MagicCinemaFramePainter extends CustomPainter {
  const _MagicCinemaFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final band = size.height * .14;
    final black = Paint()..color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, band), black);
    canvas.drawRect(Rect.fromLTWH(
      0, size.height - band, size.width, band), black);
    final edge = Paint()
      ..color = const Color(0xBBDCE1E6)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, band), Offset(size.width, band), edge);
    canvas.drawLine(Offset(0, size.height - band),
      Offset(size.width, size.height - band), edge);
  }

  @override
  bool shouldRepaint(covariant _MagicCinemaFramePainter oldDelegate) => false;
}
class _MagicGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _MagicGridPainter oldDelegate) => false;
}

class _MagicScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x66000000)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 6) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MagicScanlinePainter oldDelegate) => false;
}

class _MagicGlitchPainter extends CustomPainter {
  final double progress;
  const _MagicGlitchPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shift = (progress * 7).floor();
    final p = Paint();
    for (int i = 0; i < 4; i++) {
      final y = (i * 0.21 + .11 + .04 * math.sin(progress * 12 + i)) *
          size.height;
      p.color = (i + shift).isEven
          ? const Color(0x77FF2B63)
          : const Color(0x6605F1E6);
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width * (.45 + .12 * i), 2 + (i % 3)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MagicGlitchPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _MagicFilmStripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final band = size.width * .10;
    final black = Paint()..color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(0, 0, band, size.height), black);
    canvas.drawRect(
      Rect.fromLTWH(size.width - band, 0, band, size.height), black);
    final hole = Paint()..color = const Color(0xFFE8E2D5);
    for (int i = 0; i < 9; i++) {
      final y = size.height * (i + .25) / 9;
      final h = size.height * .045;
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(band * .26, y, band * .48, h),
        const Radius.circular(2)), hole);
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - band * .74, y, band * .48, h),
        const Radius.circular(2)), hole);
    }
  }

  @override
  bool shouldRepaint(covariant _MagicFilmStripPainter oldDelegate) => false;
}
