import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'crop_effects_model.dart';
import 'crop_body_fx_names.dart';
import 'crop_model.dart';
import 'tini_edit_cache.dart';
import 'tini_edit_directory_cache.dart';

/// Mask-driven body effects. No geometry is guessed from the centre of a video.
/// The existing Android person-segmentation engine supplies per-frame masks;
/// the contour and anchor points are derived from each real mask. The same
/// transparent PNG frames drive both live editor preview and FFmpeg export.
class TiniBodyFxEngine {
  static const category = TiniBodyFxNames.category;
  static const supported = TiniBodyFxNames.supported;
  static const frameRate = 12;
  static const MethodChannel _native = MethodChannel('titi_star/body_tracking');

  static final Map<String, _BodyPreviewEntry> _cachedPreviews = {};

  // A live, one-frame-at-a-time preview. Export still uses prepare/compose.
  static final ValueNotifier<int> liveRevision = ValueNotifier<int>(0);
  static _LiveBodyFrame? _liveFrame;
  static int _liveRequest = 0;
  static bool _liveBusy = false;

  static void clearLive() {
    _liveRequest++;
    final previous = _liveFrame;
    _liveFrame = null;
    previous?.dispose();
    liveRevision.value++;
  }

  static bool liveMatches(
    String? clipId,
    List<TiniAppliedEffect> effects,
    double outputSeconds,
  ) {
    final live = _liveFrame;
    return clipId != null &&
        live != null &&
        live.clipId == clipId &&
        sameTiniEffects(live.effects, effects) &&
        (outputSeconds - live.outputSeconds).abs() < .7;
  }

  static void paintLive(
    ui.Canvas canvas,
    ui.Size size,
    String? clipId,
    List<TiniAppliedEffect> effects,
    double outputSeconds,
  ) {
    if (!liveMatches(clipId, effects, outputSeconds)) return;
    final live = _liveFrame!;
    canvas.save();
    canvas.scale(size.width / live.width, size.height / live.height);
    for (final effect in effects) {
      if (!effect.active(outputSeconds) ||
          effect.descriptor?.category != category)
        continue;
      final name = effect.descriptor?.name;
      if (name == null || !supported.contains(name)) continue;
      _BodyPainter.paint(
        canvas,
        live.shape,
        name,
        outputSeconds - effect.startSeconds,
        live.width,
        live.height,
        pose: live.pose,
        person: live.person,
        thermal: live.thermal,
        alphaMask: live.alphaMask,
      );
    }
    canvas.restore();
  }

