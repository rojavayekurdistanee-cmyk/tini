import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'crop_retouch_model.dart';
import 'tini_edit_cache.dart';

/// The direct source needs normalization by the existing structural pipeline
/// before the hardware decoder/MP4 muxer can safely consume it.
class TiniRetouchBaselineRequired implements Exception {
  final String reason;
  TiniRetouchBaselineRequired(this.reason);
  @override
  String toString() => reason;
}

/// A private, reusable hardware-rendered checkpoint, independent of publishing.
/// The node can wrap an unevaluated graph, so a hit skips its entire ancestry.
class TiniRetouchExport {
  static const _channel = MethodChannel('titi_star/retouch_export');
  static int _serial = 0;

  // Convert only unsupported source audio. The video stream is packet-copied;
  // none of the already-rendered Tini picture effects are re-encoded here.
  // Prefer MP4 for MediaExtractor; Matroska is a compatibility alternative for
  // source video codecs that cannot be packet-copied into an MP4 container.
  static Future<String> _normalizeSourceAudio(
    String input,
    String directory,
    bool Function() stopped,
  ) async {
    for (final extension in const ['mp4', 'mkv']) {
      if (stopped()) throw TiniEditCancelled();
      final output = '$directory/normalized_source_audio.$extension';
      try {
        final session = await FFmpegKit.executeWithArguments([
          '-nostdin', '-hide_banner', '-loglevel', 'error',
          '-i', input,
          '-map', '0:v:0', '-map', '0:a:0',
          '-c:v', 'copy',
          '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2',
          '-af', 'aresample=async=1:first_pts=0',
          if (extension == 'mp4') ...['-movflags', '+faststart'],
          '-y', output,
        ]);
        if (stopped()) throw TiniEditCancelled();
        if (ReturnCode.isSuccess(await session.getReturnCode()) &&
            await File(output).exists() &&
            await File(output).length() > 0) {
          return output;
        }
      } on TiniEditCancelled {
        rethrow;
      } catch (_) {
        // Only this temporary audio-normalization attempt failed. Keep the
        // original complete-effect render/fallback available to the caller.
      }
      try {
        await File(output).delete();
      } on FileSystemException {
        // Failed or absent intermediate output.
      }
    }
    throw TiniRetouchBaselineRequired(
      'Could not normalize source audio to AAC without re-encoding video',
    );
  }

