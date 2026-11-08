import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'crop_overlay_model.dart';
import 'crop_overlay_composition.dart';
import 'tini_edit_cache.dart';

class CropOverlayExport {
  static Future<String> render({
    required String input,
    required List<CropOverlay> overlays,
    required int durationMs,
    required int width,
    required int height,
  }) async {
    final fitted = overlays
        .map((o) => o.fit(durationMs))
        .whereType<CropOverlay>()
        .toList();
    if (fitted.isEmpty) return input;
    final cache = TiniEditCache.shared;
    final source = await cache.source(input);
    var ready = source;
    for (final overlay in fitted) {
      final asset = await cache.source(overlay.path);
      ready = TiniEditNode(
        stage: 'overlay.layer.v1',
        parameters: {
          'video': overlay.isVideo,
          'aspect': overlay.aspectRatio,
          'x': overlay.centerX,
          'y': overlay.centerY,
          'width': overlay.width,
          'start': overlay.startMs,
          'end': overlay.endMs,
          'sourceStart': overlay.sourceStartMs,
          'sourceDuration': overlay.sourceDurationMs,
          'durationMs': durationMs,
          'size': [width, height],
        },
        inputs: [ready, asset],
        extension: 'mkv',
        render: (i, stop) async {
          if (stop()) throw TiniEditCancelled();
          final root = await getTemporaryDirectory();
          final folder = await root.createTemp('tini_overlay_stage_');
          final output = '${folder.path}/layer.mkv';
          try {
            final session = await FFmpegKit.executeWithArguments(
              CropOverlayComposition.arguments(
                input: i[0].path,
                output: output,
                overlays: [overlay.copyWith(path: i[1].path)],
                durationMs: durationMs,
                width: width,
                height: height,
                lossless: true,
              ),
            );
            if (!ReturnCode.isSuccess(await session.getReturnCode()))
              throw StateError(
                'تعذر تجهيز التراكب: ${await session.getAllLogsAsString()}',
              );
            return TiniEditArtifact(output, temporary: true);
          } catch (_) {
            if (await folder.exists()) await folder.delete(recursive: true);
            rethrow;
          }
        },
      );
    }
    final delivery = TiniEditNode(
      stage: 'overlay.delivery.v1',
      retainGroup: 'editor.overlay.checkpoint',
      parameters: {
        'durationMs': durationMs,
        'size': [width, height],
        'crf': 18,
      },
      inputs: [ready, source],
      render: (i, stop) async {
        if (stop()) throw TiniEditCancelled();
        final root = await getTemporaryDirectory();
        final folder = await root.createTemp('tini_overlay_result_');
        final output = '${folder.path}/result.mp4';
        try {
          final session = await FFmpegKit.executeWithArguments([
            '-i',
            i[0].path,
            '-i',
            i[1].path,
            '-map',
            '0:v:0',
            '-map',
            '1:a?',
            '-c:v',
            'libx264',
            '-preset',
            'veryfast',
            '-crf',
            '18',
            '-pix_fmt',
            'yuv420p',
            '-c:a',
            'copy',
            '-t',
            '${durationMs / 1000}',
            '-movflags',
            '+faststart',
            '-y',
            output,
          ]);
          if (!ReturnCode.isSuccess(await session.getReturnCode()))
            throw StateError(
              'تعذر تجهيز التراكب: ${await session.getAllLogsAsString()}',
            );
          return TiniEditArtifact(output, temporary: true);
        } catch (_) {
          if (await folder.exists()) await folder.delete(recursive: true);
          rethrow;
        }
      },
    );
    return (await cache.run(delivery)).path;
  }
}
