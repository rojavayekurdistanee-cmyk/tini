import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'crop_effects_model.dart';
import 'tini_edit_cache.dart';
import 'crop_scene_fx_engine.dart';

/// Tini's original, forward-moving CGI bobsled. The 3D track is pre-rendered;
/// no VTK, Blender, FFmpeg, or repeated frame extraction runs during playback.
/// Only the rider's face is composited onto the opening in the helmet.
class TiniSledEffect {
  static const category = 'مؤثر شكل الوجه';
  static const name = 'Bobsledder';
  static const asset = 'assets/tini_sled_scene_forward.mp4';
  static bool hasEffect(List<TiniAppliedEffect> effects) => effects.any(
    (e) => e.descriptor?.category == category && e.descriptor?.name == name,
  );

  static Future<TiniSledFace?> detect(String path, int milliseconds) async {
    final face = await TiniSceneFxEngine.detectFace(
      path: path,
      milliseconds: milliseconds,
      channel: 'titi_star/sled_face',
    );
    if (face == null) return null;
    return TiniSledFace(face.cx, face.cy, face.width, face.height);
  }

  static Future<String> sceneFile() => TiniSceneFxEngine.sceneFile(
    asset: asset,
    cacheFilename: 'tini_sled_scene_forward_v1.mp4',
  );
}

class TiniSledFace {
  final double cx, cy, width, height;
  const TiniSledFace(this.cx, this.cy, this.width, this.height);
}

/// Reuses the parent video player's decoded texture; the scene is a separate,
/// 480x854 H264 video. Face detection happens at most once every 900ms, on a
/// native worker; scene playback never waits for a detector or a frame export.
class TiniSledPreview extends StatefulWidget {
  final VideoPlayerController sourceController;
  final String sourcePath;
  final int sourceTimeMs;
  final double effectSeconds;
  final Widget original;

  const TiniSledPreview({
    super.key,
    required this.sourceController,
    required this.sourcePath,
    required this.sourceTimeMs,
    required this.effectSeconds,
    required this.original,
  });

  @override
  State<TiniSledPreview> createState() => _TiniSledPreviewState();
}

class _TiniSledPreviewState extends State<TiniSledPreview> {
  VideoPlayerController? _scene;
  TiniSledFace? _face;
  bool _busy = false;
  int _lastSample = -100000;
  int _generation = 0;
  bool _sceneFailed = false;

  @override
  void initState() {
    super.initState();
    _openScene();
    _scheduleDetection();
  }

  Future<void> _openScene() async {
    final player = VideoPlayerController.asset(
      TiniSledEffect.asset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _scene = player;
    try {
      await player.initialize();
      if (!mounted || !identical(player, _scene)) {
        await player.dispose();
        return;
      }
      await player.setLooping(true);
      await player.setVolume(0);
      // Do not decode the second movie while the source is paused.
      if (widget.sourceController.value.isPlaying) await player.play();
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('[Tini Sled] Failed to open CGI asset: $error');
      if (mounted) setState(() => _sceneFailed = true);
      if (identical(player, _scene)) _scene = null;
      await player.dispose();
    }
  }

  @override
  void didUpdateWidget(covariant TiniSledPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sourcePath != oldWidget.sourcePath) {
      ++_generation;
      _face = null;
      _lastSample = -100000;
    }
    _scheduleDetection();
    final scene = _scene;
    if (scene != null && scene.value.isInitialized) {
      final sourceSpeed = widget.sourceController.value.playbackSpeed;
      if ((scene.value.playbackSpeed - sourceSpeed).abs() > .01 &&
          sourceSpeed > 0) {
        scene.setPlaybackSpeed(sourceSpeed);
      }
      final durationMs = scene.value.duration.inMilliseconds;
      if (durationMs > 0) {
        final wanted = (widget.effectSeconds * 1000).round() % durationMs;
        final current = scene.value.position.inMilliseconds;
        final drift = (wanted - current).abs();
        // Small timestamp differences are normal between two decoders.
        // Seeking on each rebuild needlessly wakes the hardware decoder.
        final threshold = widget.sourceController.value.isPlaying ? 1100 : 350;
        if (drift > threshold && drift < durationMs - threshold) {
          scene.seekTo(Duration(milliseconds: wanted));
        }
        if (!scene.value.isPlaying && widget.sourceController.value.isPlaying) {
          scene.play();
        } else if (scene.value.isPlaying &&
            !widget.sourceController.value.isPlaying) {
          scene.pause();
        }
      }
    }
  }

