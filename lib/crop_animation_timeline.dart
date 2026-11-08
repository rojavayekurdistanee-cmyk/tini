import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'crop_animation_model.dart';

/// Translucent, time-accurate animation lanes on an RTL clip timeline.
/// Start is anchored to the right; End is anchored to the left. Group covers
/// the clip, with divisions showing its editable repeating cycle duration.
/// Only the small inner-edge handles capture gestures; normal scrubbing,
/// trimming, clip selection and transition controls keep their original hit areas.
class CropAnimationTimelineOverlay extends StatefulWidget {
  final CropAnimationSettings settings;
  final double clipSeconds;
  final double pixelsPerSecond;
  final bool editable;
  final void Function(CropAnimationTab tab, double seconds, bool finished) onResize;

  const CropAnimationTimelineOverlay({super.key, required this.settings,
    required this.clipSeconds, required this.pixelsPerSecond,
    required this.editable, required this.onResize});

  @override
  State<CropAnimationTimelineOverlay> createState() =>
      _CropAnimationTimelineOverlayState();
}

class _CropAnimationTimelineOverlayState
    extends State<CropAnimationTimelineOverlay> {
  double _startingSeconds = 0;
  double _travel = 0;
  double _lastSentSeconds = 0;

  Color _tintFor(String id) => HSVColor.fromAHSV(1,
      CropAnimationCatalog.hueFor(id), .78, .98).toColor();

  void _begin(CropAnimationTab tab) {
    _startingSeconds = widget.settings.seconds(tab);
    _lastSentSeconds = _startingSeconds;
    _travel = 0;
  }

  void _update(CropAnimationTab tab, double dx) {
    _travel += dx;
    // The RTL start and group inner edges move left to grow; the end inner
    // edge moves right to grow. Use absolute touch-down delta to avoid drift.
    final direction = tab == CropAnimationTab.end ? 1.0 : -1.0;
    final pixels = math.max(.001, widget.pixelsPerSecond);
    final lower = tab == CropAnimationTab.group ? .2 : .1;
    final next = (_startingSeconds + direction * _travel / pixels)
        .clamp(lower, math.max(lower, widget.clipSeconds)).toDouble();
    _lastSentSeconds = next;
    widget.onResize(tab, next, false);
  }

  Widget _handle(double x, double y, double laneHeight,
      CropAnimationTab tab, Color tint) {
    return Positioned(
      left: x - 13,
      top: y,
      width: 26,
      height: laneHeight,
      child: Semantics(
        label: 'اسحب لتغيير مدة تأثير ${tab == CropAnimationTab.start ? "البداية" : tab == CropAnimationTab.end ? "النهاية" : "المجموعة"}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _begin(tab),
          onHorizontalDragUpdate: (details) => _update(tab, details.delta.dx),
          onHorizontalDragEnd: (_) => widget.onResize(tab,
              _lastSentSeconds, true),
          onHorizontalDragCancel: () => widget.onResize(tab,
              _lastSentSeconds, true),
          child: Center(child: Container(
            width: 5,
            height: math.max(9.0, laneHeight * .70),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [BoxShadow(color: tint.withOpacity(.9), blurRadius: 4)],
            ),
          )),
        ),
      ),
    );
  }

  Widget _lane({required double x, required double y, required double width,
      required double height, required String id, required String label}) {
    final tint = _tintFor(id);
    return Positioned(left: x, top: y, width: width, height: height,
      child: IgnorePointer(child: DecoratedBox(
        decoration: BoxDecoration(color: tint.withOpacity(.32),
          border: Border.symmetric(horizontal: BorderSide(
            color: tint.withOpacity(.75), width: 1))),
        child: width > 54 ? Align(alignment: Alignment.center,
          child: Text(label, textDirection: TextDirection.rtl,
            textAlign: TextAlign.center, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 9,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black87, blurRadius: 2)])))
            : const SizedBox.shrink(),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.hasEffects || widget.clipSeconds <= 0) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final row = box.maxHeight / 3;
      if (width <= 0 || row <= 0) return const SizedBox.shrink();
      final children = <Widget>[];
      final data = widget.settings;

      if (data.start != null) {
        final seconds = data.startSeconds.clamp(.1, widget.clipSeconds).toDouble();
        final pixels = math.min(width, seconds * widget.pixelsPerSecond);
        final x = width - pixels;
        children.add(_lane(x: x, y: 0, width: pixels,
          height: row, id: data.start!, label: 'بداية ${seconds.toStringAsFixed(1)}ث'));
        if (widget.editable) {
          children.add(_handle(x, 0, row, CropAnimationTab.start,
              _tintFor(data.start!)));
        }
      }
      if (data.group != null) {
        final period = data.groupSeconds.clamp(.1, widget.clipSeconds).toDouble();
        final pixels = math.max(1.0, period * widget.pixelsPerSecond);
        children.add(_lane(x: 0, y: row, width: width,
          height: row, id: data.group!, label: 'مجموعة ${period.toStringAsFixed(1)}ث'));
        // Period tick marks visibly change spacing when the cycle is resized.
        final count = math.min(100, (width / pixels).floor());
        final tint = _tintFor(data.group!);
        for (var i = 1; i <= count; i++) {
          final x = width - pixels * i;
          if (x <= 0 || x >= width) continue;
          children.add(Positioned(left: x, top: row + 2, width: 1,
            height: math.max(0.0, row - 4), child: IgnorePointer(
              child: ColoredBox(color: tint.withOpacity(.9)))));
        }
        if (widget.editable) {
          children.add(_handle(width - math.min(width, pixels), row, row,
              CropAnimationTab.group, tint));
        }
      }
      if (data.end != null) {
        final seconds = data.endSeconds.clamp(.1, widget.clipSeconds).toDouble();
        final pixels = math.min(width, seconds * widget.pixelsPerSecond);
        children.add(_lane(x: 0, y: row * 2, width: pixels,
          height: row, id: data.end!, label: 'نهاية ${seconds.toStringAsFixed(1)}ث'));
        if (widget.editable) {
          children.add(_handle(pixels, row * 2, row, CropAnimationTab.end,
              _tintFor(data.end!)));
        }
      }
      return Stack(clipBehavior: Clip.hardEdge, children: children);
    });
  }
}
