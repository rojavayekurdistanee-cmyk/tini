import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import 'dart:io';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:convert';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';

import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart';
import 'package:http/http.dart' as http;

import 'media_quality.dart';
import 'crop_model.dart';
import 'crop_color_filters.dart';
import 'crop_rotation.dart';
import 'crop_magic_effects.dart';
import 'crop_animation_filters.dart';
import 'crop_effects_render.dart';
import 'crop_vibe_effects_export.dart';
import 'crop_background_engine.dart';
import 'crop_body_fx_engine.dart';
import 'crop_sled_effect.dart';
import 'crop_scene_fx_engine.dart';
import 'crop_retouch_engine.dart';
import 'crop_retouch_model.dart';
import 'crop_animation_model.dart';
import 'crop_background_model.dart';
import 'crop_effects_model.dart';
import 'crop_overlay_model.dart';
import 'tini_edit_cache.dart';
import 'tini_retouch_export.dart';
import 'tini_video_pipeline.dart';
import 'tini_media3_export_v1.dart';
part 'tini_edit_render_graph.dart';

class _TiniNoCachedOutput implements Exception {}

// [Tini]: تعريف التنسيقات الأربعة للهوية البصرية
enum DuetLayout { sideBySide, topBottom, react, greenScreen }

class VideoProcessor {
  static Future<FFmpegSession> _executeArguments(List<String> args,
      {bool Function()? cancelled}) async {
    if (cancelled?.call() == true) throw TiniEditCancelled();
    final filterThreads = Platform.numberOfProcessors.clamp(1, 4);
    final complete = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeWithArgumentsAsync([
      '-filter_threads', '$filterThreads', '-filter_complex_threads', '$filterThreads',
      '-threads', '$filterThreads',
      ...args.take(args.length - 1), '-threads', '2', args.last,
    ], (done) { if (!complete.isCompleted) complete.complete(done); });
    final sessionId = session.getSessionId();
    if (sessionId == null) throw StateError('FFmpeg did not create a session');
    var cancelSent = false;
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!cancelSent && cancelled?.call() == true) {
        cancelSent = true;
        unawaited(FFmpegKit.cancel(sessionId).catchError((Object error) {
          developer.log('Cancellation failed: $error', name: 'TiniExport');
        }));
      }
    });
    try {
      final result = await complete.future;
      if (cancelled?.call() == true) throw TiniEditCancelled();
      return result;
    } finally { timer.cancel(); }
  }

  static Future<FFmpegSession> _executeBounded(String command) {
    final args = FFmpegKitConfig.parseArguments(command);
    return FFmpegKit.executeWithArguments([
      '-filter_threads',
      '1',
      '-filter_complex_threads',
      '1',
      '-threads',
      '2',
      ...args.take(args.length - 1),
      '-threads',
      '2',
      args.last,
    ]);
  }

  static int _fileSerial = 0;
  static String _serial() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_fileSerial++}';
  // Use Media3 only for a plain local MP4 clip; GIF, overlays, audio mixing,
  // retouch, face effects and the complete edit graph keep their original path.
  // Preserve stream-copy trimming elsewhere; that path is already lossless.
  // Any native failure falls back to the existing FFmpeg implementation.
  static Future<String?> _tryMedia3SimpleTrim({
    required String inputPath,
    required Duration start,
    required Duration end,
    bool mute = false,
  }) async {
    if (!Platform.isAndroid ||
        !inputPath.toLowerCase().endsWith('.mp4') ||
        start.isNegative ||
        end <= start) {
      return null;
    }
    final watch = Stopwatch()..start();
    try {
      if (!await TiniMedia3Export.isAvailable()) return null;
      final output = await TiniMedia3Export.start(
        inputPath: inputPath,
        start: start,
        end: end,
        mute: mute,
      ).result;
      final file = File(output);
      if (!await file.exists() || await file.length() == 0) {
        developer.log(
          'Empty Media3 export; falling back to FFmpeg.',
          name: 'TiniMedia3',
        );
        return null;
      }
      developer.log(
        'Simple trim completed in ${watch.elapsedMilliseconds}ms',
        name: 'TiniMedia3',
      );
      return output;
    } catch (error, stack) {
      developer.log(
        'Media3 simple trim failed; falling back to FFmpeg.',
        name: 'TiniMedia3',
        error: error,
        stackTrace: stack,
      );
      return null;
    }
  }

  static Future<String?> _cachedMedia(
    String stage,
    Object parameters,
    List<String> paths,
    Future<String?> Function(List<String>) render, {
    String extension = 'mp4',
  }) async {
    try {
      final cache = TiniEditCache.shared;
      final sources = <TiniEditNode>[
        for (final path in paths) await cache.source(path),
      ];
      final node = TiniEditNode(
        stage: stage,
        parameters: parameters,
        inputs: sources,
        extension: extension,
        render: (i, stop) async {
          if (stop()) throw TiniEditCancelled();
          final path = await render(i.map((p) => p.path).toList());
          if (path == null) throw _TiniNoCachedOutput();
          return TiniEditArtifact(
            path,
            temporary: !i.any((input) => input.path == path),
          );
        },
      );
      return (await cache.run(node)).path;
    } on _TiniNoCachedOutput {
      return null;
    } on FileSystemException {
      return render(paths);
    }
  }

  // atempo supports 0.5..2 in every stage; cascade stages for 0.1..10.
  static String _tempoFilters(double speed) {
    var remaining = speed.clamp(.1, 10.0).toDouble();
    final values = <double>[];
    while (remaining > 2.0 + 0.000001) {
      values.add(2.0);
      remaining /= 2;
    }
    while (remaining < .5 - 0.000001) {
      values.add(.5);
      remaining /= .5;
    }
    values.add(remaining.clamp(.5, 2.0).toDouble());
    return values.map((v) => 'atempo=${v.toStringAsFixed(7)}').join(',');
  }

  /// Create a single speed-aware FFmpeg command per source clip. A curve is
  /// sampled into short continuous regions, and each region's output length
  /// is calculated from the exact time integral of its piecewise-linear curve.
  /// Both real audio and silence undergo the same time mapping.
  static String _speedRenderCommand({
    required CropClip clip,
    required String source,
    required Duration start,
    required int width,
    required int height,
    required String output,
    required bool useSourceAudio,
    bool lossless = false,
  }) {
    final sourceDuration = clip.duration.inMicroseconds / 1000000.0;
    if (sourceDuration <= 0) throw StateError('Invalid speed clip duration');
    final cuts = <double>[0];
    if (clip.speed.isCurve) {
      final maxSegments = (sourceDuration / .12).ceil().clamp(1, 40);
      final divisions = maxSegments;
      for (var i = 1; i < divisions; i++) {
        cuts.add(i / divisions);
      }
    }
    cuts.add(1);
    final base = start.inMicroseconds / 1000000.0;
    final filters = <String>[];
    final inputs = StringBuffer();
    for (var i = 0; i < cuts.length - 1; i++) {
      final a = cuts[i], b = cuts[i + 1];
      final startAt = base + sourceDuration * a;
      final endAt = base + sourceDuration * b;
      final sourceSpan = (endAt - startAt);
      final outputSpan =
          sourceDuration *
          (clip.speed.playbackFraction(b) - clip.speed.playbackFraction(a));
      final rate = (sourceSpan / outputSpan).clamp(.1, 10.0).toDouble();
      filters.add(
        '[0:v]trim=start=${startAt.toStringAsFixed(6)}:'
        'end=${endAt.toStringAsFixed(6)},'
        'setpts=(PTS-STARTPTS)/${rate.toStringAsFixed(8)}[v$i]',
      );
      if (useSourceAudio && !clip.isMuted) {
        filters.add(
          '[0:a]atrim=start=${startAt.toStringAsFixed(6)}:'
          'end=${endAt.toStringAsFixed(6)},asetpts=PTS-STARTPTS,'
          '${_tempoFilters(rate)},aresample=44100[a$i]',
        );
      } else {
        filters.add(
          '[1:a]atrim=duration=${outputSpan.toStringAsFixed(6)},'
          'asetpts=PTS-STARTPTS[a$i]',
        );
      }
      inputs.write('[v$i][a$i]');
    }
    filters.add('${inputs}concat=n=${cuts.length - 1}:v=1:a=1[vconcat][acat]');
    if (clip.magicEffectId != null) {
      filters.addAll(
        CropMagicEffects.filterGraph(
          input: 'vconcat',
          output: 'vprocessed',
          id: clip.magicEffectId,
          seconds: clip.playbackDuration.inMicroseconds / 1000000.0,
          width: width,
          height: height,
        ),
      );
    }
    final resultVideo = clip.magicEffectId == null ? 'vconcat' : 'vprocessed';
    if (clip.animations.hasEffects) {
      filters.addAll(
        CropAnimationFilters.filterGraph(
          input: resultVideo,
          output: 'vanim',
          settings: clip.animations,
          seconds: clip.playbackDuration.inMicroseconds / 1000000.0,
          width: width,
          height: height,
        ),
      );
    }
    final finalVideo = clip.animations.hasEffects ? 'vanim' : resultVideo;
    if (clip.videoEffects.isNotEmpty) {
      filters.addAll(
        TiniEffectsRender.filterGraph(
          input: finalVideo,
          output: 'vfx',
          effects: clip.videoEffects,
          seconds: clip.playbackDuration.inMicroseconds / 1000000.0,
          width: width,
          height: height,
        ),
      );
    }
    filters.add(
      lossless
          ? '[${clip.videoEffects.isNotEmpty ? 'vfx' : finalVideo}]null[vout]'
          : '[${clip.videoEffects.isNotEmpty ? 'vfx' : finalVideo}]scale=$width:$height:'
                'force_original_aspect_ratio=decrease,'
                'pad=$width:$height:(ow-iw)/2:(oh-ih)/2,'
                'setsar=1,fps=30,format=yuv420p[vout]',
    );
    final graph = filters.join(';');
    return '-i "$source" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 '
        '-filter_complex "$graph" -map "[vout]" -map "[acat]" '
        '${lossless ? '-c:v ffv1 -level 3' : '-c:v libx264 -preset veryfast -crf 21 -pix_fmt yuv420p'} '
        '${lossless ? '-c:a pcm_s16le' : '-c:a aac -b:a 128k'} -ar 44100 -ac 2 '
        '${lossless ? '-fps_mode passthrough' : '-movflags +faststart'} -y "$output"';
  }

  /// Normal-speed clip with a Magic graph.  Existing no-effect command stays
  /// unchanged; a silent audio stream is always available as fallback.
  static String _magicNormalCommand({
    required CropClip clip,
    required String source,
    required Duration start,
    required int width,
    required int height,
    required String output,
    required bool useSourceAudio,
  }) {
    final length = clip.duration.inMicroseconds / 1000000.0;
    final graph = <String>[
      '[0:v]trim=duration=${length.toStringAsFixed(6)},'
          'setpts=PTS-STARTPTS,fps=30[vbase]',
      ...CropMagicEffects.filterGraph(
        input: 'vbase',
        output: 'vmagic',
        id: clip.magicEffectId,
        seconds: length,
        width: width,
        height: height,
      ),
      if (clip.animations.hasEffects)
        ...CropAnimationFilters.filterGraph(
          input: 'vmagic',
          output: 'vanim',
          settings: clip.animations,
          seconds: length,
          width: width,
          height: height,
        ),
      if (clip.videoEffects.isNotEmpty)
        ...TiniEffectsRender.filterGraph(
          input: clip.animations.hasEffects ? 'vanim' : 'vmagic',
          output: 'vfx',
          effects: clip.videoEffects,
          seconds: length,
          width: width,
          height: height,
        ),
      '[${clip.videoEffects.isNotEmpty ? 'vfx' : (clip.animations.hasEffects ? 'vanim' : 'vmagic')}]scale=$width:$height:force_original_aspect_ratio=decrease,'
          'pad=$width:$height:(ow-iw)/2:(oh-ih)/2,'
          'setsar=1,fps=30,format=yuv420p[vout]',
      if (useSourceAudio && !clip.isMuted)
        '[0:a]atrim=duration=${length.toStringAsFixed(6)},'
            'asetpts=PTS-STARTPTS,aresample=44100[aout]'
      else
        '[1:a]atrim=duration=${length.toStringAsFixed(6)},'
            'asetpts=PTS-STARTPTS[aout]',
    ].join(';');
    final begin = _formatDuration(start);
    return '-ss $begin -t ${length.toStringAsFixed(6)} -i "$source" '
        '-f lavfi -t ${length.toStringAsFixed(6)} '
        '-i anullsrc=channel_layout=stereo:sample_rate=44100 '
        '-filter_complex "$graph" -map "[vout]" -map "[aout]" '
        '-c:v libx264 -preset veryfast -crf 21 -pix_fmt yuv420p '
        '-c:a aac -b:a 128k -ar 44100 -ac 2 '
        '-movflags +faststart -y "$output"';
  }

  /// Export a sequence that may contain locally replaced segments.  This is
  /// invoked only for a project that actually has replacementPath metadata;
  /// all other publish paths retain their original implementation.
  static Future<String> renderReplacementClips({
    required String originalPath,
    required List<CropClip> clips,
    required int width,
    required int height,
    bool Function()? cancelled,
    bool cacheWarmup = false,
    bool? hardwareRetouch,
    String? editorRevision,
    String? parentEditorRevision,
  }) async {
    try {
      return await _TiniReplacementGraph.render(
        originalPath: originalPath,
        clips: clips,
        width: width,
        height: height,
        cancelled: cancelled,
        hardwareRetouch: hardwareRetouch,
        editorRevision: editorRevision,
        parentEditorRevision: parentEditorRevision,
      );
    } catch (error) {
      final message = error.toString().toLowerCase();
      final noSpace =
          message.contains('no space left') ||
          (error is FileSystemException && error.osError?.errorCode == 28);
      final noCodec =
          message.contains('unknown encoder') && message.contains('ffv1');
      // A MediaCodec stream can pass encoding yet fail frame/geometry checks.
      // The graph normally retries with homogeneous software clips, but if
      // those retries also fail, do not leak the raw hardware exception into
      // Publish before trying the existing feature-complete compatibility path.
      final hardwareStreamFailure = error is _TiniStreamEncodingFailure;
      if (cacheWarmup || (!noSpace && !noCodec &&
          !hardwareStreamFailure && error is! _TiniStageFailure))
        rethrow;
      if (cancelled?.call() == true) throw CropRetouchCancelled();
      if (noSpace) await TiniEditCache.shared.prune(targetBytes: 0);
      if (hardwareStreamFailure) {
        developer.log('Hardware stream could not be delivered; using original '
            'feature-complete compatibility renderer',
            name: 'TiniExport.hardwareFallback', error: error);
      }
      // Same feature-complete path used before caching. Never substitute raw media.
      final nativeRetouch =
          (hardwareRetouch ?? Platform.isAndroid) &&
          clips.any((c) => c.duration.inMicroseconds > 0 && c.retouch.enabled);
      final compatibleClips = nativeRetouch
          ? clips
                .map((c) => c.copyWith(retouch: const CropRetouchSettings()))
                .toList(growable: false)
          : clips;
      final sources = <String>{
        originalPath,
        for (final c in clips) ...[
          if (c.replacementPath != null) c.replacementPath!,
          if (c.backgroundPath != null) c.backgroundPath!,
          if (c.cutout?.hasMask == true) c.cutout!.maskDirectory,
        ],
      }.toList();
      try {
        // A compatibility result is also reusable. The original complete clip
        // settings go into this path, including retouch, filters and effects.
        final compatible = (await _cachedMedia(
          nativeRetouch
              ? 'timeline.compatibility.base.v3'
              : 'timeline.compatibility.v1',
          {
            'clips': compatibleClips
                .map(_TiniReplacementGraph.describe)
                .toList(),
            'size': [width, height],
          },
          sources,
          (_) => _renderReplacementClipsLegacy(
            originalPath: originalPath,
            clips: compatibleClips,
            width: width,
            height: height,
            cancelled: cancelled,
          ),
        ))!;
        if (!nativeRetouch) return compatible;
        try {
          final size = CropOverlayOutputSize.fromSource(
            width.toDouble(),
            height.toDouble(),
          );
          return await TiniRetouchExport.render(
            input: compatible,
            outputWidth: size.width,
            outputHeight: size.height,
            durationMs:
                clips.fold<int>(
                  0,
                  (total, c) =>
                      total +
                      (c.duration.inMicroseconds > 0
                          ? c.playbackDuration.inMicroseconds
                          : 0),
                ) ~/
                1000,
            regions: _TiniReplacementGraph.hardwareRegions(clips),
            cancelled: cancelled,
          );
        } finally {
          try {
            await File(compatible).delete();
          } on FileSystemException {
            // An owned cache lease may already have been cleaned up.
          }
        }
      } catch (compatibilityError) {
        if (compatibilityError is CropRetouchCancelled ||
            compatibilityError is TiniEditCancelled)
          rethrow;
        throw await _TiniStageFailure.record(
          'مسار التوافق',
          compatibilityError.toString(),
        );
      }
    }
  }

  static Future<String> _renderReplacementClipsLegacy({
    required String originalPath,
    required List<CropClip> clips,
    required int width,
    required int height,
    bool Function()? cancelled,
  }) async {
    if (clips.isEmpty) throw StateError('No clips to render');
    final safeWidth = (width > 0 ? width : 720).clamp(2, 1920) ~/ 2 * 2;
    final safeHeight = (height > 0 ? height : 1280).clamp(2, 1920) ~/ 2 * 2;
    final temp = await getTemporaryDirectory();
    final serial = DateTime.now().microsecondsSinceEpoch;
    final parts = <String>[];
    final composited = <String>[];
    final listPath = '${temp.path}/tini_replace_$serial.txt';
    final finalPath = '${temp.path}/tini_replace_final_$serial.mp4';
    try {
      for (int index = 0; index < clips.length; index++) {
        if (cancelled?.call() == true) throw CropRetouchCancelled();
        final clip = clips[index];
        if (clip.duration.inMilliseconds <= 0) continue;
        var path = clip.replacementPath ?? originalPath;
        var start = clip.replacementPath == null
            ? clip.startTime
            : clip.replacementStartTime;
        // Composite on original source time. Speed and Magic are applied
        // afterwards, exactly as they are for an unedited clip.
        if (clip.cutout != null || clip.backgroundPath != null) {
          final compositePath = await CropBackgroundEngine.composeClip(
            source: path,
            sourceStart: start,
            clip: clip,
            width: safeWidth,
            height: safeHeight,
          );
          composited.add(compositePath);
          path = compositePath;
          start = Duration.zero;
        }
        final duration = clip.duration.inMilliseconds / 1000.0;
        final part = '${temp.path}/tini_replace_${serial}_$index.mp4';
        composited.add(
          part,
        ); // Also clean up a cancelled/failed in-progress part.
        final videoFilter =
            'scale=$safeWidth:$safeHeight:'
            'force_original_aspect_ratio=decrease,'
            'pad=$safeWidth:$safeHeight:(ow-iw)/2:(oh-ih)/2,'
            'setsar=1,fps=30,format=yuv420p';
        final input =
            '-ss ${_formatDuration(start)} -t $duration -i "$path" '
            '-f lavfi -t $duration -i anullsrc=channel_layout=stereo:sample_rate=44100';
        final encode =
            '-vf "$videoFilter" -map 0:v:0 '
            '-c:v libx264 -preset veryfast -crf 21 -pix_fmt yuv420p '
            '-c:a aac -b:a 128k -ar 44100 -ac 2 '
            '-t $duration -movflags +faststart -y "$part"';
        final audioMap = clip.isMuted ? '-map 1:a:0' : '-map 0:a:0';
        var session = clip.speed.isDefault
            ? await _executeBounded(
                clip.magicEffectId == null &&
                        !clip.animations.hasEffects &&
                        clip.videoEffects.isEmpty
                    ? '$input $audioMap $encode'
                    : _magicNormalCommand(
                        clip: clip,
                        source: path,
                        start: start,
                        width: safeWidth,
                        height: safeHeight,
                        output: part,
                        useSourceAudio: !clip.isMuted,
                      ),
              )
            : await _executeBounded(
                _speedRenderCommand(
                  clip: clip,
                  source: path,
                  start: start,
                  width: safeWidth,
                  height: safeHeight,
                  output: part,
                  useSourceAudio: !clip.isMuted,
                ),
              );
        if (!ReturnCode.isSuccess(await session.getReturnCode()) &&
            !clip.isMuted) {
          // Missing audio sources fall back to a time-matched silent track.
          session = clip.speed.isDefault
              ? await _executeBounded(
                  clip.magicEffectId == null &&
                          !clip.animations.hasEffects &&
                          clip.videoEffects.isEmpty
                      ? '$input -map 1:a:0 $encode'
                      : _magicNormalCommand(
                          clip: clip,
                          source: path,
                          start: start,
                          width: safeWidth,
                          height: safeHeight,
                          output: part,
                          useSourceAudio: false,
                        ),
                )
              : await _executeBounded(
                  _speedRenderCommand(
                    clip: clip,
                    source: path,
                    start: start,
                    width: safeWidth,
                    height: safeHeight,
                    output: part,
                    useSourceAudio: false,
                  ),
                );
        }
        if (!ReturnCode.isSuccess(await session.getReturnCode())) {
          throw StateError(
            'Failed to render replacement segment $index: '
            '${(await session.getAllLogsAsString()) ?? ''}',
          );
        }
        // The existing editor, magic, animation and colour-effect graphs
        // finish first. Procedural Vibe sprites are alpha-composited on top,
        // with the source AAC stream copied unchanged.
        var readyPart = part;
        if (TiniVibeEffectsExport.hasVibe(clip.videoEffects)) {
          readyPart = await TiniVibeEffectsExport.compose(
            inputPath: readyPart,
            effects: clip.videoEffects,
            seconds: clip.playbackDuration.inMicroseconds / 1000000.0,
            width: safeWidth,
            height: safeHeight,
          );
          composited.add(part); // Temporary intermediate, remove in finally.
        }
        if (TiniBodyFxEngine.hasBodyEffects(clip.videoEffects)) {
          // ML masks follow the ORIGINAL frames (before speed), while overlay
          // timing follows the output-time curve, including trimmed regions.
          final bodySource = clip.replacementPath ?? originalPath;
          final bodyStart = clip.replacementPath == null
              ? clip.startTime
              : clip.replacementStartTime;
          final overlayFrames = await TiniBodyFxEngine.prepare(
            clip: clip,
            source: bodySource,
            sourceStart: bodyStart,
          );
          try {
            final bodyPart = await TiniBodyFxEngine.compose(
              renderedPath: readyPart,
              frames: overlayFrames,
              width: safeWidth,
              height: safeHeight,
            );
            composited.add(readyPart);
            readyPart = bodyPart;
          } finally {
            await overlayFrames.dispose();
          }
        }
        if (TiniSledEffect.hasEffect(clip.videoEffects)) {
          final sledPart = await TiniSledExport.compose(
            inputPath: readyPart,
            effects: clip.videoEffects,
            seconds: clip.playbackDuration.inMicroseconds / 1000000.0,
            width: safeWidth,
            height: safeHeight,
          );
          if (sledPart != readyPart) {
            composited.add(readyPart);
            readyPart = sledPart;
          }
        }
        if (TiniFaceSceneFx.hasDog(clip.videoEffects)) {
          final dogPart = await TiniFaceSceneExport.composeDog(
            inputPath: readyPart,
            effects: clip.videoEffects,
            seconds: clip.playbackDuration.inMicroseconds / 1000000.0,
            width: safeWidth,
            height: safeHeight,
          );
          if (dogPart != readyPart) {
            composited.add(readyPart);
            readyPart = dogPart;
          }
        }
        // Grade the completed picture, including procedural/ML overlays, just
        // as the live preview does. Copy audio and preserve timing and speed.
        if (clip.colorFilter.enabled) {
          final graded = '${temp.path}/tini_grade_${serial}_$index.mp4';
          composited.add(readyPart);
          composited.add(graded);
          final gradeSession = await _executeBounded(
            '-i "$readyPart" -vf "${clip.colorFilter.ffmpeg},format=yuv420p" '
            '-map 0:v:0 -map 0:a? -c:v libx264 -preset veryfast -crf 18 '
            '-pix_fmt yuv420p -c:a copy -movflags +faststart -y "$graded"',
          );
          if (!ReturnCode.isSuccess(await gradeSession.getReturnCode())) {
            throw StateError(
              'Failed to apply colour filter: '
              '${(await gradeSession.getAllLogsAsString()) ?? ''}',
            );
          }
          readyPart = graded;
        }
        // Retouch the finished base picture; overlay media is composed later.
        // Zero settings leave the entire previous render path unchanged.
        if (clip.retouch.enabled) {
          final retouched = await CropRetouchEngine.render(
            input: readyPart,
            settings: clip.retouch,
            durationMs: clip.playbackDuration.inMilliseconds,
            width: safeWidth,
            height: safeHeight,
            cancelled: cancelled,
          );
          if (retouched.path != readyPart) {
            composited.add(readyPart);
            readyPart = retouched.path;
          }
        }
        if (clip.rotationQuarterTurns % 4 != 0) {
          if (cancelled?.call() == true) throw CropRetouchCancelled();
          final rotated = '${temp.path}/tini_rotation_${serial}_$index.mp4';
          composited.add(readyPart);
          composited.add(rotated);
          final filter = CropRotation.ffmpeg(
            clip.rotationQuarterTurns, safeWidth, safeHeight,
          );
          final rotationSession = await _executeBounded(
            '-i "$readyPart" -vf "$filter,format=yuv420p" '
            '-map 0:v:0 -map 0:a? -c:v libx264 -preset veryfast -crf 18 '
            '-pix_fmt yuv420p -c:a copy -movflags +faststart -y "$rotated"',
          );
          if (!ReturnCode.isSuccess(await rotationSession.getReturnCode())) {
            throw StateError('Failed to rotate segment $index: '
                '${(await rotationSession.getAllLogsAsString()) ?? ''}');
          }
          readyPart = rotated;
        }
        parts.add(readyPart);
      }
      if (cancelled?.call() == true) throw CropRetouchCancelled();
      if (parts.isEmpty) throw StateError('No playable replacement segments');
      await File(listPath).writeAsString(
        parts.map((p) => "file '${p.replaceAll("'", "'\\''")}'").join('\n'),
      );
      final joined = await _executeBounded(
        '-f concat -safe 0 -i "$listPath" -c copy -movflags +faststart -y "$finalPath"',
      );
      if (!ReturnCode.isSuccess(await joined.getReturnCode())) {
        throw StateError(
          'Failed to join replacement segments: '
          '${(await joined.getAllLogsAsString()) ?? ''}',
        );
      }
      return finalPath;
    } finally {
      for (final part in [...parts, ...composited]) {
        final file = File(part);
        if (await file.exists()) await file.delete();
      }
      final listFile = File(listPath);
      if (await listFile.exists()) await listFile.delete();
    }
  }

  static String editCacheSignature(
    String source,
    List<CropClip> clips,
    int width,
    int height,
  ) => TiniEditCache.digest({
    'source': source,
    'size': [width, height],
    'clips': clips.map(_TiniReplacementGraph.describe).toList(),
  });

  /// [Tini]: دالة الدمج النهائية مع خاصية الإجبار الزمني لضمان دقة القص
  static Future<String?> mergeDuetVideo({
    required String videoPath, // المسار المقصوص من شاشة المعاينة
    required String duetVideoUrl, // رابط فيديو الديو
    required DuetLayout selectedLayout,
    required double maxDuration, // المدة التي سيتم حسابها آلياً من شاشة النشر
  }) async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String outputPath =
          '${tempDir.path}/TitiStar_Final_${_serial()}.mp4';

      String filter = "";

      switch (selectedLayout) {
        case DuetLayout.sideBySide:
          // [Tini]: تعديل الطول لـ 800 وتوسيطه برقم 560 لضمان توازن المسافات
          filter =
              '[0:v]scale=540:1000,setsar=1,pad=540:1920:(ow-iw)/2:450:color=black[v1];'
              '[1:v]scale=540:1000,setsar=1,pad=540:1920:(ow-iw)/2:450:color=black[v2];'
              '[v1][v2]hstack=inputs=2[v]';
          break;
        case DuetLayout.topBottom:
          // تطبيق هندسة المساحة المرئية لـ Tini
          filter =
              '[1:v]scale=1080:-1,crop=1080:857,setsar=1[v1]; '
              '[0:v]scale=1080:-1,crop=1080:1063,setsar=1[v2]; '
              '[v1][v2]vstack=inputs=2[v]';
          break;
        case DuetLayout.react:
          filter =
              '[0:v]scale=1080:1920[bg]; '
              '[1:v]scale=315:450,drawbox=t=3:c=white,format=rgba, '
              'geq=lum=\'p(X,Y)\':a=\'if(gt(abs(W/2-X),W/2-30)*gt(abs(H/2-Y),H/2-30),if(lte(hypot(30-(W/2-abs(W/2-X)),30-(H/2-abs(H/2-Y))),30),255,0),255)\'[fg]; '
              '[bg][fg]overlay=x=140:y=165[v]';
          break;
        case DuetLayout.greenScreen:
          filter =
              '[1:v]scale=1080:1920[bg]; [0:v]scale=1080:1920,format=yuva420p,colorchannelmixer=aa=0.7[fg]; [bg][fg]overlay[v]';
          break;
      }

      // [Tini Engine - الحل القطعي]:
      String localDuetPath = '${tempDir.path}/duet_${_serial()}.mp4';
      final res = await http.get(Uri.parse(duetVideoUrl));
      await File(localDuetPath).writeAsBytes(res.bodyBytes);

      final String command =
          '-t $maxDuration -i "$videoPath" -t $maxDuration -i "$localDuetPath" '
          '-filter_complex "$filter; [0:a][1:a]amix=inputs=2:duration=first[a]" '
          '-map "[v]" -map "[a]" -c:v libx264 -preset ultrafast -c:a aac -shortest -y "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return outputPath;
      }
      return null;
    } catch (e) {
      print("Tini Processor Error: $e");
      return null;
    }
  }

  /// [Tini]: دالة معالجة العلامة المائية لغرض "الحفظ في الجهاز" فقط
  /// تُستخدم لإضافة اسم التطبيق واسم المستخدم على الفيديو قبل تخزينه في معرض الصور (تم دعم Android & iOS)
  static Future<String?> createSaveableVideoWithWatermark({
    required String
    inputPath, // الفيديو الجاهز (سواء كان عادياً أو ناتج دمج الديو)
    required String username, // اسم المستخدم لإضافته تحت الشعار
    bool useCache = true,
  }) async {
    if (useCache)
      return _cachedMedia(
        'createSaveableVideoWithWatermark.v1',
        {'username': username, 'platform': Platform.operatingSystem},
        [inputPath],
        (p) => createSaveableVideoWithWatermark(
          inputPath: p[0],
          username: username,
          useCache: false,
        ),
      );

    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String outputPath =
          '${tempDir.path}/TitiStar_Save_${_serial()}.mp4';

      // [تأمين معالج الخطوط الافتراضي]: تحديد مسار خط النظام لكل نظام تشغيل بشكل منفصل لمنع السقوط الصامت
      String fontConfig;
      if (Platform.isAndroid) {
        fontConfig = "fontfile='/system/fonts/Roboto-Regular.ttf':";
      } else if (Platform.isIOS) {
        fontConfig = "font='Helvetica':";
      } else {
        fontConfig = "";
      }

      // [الهوية البصرية]: تم دمج معالج الخطوط مع الإبقاء التام على الألوان والإحداثيات الأصلية
      final String watermarkFilter =
          "drawtext=${fontConfig}text='Tini':x=w-tw-30:y=h-th-70:fontsize=40:fontcolor='#009688':shadowcolor=black:shadowx=2:shadowy=2,"
          "drawtext=${fontConfig}text='@$username':x=w-tw-30:y=h-th-25:fontsize=22:fontcolor='#009688':shadowcolor=black:shadowx=1:shadowy=1";

      final String command =
          '-i "$inputPath" -vf "$watermarkFilter" -c:v libx264 -preset ultrafast -y "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return outputPath;
      }
      return null;
    } catch (e) {
      print("Tini Save Processor Error: $e");
      return null;
    }
  }

  // هذه الدالة تأخذ مسار الصورة وتخرج لك مساراً "نظيفاً" وجاهزاً للعمل
  static Future<String> prepareImageForFFmpeg(
    String originalPath, {
    bool useCache = true,
  }) async {
    if (useCache) {
      final result = await _cachedMedia(
        'prepare.image.v1',
        {'quality': 90},
        [originalPath],
        (p) => prepareImageForFFmpeg(p[0], useCache: false),
        extension: 'jpg',
      );
      if (result == null) throw StateError('Image preparation failed');
      return result;
    }
    final tempDir = await getTemporaryDirectory();
    final String outputPath = '${tempDir.path}/tini_ready_${_serial()}.jpg';

    // 1. نقرأ الصورة
    final bytes = await File(originalPath).readAsBytes();
    final image = decodeImage(bytes); // مكتبة image

    // 2. نجعل الأبعاد زوجية (نطرح 1 إذا كان الرقم فردياً)
    int width = image!.width % 2 == 0 ? image.width : image.width - 1;
    int height = image.height % 2 == 0 ? image.height : image.height - 1;

    // 3. نعيد حفظ الصورة في مسار التطبيق الخاص
    final resized = copyResize(image, width: width, height: height);
    await File(outputPath).writeAsBytes(encodeJpg(resized, quality: 90));

    return outputPath;
  }

  /// Media3 keeps the edited video bitstream while mixing an independent
  /// soundtrack on Android. A native/metadata failure must retain the exact
  /// existing FFmpeg audio implementation, not publish a silent video.
  static Future<String?> _tryMedia3MusicMix({
    required String mediaPath,
    required String audioPath,
    required Duration duration,
    required Duration musicStart,
    required Duration musicEnd,
    required double videoVolume,
    required double musicVolume,
  }) async {
    if (!Platform.isAndroid ||
        !mediaPath.toLowerCase().endsWith('.mp4') ||
        !File(mediaPath).existsSync() ||
        !File(audioPath).existsSync() ||
        musicEnd <= musicStart || musicEnd > duration) return null;
    String? output;
    try {
      if (!await TiniMedia3Export.isAvailable()) return null;
      final job = TiniMedia3Export.startMusicMix(
        videoPath: mediaPath,
        audioPath: audioPath,
        duration: duration,
        musicStart: musicStart,
        musicEnd: musicEnd,
        videoVolume: videoVolume,
        musicVolume: musicVolume,
      );
      output = await job.result;
      if (!await File(output).exists() || await File(output).length() == 0) {
        throw StateError('Media3 audio mix returned empty output');
      }
      final probe = await FFprobeKit.executeWithArguments([
        '-v', 'error', '-show_entries',
        'stream=codec_type,width,height:format=duration',
        '-of', 'json', output,
      ]);
      if (!ReturnCode.isSuccess(await probe.getReturnCode())) {
        throw StateError('Unable to verify Media3 audio composition');
      }
      final data = jsonDecode((await probe.getOutput()) ?? '{}') as Map;
      final streams = data['streams'];
      final seconds = double.tryParse('${(data['format'] as Map?)?['duration']}');
      if (streams is! List ||
          streams.whereType<Map>().where((x) => x['codec_type'] == 'video').length != 1 ||
          !streams.whereType<Map>().any((x) => x['codec_type'] == 'audio') ||
          seconds == null || !seconds.isFinite ||
          (seconds - duration.inMicroseconds / 1000000).abs() > 0.15) {
        throw StateError('Media3 music mix lost track or changed duration');
      }
      developer.log('Media3 mixed source and music without repeating video effects',
          name: 'TiniMedia3');
      return output;
    } catch (error, stack) {
      developer.log('Media3 music mix unavailable; preserving Tini audio path',
          name: 'TiniMedia3', error: error, stackTrace: stack);
      if (output != null) {
        try { await File(output).delete(); } on FileSystemException {}
      }
      return null;
    }
  }

  /// Mix independent added music into a time-remapped edited sequence.
  /// The rendered sequence always has a real/silent audio track; use that
  /// duration as the master clock so a shorter song cannot truncate video.
  static Future<String?> mergeSpeedEditedVideoWithMusic({
    required String mediaPath,
    required String audioPath,
    required double videoVolume,
    required double musicVolume,
    required Duration projectDuration,
    required double musicStartFraction,
    required double musicEndFraction,
    bool useCache = true,
  }) async {
    if (useCache)
      return _cachedMedia(
        'mergeSpeedEditedVideoWithMusic.v2.media3',
        {
          'volume': videoVolume,
          'music': musicVolume,
          'duration': projectDuration.inMicroseconds,
          'range': [musicStartFraction, musicEndFraction],
        },
        [mediaPath, audioPath],
        (p) => mergeSpeedEditedVideoWithMusic(
          mediaPath: p[0],
          audioPath: p[1],
          videoVolume: videoVolume,
          musicVolume: musicVolume,
          projectDuration: projectDuration,
          musicStartFraction: musicStartFraction,
          musicEndFraction: musicEndFraction,
          useCache: false,
        ),
      );

    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/tini_speed_mix_'
        '${_serial()}.mp4';
    final total = projectDuration.inMilliseconds;
    final startMs = (total * musicStartFraction).round().clamp(0, total);
    final endMs = (total * musicEndFraction).round().clamp(startMs, total);
    if (endMs <= startMs) return mediaPath;
    final media3 = await _tryMedia3MusicMix(
      mediaPath: mediaPath,
      audioPath: audioPath,
      duration: projectDuration,
      musicStart: Duration(milliseconds: startMs),
      musicEnd: Duration(milliseconds: endMs),
      videoVolume: videoVolume,
      musicVolume: musicVolume,
    );
    if (media3 != null) return media3;
    final start = startMs / 1000.0;
    final end = endMs / 1000.0;
    final filter =
        '[0:a]volume=$videoVolume[v];'
        '[1:a]atrim=start=${start.toStringAsFixed(3)}:'
        'end=${end.toStringAsFixed(3)},asetpts=PTS-STARTPTS,'
        'adelay=$startMs|$startMs,volume=$musicVolume[m];'
        '[v][m]amix=inputs=2:duration=first:dropout_transition=0[a]';
    final session = await FFmpegKit.execute(
      '-i "$mediaPath" -i "$audioPath" -filter_complex "$filter" '
      '-map 0:v:0 -map "[a]" -c:v copy -c:a aac -b:a 128k '
      '-ar 44100 -ac 2 -shortest -movflags +faststart -y "$path"',
    );
    if (ReturnCode.isSuccess(await session.getReturnCode())) return path;
    return null;
  }

  static Future<String?> mergeMediaWithAudio({
    required String mediaPath,
    required String audioPath,
    required double videoVolume,
    required double musicVolume,
    required bool isImage,
    // Safe only for a previously encoded MP4 created by renderReplacementClips.
    // Avoid a second full video encode when the only new operation is audio.
    bool copyVideoStream = false,
    bool useCache = true,
  }) async {
    if (useCache)
      return _cachedMedia(
        !isImage ? 'mergeMediaWithAudio.v2.media3' : 'mergeMediaWithAudio.v1',
        {
          'volume': videoVolume,
          'music': musicVolume,
          'image': isImage,
          'copy': copyVideoStream,
        },
        [mediaPath, audioPath],
        (p) => mergeMediaWithAudio(
          mediaPath: p[0],
          audioPath: p[1],
          videoVolume: videoVolume,
          musicVolume: musicVolume,
          isImage: isImage,
          copyVideoStream: copyVideoStream,
          useCache: false,
        ),
      );

    try {
      // Mix video and music without a second video encode, including plain MP4
      // sources. Still images keep the existing dedicated picture pipeline.
      if (!isImage) {
        final source = await FFprobeKit.executeWithArguments([
          '-v', 'error', '-show_entries', 'format=duration',
          '-of', 'json', mediaPath,
        ]);
        if (ReturnCode.isSuccess(await source.getReturnCode())) {
          final metadata = jsonDecode((await source.getOutput()) ?? '{}') as Map;
          final seconds = double.tryParse(
              '${(metadata['format'] as Map?)?['duration']}');
          if (seconds != null && seconds.isFinite && seconds > 0) {
            final duration = Duration(microseconds: (seconds * 1000000).round());
            final native = await _tryMedia3MusicMix(
              mediaPath: mediaPath, audioPath: audioPath, duration: duration,
              musicStart: Duration.zero, musicEnd: duration,
              videoVolume: videoVolume, musicVolume: musicVolume,
            );
            if (native != null) return native;
          }
        }
      }
      final Directory tempDir = await getTemporaryDirectory();
      final String outputPath =
          '${tempDir.path}/TitiStar_Merged_${_serial()}.mp4';

      // 1. استخدام أمر تحويل مباشر (Transcoding) يعيد بناء كل مسار على حدة
      // هذا الأمر لا يعتمد على الفلاتر المعقدة التي كانت تسبب الأخطاء
      // ويقوم بخلط الصوت باستخدام 'amerge' وهو أكثر استقراراً بكثير من 'amix'

      String command;
      if (isImage) {
        command =
            '-loop 1 -i "$mediaPath" -i "$audioPath" '
            '-filter_complex "[1:a]volume=$musicVolume[a]" '
            '-map 0:v:0 -map "[a]" -c:v libx264 -tune stillimage -c:a aac -b:a 192k -pix_fmt yuv420p -shortest -y "$outputPath"';
      } else {
        // [التعديل الجذري]: استخدام amerge بدلاً من amix
        // هذا الأمر يقوم بدمج المسارين بشكل خام (Raw) ويطبق مستوى الصوت قبل الدمج
        command =
            '-i "$mediaPath" -i "$audioPath" -filter_complex '
            '"[0:a]volume=$videoVolume[v_audio];[1:a]volume=$musicVolume[m_audio];[v_audio][m_audio]amerge=inputs=2[a]" '
            '-map 0:v:0 -map "[a]" '
            '${copyVideoStream ? '-c:v copy' : '-c:v libx264 -preset ultrafast'} '
            '-c:a aac -ac 2 -shortest -movflags +faststart -y "$outputPath"';
      }

      print("Tini Command: $command");

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        print("Tini: نجح الدمج باستخدام amerge");
        return outputPath;
      } else {
        final logs = await session.getAllLogsAsString();
        print("Tini Error Logs: $logs");
        return null;
      }
    } catch (e) {
      print("Tini Exception: $e");
      return null;
    }
  }

  /// [تصدير الفيديو المعدّل من شاشة المعاينة]: قص حقيقي + كتم الصوت + تحويل لـ GIF (فيديو صامت قصير يتكرر)
  /// - trim: قص دقيق (إعادة ترميز) من start إلى end
  /// - mute: حذف مسار الصوت فعلياً (الحجم يصغر)
  /// - gif: فيديو صامت بدقة 480 و15 إطار بالثانية (الحجم يصغر كثيراً)
  static Future<String?> exportEditedVideo({
    required String inputPath,
    required Duration start,
    required Duration end,
    required bool trim,
    required bool mute,
    required bool gif,
    String? overlayPath,
    bool useCache = true,
  }) async {
    if (useCache)
      return _cachedMedia(
        trim && !gif && overlayPath == null
            ? 'exportEditedVideo.v2.media3'
            : 'exportEditedVideo.v1',
        {
          'start': start.inMicroseconds,
          'end': end.inMicroseconds,
          'trim': trim,
          'mute': mute,
          'gif': gif,
        },
        [inputPath, if (overlayPath != null) overlayPath],
        (p) => exportEditedVideo(
          inputPath: p[0],
          start: start,
          end: end,
          trim: trim,
          mute: mute,
          gif: gif,
          overlayPath: overlayPath == null ? null : p[1],
          useCache: false,
        ),
        extension: gif ? 'gif' : 'mp4',
      );

    if (trim && !gif && overlayPath == null) {
      final media3 = await _tryMedia3SimpleTrim(
        inputPath: inputPath,
        start: start,
        end: end,
        mute: mute,
      );
      if (media3 != null) return media3;
    }

    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String outPath =
          '${tempDir.path}/TitiStar_Edit_${_serial()}.${gif ? 'gif' : 'mp4'}';

      final String ss = (start.inMilliseconds / 1000).toStringAsFixed(3);
      final String t = ((end - start).inMilliseconds / 1000).toStringAsFixed(3);
      final String trimArgs = trim ? '-ss $ss -t $t ' : '';

      String cmd;
      if (overlayPath != null) {
        // رسم/نص/إيموجي: نثبّت طبقة PNG شفافة فوق الفيديو (إعادة ترميز)
        if (gif) {
          cmd =
              '$trimArgs-i "$inputPath" -i "$overlayPath" -filter_complex '
              '"[0:v][1:v]overlay=0:0,fps=12,scale=360:-2:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" '
              '-loop 0 -y "$outPath"';
        } else {
          final String ovAudio = mute ? '-an' : '-c:a aac -b:a 128k';
          cmd =
              '$trimArgs-i "$inputPath" -i "$overlayPath" -filter_complex '
              '"[0:v][1:v]overlay=0:0,scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p[v]" '
              '-map "[v]" -map 0:a? $ovAudio -c:v libx264 -preset veryfast -crf 20 -movflags +faststart -y "$outPath"';
        }
      } else if (!trim && !gif && mute) {
        // كتم فقط: نحذف الصوت بدون إعادة ترميز الفيديو (سريع وبدون خسارة جودة)
        cmd =
            '-i "$inputPath" -c:v copy -an -movflags +faststart -y "$outPath"';
      } else if (gif) {
        cmd =
            '$trimArgs-i "$inputPath" '
            '-vf "fps=12,scale=360:-2:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" '
            '-loop 0 -y "$outPath"';
      } else {
        final String audio = mute ? '-an' : '-c:a aac -b:a 128k';
        cmd =
            '$trimArgs-i "$inputPath" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p '
            '$audio -movflags +faststart -y "$outPath"';
      }

      final session = await FFmpegKit.execute(cmd);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        return outPath;
      }
      final logs = await session.getAllLogsAsString();
      print("Tini Export Error Logs: $logs");
      return null;
    } catch (e) {
      print("Tini Export Exception: $e");
      return null;
    }
  }

  static Future<String> trimVideo({
    required String inputPath,
    required Duration start,
    required Duration end,
    bool useCache = true,
  }) async {
    if (useCache) {
      final result = await _cachedMedia(
        'trim.v1',
        {'start': start.inMicroseconds, 'end': end.inMicroseconds},
        [inputPath],
        (p) =>
            trimVideo(inputPath: p[0], start: start, end: end, useCache: false),
      );
      if (result == null) throw StateError('Trim did not produce media');
      return result;
    }

    final Directory tempDir = await getTemporaryDirectory();
    final String outPath = '${tempDir.path}/TitiStar_Trim_${_serial()}.mp4';

    final String startStr = _formatDuration(start);
    final String durationStr = _formatDuration(end - start);

    // -ss قبل -i للسرعة، -c copy عشان ما نعيد الترميز
    final String cmd =
        '-ss $startStr -i "$inputPath" -t $durationStr -c copy -avoid_negative_ts make_zero "$outPath"';

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return outPath;
    } else {
      final logs = await session.getAllLogsAsString();
      throw Exception('فشل قص الفيديو: $logs');
    }
  }

  // [شات الخاص والجروبات] - ضغط فويس وفيديو

  static Future<File> compressChatVideo(String path) async {
    final Directory tempDir = await getTemporaryDirectory();
    final String outPath = '${tempDir.path}/chat_vid_${_serial()}.mp4';
    // Medium quality للشات - نفس فكرة الـ trim تبعك
    // جودة عالية الدقة (اختيار المستخدم من شاشة المعاينة): دقة 1080 وجودة أعلى
    final bool hd = MediaQuality.isHd(path);
    final String cmd = hd
        ? '-i "$path" -vf "scale=1080:-2" -c:v libx264 -preset veryfast -crf 22 -c:a aac -b:a 128k -movflags +faststart -y "$outPath"'
        : '-i "$path" -vf "scale=720:-2" -c:v libx264 -preset ultrafast -crf 28 -c:a aac -b:a 64k -movflags +faststart -y "$outPath"';
    final session = await FFmpegKit.execute(cmd);
    if (ReturnCode.isSuccess(await session.getReturnCode())) {
      return File(outPath);
    }
    return File(path);
  }

  static Future<File> compressChatVoice(File file) async {
    final Directory tempDir = await getTemporaryDirectory();
    final String outPath = '${tempDir.path}/chat_voice_${_serial()}.m4a';
    // من 128k لـ 32k للفويس - توفير 75%
    final String cmd = '-i "${file.path}" -b:a 32k -y "$outPath"';
    final session = await FFmpegKit.execute(cmd);
    if (ReturnCode.isSuccess(await session.getReturnCode())) {
      return File(outPath);
    }
    return file;
  }

  static String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    final ms = (d.inMilliseconds.remainder(1000) / 10).floor();
    return '$hours:$minutes:$seconds.${twoDigits(ms)}';
  }
}
