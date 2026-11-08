import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A device-probed hardware encoder, never a software codec selected by name.
class TiniVideoEncoder {
  final String name, pixelFormat;
  final int bitrate, operatingRate;
  final bool vbr, high;
  const TiniVideoEncoder(
    this.name,
    this.pixelFormat,
    this.bitrate,
    this.vbr,
    this.high, {
    this.operatingRate = 30,
  });

  static final _probes = <String, Future<TiniVideoEncoder?>>{};
  static Future<TiniVideoEncoder?> probe(int width, int height) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(null);
    }
    return _probes.putIfAbsent('$width:$height', () async {
      try {
        final data = await const MethodChannel('titi_star/retouch_export')
            .invokeMapMethod<String, dynamic>('videoEncoder', {
              'id': 'video-encoder-capabilities',
              'width': width,
              'height': height,
            });
        if (data == null ||
            data['hardware'] != true ||
            data['name'] is! String ||
            data['bitrate'] is! num ||
            (data['bitrate'] as num) <= 0 ||
            !const {'nv12', 'yuv420p'}.contains(data['pixelFormat'])) {
          return null;
        }
        return TiniVideoEncoder(
          data['name'] as String,
          data['pixelFormat'] as String,
          (data['bitrate'] as num).toInt(),
          data['vbr'] == true,
          data['high'] == true,
          operatingRate: ((data['operatingRate'] as num?)?.toInt() ?? 30).clamp(
            30,
            240,
          ),
        );
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    });
  }

  Map<String, Object> get identity => {
    'codec': name,
    'pixel': pixelFormat,
    'bitrate': bitrate,
    'vbr': vbr,
    'high': high,
    'operatingRate': operatingRate,
  };
}

/// Original filter recipes, executed on a frame stream in their original order.
/// A checkpoint is materialized only where an external/native effect needs it.
class TiniVideoPipeline {
  final int? trimStartUs, trimDurationUs;
  final bool muted;
  final List<Map<String, Object?>> steps;
  final String? inputBoundary;
  final List<String> boundaries;
  final bool rgbOutput;
  TiniVideoPipeline.source(Duration duration)
    : trimStartUs = null,
      trimDurationUs = duration.inMicroseconds,
      muted = false,
      steps = const [],
      inputBoundary = null,
      boundaries = const [],
      rgbOutput = false;
  TiniVideoPipeline.trim(Duration start, Duration duration, this.muted)
    : trimStartUs = start.inMicroseconds,
      trimDurationUs = duration.inMicroseconds,
      steps = const [],
      inputBoundary = null,
      boundaries = const [],
      rgbOutput = false;
  TiniVideoPipeline._(
    this.trimStartUs,
    this.trimDurationUs,
    this.muted,
    this.steps, [
    this.inputBoundary,
    this.boundaries = const [],
    this.rgbOutput = false,
  ]);

  TiniVideoPipeline preserveBoundaries(
    String? first,
    List<String> values, {
    required bool rgb,
    required List<List<String>> filters,
  }) => TiniVideoPipeline._(
    trimStartUs,
    trimDurationUs,
    muted,
    List.unmodifiable([
      for (var i = 0; i < steps.length; i++)
        Map<String, Object?>.unmodifiable({
          ...steps[i],
          'filters': List<String>.unmodifiable(filters[i]),
        }),
    ]),
    first,
    List.unmodifiable(values),
    rgb,
  );

  TiniVideoPipeline then(
    String stage,
    Object? settings,
    List<String> filters,
  ) => TiniVideoPipeline._(
    trimStartUs,
    trimDurationUs,
    muted,
    List.unmodifiable([
      ...steps,
      {
        'stage': stage,
        'settings': settings,
        'filters': List<String>.unmodifiable(filters),
      },
    ]),
  );
  Map<String, Object?> get identity => {
    'schema': 4,
    'boundaries': 'ffv1-metadata-v1',
    'startUs': trimStartUs,
    'durationUs': trimDurationUs,
    'muted': muted,
    'steps': steps,
  };

  static bool accepts(List<String> filters) =>
      !filters.any((f) => RegExp(r'\[\d+:').hasMatch(f));

