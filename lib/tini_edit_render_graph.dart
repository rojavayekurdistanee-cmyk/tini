part of 'video_processor.dart';

/// Keep device diagnostics available without filling a snackbar with the
/// FFmpeg build banner. In particular, the final error lines must stay visible.
class _TiniStageFailure implements Exception {
  final String stage, details, logPath;
  _TiniStageFailure(this.stage, this.details, this.logPath);
  static Future<_TiniStageFailure> record(String stage, String log) async {
    var path = '';
    try {
      final root = await getTemporaryDirectory();
      await root.create(recursive: true);
      final file = File(
        '${root.path}/tini_ffmpeg_failure_${VideoProcessor._serial()}.log',
      );
      await file.writeAsString(log);
      path = file.path;
    } on FileSystemException {
      // A full cache must not hide the original encoding error.
    }
    final lines = log
        .split(RegExp(r'[\r\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    var details = lines
        .skip(lines.length > 7 ? lines.length - 7 : 0)
        .join('\n');
    if (details.length > 1400)
      details = details.substring(details.length - 1400);
    return _TiniStageFailure(stage, details, path);
  }

  @override
  String toString() => 'تعذرت معالجة $stage:\n$details';
}

/// Existing visual operator order, now expressed as immutable cached prefixes.
/// Lossless internal videos prevent an extra lossy generation for every edit.
class _TiniStreamEncodingFailure implements Exception {
  final Object problem;
  _TiniStreamEncodingFailure(this.problem);
  @override
  String toString() => 'Video stream encoding failed: $problem';
}

class _TiniStreamNode {
  final TiniEditNode input;
  final TiniVideoPipeline pipeline;
  _TiniStreamNode(this.input, this.pipeline);
}

class _TiniPipelineContext {
  final TiniVideoEncoder? encoder;
  final Duration duration;
  _TiniPipelineContext(this.encoder, this.duration);
}

class _TiniVideoFormat {
  final Map<String, dynamic> stream;
  _TiniVideoFormat(Map stream) : stream = Map<String, dynamic>.unmodifiable(stream.cast<String, dynamic>()) {
    if (this.stream['width'] is! int || this.stream['height'] is! int ||
        !RegExp(r'^[a-z0-9_]+$').hasMatch('${this.stream['pix_fmt']}')) {
      throw StateError('Invalid video format');
    }
  }
  String _value(String field) {
    final value = '${stream[field] ?? 'unknown'}';
    return RegExp(r'^[a-z0-9_-]+$').hasMatch(value) ? value : 'unknown';
  }
  String get sar {
    final value = '${stream['sample_aspect_ratio']}';
    return RegExp(r'^[1-9][0-9]*:[1-9][0-9]*$').hasMatch(value)
        ? value.replaceAll(':', '/') : '1/1';
  }
  String get properties => 'format=${stream['pix_fmt']},setsar=$sar,'
      'setparams=range=${_value('color_range')}:colorspace=${_value('color_space')}:'
      'color_primaries=${_value('color_primaries')}:color_trc=${_value('color_transfer')}';
  bool get rgb => RegExp(r'^(?:gbr|rgb|bgr)').hasMatch('${stream['pix_fmt']}');
  String get boundary => '$properties,settb=1/1000';
  String get dummy => 'color=black:size=${stream['width']}x${stream['height']}:'
      'rate=30:duration=0.034,$properties,settb=1/1000';
}

/// An immutable completed edit snapshot. The output node owns its checkpoint;
/// editor leases and publish cleanup never delete its cached video.
class _TiniIncrementalSnapshot {
  final String signature;
  final List<CropClip> clips;
  final TiniEditNode output;
  const _TiniIncrementalSnapshot(this.signature, this.clips, this.output);
}

class _TiniReplacementGraph {
  static final cache = TiniEditCache.shared;
  static final _streams = Expando<_TiniStreamNode>();
  static final _formats = <String, _TiniVideoFormat>{};

  // One short-lived edit history per immutable source/timeline/output mode.
  // Entries are content-addressed and never replace the existing effect graph.
  static final _editVersions = <String, List<_TiniIncrementalSnapshot>>{};
  static final _editRequests = <String, int>{};
  // Captured at request time, not at completion time. This is the UI edit
  // sequence even when an earlier asynchronous render finishes later.
  static final _requestedVersions = <String, String>{};
  // A settings-only cache key cannot distinguish Skin->Grade from
  // Grade->Skin. Editor revisions have their own keys, and an appended
  // operation may use only the exact parent that the user edited.
  static final _revisionKeys = <String, Map<String, String>>{};
  static int _editSerial = 0;

  /// A committed output is identified by its immutable media content and the
  /// complete editor configuration, not by the particular export graph that
  /// happened to produce it. The schema is intentionally versioned: older
  /// results with different processing semantics are never treated as current.
  static String _snapshotKey(String project, String signature) =>
      TiniEditCache.digest({
        'kind': 'editor.completed.snapshot',
        'schema': 2,
        'project': project,
        'signature': signature,
      });

  /// Index a completed snapshot for applying the next compatible edit.
  /// The node may be restored from disk after app restart; it is never a
  /// mutable gallery video and the cache returns independent owned copies.
  static void _recordVersion(
    String project,
    String signature,
    List<CropClip> clips,
    TiniEditNode output,
  ) {
    final versions = _editVersions.putIfAbsent(project, () => []);
    versions.removeWhere((version) => version.signature == signature);
    versions.add(_TiniIncrementalSnapshot(
      signature, List<CropClip>.unmodifiable(clips), output,
    ));
    if (versions.length > 12) versions.removeAt(0);
    if (_editVersions.length > 16) _editVersions.remove(_editVersions.keys.first);
  }

  /// Include external assets used by the graph. If a replacement, background
  /// or mask is overwritten at the same path, a previous rendered result must
  /// not be returned as if its pixels were unchanged.
  static Future<String> _inputAssetSignature(List<CropClip> clips) async {
    final paths = <String>{};
    for (final clip in clips) {
      if (clip.replacementPath?.isNotEmpty == true) {
        paths.add(clip.replacementPath!);
      }
      if (clip.backgroundPath?.isNotEmpty == true) {
        paths.add(clip.backgroundPath!);
      }
      if (clip.cutout?.hasMask == true) {
        paths.add(clip.cutout!.maskDirectory);
      }
    }
    if (paths.isEmpty) return 'no-external-assets';
    final fingerprints = <List<String>>[];
    for (final path in paths.toList()..sort()) {
      // A removed editor-owned temporary asset must not silently allow an old
      // picture to bypass the normal renderer's missing-source diagnostics.
      fingerprints.add([path, await cache.fingerprint(path)]);
    }
    return TiniEditCache.digest(fingerprints);
  }

  static Future<_TiniVideoFormat> _inspectFormat(String path, bool Function() stop) async {
    if (stop()) throw TiniEditCancelled();
    final probe = await FFprobeKit.executeWithArguments([
      '-v', 'error', '-select_streams', 'v:0', '-show_entries',
      'stream=width,height,pix_fmt,sample_aspect_ratio,color_range,color_space,color_primaries,color_transfer',
      '-of', 'json', path,
    ]);
    if (stop()) throw TiniEditCancelled();
    if (!ReturnCode.isSuccess(await probe.getReturnCode())) throw StateError('Video format probe failed');
    final streams = (jsonDecode((await probe.getOutput()) ?? '{}') as Map)['streams'] as List;
    return _TiniVideoFormat(streams.single as Map);
  }

  static Future<TiniVideoPipeline> _compileStream(_TiniStreamNode plan,
      String input, bool Function() stop) async {
    // Preserve the exact pixel-format/color/time-base boundaries chosen by
    // the original FFV1 stages. Calibration processes only a single frame;
    // real video still traverses the compiled graph once, without those files.
    final initialKey = TiniEditCache.digest({'input': plan.input.key,
      'start': plan.pipeline.trimStartUs, 'formatPolicy': 1});
    var format = _formats[initialKey];
    if (format == null) {
      if (plan.pipeline.trimStartUs == null) {
        format = await _inspectFormat(input, stop);
      } else {
        final sample = await _output('mkv');
        try {
          await _streamCommand([
            '-ss', _number(plan.pipeline.trimStartUs! / 1000000), '-i', input,
            '-map', '0:v:0', '-an', '-vf', 'setpts=PTS-STARTPTS,fps=30',
            '-frames:v', '1', '-c:v', 'ffv1', '-level', '3', '-y', sample,
          ], stop, 'initial format');
          format = await _inspectFormat(sample, stop);
        } finally {
          try { await File(sample).delete(); await File(sample).parent.delete(); }
          on FileSystemException { /* Owned calibration file already removed. */ }
        }
      }
      if (_formats.length > 512) _formats.clear();
      _formats[initialKey] = format;
    }
    var current = format;
    final first = plan.pipeline.trimStartUs == null ? null : current.boundary;
    final boundaries = <String>[];
    final compiledFilters = <List<String>>[];
    for (final step in plan.pipeline.steps) {
      final graph = (step['filters'] as List<String>).join(';');
      final key = TiniEditCache.digest({'inputFormat': current.stream, 'graph': graph, 'formatPolicy': 1});
      var next = _formats[key];
      if (next == null) {
        final sample = await _output('mkv');
        try {
          await _streamCommand([
            '-f', 'lavfi', '-i', current.dummy,
            '-filter_complex', '[0:v]null[src];$graph', '-map', '[dst]', '-an',
            '-frames:v', '1', '-c:v', 'ffv1', '-level', '3', '-fps_mode', 'passthrough', '-y', sample,
          ], stop, 'filter format');
          next = await _inspectFormat(sample, stop);
          _formats[key] = next;
        } finally {
          try { await File(sample).delete(); await File(sample).parent.delete(); }
          on FileSystemException { /* Owned calibration file already removed. */ }
        }
      }
      var filters = step['filters'] as List<String>;
      if (current.rgb && !next.rgb) {
        // Standalone FFV1 sinks select limited-range YUV at these scale nodes.
        // State that conversion at the same node, before padding/quantization;
        // retagging a full-range result afterwards would change the picture.
        if (!const {'effect.input.v1', 'canvas.fps.v1'}.contains(step['stage']) ||
            !filters.first.startsWith('[src]scale=') || next.stream['color_range'] != 'tv') {
          throw UnsupportedError('Uncompiled RGB/YUV boundary: ${step['stage']}');
        }
        filters = [for (final f in filters) f.replaceFirstMapped(
            RegExp(r'scale=([^,;]+)'), (m) => 'scale=${m[1]}:out_range=tv')];
      }
      compiledFilters.add(filters);
      boundaries.add(next.boundary);
      current = next;
    }
    return plan.pipeline.preserveBoundaries(first, boundaries,
        rgb: current.rgb, filters: compiledFilters);
  }

  static Future<void> _streamCommand(List<String> args, bool Function() stop,
      String phase) async {
    final watch = Stopwatch()..start();
    final session = await VideoProcessor._executeArguments(args, cancelled: stop);
    developer.log('phase=$phase elapsedMs=${watch.elapsedMilliseconds}', name: 'TiniExport');
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw await _TiniStageFailure.record(phase, (await session.getAllLogsAsString()) ?? '');
    }
  }

  static Future<({bool audio, bool highDepth})> _sourceInfo(String input, bool Function() stop) async {
    if (stop()) throw TiniEditCancelled();
    final session = await FFprobeKit.executeWithArguments([
      '-v', 'error', '-show_entries', 'stream=index,codec_type,color_transfer,pix_fmt',
      '-of', 'json', input,
    ]);
    if (stop()) throw TiniEditCancelled();
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw await _TiniStageFailure.record('source audio', (await session.getOutput()) ?? '');
    }
    final data = jsonDecode((await session.getOutput()) ?? '{}') as Map;
    if (data['streams'] is! List) throw StateError('Invalid source audio probe');
    final streams = data['streams'] as List;
    final highDepth = streams.whereType<Map>().any((s) =>
        const {'smpte2084', 'arib-std-b67'}.contains(s['color_transfer']) ||
        RegExp(r'(?:9|10|12|14|16)(?:le|be)$').hasMatch('${s['pix_fmt']}'));
    return (audio: streams.whereType<Map>().any((s) => s['codec_type'] == 'audio'),
        highDepth: highDepth);
  }

  static TiniEditNode _streamCheckpoint(_TiniStreamNode plan) => TiniEditNode(
    stage: 'video.stream.checkpoint.v1',
    parameters: {'pipeline': plan.pipeline.identity,
      'filterThreads': Platform.numberOfProcessors.clamp(1, 4)},
    inputs: [plan.input], extension: 'mkv',
    render: (inputs, stop) async {
      final output = await _output('mkv');
      try {
        final hasAudio = !plan.pipeline.muted && (await _sourceInfo(inputs.single.path, stop)).audio;
        final compiled = await _compileStream(plan, inputs.single.path, stop);
        await _streamCommand(compiled.checkpoint(inputs.single.path, output, hasAudio),
            stop, 'effect checkpoint');
        return TiniEditArtifact(output, temporary: true);
      } catch (_) { try { await File(output).delete(); } on FileSystemException { /* Temporary output already removed. */ } rethrow; }
    },
  );

