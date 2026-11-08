import 'dart:math' as math;
import 'crop_overlay_model.dart';

/// Shared, testable export arguments. Paths are separate argv entries, never
/// interpolated into filter expressions or a shell command.
class CropOverlayComposition {
  static List<String> arguments({
    required String input,
    required String output,
    required List<CropOverlay> overlays,
    required int durationMs,
    required int width,
    required int height,
    bool lossless = false,
  }) {
    final layers = overlays
        .map((o) => o.fit(durationMs))
        .whereType<CropOverlay>()
        .where(
          (o) =>
              o.centerX + o.width / 2 > 0 &&
              o.centerX - o.width / 2 < 1 &&
              o.centerY + o.height(width / height) / 2 > 0 &&
              o.centerY - o.height(width / height) / 2 < 1,
        )
        .toList();
    final args = <String>['-i', input];
    final graph = <String>['[0:v]setpts=PTS-STARTPTS[base0]'];
    String number(num n) => n.toStringAsFixed(6);
    for (var i = 0; i < layers.length; i++) {
      final o = layers[i];
      if (!o.isVideo) args.addAll(['-loop', '1', '-framerate', '30']);
      args.addAll(['-i', o.path]);
      final start = o.startMs / 1000.0;
      final span = (o.endMs - o.startMs) / 1000.0;
      final ow = (width * o.width).round().clamp(2, width * 8);
      final oh = math.max(2, (ow / o.aspectRatio).round());
      final x = (width * o.centerX - ow / 2).round();
      final y = (height * o.centerY - oh / 2).round();
      // Crop in source coordinates before scaling. Even an 800% layer only
      // allocates the visible output rectangle, rather than a giant bitmap.
      final left = math.max(0, x), top = math.max(0, y);
      final visibleW = math.max(1, math.min(width, x + ow) - left);
      final visibleH = math.max(1, math.min(height, y + oh) - top);
      final sourceAt = o.isVideo
          ? o.sourceStartMs.clamp(0, math.max(0, o.sourceDurationMs - 40))
          : 0;
      graph.add(
        '[${i + 1}:v]trim=start=${number(sourceAt / 1000)},'
        'setpts=PTS-STARTPTS,format=rgba,'
        "crop=w='max(1,iw*${number(visibleW / ow)})':"
        "h='max(1,ih*${number(visibleH / oh)})':"
        "x='iw*${number((left - x) / ow)}':y='ih*${number((top - y) / oh)}':exact=1,"
        'scale=$visibleW:$visibleH,setsar=1,fps=30,'
        'tpad=stop_mode=clone:stop_duration=${number(span)},'
        'trim=duration=${number(span)},setpts=PTS+${number(start)}/TB[layer$i]',
      );
      graph.add(
        '[base$i][layer$i]overlay=x=$left:y=$top:'
        "enable='gte(t,${number(start)})*lt(t,${number(o.endMs / 1000)})':"
        'eof_action=pass:repeatlast=1:format=auto[base${i + 1}]',
      );
    }
    graph.add(
      '[base${layers.length}]format=${lossless ? 'bgra' : 'yuv420p'}[vout]',
    );
    args.addAll([
      '-filter_complex_threads',
      '1',
      '-filter_complex',
      graph.join(';'),
      '-map',
      '[vout]',
      if (!lossless) ...['-map', '0:a?'],
      '-t',
      number(durationMs / 1000),
      '-r',
      '30',
      '-c:v',
      lossless ? 'ffv1' : 'libx264',
      if (lossless) ...[
        '-level',
        '3',
      ] else ...[
        '-preset',
        'veryfast',
        '-crf',
        '18',
      ],
      '-pix_fmt',
      lossless ? 'bgra' : 'yuv420p',
      if (lossless) '-an' else ...['-c:a', 'copy', '-movflags', '+faststart'],
      '-y',
      output,
    ]);
    return args;
  }
}
