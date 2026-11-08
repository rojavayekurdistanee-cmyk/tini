import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android Media3 Transformer exporter. The Tini edit graph owns effects and
/// history; callers may submit only media operations supported by this bridge.
class TiniMedia3Export {
  TiniMedia3Export._();

  static const MethodChannel _channel = MethodChannel('titi_star/media3_export');
  static int _serial = 0;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isAvailable() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static String _nextId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_serial++}';

  static void _validateMatrix(List<double>? matrix) {
    if (matrix == null) return;
    if (matrix.length != 20 || matrix.any((n) => !n.isFinite) ||
        matrix[15] != 0 || matrix[16] != 0 ||
        matrix[17] != 0 || matrix[18] != 1 || matrix[19] != 0) {
      throw ArgumentError('Media3 only supports an RGB 4x5 colour matrix with unchanged alpha');
    }
  }

  /// Starts a native export job. Call only from an explicitly permitted
  /// export/render operation; this method does not trigger publishing.
  static TiniMedia3Job start({
    required String inputPath,
    Duration start = Duration.zero,
    Duration? end,
    bool mute = false,
    List<double>? colorMatrix,
  }) {
    if (!isAndroid) {
      throw UnsupportedError('Media3 export is available on Android only');
    }
    if (inputPath.isEmpty || start.isNegative ||
        (end != null && end <= start)) {
      throw ArgumentError('Invalid source or clipping range');
    }
    _validateMatrix(colorMatrix);
    final id = _nextId();
    final result = _channel.invokeMethod<String>('start', <String, Object?>{
      'id': id,
      'inputPath': inputPath,
      'startMs': start.inMilliseconds,
      if (end != null) 'endMs': end.inMilliseconds,
      'mute': mute,
      if (colorMatrix != null) 'colorMatrix': colorMatrix,
    }).then(_requirePath);
    return TiniMedia3Job._(id, result);
  }

  /// Renders one chronological timeline with Media3 Transformer, keeping the
  /// source/audio of each piece. Tini-specific effects must be applied by the
  /// existing edit graph before a segment is passed to this API.
  static TiniMedia3Job startTimeline({
    required List<TiniMedia3Segment> segments,
    // For fully rendered effect checkpoints, copy encoded video packets.
    // Media3 must report transmuxing; otherwise Tini keeps its original muxer.
    bool transmuxRenderedVideo = false,
  }) {
    if (!isAndroid) {
      throw UnsupportedError('Media3 export is available on Android only');
    }
    if (segments.isEmpty) throw ArgumentError('Timeline cannot be empty');
    for (final segment in segments) {
      if (segment.inputPath.isEmpty || segment.start.isNegative ||
          segment.end <= segment.start) {
        throw ArgumentError('Invalid Media3 timeline segment');
      }
      _validateMatrix(segment.colorMatrix);
      if (!segment.speed.isFinite || segment.speed < 0.1 || segment.speed > 10) {
        throw ArgumentError('Invalid Media3 clip speed');
      }
    }
    final id = _nextId();
    final result = _channel.invokeMethod<String>(
      'startTimeline',
      <String, Object?>{
        'id': id,
        'segments': segments.map((segment) => segment._asMap()).toList(),
        'transmuxRenderedVideo': transmuxRenderedVideo,
      },
    ).then(_requirePath);
    return TiniMedia3Job._(id, result);
  }

  /// Mixes an independent music track over a previously completed MP4 without
  /// re-running video effects. Native Transformer is requested to transmux video.
  /// The Tini FFmpeg audio compositor remains the compatibility fallback.
  static TiniMedia3Job startMusicMix({
    required String videoPath,
    required String audioPath,
    required Duration duration,
    required Duration musicStart,
    required Duration musicEnd,
    required double videoVolume,
    required double musicVolume,
  }) {
    if (!isAndroid) {
      throw UnsupportedError('Media3 export is available on Android only');
    }
    if (videoPath.isEmpty || audioPath.isEmpty || duration <= Duration.zero ||
        musicStart.isNegative || musicStart >= musicEnd || musicEnd > duration ||
        !videoVolume.isFinite || !musicVolume.isFinite ||
        videoVolume < 0 || musicVolume < 0 ||
        videoVolume > 2 || musicVolume > 2) {
      throw ArgumentError('Invalid Media3 music mix request');
    }
    final id = _nextId();
    final result = _channel.invokeMethod<String>('startMusicMix', <String, Object?>{
      'id': id,
      'videoPath': videoPath,
      'audioPath': audioPath,
      'durationMs': duration.inMilliseconds,
      'musicStartMs': musicStart.inMilliseconds,
      'musicEndMs': musicEnd.inMilliseconds,
      'videoVolume': videoVolume,
      'musicVolume': musicVolume,
    }).then(_requirePath);
    return TiniMedia3Job._(id, result);
  }

  static String _requirePath(String? path) {
    if (path == null || path.isEmpty) {
      throw StateError('Media3 returned no output file');
    }
    return path;
  }
}

@immutable
class TiniMedia3Segment {
  const TiniMedia3Segment({
    required this.inputPath,
    required this.start,
    required this.end,
    this.mute = false,
    this.colorMatrix,
    this.speed = 1.0,
  });

  final String inputPath;
  final Duration start;
  final Duration end;
  final bool mute;
  final List<double>? colorMatrix;
  /// Constant source-time playback speed; animated curves stay on Tini's renderer.
  final double speed;

  Map<String, Object?> _asMap() => <String, Object?>{
    'inputPath': inputPath,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'mute': mute,
    'speed': speed,
    if (colorMatrix != null) 'colorMatrix': colorMatrix,
  };
}

class TiniMedia3Job {
  TiniMedia3Job._(this.id, this.result);

  final String id;
  final Future<String> result;

  /// Returns 0..100 while Transformer exposes progress, otherwise null.
  Future<int?> progress() async {
    final data = await TiniMedia3Export._channel
        .invokeMapMethod<String, dynamic>('progress', {'id': id});
    final value = data?['percent'];
    return value is num ? value.toInt().clamp(0, 100).toInt() : null;
  }

  Future<bool> cancel() async =>
      await TiniMedia3Export._channel
          .invokeMethod<bool>('cancel', {'id': id}) ?? false;
}