  static TiniEditNode _hardwareVideo(_TiniStreamNode plan, TiniVideoEncoder encoder,
      Duration duration, int width, int height, {required bool allowClipSoftwareFallback}) => TiniEditNode(
    stage: 'video.hardware.stream.v2',
    parameters: {'pipeline': plan.pipeline.identity, 'encoder': encoder.identity,
      'durationUs': duration.inMicroseconds, 'fps': 30, 'color': 'source',
      'container': 'mov', 'packetClock': 'N/(30*TB)', 'videoTimescale': 30,
      'filterThreads': Platform.numberOfProcessors.clamp(1, 4)},
    inputs: [plan.input], extension: 'mov',
    render: (inputs, stop) async {
      final output = await _output('mov');
      final video = '$output.h264', audio = '$output.audio.mka';
      final watch = Stopwatch()..start();
      var delivered = false;
      try {
        // Silence is selected only after proving that the source has no audio.
        // An encoder/filter failure must never be retried with muted audio.
        final sourceInfo = await _sourceInfo(inputs.single.path, stop);
        if (sourceInfo.highDepth) {
          throw StateError('Preserve the existing high-depth/HDR software color path');
        }
        final hasAudio = !plan.pipeline.muted && sourceInfo.audio;
        final compiled = await _compileStream(plan, inputs.single.path, stop);
        await _streamCommand(compiled.encode(
            inputs.single.path, video, audio, encoder, hasAudio), stop, 'hardware video');
        // Packet counting parses compressed H.264; it does not decode frames.
        // Reject a codec that drops frames or changes the requested geometry.
        final probe = await FFprobeKit.executeWithArguments([
          '-v', 'error', '-select_streams', 'v:0', '-count_packets',
          '-show_entries', 'stream=width,height,nb_read_packets,has_b_frames', '-of', 'json', video,
        ]);
        if (!ReturnCode.isSuccess(await probe.getReturnCode())) {
          throw StateError('Unable to validate hardware video');
        }
        final streams = (jsonDecode((await probe.getOutput()) ?? '{}') as Map)['streams'] as List?;
        if (streams == null || streams.length != 1) throw StateError('Missing hardware video track');
        final info = streams.single as Map;
        final packets = int.tryParse('${info['nb_read_packets']}') ?? 0;
        final expected = (duration.inMicroseconds * 30 / 1000000).round();
        if (info['width'] != width || info['height'] != height ||
            info['has_b_frames'] != 0 || packets <= 0 || (packets - expected).abs() > 1) {
          throw StateError('Hardware video changed dimensions, frame count, or frame order');
        }
        await _streamCommand(TiniVideoPipeline.mux(video, audio, output), stop, 'hardware mux');
        // Validate the sample-table clock before publishing/caching the result.
        // Some Android FFmpeg builds silently retain a vendor's default rate
        // or fail to rescale a bitstream filter's output time base.
        final delivery = await FFprobeKit.executeWithArguments([
          '-v', 'error', '-select_streams', 'v:0', '-show_entries',
          'stream=width,height,nb_frames,avg_frame_rate:format=duration', '-of', 'json', output,
        ]);
        if (stop()) throw TiniEditCancelled();
        if (!ReturnCode.isSuccess(await delivery.getReturnCode())) {
          throw StateError('Unable to validate delivery clock');
        }
        final deliveredInfo = jsonDecode((await delivery.getOutput()) ?? '{}') as Map;
        final deliveredVideo = (deliveredInfo['streams'] as List).single as Map;
        final rate = '${deliveredVideo['avg_frame_rate']}'.split('/');
        final numerator = rate.length == 2 ? double.tryParse(rate[0]) : null;
        final denominator = rate.length == 2 ? double.tryParse(rate[1]) : null;
        final deliveredDuration = double.tryParse('${(deliveredInfo['format'] as Map)['duration']}');
        if (deliveredVideo['width'] != width || deliveredVideo['height'] != height ||
            int.tryParse('${deliveredVideo['nb_frames']}') != packets ||
            numerator == null || denominator == null || denominator <= 0 ||
            !numerator.isFinite || !denominator.isFinite || (numerator / denominator - 30).abs() > .001 ||
            deliveredDuration == null || !deliveredDuration.isFinite ||
            (deliveredDuration - duration.inMicroseconds / 1000000).abs() > .035) {
          throw StateError('Hardware delivery changed the frame rate or duration');
        }
        developer.log('codec=${encoder.name} elapsedMs=${watch.elapsedMilliseconds}', name: 'TiniExport');
        delivered = true;
        return TiniEditArtifact(output, temporary: true,
            metadata: {'encoder': encoder.name, 'hardware': true, 'elapsedMs': watch.elapsedMilliseconds});
      } on TiniEditCancelled { rethrow; }
      catch (error, stack) {
        // Some vendor MediaCodec implementations report a different packet
        // count, geometry, or clock from the raw H.264 stream. Never publish
        // that unverified stream. Rebuild ONLY this clip from the same input
        // and unchanged filter graph using the proven software AVC path.
        // Other errors keep the existing complete-timeline fallback.
        final verificationFailure =
            error.toString().contains('Hardware video changed dimensions, frame count, or frame order') ||
            error.toString().contains('Hardware delivery changed the frame rate or duration');
        if (!verificationFailure || !allowClipSoftwareFallback) {
          throw _TiniStreamEncodingFailure(error);
        }
        if (stop()) throw TiniEditCancelled();
        developer.log('Hardware AVC result was rejected; trying verified software AVC for this clip',
            name: 'TiniExport.hardwareFallback', error: error, stackTrace: stack);
        try {
          // The MOV output may already contain an incomplete hardware mux.
          // Discard it before allowing a software encoder to reuse the path.
          try { await File(output).delete(); }
          on FileSystemException { /* No completed hardware output to retain. */ }
          final sourceAudio = await _sourceInfo(inputs.single.path, stop);
          final compiled = await _compileStream(plan, inputs.single.path, stop);
          await _streamCommand(compiled.software(
              inputs.single.path, output,
              !plan.pipeline.muted && sourceAudio.audio),
              stop, 'hardware-metadata software fallback');
          if (stop()) throw TiniEditCancelled();
          // A recovered clip must pass the same output contract. In particular
          // an empty/short video or silently removed audio is not a success.
          final check = await FFprobeKit.executeWithArguments([
            '-v', 'error', '-show_entries',
            'stream=codec_type,width,height,nb_frames,avg_frame_rate:format=duration',
            '-of', 'json', output,
          ]);
          if (!ReturnCode.isSuccess(await check.getReturnCode())) {
            throw StateError('Cannot verify software fallback video');
          }
          final report = jsonDecode((await check.getOutput()) ?? '{}') as Map;
          final streams = report['streams'];
          if (streams is! List) {
            throw StateError('Software fallback returned no streams');
          }
          final pictures = streams.whereType<Map>()
              .where((s) => s['codec_type'] == 'video').toList();
          final sound = streams.whereType<Map>()
              .where((s) => s['codec_type'] == 'audio').toList();
          if (pictures.length != 1 || sound.length != 1) {
            throw StateError('Software fallback changed audio/video stream count');
          }
          final picture = pictures.single;
          final rate = '${picture['avg_frame_rate']}'.split('/');
          final top = rate.length == 2 ? double.tryParse(rate.first) : null;
          final bottom = rate.length == 2 ? double.tryParse(rate.last) : null;
          final frameCount = int.tryParse('${picture['nb_frames']}');
          final seconds = double.tryParse('${(report['format'] as Map?)?['duration']}');
          final expectedFrames = (duration.inMicroseconds * 30 / 1000000).round();
          if (picture['width'] != width || picture['height'] != height ||
              top == null || bottom == null || bottom <= 0 ||
              !top.isFinite || !bottom.isFinite ||
              (top / bottom - 30).abs() > 0.01 ||
              frameCount == null || frameCount <= 0 ||
              (frameCount - expectedFrames).abs() > 1 ||
              seconds == null || !seconds.isFinite ||
              (seconds - duration.inMicroseconds / 1000000).abs() > 0.10) {
            throw StateError('Software fallback changed geometry, frame count, or duration');
          }
          if (stop()) throw TiniEditCancelled();
          delivered = true;
          developer.log('Validated software clip after hardware metadata failure: '
              '${watch.elapsedMilliseconds}ms', name: 'TiniExport.hardwareFallback');
          return TiniEditArtifact(output, temporary: true, metadata: {
            'encoder': 'libx264',
            'hardware': false,
            'fallback': 'hardware-metadata-validation',
            'elapsedMs': watch.elapsedMilliseconds,
          });
        } on TiniEditCancelled {
          rethrow;
        } catch (fallbackError, fallbackStack) {
          developer.log('Clip-local software AVC fallback failed; using existing timeline fallback',
              name: 'TiniExport.hardwareFallback',
              error: fallbackError, stackTrace: fallbackStack);
          throw _TiniStreamEncodingFailure(
              'hardware: $error; software: $fallbackError');
        }
      } finally {
        for (final path in [video, audio, if (!delivered) output]) {
          try { await File(path).delete(); } on FileSystemException { /* Already cleaned. */ }
        }
      }
    },
  );

  static TiniEditNode _softwareVideo(_TiniStreamNode plan, Duration duration) => TiniEditNode(
    stage: 'video.software.stream.v1',
    parameters: {'pipeline': plan.pipeline.identity, 'durationUs': duration.inMicroseconds,
      'crf': 18, 'fps': 30, 'filterThreads': Platform.numberOfProcessors.clamp(1, 4)},
    inputs: [plan.input], extension: 'mkv',
    render: (inputs, stop) async {
      final output = await _output('mkv');
      try {
        final hasAudio = !plan.pipeline.muted && (await _sourceInfo(inputs.single.path, stop)).audio;
        final compiled = await _compileStream(plan, inputs.single.path, stop);
        await _streamCommand(compiled.software(inputs.single.path, output, hasAudio),
            stop, 'software video stream');
        return TiniEditArtifact(output, temporary: true, metadata: {'hardware': false});
      } on TiniEditCancelled {
        try { await File(output).delete(); } on FileSystemException { /* Already removed. */ }
        rethrow;
      } catch (error) {
        try { await File(output).delete(); } on FileSystemException { /* Already removed. */ }
        throw _TiniStreamEncodingFailure(error);
      }
    },
  );
  static String _number(num value) => value.toStringAsFixed(6);
  static Future<String> _output(String extension) async {
    final dir = await getTemporaryDirectory();
    await dir.create(recursive: true);
    final folder = await dir.createTemp('tini_stage_');
    return '${folder.path}/stage.$extension';
  }

