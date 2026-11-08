import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'crop_model.dart';
import 'crop_background_model.dart';
import 'tini_edit_cache.dart';
import 'tini_edit_directory_cache.dart';

/// Native person segmentation on Android. The work runs on an Android worker
/// thread. A cancellation request is forwarded rather than queuing new jobs.
class CropBackgroundEngine {
  static const MethodChannel _native = MethodChannel('titi_star/cutout');

  static Future<CutoutSettings> createMasks({
    required String videoPath,
    required Duration sourceStart,
    required Duration duration,
    bool edgeQuality = false,
  }) async {
    if (duration.inMilliseconds < 100) {
      throw StateError('لا يمكن قص خلفية مقطع أقصر من 0.1 ثانية');
    }
    final readable = await _readableMediaPath(videoPath, 'الفيديو');
    final saved = await TiniEditDirectoryCache.obtain(
      stage: 'cutout.analysis.v1',
      parameters: {
        'start': sourceStart.inMicroseconds,
        'duration': duration.inMicroseconds,
        'fps': edgeQuality ? 15 : 12,
        'size': edgeQuality ? 512 : 384,
      },
      sources: [readable],
      persistentExtraction: true,
      build: (inputs, stop) async {
        final temp = await getApplicationSupportDirectory();
        await temp.create(recursive: true);
        final directory = (await temp.createTemp('tini_mask_')).path;
        try {
          final response = await _native
              .invokeMapMethod<String, dynamic>('createMasks', {
                'path': inputs[0].path,
                'outputDir': directory,
                'startMs': sourceStart.inMilliseconds,
                'durationMs': duration.inMilliseconds,
                'fps': edgeQuality ? 15 : 12,
                'size': edgeQuality ? 512 : 384,
              });
          if (response == null || (response['count'] as int? ?? 0) < 1)
            throw StateError('فشل إنشاء قناع قص الخلفية');
          return TiniEditDirectoryResult(directory, {
            'count': response['count'],
            'fps': response['fps'],
          });
        } catch (_) {
          try {
            await Directory(directory).delete(recursive: true);
          } catch (_) {}
          rethrow;
        }
      },
    );
    return CutoutSettings(
      maskDirectory: saved.path,
      sourceStart: sourceStart,
      framesPerSecond: (saved.metadata['fps'] as num).toDouble(),
      frameCount: saved.metadata['count'] as int,
    );
  }

