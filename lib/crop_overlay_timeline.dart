import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'crop_overlay_model.dart';

/// Every layer owns a project-time track. The handles adjust visibility only;
/// dragging the middle moves the interval without changing its source in-point.
class CropOverlayTimeline extends StatelessWidget {
  final List<CropOverlay> overlays;
  final int durationMs, positionMs;
  final String? selectedId;
  final List<Uint8List> baseFrames;
  final Map<String, Uint8List> layerFrames;
  final ValueChanged<String> onSelect;
  final ValueChanged<int> onSeek;
  final ValueChanged<CropOverlay> onChanged;
  final VoidCallback onEditStart, onEditEnd;
  const CropOverlayTimeline({
    super.key,
    required this.overlays,
    required this.durationMs,
    required this.positionMs,
    this.selectedId,
    this.baseFrames = const [],
    this.layerFrames = const {},
    required this.onSelect,
    required this.onSeek,
    required this.onChanged,
    required this.onEditStart,
    required this.onEditEnd,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final span = math.max(1, durationMs);
      final width = math.max(
        constraints.maxWidth,
        (span / 1000 * 32).clamp(0, 21600).toDouble(),
      );
      int milliseconds(double pixels) => (pixels / width * span).round();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 23,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 0; i <= 5; i++)
                          Text(
                            '${(span / 1000 * i / 5).toStringAsFixed(1)}ث',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => onSeek(
                      milliseconds(d.localPosition.dx).clamp(0, span - 1),
                    ),
                    onHorizontalDragUpdate: (d) => onSeek(
                      milliseconds(d.localPosition.dx).clamp(0, span - 1),
                    ),
                    child: Container(
                      height: 52,
                      margin: const EdgeInsets.only(bottom: 9),
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: baseFrames.isEmpty
                          ? const Center(
                              child: Icon(
                                Icons.movie_outlined,
                                color: Colors.white54,
                              ),
                            )
                          : Row(
                              children: [
                                for (
                                  var i = 0;
                                  i < math.max(1, (width / 48).ceil());
                                  i++
                                )
                                  Expanded(
                                    child: Image.memory(
                                      baseFrames[i % baseFrames.length],
                                      height: 52,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  for (final o in overlays)
                    SizedBox(
                      height: 55,
                      child: Stack(
                        children: [
                          Positioned(
                            left: width * o.startMs / span,
                            width: math.max(
                              44,
                              width * (o.endMs - o.startMs) / span,
                            ),
                            height: 46,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: selectedId == o.id
                                    ? const Color(0xFF245B61)
                                    : const Color(0xFF26323B),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: selectedId == o.id
                                      ? Colors.white
                                      : Colors.white30,
                                  width: selectedId == o.id ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  _handle('بداية التراكب', (delta) {
                                    final start =
                                        (o.startMs + milliseconds(delta)).clamp(
                                          0,
                                          math.max(0, o.endMs - 100),
                                        );
                                    onChanged(
                                      o.copyWith(startMs: start.toInt()),
                                    );
                                  }),
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        onSelect(o.id);
                                        onSeek(o.startMs);
                                      },
                                      onHorizontalDragStart: (_) {
                                        onSelect(o.id);
                                        onEditStart();
                                      },
                                      onHorizontalDragUpdate: (d) {
                                        final start =
                                            (o.startMs +
                                                    milliseconds(d.delta.dx))
                                                .clamp(
                                                  0,
                                                  math.max(
                                                    0,
                                                    span -
                                                        (o.endMs - o.startMs),
                                                  ),
                                                );
                                        onChanged(
                                          o.copyWith(
                                            startMs: start.toInt(),
                                            endMs: (start + o.endMs - o.startMs)
                                                .toInt(),
                                          ),
                                        );
                                      },
                                      onHorizontalDragEnd: (_) => onEditEnd(),
                                      onHorizontalDragCancel: onEditEnd,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          if (layerFrames[o.id] != null)
                                            Image.memory(
                                              layerFrames[o.id]!,
                                              fit: BoxFit.cover,
                                              gaplessPlayback: true,
                                            ),
                                          const ColoredBox(
                                            color: Color(0x55000000),
                                          ),
                                          Center(
                                            child: Icon(
                                              o.isVideo
                                                  ? Icons.videocam_outlined
                                                  : Icons.image_outlined,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  _handle(
                                    'نهاية التراكب',
                                    (delta) => onChanged(
                                      o.copyWith(
                                        endMs: (o.endMs + milliseconds(delta))
                                            .clamp(
                                              math.min(span, o.startMs + 100),
                                              span,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: width * positionMs.clamp(0, span) / span,
                child: const IgnorePointer(
                  child: SizedBox(
                    width: 2,
                    child: ColoredBox(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _handle(String label, ValueChanged<double> onDelta) => Semantics(
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => onEditStart(),
      onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
      onHorizontalDragEnd: (_) => onEditEnd(),
      onHorizontalDragCancel: onEditEnd,
      child: const SizedBox(
        width: 18,
        height: 46,
        child: Icon(Icons.drag_indicator, color: Colors.white, size: 14),
      ),
    ),
  );
}
