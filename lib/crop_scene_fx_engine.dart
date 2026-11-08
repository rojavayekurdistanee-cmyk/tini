import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'crop_effects_model.dart';
import 'tini_edit_cache.dart';

/// Shared primitives for pre-rendered scene effects.
/// This engine does not control playback, composition, or export timing.
class TiniSceneFxEngine {
  const TiniSceneFxEngine._();

  /// Extract a bundled scene into the temporary directory when needed.
  static Future<String> sceneFile({
    required String asset,
    required String cacheFilename,
    int minimumBytes = 100000,
  }) async {
    final cache = await getTemporaryDirectory();
    final output = File('${cache.path}/$cacheFilename');
    if (await output.exists() && await output.length() > minimumBytes) {
      return output.path;
    }
    final raw = await rootBundle.load(asset);
    await output.writeAsBytes(
      raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      flush: true,
    );
    return output.path;
  }

  /// Calls the native face detector and normalizes its result.
  /// Null is returned when no suitable face is reported.
  static Future<TiniSceneFace?> detectFace({
    required String path,
    required int milliseconds,
    required String channel,
    String method = 'detect',
  }) async {
    if (!Platform.isAndroid || path.isEmpty) return null;
    final uri = Uri.tryParse(path);
    final filePath = uri?.scheme == 'file' ? uri!.toFilePath() : path;
    final data = await MethodChannel(channel).invokeMapMethod<String, dynamic>(
      method,
      {'path': filePath, 'timeMs': milliseconds.clamp(0, 2147483647)},
    );
    if (data == null) return null;
    return TiniSceneFace.fromNative(data);
  }
}

class TiniSceneFace {
  final double cx, cy, width, height;
  // Landmark sampling applies ONLY to face scenes; sled's native 'detect'
  // response and positioning are not modified.
  final double roll, yaw, pitch;
  final double? noseX, noseY;
  final double? leftEyeX, leftEyeY, rightEyeX, rightEyeY;
  final double? leftEarX, leftEarY, rightEarX, rightEarY;
  final double? mouthX, mouthY;

  const TiniSceneFace(
    this.cx,
    this.cy,
    this.width,
    this.height, {
    this.roll = 0,
    this.yaw = 0,
    this.pitch = 0,
    this.noseX,
    this.noseY,
    this.leftEyeX,
    this.leftEyeY,
    this.rightEyeX,
    this.rightEyeY,
    this.leftEarX,
    this.leftEarY,
    this.rightEarX,
    this.rightEarY,
    this.mouthX,
    this.mouthY,
  });

  static TiniSceneFace? fromNative(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    double? n(String key) => (map[key] as num?)?.toDouble();
    double? point(String key) => n(key)?.clamp(0.0, 1.0).toDouble();
    final cx = n('cx'), cy = n('cy');
    final width = n('width'), height = n('height');
    if (cx == null ||
        cy == null ||
        width == null ||
        height == null ||
        !cx.isFinite ||
        !cy.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        width < .015 ||
        height < .015)
      return null;
    return TiniSceneFace(
      cx.clamp(0.0, 1.0).toDouble(),
      cy.clamp(0.0, 1.0).toDouble(),
      width.clamp(.02, 1.0).toDouble(),
      height.clamp(.02, 1.0).toDouble(),
      roll: (n('roll') ?? 0).clamp(-70.0, 70.0).toDouble(),
      yaw: (n('yaw') ?? 0).clamp(-70.0, 70.0).toDouble(),
      pitch: (n('pitch') ?? 0).clamp(-60.0, 60.0).toDouble(),
      noseX: point('nx'),
      noseY: point('ny'),
      leftEyeX: point('lex'),
      leftEyeY: point('ley'),
      rightEyeX: point('rex'),
      rightEyeY: point('rey'),
      leftEarX: point('lax'),
      leftEarY: point('lay'),
      rightEarX: point('rax'),
      rightEarY: point('ray'),
      mouthX: point('mx'),
      mouthY: point('my'),
    );
  }