  /// Nonblocking preview: sample the frame currently playing, never the clip.
  /// If the device takes longer to infer one frame, the player keeps playing.
  static Future<void> captureLive({
    required CropClip clip,
    required String source,
    required int sourceTimeMs,
    required double outputSeconds,
  }) async {
    if (_liveBusy || !hasBodyEffects(clip.videoEffects)) return;
    final request = _liveRequest;
    final effects = List<TiniAppliedEffect>.of(clip.videoEffects);
    final needsRgb = effects.any(
      (e) =>
          e.active(outputSeconds) &&
          const <String>{
            'Ghost',
            'Squad Yours...',
            'Sliding Door...',
            'Thermal Heat',
            'Scattering Fr...',
          }.contains(e.descriptor?.name),
    );
    _liveBusy = true;
    try {
      final uri = Uri.tryParse(source);
      final path = uri?.scheme == 'file' ? uri!.toFilePath() : source;
      final answer = await _native.invokeMapMethod<String, dynamic>(
        'trackFrame',
        <String, dynamic>{
          'path': path,
          'timeMs': sourceTimeMs,
          'includeRgb': needsRgb,
        },
      );
      if (answer == null) throw StateError('Tracking returned no frame');
      final width = (answer['width'] as num).toInt();
      final height = (answer['height'] as num).toInt();
      final alpha = answer['mask'] as Uint8List;
      if (alpha.length != width * height) {
        throw StateError('Tracking mask size mismatch');
      }
      final rgba = Uint8List(alpha.length * 4);
      for (var k = 0; k < alpha.length; k++) {
        final n = 4 * k;
        rgba[n] = alpha[k];
        rgba[n + 1] = alpha[k];
        rgba[n + 2] = alpha[k];
        rgba[n + 3] = 255;
      }
      final shape = _SubjectShape.extract(rgba, width, height);
      if (shape == null || request != _liveRequest) return;
      final pose = _BodyPose.fromJson(answer['pose'], width, height);
      ui.Image? person;
      ui.Image? thermal;
      ui.Image? alphaMask;
      try {
        if (needsRgb) {
          final rgb = answer['rgb'] as Uint8List?;
          if (rgb == null) throw StateError('Tracking RGB frame is missing');
          final codec = await ui.instantiateImageCodec(rgb);
          ui.Image sourceImage;
          try {
            sourceImage = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
          try {
            if (sourceImage.width != width || sourceImage.height != height) {
              throw StateError('Tracking frame dimensions mismatch');
            }
            final raw = await sourceImage.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (raw == null)
              throw StateError('Cannot decode tracked video frame');
            final pixels = raw.buffer.asUint8List();
            final isolated = Uint8List(rgba.length);
            final hotPixels = Uint8List(rgba.length);
            for (var j = 0; j < rgba.length; j += 4) {
              final a = rgba[j];
              if (a < 80) continue;
              isolated[j] = pixels[j];
              isolated[j + 1] = pixels[j + 1];
              isolated[j + 2] = pixels[j + 2];
              isolated[j + 3] = a;
              final gray =
                  (pixels[j] * .30 +
                      pixels[j + 1] * .59 +
                      pixels[j + 2] * .11) /
                  255;
              final warm = gray > .70;
              final cool = gray < .35;
              hotPixels[j] = warm ? 255 : (cool ? 40 : 115);
              hotPixels[j + 1] = warm ? 178 : (cool ? 80 : 236);
              hotPixels[j + 2] = warm ? 20 : (cool ? 245 : 56);
              hotPixels[j + 3] = (a * .92).round();
            }
            person = await _decodeRgba(isolated, width, height);
            if (effects.any(
              (e) =>
                  e.active(outputSeconds) &&
                  e.descriptor?.name == 'Thermal Heat',
            )) {
              thermal = await _decodeRgba(hotPixels, width, height);
            }
          } finally {
            sourceImage.dispose();
          }
        }
        if (effects.any(
          (e) =>
              e.active(outputSeconds) && e.descriptor?.name == 'Background ...',
        )) {
          final bg = Uint8List(rgba.length);
          for (var j = 0; j < bg.length; j += 4) {
            bg[j] = 255;
            bg[j + 1] = 255;
            bg[j + 2] = 255;
            bg[j + 3] = rgba[j];
          }
          alphaMask = await _decodeRgba(bg, width, height);
        }
        if (request != _liveRequest) return;
        final frame = _LiveBodyFrame(
          clip.id,
          effects,
          outputSeconds,
          width,
          height,
          shape,
          pose,
          person,
          thermal,
          alphaMask,
        );
        person = null;
        thermal = null;
        alphaMask = null; // ownership transferred
        final previous = _liveFrame;
        _liveFrame = frame;
        liveRevision.value++;
        // Keep previous frame alive through the current Flutter paint cycle.
        if (previous != null) {
          Future<void>.delayed(
            const Duration(milliseconds: 120),
            previous.dispose,
          );
        }
      } finally {
        person?.dispose();
        thermal?.dispose();
        alphaMask?.dispose();
      }
    } finally {
      _liveBusy = false;
    }
  }

  // Share the native segmentation result while slider edits regenerate the
  // overlay. The masks are reference-counted so export and preview cannot
  // delete each other's frames; ordinary cutout masks are never owned here.
  static final Map<String, _CachedGeneratedMask> _generatedMasks = {};
  static Future<void> _maskGenerationQueue = Future<void>.value();

  static Future<void> _releaseGeneratedMask(String key) async {
    final cached = _generatedMasks[key];
    if (cached == null) return;
    cached.references--;
    if (cached.references > 0) return;
    _generatedMasks.remove(key);
    try {
      await Directory(cached.source.directory).delete(recursive: true);
    } catch (_) {}
  }

  static TiniBodyFxFrames? previewFor(
    String? clipId,
    List<TiniAppliedEffect> effects,
  ) {
    if (clipId == null) return null;
    final entry = _cachedPreviews[clipId];
    if (entry == null || !sameTiniEffects(entry.effects, effects)) return null;
    return entry.frames;
  }

  static Future<void> replacePreview(
    String clipId,
    List<TiniAppliedEffect> effects,
    TiniBodyFxFrames? frames,
  ) async {
    final previous = _cachedPreviews.remove(clipId);
    if (frames != null) {
      _cachedPreviews[clipId] = _BodyPreviewEntry(List.of(effects), frames);
    }
    await previous?.frames.dispose();
  }

  static bool hasBodyEffects(List<TiniAppliedEffect> effects) => effects.any(
    (effect) =>
        effect.descriptor?.category == category &&
        supported.contains(effect.descriptor?.name),
  );

  static Future<_BodyMaskSource> _maskDirectory(
    CropClip clip,
    String source,
    Duration begin,
    List<String> owned,
  ) async {
    final key =
        '${await TiniEditCache.shared.fingerprint(source)}|${begin.inMicroseconds}|${clip.duration.inMicroseconds}';
    // Never route editor body tracking through existing background cutout:
    // that API must remain independent and cannot return skeletal landmarks.
    final previous = _maskGenerationQueue;
    final gate = Completer<void>();
    _maskGenerationQueue = gate.future;
    await previous;
    try {
      final cached = _generatedMasks[key];
      if (cached != null && await Directory(cached.source.directory).exists()) {
        cached.references++;
        return cached.source;
      }
      if (cached != null) _generatedMasks.remove(key);
      final saved = await TiniEditDirectoryCache.obtain(
        stage: 'body.analysis.v1',
        parameters: {
          'start': begin.inMicroseconds,
          'duration': clip.duration.inMicroseconds,
          'fps': frameRate,
        },
        sources: [source],
        build: (inputs, stop) async {
          final temp = await getTemporaryDirectory();
          final directory = (await temp.createTemp('tini_body_tracking_')).path;
          try {
            final response = await _native
                .invokeMapMethod<String, dynamic>('createTracking', {
                  'path': inputs[0].path,
                  'outputDir': directory,
                  'startMs': begin.inMilliseconds,
                  'durationMs': clip.duration.inMilliseconds,
                  'fps': frameRate,
                });
            final count = (response?['count'] as num?)?.toInt() ?? 0;
            if (count < 1 || !await File('$directory/poses.json').exists()) {
              throw StateError('تعذر توليد بيانات تتبع الجسم');
            }
            return TiniEditDirectoryResult(directory, {
              'count': count,
              'fps':
                  (response?['fps'] as num?)?.toDouble() ??
                  frameRate.toDouble(),
            });
          } catch (_) {
            try {
              await Directory(directory).delete(recursive: true);
            } catch (_) {}
            rethrow;
          }
        },
      );
      final result = _BodyMaskSource(
        saved.path,
        (saved.metadata['fps'] as num).toDouble(),
        saved.metadata['count'] as int,
        begin,
        cacheKey: key,
      );
      _generatedMasks[key] = _CachedGeneratedMask(result);
      return result;
    } finally {
      gate.complete();
    }
  }

  /// Creates the SAME overlay frames for preview and for final output. These
  /// images are not a replacement for the source video or its audio.
  static Future<TiniBodyFxFrames> prepare({
    required CropClip clip,
    required String source,
    required Duration sourceStart,
    bool Function()? cancelled,
    bool useCache = true,
  }) async {
    if (!hasBodyEffects(clip.videoEffects)) {
      throw ArgumentError('Body effects were not selected');
    }
    if (useCache) {
      final saved = await TiniEditDirectoryCache.obtain(
        stage: 'body.overlay.frames.v1',
        parameters: {
          'start': sourceStart.inMicroseconds,
          'duration': clip.duration.inMicroseconds,
          'speed': [
            clip.speed.isCurve,
            clip.speed.normal,
            [
              for (final p in clip.speed.points) [p.at, p.speed],
            ],
          ],
          'effects': [
            for (final e in clip.videoEffects)
              [e.id, e.startSeconds, e.endSeconds],
          ],
        },
        sources: [source],
        cancelled: cancelled,
        build: (inputs, stop) async {
          final frames = await prepare(
            clip: clip,
            source: inputs[0].path,
            sourceStart: sourceStart,
            cancelled: stop,
            useCache: false,
          );
          return TiniEditDirectoryResult(frames.directory, {
            'fps': frames.fps,
            'frames': frames.frames,
          }, release: frames.dispose);
        },
      );
      return TiniBodyFxFrames(
        directory: saved.path,
        fps: saved.metadata['fps'] as int,
        frames: saved.metadata['frames'] as int,
        maskDirectoriesToDelete: [],
      );
    }
    final own = <String>[];
    String? acquiredMaskKey;
    try {
      final masks = await _maskDirectory(clip, source, sourceStart, own);
      acquiredMaskKey = masks.cacheKey;
      final temp = await getTemporaryDirectory();
      final framesDir = Directory(
        '${temp.path}/tini_body_fx_${DateTime.now().microsecondsSinceEpoch}',
      );
      await framesDir.create(recursive: true);
      own.add(framesDir.path);
      final seconds = clip.playbackDuration.inMicroseconds / 1000000.0;
      final count = math.max(1, (seconds * frameRate).ceil());
      // Use the ACTUAL FPS and mask-start metadata from Android. Existing
      // cutout masks may use 12 fps, while edge-quality requests use 15 fps.
      final maskFps = masks.fps;
      final maskCount = masks.count;
      final rawPoseList =
          jsonDecode(await File('${masks.directory}/poses.json').readAsString())
              as List<dynamic>;
      if (rawPoseList.length != maskCount) {
        throw StateError('عدد إطارات تتبع الجسم لا يطابق الأقنعة');
      }
      final needsRgb = clip.videoEffects.any(
        (e) => const <String>{
          'Ghost',
          'Squad Yours...',
          'Sliding Door...',
          'Thermal Heat',
          'Scattering Fr...',
        }.contains(e.descriptor?.name),
      );
      String? sourcesDir;
      var sourceFrameCount = 0;
      if (needsRgb) {
        final initial = await _decodeImage(
          '${masks.directory}/mask_000000.png',
        );
        final ww = initial.width;
        final hh = initial.height;
        initial.dispose();
        final sourceFiles = Directory(
          '${temp.path}/tini_body_src_${DateTime.now().microsecondsSinceEpoch}',
        );
        await sourceFiles.create(recursive: true);
        sourcesDir = sourceFiles.path;
        own.add(sourceFiles.path);
        String safe(String value) => value.replaceAll('"', '\\"');
        final begin = sourceStart.inMicroseconds / 1000000.0;
        final length = clip.duration.inMicroseconds / 1000000.0;
        final ffmpeg = await FFmpegKit.execute(
          '-hide_banner -loglevel error '
          '-ss ${begin.toStringAsFixed(6)} -t ${length.toStringAsFixed(6)} '
          '-i "${safe(source)}" -vf "fps=$frameRate,scale=$ww:$hh:'
          'force_original_aspect_ratio=decrease,'
          'pad=$ww:$hh:(ow-iw)/2:(oh-ih)/2:black,format=rgba" '
          '-start_number 0 -y "${safe(sourcesDir)}/src_%06d.png"',
        );
        if (!ReturnCode.isSuccess(await ffmpeg.getReturnCode())) {
          throw StateError(
            'Could not extract body source frames: '
            '${await ffmpeg.getAllLogsAsString()}',
          );
        }
        sourceFrameCount = await sourceFiles
            .list()
            .where((entry) => entry.path.endsWith('.png'))
            .length;
        if (sourceFrameCount == 0)
          throw StateError('No source frames extracted');
      }

      var detectedFrames = 0;
      var lastIndex = -1;
      ui.Image? maskImage;
      Uint8List? maskBytes;
      var lastRgbIndex = -1;
      ui.Image? sourceFrame;
      Uint8List? sourceBytes;
      for (var i = 0; i < count; i++) {
        if (cancelled?.call() == true) throw TiniEditCancelled();
        final outputTime = i / frameRate;
        final mapped = clip.sourceAtProjectOffset(outputTime);
        final localSource =
            (mapped - clip.startTime).inMicroseconds / 1000000.0;
        final maskOffset =
            (sourceStart - masks.sourceStart).inMicroseconds / 1000000.0;
        final maskIndex = ((localSource + maskOffset) * maskFps).floor().clamp(
          0,
          maskCount - 1,
        );
        if (maskIndex != lastIndex) {
          maskImage?.dispose();
          maskImage = await _decodeImage(
            '${masks.directory}/mask_${maskIndex.toString().padLeft(6, '0')}.png',
          );
          final raw = await maskImage!.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (raw == null)
            throw StateError('Could not read segmentation mask pixels');
          maskBytes = raw.buffer.asUint8List();
          lastIndex = maskIndex;
        }
        final mask = maskImage!;
        final raw = maskBytes!;
        final w = mask.width;
        final h = mask.height;
        final shape = _SubjectShape.extract(raw, w, h);
        final pose = _BodyPose.fromJson(rawPoseList[maskIndex], w, h);
        if (shape != null) detectedFrames++;
        ui.Image? person;
        ui.Image? thermal;
        ui.Image? alphaMask;
        final activeNames = clip.videoEffects
            .where(
              (e) => e.active(outputTime) && e.descriptor?.category == category,
            )
            .map((e) => e.descriptor?.name)
            .toSet();
        final needsPerson = activeNames.intersection(const <String>{
          'Ghost',
          'Squad Yours...',
          'Sliding Door...',
          'Thermal Heat',
          'Scattering Fr...',
        }).isNotEmpty;
        if (needsPerson && sourcesDir != null) {
          final imageIndex = (localSource * frameRate).floor().clamp(
            0,
            sourceFrameCount - 1,
          );
          if (imageIndex != lastRgbIndex) {
            sourceFrame?.dispose();
            final framePath =
                '$sourcesDir/src_${imageIndex.toString().padLeft(6, '0')}.png';
            sourceFrame = await _decodeImage(framePath);
            final pixels = await sourceFrame!.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (pixels == null)
              throw StateError('Could not read original video pixels');
            sourceBytes = pixels.buffer.asUint8List();
            lastRgbIndex = imageIndex;
          }
          if (sourceFrame!.width != w || sourceFrame!.height != h) {
            throw StateError('Source and mask size mismatch');
          }
          final rgba = Uint8List(raw.length);
          final thermalRgba = Uint8List(raw.length);
          final pixels = sourceBytes!;
          for (var j = 0; j < raw.length; j += 4) {
            final alpha = raw[j];
            if (alpha < 80) continue;
            rgba[j] = pixels[j];
            rgba[j + 1] = pixels[j + 1];
            rgba[j + 2] = pixels[j + 2];
            rgba[j + 3] = alpha;
            final gray =
                (pixels[j] * .30 + pixels[j + 1] * .59 + pixels[j + 2] * .11) /
                255;
            final hot = gray > .70;
            final cold = gray < .35;
            thermalRgba[j] = hot ? 255 : (cold ? 40 : 115);
            thermalRgba[j + 1] = hot ? 178 : (cold ? 80 : 236);
            thermalRgba[j + 2] = hot ? 20 : (cold ? 245 : 56);
            thermalRgba[j + 3] = (alpha * .92).round();
          }
          person = await _decodeRgba(rgba, w, h);
          if (activeNames.contains('Thermal Heat')) {
            thermal = await _decodeRgba(thermalRgba, w, h);
          }
        }
        if (activeNames.contains('Background ...')) {
          final alpha = Uint8List(raw.length);
          for (var j = 0; j < raw.length; j += 4) {
            alpha[j] = 255;
            alpha[j + 1] = 255;
            alpha[j + 2] = 255;
            alpha[j + 3] = raw[j];
          }
          alphaMask = await _decodeRgba(alpha, w, h);
        }
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(
          recorder,
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        );
        if (shape != null) {
          for (final effect in clip.videoEffects) {
            if (!effect.active(outputTime)) continue;
            if (effect.descriptor?.category != category) continue;
            final name = effect.descriptor?.name;
            if (name == null || !supported.contains(name)) continue;
            _BodyPainter.paint(
              canvas,
              shape,
              name,
              outputTime - effect.startSeconds,
              w,
              h,
              person: person,
              thermal: thermal,
              alphaMask: alphaMask,
              pose: pose,
            );
          }
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(w, h);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        person?.dispose();
        thermal?.dispose();
        alphaMask?.dispose();
        if (bytes == null) throw StateError('Body overlay PNG encoding failed');
        await File(
          '${framesDir.path}/frame_${i.toString().padLeft(6, '0')}.png',
        ).writeAsBytes(bytes.buffer.asUint8List());
        if (i % 8 == 0) await Future<void>.delayed(Duration.zero);
      }
      maskImage?.dispose();
      sourceFrame?.dispose();
      // Do not silently export empty effects when segmentation cannot detect
      // a person in any processed frame.
      if (detectedFrames == 0) {
        throw StateError(
          'لم يتم العثور على شخص في الفيديو لتطبيق مؤثرات الجسم',
        );
      }
      // Don't delete the overlay files until its owner has disposed them.
      own.remove(framesDir.path);
      return TiniBodyFxFrames(
        directory: framesDir.path,
        fps: frameRate,
        frames: count,
        maskDirectoriesToDelete: own,
        generatedMaskCacheKey: acquiredMaskKey,
      );
    } catch (_) {
      for (final path in own) {
        try {
          await Directory(path).delete(recursive: true);
        } catch (_) {}
      }
      if (acquiredMaskKey != null) {
        await _releaseGeneratedMask(acquiredMaskKey);
      }
      rethrow;
    }
  }

  static Future<ui.Image> _decodeImage(String path) async {
    final data = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  static Future<ui.Image> _decodeRgba(Uint8List bytes, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );
    return completer.future;
  }

  /// FFmpeg receives the generated overlay frames as an additional input.
  /// The original audio is stream-copied and all unrelated effects are intact.
  static Future<String> compose({
    required String renderedPath,
    required TiniBodyFxFrames frames,
    required int width,
    required int height,
    bool lossless = false,
  }) async {
    final temp = await getTemporaryDirectory();
    final output =
        '${temp.path}/tini_body_composite_${DateTime.now().microsecondsSinceEpoch}.${lossless ? 'mkv' : 'mp4'}';
    String q(String value) => value.replaceAll('"', '\\"');
    final command =
        '-hide_banner -loglevel error -nostats '
        '-i "${q(renderedPath)}" '
        '-framerate ${frames.fps} -start_number 0 '
        '-i "${q(frames.directory)}/frame_%06d.png" '
        '-filter_complex "[0:v]format=rgba[bv];'
        '[1:v]format=rgba,scale=$width:$height:'
        'force_original_aspect_ratio=decrease,'
        'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black@0[ov];'
        '[bv][ov]overlay=0:0:shortest=0:eof_action=repeat:format=auto,'
        'format=${lossless ? 'bgra' : 'yuv420p'}[out]" '
        '-map "[out]" -map 0:a? ${lossless ? '-c:v ffv1 -level 3' : '-c:v libx264 -crf 20 -preset veryfast'} '
        '-c:a copy -pix_fmt ${lossless ? 'bgra' : 'yuv420p'} ${lossless ? '' : '-movflags +faststart'} '
        '-y "${q(output)}"';
    final session = await FFmpegKit.execute(command);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      final logs = await session.getAllLogsAsString() ?? '';
      throw StateError(
        'Body effect rendering failed: '
        '${logs.length > 1200 ? logs.substring(logs.length - 1200) : logs}',
      );
    }
    if (!await File(output).exists()) {
      throw StateError('Body effect renderer did not generate an output file');
    }
    return output;
  }
}

class _LiveBodyFrame {
  final String clipId;
  final List<TiniAppliedEffect> effects;
  final double outputSeconds;
  final int width, height;
  final _SubjectShape shape;
  final _BodyPose pose;
  final ui.Image? person, thermal, alphaMask;
  _LiveBodyFrame(
    this.clipId,
    this.effects,
    this.outputSeconds,
    this.width,
    this.height,
    this.shape,
    this.pose,
    this.person,
    this.thermal,
    this.alphaMask,
  );
  void dispose() {
    person?.dispose();
    thermal?.dispose();
    alphaMask?.dispose();
  }
}

class _BodyPreviewEntry {
  final List<TiniAppliedEffect> effects;
  final TiniBodyFxFrames frames;
  _BodyPreviewEntry(this.effects, this.frames);
}

class _BodyMaskSource {
  final String directory;
  final double fps;
  final int count;
  final Duration sourceStart;
  final String? cacheKey;
  const _BodyMaskSource(
    this.directory,
    this.fps,
    this.count,
    this.sourceStart, {
    this.cacheKey,
  });
}

class _CachedGeneratedMask {
  final _BodyMaskSource source;
  int references;
  _CachedGeneratedMask(this.source) : references = 1;
}

class TiniBodyFxFrames {
  final String directory;
  final int fps;
  final int frames;
  final List<String> maskDirectoriesToDelete;
  final String? generatedMaskCacheKey;
  const TiniBodyFxFrames({
    required this.directory,
    required this.fps,
    required this.frames,
    required this.maskDirectoriesToDelete,
    this.generatedMaskCacheKey,
  });
  String framePath(int index) =>
      '$directory/frame_${index.toString().padLeft(6, '0')}.png';

