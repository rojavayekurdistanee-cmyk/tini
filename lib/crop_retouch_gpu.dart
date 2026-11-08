import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'crop_retouch_model.dart';

/// An Android hardware decoder + GPU texture. It replaces the editor's player;
/// it does not start a second VideoPlayer or generate processed video files.
class CropRetouchGpuController extends VideoPlayerController
    with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('titi_star/retouch_gpu');
  final String _path;
  int? _id;
  int? textureId;
  int faceCount = -1;
  int thermalStatus = 0;
  bool thermalPaused = false;
  bool _closed = false, _polling = false, _foreground = true;
  Timer? _timer;
  int _idlePollsRemaining = 0;
  List<CropRetouchSegment> _regions = const [];
  CropRetouchSettings _settings = const CropRetouchSettings();
  CropRetouchGpuController(String path)
    : _path = Uri.tryParse(path)?.scheme == 'file'
          ? Uri.parse(path).toFilePath()
          : path,
      super.file(File(path));

  @override
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('create', {
        'path': _path,
      });
      if (info == null) throw StateError('لم يرجع مشغل المعاينة بيانات');
      _id = (info['id'] as num).toInt();
      textureId = (info['textureId'] as num).toInt();
      if (_closed) {
        await _channel.invokeMethod<void>('dispose', {'id': _id});
        return;
      }
      value = VideoPlayerValue(
        duration: Duration(milliseconds: (info['durationMs'] as num).toInt()),
        size: Size(
          (info['width'] as num).toDouble(),
          (info['height'] as num).toDouble(),
        ),
        isInitialized: true,
      );
      await apply(_settings, regions: _regions);
      _wake();
    } catch (error) {
      if (!_closed) {
        value = VideoPlayerValue.erroneous('تعذر بدء معاينة GPU: $error');
      }
      rethrow;
    }
  }

  Future<void> _call(
    String method, [
    Map<String, Object?> data = const {},
  ]) async {
    if (_closed || _id == null) return;
    await _channel.invokeMethod<void>(method, {'id': _id, ...data});
  }

  Future<void> apply(
    CropRetouchSettings settings, {
    List<CropRetouchSegment> regions = const [],
  }) async {
    _settings = settings;
    _regions = List.unmodifiable(regions);
    await _call('settings', {
      'smooth': settings.smooth,
      'teeth': settings.teeth,
      'regions': [
        for (final r in regions)
          {
            'startMs': r.startMs,
            'endMs': r.endMs,
            'smooth': r.settings.smooth,
            'teeth': r.settings.teeth,
          },
      ],
    });
    _wake();
  }

  void _wake() {
    if (_closed || !_foreground || _id == null) return;
    _idlePollsRemaining = 12;
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _poll(),
    );
    _poll();
  }

  Future<void> _poll() async {
    if (_closed || _id == null || _polling) return;
    _polling = true;
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('state', {
        'id': _id,
      });
      if (_closed || info == null) return;
      final oldFaces = faceCount, oldThermal = thermalStatus;
      final oldThermalPaused = thermalPaused;
      final oldValue = value;
      faceCount = (info['faces'] as num?)?.toInt() ?? -1;
      thermalStatus = (info['thermalStatus'] as num?)?.toInt() ?? 0;
      thermalPaused = info['thermalPaused'] == true;
      final error = info['error'] as String?;
      value = value.copyWith(
        position: Duration(
          milliseconds: (info['positionMs'] as num?)?.toInt() ?? 0,
        ),
        isPlaying: info['playing'] == true,
        isCompleted: info['completed'] == true,
        errorDescription: error,
      );
      if (value == oldValue &&
          (oldFaces != faceCount ||
              oldThermal != thermalStatus ||
              oldThermalPaused != thermalPaused)) {
        notifyListeners();
      }
      if (!value.isPlaying &&
          info['tracking'] != true &&
          --_idlePollsRemaining <= 0) {
        _timer?.cancel();
        _timer = null;
      }
    } catch (error) {
      if (!_closed) {
        value = value.copyWith(
          isPlaying: false,
          errorDescription: 'تعذرت معاينة GPU: $error',
        );
        _timer?.cancel();
        _timer = null;
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Future<Duration?> get position async => value.position;

  @override
  Future<void> play() async {
    await _call('play');
    if (_closed) return;
    value = value.copyWith(isPlaying: true, isCompleted: false);
    _wake();
  }

  @override
  Future<void> pause() async {
    await _call('pause');
    if (_closed) return;
    value = value.copyWith(isPlaying: false);
    _wake();
  }

  @override
  Future<void> seekTo(Duration position) async {
    final ms = position.inMilliseconds.clamp(0, value.duration.inMilliseconds);
    await _call('seek', {'positionMs': ms});
    if (_closed) return;
    value = value.copyWith(
      position: Duration(milliseconds: ms),
      isCompleted: false,
    );
    _wake();
  }

  @override
  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    await _call('volume', {'volume': v});
    if (!_closed) value = value.copyWith(volume: v);
  }

  @override
  Future<void> setLooping(bool looping) async {
    await _call('loop', {'looping': looping});
    if (!_closed) value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    final v = speed.clamp(.1, 10.0);
    await _call('speed', {'speed': v});
    if (!_closed) value = value.copyWith(playbackSpeed: v);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      pause();
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    final id = _id;
    _id = null;
    try {
      if (id != null) await _channel.invokeMethod<void>('dispose', {'id': id});
    } finally {
      await super.dispose();
    }
  }
}

Widget cropRetouchVideo(VideoPlayerController controller) =>
    controller is CropRetouchGpuController && controller.textureId != null
    ? Texture(textureId: controller.textureId!)
    : VideoPlayer(controller);
