import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'crop_animation_preview.dart';
import 'crop_background_engine.dart';
import 'crop_effects_preview.dart';
import 'crop_magic_live_preview.dart';
import 'crop_model.dart';
import 'crop_rotation.dart';
import 'crop_retouch_gpu.dart';
import 'filter_bottom_sheet.dart';

class CropOverlayVideoState extends ValueNotifier<VideoPlayerValue> {
  CropOverlayVideoState(super.value);

  // A different source can show a different image at the same project time.
  void refresh() => notifyListeners();
}

/// Non-destructive preview clock for the Overlay tool. Project position is
/// calculated from the ordered clip list, not from a pre-exported video.
/// Only the currently displayed source is opened; other sources are lazy.
class CropOverlayProjectPlayer {
  final String sourcePath;
  final List<CropClip> clips;
  final List<FilterClip> filters;
  final String? existingBackgroundPath;
  final String? existingBackgroundClipId;

  final Map<String, VideoPlayerController> _players = {};
  final Map<String, String> _backgroundPaths = {};
  final Set<String> _preparingBackground = {};
  final List<int> _boundaries = [0];
  final CropOverlayVideoState state;

  VideoPlayerController? _active;
  int _index = 0;
  int _positionMs = 0;
  int _generation = 0;
  bool _busy = false;
  bool _closed = false;
  bool _playingWanted = false;
  bool _ended = false;
  double _lastSpeed = -1;
  Size _originalSize;
  final Map<String, String> _backgroundErrors = {};
  String? _playbackError;

  CropOverlayProjectPlayer({
    required this.sourcePath,
    required List<CropClip> projectClips,
    required Size originalSize,
    this.filters = const [],
    this.existingBackgroundPath,
    this.existingBackgroundClipId,
  }) : clips = List.unmodifiable(projectClips),
       _originalSize = originalSize,
       state = CropOverlayVideoState(
         VideoPlayerValue(duration: Duration.zero),
       ) {
    for (final clip in clips) {
      _boundaries.add(
        _boundaries.last + math.max(0, clip.playbackDuration.inMilliseconds),
      );
    }
    state.value = VideoPlayerValue(
      duration: Duration(milliseconds: durationMs),
    );
    if (existingBackgroundPath != null &&
        existingBackgroundClipId != null &&
        File(existingBackgroundPath!).existsSync()) {
      _backgroundPaths[existingBackgroundClipId!] = existingBackgroundPath!;
    }
  }

  int get durationMs => _boundaries.last;
  int get positionMs => _positionMs;
  VideoPlayerController? get activeController => _active;
  CropClip get activeClip => clips[_index];
  int get clipPositionMs => (_positionMs - _boundaries[_index])
      .clamp(0, math.max(0, activeClip.playbackDuration.inMilliseconds))
      .toInt();
  bool get isPlaying => state.value.isPlaying;
  String? get backgroundError => _backgroundErrors[activeClip.id];
  String? get playbackError => _playbackError;
  bool get backgroundLoading =>
      _preparingBackground.contains(activeClip.id);

  int clipIndexAt(int projectMs) {
    final time = projectMs.clamp(0, math.max(0, durationMs - 1));
    for (var i = 0; i < clips.length; i++) {
      if (time < _boundaries[i + 1]) return i;
    }
    return clips.length - 1;
  }

  Duration sourcePositionAt(int projectMs) {
    final index = clipIndexAt(projectMs);
    final offset = (projectMs - _boundaries[index])
        .clamp(0, math.max(0, clips[index].playbackDuration.inMilliseconds));
    return clips[index].sourceAtProjectOffset(offset / 1000.0);
  }

  String sourcePathAt(int projectMs) {
    final index = clipIndexAt(projectMs);
    final clip = clips[index];
    return _backgroundPaths[clip.id] ?? clip.replacementPath ?? sourcePath;
  }

  int mediaPositionAt(int projectMs) {
    final clip = clips[clipIndexAt(projectMs)];
    final position = sourcePositionAt(projectMs);
    final background = _backgroundPaths.containsKey(clip.id);
    return (background
            ? position - clip.startTime
            : clip.replacementPath == null
                ? position
                : clip.replacementStartTime + position - clip.startTime)
        .inMilliseconds
        .clamp(0, 2147483647)
        .toInt();
  }

  // Thumbnail decoding is not part of opening the editor. Frames are loaded
  // asynchronously and never gate playback or overlay editing.
  Future<Uint8List?> thumbnailAt(int projectMs) =>
      VideoThumbnail.thumbnailData(
        video: sourcePathAt(projectMs),
        timeMs: mediaPositionAt(projectMs),
        maxWidth: 120,
        quality: 65,
      );

