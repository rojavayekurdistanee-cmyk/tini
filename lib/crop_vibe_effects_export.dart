import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'crop_effects_model.dart';
import 'tini_edit_cache.dart';
import 'tini_edit_directory_cache.dart';
import 'crop_vibe_effects_painter.dart';

/// Alpha overlay renderer for Vibe. Produces exactly the same procedural
/// strokes/shapes as the Flutter live preview, then composes them with FFmpeg.
/// Existing clip audio is stream-copied. In particular, a failed overlay must
/// NEVER be silently replaced with the unmodified video.
class TiniVibeEffectsExport {
  static bool hasVibe(List<TiniAppliedEffect> effects) => effects.any((fx) {
    final descriptor = fx.descriptor;
    return descriptor != null &&
        descriptor.category == TiniVibeEffectsPainter.category &&
        descriptor.available &&
        fx.endSeconds > fx.startSeconds;
  });

  static Future<String> compose({
    required String inputPath,
    required List<TiniAppliedEffect> effects,
    required double seconds,
    required int width,
    required int height,
    bool lossless = false,
    bool Function()? cancelled,
  }) async {
    final relevant = effects
        .where(
          (fx) =>
              fx.descriptor?.category == TiniVibeEffectsPainter.category &&
              fx.descriptor?.available == true &&
              fx.endSeconds > fx.startSeconds,
        )
        .toList(growable: false);
    if (relevant.isEmpty) return inputPath;
    if (seconds <= 0 || width <= 0 || height <= 0) {
      throw StateError('Invalid dimensions or duration for Vibe overlay');
    }

    // Export at reduced overlay resolution to bound time, RAM and disk use.
    // Pixel geometry is shared with the preview and scaled over the video.
    const fps = 15;
    final scale = math.min(1.0, 720.0 / math.max(width, height).toDouble());
    final overlayWidth = math.max(2, (width * scale).round());
    final overlayHeight = math.max(2, (height * scale).round());
    final start = relevant
        .map((fx) => fx.startSeconds)
        .reduce(math.min)
        .clamp(0.0, seconds)
        .toDouble();
    final end = relevant
        .map((fx) => fx.endSeconds)
        .reduce(math.max)
        .clamp(0.0, seconds)
        .toDouble();
    if (end <= start) return inputPath;
    final frameCount = math.max(2, ((end - start) * fps).ceil() + 1);
    final saved = await TiniEditDirectoryCache.obtain(
      stage: 'vibe.overlay.frames.v1',
      parameters: {
        'effects': [
          for (final e in relevant) [e.id, e.startSeconds, e.endSeconds],
        ],
        'size': [overlayWidth, overlayHeight],
        'start': start,
        'end': end,
        'fps': fps,
      },
      sources: [],
      cancelled: cancelled,
      build: (inputs, stop) async {
        final temp = await getTemporaryDirectory();
        final folder = await temp.createTemp('tini_vibe_frames_');
        try {
          for (var i = 0; i < frameCount; i++) {
            if (stop()) throw TiniEditCancelled();
            final time = math.min(end - .00001, start + i / fps);
            final recorder = ui.PictureRecorder();
            final canvas = ui.Canvas(recorder);
            TiniVibeEffectsPainter.draw(
              canvas,
              ui.Size(overlayWidth.toDouble(), overlayHeight.toDouble()),
              relevant,
              time,
            );
            final picture = recorder.endRecording();
            try {
              final frame = await picture.toImage(overlayWidth, overlayHeight);
              try {
                final bytes = await frame.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (bytes == null)
                  throw StateError('Could not encode Vibe overlay PNG');
                final number = i.toString().padLeft(6, '0');
                await File(
                  '${folder.path}/frame_$number.png',
                ).writeAsBytes(bytes.buffer.asUint8List(), flush: false);
              } finally {
                frame.dispose();
              }
            } finally {
              picture.dispose();
            }
            // Keep longer exports responsive; no allocation of full-frame lists.
            if (i % 8 == 0) await Future<void>.delayed(Duration.zero);
          }

          return TiniEditDirectoryResult(folder.path, {
            'frames': frameCount,
            'fps': fps,
          });
        } catch (_) {
          if (await folder.exists()) await folder.delete(recursive: true);
          rethrow;
        }
      },
    );
    final folder = Directory(saved.path);
    final resultPath = '${folder.path}_rendered.${lossless ? 'mkv' : 'mp4'}';
    try {
      final sequence = '${folder.path}/frame_%06d.png';
      final command =
          '-i "$inputPath" -itsoffset ${start.toStringAsFixed(6)} '
          '-framerate $fps -start_number 0 -i "$sequence" '
          '-filter_complex "[1:v]scale=$width:$height,format=rgba[ov];'
          '[0:v][ov]overlay=0:0:eof_action=pass:'
          'repeatlast=0:format=auto,format=${lossless ? 'bgra' : 'yuv420p'}[v]" '
          '-map "[v]" -map 0:a? ${lossless ? '-c:v ffv1 -level 3' : '-c:v libx264 -preset veryfast -crf 21'} '
          '-pix_fmt ${lossless ? 'bgra' : 'yuv420p'} -c:a copy -t ${seconds.toStringAsFixed(6)} '
          '${lossless ? '' : '-movflags +faststart'} -y "$resultPath"';
      if (cancelled?.call() == true) throw TiniEditCancelled();
      final session = await FFmpegKit.execute(command);
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        throw StateError(
          'Vibe overlay export failed: '
          '${(await session.getAllLogsAsString()) ?? 'Unknown FFmpeg error'}',
        );
      }
      return resultPath;
    } catch (_) {
      final output = File(resultPath);
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      if (await folder.exists()) await folder.delete(recursive: true);
    }
  }
}
