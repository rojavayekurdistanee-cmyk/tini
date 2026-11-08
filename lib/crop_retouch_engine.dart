import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'crop_retouch_model.dart';
import 'crop_retouch_pixels.dart';
import 'crop_retouch_detector.dart';
import 'crop_retouch_commands.dart';
import 'tini_edit_cache.dart';

class CropRetouchCancelled implements Exception {}

class _TiniMissingRetouchAnalysis implements Exception {}

class CropRetouchResult {
  final String path;
  final int frames, faceFrames, changedPixels;
  const CropRetouchResult(
    this.path,
    this.frames,
    this.faceFrames,
    this.changedPixels,
  );
}

class CropRetouchStill {
  final Uint8List png;
  final bool hasFace;
  final int changedPixels;
  const CropRetouchStill(this.png, this.hasFace, this.changedPixels);
}

/// Actual face tracking on every decoded frame. Pixel work is isolated from
/// Flutter's UI isolate; only 30 PNGs coexist on disk, even for a long video.
class CropRetouchEngine {
  /// Directory.createTemp creates a child of its receiver, not a path prefix.
  /// Re-create the cache parent if Android removed it before this operation.
  static Future<Directory> createWorkspace(
    Directory cache,
    String prefix,
  ) async {
    await cache.create(recursive: true);
    return cache.createTemp(prefix);
  }