  Future<void> initialize() async {
    if (clips.isEmpty || durationMs <= 0) {
      throw StateError('لا توجد مقاطع صالحة لمعاينة التراكب');
    }
    await _request(0, play: false);
  }

  bool _needsGpu(String path) => Platform.isAndroid && clips.any(
    (c) => c.retouch.enabled &&
        ((c.replacementPath ?? sourcePath) == path ||
         _backgroundPaths[c.id] == path),
  );

  Future<VideoPlayerController> _openSource(String path) async {
    final existing = _players[path];
    if (existing != null) return existing;
    final player = _needsGpu(path)
        ? CropRetouchGpuController(path)
        : VideoPlayerController.file(
            File(path),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          );
    // Own the player before awaiting its initialization so it is also disposed
    // when the user immediately leaves the editor.
    _players[path] = player;
    try {
      await player.initialize();
      if (_closed) return player;
      await player.setLooping(false);
      // The source's dimensions are the project's preview dimensions even if
      // a replacement clip happens to have a different aspect ratio.
      if (path == sourcePath) _originalSize = player.value.size;
      return player;
    } catch (_) {
      _players.remove(path);
      await player.dispose();
      rethrow;
    }
  }

  void _syncState() {
    if (_closed) return;
    final v = _active?.value;
    final next = VideoPlayerValue(
      duration: Duration(milliseconds: durationMs),
      size: _originalSize.width > 0 && _originalSize.height > 0
          ? _originalSize
          : v?.size ?? const Size(9, 16),
      position: Duration(milliseconds: _positionMs),
      isInitialized: v?.isInitialized ?? false,
      isPlaying: (v?.isPlaying ?? false) && !_ended,
      isCompleted: _ended,
    );
    if (state.value == next) {
      state.refresh();
    } else {
      state.value = next;
    }
  }

  void _tick() {
    if (_closed || _busy || _active == null || !_active!.value.isInitialized) {
      return;
    }
    final clip = activeClip;
    final background = _backgroundPaths.containsKey(clip.id);
    final start = background
        ? Duration.zero
        : clip.replacementPath == null
            ? clip.startTime
            : clip.replacementStartTime;
    final relative = _active!.value.position - start;
    final sourceUnbounded = clip.startTime + relative;
    final source = sourceUnbounded < clip.startTime
        ? clip.startTime
        : sourceUnbounded > clip.endTime
            ? clip.endTime
            : sourceUnbounded;
    final offset = clip.projectOffsetForSource(source);
    _positionMs = (_boundaries[_index] + (offset * 1000).round())
        .clamp(0, durationMs).toInt();
    final fraction = clip.duration.inMicroseconds <= 0
        ? 0.0
        : (source - clip.startTime).inMicroseconds /
              clip.duration.inMicroseconds;
    final speed = clip.speed.speedAt(fraction).clamp(0.1, 10.0).toDouble();
    if ((speed - _lastSpeed).abs() > .035) {
      _lastSpeed = speed;
      _active!.setPlaybackSpeed(speed).catchError((Object error) {
        debugPrint('Tini overlay playback speed: $error');
      });
    }
    _syncState();
    // A cut, deletion, reorder or split ends here; move to the next source
    // without ever rendering the entire timeline.
    if (_playingWanted &&
        (_active!.value.isPlaying || _active!.value.isCompleted) &&
        (relative.inMilliseconds >= clip.duration.inMilliseconds - 35 ||
            _active!.value.isCompleted)) {
      if (_index == clips.length - 1) {
        _ended = true;
        _playingWanted = false;
        _positionMs = durationMs;
        _active!.pause();
        _syncState();
      } else {
        _request(_boundaries[_index + 1], play: true);
      }
    }
  }

  Future<void> _request(int target, {required bool play}) async {
    if (_closed) return;
    _generation++;
    _playingWanted = play;
    _playbackError = null;
    _ended = false;
    _positionMs = target.clamp(0, math.max(0, durationMs - 1)).toInt();
    _syncState();
    if (_busy) return;
    _busy = true;
    try {
      // Coalesce successive scrubs. Only the latest request can play.
      do {
        final serial = _generation;
        final nextIndex = clipIndexAt(_positionMs);
        final clip = clips[nextIndex];
        final path = sourcePathAt(_positionMs);
        final targetMs = mediaPositionAt(_positionMs);
        final previous = _active;
        if (previous != null) {
          previous.removeListener(_tick);
          await previous.pause();
        }
        final player = await _openSource(path);
        if (_closed) return;
        if (serial != _generation) continue;
        _index = nextIndex;
        _active = player;
        _lastSpeed = -1;
        if (player is CropRetouchGpuController) {
          await player.apply(clip.retouch);
        }
        if (_closed || serial != _generation) continue;
        await player.seekTo(Duration(milliseconds: targetMs));
        if (_closed || serial != _generation) continue;
        player.addListener(_tick);
        if (_playingWanted) {
          await player.play();
        }
        _appliedGeneration = serial;
        _syncState();
        _prepareBackground(clip);
      } while (!_closed && _generation != _appliedGeneration);
    } catch (error) {
      if (_closed) return;
      _playingWanted = false;
      _playbackError = 'تعذر تشغيل مقطع في معاينة التراكب: $error';
      debugPrint('Tini overlay project playback: $error');
      final hadActivePlayer = _active != null;
      _active = null; // Never show a stale previous clip after a source failure.
      _syncState();
      if (!hadActivePlayer) rethrow;
    } finally {
      _busy = false;
      if (!_closed) _tick();
    }
  }