  // Rename only links, never brackets inside escaped/quoted drawtext options.
  static String _links(String text, int index) {
    final out = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == r'\' && i + 1 < text.length) {
        out.write(text[i]);
        out.write(text[++i]);
        continue;
      }
      if (text[i] == "'") quoted = !quoted;
      if (!quoted && text[i] == '[') {
        final end = text.indexOf(']', i + 1);
        if (end >= 0) {
          final label = text.substring(i + 1, end);
          if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(label)) {
            out.write(
              label == 'src'
                  ? '[tv$index]'
                  : label == 'dst'
                  ? '[tv${index + 1}]'
                  : '[tv${index}_$label]',
            );
            i = end;
            continue;
          }
        }
      }
      out.write(text[i]);
    }
    return out.toString();
  }

  String _step(int index) {
    final graph = _links(
      (steps[index]['filters'] as List<String>).join(';'),
      index,
    );
    if (boundaries.isEmpty) return graph;
    final output = '[tv${index + 1}]';
    final at = graph.lastIndexOf(output);
    if (at < 0) throw StateError('Filter has no output link');
    return '${graph.substring(0, at)}[tf$index];[tf$index]${boundaries[index]}'
        '$output${graph.substring(at + output.length)}';
  }

  String _graph(String last) => [
    trimStartUs == null
        ? '[0:v]null[tv0]'
        : '[0:v]setpts=PTS-STARTPTS,fps=30${inputBoundary == null ? '' : ',$inputBoundary'}[tv0]',
    for (var i = 0; i < steps.length; i++) _step(i),
    '[tv${steps.length}]$last[video]',
  ].join(';');

  List<String> _inputs(String input) => [
    if (trimStartUs != null) ...[
      '-ss',
      _seconds(trimStartUs!),
      '-t',
      _seconds(trimDurationUs!),
    ],
    '-i',
    input,
    if (trimDurationUs != null) ...[
      '-f',
      'lavfi',
      '-t',
      _seconds(trimDurationUs!),
      '-i',
      'anullsrc=channel_layout=stereo:sample_rate=44100',
    ],
  ];
  static String _seconds(int value) => (value / 1000000).toStringAsFixed(6);
  List<String> _audio(bool sourceAudio) => trimStartUs == null && sourceAudio
      ? ['-map', '0:a?', '-c:a', 'copy']
      : [
          '-map',
          '${sourceAudio && !muted ? 0 : 1}:a:0',
          '-af',
          'asetpts=PTS-STARTPTS,aresample=44100',
          '-c:a',
          'pcm_s16le',
          '-ar',
          '44100',
          '-ac',
          '2',
          '-t',
          _seconds(trimDurationUs!),
        ];

  List<String> checkpoint(String input, String output, bool sourceAudio) => [
    ..._inputs(input),
    '-filter_complex',
    _graph('null'),
    '-map',
    '[video]',
    ..._audio(sourceAudio),
    '-c:v',
    'ffv1',
    '-level',
    '3',
    '-fps_mode',
    'passthrough',
    '-y',
    output,
  ];

  // A Matroska millisecond time base is a precision boundary, not a frame
  // rate. State the delivery clock explicitly before MediaCodec; otherwise
  // some Android FFmpeg builds expand 0.8 seconds into 800 encoder frames.
  String _delivery(String pixel) =>
      '${rgbOutput ? 'scale=iw:ih:out_range=tv,format=$pixel,setparams=range=tv:colorspace=unknown' : 'format=$pixel'},fps=30,trim=duration=${_seconds(trimDurationUs!)}';

  List<String> software(String input, String output, bool sourceAudio) => [
    ..._inputs(input),
    '-filter_complex',
    _graph(_delivery('yuv420p')),
    '-map',
    '[video]',
    ..._audio(sourceAudio),
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-crf',
    '18',
    '-bf',
    '0',
    '-pix_fmt',
    'yuv420p',
    '-r',
    '30',
    '-enc_time_base:v',
    '1/30',
    '-t',
    _seconds(trimDurationUs!),
    '-fps_mode',
    'cfr',
    '-y',
    output,
  ];

  /// Hardware produces a compressed elementary stream, avoiding the MP4 global
  /// header limitation in MediaCodec. The subsequent mux only copies packets.
  List<String> encode(
    String input,
    String video,
    String audio,
    TiniVideoEncoder encoder,
    bool sourceAudio,
  ) => [
    ..._inputs(input),
    '-filter_complex',
    _graph(_delivery(encoder.pixelFormat)),
    '-map',
    '[video]',
    '-an',
    '-c:v',
    'h264_mediacodec',
    '-codec_name',
    encoder.name,
    '-ndk_codec',
    '1',
    '-bitrate_mode',
    encoder.vbr ? 'vbr' : 'cbr',
    '-b:v',
    '${encoder.bitrate}',
    '-bf',
    '0',
    '-g',
    '60',
    if (encoder.high) ...['-profile:v', 'high'],
    '-operating_rate',
    '${encoder.operatingRate}',
    '-flags:v',
    '-global_header',
    '-r',
    '30',
    '-enc_time_base:v',
    '1/30',
    '-t',
    _seconds(trimDurationUs!),
    '-fps_mode',
    'cfr',
    '-f',
    'h264',
    '-y',
    video,
    ..._audio(sourceAudio),
    '-vn',
    '-f',
    'matroska',
    '-y',
    audio,
  ];

  // MOV stores exact sample durations for AVC + PCM, avoiding a vendor's
  // default-rate hint in Matroska. Only zero-B-frame streams reach this mux.
  // Rebuild the packet clock; neither picture nor sound is re-encoded here.
  static List<String> mux(String video, String audio, String output) => [
    '-r',
    '30',
    '-fflags',
    '+genpts',
    '-i',
    video,
    '-i',
    audio,
    '-map',
    '0:v:0',
    '-map',
    '1:a?',
    '-r:v',
    '30',
    '-bsf:v',
    'h264_metadata=tick_rate=60,setts=pts=N/(30*TB):dts=N/(30*TB):duration=1/(30*TB)',
    '-c',
    'copy',
    '-video_track_timescale',
    '30',
    '-f',
    'mov',
    '-y',
    output,
  ];
}