  static Future<void> _queue = Future<void>.value();
  static Future<void> _execute(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(args);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw StateError(
        'تعذرت معالجة التنميق: ${await session.getAllLogsAsString()}',
      );
    }
  }

  static Future<CropRetouchResult> render({
    required String input,
    required CropRetouchSettings settings,
    required int durationMs,
    required int width,
    required int height,
    ValueProgress? onProgress,
    int sourceStartMs = 0,
    bool lossless = false,
    String? sourceCacheKey,
    bool useCache = true,
    bool Function()? cancelled,
  }) {
    if (!settings.enabled) {
      return Future.value(CropRetouchResult(input, 0, 0, 0));
    }
    if (cancelled?.call() == true) return Future.error(CropRetouchCancelled());
    if (useCache)
      return _cachedRender(
        input: input,
        settings: settings,
        durationMs: durationMs,
        width: width,
        height: height,
        sourceStartMs: sourceStartMs,
        lossless: lossless,
        onProgress: onProgress,
        cancelled: cancelled,
      );
    final completer = Completer<CropRetouchResult>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(
          await _render(
            input: input,
            settings: settings,
            durationMs: durationMs,
            width: width,
            height: height,
            onProgress: onProgress,
            sourceStartMs: sourceStartMs,
            lossless: lossless,
            sourceCacheKey: sourceCacheKey,
            cancelled: cancelled,
          ),
        );
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  static Future<CropRetouchResult> _cachedRender({
    required String input,
    required CropRetouchSettings settings,
    required int durationMs,
    required int width,
    required int height,
    required int sourceStartMs,
    required bool lossless,
    ValueProgress? onProgress,
    bool Function()? cancelled,
  }) async {
    final cache = TiniEditCache.shared;
    final source = await cache.source(input);
    final node = TiniEditNode(
      stage: 'retouch.direct.v1',
      parameters: {
        'smooth': settings.smooth,
        'teeth': settings.teeth,
        'duration': durationMs,
        'size': [width, height],
        'start': sourceStartMs,
        'lossless': lossless,
      },
      inputs: [source],
      extension: lossless ? 'mkv' : 'mp4',
      render: (i, stop) async {
        final r = await render(
          input: i[0].path,
          settings: settings,
          durationMs: durationMs,
          width: width,
          height: height,
          sourceStartMs: sourceStartMs,
          lossless: lossless,
          onProgress: onProgress,
          cancelled: stop,
          useCache: false,
        );
        return TiniEditArtifact(
          r.path,
          temporary: r.path != i[0].path,
          metadata: {
            'frames': r.frames,
            'faceFrames': r.faceFrames,
            'changedPixels': r.changedPixels,
          },
        );
      },
    );
    try {
      final result = await cache.run(node, cancelled: cancelled);
      onProgress?.call(1);
      return CropRetouchResult(
        result.path,
        result.metadata['frames'] as int,
        result.metadata['faceFrames'] as int,
        result.metadata['changedPixels'] as int,
      );
    } on TiniEditCancelled {
      throw CropRetouchCancelled();
    }
  }

  static Future<CropRetouchStill> _cachedStill({
    required String input,
    required int positionMs,
    required CropRetouchSettings settings,
  }) async {
    final cache = TiniEditCache.shared;
    final source = await cache.source(input);
    final node = TiniEditNode(
      stage: 'retouch.still.v1',
      parameters: {
        'at': positionMs,
        'smooth': settings.smooth,
        'teeth': settings.teeth,
      },
      inputs: [source],
      extension: 'png',
      render: (i, stop) async {
        final r = await still(
          input: i[0].path,
          positionMs: positionMs,
          settings: settings,
          useCache: false,
        );
        final folder = await createWorkspace(
          await getTemporaryDirectory(),
          'tini_still_cache_',
        );
        final output = File('${folder.path}/frame.png');
        await output.writeAsBytes(r.png);
        return TiniEditArtifact(
          output.path,
          temporary: true,
          metadata: {'face': r.hasFace, 'changed': r.changedPixels},
        );
      },
    );
    final cached = await cache.run(node);
    try {
      return CropRetouchStill(
        await File(cached.path).readAsBytes(),
        cached.metadata['face'] as bool,
        cached.metadata['changed'] as int,
      );
    } finally {
      try {
        await File(cached.path).delete();
      } catch (_) {}
    }
  }

  static Future<CropRetouchResult> _render({
    required String input,
    required CropRetouchSettings settings,
    required int durationMs,
    required int width,
    required int height,
    ValueProgress? onProgress,
    int sourceStartMs = 0,
    bool lossless = false,
    String? sourceCacheKey,
    bool Function()? cancelled,
  }) async {
    void check() {
      if (cancelled?.call() == true) throw CropRetouchCancelled();
    }

    check();
    if (durationMs <= 0 || width < 2 || height < 2) {
      throw StateError('مدة أو أبعاد الفيديو غير صالحة');
    }
    final cache = TiniEditCache.shared;
    final source = sourceCacheKey == null
        ? await cache.source(input)
        : TiniEditNode.source(input, sourceCacheKey);
    TiniEditNode geometry(TiniEditProducer producer) => TiniEditNode(
      stage: 'retouch.faces.accurate.v1',
      parameters: {
        'size': [width, height],
        'start': sourceStartMs,
        'duration': durationMs,
      },
      inputs: [source],
      extension: 'json',
      render: producer,
    );
    List<List<CropRetouchFace>>? known;
    try {
      final saved = await cache.run(
        geometry((i, stop) async {
          throw _TiniMissingRetouchAnalysis();
        }),
      );
      try {
        final rows = jsonDecode(await File(saved.path).readAsString()) as List;
        known = [
          for (final row in rows)
            [for (final f in row as List) CropRetouchFace.fromMap(f as Map)],
        ];
      } finally {
        await File(saved.path).delete();
      }
    } on _TiniMissingRetouchAnalysis {
      /* Collect geometry during the normal processing pass. */
    } on FileSystemException {
      /* Analysis caching must not prevent rendering. */
    } on FormatException {
      /* Rebuild malformed analysis. */
    } on TypeError {
      /* Rebuild malformed analysis. */
    }
    if (known != null && known.isNotEmpty && known.every((f) => f.isEmpty)) {
      onProgress?.call(1);
      return CropRetouchResult(input, known.length, 0, 0);
    }
    final observed = <List<CropRetouchFace>>[];
    final temp = await getTemporaryDirectory();
    final root = await createWorkspace(temp, 'tini_retouch_');
    final output =
        '${temp.path}/tini_retouch_result_${DateTime.now().microsecondsSinceEpoch}.${lossless ? 'mkv' : 'mp4'}';
    final detector = CropRetouchDetector();
    _RetouchWorker? worker;
    var done = 0, faceFrames = 0, changed = 0;
    final frames = (durationMs * 30 / 1000).round().clamp(1, 1 << 31);
    final parts = <String>[];
    var keepOutput = false;
    try {
      worker = await _RetouchWorker.open();
      while (done < frames) {
        check();
        final count = (frames - done).clamp(1, 30);
        final pattern = '${root.path}/frame_%06d.png';
        await _execute(
          CropRetouchCommands.extract(
            input: input,
            pattern: pattern,
            startSeconds: sourceStartMs / 1000 + done / 30,
            frames: count,
            width: width,
            height: height,
          ),
        );
        var actual = 0;
        for (var i = 0; i < count; i++) {
          check();
          final file = File(
            '${root.path}/frame_${i.toString().padLeft(6, '0')}.png',
          );
          if (!await file.exists()) break;
          // Bound per-frame detector/worker waits. A timeout is an explicit
          // export failure, never a silent fallback to unretouched video.
          final faces = known != null && done + actual < known.length
              ? known[done + actual]
              : await detector
                    .detect(file.path)
                    .timeout(
                      const Duration(seconds: 15),
                      onTimeout: () => throw TimeoutException(
                        'انتهت مهلة كشف الوجه أثناء تجهيز التنميق',
                      ),
                    );
          observed.add(faces);
          if (faces.isNotEmpty) {
            faceFrames++;
            changed += await worker
                .process(file.path, faces, settings)
                .timeout(
                  const Duration(seconds: 15),
                  onTimeout: () =>
                      throw TimeoutException('انتهت مهلة معالجة إطار التنميق'),
                );
          }
          actual++;
          onProgress?.call((done + actual) / frames);
        }
        if (actual == 0) break;
        final part =
            '${root.path}/part_${parts.length}.${lossless ? 'mkv' : 'mp4'}';
        await _execute(
          CropRetouchCommands.encode(
            pattern: pattern,
            output: part,
            frames: actual,
            lossless: lossless,
          ),
        );
        parts.add(part);
        for (var i = 0; i < actual; i++) {
          await File(
            '${root.path}/frame_${i.toString().padLeft(6, '0')}.png',
          ).delete();
        }
        done += actual;
        if (actual < count) break;
      }
      check();
      if (done == 0) throw StateError('لم يتم فك أي إطار من الفيديو');
      if (known == null) {
        try {
          final saved = await cache.run(
            geometry((i, stop) async {
              final dir = await createWorkspace(
                await getTemporaryDirectory(),
                'tini_face_analysis_',
              );
              final data = File('${dir.path}/faces.json');
              await data.writeAsString(
                jsonEncode([
                  for (final frame in observed)
                    [for (final face in frame) face.toMap()],
                ]),
              );
              return TiniEditArtifact(data.path, temporary: true);
            }),
          );
          await File(saved.path).delete();
        } on FileSystemException {
          /* The completed render remains valid without its optional analysis cache. */
        }
      }
      if (changed == 0) return CropRetouchResult(input, done, faceFrames, 0);
      final list = File('${root.path}/parts.txt');
      await list.writeAsString(
        parts.map((p) => "file '${p.replaceAll("'", "'\\''")}'").join('\n'),
      );
      await _execute(
        CropRetouchCommands.mux(
          list: list.path,
          source: input,
          output: output,
          seconds: durationMs / 1000,
          sourceStartMs: sourceStartMs,
          lossless: lossless,
        ),
      );
      if (!await File(output).exists() || await File(output).length() == 0) {
        throw StateError('لم تنتج المعالجة فيديو صالحًا');
      }
      keepOutput = true;
      return CropRetouchResult(output, done, faceFrames, changed);
    } finally {
      worker?.close();
      try {
        await detector.close();
      } catch (_) {}
      try {
        await root.delete(recursive: true);
      } catch (_) {}
      if (!keepOutput) {
        try {
          await File(output).delete();
        } catch (_) {}
      }
    }
  }

  static Future<CropRetouchStill> still({
    required String input,
    required int positionMs,
    required CropRetouchSettings settings,
    bool useCache = true,
  }) async {
    if (useCache)
      return _cachedStill(
        input: input,
        positionMs: positionMs,
        settings: settings,
      );
    final temp = await getTemporaryDirectory();
    final root = await createWorkspace(temp, 'tini_retouch_still_');
    final frame = File('${root.path}/frame.png');
    final detector = CropRetouchDetector();
    _RetouchWorker? worker;
    try {
      await _execute([
        '-ss',
        (positionMs / 1000).toStringAsFixed(6),
        '-i',
        input,
        '-pix_fmt',
        'rgb24',
        '-frames:v',
        '1',
        '-vf',
        'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        '-y',
        frame.path,
      ]);
      if (!await frame.exists()) throw StateError('تعذر قراءة الإطار الحالي');
      final faces = await detector.detect(frame.path);
      var changed = 0;
      if (settings.enabled && faces.isNotEmpty) {
        worker = await _RetouchWorker.open();
        changed = await worker.process(frame.path, faces, settings);
      }
      return CropRetouchStill(
        await frame.readAsBytes(),
        faces.isNotEmpty,
        changed,
      );
    } finally {
      worker?.close();
      try {
        await detector.close();
      } catch (_) {}
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    }
  }
}