  int _appliedGeneration = 0;

  Future<void> pause() async {
    if (_closed) return;
    _playingWanted = false;
    await _active?.pause();
    _syncState();
  }

  Future<void> play() async {
    if (_closed) return;
    if (_ended || positionMs >= durationMs - 50) {
      await _request(0, play: true);
    } else {
      _playingWanted = true;
      if (_active != null) {
        await _active!.play();
        _syncState();
      } else {
        await _request(positionMs, play: true);
      }
    }
  }

  Future<void> seek(int projectMs) => _request(projectMs, play: false);

  void _prepareBackground(CropClip clip) {
    if (_closed ||
        (clip.backgroundPath == null && clip.cutout == null) ||
        _backgroundPaths.containsKey(clip.id) ||
        !_preparingBackground.add(clip.id)) {
      return;
    }
    _backgroundErrors.remove(clip.id);
    _syncState();
    final original = clip.replacementPath ?? sourcePath;
    final start = clip.replacementPath == null
        ? clip.startTime
        : clip.replacementStartTime;
    () async {
      String? path;
      try {
        final width = _originalSize.width > 0 ? _originalSize.width : 360.0;
        final height = _originalSize.height > 0 ? _originalSize.height : 640.0;
        final longestSide = math.max(width, height);
        final previewWidth =
            ((width / longestSide * 640).round().clamp(2, 640) ~/ 2) * 2;
        final previewHeight =
            ((height / longestSide * 640).round().clamp(2, 640) ~/ 2) * 2;
        path = await CropBackgroundEngine.composeClip(
          source: original,
          sourceStart: start,
          clip: clip,
          width: previewWidth,
          height: previewHeight,
          preview: true,
        );
        if (_closed) return;
        _backgroundPaths[clip.id] = path!;
        if (clips[_index].id == clip.id) {
          await _request(positionMs, play: _playingWanted);
        }
      } catch (error) {
        _backgroundErrors[clip.id] = 'تعذرت معاينة الخلفية: $error';
        debugPrint('Tini overlay background preview: $error');
      } finally {
        _preparingBackground.remove(clip.id);
        _syncState();
      }
    }();
  }

  Widget buildPicture() {
    final player = _active;
    if (player == null || !player.value.isInitialized) {
      return const ColoredBox(color: Color(0xFF0F1720));
    }
    final clip = activeClip;
    final elapsed = Duration(milliseconds: clipPositionMs);
    Widget picture = TiniEffectsPreview(
      key: ValueKey(clip.id),
      clipId: clip.id,
      effects: clip.videoEffects,
      colorFilter: clip.colorFilter,
      elapsedSeconds: elapsed.inMicroseconds / 1000000.0,
      sledSourceController: player,
      sledSourcePath: sourcePathAt(positionMs),
      sledSourceTimeMs: player.value.position.inMilliseconds,
      child: CropAnimationPreview(
        settings: clip.animations,
        elapsed: elapsed,
        clipDuration: clip.playbackDuration,
        child: CropMagicLivePreview(
          effectId: clip.magicEffectId,
          child: cropRetouchVideo(player),
        ),
      ),
    );
    final sourcePosition = sourcePositionAt(positionMs);
    final applicable = filters.where((f) =>
        sourcePosition >= f.startTime && sourcePosition <= f.endTime);
    for (final f in applicable.where((f) => !f.filter.isEffect)) {
      picture = ColorFiltered(
        colorFilter: f.filter.colorFilter,
        child: picture,
      );
    }
    for (final f in applicable
        .where((f) => f.filter.isEffect)
        .toList()
        .reversed) {
      picture = f.filter.effectBuilder!(picture);
    }
    return CropRotation.preview(picture, clip.rotationQuarterTurns);
  }

  void dispose() {
    _closed = true;
    _generation++;
    for (final p in _players.values) {
      p.removeListener(_tick);
      unawaited(p.pause().catchError((Object _) {}));
      unawaited(p.dispose());
    }
    _players.clear();
    state.dispose();
    // Preview files generated by TiniEditCache are shared across the editor.
    // Do not delete cached assets owned by the renderer or the parent screen.
  }
}