  Future<void> dispose() async {
    for (final path in [directory, ...maskDirectoriesToDelete]) {
      try {
        await Directory(path).delete(recursive: true);
      } catch (_) {}
    }
    final key = generatedMaskCacheKey;
    if (key != null) await TiniBodyFxEngine._releaseGeneratedMask(key);
  }
}

class _SubjectShape {
  final double left, top, right, bottom;
  final List<ui.Offset> edge;
  const _SubjectShape(this.left, this.top, this.right, this.bottom, this.edge);
  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
  double get width => right - left;
  double get height => bottom - top;

  static _SubjectShape? extract(Uint8List raw, int w, int h) {
    var minX = w;
    var minY = h;
    var maxX = -1;
    var maxY = -1;
    int luminance(int x, int y) => raw[(y * w + x) * 4];
    final edge = <ui.Offset>[];
    for (var y = 2; y < h - 2; y += 2) {
      for (var x = 2; x < w - 2; x += 2) {
        if (luminance(x, y) < 145) continue;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
        if (luminance(x - 2, y) < 145 ||
            luminance(x + 2, y) < 145 ||
            luminance(x, y - 2) < 145 ||
            luminance(x, y + 2) < 145) {
          edge.add(ui.Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    if (maxX < minX || maxY < minY || maxX - minX < 8 || maxY - minY < 18)
      return null;
    return _SubjectShape(
      minX.toDouble(),
      minY.toDouble(),
      maxX.toDouble(),
      maxY.toDouble(),
      edge,
    );
  }
}

// Frame-by-frame landmarks normalized in Kotlin to the original frame.
// Missing/low-confidence joints are never fabricated; mask geometry remains
// the fallback for effects without a reliable pose.
class _BodyPose {
  final Map<String, ui.Offset> joints;
  const _BodyPose(this.joints);

  static _BodyPose fromJson(dynamic value, int w, int h) {
    final result = <String, ui.Offset>{};
    if (value is Map) {
      for (final entry in value.entries) {
        final coordinates = entry.value;
        if (entry.key is! String ||
            coordinates is! List ||
            coordinates.length != 2 ||
            coordinates[0] is! num ||
            coordinates[1] is! num)
          continue;
        final x = (coordinates[0] as num).toDouble();
        final y = (coordinates[1] as num).toDouble();
        if (!x.isFinite || !y.isFinite) continue;
        result[entry.key as String] = ui.Offset(x * w, y * h);
      }
    }
    return _BodyPose(result);
  }

  ui.Offset? get shoulderCenter {
    final left = joints['leftShoulder'];
    final right = joints['rightShoulder'];
    if (left == null || right == null) return null;
    return ui.Offset((left.dx + right.dx) / 2, (left.dy + right.dy) / 2);
  }

  double? get shoulderWidth {
    final left = joints['leftShoulder'];
    final right = joints['rightShoulder'];
    if (left == null || right == null) return null;
    return (left - right).distance;
  }
}

class _BodyPainter {
  static void paint(
    ui.Canvas canvas,
    _SubjectShape s,
    String name,
    double t,
    int w,
    int h, {
    ui.Image? person,
    ui.Image? thermal,
    ui.Image? alphaMask,
    _BodyPose? pose,
  }) {
    final x = s.cx;
    final y = s.top + s.height * .58;
    final rw = s.width * .7;
    final ry = s.height * .065;
    switch (name) {
      case 'Ghost':
        if (person != null) {
          _copyPerson(
            canvas,
            person,
            s.width * .19 * math.sin(t * 2),
            -s.height * .025,
            alpha: .44,
            tint: const ui.Color(0xFF8CF4FF),
          );
          _copyPerson(
            canvas,
            person,
            -s.width * .16,
            -s.height * .03,
            alpha: .25,
            tint: const ui.Color(0xFF9A85FF),
          );
        }
        return;
      case 'Squad Yours...':
        if (person != null) {
          _copyPerson(canvas, person, -s.width * 1.12, 0, alpha: .93);
          _copyPerson(canvas, person, s.width * 1.12, 0, alpha: .93);
          _copyPerson(canvas, person, -s.width * 1.80, 0, alpha: .66);
          _copyPerson(canvas, person, s.width * 1.80, 0, alpha: .66);
        }
        return;
      case 'Sliding Door...':
        if (person != null) {
          final region = ui.Rect.fromLTWH(s.left, s.top, s.width, s.height);
          final left = ui.Rect.fromLTWH(s.left, s.top, s.width / 2, s.height);
          final right = ui.Rect.fromLTWH(s.cx, s.top, s.width / 2, s.height);
          canvas.save();
          canvas.clipRect(left.shift(ui.Offset(-s.width * .26, 0)));
          _copyPerson(canvas, person, -s.width * .26, 0, alpha: .94);
          canvas.restore();
          canvas.save();
          canvas.clipRect(right.shift(ui.Offset(s.width * .26, 0)));
          _copyPerson(canvas, person, s.width * .26, 0, alpha: .94);
          canvas.restore();
          // An animated bright seam separates the two sliding halves.
          _slash(
            canvas,
            region.center.dx + math.sin(t * 2) * s.width * .07,
            region.top,
            region.center.dx + math.sin(t * 2) * s.width * .07,
            region.bottom,
            const ui.Color(0xD3F9EEFF),
            2.2,
          );
        }
        return;
      case 'Thermal Heat':
        if (thermal != null) {
          canvas.drawImage(
            thermal,
            ui.Offset.zero,
            ui.Paint()..filterQuality = ui.FilterQuality.low,
          );
        }
        return;
      case 'Scattering Fr...':
        if (person != null) {
          final maxShift = s.width * .42;
          for (var j = 0; j < 9; j++) {
            final row = j % 3;
            final col = j ~/ 3;
            final rect = ui.Rect.fromLTWH(
              s.left + col * s.width / 3,
              s.top + row * s.height / 3,
              s.width / 3,
              s.height / 3,
            );
            canvas.save();
            final dx = (col - 1) * maxShift * (.45 + .25 * math.sin(t + j));
            final dy = (row - 1) * s.height * .04;
            canvas.clipRect(rect.shift(ui.Offset(dx, dy)));
            _copyPerson(canvas, person, dx, dy, alpha: .92);
            canvas.restore();
          }
        }
        return;
      case 'Background ...':
        if (alphaMask != null) {
          final bounds = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
          canvas.saveLayer(bounds, ui.Paint());
          final bg = ui.Paint()
            ..shader = ui.Gradient.linear(
              ui.Offset(0, t * 14),
              ui.Offset(w.toDouble(), h.toDouble()),
              [
                const ui.Color(0xD9401D8F),
                const ui.Color(0xDF1696C4),
                const ui.Color(0xDFD64A95),
              ],
            );
          canvas.drawRect(bounds, bg);
          for (var n = 0; n < 7; n++) {
            _wave(
              canvas,
              0,
              w.toDouble(),
              h * (n / 7),
              h * .028,
              t + n,
              const ui.Color(0x77F3C0FF),
              5,
            );
          }
          canvas.drawImage(
            alphaMask,
            ui.Offset.zero,
            ui.Paint()..blendMode = ui.BlendMode.dstOut,
          );
          canvas.restore();
        }
        return;
      case 'Halo 1':
        _ring(canvas, x, y, rw, ry, const ui.Color(0xFFFFD978), t);
        _ring(
          canvas,
          x,
          y - s.height * .10,
          rw * .87,
          ry * .6,
          const ui.Color(0xA6FF994F),
          -t * .7,
        );
        return;
      case 'Hellfire':
        _ring(canvas, x, y, rw, ry, const ui.Color(0xFFFF7C22), t * 2.5);
        for (var n = 0; n < 12; n++) {
          final a = n * math.pi * 2 / 12 + t * 2;
          final px = x + math.cos(a) * rw;
          final py = y + math.sin(a) * ry;
          final len = s.height * (.06 + (n % 3) * .012);
          final p = ui.Path()
            ..moveTo(px, py)
            ..quadraticBezierTo(
              px - math.sin(a) * 6,
              py - len * .6,
              px + math.sin(t * 4 + n) * 9,
              py - len,
            );
          canvas.drawPath(
            p,
            ui.Paint()
              ..color = const ui.Color(0xFFFFD659)
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = 3,
          );
        }
        return;
      case 'Butterfly Win...':
        _wings(canvas, s, const ui.Color(0xFFB5FFE4), false, t, pose: pose);
        return;
      case 'أجنحة':
        _wings(canvas, s, const ui.Color(0xFF68D7FF), true, t, pose: pose);
        return;
      case 'Aura':
        _ring(
          canvas,
          x,
          y,
          rw * .93,
          ry * 1.2,
          const ui.Color(0xFFFF62E6),
          t * 1.2,
        );
        _outline(canvas, s, const ui.Color(0x887C35FF), 5.0);
        return;
      case 'Mechanical 2':
        _outline(canvas, s, const ui.Color(0x557DDFFF), 1.9);
        for (var j = 0; j < 3; j++) {
          _ring(
            canvas,
            x,
            y + s.height * (.06 * (j - 1)),
            rw * (1.04 - j * .12),
            ry * (1.03 + j * .15),
            j.isEven ? const ui.Color(0xFFD9F8FF) : const ui.Color(0xFF79DFFF),
            t * (j.isEven ? 2.2 : -1.4),
          );
        }
        return;
      case 'Phantom':
        _outline(canvas, s, const ui.Color(0x885DE6FF), 8);
        _outline(canvas, s, const ui.Color(0xFFCF79FF), 2);
        _slash(
          canvas,
          s.cx - s.width * .9,
          s.top + s.height * .5,
          s.cx + s.width * .82,
          s.top + s.height * .43,
          const ui.Color(0x99F2B5FF),
          3.0,
        );
        return;
      case 'Enveloping L...':
        _helix(
          canvas,
          s,
          t,
          const ui.Color(0xFFFFA4F2),
          const ui.Color(0xFF8D78FF),
        );
        return;
      case 'Color Fringe':
        _outline(canvas, s, const ui.Color(0xFFFF3B83), 8);
        _outline(canvas, s, const ui.Color(0xFF5FCEFF), 3);
        return;
      case 'Tunnel Lights':
        for (var j = 0; j < 6; j++) {
          final radius = .8 + (j + (t * .65) % 1.0) * .13;
          _ring(
            canvas,
            x,
            y - s.height * .12,
            s.width * radius,
            s.height * radius * .26,
            j.isEven ? const ui.Color(0xFF36FFC4) : const ui.Color(0x664AFFDE),
            t * (j.isEven ? 2 : -2),
          );
        }
        return;
      case 'Oscars':
        final beam = ui.Path()
          ..moveTo(s.cx - s.width * .16, s.top - s.height * .5)
          ..lineTo(s.left - s.width * .2, s.bottom)
          ..lineTo(s.right + s.width * .2, s.bottom)
          ..lineTo(s.cx + s.width * .16, s.top - s.height * .5)
          ..close();
        canvas.drawPath(beam, ui.Paint()..color = const ui.Color(0x36FFDE88));
        _outline(canvas, s, const ui.Color(0x99FFDF7E), 3);
        return;
      case 'Water Lighti...':
        _outline(canvas, s, const ui.Color(0x883AD7FF), 4);
        for (var j = 0; j < 4; j++) {
          final yy = s.top + s.height * (.22 + j * .17);
          _wave(
            canvas,
            s.left - s.width * .3,
            s.right + s.width * .3,
            yy,
            s.height * .012,
            t * 2 + j,
            const ui.Color(0xAA6DEAFF),
            2.8,
          );
        }
        return;
      case 'Rainbow Sha...':
        final cols = [
          const ui.Color(0xFFFE4E81),
          const ui.Color(0xFFFFCC61),
          const ui.Color(0xFF6FFDC1),
          const ui.Color(0xFF74D4FF),
          const ui.Color(0xFFBC7BFF),
        ];
        for (var j = 4; j >= 0; j--) {
          _outline(canvas, s, cols[j].withValues(alpha: .55), j * 2.3 + 2.8);
        }
        return;
      case 'Starry Clouds':
        _outline(canvas, s, const ui.Color(0x8868D5FF), 4);
        _particles(
          canvas,
          s,
          t,
          const ui.Color(0xFF9FEFFF),
          43,
          xSpread: 1.2,
          ySpread: 1.6,
        );
        return;
      case 'Doodle Groo...':
        final colors = [
          const ui.Color(0xFFFF887C),
          const ui.Color(0xFF5AE3D5),
          const ui.Color(0xFFFFCC6B),
          const ui.Color(0xFFB187FF),
        ];
        for (var j = 0; j < colors.length; j++) {
          _wave(
            canvas,
            s.left - s.width * .4,
            s.right + s.width * .4,
            s.top + s.height * (.20 + j * .22),
            s.height * .032,
            t * 1.4 + j,
            colors[j],
            4.7,
          );
        }
        return;
      case 'Sinking':
        _outline(canvas, s, const ui.Color(0xFFFFD86B), 3.3);
        for (var j = 0; j < 5; j++) {
          _slash(
            canvas,
            s.left + j * s.width / 4,
            s.bottom - s.height * .06,
            s.left + j * s.width / 4,
            s.bottom + s.height * (.13 + math.sin(t + j) * .02),
            const ui.Color(0x88FFAC4B),
            2.6,
          );
        }
        return;
      case 'Glowing Rain':
        _outline(canvas, s, const ui.Color(0xAA4CCBFF), 3.8);
        _particles(
          canvas,
          s,
          t,
          const ui.Color(0xFFB17CFF),
          36,
          xSpread: 1.3,
          ySpread: 1.8,
          rain: true,
        );
        return;
      case 'أشكال':
        _outline(canvas, s, const ui.Color(0x885ED5FF), 2.3);
        for (var j = 0; j < 4; j++) {
          final yp = s.top + s.height * (.16 + j * .20);
          final path = ui.Path()
            ..moveTo(s.left - s.width * .16, yp)
            ..lineTo(s.cx - s.width * .15, yp + s.height * .032)
            ..lineTo(s.cx + s.width * .15, yp - s.height * .044)
            ..lineTo(s.right + s.width * .18, yp);
          final c = j.isEven
              ? const ui.Color(0xFF6ADFFF)
              : const ui.Color(0xFFB18CFF);
          canvas.drawPath(
            path,
            ui.Paint()
              ..color = c
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = 3.0,
          );
        }
        return;
      case 'White Outline':
        _outline(canvas, s, const ui.Color(0xFFFFFFFF), 3.4);
        return;
      case 'Colorful Outl...':
        _outline(canvas, s, const ui.Color(0xFF00CFFF), 5.6);
        _outline(canvas, s, const ui.Color(0xFFFF66DD), 2.2);
        return;
      case 'Thermal Aura...':
        _outline(canvas, s, const ui.Color(0xFFFFD55F), 6.1);
        _outline(canvas, s, const ui.Color(0xFFFF6C3F), 2.1);
        return;
      case 'Thermal Aura':
        _outline(canvas, s, const ui.Color(0xFF7BFFAD), 6.1);
        _outline(canvas, s, const ui.Color(0xFFBE6FFF), 2.2);
        return;
      case 'تحديد':
        _outline(canvas, s, const ui.Color(0xFFD0F9FF), 2.5);
        return;
      case 'بريق':
        _outline(canvas, s, const ui.Color(0x77FFE7A0), 2.7);
        for (
          var i = 0;
          i < s.edge.length;
          i += math.max(1, s.edge.length ~/ 20)
        ) {
          final p = s.edge[i];
          final a = t * 3 + i;
          final shine = 2.5 + math.sin(a) * 1.5;
          canvas.drawLine(
            p.translate(-shine, 0),
            p.translate(shine, 0),
            ui.Paint()
              ..color = const ui.Color(0xFFFAE8A4)
              ..strokeWidth = 1.1,
          );
          canvas.drawLine(
            p.translate(0, -shine),
            p.translate(0, shine),
            ui.Paint()
              ..color = const ui.Color(0xFFFAE8A4)
              ..strokeWidth = 1.1,
          );
        }
        return;
    }
  }

  static void _helix(
    ui.Canvas canvas,
    _SubjectShape s,
    double t,
    ui.Color a,
    ui.Color b,
  ) {
    for (var j = 0; j < 2; j++) {
      final path = ui.Path();
      for (var n = 0; n <= 42; n++) {
        final yy = s.bottom - n / 42 * s.height;
        final xx =
            s.cx +
            math.sin(n / 42 * math.pi * 6 + t * 2.5 + j * math.pi) *
                s.width *
                .52;
        if (n == 0) {
          path.moveTo(xx, yy);
        } else {
          path.lineTo(xx, yy);
        }
      }
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = (j == 0 ? a : b).withValues(alpha: .55)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 11
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7),
      );
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = j == 0 ? a : b
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 3.0,
      );
    }
  }

  static void _slash(
    ui.Canvas canvas,
    double x0,
    double y0,
    double x1,
    double y1,
    ui.Color color,
    double stroke,
  ) {
    canvas.drawLine(
      ui.Offset(x0, y0),
      ui.Offset(x1, y1),
      ui.Paint()
        ..color = color.withValues(alpha: .38)
        ..strokeWidth = stroke * 5
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    );
    canvas.drawLine(
      ui.Offset(x0, y0),
      ui.Offset(x1, y1),
      ui.Paint()
        ..color = color
        ..strokeWidth = stroke,
    );
  }

  static void _wave(
    ui.Canvas canvas,
    double left,
    double right,
    double y,
    double amp,
    double phase,
    ui.Color color,
    double stroke,
  ) {
    final path = ui.Path()..moveTo(left, y);
    for (var j = 1; j <= 32; j++) {
      final xx = left + (right - left) * j / 32;
      path.lineTo(xx, y + math.sin(j * math.pi / 5 + phase) * amp);
    }
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = color
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = stroke
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
    );
  }