  static TiniSceneFace interpolate(TiniSceneFace a, TiniSceneFace b, double t) {
    final p = t.clamp(0.0, 1.0).toDouble();
    double mix(double x, double y) => x + (y - x) * p;
    double? optional(double? x, double? y) {
      if (x != null && y != null) return mix(x, y);
      return x ?? y;
    }

    return TiniSceneFace(
      mix(a.cx, b.cx),
      mix(a.cy, b.cy),
      mix(a.width, b.width),
      mix(a.height, b.height),
      roll: mix(a.roll, b.roll),
      yaw: mix(a.yaw, b.yaw),
      pitch: mix(a.pitch, b.pitch),
      noseX: optional(a.noseX, b.noseX),
      noseY: optional(a.noseY, b.noseY),
      leftEyeX: optional(a.leftEyeX, b.leftEyeX),
      leftEyeY: optional(a.leftEyeY, b.leftEyeY),
      rightEyeX: optional(a.rightEyeX, b.rightEyeX),
      rightEyeY: optional(a.rightEyeY, b.rightEyeY),
      leftEarX: optional(a.leftEarX, b.leftEarX),
      leftEarY: optional(a.leftEarY, b.leftEarY),
      rightEarX: optional(a.rightEarX, b.rightEarX),
      rightEarY: optional(a.rightEarY, b.rightEarY),
      mouthX: optional(a.mouthX, b.mouthX),
      mouthY: optional(a.mouthY, b.mouthY),
    );
  }

  bool get hasEyes =>
      leftEyeX != null &&
      leftEyeY != null &&
      rightEyeX != null &&
      rightEyeY != null;

  (double, double) get eyeCentre => hasEyes
      ? ((leftEyeX! + rightEyeX!) / 2, (leftEyeY! + rightEyeY!) / 2)
      : (cx, cy - height * .13);

  double get eyeSpacing {
    if (!hasEyes) return width * .44;
    return math.sqrt(
      math.pow(rightEyeX! - leftEyeX!, 2) + math.pow(rightEyeY! - leftEyeY!, 2),
    );
  }

  /// The same dimensions are fed to both preview and FFmpeg. Compensating
  /// eye separation for yaw prevents the entire drawing from shrinking when
  /// one eye moves towards the other in the source video.
  double get dogWidth {
    if (!hasEyes) return width * 1.95;
    final cosYaw = math.cos(yaw * math.pi / 180).abs().clamp(.60, 1.0);
    final eyeBased = eyeSpacing / math.max(.65, cosYaw) / .44 * 1.95;
    return eyeBased.clamp(width * 1.55, width * 2.22).toDouble();
  }

  double get dogHeight => height * 1.33;

  /// Screen-space inclination uses the inter-eye vector, not a delayed
  /// bounding-box rotation. Euler-Z is a fallback if the eyes are occluded.
  double get dogRoll {
    if (!hasEyes || (rightEyeX! - leftEyeX!).abs() < .012) {
      return -roll;
    }
    final dx = rightEyeX! - leftEyeX!;
    final dy = rightEyeY! - leftEyeY!;
    return (math.atan2(dx > 0 ? dy : -dy, dx.abs()) * 180 / math.pi)
        .clamp(-65.0, 65.0)
        .toDouble();
  }

  double get dogNoseX => noseX ?? eyeCentre.$1;
  double get dogNoseY => noseY ?? cy + height * .07;

  /// The ears AND flower are connected in the scene movie. Keep them rigid
  /// instead of separating the two ears and cutting the bridge between them.
  (double, double) get dogHeadCentre {
    final eye = eyeCentre;
    final rad = dogRoll * math.pi / 180;
    final lift = height * .19;
    return (eye.$1 + math.sin(rad) * lift, eye.$2 - math.cos(rad) * lift);
  }

  (double, double) get dogSnoutCentre => (dogNoseX, dogNoseY);