  static TiniEditNode node({
    required TiniEditNode input,
    required int outputWidth,
    required int outputHeight,
    required int durationMs,
    List<CropRetouchSegment> regions = const [],
    int sourceStartMs = 0,
    bool muted = false,
  }) {
    if (outputWidth < 2 ||
        outputHeight < 2 ||
        outputWidth.isOdd ||
        outputHeight.isOdd ||
        durationMs <= 0 ||
        sourceStartMs < 0) {
      throw ArgumentError(
        'Invalid hardware retouch output geometry or duration',
      );
    }
    final effective = <Map<String, Object>>[];
    for (final region in regions) {
      final smooth = region.settings.smooth;
      final teeth = region.settings.teeth;
      if (!smooth.isFinite ||
          !teeth.isFinite ||
          region.startMs < 0 ||
          region.endMs <= region.startMs ||
          region.endMs > durationMs + 1) {
        throw ArgumentError('Invalid hardware retouch segment');
      }
      if (!region.settings.enabled) continue;
      final start = region.startMs;
      final end = region.endMs.clamp(0, durationMs);
      final s = smooth.clamp(0.0, 1.0), t = teeth.clamp(0.0, 1.0);
      if (effective.isNotEmpty &&
          effective.last['endMs'] == start &&
          effective.last['smooth'] == s &&
          effective.last['teeth'] == t) {
        effective.last['endMs'] = end;
      } else {
        effective.add({
          'startMs': start,
          'endMs': end,
          'smooth': s,
          'teeth': t,
        });
      }
    }
    if (effective.isEmpty) throw ArgumentError('No enabled retouch segments');
    // Freeze the snapshot before any native asynchronous work starts.
    final snapshot = effective
        .map((r) => Map<String, Object>.unmodifiable(r))
        .toList(growable: false);
    return TiniEditNode(
      stage: 'gpu.retouch.export.v1',
      retainGroup: 'editor.gpu.checkpoint',
      parameters: {
        'regions': snapshot,
        'size': [outputWidth, outputHeight],
        'durationMs': durationMs,
        'sourceStartMs': sourceStartMs,
        'muted': muted,
        'quality': 'native-avc-high-v1',
      },
      inputs: [input],
      render: (inputs, stopped) async {
        if (stopped()) throw TiniEditCancelled();
        final temp = await getTemporaryDirectory();
        await temp.create(recursive: true);
        final folder = await temp.createTemp('tini_gpu_export_');
        final output = '${folder.path}/retouched.mp4';
        final id = '${DateTime.now().microsecondsSinceEpoch}_${_serial++}';
        var activeId = id;
        String? normalizedInput;
        var done = false, cancelSent = false, succeeded = false;
        Future<void> cancel() async {
          if (done || cancelSent) return;
          cancelSent = true;
          try {
            await _channel.invokeMethod<void>('cancel', {'id': activeId});
          } on PlatformException {
            // The render call remains responsible for completion/cleanup.
          } on MissingPluginException {
            // Render reports the missing native implementation below.
          }
        }

        Future<Map<String, dynamic>?> renderNative(String source) =>
            _channel.invokeMapMethod<String, dynamic>('render', {
              'id': activeId,
              'input': source,
              'output': output,
              'width': outputWidth,
              'height': outputHeight,
              'durationMs': durationMs,
              'sourceStartMs': sourceStartMs,
              'muted': muted,
              'smooth': 0.0,
              'teeth': 0.0,
              'regions': snapshot,
            });

        final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (stopped()) unawaited(cancel());
        });
        try {
          Map<String, dynamic>? result;
          try {
            result = await renderNative(inputs.single.path);
          } on PlatformException catch (error) {
            // Android's GPU retouch path cannot packet-copy PCM, Opus, etc.
            // Retry once with AAC audio and the SAME compressed video packets.
            // Unrelated baseline failures keep their original fallback path.
            if (error.code != 'BASELINE_REQUIRED' ||
                error.message !=
                    'Source audio requires normalization before MP4 packet copying') {
              rethrow;
            }
            if (stopped()) throw TiniEditCancelled();
            final preparedInput = await _normalizeSourceAudio(
              inputs.single.path, folder.path, stopped,
            );
            normalizedInput = preparedInput;
            if (stopped()) throw TiniEditCancelled();
            activeId = '${id}_aac';
            result = await renderNative(preparedInput);
          }
          // A successful immutable result may still be cached if the UI request
          // changed just after completion; cache.run rejects the obsolete caller.
          if (result == null ||
              !await File(output).exists() ||
              await File(output).length() == 0 ||
              (result['frames'] as num? ?? 0) <= 0 ||
              (result['width'] as num?)?.toInt() != outputWidth ||
              (result['height'] as num?)?.toInt() != outputHeight) {
            throw StateError('لم ينتج التصدير العتادي فيديو صالحًا');
          }
          succeeded = true;
          return TiniEditArtifact(
            output,
            temporary: true,
            metadata: {
              'frames': result['frames'],
              'faceFrames': result['faceFrames'] ?? 0,
              'width': outputWidth,
              'height': outputHeight,
              'durationMs': durationMs,
              'elapsedMs': result['elapsedMs'],
              'encoder': result['encoder'],
              'bitrate': result['bitrate'],
            },
          );
        } on MissingPluginException {
          throw UnsupportedError(
            'مسار التصدير العتادي غير مثبت. أعد بناء التطبيق كاملًا بعد إضافة ملفات أندرويد؛ Hot Reload لا يكفي.',
          );
        } on PlatformException catch (error) {
          if (stopped() || error.code.toLowerCase() == 'cancelled')
            throw TiniEditCancelled();
          if (error.code == 'BASELINE_REQUIRED') {
            throw TiniRetouchBaselineRequired(error.message ?? error.code);
          }
          throw StateError(
            'تعذر التصدير العتادي: ${error.message ?? error.code}',
          );
        } finally {
          done = true;
          timer.cancel();
          // Always release the intermediate. Never release the completed
          // video: the immutable cache takes ownership of it on success.
          if (normalizedInput != null) {
            try {
              await File(normalizedInput).delete();
            } on FileSystemException {
              /* Intermediate may already have been cleaned. */
            }
          }
          // On success the cache takes ownership of this file after return.
          // On failure/cancellation native code removes its partial output.
          // The directory is removed by cache ownership cleanup when empty.
          if (!succeeded) {
            try {
              await folder.delete(recursive: true);
            } on FileSystemException {
              /* Native cleanup. */
            }
          }
        }
      },
    );
  }

  static Future<String> render({
    required String input,
    required int outputWidth,
    required int outputHeight,
    required int durationMs,
    List<CropRetouchSegment> regions = const [],
    int sourceStartMs = 0,
    bool muted = false,
    bool Function()? cancelled,
  }) async {
    final cache = TiniEditCache.shared;
    return (await cache.run(
      node(
        input: await cache.source(input),
        outputWidth: outputWidth,
        outputHeight: outputHeight,
        durationMs: durationMs,
        regions: regions,
        sourceStartMs: sourceStartMs,
        muted: muted,
      ),
      cancelled: cancelled,
    )).path;
  }
}