typedef ValueProgress = void Function(double progress);

class _RetouchWorker {
  final Isolate isolate;
  final SendPort port;
  _RetouchWorker(this.isolate, this.port);
  static Future<_RetouchWorker> open() async {
    final receiver = ReceivePort();
    final isolate = await Isolate.spawn(_retouchWorkerMain, receiver.sendPort);
    final port = await receiver.first as SendPort;
    receiver.close();
    return _RetouchWorker(isolate, port);
  }

  Future<int> process(
    String path,
    List<CropRetouchFace> faces,
    CropRetouchSettings settings,
  ) async {
    final response = ReceivePort();
    port.send({
      'path': path,
      'faces': faces.map((f) => f.toMap()).toList(),
      'smooth': settings.smooth,
      'teeth': settings.teeth,
      'reply': response.sendPort,
    });
    try {
      final value = await response.first;
      if (value is int) return value;
      throw StateError('تعذرت معالجة الإطار: $value');
    } finally {
      response.close();
    }
  }

  void close() => isolate.kill(priority: Isolate.immediate);
}

void _retouchWorkerMain(SendPort sender) async {
  final port = ReceivePort();
  sender.send(port.sendPort);
  await for (final dynamic job in port) {
    final reply = job['reply'] as SendPort;
    try {
      final file = File(job['path'] as String);
      final image = img.decodePng(await file.readAsBytes());
      if (image == null) throw StateError('PNG decode failed');
      final faces = [
        for (final face in job['faces'] as List)
          CropRetouchFace.fromMap(face as Map),
      ];
      final changed = CropRetouchPixels.apply(
        image,
        faces,
        CropRetouchSettings(
          smooth: job['smooth'] as double,
          teeth: job['teeth'] as double,
        ),
      );
      if (changed > 0) await file.writeAsBytes(img.encodePng(image, level: 1));
      reply.send(changed);
    } catch (error) {
      reply.send(error.toString());
    }
  }
}