  /// A modest horizontal foreshortening on turns is possible with 2D artwork.
  /// This does not pretend that a flat MP4 supplies a genuine 3D dog mesh.
  double dogSquash(_TiniDogRegion region) {
    final amount = (1 - math.cos(yaw.abs() * math.pi / 180))
        .clamp(0.0, 0.70)
        .toDouble();
    return 1 - amount * (region == _TiniDogRegion.head ? .72 : .45);
  }
}

/// Scene-backed face accessories reuse the existing shared scene engine.
/// Bobsledder still uses its own unmodified 'detect' method and scene.
class TiniFaceSceneFx {
  const TiniFaceSceneFx._();

  static const category = 'مؤثر شكل الوجه';
  static const dogName = '2014 Dog Ch...';
  static const _asset = 'assets/tini_dog_champion_scene.mp4';
  static const _channel = 'titi_star/sled_face';

  static bool hasDog(List<TiniAppliedEffect> effects) => effects.any(
    (e) => e.descriptor?.category == category && e.descriptor?.name == dogName,
  );

  static Future<TiniSceneFace?> face(String path, int timeMs) =>
      TiniSceneFxEngine.detectFace(
        path: path,
        milliseconds: timeMs,
        channel: _channel,
        method: 'detectPose',
      );

  /// Batched decoding preserves timestamps and avoids a queue of slow,
  /// obsolete individual detector calls while the user plays/scrubs a clip.
  static Future<Map<int, TiniSceneFace>> sampleFaces(
    String path,
    List<int> timesMs,
  ) async {
    if (!Platform.isAndroid || path.isEmpty || timesMs.isEmpty) return {};
    final uri = Uri.tryParse(path);
    final filePath = uri?.scheme == 'file' ? uri!.toFilePath() : path;
    final response = await const MethodChannel(_channel)
        .invokeMethod<List<dynamic>>('detectPoseBatch', {
          'path': filePath,
          'timesMs': timesMs,
        });
    final output = <int, TiniSceneFace>{};
    if (response == null) return output;
    for (final item in response) {
      if (item is! Map) continue;
      final time = (item['timeMs'] as num?)?.toInt();
      final pose = TiniSceneFace.fromNative(item);
      if (time != null && pose != null) output[time] = pose;
    }
    return output;
  }

  static Future<String> dogSceneFile() => TiniSceneFxEngine.sceneFile(
    asset: _asset,
    cacheFilename: 'tini_dog_champion_scene_v3.mp4',
    minimumBytes: 25000,
  );

  // H.264 carries no alpha in the Android video decoder. This matrix keys
  // the blue backing in preview; export uses FFmpeg's colorkey below.
  static const ColorFilter previewKey = ColorFilter.matrix(<double>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    3.0,
    3.0,
    -2.0,
    0,
    -10,
  ]);
}

// Two connected atlas regions; these rectangles are taken from the *existing*
// 512x512 movie, which remains untouched in assets/. Crops are intentionally
// non-overlapping to avoid duplicated outlines/visible seams.
enum _TiniDogRegion {
  head(76, 70, 360, 172),
  snout(171, 246, 170, 103);

  const _TiniDogRegion(this.x, this.y, this.w, this.h);
  final int x, y, w, h;

  (double, double) anchor(TiniSceneFace face) =>
      this == _TiniDogRegion.head ? face.dogHeadCentre : face.dogSnoutCentre;
}

/// Draw the same two atlas crops as the offline export, centred on their
/// facial anchors. No separate dart class or separate asset per ear is added.
class TiniFaceScenePreview extends StatefulWidget {
  final VideoPlayerController sourceController;
  final String sourcePath;
  final int sourceTimeMs;
  final double effectSeconds;
  final Widget original;

  const TiniFaceScenePreview({
    super.key,
    required this.sourceController,
    required this.sourcePath,
    required this.sourceTimeMs,
    required this.effectSeconds,
    required this.original,
  });

  @override
  State<TiniFaceScenePreview> createState() => _TiniFaceScenePreviewState();
}