  static Future<void> _command(
    String command,
    bool Function() cancelled, {
    String? fallback,
    String stage = 'الفيديو',
  }) async {
    if (cancelled()) throw TiniEditCancelled();
    var session = await VideoProcessor._executeBounded(command);
    if (!ReturnCode.isSuccess(await session.getReturnCode()) &&
        fallback != null &&
        !cancelled()) {
      session = await VideoProcessor._executeBounded(fallback);
    }
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw await _TiniStageFailure.record(
        stage,
        (await session.getAllLogsAsString()) ?? '',
      );
    }
  }

  static Map<String, Object?> _speed(CropClip c) => {
    'curve': c.speed.isCurve,
    'normal': c.speed.normal,
    'points': [
      for (final p in c.speed.points) [p.at, p.speed],
    ],
  };
  static Map<String, Object?> _fx(TiniAppliedEffect f) => {
    'id': f.id,
    'start': f.startSeconds,
    'end': f.endSeconds,
  };
  static Map<String, Object?>? _cutout(CutoutSettings? c) => c == null
      ? null
      : {
          'masks': c.maskDirectory,
          'startUs': c.sourceStart.inMicroseconds,
          'fps': c.framesPerSecond,
          'count': c.frameCount,
          'manual': c.manualMask,
          'strokes': [
            for (final s in c.strokes)
              {
                'erase': s.erase,
                'quick': s.quick,
                'radius': s.radius,
                'points': [
                  for (final p in s.points) [p.dx, p.dy],
                ],
              },
          ],
          'chroma': c.chromaEnabled,
          'color': c.chromaColor,
          'similarity': c.chromaSimilarity,
          'blend': c.chromaBlend,
          'draft': c.chromaDraftEnabled,
          'passes': [
            for (final p in c.chromaPasses) [p.color, p.similarity, p.blend],
          ],
          'feather': c.edgeFeather,
          'edge': c.edgeStyle.name,
          'edgeColor': c.edgeColor,
          'edgeSize': c.edgeSize,
          'edgeDistance': c.edgeDistance,
          'edgeOpacity': c.edgeOpacity,
        };
  static Map<String, Object?> describe(CropClip c) => {
    'startUs': c.startTime.inMicroseconds,
    'endUs': c.endTime.inMicroseconds,
    'source': c.replacementPath,
    'replacementStartUs': c.replacementStartTime.inMicroseconds,
    'speed': _speed(c),
    'mute': c.isMuted,
    'rotation': c.rotationQuarterTurns % 4,
    'background': c.backgroundPath,
    'cutout': _cutout(c.cutout),
    'magic': c.magicEffectId,
    'animations': [
      c.animations.start,
      c.animations.startSeconds,
      c.animations.end,
      c.animations.endSeconds,
      c.animations.group,
      c.animations.groupSeconds,
    ],
    'effects': c.videoEffects.map(_fx).toList(),
    'grade': [c.colorFilter.id, c.colorFilter.intensity, c.colorFilter.ffmpeg],
    'retouch': [c.retouch.smooth, c.retouch.teeth],
  };

  static TiniEditNode _filter(
    _TiniPipelineContext? context,
    TiniEditNode input,
    String stage,
    Object? parameters,
    List<String> graph,
  ) {
    if (context != null && TiniVideoPipeline.accepts(graph)) {
      final previous = _streams[input];
      final plan = _TiniStreamNode(previous?.input ?? input,
          (previous?.pipeline ?? TiniVideoPipeline.source(context.duration))
              .then(stage, parameters, graph));
      final node = _streamCheckpoint(plan);
      _streams[node] = plan;
      return node;
    }
    return TiniEditNode(
    stage: stage,
    parameters: parameters,
    inputs: [input],
    extension: 'mkv',
    render: (i, cancelled) async {
      final output = await _output('mkv');
      try {
        await _command(
          '-i "${i[0].path}" -filter_complex "[0:v]null[src];${graph.join(';')}" '
          '-map "[dst]" -map 0:a? -c:v ffv1 -level 3 -c:a copy -fps_mode passthrough -y "$output"',
          cancelled,
          stage: stage,
        );
        return TiniEditArtifact(output, temporary: true);
      } catch (_) {
        try {
          await File(output).delete();
        } catch (_) {}
        rethrow;
      }
    },
    );
  }

  static Future<TiniEditNode> clip(
    String original,
    CropClip c,
    int width,
    int height,
    TiniVideoEncoder? encoder,
    bool legacyVideo, {
    bool allowClipSoftwareFallback = false,
    bool deliverComposedBackground = false,
  }) async {
    final context = legacyVideo ? null : _TiniPipelineContext(encoder, c.playbackDuration);
    final source = await cache.source(c.replacementPath ?? original);
    var ready = source;
    var start = c.replacementPath == null
        ? c.startTime
        : c.replacementStartTime;
    final seconds = c.playbackDuration.inMicroseconds / 1000000.0;
    if (c.cutout != null || c.backgroundPath != null) {
      final parents = <TiniEditNode>[source];
      if (c.backgroundPath?.isNotEmpty == true) {
        parents.add(await cache.source(c.backgroundPath!));
      }
      if (c.cutout?.hasMask == true) {
        parents.add(await cache.source(c.cutout!.maskDirectory));
      }
      final begin = start;
      final cutoutParameters = _cutout(c.cutout);
      cutoutParameters?.remove('masks');
      ready = TiniEditNode(
        stage: 'background.v1',
        parameters: {
          'cutout': cutoutParameters,
          'startUs': begin.inMicroseconds,
          'durationUs': c.duration.inMicroseconds,
          'size': [width, height],
        },
        inputs: parents,
        render: (i, stop) async {
          if (stop()) throw TiniEditCancelled();
          final p = await CropBackgroundEngine.composeClip(
            source: i[0].path,
            sourceStart: begin,
            clip: c,
            width: width,
            height: height,
            useCache: false,
          );
          return TiniEditArtifact(p, temporary: p != i[0].path);
        },
      );
      start = Duration.zero;
      // CropBackgroundEngine has already created the finished 30-fps H.264
      // picture and AAC audio. For a background-only clip there are NO more
      // video operations: re-encoding through Exynos MediaCodec and then
      // remuxing with Media3 risks corrupting the already-valid bitstream.
      // The caller explicitly proves the absence of downstream operations.
      if (deliverComposedBackground) return ready;
    }
    final begin = start;
    final timingInput = ready;
    // Background composition has already trimmed the source, assigned a
    // 30-fps clock and muxed its audio. Passing that MP4 through the generic
    // FFV1 timing stage would decode and encode the entire cutout AGAIN.
    // Keep the original timing path for speed curves, mute, other clips and
    // legacy rendering; do not change any visual operator or its ordering.
    final backgroundIsTimed = context != null &&
        (c.cutout != null || c.backgroundPath != null) &&
        c.speed.isDefault && !c.isMuted;
    ready = backgroundIsTimed ? ready : TiniEditNode(
      stage: 'cut.speed.audio.lossless.v1',
      parameters: {
        'startUs': begin.inMicroseconds,
        'durationUs': c.duration.inMicroseconds,
        'speed': _speed(c),
        'muted': c.isMuted,
      },
      inputs: [ready],
      extension: 'mkv',
      render: (i, stop) async {
        final output = await _output('mkv');
        try {
          final base = CropClip(
            id: 'cache-timing',
            startTime: c.startTime,
            endTime: c.endTime,
            startFraction: c.startFraction,
            endFraction: c.endFraction,
            speed: c.speed,
            isMuted: c.isMuted,
          );
          if (!c.speed.isDefault) {
            String cmd(bool audio) => VideoProcessor._speedRenderCommand(
              clip: base,
              source: i[0].path,
              start: begin,
              width: width,
              height: height,
              output: output,
              useSourceAudio: audio,
              lossless: true,
            );
            await _command(
              cmd(!c.isMuted),
              stop,
              fallback: c.isMuted ? null : cmd(false),
            );
          } else {
            final duration = _number(c.duration.inMicroseconds / 1000000);
            final input =
                '-ss ${VideoProcessor._formatDuration(begin)} -t $duration -i "${i[0].path}" '
                '-f lavfi -t $duration -i anullsrc=channel_layout=stereo:sample_rate=44100';
            final encode =
                '-map 0:v:0 -vf "setpts=PTS-STARTPTS,fps=30" '
                '-af "asetpts=PTS-STARTPTS,aresample=44100" -c:v ffv1 -level 3 '
                '-c:a pcm_s16le -ar 44100 -ac 2 -t $duration -y "$output"';
            await _command(
              '$input -map ${c.isMuted ? '1' : '0'}:a:0 $encode',
              stop,
              fallback: c.isMuted ? null : '$input -map 1:a:0 $encode',
            );
          }
          return TiniEditArtifact(output, temporary: true);
        } catch (_) {
          try {
            await File(output).delete();
          } catch (_) {}
          rethrow;
        }
      },
    );
    if (context != null && c.speed.isDefault && !backgroundIsTimed) {
      // Match _formatDuration's centisecond seek exactly; changing seek
      // precision here can select another source frame and shift the audio.
      final seek = Duration(microseconds: (begin.inMicroseconds ~/ 10000) * 10000);
      _streams[ready] = _TiniStreamNode(timingInput,
          TiniVideoPipeline.trim(seek, c.duration, c.isMuted));
    }
    if (c.magicEffectId != null) {
      ready = _filter(context,
        ready,
        'magic.v1',
        {
          'id': c.magicEffectId,
          'size': [width, height],
          'seconds': seconds,
        },
        CropMagicEffects.filterGraph(
          input: 'src',
          output: 'dst',
          id: c.magicEffectId,
          seconds: seconds,
          width: width,
          height: height,
        ),
      );
    }
    for (final animation in [
      CropAnimationSettings(
        start: c.animations.start,
        startSeconds: c.animations.startSeconds,
      ),
      CropAnimationSettings(
        end: c.animations.end,
        endSeconds: c.animations.endSeconds,
      ),
      CropAnimationSettings(
        group: c.animations.group,
        groupSeconds: c.animations.groupSeconds,
      ),
    ]) {
      if (!animation.hasEffects) continue;
      final graph = CropAnimationFilters.filterGraph(
        input: 'src',
        output: 'dst',
        settings: animation,
        seconds: seconds,
        width: width,
        height: height,
      );
      ready = _filter(context, ready, 'animation.v1', {
        'graph': graph,
        'size': [width, height],
        'seconds': seconds,
      }, graph);
    }
    final generic = c.videoEffects
        .where(
          (fx) =>
              !TiniVibeEffectsExport.hasVibe([fx]) &&
              !TiniBodyFxEngine.hasBodyEffects([fx]) &&
              !TiniSledEffect.hasEffect([fx]) &&
              !TiniFaceSceneFx.hasDog([fx]),
        )
        .toList();
    if (generic.isNotEmpty) {
      final full = TiniEffectsRender.filterGraph(
        input: 'src',
        output: 'dst',
        effects: generic,
        seconds: seconds,
        width: width,
        height: height,
      );
      final preparation = full.first;
      if (preparation.endsWith('[te_source]')) {
        final graph = [preparation.replaceFirst('[te_source]', '[dst]')];
        ready = _filter(context, ready, 'effect.input.v1', {'graph': graph}, graph);
      }
      for (final fx in generic) {
        final graph = TiniEffectsRender.filterGraph(
          input: 'src',
          output: 'dst',
          effects: [fx],
          seconds: seconds,
          width: width,
          height: height,
        );
        if (graph.first.endsWith('[te_source]')) {
          graph[0] = '[src]null[te_source]';
        }
        ready = _filter(context, ready, 'effect.v1', {
          'effect': _fx(fx),
          'size': [width, height],
          'seconds': seconds,
        }, graph);
      }
    }
    ready = _filter(context,
      ready,
      'canvas.fps.v1',
      {
        'size': [width, height],
        'fps': 30,
      },
      [
        '[src]scale=$width:$height:force_original_aspect_ratio=decrease,'
            'pad=$width:$height:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p[dst]',
      ],
    );
    for (final fx in c.videoEffects.where(
      (f) => TiniVibeEffectsExport.hasVibe([f]),
    )) {
      ready = TiniEditNode(
        stage: 'vibe.v1',
        parameters: {
          'effect': _fx(fx),
          'size': [width, height],
          'seconds': seconds,
        },
        inputs: [ready],
        extension: 'mkv',
        render: (i, stop) async {
          if (stop()) throw TiniEditCancelled();
          final p = await TiniVibeEffectsExport.compose(
            inputPath: i[0].path,
            effects: [fx],
            seconds: seconds,
            width: width,
            height: height,
            lossless: true,
            cancelled: stop,
          );
          return TiniEditArtifact(p, temporary: p != i[0].path);
        },
      );
    }
    for (final fx in c.videoEffects.where(
      (f) => TiniBodyFxEngine.hasBodyEffects([f]),
    )) {
      ready = TiniEditNode(
        stage: 'body.v1',
        parameters: {
          'effect': _fx(fx),
          'size': [width, height],
          'startUs':
              (c.replacementPath == null ? c.startTime : c.replacementStartTime)
                  .inMicroseconds,
          'durationUs': c.duration.inMicroseconds,
          'speed': _speed(c),
        },
        inputs: [ready, source],
        extension: 'mkv',
        render: (i, stop) async {
          if (stop()) throw TiniEditCancelled();
          final frames = await TiniBodyFxEngine.prepare(
            clip: c.copyWith(videoEffects: [fx]),
            source: i[1].path,
            cancelled: stop,
            sourceStart: c.replacementPath == null
                ? c.startTime
                : c.replacementStartTime,
          );
          try {
            if (stop()) throw TiniEditCancelled();
            final p = await TiniBodyFxEngine.compose(
              renderedPath: i[0].path,
              frames: frames,
              width: width,
              height: height,
              lossless: true,
            );
            return TiniEditArtifact(p, temporary: p != i[0].path);
          } finally {
            await frames.dispose();
          }
        },
      );
    }
    for (final dog in [false, true]) {
      for (final fx in c.videoEffects.where(
        (f) =>
            dog ? TiniFaceSceneFx.hasDog([f]) : TiniSledEffect.hasEffect([f]),
      )) {
        final proxy = TiniEditNode(
          stage: 'native.analysis.proxy.v1',
          parameters: {
            'size': [width, height],
          },
          inputs: [ready],
          render: (i, stop) async {
            final out = await _output('mp4');
            try {
              await _command(
                '-i "${i[0].path}" -an -c:v libx264 -preset veryfast -crf 18 '
                '-pix_fmt yuv420p -movflags +faststart -y "$out"',
                stop,
              );
              return TiniEditArtifact(out, temporary: true);
            } catch (_) {
              try {
                await File(out).delete();
              } catch (_) {}
              rethrow;
            }
          },
        );
        final scene = await cache.source(
          dog
              ? await TiniFaceSceneFx.dogSceneFile()
              : await TiniSledEffect.sceneFile(),
        );
        ready = TiniEditNode(
          stage: dog ? 'dog.v1' : 'sled.v1',
          parameters: {
            'effect': _fx(fx),
            'size': [width, height],
            'seconds': seconds,
          },
          inputs: [ready, proxy, scene],
          extension: 'mkv',
          render: (i, stop) async {
            if (stop()) throw TiniEditCancelled();
            final p = dog
                ? await TiniFaceSceneExport.composeDog(
                    inputPath: i[0].path,
                    effects: [fx],
                    width: width,
                    height: height,
                    seconds: seconds,
                    lossless: true,
                    analysisInputPath: i[1].path,
                    cancelled: stop,
                  )
                : await TiniSledExport.compose(
                    inputPath: i[0].path,
                    effects: [fx],
                    width: width,
                    height: height,
                    seconds: seconds,
                    lossless: true,
                    analysisInputPath: i[1].path,
                    cancelled: stop,
                  );
            return TiniEditArtifact(p, temporary: p != i[0].path);
          },
        );
      }
    }
    if (c.colorFilter.enabled) {
      ready = _filter(context,
        ready,
        'grade.v1',
        {'filter': c.colorFilter.ffmpeg},
        ['[src]${c.colorFilter.ffmpeg},format=bgra[dst]'],
      );
    }
    for (final smoothing in [true, false]) {
      final settings = CropRetouchSettings(
        smooth: smoothing ? c.retouch.smooth : 0,
        teeth: smoothing ? 0 : c.retouch.teeth,
      );
      if (!settings.enabled) continue;
      final geometryInputKey = ready.key;
      ready = TiniEditNode(
        stage: smoothing ? 'skin.v1' : 'teeth.v1',
        parameters: {
          'strength': smoothing ? settings.smooth : settings.teeth,
          'size': [width, height],
          'durationMs': c.playbackDuration.inMilliseconds,
        },
        inputs: [ready],
        extension: 'mkv',
        render: (i, stop) async {
          final r = await CropRetouchEngine.render(
            sourceCacheKey: geometryInputKey,
            input: i[0].path,
            settings: settings,
            durationMs: c.playbackDuration.inMilliseconds,
            width: width,
            height: height,
            lossless: true,
            useCache: false,
            cancelled: stop,
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
    }
    if (c.rotationQuarterTurns % 4 != 0) {
      ready = _filter(context,
        ready,
        'rotation.v1',
        {'turns': c.rotationQuarterTurns % 4, 'size': [width, height]},
        ['[src]${CropRotation.ffmpeg(c.rotationQuarterTurns, width, height)}'
          '${context != null && c.colorFilter.enabled && !c.retouch.enabled ? ',format=bgra' : ''}[dst]'],
      );
    }
    if (context != null) {
      final plan = _streams[ready] ?? _TiniStreamNode(ready, TiniVideoPipeline.source(c.playbackDuration));
      return context.encoder == null
          ? _softwareVideo(plan, c.playbackDuration)
          : _hardwareVideo(plan, context.encoder!, c.playbackDuration, width, height,
              allowClipSoftwareFallback: allowClipSoftwareFallback);
    }
    return TiniEditNode(
      stage: 'clip.delivery.video.v1',
      parameters: {
        'size': [width, height],
        'crf': 18,
        'fps': 30,
        'bframes': 0,
      },
      inputs: [ready],
      extension: 'mkv',
      render: (i, stop) async {
        final out = await _output('mkv');
        try {
          await _command(
            '-i "${i[0].path}" -map 0:v:0 -map 0:a? '
            '-c:v libx264 -preset veryfast -crf 18 -bf 0 -pix_fmt yuv420p -c:a copy -y "$out"',
            stop,
          );
          return TiniEditArtifact(out, temporary: true);
        } catch (_) {
          try {
            await File(out).delete();
          } catch (_) {}
          rethrow;
        }
      },
    );
  }

  /// Media3 owns straightforward trim/split/reorder/mute/constant-speed timelines. Every
  /// specialised Tini effect still uses the original complete renderer.
  static bool _media3DirectTimelineEligible(List<CropClip> clips) =>
      Platform.isAndroid && clips.isNotEmpty && clips.every((c) =>
          c.duration.inMilliseconds > 0 &&
          !c.speed.isCurve && c.speed.normal.isFinite &&
          c.speed.normal >= 0.1 && c.speed.normal <= 10 &&
          !c.colorFilter.enabled &&
          !c.retouch.enabled && c.cutout == null &&
          c.backgroundPath == null && c.magicEffectId == null &&
          !c.animations.hasEffects && c.videoEffects.isEmpty &&
          c.rotationQuarterTurns % 4 == 0 &&
          (c.replacementPath == null || c.replacementPath!.isNotEmpty));

  static Future<bool> _media3SourceCompatible(
      String path, int width, int height) async {
    if (!path.toLowerCase().endsWith('.mp4') || !await File(path).exists()) {
      return false;
    }
    final checked = await FFprobeKit.executeWithArguments([
      '-v', 'error', '-show_entries',
      'stream=codec_type,codec_name,width,height,pix_fmt,avg_frame_rate,color_transfer:'
          'stream_tags=rotate:stream_side_data=rotation:format=duration',
      '-of', 'json', path,
    ]);
    if (!ReturnCode.isSuccess(await checked.getReturnCode())) return false;
    final parsed = jsonDecode((await checked.getOutput()) ?? '{}') as Map;
    final streams = parsed['streams'];
    if (streams is! List) return false;
    final videos = streams.whereType<Map>()
        .where((s) => s['codec_type'] == 'video').toList();
    if (videos.length != 1) return false;
    final v = videos.single;
    final fps = '${v['avg_frame_rate']}'.split('/');
    if (fps.length != 2) return false;
    final numerator = double.tryParse(fps[0]);
    final denominator = double.tryParse(fps[1]);
    if (numerator == null || denominator == null || denominator <= 0 ||
        (numerator / denominator - 30).abs() > 0.001 ||
        v['codec_name'] != 'h264' || v['width'] != width ||
        v['height'] != height || v['pix_fmt'] != 'yuv420p' ||
        const {'smpte2084', 'arib-std-b67'}.contains(v['color_transfer'])) {
      return false;
    }
    if ((v['tags'] is Map && '${(v['tags'] as Map)['rotate'] ?? '0'}' != '0') ||
        (v['side_data_list'] is List &&
            (v['side_data_list'] as List).whereType<Map>()
                .any((s) => s['rotation'] != null && s['rotation'] != 0))) {
      return false;
    }
    final audio = streams.whereType<Map>()
        .where((s) => s['codec_type'] == 'audio').toList();
    return audio.length <= 1 &&
        audio.every((stream) => stream['codec_name'] == 'aac');
  }

  static Future<String?> _tryMedia3DirectTimeline({
    required String originalPath,
    required List<CropClip> clips,
    required int width,
    required int height,
    bool Function()? cancelled,
  }) async {
    if (!_media3DirectTimelineEligible(clips)) return null;
    if (cancelled?.call() == true) throw TiniEditCancelled();
    String? output;
    try {
      if (!await TiniMedia3Export.isAvailable()) return null;
      final paths = <String>{
        for (final c in clips) c.replacementPath ?? originalPath,
      };
      for (final path in paths) {
        if (!await _media3SourceCompatible(path, width, height)) return null;
      }
      if (cancelled?.call() == true) throw TiniEditCancelled();
      final segments = [
        for (final c in clips)
          TiniMedia3Segment(
            inputPath: c.replacementPath ?? originalPath,
            start: c.replacementPath == null
                ? c.startTime : c.replacementStartTime,
            end: (c.replacementPath == null
                ? c.startTime : c.replacementStartTime) + c.duration,
            mute: c.isMuted,
            speed: c.speed.normal,
          ),
      ];
      final job = segments.length == 1 && !segments.single.mute &&
              (segments.single.speed - 1.0).abs() < 0.00001
          ? TiniMedia3Export.start(
              inputPath: segments.single.inputPath,
              start: segments.single.start,
              end: segments.single.end,
            )
          : TiniMedia3Export.startTimeline(segments: segments);
      var cancelledJob = false;
      final timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (!cancelledJob && cancelled?.call() == true) {
          cancelledJob = true;
          unawaited(job.cancel().catchError((Object error) {
            developer.log('Media3 cancellation failed',
                name: 'TiniMedia3', error: error);
            return false;
          }));
        }
      });
      try {
        output = await job.result;
      } finally {
        timer.cancel();
      }
      if (cancelled?.call() == true) throw TiniEditCancelled();
      if (output == null || !await File(output).exists() ||
          await File(output).length() == 0) {
        throw StateError('Media3 did not produce a complete timeline');
      }
      final verify = await FFprobeKit.executeWithArguments([
        '-v', 'error', '-show_entries',
        'stream=codec_type,width,height,avg_frame_rate:format=duration',
        '-of', 'json', output,
      ]);
      if (!ReturnCode.isSuccess(await verify.getReturnCode())) {
        throw StateError('Media3 output metadata could not be verified');
      }
      final data = jsonDecode((await verify.getOutput()) ?? '{}') as Map;
      final streams = data['streams'];
      if (streams is! List) throw StateError('Media3 output has no streams');
      final video = streams.whereType<Map>()
          .where((s) => s['codec_type'] == 'video').toList();
      final duration = double.tryParse(
          '${(data['format'] as Map?)?['duration']}');
      final expected = clips.fold<int>(0,
          (total, c) => total + c.playbackDuration.inMicroseconds) / 1000000.0;
      final rate = video.isEmpty ? const <String>[] :
          '${video.single['avg_frame_rate']}'.split('/');
      final rateNumerator = rate.length == 2 ? double.tryParse(rate[0]) : null;
      final rateDenominator = rate.length == 2 ? double.tryParse(rate[1]) : null;
      final frameRateGood = rateNumerator != null &&
          rateDenominator != null && rateDenominator > 0 &&
          (rateNumerator / rateDenominator - 30).abs() <= 0.2;
      if (video.length != 1 || video.single['width'] != width ||
          video.single['height'] != height || !frameRateGood ||
          !streams.whereType<Map>().any((s) => s['codec_type'] == 'audio') ||
          duration == null || !duration.isFinite ||
          (duration - expected).abs() > 0.12) {
        throw StateError('Media3 changed timeline dimensions, duration or audio');
      }
      // This is an already encoded, complete MP4. The existing edit cache
      // stores it as a snapshot; no second compression is performed here.
      return output;
    } on TiniEditCancelled {
      rethrow;
    } catch (error, stack) {
      if (cancelled?.call() == true) throw TiniEditCancelled();
      developer.log('Media3 timeline rejected; retaining complete Tini renderer',
          name: 'TiniMedia3', error: error, stackTrace: stack);
      if (output != null) {
        try { await File(output).delete(); } on FileSystemException {}
      }
      return null;
    }
  }

  /// Apply one *new* colour grade over the last completed edit using GPU.
  /// A native failure runs the exact previous FFmpeg grade on the same input;
  /// earlier retouch/magic/background stages are not re-evaluated.
  static TiniEditNode _incrementalGradeOnMedia3(
    TiniEditNode input,
    CropFilterSelection selection,
    int width,
    int height,
  ) => TiniEditNode(
    stage: 'editor.incremental.grade.media3.v2',
    parameters: {
      'grade': selection.ffmpeg,
      'matrix': selection.filter!.matrix(selection.intensity),
      'size': [width, height],
      'fps': 30,
    },
    inputs: [input],
    extension: 'mp4',
    render: (files, stop) async {
      if (stop()) throw TiniEditCancelled();
      final source = files.single.path;
      String? nativeOutput;
      if (Platform.isAndroid &&
          await _media3SourceCompatible(source, width, height)) {
        try {
          if (await TiniMedia3Export.isAvailable()) {
            final job = TiniMedia3Export.start(
              inputPath: source,
              colorMatrix: selection.filter!.matrix(selection.intensity),
            );
            var cancelledJob = false;
            final timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
              if (!cancelledJob && stop()) {
                cancelledJob = true;
                unawaited(job.cancel().catchError((Object error) {
                  developer.log('Media3 grade cancellation failed',
                      name: 'TiniMedia3', error: error);
                  return false;
                }));
              }
            });
            try {
              nativeOutput = await job.result;
            } finally {
              timer.cancel();
            }
            if (stop()) throw TiniEditCancelled();
            if (nativeOutput != null &&
                await _media3SourceCompatible(nativeOutput, width, height)) {
              return TiniEditArtifact(nativeOutput, temporary: true);
            }
            throw StateError('Media3 GPU grade did not preserve output metadata');
          }
        } on TiniEditCancelled {
          if (nativeOutput != null) {
            try { await File(nativeOutput).delete(); } on FileSystemException {}
          }
          rethrow;
        } catch (error, stack) {
          developer.log('Media3 colour grade failed; using original FFmpeg grade',
              name: 'TiniMedia3', error: error, stackTrace: stack);
          if (nativeOutput != null) {
            try { await File(nativeOutput).delete(); } on FileSystemException {}
          }
          if (stop()) throw TiniEditCancelled();
        }
      }
      final output = await _output('mp4');
      try {
        final grade = selection.ffmpeg;
        await _command(
          '-i "$source" -filter_complex '
          '"[0:v]null[src];[src]$grade,format=yuv420p[dst]" '
          '-map "[dst]" -map 0:a? -c:v libx264 -preset veryfast '
          '-crf 18 -pix_fmt yuv420p -c:a copy '
          '-movflags +faststart -y "$output"',
          stop, stage: 'editor.incremental.grade.software.fallback',
        );
        if (stop()) throw TiniEditCancelled();
        return TiniEditArtifact(output, temporary: true);
      } catch (_) {
        try { await File(output).delete(); } on FileSystemException {}
        rethrow;
      }
    },
  );

  /// GPU shortcut only for a complete untrimmed SDR MP4 with a colour filter.
  /// The existing complex graph remains authoritative for every other case.
  static bool _gpuColorEligible(CropClip c) =>
      Platform.isAndroid &&
      c.colorFilter.enabled &&
      !c.isMuted &&
      c.startTime == Duration.zero &&
      c.startFraction == 0 &&
      c.endFraction == 1 &&
      c.replacementPath == null &&
      c.speed.isDefault &&
      c.cutout == null &&
      c.backgroundPath == null &&
      c.magicEffectId == null &&
      !c.animations.hasEffects &&
      c.videoEffects.isEmpty &&
      !c.retouch.enabled &&
      c.rotationQuarterTurns % 4 == 0;

  static Future<String?> _tryGpuColorOnly({
    required String inputPath,
    required CropClip clip,
    required int width,
    required int height,
    bool Function()? cancelled,
  }) async {
    if (!_gpuColorEligible(clip) ||
        !inputPath.toLowerCase().endsWith('.mp4')) {
      return null;
    }
    if (cancelled?.call() == true) throw TiniEditCancelled();
    try {
      if (!await TiniMedia3Export.isAvailable()) return null;
      final sourceProbe = await FFprobeKit.executeWithArguments([
        '-v', 'error', '-show_entries',
        'stream=codec_type,codec_name,width,height,pix_fmt,avg_frame_rate,color_transfer:'
            'stream_tags=rotate:stream_side_data=rotation:format=duration',
        '-of', 'json', inputPath,
      ]);
      if (!ReturnCode.isSuccess(await sourceProbe.getReturnCode())) {
        return null;
      }
      final sourceInfo = jsonDecode((await sourceProbe.getOutput()) ?? '{}') as Map;
      final sourceStreams = sourceInfo['streams'];
      if (sourceStreams is! List) return null;
      final videos = sourceStreams.whereType<Map>()
          .where((stream) => stream['codec_type'] == 'video').toList();
      if (videos.length != 1) return null;
      final video = videos.single;
      if (video['width'] != width || video['height'] != height ||
          video['codec_name'] != 'h264' ||
          video['pix_fmt'] != 'yuv420p' ||
          const {'smpte2084', 'arib-std-b67'}.contains(video['color_transfer']) ||
          sourceStreams.whereType<Map>().where((s) =>
              s['codec_type'] == 'audio').length != 1 ||
          !sourceStreams.whereType<Map>().any((s) =>
              s['codec_type'] == 'audio' && s['codec_name'] == 'aac')) {
        return null;
      }
      final rotation = (video['tags'] is Map)
          ? '${(video['tags'] as Map)['rotate'] ?? '0'}' : '0';
      if (rotation != '0' ||
          (video['side_data_list'] is List &&
              (video['side_data_list'] as List).whereType<Map>().any((s) =>
                  s['rotation'] != null && s['rotation'] != 0))) {
        return null;
      }
      bool fps30(Object? value) {
        final pieces = '$value'.split('/');
        if (pieces.length != 2) return false;
        final num = double.tryParse(pieces[0]);
        final den = double.tryParse(pieces[1]);
        return num != null && den != null && den > 0 &&
            (num / den - 30).abs() < 0.001;
      }
      if (!fps30(video['avg_frame_rate'])) return null;
      final sourceDuration = double.tryParse(
          '${(sourceInfo['format'] as Map?)?['duration']}');
      final expected = clip.playbackDuration.inMicroseconds / 1000000.0;
      if (sourceDuration == null || !sourceDuration.isFinite ||
          (sourceDuration - expected).abs() > 0.06) {
        return null;
      }
      if (cancelled?.call() == true) throw TiniEditCancelled();
      final matrix = clip.colorFilter.filter!.matrix(clip.colorFilter.intensity);
      final node = TiniEditNode(
        stage: 'media3.gpu.color.sdr.v1',
        parameters: {
          'matrix': matrix,
          'size': [width, height],
          'fps': 30,
          'color': 'bt709-lut33',
          'durationUs': clip.playbackDuration.inMicroseconds,
        },
        inputs: [await cache.source(inputPath)],
        extension: 'mp4',
        render: (inputs, stop) async {
          if (stop()) throw TiniEditCancelled();
          final job = TiniMedia3Export.start(
            inputPath: inputs.single.path,
            colorMatrix: matrix,
          );
          var cancelledJob = false;
          final timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
            if (!cancelledJob && stop()) {
              cancelledJob = true;
              unawaited(job.cancel().then<void>((_) {}).catchError(
                (Object error, StackTrace stack) {
                  developer.log('GPU cancellation failed', name: 'TiniExport',
                      error: error, stackTrace: stack);
                },
              ));
            }
          });
          String? resultPath;
          try {
            resultPath = await job.result;
            if (stop()) throw TiniEditCancelled();
            final resultFile = File(resultPath);
            if (!await resultFile.exists() || await resultFile.length() == 0) {
              throw StateError('GPU export produced empty media');
            }
            final verified = await FFprobeKit.executeWithArguments([
              '-v', 'error', '-show_entries',
              'stream=codec_type,width,height,avg_frame_rate:'
                  'format=duration',
              '-of', 'json', resultPath,
            ]);
            if (!ReturnCode.isSuccess(await verified.getReturnCode())) {
              throw StateError('Cannot verify GPU export');
            }
            final report = jsonDecode((await verified.getOutput()) ?? '{}') as Map;
            final streams = report['streams'];
            if (streams is! List) throw StateError('No GPU output streams');
            final outputVideo = streams.whereType<Map>()
                .where((s) => s['codec_type'] == 'video').toList();
            final duration = double.tryParse(
                '${(report['format'] as Map?)?['duration']}');
            if (outputVideo.length != 1 ||
                outputVideo.single['width'] != width ||
                outputVideo.single['height'] != height ||
                !fps30(outputVideo.single['avg_frame_rate']) ||
                !streams.whereType<Map>().any((s) =>
                    s['codec_type'] == 'audio') ||
                duration == null || !duration.isFinite ||
                (duration - expected).abs() > 0.06) {
              throw StateError('GPU export did not preserve video/audio metadata');
            }
            if (stop()) throw TiniEditCancelled();
            return TiniEditArtifact(resultPath, temporary: true);
          } catch (_) {
            if (resultPath != null) {
              try { await File(resultPath).delete(); }
              on FileSystemException { /* Failed output already removed. */ }
            }
            rethrow;
          } finally {
            timer.cancel();
          }
        },
      );
      return (await cache.run(node, cancelled: cancelled)).path;
    } on TiniEditCancelled {
      rethrow;
    } catch (error, stack) {
      developer.log('Media3 colour GPU fallback to existing graph',
          name: 'TiniExport', error: error, stackTrace: stack);
      return null;
    }
  }

  /// Compare complete project snapshots, excluding exactly one operation.
  /// Do not infer an edit order from UI clip identifiers or object identity.
  static bool _sameExcept(CropClip before, CropClip after, String field) {
    final oldSettings = Map<String, Object?>.from(describe(before))..remove(field);
    final newSettings = Map<String, Object?>.from(describe(after))..remove(field);
    return TiniEditCache.digest(oldSettings) ==
        TiniEditCache.digest(newSettings);
  }

  /// Only additions of previously disabled face operations are composable.
  /// Skin always precedes teeth; editing an already-active amount, disabling
  /// retouch or adding skin *after* teeth must rebuild the canonical graph.
  /// Different clips retain independent strengths and project-time offsets.
  static List<CropRetouchSegment>? _additionalRetouch(
    List<CropClip> before,
    List<CropClip> after, {
    bool chronological = false,
  }) {
    if (before.length != after.length) return null;
    final regions = <CropRetouchSegment>[];
    var elapsedUs = 0;
    var changed = false;
    for (var index = 0; index < before.length; index++) {
      final oldClip = before[index];
      final newClip = after[index];
      if (!_sameExcept(oldClip, newClip, 'retouch')) return null;
      final old = oldClip.retouch;
      final next = newClip.retouch;
      if ((old.smooth > 0 && next.smooth != old.smooth) ||
          (old.teeth > 0 && next.teeth != old.teeth) ||
          next.smooth < old.smooth ||
          next.teeth < old.teeth ||
          // Chronological commits can add skin after an already completed
          // teeth checkpoint, because only the new skin pass is applied.
          (!chronological && old.teeth > 0 &&
              old.smooth == 0 && next.smooth > 0)) {
        return null;
      }
      final newSkin = old.smooth == 0 ? next.smooth : 0.0;
      final newTeeth = old.teeth == 0 ? next.teeth : 0.0;
      changed = changed || newSkin > 0 || newTeeth > 0;
      final endUs = elapsedUs + newClip.playbackDuration.inMicroseconds;
      regions.add(CropRetouchSegment(
        id: newClip.id,
        startMs: elapsedUs ~/ 1000,
        endMs: endUs ~/ 1000,
        settings: CropRetouchSettings(smooth: newSkin, teeth: newTeeth),
      ));
      elapsedUs = endUs;
    }
    return changed ? List<CropRetouchSegment>.unmodifiable(regions) : null;
  }

  /// A new colour grade follows existing magic/animation/scene effects in
  /// the canonical graph, but precedes face retouch and rotation. Reusing a
  /// completed video for grading is therefore allowed only when those later
  /// stages are absent; otherwise the original graph preserves preview parity.
  static bool _additionalGrade(
    List<CropClip> before,
    List<CropClip> after, {
    bool chronological = false,
  }) =>
      before.length == 1 &&
      after.length == 1 &&
      !before.single.colorFilter.enabled &&
      after.single.colorFilter.enabled &&
      (chronological || (
        !before.single.retouch.enabled &&
        !after.single.retouch.enabled &&
        before.single.rotationQuarterTurns % 4 == 0 &&
        after.single.rotationQuarterTurns % 4 == 0
      )) &&
      _sameExcept(before.single, after.single, 'grade');

  /// Muting one or more timeline segments changes only their audio. Earlier
  /// retouch, scene effects and colour grades remain baked and untouched.
  /// Preserve all other segment audio; unmuting remains a full rebuild.
  static bool _additionalMute(
    List<CropClip> before,
    List<CropClip> after,
  ) {
    if (before.length != after.length || before.isEmpty) return false;
    var changed = false;
    for (var index = 0; index < before.length; index++) {
      final old = before[index], next = after[index];
      if (!_sameExcept(old, next, 'mute') ||
          (old.isMuted && !next.isMuted)) return false;
      changed = changed || (!old.isMuted && next.isMuted);
    }
    return changed;
  }

  /// Audio-only composition for a completed multi-clip timeline. FFmpeg
  /// decodes/encodes audio once while video packets are copied unchanged.
  /// Using the original segment durations also keeps the music track aligned.
  static TiniEditNode _muteTimelineSuffix(
    TiniEditNode previous,
    List<CropClip> before,
    List<CropClip> after,
  ) {
    // Keep the already-established single-clip path unchanged.
    if (after.length == 1) {
      final seconds = _number(
        after.single.playbackDuration.inMicroseconds / 1000000.0,
      );
      return _postProcess(previous,
        stage: 'editor.incremental.mute.v1',
        parameters: {'mute': true, 'audio': 'aac128-44100-stereo', 'seconds': seconds},
        command: (input, output) =>
          '-i "$input" -f lavfi -t $seconds '
          '-i anullsrc=channel_layout=stereo:sample_rate=44100 '
          '-map 0:v:0 -map 1:a:0 -c:v copy '
          '-c:a aac -b:a 128k -ar 44100 -ac 2 -t $seconds '
          '-movflags +faststart -y "$output"',
      );
    }
    final totalUs = after.fold<int>(
      0, (sum, clip) => sum + clip.playbackDuration.inMicroseconds,
    );
    final graph = <String>[];
    final streams = StringBuffer();
    var elapsedUs = 0;
    for (var index = 0; index < after.length; index++) {
      final durationUs = after[index].playbackDuration.inMicroseconds;
      final start = _number(elapsedUs / 1000000.0);
      final end = _number((elapsedUs + durationUs) / 1000000.0);
      final length = _number(durationUs / 1000000.0);
      final newlyMuted = !before[index].isMuted && after[index].isMuted;
      graph.add(newlyMuted
          ? '[1:a]atrim=duration=$length,asetpts=PTS-STARTPTS[a$index]'
          : '[0:a]atrim=start=$start:end=$end,'
              'asetpts=PTS-STARTPTS[a$index]');
      streams.write('[a$index]');
      elapsedUs += durationUs;
    }
    graph.add('${streams}concat=n=${after.length}:v=0:a=1[aout]');
    final length = _number(totalUs / 1000000.0);
    return _postProcess(previous,
      stage: 'editor.incremental.timeline.mute.v1',
      parameters: {
        'muted': [for (final clip in after) clip.isMuted],
        'durationUs': [for (final clip in after)
          clip.playbackDuration.inMicroseconds],
        'audio': 'aac128-44100-stereo',
      },
      command: (input, output) =>
        '-i "$input" -f lavfi -t $length '
        '-i anullsrc=channel_layout=stereo:sample_rate=44100 '
        '-filter_complex "${graph.join(';')}" '
        '-map 0:v:0 -map "[aout]" -c:v copy '
        '-c:a aac -b:a 128k -ar 44100 -ac 2 '
        '-t $length -movflags +faststart -y "$output"',
    );
  }

  /// Only a newly selected Magic effect may follow an already-completed clip.
  /// It is canonical only when no animation, video effect, grade, retouch or
  /// rotation has yet been applied to that clip. Earlier operations stay cached.
  static bool _additionalMagic(List<CropClip> before, List<CropClip> after,
      {bool chronological = false}) =>
      before.length == 1 &&
      after.length == 1 &&
      before.single.magicEffectId == null &&
      after.single.magicEffectId != null &&
      (chronological || (
        !before.single.animations.hasEffects &&
        before.single.videoEffects.isEmpty &&
        !before.single.colorFilter.enabled &&
        !before.single.retouch.enabled &&
        before.single.rotationQuarterTurns % 4 == 0
      )) &&
      _sameExcept(before.single, after.single, 'magic');

  /// Add exactly one animation in original start/end/group order. An animation
  /// inserted ahead of an existing animation is not a safe suffix.
  static CropAnimationSettings? _additionalAnimation(
    List<CropClip> before,
    List<CropClip> after, {
    bool chronological = false,
  }) {
    if (before.length != 1 || after.length != 1) return null;
    final previous = before.single;
    final current = after.single;
    if (!_sameExcept(previous, current, 'animations') ||
        (!chronological && (
          previous.videoEffects.isNotEmpty ||
          previous.colorFilter.enabled ||
          previous.retouch.enabled ||
          previous.rotationQuarterTurns % 4 != 0))) {
      return null;
    }
    final old = previous.animations;
    final next = current.animations;
    final oldIds = [old.start, old.end, old.group];
    final nextIds = [next.start, next.end, next.group];
    final oldDurations = [old.startSeconds, old.endSeconds, old.groupSeconds];
    final nextDurations = [next.startSeconds, next.endSeconds, next.groupSeconds];
    var added = -1;
    for (var index = 0; index < oldIds.length; index++) {
      if (oldIds[index] != null) {
        if (oldIds[index] != nextIds[index] ||
            oldDurations[index] != nextDurations[index]) return null;
      } else if (nextIds[index] != null) {
        if (added >= 0) return null;
        added = index;
      }
    }
    if (added < 0 || (!chronological &&
        oldIds.skip(added + 1).any((id) => id != null))) {
      return null;
    }
    return CropAnimationSettings(
      start: added == 0 ? next.start : null,
      end: added == 1 ? next.end : null,
      group: added == 2 ? next.group : null,
      startSeconds: next.startSeconds,
      endSeconds: next.endSeconds,
      groupSeconds: next.groupSeconds,
    );
  }

  /// Generic effects use the original exporter recipes, not approximations.
  /// Body/face tracking, Vibe and scene composites require their own source
  /// analysis and cannot be substituted with an FFmpeg post-filter.
  static List<TiniAppliedEffect>? _additionalGenericEffects(
    List<CropClip> before,
    List<CropClip> after, {
    bool chronological = false,
  }) {
    if (before.length != 1 || after.length != 1) return null;
    final oldClip = before.single, newClip = after.single;
    if (!_sameExcept(oldClip, newClip, 'effects') ||
        (!chronological && (
          oldClip.colorFilter.enabled ||
          oldClip.retouch.enabled ||
          oldClip.rotationQuarterTurns % 4 != 0))) return null;
    final old = oldClip.videoEffects, next = newClip.videoEffects;
    if (next.length <= old.length) return null;
    for (var i = 0; i < old.length; i++) {
      if (old[i] != next[i]) return null;
    }
    final added = next.skip(old.length).toList(growable: false);
    bool isGeneric(TiniAppliedEffect effect) =>
        !TiniVibeEffectsExport.hasVibe([effect]) &&
        !TiniBodyFxEngine.hasBodyEffects([effect]) &&
        !TiniSledEffect.hasEffect([effect]) &&
        !TiniFaceSceneFx.hasDog([effect]);
    if ((!chronological && !old.every(isGeneric)) ||
        !added.every(isGeneric)) return null;
    return added;
  }

  /// Later effect passes can reuse an earlier completed video when the newly
  /// appended effect is in the same or a later canonical category. An earlier
  /// category, or any effect before an existing grade/retouch, is not a suffix.
  static TiniAppliedEffect? _additionalSpecialEffect(
    List<CropClip> before,
    List<CropClip> after, {
    bool chronological = false,
  }) {
    if (before.length != 1 || after.length != 1) return null;
    final oldClip = before.single, newClip = after.single;
    if (!_sameExcept(oldClip, newClip, 'effects') ||
        (!chronological && (oldClip.colorFilter.enabled ||
            oldClip.retouch.enabled ||
            oldClip.rotationQuarterTurns % 4 != 0))) return null;
    final old = oldClip.videoEffects, next = newClip.videoEffects;
    if (next.length != old.length + 1) return null;
    for (var index = 0; index < old.length; index++) {
      if (old[index] != next[index]) return null;
    }
    int rank(TiniAppliedEffect fx) {
      if (TiniFaceSceneFx.hasDog([fx])) return 4;
      if (TiniSledEffect.hasEffect([fx])) return 3;
      if (TiniBodyFxEngine.hasBodyEffects([fx])) return 2;
      if (TiniVibeEffectsExport.hasVibe([fx])) return 1;
      return 0;
    }
    final effect = next.last;
    final index = rank(effect);
    if (index == 0 || effect.descriptor?.available != true ||
        (!chronological && old.any((fx) => rank(fx) > index))) return null;
    return effect;
  }

  static Future<TiniEditNode> _specialSuffix(
    TiniEditNode before,
    String sourcePath,
    CropClip clip,
    TiniAppliedEffect effect,
    int width,
    int height,
  ) async {
    final seconds = clip.playbackDuration.inMicroseconds / 1000000.0;
    final isBody = TiniBodyFxEngine.hasBodyEffects([effect]);
    final isVibe = TiniVibeEffectsExport.hasVibe([effect]);
    final isSled = TiniSledEffect.hasEffect([effect]);
    final source = clip.replacementPath ?? sourcePath;
    final parents = <TiniEditNode>[before,
      if (isBody) await cache.source(source)];
    return TiniEditNode(
      stage: 'editor.incremental.special.effect.v1',
      parameters: {
        'effect': _fx(effect),
        'category': isBody ? 'body' : isVibe ? 'vibe' : isSled ? 'sled' : 'dog',
        'size': [width, height], 'seconds': seconds,
        'sourceStartUs': (clip.replacementPath == null
            ? clip.startTime : clip.replacementStartTime).inMicroseconds,
      },
      inputs: parents,
      render: (files, stop) async {
        if (stop()) throw TiniEditCancelled();
        final input = files.first.path;
        String? output;
        try {
          if (isVibe) {
            output = await TiniVibeEffectsExport.compose(
              inputPath: input, effects: [effect], seconds: seconds,
              width: width, height: height, cancelled: stop);
          } else if (isBody) {
            final frames = await TiniBodyFxEngine.prepare(
              clip: clip.copyWith(videoEffects: [effect]),
              source: files[1].path,
              sourceStart: clip.replacementPath == null
                  ? clip.startTime : clip.replacementStartTime,
              cancelled: stop,
            );
            try {
              if (stop()) throw TiniEditCancelled();
              output = await TiniBodyFxEngine.compose(
                renderedPath: input, frames: frames,
                width: width, height: height,
              );
            } finally {
              await frames.dispose();
            }
          } else if (isSled) {
            output = await TiniSledExport.compose(
              inputPath: input, effects: [effect], seconds: seconds,
              width: width, height: height, analysisInputPath: input,
              cancelled: stop,
            );
          } else {
            output = await TiniFaceSceneExport.composeDog(
              inputPath: input, effects: [effect], seconds: seconds,
              width: width, height: height, analysisInputPath: input,
              cancelled: stop,
            );
          }
          if (stop()) throw TiniEditCancelled();
          final producedPath = output;
          if (producedPath == null || producedPath == input ||
              !await File(producedPath).exists() ||
              await File(producedPath).length() == 0) {
            throw StateError('The appended effect generated no output video');
          }
          return TiniEditArtifact(producedPath, temporary: true);
        } catch (_) {
          if (output != null && output != input) {
            try { await File(output).delete(); }
            on FileSystemException { /* Temporary native effect was removed. */ }
          }
          rethrow;
        }
      },
    );
  }

  /// Rotation is the final operation in the clip graph. Applying it over an
  /// immutable, unrotated checkpoint preserves the canonical effect order.
  static bool _additionalRotation(
    List<CropClip> before,
    List<CropClip> after, {
    bool nativeRetouch = true,
    bool chronological = false,
  }) =>
      before.length == 1 &&
      after.length == 1 &&
      before.single.rotationQuarterTurns % 4 == 0 &&
      after.single.rotationQuarterTurns % 4 != 0 &&
      (chronological || !(nativeRetouch && Platform.isAndroid &&
          (before.single.retouch.enabled || after.single.retouch.enabled))) &&
      _sameExcept(before.single, after.single, 'rotation');

  /// Shrinking the visible region of a completed, normal-speed clip can reuse
  /// its processed pixels. Time-dependent effects must be rebuilt with their
  /// original new timeline; otherwise their clock/face analysis would differ.
  static ({Duration start, Duration length})? _shorterTrim(
    List<CropClip> before,
    List<CropClip> after,
  ) {
    if (before.length != 1 || after.length != 1) return null;
    final old = before.single, next = after.single;
    if (!old.speed.isDefault || !next.speed.isDefault ||
        old.magicEffectId != null || old.animations.hasEffects ||
        old.videoEffects.isNotEmpty ||
        next.startTime < old.startTime || next.endTime > old.endTime ||
        next.endTime <= next.startTime ||
        (next.startTime == old.startTime && next.endTime == old.endTime)) {
      return null;
    }
    final previous = Map<String, Object?>.from(describe(old))
      ..remove('startUs')..remove('endUs');
    final current = Map<String, Object?>.from(describe(next))
      ..remove('startUs')..remove('endUs');
    if (TiniEditCache.digest(previous) != TiniEditCache.digest(current)) {
      return null;
    }
    return (start: next.startTime - old.startTime, length: next.duration);
  }

  /// Execute a proven suffix through the exact Tini filtergraph recipe.
  /// Use the cached prior output as input; earlier native face processing
  /// is never invoked again for this suffix.
  static TiniEditNode _visualSuffix(
    TiniEditNode input, {
    required String stage,
    required Object parameters,
    required List<String> filters,
    required Duration duration,
  }) => _postProcess(
    input,
    stage: stage,
    parameters: parameters,
    command: (source, output) =>
      '-i "$source" -filter_complex '
      '"[0:v]null[src];${filters.join(';')}" '
      '-map "[dst]" -map 0:a? -c:v libx264 -preset veryfast '
      '-crf 18 -pix_fmt yuv420p -r 30 -c:a copy '
      '-t ${_number(duration.inMicroseconds / 1000000.0)} '
      '-movflags +faststart -y "$output"',
  );

  static TiniEditNode _postProcess(
    TiniEditNode input, {
    required String stage,
    required Object parameters,
    required String Function(String source, String output) command,
  }) => TiniEditNode(
    stage: stage,
    parameters: parameters,
    inputs: [input],
    render: (files, stop) async {
      if (stop()) throw TiniEditCancelled();
      final output = await _output('mp4');
      try {
        await _command(command(files.single.path, output), stop, stage: stage);
        if (stop()) throw TiniEditCancelled();
        return TiniEditArtifact(output, temporary: true);
      } catch (_) {
        try { await File(output).delete(); }
        on FileSystemException { /* Failed partial output. */ }
        rethrow;
      }
    },
  );

  /// Verify a finished incremental video before caching it. The process that
  /// produced it may finish successfully yet silently change the clip length,
  /// frame rate, canvas, or audio streams. On mismatch, the full Tini graph is
  /// used instead of publishing an incomplete cached result.
  static Future<void> _verifyIncremental(
    String previous,
    String output,
    int width,
    int height,
    Duration duration,
    bool Function() stopped,
  ) async {
    Future<Map> inspect(String path) async {
      if (stopped()) throw TiniEditCancelled();
      final probe = await FFprobeKit.executeWithArguments([
        '-v', 'error', '-show_entries',
        'stream=codec_type,width,height,avg_frame_rate:format=duration',
        '-of', 'json', path,
      ]);
      if (!ReturnCode.isSuccess(await probe.getReturnCode())) {
        throw StateError('Cannot inspect incremental video');
      }
      return jsonDecode((await probe.getOutput()) ?? '{}') as Map;
    }
    final before = await inspect(previous);
    final after = await inspect(output);
    if (stopped()) throw TiniEditCancelled();
    final oldStreams = before['streams'], newStreams = after['streams'];
    if (oldStreams is! List || newStreams is! List) {
      throw StateError('No video streams in incremental output');
    }
    final sourceAudio = oldStreams.whereType<Map>()
        .where((s) => s['codec_type'] == 'audio').length;
    final outputAudio = newStreams.whereType<Map>()
        .where((s) => s['codec_type'] == 'audio').length;
    final videoStreams = newStreams.whereType<Map>()
        .where((s) => s['codec_type'] == 'video').toList();
    if (videoStreams.length != 1 || sourceAudio != outputAudio) {
      throw StateError('Incremental edit changed video/audio stream count');
    }
    final video = videoStreams.single;
    final rate = '${video['avg_frame_rate']}'.split('/');
    final numerator = rate.isNotEmpty ? double.tryParse(rate.first) : null;
    final denominator = rate.length == 2 ? double.tryParse(rate.last) : null;
    final measuredDuration = double.tryParse(
        '${(after['format'] as Map?)?['duration']}');
    if (video['width'] != width || video['height'] != height ||
        numerator == null || denominator == null || denominator <= 0 ||
        !numerator.isFinite || !denominator.isFinite ||
        (numerator / denominator - 30).abs() > .01 ||
        measuredDuration == null || !measuredDuration.isFinite ||
        (measuredDuration - duration.inMicroseconds / 1000000.0).abs() > .10) {
      throw StateError('Incremental edit changed dimensions, FPS or duration');
    }
  }

  /// The full edit stays independently addressable for undo/redo. Only a
  /// successfully completed output can become an incremental parent.
  static Future<String> _rememberCompleted({
    required TiniEditNode completed,
    required String project,
    required String signature,
    required List<CropClip> clips,
    required int request,
    String? previousSignature,
    TiniEditNode? verifySource,
    int? verifyWidth,
    int? verifyHeight,
    Duration? verifyDuration,
    bool Function()? cancelled,
  }) async {
    if (verifySource != null &&
        (verifyWidth == null || verifyHeight == null || verifyDuration == null)) {
      throw ArgumentError('Incomplete incremental output validation');
    }
    final snapshot = TiniEditNode(
      stage: 'editor.incremental.snapshot.v2',
      parameters: {
        'project': project, 'edit': signature,
        'verified': verifySource != null,
      },
      inputs: [completed, if (verifySource != null) verifySource],
      cacheKey: _snapshotKey(project, signature),
      retainGroup: 'editor.incremental.$project',
      render: (files, stop) async {
        if (stop()) throw TiniEditCancelled();
        if (verifySource != null) {
          await _verifyIncremental(
            files[1].path, files.first.path,
            verifyWidth!, verifyHeight!, verifyDuration!, stop,
          );
        }
        return TiniEditArtifact(files.first.path);
      },
    );
    // Record a completed checkpoint even if the user starts the next edit
    // while its independent owned copy is being made. The on-disk artifact
    // must already exist and pass cache validation; an unfinished render can
    // never enter history.
    Future<void> rememberIfCompleted() async {
      if (!await cache.containsCached(snapshot)) return;
      _recordVersion(project, signature, clips, snapshot);
      try {
        await cache.rememberEditorHistory(
          project, signature, [for (final clip in clips) describe(clip)],
          previousSignature: previousSignature,
        );
      } catch (error, stack) {
        // A history-index I/O failure must never fail a completed export.
        developer.log('Could not persist editor history index',
            name: 'TiniEditCache', error: error, stackTrace: stack);
      }
    }

    String output;
    try {
      output = (await cache.run(snapshot, cancelled: cancelled)).path;
    } on TiniEditCancelled {
      // An obsolete caller may be cancelled after _materialize committed
      // the result. Preserve that result for undo/redo and the next edit.
      try {
        await rememberIfCompleted();
      } catch (error, stack) {
        developer.log('Could not register completed cancelled checkpoint',
            name: 'TiniEditCache', error: error, stackTrace: stack);
      }
      rethrow;
    }
    await rememberIfCompleted();
    return output;
  }

  /// Rehydrate only the changed operator from a disk index. All unchanged
  /// properties come from the live editor model. The complete descriptor is
  /// compared again before accepting an earlier checkpoint, so unsupported
  /// model fields can never silently change the pixels or timeline.
  static List<CropClip>? _previousClipsFromHistory(
    Object? stored,
    List<CropClip> current,
  ) {
    if (stored is! List || stored.length != current.length || current.isEmpty) {
      return null;
    }
    final previous = <CropClip>[];
    // A user can commit several changes while warmup is pending. Restore
    // the entire previous *supported* snapshot, not just one field, then
    // compare its full canonical descriptor before it may be an ancestor.
    // Structural inputs (speed/replacement/cutout/background) are deliberately
    // never synthesized from an older record: these require the real assets.
    const restorable = {
      'startUs', 'endUs', 'retouch', 'grade', 'mute', 'magic',
      'rotation', 'animations', 'effects',
    };
    try {
      for (var index = 0; index < current.length; index++) {
        final record = Map<String, dynamic>.from(stored[index] as Map);
        final live = current[index];
        final fields = describe(live);
        if (record.length != fields.length ||
            record.keys.any((field) => !fields.containsKey(field))) {
          return null;
        }
        final differences = <String>{};
        for (final field in fields.keys) {
          if (!record.containsKey(field) ||
              TiniEditCache.digest(record[field]) !=
                  TiniEditCache.digest(fields[field])) {
            differences.add(field);
          }
        }
        if (!restorable.containsAll(differences)) return null;
        var candidate = live;
        if (differences.contains('startUs') || differences.contains('endUs')) {
          candidate = candidate.copyWith(
            startTime: Duration(microseconds: (record['startUs'] as num).toInt()),
            endTime: Duration(microseconds: (record['endUs'] as num).toInt()),
          );
          if (candidate.endTime <= candidate.startTime) return null;
        }
        if (differences.contains('retouch')) {
          final old = record['retouch'] as List;
          if (old.length != 2) return null;
          candidate = candidate.copyWith(retouch: CropRetouchSettings(
            smooth: (old[0] as num).toDouble(),
            teeth: (old[1] as num).toDouble(),
          ));
        }
        if (differences.contains('grade')) {
          final old = record['grade'] as List;
          if (old.length != 3) return null;
          candidate = candidate.copyWith(colorFilter: CropFilterSelection(
            id: old[0] as String?,
            intensity: (old[1] as num).toDouble(),
          ));
        }
        if (differences.contains('mute')) {
          if (record['mute'] is! bool) return null;
          candidate = candidate.copyWith(isMuted: record['mute'] as bool);
        }
        if (differences.contains('magic')) {
          candidate = candidate.withMagic(record['magic'] as String?);
        }
        if (differences.contains('rotation')) {
          candidate = candidate.copyWith(
            rotationQuarterTurns: (record['rotation'] as num).toInt(),
          );
        }
        if (differences.contains('animations')) {
          final old = record['animations'] as List;
          if (old.length != 6) return null;
          candidate = candidate.copyWith(animations: CropAnimationSettings(
            start: old[0] as String?,
            startSeconds: (old[1] as num).toDouble(),
            end: old[2] as String?,
            endSeconds: (old[3] as num).toDouble(),
            group: old[4] as String?,
            groupSeconds: (old[5] as num).toDouble(),
          ));
        }
        if (differences.contains('effects')) {
          final old = record['effects'] as List;
          candidate = candidate.withVideoEffects([
            for (final item in old)
              TiniAppliedEffect(
                id: (item as Map)['id'] as String,
                startSeconds: (item['start'] as num).toDouble(),
                endSeconds: (item['end'] as num).toDouble(),
              ),
          ]);
        }
        // This check is the safety boundary. Missing fields, malformed
        // history, or an old filter recipe never becomes a false cache hit.
        if (TiniEditCache.digest(describe(candidate)) !=
            TiniEditCache.digest(record)) return null;
        previous.add(candidate);
      }
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on RangeError {
      return null;
    } on ArgumentError {
      return null;
    }
    return List<CropClip>.unmodifiable(previous);
  }

  /// Combine several *new* canonical suffix operations after a previously
  /// completed edit. This planner only appends stages that follow all existing
  /// pixel operations. Changing or removing an earlier stage is deliberately
  /// not eligible: it would otherwise render a different video than preview.
  /// The produced node chain is lazy; failures use the complete original graph.
  static Future<TiniEditNode?> _compoundCanonicalSuffix({
    required TiniEditNode input,
    required String originalPath,
    required List<CropClip> before,
    required List<CropClip> after,
    required int width,
    required int height,
    required bool allowHardwareRetouch,
  }) async {
    if (before.length != 1 || after.length != 1) return null;
    // A sequence of new lossy encodes is slower than one full graph on a plain
    // source. Reserve chaining for prior expensive processing checkpoints.
    final prior = before.single;
    if (!prior.retouch.enabled && prior.cutout == null &&
        prior.backgroundPath == null && prior.magicEffectId == null &&
        prior.videoEffects.isEmpty && prior.speed.isDefault) return null;
    final target = after.single;
    var current = prior;
    final first = Map<String, Object?>.from(describe(current));
    final last = Map<String, Object?>.from(describe(target));
    for (final field in const [
      'magic', 'animations', 'effects', 'grade', 'retouch',
      'rotation', 'mute',
    ]) {
      first.remove(field);
      last.remove(field);
    }
    if (TiniEditCache.digest(first) != TiniEditCache.digest(last)) {
      return null;
    }
    final seconds = target.playbackDuration.inMicroseconds / 1000000.0;
    var result = input;
    var count = 0;

    if (current.magicEffectId != target.magicEffectId) {
      final next = current.withMagic(target.magicEffectId);
      if (!_additionalMagic([current], [next])) return null;
      result = _visualSuffix(result,
        stage: 'editor.incremental.magic.v1',
        parameters: {'magic': next.magicEffectId, 'size': [width, height]},
        filters: CropMagicEffects.filterGraph(
          input: 'src', output: 'dst', id: next.magicEffectId,
          seconds: seconds, width: width, height: height,
        ),
        duration: next.playbackDuration,
      );
      current = next;
      count++;
    }

    if (current.animations != target.animations) {
      final next = current.copyWith(animations: target.animations);
      final added = _additionalAnimation([current], [next]);
      if (added == null) return null;
      result = _visualSuffix(result,
        stage: 'editor.incremental.animation.v1',
        parameters: {'animations': describe(next)['animations'],
          'size': [width, height]},
        filters: CropAnimationFilters.filterGraph(
          input: 'src', output: 'dst', settings: added,
          seconds: seconds, width: width, height: height,
        ),
        duration: next.playbackDuration,
      );
      current = next;
      count++;
    }

    final effects = target.videoEffects;
    if (current.videoEffects.length > effects.length) return null;
    for (var i = 0; i < current.videoEffects.length; i++) {
      if (current.videoEffects[i] != effects[i]) return null;
    }
    while (current.videoEffects.length < effects.length) {
      final addedEffect = effects[current.videoEffects.length];
      final next = current.withVideoEffects([
        ...current.videoEffects,
        addedEffect,
      ]);
      final generic = _additionalGenericEffects([current], [next]);
      if (generic != null) {
        result = _visualSuffix(result,
          stage: 'editor.incremental.effect.v1',
          parameters: {'added': generic.map(_fx).toList(),
            'size': [width, height]},
          filters: TiniEffectsRender.filterGraph(
            input: 'src', output: 'dst', effects: generic,
            seconds: seconds, width: width, height: height,
          ),
          duration: next.playbackDuration,
        );
      } else {
        final special = _additionalSpecialEffect([current], [next]);
        if (special == null) return null;
        result = await _specialSuffix(
          result, originalPath, next, special, width, height,
        );
      }
      current = next;
      count++;
    }

    if (current.colorFilter != target.colorFilter) {
      final next = current.copyWith(colorFilter: target.colorFilter);
      if (!_additionalGrade([current], [next])) return null;
      result = _incrementalGradeOnMedia3(
        result, next.colorFilter, width, height,
      );
      current = next;
      count++;
    }

    if (current.retouch != target.retouch) {
      final next = current.copyWith(retouch: target.retouch);
      if (!allowHardwareRetouch || !Platform.isAndroid) return null;
      final regions = _additionalRetouch([current], [next]);
      if (regions == null) return null;
      result = TiniRetouchExport.node(
        input: result, outputWidth: width, outputHeight: height,
        durationMs: target.playbackDuration.inMilliseconds,
        regions: regions,
      );
      current = next;
      count++;
    }

    if (current.rotationQuarterTurns != target.rotationQuarterTurns) {
      final next = current.copyWith(
        rotationQuarterTurns: target.rotationQuarterTurns,
      );
      if (!_additionalRotation([current], [next],
          nativeRetouch: allowHardwareRetouch)) return null;
      result = _visualSuffix(result,
        stage: 'editor.incremental.rotation.v1',
        parameters: {'quarterTurns': next.rotationQuarterTurns % 4,
          'size': [width, height]},
        filters: [
          '[src]${CropRotation.ffmpeg(next.rotationQuarterTurns, width, height)},'
              'format=yuv420p[dst]',
        ],
        duration: next.playbackDuration,
      );
      current = next;
      count++;
    }

    if (current.isMuted != target.isMuted) {
      final next = current.copyWith(isMuted: target.isMuted);
      if (!_additionalMute([current], [next])) return null;
      result = _muteTimelineSuffix(result, [current], [next]);
      current = next;
      count++;
    }
    if (count < 2 ||
        TiniEditCache.digest(describe(current)) !=
            TiniEditCache.digest(describe(target))) {
      return null;
    }
    return result;
  }

  static Future<String?> _resumeIncrementally({
    required String project,
    required String originalPath,
    required String signature,
    required List<CropClip> clips,
    required int width,
    required int height,
    required bool allowHardwareRetouch,
    required int request,
    String? preferredPreviousSignature,
    bool chronological = false,
    bool Function()? cancelled,
  }) async {
    final versions = <_TiniIncrementalSnapshot>[
      ...?_editVersions[project],
    ];
    // A process restart clears _editVersions, but not completed on-disk
    // snapshots. Recreate only unambiguous older state descriptors.
    try {
      for (final entry in await cache.editorHistory(project)) {
        final historySignature = entry['signature'] as String;
        if (versions.any((v) => v.signature == historySignature)) continue;
        final reconstructed = _previousClipsFromHistory(entry['clips'], clips);
        if (reconstructed == null) continue;
        versions.add(_TiniIncrementalSnapshot(
          historySignature,
          reconstructed,
          TiniEditNode.cached(
            _snapshotKey(project, historySignature),
            retainGroup: 'editor.incremental.$project',
          ),
        ));
      }
    } catch (error, stack) {
      // Invalid history is ignored; the canonical renderer still works.
      developer.log('Editor history index unavailable',
          name: 'TiniEditCache', error: error, stackTrace: stack);
    }
    if (versions.isEmpty) return null;
    // Rendering in user-commit order is permitted only above the EXACT
    // predecessor. Never choose another branch merely because its settings
    // happen to be compatible. Otherwise equal settings could cache pixels
    // generated in a different order.
    if (chronological) {
      if (preferredPreviousSignature == null) return null;
      versions.removeWhere((v) => v.signature != preferredPreviousSignature);
      if (versions.isEmpty) return null;
    }
    // Prefer the exact state from which the user made the edit. A warmup
    // finishing late must not jump ahead of a newer undo/redo branch.
    // Other valid ancestors remain candidates if that checkpoint was pruned.
    if (preferredPreviousSignature != null) {
      final index = versions.indexWhere(
        (v) => v.signature == preferredPreviousSignature,
      );
      if (index >= 0 && index != versions.length - 1) {
        final preferred = versions.removeAt(index);
        versions.add(preferred);
      }
    }
    // Snapshot the collection so a concurrent warmup completion cannot
    // invalidate this iterator during an awaited cache lookup.
    for (final version in List<_TiniIncrementalSnapshot>.of(versions.reversed)) {
      if (version.signature != signature) continue;
      try {
        final path = (await cache.run(version.output, cancelled: cancelled)).path;
        if (_editRequests[project] == request) {
          versions.remove(version);
          versions.add(version);
        }
        developer.log('Restored completed edit checkpoint', name: 'TiniEditCache');
        return path;
      } on TiniEditCancelled {
        rethrow;
      } catch (error, stack) {
        developer.log('Previous checkpoint unavailable; checking older history',
            name: 'TiniEditCache', error: error, stackTrace: stack);
        continue;
      }
    }
    // Undo/redo branches can make the most recently completed snapshot an
    // incompatible parent. Search all retained versions newest-first; never
    // infer chronological user intent from a clip ID or reorder operations.
    for (final previous in List<_TiniIncrementalSnapshot>.of(versions.reversed)) {
    // Do not start another native export against an evicted parent. There may
    // still be an earlier valid undo/redo checkpoint in the same history.
    if (!await cache.containsCached(previous.output)) continue;
    TiniEditNode? addition;
    if (allowHardwareRetouch && Platform.isAndroid) {
      final changes = _additionalRetouch(previous.clips, clips,
          chronological: chronological);
      if (changes != null) {
        final durationMs = clips.fold<int>(
          0, (total, c) => total + c.playbackDuration.inMicroseconds,
        ) ~/ 1000;
        addition = TiniRetouchExport.node(
          input: previous.output,
          outputWidth: width,
          outputHeight: height,
          durationMs: durationMs,
          regions: changes,
        );
      }
    }
    if (addition == null && _additionalGrade(previous.clips, clips,
        chronological: chronological)) {
      addition = _incrementalGradeOnMedia3(
        previous.output, clips.single.colorFilter, width, height,
      );
    }
    // Only a single added operation is applied to an existing checkpoint.
    // These paths preserve the same canonical visual order as clip().
    if (addition == null && _additionalMagic(previous.clips, clips,
        chronological: chronological)) {
      final c = clips.single;
      addition = _visualSuffix(previous.output,
        stage: 'editor.incremental.magic.v1',
        parameters: {'magic': c.magicEffectId, 'size': [width, height]},
        filters: CropMagicEffects.filterGraph(
          input: 'src', output: 'dst', id: c.magicEffectId,
          seconds: c.playbackDuration.inMicroseconds / 1000000.0,
          width: width, height: height,
        ),
        duration: c.playbackDuration,
      );
    }
    if (addition == null) {
      final animation = _additionalAnimation(previous.clips, clips,
          chronological: chronological);
      if (animation != null) {
        final c = clips.single;
        addition = _visualSuffix(previous.output,
          stage: 'editor.incremental.animation.v1',
          parameters: {
            'animations': describe(c)['animations'],
            'size': [width, height],
          },
          filters: CropAnimationFilters.filterGraph(
            input: 'src', output: 'dst', settings: animation,
            seconds: c.playbackDuration.inMicroseconds / 1000000.0,
            width: width, height: height,
          ),
          duration: c.playbackDuration,
        );
      }
    }
    if (addition == null) {
      final effects = _additionalGenericEffects(previous.clips, clips,
          chronological: chronological);
      if (effects != null) {
        final c = clips.single;
        addition = _visualSuffix(previous.output,
          stage: 'editor.incremental.effect.v1',
          parameters: {
            'added': effects.map(_fx).toList(),
            'size': [width, height],
          },
          filters: TiniEffectsRender.filterGraph(
            input: 'src', output: 'dst', effects: effects,
            seconds: c.playbackDuration.inMicroseconds / 1000000.0,
            width: width, height: height,
          ),
          duration: c.playbackDuration,
        );
      }
    }
    if (addition == null) {
      final effect = _additionalSpecialEffect(previous.clips, clips,
          chronological: chronological);
      if (effect != null) {
        addition = await _specialSuffix(previous.output, originalPath,
          clips.single, effect, width, height);
      }
    }
    if (addition == null && _additionalRotation(previous.clips, clips,
        nativeRetouch: allowHardwareRetouch,
        chronological: chronological)) {
      final c = clips.single;
      addition = _visualSuffix(previous.output,
        stage: 'editor.incremental.rotation.v1',
        parameters: {
          'quarterTurns': c.rotationQuarterTurns % 4,
          'size': [width, height],
        },
        filters: ['[src]${CropRotation.ffmpeg(c.rotationQuarterTurns, width, height)},format=yuv420p[dst]'],
        duration: c.playbackDuration,
      );
    }
    if (addition == null) {
      final trim = _shorterTrim(previous.clips, clips);
      if (trim != null) {
        final start = _number(trim.start.inMicroseconds / 1000000.0);
        final seconds = _number(trim.length.inMicroseconds / 1000000.0);
        addition = _postProcess(previous.output,
          stage: 'editor.incremental.trim.v1',
          parameters: {'startUs': trim.start.inMicroseconds,
            'durationUs': trim.length.inMicroseconds, 'fps': 30},
          command: (input, output) =>
            '-ss $start -t $seconds -i "$input" -map 0:v:0 -map 0:a? '
            '-c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p '
            '-r 30 -c:a aac -b:a 128k -ar 44100 -ac 2 '
            '-t $seconds -movflags +faststart -y "$output"',
        );
      }
    }
    if (addition == null && _additionalMute(previous.clips, clips)) {
      addition = _muteTimelineSuffix(previous.output, previous.clips, clips);
    }
    if (addition == null && !chronological) {
      addition = await _compoundCanonicalSuffix(
        input: previous.output,
        originalPath: originalPath,
        before: previous.clips,
        after: clips,
        width: width,
        height: height,
        allowHardwareRetouch: allowHardwareRetouch,
      );
    }
    if (addition == null) continue;
    // Validation runs inside the last cache producer, before the result is
    // committed to disk. This avoids an extra large video copy just to check
    // metadata, and no invalid result can enter the reusable edit history.
    try {
      final output = await _rememberCompleted(
        completed: addition,
        project: project,
        signature: signature,
        clips: clips,
        request: request,
        previousSignature: preferredPreviousSignature,
        verifySource: previous.output,
        verifyWidth: width,
        verifyHeight: height,
        verifyDuration: Duration(microseconds: clips.fold<int>(0,
          (total, c) => total + c.playbackDuration.inMicroseconds)),
        cancelled: cancelled,
      );
      developer.log('Applied only new edit over existing cached video',
          name: 'TiniEditCache');
      return output;
    } on TiniEditCancelled {
      rethrow;
    } on TiniRetouchBaselineRequired {
      // Do not retry costly native export against multiple cached parents.
      return null;
    } catch (error, stack) {
      // If a device cannot consume the checkpoint, the original complete
      // effect graph is authoritative. Never return unedited source media.
      developer.log('Incremental checkpoint rejected; rebuilding canonical graph',
          name: 'TiniEditCache', error: error, stackTrace: stack);
      return null;
    }
    }
    return null;
  }

  /// Media3 only assembles *completed* Tini picture-effect checkpoints.
  /// Filters, Magic, animation, background masks, face effects and cutouts
  /// remain in their existing frame-accurate render nodes. This is a packet
  /// mux, not a second effect pass or an approximation of a Tini shader.
  /// Falling back here reuses the SAME rendered inputs; no effects are lost.
  static Future<String?> _media3JoinRenderedEffects({
    required List<TiniEditArtifact> inputs,
    required List<double> durations,
    required int width,
    required int height,
    required bool Function() cancelled,
  }) async {
    if (!Platform.isAndroid || inputs.isEmpty ||
        inputs.length != durations.length) return null;
    if (cancelled()) throw TiniEditCancelled();
    String? resultPath;
    var accepted = false;
    try {
      if (!await TiniMedia3Export.isAvailable()) return null;
      var expectedPackets = 0;
      final segments = <TiniMedia3Segment>[];
      for (var i = 0; i < inputs.length; i++) {
        if (cancelled()) throw TiniEditCancelled();
        final path = inputs[i].path;
        if (!await File(path).exists() || durations[i] <= 0 ||
            !durations[i].isFinite) return null;
        final probe = await FFprobeKit.executeWithArguments([
          '-v', 'error', '-count_packets', '-show_entries',
          'stream=codec_type,codec_name,width,height,pix_fmt,avg_frame_rate,'
              'nb_read_packets,color_transfer:format=duration',
          '-of', 'json', path,
        ]);
        if (!ReturnCode.isSuccess(await probe.getReturnCode())) return null;
        final info = jsonDecode((await probe.getOutput()) ?? '{}') as Map;
        final streams = info['streams'];
        if (streams is! List) return null;
        final video = streams.whereType<Map>()
            .where((st) => st['codec_type'] == 'video').toList();
        final audio = streams.whereType<Map>()
            .where((st) => st['codec_type'] == 'audio').toList();
        // The current Tini join expects one audio stream per clip. Do not use
        // the Media3 path if it would manufacture silence or drop real audio.
        if (video.length != 1 || audio.length != 1) return null;
        final v = video.single;
        final rate = '${v['avg_frame_rate']}'.split('/');
        if (rate.length != 2) return null;
        final numerator = double.tryParse(rate[0]);
        final denominator = double.tryParse(rate[1]);
        final packets = int.tryParse('${v['nb_read_packets']}');
        final actualDuration = double.tryParse(
            '${(info['format'] as Map?)?['duration']}');
        if (v['codec_name'] != 'h264' ||
            v['width'] != width || v['height'] != height ||
            v['pix_fmt'] != 'yuv420p' ||
            const {'smpte2084', 'arib-std-b67'}.contains(v['color_transfer']) ||
            numerator == null || denominator == null || denominator <= 0 ||
            (numerator / denominator - 30).abs() > 0.01 ||
            packets == null || packets <= 0 ||
            actualDuration == null || !actualDuration.isFinite ||
            (actualDuration - durations[i]).abs() > 0.15 ||
            !const {'aac', 'pcm_s16le'}.contains(audio.single['codec_name'])) {
          return null;
        }
        expectedPackets += packets;
        // A delivery-stage clip begins at zero; all Tini effects, speed and
        // original clip trims were already rendered into this local file.
        segments.add(TiniMedia3Segment(
          inputPath: path,
          start: Duration.zero,
          end: Duration(milliseconds: (durations[i] * 1000).round()),
        ));
      }
      if (cancelled()) throw TiniEditCancelled();
      final job = TiniMedia3Export.startTimeline(
        segments: segments, transmuxRenderedVideo: true,
      );
      var cancellationSent = false;
      final timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (!cancellationSent && cancelled()) {
          cancellationSent = true;
          unawaited(job.cancel().catchError((Object error) {
            developer.log('Media3 effects mux cancellation failed',
                name: 'TiniMedia3', error: error);
            return false;
          }));
        }
      });
      try {
        resultPath = await job.result;
      } finally {
        timer.cancel();
      }
      if (cancelled()) throw TiniEditCancelled();
      if (resultPath == null || !await File(resultPath).exists() ||
          await File(resultPath).length() == 0) {
        throw StateError('Media3 did not deliver the rendered effects');
      }
      final verify = await FFprobeKit.executeWithArguments([
        '-v', 'error', '-count_packets', '-show_entries',
        'stream=codec_type,codec_name,width,height,avg_frame_rate,'
            'nb_read_packets:format=duration',
        '-of', 'json', resultPath,
      ]);
      if (!ReturnCode.isSuccess(await verify.getReturnCode())) {
        throw StateError('Media3 effects output is not readable');
      }
      final info = jsonDecode((await verify.getOutput()) ?? '{}') as Map;
      final streams = info['streams'];
      if (streams is! List) throw StateError('Missing Media3 effects streams');
      final video = streams.whereType<Map>()
          .where((st) => st['codec_type'] == 'video').toList();
      final audio = streams.whereType<Map>()
          .where((st) => st['codec_type'] == 'audio').toList();
      final seconds = double.tryParse('${(info['format'] as Map?)?['duration']}');
      final outputPackets = video.length == 1
          ? int.tryParse('${video.single['nb_read_packets']}') : null;
      final expectedSeconds = durations.fold<double>(0, (sum, d) => sum + d);
      if (video.length != 1 || audio.length != 1 ||
          video.single['codec_name'] != 'h264' ||
          video.single['width'] != width || video.single['height'] != height ||
          outputPackets == null || (outputPackets - expectedPackets).abs() > inputs.length ||
          seconds == null || !seconds.isFinite ||
          (seconds - expectedSeconds).abs() > 0.12) {
        throw StateError('Media3 changed effect frames, timing or audio');
      }
      developer.log('Media3 packet-muxed ${inputs.length} rendered effect clips '
          'without re-encoding their video', name: 'TiniMedia3');
      accepted = true;
      return resultPath;
    } on TiniEditCancelled {
      rethrow;
    } catch (error, stack) {
      developer.log('Media3 effects mux not compatible; using original join',
          name: 'TiniMedia3', error: error, stackTrace: stack);
      return null;
    } finally {
      if (!accepted && resultPath != null) {
        try { await File(resultPath).delete(); }
        on FileSystemException { /* Native job may have removed the output. */ }
      }
    }
  }

  // The background compositor is already a final H.264/AAC encoder. Its
  // output is directly deliverable ONLY when it contains the whole edit.
  static bool _directBackgroundClip(CropClip c) =>
      (c.cutout != null || c.backgroundPath != null) &&
      c.duration.inMicroseconds > 0 &&
      c.speed.isDefault && !c.isMuted &&
      c.magicEffectId == null &&
      !c.animations.hasEffects &&
      c.videoEffects.isEmpty &&
      !c.colorFilter.enabled &&
      !c.retouch.enabled &&
      c.rotationQuarterTurns % 4 == 0;

  // Packet counts and container timestamps do not prove a valid H.264
  // bitstream: decode every frame BEFORE a video enters immutable edit history
  // or the publishing workflow. No second encode or retry occurs here.
  static Future<void> _verifyBackgroundFrames(
      String path, bool Function() stopped) async {
    try {
      await _streamCommand([
        '-hide_banner', '-loglevel', 'error',
        '-xerror', '-err_detect', 'explode',
        '-i', path, '-map', '0:v:0', '-an', '-sn', '-dn',
        '-f', 'null', '-',
      ], stopped, 'background H264 full-frame decode');
    } on _TiniStageFailure catch (error) {
      // A damaged video is a DATA-integrity violation, not a cue to encode
      // the same project again behind the user's back. Propagate a StateError
      // so VideoProcessor never activates its legacy FFmpeg retry branch.
      throw StateError('فيديو عزل الخلفية غير صالح: فشل فك ترميز H264. '
          '${error.details}');
    }
  }

  static TiniEditNode _verifiedBackgroundOutput(TiniEditNode input) =>
      TiniEditNode(
        stage: 'background.h264.full_decode.v1',
        parameters: const {'codec': 'h264', 'decode': 'entire-stream',
            'noReencode': true},
        inputs: [input],
        render: (files, stopped) async {
          await _verifyBackgroundFrames(files.single.path, stopped);
          return TiniEditArtifact(files.single.path);
        },
      );

  static Future<String> render({
    required String originalPath,
    required List<CropClip> clips,
    required int width,
    required int height,
    bool Function()? cancelled,
    bool? hardwareRetouch,
    bool softwareVideo = false,
    bool legacyVideo = false,
    String? editorRevision,
    String? parentEditorRevision,
  }) async {
    if (clips.isEmpty) throw StateError('No clips to render');
    // Reserve user-request order before source hashing or other awaits; a
    // large gallery file must not let an older request overtake a newer edit.
    final request = ++_editSerial;
    final size = CropOverlayOutputSize.fromSource(
      width.toDouble(),
      height.toDouble(),
    );
    final w = size.width, h = size.height;
    final nativeRetouch =
        (hardwareRetouch ?? Platform.isAndroid) &&
        clips.any((c) => c.duration.inMicroseconds > 0 && c.retouch.enabled);
    final playable = clips
        .where((c) => c.duration.inMicroseconds > 0)
        .toList(growable: false);
    if (playable.isEmpty) throw StateError('No playable segments');
    // The source fingerprint and every project setting are part of the key.
    // A new source, trim, speed, background or effect revision cannot reuse
    // another project's pixels by accident.
    final sourceNode = await cache.source(originalPath);
    final externalAssets = await _inputAssetSignature(playable);
    final hasBackground = playable.any(
        (c) => c.cutout != null || c.backgroundPath != null);
    final project = TiniEditCache.digest({
      'source': sourceNode.key,
      'assets': externalAssets,
      'size': [w, h],
      'backend': [softwareVideo, legacyVideo, hardwareRetouch ?? Platform.isAndroid],
      // Prevent old, packet-count-only background exports from being handed
      // back from cache. Unrelated editor histories retain their identities.
      if (hasBackground) 'backgroundCodecPolicy': 'single-encode-verified-v1',
    });
    final stateSignature = TiniEditCache.digest(playable.map(describe).toList());
    // A result created by adding a filter AFTER skin must never share a
    // checkpoint key with the canonical filter-before-skin result. Each
    // committed revision has a distinct identity; legacy callers keep the
    // original settings-only cache key unchanged.
    final signature = editorRevision == null ? stateSignature
        : TiniEditCache.digest({'state': stateSignature, 'revision': editorRevision});
    final revisions = _revisionKeys.putIfAbsent(project, () => <String, String>{});
    final explicitParent = editorRevision == null || parentEditorRevision == null
        ? null : revisions[parentEditorRevision];
    if (editorRevision != null) {
      revisions[editorRevision] = signature;
      if (revisions.length > 24) revisions.remove(revisions.keys.first);
      if (_revisionKeys.length > 16) _revisionKeys.remove(_revisionKeys.keys.first);
    }
    // Never allow a slower *older* render to change the current editor head.
    // It can still finish and retain its immutable result for undo/redo.
    final latestRequest = _editRequests[project];
    final previousSignature = editorRevision == null
        ? (latestRequest == null || request > latestRequest
            ? _requestedVersions[project] : null)
        : explicitParent;
    if (latestRequest == null || request > latestRequest) {
      _requestedVersions.remove(project);
      _requestedVersions[project] = signature;
      _editRequests[project] = request;
      if (_requestedVersions.length > 16) {
        _requestedVersions.remove(_requestedVersions.keys.first);
      }
    }
    // Read the completed artifact directly, before touching any expensive
    // ancestor. This also works after app restart and across undo/redo.
    try {
      final restoredNode = TiniEditNode.cached(
        _snapshotKey(project, signature),
        retainGroup: 'editor.incremental.$project',
      );
      final cached = await cache.run(restoredNode, cancelled: cancelled);
      // This is essential after restarting the app: the first new edit can
      // reuse this previously completed video as its incremental parent.
      if (cancelled?.call() != true) {
        _recordVersion(project, signature, playable, restoredNode);
      }
      developer.log('Restored persisted edit without reprocessing',
          name: 'TiniEditCache');
      return cached.path;
    } on TiniEditCancelled {
      throw CropRetouchCancelled();
    } on FileSystemException {
      // The operating system may have pruned the temporary cache.
    } on StateError {
      // A missing/incomplete snapshot must be built from the actual inputs.
    }
    // No hardware H.264 re-encoding and no redundant Media3 concatenation
    // for an already composed, fully edited background-only clip.
    if (playable.length == 1 &&
        !softwareVideo && !legacyVideo && !nativeRetouch &&
        _directBackgroundClip(playable.single)) {
      final clipSource = playable.single.replacementPath ?? originalPath;
      // clipSource is the actual video path. cache.source() returns a graph
      // node rather than a file and must not be accessed through .path.
      final clipAudio = await _sourceInfo(
          clipSource, () => cancelled?.call() == true);
      if (clipAudio.audio) {
        final direct = await clip(
          originalPath, playable.single, w, h, null, false,
          deliverComposedBackground: true,
        );
        return await _rememberCompleted(
          completed: _verifiedBackgroundOutput(direct),
          project: project, signature: signature, clips: playable,
          request: request, previousSignature: previousSignature,
          cancelled: cancelled,
        );
      }
      // No audio: the standard graph supplies silence and retains its
      // original stream-count contract instead of silently dropping audio.
    }
    if (!softwareVideo && !legacyVideo &&
        (editorRevision == null || explicitParent != null)) {
      try {
        final incremental = await _resumeIncrementally(
          project: project,
          originalPath: originalPath,
          signature: signature,
          clips: playable,
          width: w,
          height: h,
          allowHardwareRetouch: hardwareRetouch ?? Platform.isAndroid,
          request: request,
          preferredPreviousSignature: previousSignature,
          // Honor the committed editor order for every Android effect,
          // including colour grades, Magic, animations and face retouch.
          // A chronological suffix is allowed only on its exact cached parent;
          // never substitute an unrelated branch or reapply old effects.
          chronological: editorRevision != null && Platform.isAndroid,
          cancelled: cancelled,
        );
        if (incremental != null) {
          // Incremental checkpoints can be composed by different engines.
          // A modified background remains subject to the same bitstream check.
          if (hasBackground) {
            await _verifyBackgroundFrames(
                incremental, () => cancelled?.call() == true);
          }
          return incremental;
        }
      } on TiniEditCancelled {
        throw CropRetouchCancelled();
      }
    }
    // A structural-only timeline can use Media3 Transformer directly.
    // Complex video/audio effects retain their canonical, lossless edit graph.
    if (!softwareVideo && !legacyVideo &&
        _media3DirectTimelineEligible(playable)) {
      try {
        final fast = await _tryMedia3DirectTimeline(
          originalPath: originalPath, clips: playable,
          width: w, height: h, cancelled: cancelled,
        );
        if (fast != null) {
          try {
            final remembered = await _rememberCompleted(
              completed: await cache.source(fast), project: project,
              signature: signature, clips: playable, request: request,
              previousSignature: previousSignature, cancelled: cancelled,
            );
            try { await File(fast).delete(); } on FileSystemException {}
            return remembered;
          } on TiniEditCancelled {
            try { await File(fast).delete(); } on FileSystemException {}
            rethrow;
          } catch (error, stack) {
            developer.log('Media3 checkpoint failed; using canonical graph',
                name: 'TiniMedia3', error: error, stackTrace: stack);
            try { await File(fast).delete(); } on FileSystemException {}
          }
        }
      } on TiniEditCancelled {
        throw CropRetouchCancelled();
      }
    }
    // Safe single-clip GPU shortcut. Multi-clip projects, face/background,
    // animation and all Tini-specific effects retain their original graph.
    if (!softwareVideo && !legacyVideo && playable.length == 1) {
      try {
        final gpu = await _tryGpuColorOnly(
          inputPath: originalPath,
          clip: playable.single,
          width: w,
          height: h,
          cancelled: cancelled,
        );
        if (gpu != null) {
          // Colour-only exports must join the same edit history; otherwise
          // enabling face retouch afterwards would unnecessarily rebuild the
          // colour grade instead of consuming the completed GPU checkpoint.
          try {
            final completed = await cache.source(gpu);
            final remembered = await _rememberCompleted(
              completed: completed,
              project: project,
              signature: signature,
              clips: playable,
              request: request,
              previousSignature: previousSignature,
              cancelled: cancelled,
            );
            try { await File(gpu).delete(); }
            on FileSystemException { /* Owned GPU lease was released. */ }
            return remembered;
          } on TiniEditCancelled {
            try { await File(gpu).delete(); }
            on FileSystemException { /* GPU lease already released. */ }
            rethrow;
          } catch (error, stack) {
            developer.log('GPU checkpoint history unavailable',
              name: 'TiniEditCache', error: error, stackTrace: stack);
            return gpu;
          }
        }
      } on TiniEditCancelled {
        throw CropRetouchCancelled();
      }
    }
    final regions = hardwareRegions(playable);
    // A full untouched source needs neither PNG extraction nor FFV1/MP4
    // preparation. Decode it once directly into the GPU encoder pipeline.
    if (nativeRetouch &&
        playable.length == 1 &&
        _directHardwareSource(playable.single)) {
      final c = playable.single;
      final direct = TiniRetouchExport.node(
        input: sourceNode,
        outputWidth: w,
        outputHeight: h,
        durationMs: c.playbackDuration.inMilliseconds,
        regions: regions,
        muted: c.isMuted,
      );
      try {
        return await _rememberCompleted(
          completed: direct, project: project, signature: signature,
          clips: playable, request: request,
          previousSignature: previousSignature, cancelled: cancelled,
        );
      } on TiniRetouchBaselineRequired {
        // The direct source may carry audio/HDR characteristics the hardware
        // export cannot copy as-is. Prepare the existing compatible baseline,
        // then keep retouch on the GPU; never substitute raw/CPU retouch output.
      } on TiniEditCancelled {
        throw CropRetouchCancelled();
      }
    }
    // Probe hardware only when a new timeline truly needs encoding. Cached
    // exports, simple GPU grading and direct native retouch skip this work.
    // Exynos MediaCodec writes an elementary H.264 stream and the old path
    // reconstructs its packet timestamps while muxing. This is unnecessary
    // after a background cutout and is the suspect non-decodable frame source.
    // Keep one homogeneous libx264 delivery backend for mixed background FX;
    // retain hardware/Media3 for all unrelated, proven-compatible edits.
    final encoder = softwareVideo || legacyVideo || hasBackground
        ? null : await TiniVideoEncoder.probe(w, h);
    final nodes = <TiniEditNode>[];
    final spans = <double>[];
    for (final c in playable) {
      // Structural edits and grading keep their existing canonical order.
      // Both retouch operations are then rendered together over the complete
      // timeline, retaining each clip's own time range and strengths.
      final base = nativeRetouch
          ? c.copyWith(retouch: const CropRetouchSettings())
          : c;
      nodes.add(await clip(originalPath, base, w, h, encoder, legacyVideo,
          allowClipSoftwareFallback: playable.length == 1));
      spans.add(c.playbackDuration.inMicroseconds / 1000000.0);
    }
    if (nodes.isEmpty) throw StateError('No playable segments');
    final joined = TiniEditNode(
      stage: 'timeline.join.effects.media3.v1',
      parameters: {
        'size': [w, h],
        'audio': 'aac128-44100-stereo',
        'boundaries': spans,
      },
      inputs: nodes,
      render: (inputs, stop) async {
        // Use Media3 as the primary lossless video assembler after every
        // specialised Tini visual effect has finished rendering. If a device
        // rejects the container/codec, the old join consumes the SAME inputs.
        final native = !legacyVideo && !softwareVideo && !hasBackground
            ? await _media3JoinRenderedEffects(
                inputs: inputs,
                durations: spans,
                width: w,
                height: h,
                cancelled: stop,
              )
            : null;
        if (native != null) {
          return TiniEditArtifact(native, temporary: true);
        }
        final output = await _output('mp4');
        final list = File('$output.txt');
        try {
          await list.writeAsString(
            [
              for (var index = 0; index < inputs.length; index++)
                "file '${inputs[index].path.replaceAll("'", "'\\''")}'\nduration ${_number(spans[index])}",
            ].join('\n'),
          );
          await _command(
            '-f concat -safe 0 -i "${list.path}" -map 0:v:0 -map 0:a? '
            '-c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 -t ${_number(spans.fold<double>(0, (a, b) => a + b))} -movflags +faststart -y "$output"',
            stop,
          );
          return TiniEditArtifact(output, temporary: true);
        } catch (_) {
          try {
            await File(output).delete();
          } catch (_) {}
          rethrow;
        } finally {
          if (await list.exists()) await list.delete();
        }
      },
    );
    final result = nativeRetouch
        ? TiniRetouchExport.node(
            input: joined,
            outputWidth: w,
            outputHeight: h,
            durationMs:
                playable.fold<int>(
                  0,
                  (total, c) => total + c.playbackDuration.inMicroseconds,
                ) ~/
                1000,
            regions: regions,
          )
        : joined;
    try {
      // A background export is accepted only after a full picture decode,
      // never merely because the MP4 header and packet count look correct.
      // This is a read-only verification, not a repeat export or fallback.
      final verifiedResult = hasBackground
          ? _verifiedBackgroundOutput(result) : result;
      // Resolve the native result as the leaf. A completed cached export does
      // not materialize or copy any structural ancestors again.
      return await _rememberCompleted(
        completed: verifiedResult, project: project, signature: signature,
        clips: playable, request: request,
        previousSignature: previousSignature, cancelled: cancelled,
      );
    } on TiniEditCancelled {
      throw CropRetouchCancelled();
    } on _TiniStreamEncodingFailure catch (error) {
      // Rebuild the WHOLE timeline with one backend. Do not concatenate clips
      // with mixed encoder parameter sets, and never drop an effect on failure.
      if (legacyVideo) rethrow;
      developer.log('$error', name: 'TiniExport.hardwareFallback');
      return render(originalPath: originalPath, clips: clips, width: width, height: height,
          cancelled: cancelled, hardwareRetouch: hardwareRetouch,
          softwareVideo: true, legacyVideo: encoder == null,
          editorRevision: editorRevision, parentEditorRevision: parentEditorRevision);
    }
  }

  static bool _directHardwareSource(CropClip c) =>
      c.startTime == Duration.zero &&
      c.startFraction == 0 &&
      c.endFraction == 1 &&
      c.replacementPath == null &&
      c.rotationQuarterTurns % 4 == 0 &&
      c.speed.isDefault &&
      c.cutout == null &&
      c.backgroundPath == null &&
      c.magicEffectId == null &&
      !c.animations.hasEffects &&
      c.videoEffects.isEmpty &&
      !c.colorFilter.enabled;

  static List<CropRetouchSegment> hardwareRegions(List<CropClip> clips) {
    var elapsedUs = 0;
    final regions = <CropRetouchSegment>[];
    for (final c in clips) {
      if (c.duration.inMicroseconds <= 0) continue;
      final endUs = elapsedUs + c.playbackDuration.inMicroseconds;
      regions.add(
        CropRetouchSegment(
          id: c.id,
          startMs: elapsedUs ~/ 1000,
          endMs: endUs ~/ 1000,
          settings: c.retouch,
        ),
      );
      elapsedUs = endUs;
    }
    return List<CropRetouchSegment>.unmodifiable(regions);
  }
}