  static void _particles(
    ui.Canvas canvas,
    _SubjectShape s,
    double t,
    ui.Color color,
    int count, {
    double xSpread = 1.0,
    double ySpread = 1.0,
    bool rain = false,
  }) {
    for (var j = 0; j < count; j++) {
      final fraction = (j * 0.61803398875) % 1.0;
      final py = (j * 0.38196601125 + (t * (rain ? .45 : .04))) % 1.0;
      final x = s.cx + (fraction - .5) * s.width * xSpread * 2;
      final y = s.cy + (py - .5) * s.height * ySpread;
      final p = ui.Paint()
        ..color = color.withValues(
          alpha: (.3 + (j % 5) * .12).clamp(0.0, .9).toDouble(),
        );
      if (rain) {
        canvas.drawLine(
          ui.Offset(x, y),
          ui.Offset(x - 2, y + 15),
          p..strokeWidth = 2.4,
        );
      } else {
        canvas.drawCircle(ui.Offset(x, y), 1.2 + (j % 3), p);
      }
    }
  }

  static void _copyPerson(
    ui.Canvas canvas,
    ui.Image person,
    double dx,
    double dy, {
    double alpha = 1.0,
    ui.Color? tint,
  }) {
    canvas.save();
    canvas.translate(dx, dy);
    final paint = ui.Paint()
      ..color = ui.Color.fromRGBO(255, 255, 255, alpha)
      ..filterQuality = ui.FilterQuality.low;
    if (tint != null) {
      paint.colorFilter = ui.ColorFilter.mode(tint, ui.BlendMode.modulate);
    }
    canvas.drawImage(person, ui.Offset.zero, paint);
    canvas.restore();
  }