class _TiniFaceScenePreviewState extends State<TiniFaceScenePreview> {
  VideoPlayerController? _plate;
  final SplayTreeMap<int, TiniSceneFace> _faces = SplayTreeMap();
  final Set<int> _attempted = <int>{};
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _open();
    _scheduleSamples();
  }

  Future<void> _open() async {
    final player = VideoPlayerController.asset(
      TiniFaceSceneFx._asset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _plate = player;
    try {
      await player.initialize();
      if (!mounted || !identical(_plate, player)) {
        await player.dispose();
        return;
      }
      await player.setLooping(true);
      await player.setVolume(0);
      if (widget.sourceController.value.isPlaying) await player.play();
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('[Tini Face Scene] Cannot open dog asset: $error');
      if (mounted) setState(() => _plate = null);
      await player.dispose();
    }
  }

  @override
  void didUpdateWidget(covariant TiniFaceScenePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourcePath != widget.sourcePath) {
      ++_generation;
      _faces.clear();
      _attempted.clear();
    }
    _scheduleSamples();
    final plate = _plate;
    if (plate == null || !plate.value.isInitialized) return;
    final speed = widget.sourceController.value.playbackSpeed;
    if (speed > 0 && (speed - plate.value.playbackSpeed).abs() > .01) {
      plate.setPlaybackSpeed(speed);
    }
    final length = plate.value.duration.inMilliseconds;
    if (length > 0) {
      final want = (widget.effectSeconds * 1000).round() % length;
      final current = plate.value.position.inMilliseconds;
      final drift = (want - current).abs();
      // Continuous sub-second seeks force the platform decoder to restart.
      // Correct larger drift while playing, but allow precise paused seeks.
      final threshold = widget.sourceController.value.isPlaying ? 850 : 280;
      if (drift > threshold && drift < length - threshold) {
        plate.seekTo(Duration(milliseconds: want));
      }
    }
    if (widget.sourceController.value.isPlaying && !plate.value.isPlaying) {
      plate.play();
    } else if (!widget.sourceController.value.isPlaying &&
        plate.value.isPlaying) {
      plate.pause();
    }
  }

  void _scheduleSamples() {
    if (_busy || widget.sourcePath.isEmpty) return;
    final current = widget.sourceTimeMs.clamp(0, 2147483647).toInt();
    final duration = widget.sourceController.value.duration.inMilliseconds;
    // Sample only the visible neighborhood. Pre-decoding one second ahead
    // kept the native ML worker busy continuously and heated the device.
    // Preserve 120 ms landmark accuracy and interpolate between samples.
    const sampleMs = 120;
    final origin = current ~/ sampleMs * sampleMs;
    final playing = widget.sourceController.value.isPlaying;
    final candidates = playing
        ? <int>[origin, origin + sampleMs]
        : <int>[origin];
    final next = candidates
        .where(
          (t) =>
              t >= 0 &&
              (duration <= 0 || t <= duration) &&
              !_attempted.contains(t),
        )
        .toList();
    if (next.isEmpty) return;
    _attempted.addAll(next);
    _busy = true;
    final generation = _generation;
    final path = widget.sourcePath;
    _fetchSamples(path, next, generation);
  }

  Future<void> _fetchSamples(
    String path,
    List<int> times,
    int generation,
  ) async {
    try {
      final detected = await TiniFaceSceneFx.sampleFaces(path, times);
      if (!mounted || generation != _generation) return;
      setState(() {
        _faces.addAll(detected);
        // Keep only a short rolling window for scrubbing and interpolation.
        // An arbitrarily long editing session must not grow these maps.
        final current = widget.sourceTimeMs;
        _faces.removeWhere((ms, _) => (ms - current).abs() > 2400);
        _attempted.removeWhere((ms) => (ms - current).abs() > 2400);
      });
    } catch (error) {
      debugPrint('[Tini Face Scene] Pose sampling: $error');
    } finally {
      if (mounted && generation == _generation) {
        _busy = false;
        // Let normal playback position updates request the next sample.
        // Immediately recursing here fills the whole movie even while the
        // user is waiting at a different position or has left the panel.
      } else {
        _busy = false;
      }
    }
  }

  TiniSceneFace? _faceAt(int milliseconds) {
    if (_faces.isEmpty) return null;
    final exact = _faces[milliseconds];
    if (exact != null) return exact;
    final before = _faces.lastKeyBefore(milliseconds + 1);
    final after = _faces.firstKeyAfter(milliseconds - 1);
    if (before != null &&
        after != null &&
        before != after &&
        after - before <= 350) {
      return TiniSceneFace.interpolate(
        _faces[before]!,
        _faces[after]!,
        (milliseconds - before) / (after - before),
      );
    }
    if (before != null && milliseconds - before <= 150) {
      return _faces[before];
    }
    if (after != null && after - milliseconds <= 150) {
      return _faces[after];
    }
    return null;
  }

  @override
  void dispose() {
    ++_generation;
    _plate?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plate = _plate;
    final face = _faceAt(widget.sourceTimeMs);
    if (plate == null || !plate.value.isInitialized || face == null) {
      return widget.original;
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        final w = bounds.maxWidth, h = bounds.maxHeight;
        if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
          return widget.original;
        }
        Widget part(_TiniDogRegion region) {
          final anchor = region.anchor(face);
          final pw =
              w * face.dogWidth * region.w / 512 * face.dogSquash(region);
          final ph = h * face.dogHeight * region.h / 512;
          if (pw <= 0 || ph <= 0) return const SizedBox.shrink();
          final atlasW = pw * 512 / region.w;
          final atlasH = ph * 512 / region.h;
          return Positioned(
            left: w * anchor.$1 - pw / 2,
            top: h * anchor.$2 - ph / 2,
            width: pw,
            height: ph,
            child: Transform.rotate(
              angle: face.dogRoll * math.pi / 180,
              alignment: Alignment.center,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: -region.x / 512 * atlasW,
                      top: -region.y / 512 * atlasH,
                      width: atlasW,
                      height: atlasH,
                      child: ColorFiltered(
                        colorFilter: TiniFaceSceneFx.previewKey,
                        child: VideoPlayer(plate),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            widget.original,
            IgnorePointer(
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    part(_TiniDogRegion.head),
                    part(_TiniDogRegion.snout),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Offline composition samples the exact speed-adjusted output clip, not a
/// stale time position in an untrimmed original source. Per-frame dimensions,
/// rotation, and centres are calculated from the same TiniSceneFace methods
/// used in the live preview.
class TiniFaceSceneExport {
  const TiniFaceSceneExport._();

  static Future<String> composeDog({
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
    for (final effect in effects) {
      if (cancelled?.call() == true) throw TiniEditCancelled();
      if (effect.descriptor?.category != TiniFaceSceneFx.category ||
          effect.descriptor?.name != TiniFaceSceneFx.dogName)
        continue;
      final start = effect.startSeconds.clamp(0.0, seconds).toDouble();
      final end = effect.endSeconds.clamp(0.0, seconds).toDouble();
      if (end - start < .08) continue;
      final duration = end - start;
      final samples = <(double, TiniSceneFace)>[];
      // 120 ms pose keyframes retain smooth interpolation without decoding
      // redundant near-identical frames during CPU-heavy offline export.
      final spacing = math.max(.12, duration / 100);
      final times = <int>[];
      for (double t = start; t <= end + .001; t += spacing) {
        times.add((t.clamp(start, end) * 1000).round());
      }
      for (var i = 0; i < times.length; i += 12) {
        if (cancelled?.call() == true) throw TiniEditCancelled();
        final section = times.skip(i).take(12).toList();
        final found = await TiniFaceSceneFx.sampleFaces(
          analysisInputPath ?? ready,
          section,
        );
        for (final ms in section) {
          final face = found[ms];
          if (face != null) samples.add((ms / 1000, face));
        }
      }
      if (samples.isEmpty) {
        throw StateError(
          '2014 Dog Ch...: no detectable face in effect interval',
        );
      }

      /// Return an expression in absolute *source clip* time. The source
      /// scene's local time is shifted only when evaluating scale/rotation.
      String expression(
        double Function(TiniSceneFace) value, {
        bool sceneLocal = false,
      }) {
        // Balanced tree: a linear chain of >70 nested if() operations can
        // exceed FFmpeg's expression parser recursion limit on some builds.
        String segment(int lo, int hi) {
          if (lo == hi) {
            final a = samples[lo], b = samples[lo + 1];
            final from = value(a.$2), to = value(b.$2);
            final interval = math.max(.0001, b.$1 - a.$1);
            return '${from.toStringAsFixed(8)}+'
                '(${(to - from).toStringAsFixed(8)})*'
                '(t-${a.$1.toStringAsFixed(5)})/${interval.toStringAsFixed(5)}';
          }
          final mid = (lo + hi) ~/ 2;
          return 'if(lt(t,${samples[mid + 1].$1.toStringAsFixed(5)}),'
              '${segment(lo, mid)},${segment(mid + 1, hi)})';
        }

        String result;
        if (samples.length == 1) {
          result = value(samples.first.$2).toStringAsFixed(8);
        } else {
          result = segment(0, samples.length - 2);
          result =
              'if(lt(t,${samples.first.$1.toStringAsFixed(5)}),'
              '${value(samples.first.$2).toStringAsFixed(8)},'
              'if(gt(t,${samples.last.$1.toStringAsFixed(5)}),'
              '${value(samples.last.$2).toStringAsFixed(8)},$result))';
        }
        if (sceneLocal) {
          final startStr = start.toStringAsFixed(6);
          result = result.replaceAll(
            RegExp(r'(?<![a-zA-Z])t(?![a-zA-Z])'),
            '(t+$startStr)',
          );
        }
        return result.replaceAll(',', r'\,');
      }

      final scene = await TiniFaceSceneFx.dogSceneFile();
      final startStr = start.toStringAsFixed(6);
      final durationStr = duration.toStringAsFixed(6);

      String piece(_TiniDogRegion region, String input, String output) {
        final widthFactor = expression(
          (f) => width / 512 * f.dogWidth * f.dogSquash(region),
          sceneLocal: true,
        );
        final heightFactor = expression(
          (f) => height / 512 * f.dogHeight,
          sceneLocal: true,
        );
        final rotation = expression(
          (f) => f.dogRoll * math.pi / 180,
          sceneLocal: true,
        );
        return '$input'
            'crop=${region.w}:${region.h}:${region.x}:${region.y},'
            'format=rgba,colorkey=0x0000ff:0.18:0.09,'
            'scale=w=iw*($widthFactor):h=ih*($heightFactor):eval=frame,'
            'rotate=angle=$rotation:'
            'ow=hypot(iw\\,ih):oh=hypot(iw\\,ih):fillcolor=none,'
            'setpts=PTS+$startStr/TB$output';
      }

      String overlay(
        _TiniDogRegion region,
        String base,
        String crop,
        String destination,
      ) {
        final ax = expression((f) => region.anchor(f).$1);
        final ay = expression((f) => region.anchor(f).$2);
        return '$base$crop'
            'overlay=x=main_w*($ax)-overlay_w/2:'
            'y=main_h*($ay)-overlay_h/2:'
            'eof_action=pass:repeatlast=0:shortest=0:format=auto$destination';
      }

      final graph =
          '[1:v]trim=duration=$durationStr,setpts=PTS-STARTPTS,'
          'split=2[dogHeadIn][dogNoseIn];'
          '${piece(_TiniDogRegion.head, '[dogHeadIn]', '[dogHead]')};'
          '${piece(_TiniDogRegion.snout, '[dogNoseIn]', '[dogNose]')};'
          '${overlay(_TiniDogRegion.head, '[0:v]', '[dogHead]', '[tmpDog]')};'
          '${overlay(_TiniDogRegion.snout, '[tmpDog]', '[dogNose]', '[tmpOutput]')};'
          '[tmpOutput]format=${lossless ? 'bgra' : 'yuv420p'}[vout]';
      final cache = await getTemporaryDirectory();
      final output =
          '${cache.path}/tini_face_scene_export_'
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
          '2014 Dog Ch... export failed: '
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