  Future<void> _scheduleDetection() async {
    if (_busy ||
        widget.sourcePath.isEmpty ||
        (widget.sourceTimeMs - _lastSample).abs() < 900)
      return;
    _busy = true;
    _lastSample = widget.sourceTimeMs;
    final generation = _generation;
    try {
      final result = await TiniSledEffect.detect(
        widget.sourcePath,
        widget.sourceTimeMs,
      );
      if (mounted && generation == _generation && result != null) {
        setState(() => _face = result);
      }
    } catch (error) {
      debugPrint('[Tini Sled] Face detection: $error');
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _scene?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    if (_sceneFailed || scene == null || !scene.value.isInitialized) {
      return widget.original;
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = bounds.maxWidth, height = bounds.maxHeight;
        if (width <= 0 || height <= 0) return widget.original;
        // Design coordinates in the pre-rendered 480x854 plate. Never place the
        // user video over the helmet shell, cheeks, or the sled's front bonnet.
        final faceLeft = width * .403;
        final faceTop = height * .396;
        final faceWidth = width * .194;
        final faceHeight = height * .121;
        final face = _face;
        Widget? liveFace;
        final ratio = widget.sourceController.value.aspectRatio;
        if (face != null &&
            ratio > 0 &&
            math.min(face.width, face.height) > .02) {
          // Render the existing video texture inside the face opening, cropping
          // to the ML Kit bounding rectangle. No second decoder of source footage.
          final fullW = faceWidth / (face.width * .70);
          final fullH = fullW / ratio;
          final offX = faceWidth * .5 - fullW * face.cx;
          final offY = faceHeight * .5 - fullH * face.cy;
          liveFace = Positioned(
            left: faceLeft,
            top: faceTop,
            width: faceWidth,
            height: faceHeight,
            child: ClipOval(
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: offX,
                      top: offY,
                      width: fullW,
                      height: fullH,
                      child: VideoPlayer(widget.sourceController),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return IgnorePointer(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      width: 480,
                      height: 854,
                      child: VideoPlayer(scene),
                    ),
                  ),
                ),
                if (liveFace != null) liveFace,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Offline export. The scene is looped only in the selected effect interval.
/// Sampled native ML Kit boxes are used to crop the *processed output video*,
/// retaining the exact clip's trims, speed curve, other effects, and audio.
class TiniSledExport {
  static Future<String> compose({
    required String inputPath,
    required List<TiniAppliedEffect> effects,
    required int width,
    required int height,
    required double seconds,
    bool lossless = false,
    String? analysisInputPath,
    bool Function()? cancelled,
  }) async {
    var ready = inputPath;
    final scene = await TiniSledEffect.sceneFile();
    for (final effect in effects) {
      if (cancelled?.call() == true) throw TiniEditCancelled();
      if (effect.descriptor?.category != TiniSledEffect.category ||
          effect.descriptor?.name != TiniSledEffect.name)
        continue;
      final start = effect.startSeconds.clamp(0.0, seconds).toDouble();
      final end = effect.endSeconds.clamp(0.0, seconds).toDouble();
      if (end - start < .08) continue;
      // A small bounded set of samples suffices for a ~2s effect. Samples are
      // acquired on demand during export, never continuously during preview.
      final duration = end - start;
      final samples = <(double, TiniSledFace)>[];
      final sampleStep = math.max(1.0, duration / 18.0);
      for (var t = start + .12; t < end; t += sampleStep) {
        if (cancelled?.call() == true) throw TiniEditCancelled();
        final face = await TiniSledEffect.detect(
          analysisInputPath ?? ready,
          (t * 1000).round(),
        );
        if (face != null) samples.add((t - start, face));
      }
      if (samples.isEmpty) {
        throw StateError(
          'Bobsledder: no detectable face in the selected video interval',
        );
      }
      final median = samples[samples.length ~/ 2].$2;
      final cropW = ((median.width * width * .70).round()).clamp(32, width);
      final cropH = ((median.height * height * 1.00).round()).clamp(32, height);
      final eyeX = (width * .403).round();
      final eyeY = (height * .396).round();
      final eyeW = math.max(2, (width * .194).round() ~/ 2 * 2);
      final eyeH = math.max(2, (height * .121).round() ~/ 2 * 2);
      String motion(bool horizontal) {
        // A smooth piecewise linear path, bounded by video dimensions.
        String expr = horizontal
            ? samples.last.$2.cx.toStringAsFixed(6)
            : samples.last.$2.cy.toStringAsFixed(6);
        for (var i = samples.length - 2; i >= 0; i--) {
          final a = samples[i], b = samples[i + 1];
          final v0 = horizontal ? a.$2.cx : a.$2.cy;
          final v1 = horizontal ? b.$2.cx : b.$2.cy;
          final span = (b.$1 - a.$1).clamp(.001, 9999.0);
          final lerp =
              '${v0.toStringAsFixed(6)}+'
              '(${(v1 - v0).toStringAsFixed(6)})*'
              '(t-${a.$1.toStringAsFixed(3)})/$span';
          expr = 'if(lt(t,${b.$1.toStringAsFixed(3)}),$lerp,$expr)';
        }
        final dim = horizontal ? width : height;
        final crop = horizontal ? cropW : cropH;
        return 'max(0,min(${dim - crop},$dim*($expr)-${crop / 2}))';
      }

      final x = motion(true).replaceAll(',', r'\,');
      final y = motion(false).replaceAll(',', r'\,');
      final timeline = '${start.toStringAsFixed(5)}';
      final clipEnd = '${end.toStringAsFixed(5)}';
      final clipLength = '${duration.toStringAsFixed(5)}';
      // Sled plate is already a 3D video without a synthetic face. Overlay a
      // real cropped face, with an elliptical alpha opening, then composite
      // that finished plate only during the recorded effect interval.
      final mask =
          "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':"
          "a='if(lte(pow((X-W/2)/(W*0.49),2)+pow((Y-H/2)/(H*0.49),2),1),255,0)'";
      final graph =
          '[0:v]split=2[base][face_input];'
          '[face_input]trim=start=$timeline:end=$clipEnd,'
          'setpts=PTS-STARTPTS,crop=$cropW:$cropH:$x:$y,'
          'scale=$eyeW:$eyeH,format=rgba,$mask[face_window];'
          '[1:v]trim=duration=$clipLength,setpts=PTS-STARTPTS,'
          'scale=$width:$height,setsar=1,format=rgba[scene];'
          '[scene][face_window]overlay=x=$eyeX:y=$eyeY:'
          'shortest=1:format=auto,setpts=PTS+$timeline/TB[scene_ready];'
          '[base][scene_ready]overlay=x=0:y=0:eof_action=pass:'
          'repeatlast=0:shortest=0:format=auto,format=${lossless ? 'bgra' : 'yuv420p'}[vout]';
      final cache = await getTemporaryDirectory();
      final output =
          '${cache.path}/tini_sled_export_'
          '${DateTime.now().microsecondsSinceEpoch}.${lossless ? 'mkv' : 'mp4'}';
      final command =
          '-i "$ready" -stream_loop -1 -i "$scene" '
          '-filter_complex "$graph" -map "[vout]" -map 0:a? '
          '${lossless ? '-c:v ffv1 -level 3 -pix_fmt bgra' : '-c:v libx264 -preset veryfast -crf 21 -pix_fmt yuv420p'} '
          '-c:a copy ${lossless ? '' : '-movflags +faststart'} -y "$output"';
      if (cancelled?.call() == true) throw TiniEditCancelled();
      final session = await FFmpegKit.execute(command);
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        throw StateError(
          'Bobsledder export failed: '
          '${(await session.getAllLogsAsString()) ?? ''}',
        );
      }
      if (ready != inputPath) {
        try {
          await File(ready).delete();
        } catch (_) {}
      }
      ready = output;
    }
    return ready;
  }
}