  static void _outline(
    ui.Canvas canvas,
    _SubjectShape s,
    ui.Color color,
    double thickness,
  ) {
    final blur = ui.Paint()
      ..color = color.withValues(alpha: .38)
      ..strokeWidth = thickness * 3
      ..strokeCap = ui.StrokeCap.round
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5);
    final core = ui.Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawPoints(ui.PointMode.points, s.edge, blur);
    canvas.drawPoints(ui.PointMode.points, s.edge, core);
  }

  static void _ring(
    ui.Canvas canvas,
    double x,
    double y,
    double rx,
    double ry,
    ui.Color color,
    double spin,
  ) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(math.sin(spin) * .10);
    final rect = ui.Rect.fromCenter(
      center: ui.Offset.zero,
      width: rx * 2,
      height: ry * 2,
    );
    canvas.drawOval(
      rect,
      ui.Paint()
        ..color = color.withValues(alpha: .44)
        ..strokeWidth = 12
        ..style = ui.PaintingStyle.stroke
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
    );
    canvas.drawOval(
      rect,
      ui.Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = ui.PaintingStyle.stroke,
    );
    canvas.restore();
  }

  static void _wings(
    ui.Canvas canvas,
    _SubjectShape s,
    ui.Color color,
    bool broad,
    double t, {
    _BodyPose? pose,
  }) {
    final center = pose?.shoulderCenter;
    final anchorY = center?.dy ?? (s.top + s.height * .30);
    final widthFromShoulders = pose?.shoulderWidth;
    final wingW =
        (widthFromShoulders != null && widthFromShoulders > 12
            ? widthFromShoulders
            : s.width) *
        (broad ? 1.10 : 1.32);
    final wingH = s.height * (broad ? .21 : .32);
    final flutter = math.sin(t * 3.7) * wingH * .07;
    for (final dir in [-1.0, 1.0]) {
      final shoulderA = pose?.joints['leftShoulder'];
      final shoulderB = pose?.joints['rightShoulder'];
      final shoulder = shoulderA != null && shoulderB != null
          ? (dir < 0
                ? (shoulderA.dx < shoulderB.dx ? shoulderA : shoulderB)
                : (shoulderA.dx > shoulderB.dx ? shoulderA : shoulderB))
          : null;
      final startX = shoulder?.dx ?? (s.cx + dir * s.width * .18);
      final endX = startX + dir * wingW;
      final path = ui.Path()
        ..moveTo(startX, anchorY)
        ..cubicTo(
          startX + dir * wingW * .10,
          anchorY - wingH * .52,
          endX - dir * wingW * .19,
          anchorY - wingH * .81 + flutter,
          endX,
          anchorY - wingH * .67 + flutter,
        )
        ..quadraticBezierTo(
          endX + dir * wingW * .09,
          anchorY + wingH * .12,
          startX,
          anchorY + wingH * .62,
        )
        ..close();
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = color.withValues(alpha: .21)
          ..style = ui.PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = color
          ..strokeWidth = broad ? 4 : 2.8
          ..style = ui.PaintingStyle.stroke
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
      );
      for (var i = 1; i <= 4; i++) {
        canvas.drawLine(
          ui.Offset(startX, anchorY),
          ui.Offset(
            startX + dir * wingW * i / 5,
            anchorY - wingH * (.8 - i * .06) + flutter,
          ),
          ui.Paint()
            ..color = color.withValues(alpha: .7)
            ..strokeWidth = 1.2,
        );
      }
    }
  }
}