  static Future<void> cancel() async {
    try {
      await _native.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  /// A manual-only cutout uses an invisible uniform mask as its editing base.
  /// It never runs automatic segmentation: the image stays fully visible in
  /// the editor until the painted preview is processed. The base is hidden
  /// (brush first) or visible (eraser first), as requested by the first stroke.
  static Future<CutoutSettings> createManualMasks({
    required Duration sourceStart,
    required Duration duration,
    required double aspectRatio,
    required bool firstStrokeErases,
    bool useCache = true,
  }) async {
    if (duration.inMilliseconds < 100) {
      throw StateError('لا يمكن قص مقطع أقصر من 0.1 ثانية');
    }
    if (useCache) {
      final ratio = aspectRatio.isFinite && aspectRatio > 0
          ? aspectRatio
          : 9 / 16;
      final saved = await TiniEditDirectoryCache.obtain(
        stage: 'cutout.manual.v1',
        parameters: {
          'duration': duration.inMicroseconds,
          'ratio': ratio,
          'eraseFirst': firstStrokeErases,
        },
        sources: [],
        persistentExtraction: true,
        build: (inputs, stop) async {
          final masks = await createManualMasks(
            sourceStart: sourceStart,
            duration: duration,
            aspectRatio: aspectRatio,
            firstStrokeErases: firstStrokeErases,
            useCache: false,
          );
          return TiniEditDirectoryResult(masks.maskDirectory, {
            'fps': masks.framesPerSecond,
            'count': masks.frameCount,
          });
        },
      );
      return CutoutSettings(
        maskDirectory: saved.path,
        sourceStart: sourceStart,
        framesPerSecond: (saved.metadata['fps'] as num).toDouble(),
        frameCount: saved.metadata['count'] as int,
        manualMask: true,
      );
    }
    final temp = await getApplicationSupportDirectory();
    final dir = Directory(
      '${temp.path}/tini_mask_manual_${DateTime.now().microsecondsSinceEpoch}',
    );
    final ratio = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio
        : 9 / 16;
    const longest = 384;
    const fps = 12.0;
    final width = ratio >= 1 ? longest : math.max(1, (longest * ratio).round());
    final height = ratio >= 1
        ? math.max(1, (longest / ratio).round())
        : longest;
    final frameCount = math.max(
      1,
      (duration.inMilliseconds * fps / 1000).round(),
    );
    try {
      await dir.create(recursive: true);
      final image = img.Image(width: width, height: height, numChannels: 4);
      final shade = firstStrokeErases ? 255 : 0;
      img.fill(image, color: img.ColorRgba8(shade, shade, shade, 255));
      final bytes = img.encodePng(image);
      for (var i = 0; i < frameCount; i++) {
        final name = 'mask_${i.toString().padLeft(6, '0')}.png';
        await File('${dir.path}/$name').writeAsBytes(bytes);
      }
      return CutoutSettings(
        maskDirectory: dir.path,
        sourceStart: sourceStart,
        framesPerSecond: fps,
        frameCount: frameCount,
        manualMask: true,
      );
    } catch (_) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  /// Apply user edits to a fresh copy of original masks. The original masks
  /// stay immutable so undo, reset and subsequent modifications are reliable.
  static Future<String> correctedMaskDirectory(CutoutSettings settings) async {
    if (!settings.hasMask || settings.strokes.isEmpty)
      return settings.maskDirectory;
    final saved = await TiniEditDirectoryCache.obtain(
      stage: 'cutout.strokes.v1',
      parameters: {
        'strokes': settings.strokes.map((s) => s.toNative()).toList(),
      },
      sources: [settings.maskDirectory],
      build: (inputs, stop) async {
        final temp = await getTemporaryDirectory();
        final output = await temp.createTemp('tini_mask_edited_');
        await output.delete();
        try {
          await _native.invokeMethod('applyStrokes', {
            'inputDir': inputs[0].path,
            'outputDir': output.path,
            'strokes': settings.strokes.map((s) => s.toNative()).toList(),
          });
          return TiniEditDirectoryResult(output.path, {});
        } catch (_) {
          if (await output.exists()) await output.delete(recursive: true);
          rethrow;
        }
      },
    );
    return saved.path;
  }

  /// FFmpeg logs include a very long version/configuration header. Keep the
  /// last actionable diagnostics in the UI; retain the full text on disk.
  static String _failureSummary(String logs, Object? code) {
    final lines = logs
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final errorPattern = RegExp(
      r'error|failed|invalid|unknown|not found|no such|cannot|could not|unable|unsupported|encoder|decoder',
      caseSensitive: false,
    );
    final diagnosticLines = lines
        .where(
          (line) =>
              errorPattern.hasMatch(line) &&
              !line.startsWith('configuration:') &&
              !line.startsWith('built with'),
        )
        .toList();
    final relevant = diagnosticLines.isNotEmpty ? diagnosticLines : lines;
    final tail = relevant
        .skip(relevant.length > 3 ? relevant.length - 3 : 0)
        .join(' | ');
    final short = tail.length > 420 ? tail.substring(tail.length - 420) : tail;
    return short.isEmpty
        ? 'FFmpeg failed (exit code: $code). Inspect the saved diagnostic log.'
        : 'FFmpeg (code $code): $short';
  }

  /// Gallery pickers may provide a percent-encoded file URI (file:///.../%D9...)
  /// instead of a filesystem path. FFmpeg's -i expects the decoded local path,
  /// not that URI. Keep ordinary paths unchanged, including literal '%' names.
  static String _localMediaPath(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'file') {
      return uri.toFilePath();
    }
    return value;
  }

  static Future<String> _readableMediaPath(String value, String label) async {
    final path = _localMediaPath(value);
    if (path.isEmpty ||
        ((path.startsWith('/') || value.startsWith('file:')) &&
            !await File(path).exists())) {
      throw StateError(
        'تعذر العثور على ملف $label. اختر الملف مجدداً ثم حاول مرة أخرى.',
      );
    }
    return path;
  }

  // Restrict all generated FFmpeg inputs to numeric values from the immutable
  // settings. No user-controlled filter expressions or paths are interpolated.
  static String _edgeRgb(int color) =>
      (color & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

  /// A 3x3 dilation grows a mask one pixel. The outer minus inner masks make
  /// the stroke external to the person, without coloring the subject itself.
  static String _edgeDilate(int pixels) =>
      List.filled(pixels.clamp(0, 56).toInt(), 'dilation').join(',');

  static void _edgeRing(
    List<String> filters, {
    required int index,
    required int outer,
    required int inner,
    required CutoutEdgeStyle style,
  }) {
    final outerFilter = _edgeDilate(outer);
    final innerFilter = _edgeDilate(inner);
    filters.add(
      "[edgeOuter$index]${outerFilter.isEmpty ? '' : '$outerFilter,'}format=gray[edgeExpanded$index]",
    );
    filters.add(
      "[edgeInner$index]${innerFilter.isEmpty ? '' : '$innerFilter,'}format=gray[edgeContracted$index]",
    );
    var expr = 'max(0,A-B)';
    if (style == CutoutEdgeStyle.paper) {
      // Deterministic fine torn-paper pattern along the actual contour.
      expr = 'max(0,A-B)*if(lt(mod(X*7+Y*11,17),3),0.38,1)';
    } else if (style == CutoutEdgeStyle.dashed) {
      expr = 'max(0,A-B)*if(lt(mod(X+Y,26),16),1,0)';
    } else if (style == CutoutEdgeStyle.sparkle) {
      expr =
          'max(0,A-B)*max(lt(mod(X,24),3)*lt(mod(Y,24),11),lt(mod(X,24),11)*lt(mod(Y,24),3))';
    }
    filters.add(
      '[edgeExpanded$index][edgeContracted$index]'
      "blend=all_expr='$expr'[edgeRing$index]",
    );
  }

  static String _sec(Duration d) =>
      (d.inMicroseconds / 1000000).toStringAsFixed(6);
  static String _safe(String path) => path.replaceAll('"', '\\"');

  /// Render at the original source playback rate. The existing editor handles
  /// Speed (normal/curve), Magic, mute, and concatenation after this stage.
  static Future<String> composeClip({
    required String source,
    required Duration sourceStart,
    required CropClip clip,
    required int width,
    required int height,
    bool preview = false,
    bool useCache = true,
  }) async {
    if (useCache) {
      final cache = TiniEditCache.shared;
      final inputs = <TiniEditNode>[await cache.source(source)];
      if (clip.backgroundPath?.isNotEmpty == true)
        inputs.add(await cache.source(clip.backgroundPath!));
      final c = clip.cutout;
      if (c?.hasMask == true) inputs.add(await cache.source(c!.maskDirectory));
      final parameters = <String, Object?>{
        'start': sourceStart.inMicroseconds,
        'duration': clip.duration.inMicroseconds,
        'size': [width, height],
        'preview': preview,
        'cutout': c == null
            ? null
            : {
                'maskStart': c.sourceStart.inMicroseconds,
                'fps': c.framesPerSecond,
                'frames': c.frameCount,
                'manual': c.manualMask,
                'strokes': [
                  for (final s in c.strokes)
                    [
                      s.erase,
                      s.quick,
                      s.radius,
                      [
                        for (final p in s.points) [p.dx, p.dy],
                      ],
                    ],
                ],
                'chroma': [
                  c.chromaEnabled,
                  c.chromaColor,
                  c.chromaSimilarity,
                  c.chromaBlend,
                  c.chromaDraftEnabled,
                ],
                'passes': [
                  for (final p in c.chromaPasses)
                    [p.color, p.similarity, p.blend],
                ],
                'edge': [
                  c.edgeFeather,
                  c.edgeStyle.name,
                  c.edgeColor,
                  c.edgeSize,
                  c.edgeDistance,
                  c.edgeOpacity,
                ],
              },
      };
      final node = TiniEditNode(
        stage: 'background.direct.v1',
        parameters: parameters,
        inputs: inputs,
        render: (i, stop) async {
          if (stop()) throw TiniEditCancelled();
          final p = await composeClip(
            source: i[0].path,
            sourceStart: sourceStart,
            clip: clip,
            width: width,
            height: height,
            preview: preview,
            useCache: false,
          );
          return TiniEditArtifact(p, temporary: p != i[0].path);
        },
      );
      return (await cache.run(node)).path;
    }

    final temp = await getTemporaryDirectory();
    final serial = DateTime.now().microsecondsSinceEpoch;
    final output = '${temp.path}/tini_background_$serial.mp4';
    final w =
        (preview ? width.clamp(2, 540) : width.clamp(2, 1920)).toInt() ~/ 2 * 2;
    final h =
        (preview ? height.clamp(2, 960) : height.clamp(2, 1920)).toInt() ~/
        2 *
        2;
    final seconds = clip.duration.inMicroseconds / 1000000.0;
    if (seconds <= 0) throw StateError('Invalid clip duration');
    final cutout = clip.cutout;
    String? editedMasks;
    try {
      if (cutout != null && cutout.hasMask && cutout.strokes.isNotEmpty) {
        editedMasks = await correctedMaskDirectory(cutout);
      }
      final maskDir =
          editedMasks ??
          (cutout?.hasMask == true ? cutout!.maskDirectory : null);
      // Masks were sampled starting at an absolute source timestamp. Splits
      // and trims select their matching subrange, without retiming the source.
      final maskOffset = cutout == null
          ? 0.0
          : (sourceStart - cutout.sourceStart).inMicroseconds / 1000000.0;
      if (maskDir != null &&
          cutout != null &&
          (maskOffset < -0.075 ||
              maskOffset + seconds >
                  cutout.frameCount / cutout.framesPerSecond + 0.075)) {
        throw StateError(
          'القص تجاوز حدود قناع العزل. أعد تنفيذ القص التلقائي على المقطع.',
        );
      }
      final inputPath = await _readableMediaPath(source, 'الفيديو');
      final backgroundPath = clip.backgroundPath == null
          ? null
          : await _readableMediaPath(clip.backgroundPath!, 'الخلفية');
      final args = StringBuffer(
        '-hide_banner -loglevel error -nostats '
        '-filter_complex_threads 1 '
        '-ss ${_sec(sourceStart)} -t ${seconds.toStringAsFixed(6)} '
        '-i "${_safe(inputPath)}" ',
      );
      // Background file is always the second input. In the no-background case,
      // a neutral color canvas is generated; users can change it later.
      if (backgroundPath != null) {
        args.write('-loop 1 -framerate 30 -i "${_safe(backgroundPath)}" ');
      } else {
        args.write('-f lavfi -i color=c=black:s=${w}x$h:r=30 ');
      }
      if (maskDir != null) {
        args.write(
          '-framerate ${cutout!.framesPerSecond.toStringAsFixed(5)} '
          '-start_number 0 -i "${_safe(maskDir)}/mask_%06d.png" ',
        );
      }
      final edge =
          cutout != null &&
          cutout.hasMask &&
          cutout.edgeStyle != CutoutEdgeStyle.none &&
          cutout.edgeOpacity > 0.001;
      if (edge) {
        args.write(
          '-f lavfi -i color=c=0x${_edgeRgb(cutout.edgeColor)}:'
          's=${w}x$h:r=30 ',
        );
        if (cutout.edgeStyle == CutoutEdgeStyle.doubleLine) {
          args.write('-f lavfi -i color=c=0xFF4DAA:s=${w}x$h:r=30 ');
        }
      }
      final filters = <String>[
        '[1:v]scale=$w:$h:force_original_aspect_ratio=increase,'
            'crop=$w:$h,setsar=1,format=rgba[background]',
      ];
      if (maskDir != null && cutout != null) {
        filters.add(
          '[0:v]scale=$w:$h:force_original_aspect_ratio=decrease,'
          'pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=black@0,setsar=1,'
          'fps=30,format=rgba[foreground]',
        );
        filters.add(
          '[2:v]trim=start=${maskOffset.clamp(0.0, 999999.0).toStringAsFixed(6)}:'
          'duration=${seconds.toStringAsFixed(6)},setpts=PTS-STARTPTS,'
          'scale=$w:$h:force_original_aspect_ratio=decrease:flags=bilinear,'
          'pad=$w:$h:(ow-iw)/2:(oh-ih)/2:black,format=gray,'
          'tpad=stop_mode=clone:stop_duration=0.15,fps=30'
          '${edge ? ',split=2[alphaRaw][edgeMaskRaw]' : ','
                    'gblur=sigma=${(cutout.edgeFeather.clamp(0.0, 5.0)).toStringAsFixed(2)}[alpha]'}',
        );
        if (edge) {
          // Keep the person's alpha soft, but extract the outline from a
          // separate clean silhouette. This suppresses tiny mask islands and
          // avoids drawing light around semi-transparent background speckles.
          filters.add(
            '[alphaRaw]gblur=sigma='
            '${(cutout.edgeFeather.clamp(0.0, 5.0)).toStringAsFixed(2)}[alpha]',
          );
          filters.add(
            '[edgeMaskRaw]median=radius=1,gblur=sigma=0.85,'
            "lut=y='if(gte(val,122),255,0)'[edgeMaskBase]",
          );
        }
        filters.add('[foreground][alpha]alphamerge[cut]');
        var baseLabel = 'background';
        if (edge) {
          final style = cutout.edgeStyle;
          // Pixel radii scale with output resolution but remain bounded for
          // mobile encoding. Presets differ in shape, glow and ring spacing.
          final scale = (math.min(w / 540.0, h / 960.0)).clamp(.55, 1.8);
          // A neon outline is visibly broader than an ordinary single stroke.
          // Scale both types with the output, so preview and export preserve
          // similar visual proportions despite their different resolutions.
          final luminous =
              style == CutoutEdgeStyle.glow || style == CutoutEdgeStyle.pink;
          final widthPx =
              ((luminous ? 2.5 : 1.0) +
                      cutout.edgeSize.clamp(0.0, 1.0) * (luminous ? 10.0 : 7.0))
                  .toDouble() *
              scale;
          final strokeWidth = widthPx.round().clamp(1, 18).toInt();
          final gapPx = (cutout.edgeDistance.clamp(0.0, 1.0) * 5 * scale)
              .round()
              .clamp(0, 9)
              .toInt();
          final rings = style == CutoutEdgeStyle.doubleLine ? 2 : 1;
          filters.add(
            '[edgeMaskBase]split=${rings * 2}'
            '${List.generate(rings, (i) => '[edgeOuter$i][edgeInner$i]').join()}',
          );
          for (var i = 0; i < rings; i++) {
            final extra = i == 0 ? 0 : strokeWidth + 2;
            _edgeRing(
              filters,
              index: i,
              outer: strokeWidth + gapPx + extra,
              inner: gapPx + extra,
              style: style,
            );
          }
          // Opacity is applied to the edge's mask, not to the person.
          final opacity = cutout.edgeOpacity.clamp(0.0, 1.0);
          if (style == CutoutEdgeStyle.glow || style == CutoutEdgeStyle.pink) {
            // Two *independent* illuminated halos behind an opaque neon core.
            // Blurring a thin ring once and multiplying by .55 (old behavior)
            // made nearly all light disappear at real playback size.
            final innerBlur = (2.5 + strokeWidth * 0.90).clamp(3.0, 20.0);
            final outerBlur = (7.0 + strokeWidth * 2.25).clamp(8.0, 48.0);
            filters.add(
              '[edgeRing0]split=3[edgeCore][edgeInnerGlow][edgeOuterGlow]',
            );
            filters.add(
              "[edgeCore]lut=y='min(255,val*${opacity.toStringAsFixed(3)})'[edgeCoreOpacity]",
            );
            filters.add(
              '[edgeInnerGlow]gblur=sigma=${innerBlur.toStringAsFixed(2)},'
              "lut=y='min(255,val*${(opacity * 2.2).toStringAsFixed(3)})'[edgeInnerOpacity]",
            );
            filters.add(
              '[edgeOuterGlow]gblur=sigma=${outerBlur.toStringAsFixed(2)},'
              "lut=y='min(255,val*${(opacity * 3.2).toStringAsFixed(3)})'[edgeOuterOpacity]",
            );
            filters.add(
              '[3:v]format=rgba,split=3'
              '[edgeColorCore][edgeColorInner][edgeColorOuter]',
            );
            filters.add(
              '[edgeColorOuter][edgeOuterOpacity]alphamerge[edgeOuterLayer]',
            );
            filters.add(
              '[background][edgeOuterLayer]overlay=0:0:shortest=1:'
              'format=auto[edgeOuterBackground]',
            );
            filters.add(
              '[edgeColorInner][edgeInnerOpacity]alphamerge[edgeInnerLayer]',
            );
            filters.add(
              '[edgeOuterBackground][edgeInnerLayer]overlay=0:0:shortest=1:'
              'format=auto[edgeInnerBackground]',
            );
            filters.add(
              '[edgeColorCore][edgeCoreOpacity]alphamerge[edgeCoreLayer]',
            );
            filters.add(
              '[edgeInnerBackground][edgeCoreLayer]overlay=0:0:'
              'shortest=1:format=auto[edgeBackground]',
            );
          } else if (rings == 2) {
            filters.add(
              "[edgeRing0]lut=y='val*${opacity.toStringAsFixed(3)}'[edgeAlpha0]",
            );
            filters.add(
              "[edgeRing1]lut=y='val*${opacity.toStringAsFixed(3)}'[edgeAlpha1]",
            );
            filters.add('[3:v]format=rgba[edgeColor0]');
            filters.add('[4:v]format=rgba[edgeColor1]');
            filters.add('[edgeColor1][edgeAlpha1]alphamerge[edgeLayer1]');
            filters.add(
              '[background][edgeLayer1]overlay=0:0:shortest=1:'
              'format=auto[edgeOuterBackground]',
            );
            filters.add('[edgeColor0][edgeAlpha0]alphamerge[edgeLayer0]');
            filters.add(
              '[edgeOuterBackground][edgeLayer0]overlay=0:0:'
              'shortest=1:format=auto[edgeBackground]',
            );
          } else {
            filters.add(
              "[edgeRing0]lut=y='val*${opacity.toStringAsFixed(3)}'[edgeOpacity]",
            );
            filters.add('[3:v]format=rgba[edgeColor]');
            filters.add('[edgeColor][edgeOpacity]alphamerge[edgeLayer]');
            filters.add(
              '[background][edgeLayer]overlay=0:0:shortest=1:'
              'format=auto[edgeBackground]',
            );
          }
          baseLabel = 'edgeBackground';
        }
        filters.add(
          '[$baseLabel][cut]overlay=x=0:y=0:shortest=1:format=auto,'
          'format=yuv420p[vout]',
        );
      } else if (cutout?.chromaEnabled == true) {
        // Compute all confirmed keys and the optional draft independently.
        // Multiplying their alpha masks never restores a previously cut pixel.
        final keys = <ChromaKeyPass>[
          ...cutout!.chromaPasses,
          if (cutout.chromaDraftEnabled)
            ChromaKeyPass(
              color: cutout.chromaColor,
              similarity: cutout.chromaSimilarity,
              blend: cutout.chromaBlend,
            ),
        ];
        final base =
            '[0:v]scale=$w:$h:force_original_aspect_ratio=decrease,'
            'pad=$w:$h:(ow-iw)/2:(oh-ih)/2:black,setsar=1,fps=30,format=rgba';
        if (keys.isEmpty) {
          filters.add('$base[cut]');
        } else if (keys.length == 1) {
          final key = keys.first.color.toRadixString(16).padLeft(6, '0');
          final similarity = keys.first.similarity
              .clamp(.01, .12)
              .toStringAsFixed(3);
          final blend = keys.first.blend.clamp(0.0, .05).toStringAsFixed(3);
          filters.add('$base,colorkey=0x$key:$similarity:$blend[cut]');
        } else {
          final streams = <String>[
            '[chromaBase]',
            for (var i = 0; i < keys.length; i++) '[chromaInput$i]',
          ];
          filters.add('$base,split=${streams.length}${streams.join()}');
          for (var i = 0; i < keys.length; i++) {
            final key = keys[i].color.toRadixString(16).padLeft(6, '0');
            final similarity = keys[i].similarity
                .clamp(.01, .12)
                .toStringAsFixed(3);
            final blend = keys[i].blend.clamp(0.0, .05).toStringAsFixed(3);
            filters.add(
              '[chromaInput$i]colorkey=0x$key:$similarity:$blend,'
              'alphaextract[chromaAlpha$i]',
            );
          }
          var previous = 'chromaAlpha0';
          for (var i = 1; i < keys.length; i++) {
            final joined = 'chromaJoint$i';
            filters.add(
              '[$previous][chromaAlpha$i]blend=all_mode=multiply[$joined]',
            );
            previous = joined;
          }
          filters.add('[chromaBase][$previous]alphamerge[cut]');
        }
        filters.add(
          '[background][cut]overlay=x=0:y=0:shortest=1:format=auto,'
          'format=yuv420p[vout]',
        );
      } else {
        // For uncut videos, background is a surround, not a foreground replacement.
        filters.add(
          '[0:v]scale=trunc($w*0.88/2)*2:trunc($h*0.88/2)*2:'
          'force_original_aspect_ratio=decrease,setsar=1[foreground]',
        );
        filters.add(
          '[background][foreground]overlay=(W-w)/2:(H-h)/2:'
          'shortest=1,format=yuv420p[vout]',
        );
      }
      final full =
          '${args.toString()}-filter_complex "${filters.join(';')}" '
          '-map "[vout]" -map 0:a:0? -t ${seconds.toStringAsFixed(6)} '
          '-threads 2 -c:v libx264 -preset veryfast -crf ${preview ? 29 : 21} '
          '-pix_fmt yuv420p -c:a aac -b:a 128k -ar 44100 -ac 2 '
          '-movflags +faststart -y "${_safe(output)}"';
      final session = await FFmpegKit.execute(full);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = (await session.getAllLogsAsString()) ?? '';
        // The full FFmpeg log is diagnostic data, not a widget's error label.
        // Keep it locally for Android debugging without making the UI overflow.
        final logPath = '${temp.path}/tini_cutout_last_ffmpeg_failure.log';
        try {
          await File(
            logPath,
          ).writeAsString('Return code: $returnCode\nCommand: $full\n\n$logs');
        } catch (_) {}
        final summary = _failureSummary(logs, returnCode);
        debugPrint('Tini Cutout render failed: $summary (log: $logPath)');
        try {
          await File(output).delete();
        } catch (_) {}
        throw StateError('تعذرت معاينة قص الخلفية. $summary');
      }
      if (!await File(output).exists() || await File(output).length() == 0) {
        throw StateError('انتهت المعالجة دون إنتاج فيديو معاينة صالح.');
      }
      return output;
    } finally {
      if (editedMasks != null) {
        try {
          await Directory(editedMasks).delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
