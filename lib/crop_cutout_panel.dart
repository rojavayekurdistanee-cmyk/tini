import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:image/image.dart' as img;
import 'crop_background_engine.dart';
import 'crop_background_model.dart';
import 'crop_model.dart';

/// Edits the selected source clip. Unconfirmed edits never modify the project.
/// Both source playback and processed preview retain the source aspect ratio.
class CropCutoutPanel extends StatefulWidget {
  final String sourcePath;
  final Duration sourceStart;
  final CropClip clip;

  const CropCutoutPanel({super.key, required this.sourcePath,
    required this.sourceStart, required this.clip});

  @override
  State<CropCutoutPanel> createState() => _CropCutoutPanelState();
}

class CropCutoutResult {
  final CutoutSettings? settings;
  const CropCutoutResult(this.settings);
}

enum _CutoutMode { main, custom, chroma, edges }
enum _CutoutTool { quick, brush, eraser }

class _CropCutoutPanelState extends State<CropCutoutPanel>
    with WidgetsBindingObserver {
  static const _thumbs = MethodChannel('titi_star/thumbnails');
  CutoutSettings? _settings;
  final List<CutoutStroke> _strokes = [];
  final List<CutoutStroke> _redoStrokes = [];
  final List<Uint8List> _timelineFrames = [];
  List<Offset> _drawing = [];
  Offset? _finger;
  _CutoutMode _mode = _CutoutMode.main;
  _CutoutTool _tool = _CutoutTool.quick;
  double _brushRadius = .025;
  double _videoRatio = 9 / 16;
  bool _busy = false;
  bool _rendering = false;
  bool _renderAgain = false;
  bool _showOriginal = false;
  bool _disposed = false;
  Timer? _brushIdleTimer;
  Timer? _edgeRenderTimer;
  bool _edgeFeatherVisible = false;
  // Chroma selection is interactive; FFmpeg runs only after a pause in editing.
  Timer? _chromaRenderTimer;
  Timer? _chromaPixelTimer;
  Uint8List? _chromaSourceRgba;
  ui.Image? _chromaSourceImage;
  ui.Image? _chromaLiveImage;
  // RGBA image with cumulative alpha stored as opaque RGB luminance.
  ui.Image? _chromaCommittedMaskImage;
  int _chromaMaskRevision = 0;
  ui.FragmentProgram? _chromaShaderProgram;
  bool _chromaShaderLoading = false;
  bool _chromaShaderUnavailable = false;
  int _chromaSourceWidth = 0;
  int _chromaSourceHeight = 0;
  int _chromaFrameRequest = 0;
  int _chromaPixelRevision = 0;
  int _chromaSettingsRevision = 0;
  bool _chromaPixelBusy = false;
  bool _chromaPreviewVisible = false;
  bool _chromaRenderFresh = false;
  int? _chromaPointer;
  Offset _chromaPosition = const Offset(.5, .35);
  bool _manualPreviewPending = false;
  int _progress = 0;
  String? _error;
  VideoPlayerController? _sourcePlayer;
  VideoPlayerController? _processedPlayer;
  String? _processedPath;
  StreamSubscription<dynamic>? _progressSubscription;
  Duration _position = Duration.zero;
  DateTime _lastUiTick = DateTime.fromMillisecondsSinceEpoch(0);
  bool _seeking = false;
  ui.Image? _magnifierImage;
  int? _activeBrushPointer;
  int _strokeRevision = 0;
  bool _magnifierLoading = false;
  bool _magnifierRefreshPending = false;
  int _magnifierRequestId = 0;
  String? _magnifierFrameSource;
  int? _magnifierFrameTimeMs;

  Duration get _clipDuration => widget.clip.duration;
  String get _localPath {
    final uri = Uri.tryParse(widget.sourcePath);
    return uri?.scheme == 'file' ? uri!.toFilePath() : widget.sourcePath;
  }

  VideoPlayerController? get _activePlayer {
    if (_mode == _CutoutMode.chroma && _chromaPreviewVisible) {
      return _sourcePlayer;
    }
    if (!_showOriginal && !_manualPreviewPending &&
        _processedPlayer?.value.isInitialized == true) {
      return _processedPlayer;
    }
    return _sourcePlayer;
  }

  bool get _playing => _activePlayer?.value.isPlaying ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings = widget.clip.cutout;
    if (_settings != null) _strokes.addAll(_settings!.strokes);
    _progressSubscription = const EventChannel('titi_star/cutout/progress')
        .receiveBroadcastStream().listen((event) {
      if (!_disposed && mounted && _busy && event is num) {
        setState(() => _progress = event.toInt().clamp(0, 100).toInt());
      }
    }, onError: (_) {});
    _initializeVideo();
    _loadTimeline();
  }

  Future<void> _initializeVideo() async {
    final player = VideoPlayerController.file(File(_localPath));
    try {
      await player.initialize();
      if (!mounted || _disposed) { await player.dispose(); return; }
      await player.setLooping(false);
      await player.seekTo(widget.sourceStart);
      player.addListener(_onVideoTick);
      setState(() {
        _sourcePlayer = player;
        if (player.value.aspectRatio > 0) _videoRatio = player.value.aspectRatio;
      });
      if (_settings != null) _queueRender();
    } catch (error) {
      await player.dispose();
      if (mounted && !_disposed) setState(() => _error = 'تعذر فتح الفيديو: $error');
    }
  }

  Future<void> _loadTimeline() async {
    try {
      final result = await _thumbs.invokeMethod<List<dynamic>>('getFrames', {
        'path': _localPath, 'count': 10, 'thumbHeight': 76,
      });
      if (!mounted || _disposed || result == null) return;
      setState(() => _timelineFrames.addAll(result.whereType<Uint8List>()));
    } catch (_) {
      // Timeline remains operable without thumbnails.
    }
  }

  void _onVideoTick() {
    final player = _activePlayer;
    if (_disposed || !mounted || player == null || !player.value.isInitialized || _seeking) return;
    final current = player == _sourcePlayer
        ? player.value.position - widget.sourceStart : player.value.position;
    final bounded = Duration(microseconds:
      current.inMicroseconds.clamp(0, _clipDuration.inMicroseconds).toInt());
    if (player.value.isPlaying && current >= _clipDuration) {
      player.pause();
      _seekTo(Duration.zero);
    }
    if (DateTime.now().difference(_lastUiTick).inMilliseconds >= 90 ||
        (bounded - _position).inMilliseconds.abs() > 400) {
      _lastUiTick = DateTime.now();
      setState(() => _position = bounded);
    }
  }

  Future<void> _seekTo(Duration offset) async {
    if (_disposed) return;
    final previousPosition = _position;
    final bounded = Duration(microseconds:
        offset.inMicroseconds.clamp(0, _clipDuration.inMicroseconds).toInt());
    setState(() => _position = bounded);
    _seeking = true;
    try {
      final active = _activePlayer;
      if (active != null && active.value.isInitialized) {
        await active.seekTo(active == _sourcePlayer
            ? widget.sourceStart + bounded : bounded);
      }
    } finally {
      _seeking = false;
    }
    if (_mode == _CutoutMode.custom && _finger == null) {
      _captureMagnifierFrame();
    }
    if (_mode == _CutoutMode.chroma && _chromaPreviewVisible &&
        _chromaPointer == null &&
        (_position - previousPosition).inMilliseconds.abs() > 65) {
      _loadChromaFrame();
    }
  }

  Future<void> _togglePlay() async {
    if (_mode == _CutoutMode.chroma && !_showOriginal &&
        _chromaPreviewVisible) {
      if (!_chromaRenderFresh || _busy || _rendering) {
        _message('انتظر اكتمال معاينة الكروما لتشغيل الفيديو.');
        return;
      }
      setState(() => _chromaPreviewVisible = false);
      await _seekTo(_position);
    }
    final player = _activePlayer;
    if (_busy || player == null || !player.value.isInitialized) return;
    if (player.value.isPlaying) { await player.pause(); return; }
    if (_position >= _clipDuration - const Duration(milliseconds: 90)) {
      await _seekTo(Duration.zero);
    }
    await player.play();
    if (mounted) setState(() {});
  }

  Future<void> _switchPreview(bool showOriginal) async {
    if (_showOriginal == showOriginal) return;
    final wasPlaying = _playing;
    await _activePlayer?.pause();
    if (!mounted) return;
    setState(() => _showOriginal = showOriginal);
    await _seekTo(_position);
    if (_mode == _CutoutMode.custom) _captureMagnifierFrame();
    if (_mode == _CutoutMode.chroma && !showOriginal) {
      setState(() => _chromaPreviewVisible = true);
      _loadChromaFrame();
      return; // A still frame must not hide a playing source video.
    }
    if (wasPlaying && !_busy) await _activePlayer?.play();
  }

  Future<void> _generate() async {
    if (_busy || _rendering) return;
    _brushIdleTimer?.cancel();
    _brushIdleTimer = null;
    _edgeRenderTimer?.cancel();
    _edgeRenderTimer = null;
    _manualPreviewPending = false;
    await _activePlayer?.pause();
    if (!mounted) return;
    final edgeBeforeMask = _settings;
    setState(() { _busy = true; _progress = 0; _error = null; });
    try {
      final result = await CropBackgroundEngine.createMasks(
        videoPath: _localPath,
        sourceStart: widget.sourceStart,
        duration: _clipDuration,
        edgeQuality: _mode == _CutoutMode.edges,
      );
      if (!mounted || _disposed) return;
      // Only edge appearance survives refreshing the person mask. Existing
      // strokes and unrelated cutout settings keep their original reset rules.
      final edgeResult = edgeBeforeMask == null ? result : result.withOptions(
        edgeStyle: edgeBeforeMask.edgeStyle,
        edgeColor: edgeBeforeMask.edgeColor,
        edgeSize: edgeBeforeMask.edgeSize,
        edgeDistance: edgeBeforeMask.edgeDistance,
        edgeOpacity: edgeBeforeMask.edgeOpacity,
        edgeFeather: edgeBeforeMask.edgeFeather);
      setState(() {
        _settings = edgeResult;
        _strokes.clear();
        _redoStrokes.clear();
        _strokeRevision++;
        _showOriginal = false;
        _progress = 100;
      });
      await _renderResult();
    } catch (error) {
      if (mounted && !_disposed) setState(() => _error = _shortError(error));
    } finally {
      if (mounted && !_disposed) setState(() => _busy = false);
    }
  }

  String _shortError(Object e) {
    final value = e.toString();
    return value.length > 280 ? '${value.substring(0, 280)}…' : value;
  }

  // Only one FFmpeg render is allowed at a time. Intermediate brush strokes
  // are coalesced; obsolete previews are not installed after a newer change.
  Future<void> _queueRender() async {
    if (_settings == null) return;
    if (_rendering) { _renderAgain = true; return; }
    _rendering = true;
    do {
      _renderAgain = false;
      if (_disposed) break;
      if (mounted) setState(() { _busy = true; _error = null; });
      try { await _renderResult(); }
      catch (error) {
        if (mounted && !_disposed) setState(() => _error = _shortError(error));
      }
    } while (_renderAgain && !_disposed);
    _rendering = false;
    if (mounted && !_disposed) setState(() => _busy = false);
  }

  Future<void> _renderResult() async {
    final chromaRevision = _chromaSettingsRevision;
    final settings = _settings;
    if (settings == null || _disposed) return;
    final clip = widget.clip.withCutout(settings.withStrokes(_strokes));
    // Preserve the source aspect ratio instead of rendering every video 9:16.
    final r = _videoRatio.clamp(.4, 2.5).toDouble();
    final w = r <= 1 ? 360 : 640;
    final h = r <= 1 ? ((360 / r).round() ~/ 2 * 2) : ((640 / r).round() ~/ 2 * 2);
    final result = await CropBackgroundEngine.composeClip(
      source: _localPath, sourceStart: widget.sourceStart,
      clip: clip, width: w, height: h, preview: true);
    if (!mounted || _disposed || _renderAgain ||
        (_mode == _CutoutMode.chroma && !settings.chromaEnabled) ||
        (settings.chromaEnabled &&
            chromaRevision != _chromaSettingsRevision)) {
      try { await File(result).delete(); } catch (_) {}
      return;
    }
    final player = VideoPlayerController.file(File(result));
    try {
      await player.initialize();
      if (!mounted || _disposed || _renderAgain ||
          (_mode == _CutoutMode.chroma && !settings.chromaEnabled) ||
          (settings.chromaEnabled &&
              chromaRevision != _chromaSettingsRevision)) {
        await player.dispose();
        try { await File(result).delete(); } catch (_) {}
        return;
      }
      await player.setLooping(false);
      player.addListener(_onVideoTick);
      final old = _processedPlayer;
      final previous = _processedPath;
      await old?.pause();
      setState(() {
        _processedPlayer = player; _processedPath = result;
        if (_settings?.manualMask == true) {
          _manualPreviewPending = false;
          _showOriginal = false;
        }
        if (_mode == _CutoutMode.chroma) _chromaRenderFresh = true;
      });
      await _seekTo(_position);
      await old?.dispose();
      if (previous != null) {
        try { await File(previous).delete(); } catch (_) {}
      }
    } catch (_) {
      await player.dispose();
      try { await File(result).delete(); } catch (_) {}
      rethrow;
    }
  }

  void _openCustom() {
    _activePlayer?.pause();
    setState(() => _mode = _CutoutMode.custom);
    _captureMagnifierFrame();
  }

  Future<void> _openEdges() async {
    if (_busy) return;
    if (_settings?.chromaEnabled == true && _settings?.hasMask != true) {
      _message('تأثير الحواف يحتاج قناع عزل للشخص؛ لن يتم استبدال الكروما الحالية.');
      return;
    }
    _activePlayer?.pause();
    if (_settings?.hasMask != true) {
      final accepted = await showDialog<bool>(context: context, builder: (dialog) =>
        AlertDialog(backgroundColor: const Color(0xFF1A222C),
          title: const Text('قص الخلفية تلقائيًا',
            style: TextStyle(color: Colors.white)),
          content: const Text('لإضافة تأثيرات الحواف يجب عزل الشخص أولًا. '
              'هل تريد تشغيل قص الخلفية التلقائي؟',
            style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('متابعة', style: TextStyle(color: Colors.tealAccent))),
          ]));
      if (!mounted || accepted != true) return;
      setState(() => _mode = _CutoutMode.edges);
      await _generate();
      return;
    }
    setState(() => _mode = _CutoutMode.edges);
  }

  void _scheduleEdgeRender() {
    _edgeRenderTimer?.cancel();
    _edgeRenderTimer = Timer(const Duration(milliseconds: 250), () {
      _edgeRenderTimer = null;
      if (!_disposed && _settings?.hasMask == true) unawaited(_queueRender());
    });
  }

  void _changeEdge({CutoutEdgeStyle? style, int? color, double? size,
      double? distance, double? opacity}) {
    if ((_busy && !_rendering) || _settings?.hasMask != true) return;
    setState(() => _settings = _settings!.withOptions(edgeStyle: style,
      edgeColor: color, edgeSize: size, edgeDistance: distance,
      edgeOpacity: opacity));
    _scheduleEdgeRender();
  }

  void _openChroma() {
    _brushIdleTimer?.cancel();
    _brushIdleTimer = null;
    _manualPreviewPending = false;
    _chromaRenderTimer?.cancel();
    _chromaPixelTimer?.cancel();
    _chromaFrameRequest++;
    _chromaPixelRevision++;
    _chromaSourceRgba = null;
    final previousSource = _chromaSourceImage;
    _chromaSourceImage = null;
    if (previousSource != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previousSource.dispose());
    }
    final previousLive = _chromaLiveImage;
    _chromaLiveImage = null;
    final previousMask = _chromaCommittedMaskImage;
    _chromaCommittedMaskImage = null;
    _chromaMaskRevision++;
    if (previousLive != null || previousMask != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previousLive?.dispose();
        previousMask?.dispose();
      });
    }
    _activePlayer?.pause();
    // Chroma is independent from ML and manual-mask segmentation.
    // An earlier confirmed panel may have stored a draft instead of a pass.
    // Freeze it before the next eyedropper selection can replace its color.
    final settings = _settings?.chromaEnabled == true && _settings?.hasMask != true
      ? _withCommittedChromaDraft(_settings!) : CutoutSettings(maskDirectory: '',
          sourceStart: widget.sourceStart, framesPerSecond: 0, frameCount: 0,
          chromaEnabled: true, chromaSimilarity: .045, chromaBlend: .025);
    setState(() {
      _settings = settings;
      _strokes.clear();
      _redoStrokes.clear();
      _mode = _CutoutMode.chroma;
      _showOriginal = false;
      _chromaPreviewVisible = true;
      _chromaRenderFresh = false;
    });
    _loadChromaShader();
    _loadChromaFrame(selectInitialColor: settings.chromaPasses.isEmpty &&
        settings.chromaDraftEnabled);
  }

  /// Compile once; GPU renders new picker/slider values on the next Flutter
  /// frame. The CPU fallback remains available on unsupported renderers.
  Future<void> _loadChromaShader() async {
    if (_chromaShaderProgram != null || _chromaShaderLoading ||
        _chromaShaderUnavailable || _disposed) return;
    _chromaShaderLoading = true;
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/tini_chroma.frag');
      if (!mounted || _disposed) return;
      setState(() { _chromaShaderProgram = program; _error = null; });
    } catch (error) {
      if (!mounted || _disposed) return;
      setState(() {
        _chromaShaderUnavailable = true;
        _error = 'تعذر تفعيل معاينة GPU؛ سيتم استخدام المعاينة البديلة: ${_shortError(error)}';
      });
      _scheduleChromaPixels();
    } finally {
      _chromaShaderLoading = false;
    }
  }

  /// Decode only the currently paused source frame, not the processed preview.
  /// Its pixels remain cached while the eyedropper is moved across the screen.
  Future<void> _loadChromaFrame({bool selectInitialColor = false}) async {
    if (_disposed || _mode != _CutoutMode.chroma) return;
    if (!_chromaPreviewVisible) return;
    final request = ++_chromaFrameRequest;
    _chromaPixelRevision++;
    final oldSource = _chromaSourceImage;
    final oldPreview = _chromaLiveImage;
    final oldMask = _chromaCommittedMaskImage;
    _chromaMaskRevision++;
    if (mounted) setState(() {
      _chromaSourceImage = null;
      _chromaLiveImage = null;
      _chromaCommittedMaskImage = null;
      _chromaSourceRgba = null;
    });
    if (oldSource != null || oldPreview != null || oldMask != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldSource?.dispose();
        oldPreview?.dispose();
        oldMask?.dispose();
      });
    }
    try {
      final frame = await vt.VideoThumbnail.thumbnailData(
        video: _localPath, imageFormat: vt.ImageFormat.PNG,
        timeMs: (widget.sourceStart + _position).inMilliseconds,
        maxWidth: 540, quality: 95);
      if (frame == null || request != _chromaFrameRequest || _disposed) return;
      final bitmap = img.decodeImage(frame);
      if (bitmap == null || !mounted || request != _chromaFrameRequest) return;
      final codec = await ui.instantiateImageCodec(frame);
      ui.Image sourceImage;
      try {
        sourceImage = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      if (!mounted || _disposed || request != _chromaFrameRequest) {
        sourceImage.dispose();
        return;
      }
      // The sampler and the eyedropper always use the SAME source frame.
      final rgba = bitmap.getBytes(order: img.ChannelOrder.rgba);
      setState(() {
        _chromaSourceImage = sourceImage;
        _chromaSourceRgba = rgba;
        _chromaSourceWidth = bitmap.width;
        _chromaSourceHeight = bitmap.height;
      });
      _refreshChromaMask();
      if (selectInitialColor) {
        _sampleChromaColor(_chromaPosition);
        if (_chromaPointer == null) _scheduleChromaRender();
      } else if (_chromaShaderProgram == null) {
        _scheduleChromaPixels();
      }
    } catch (error) {
      if (mounted && !_disposed && request == _chromaFrameRequest) {
        setState(() => _error = 'تعذر تحميل إطار معاينة الكروما: ${_shortError(error)}');
      }
    }
  }

  void _sampleChromaColor(Offset normalized) {
    final pixels = _chromaSourceRgba;
    if (_disposed || !mounted || _mode != _CutoutMode.chroma) return;
    final x = normalized.dx.clamp(0.0, 1.0).toDouble();
    final y = normalized.dy.clamp(0.0, 1.0).toDouble();
    _chromaPosition = Offset(x, y);
    if (pixels == null || _chromaSourceWidth <= 0 || _chromaSourceHeight <= 0) {
      setState(() {});
      return;
    }
    final cx = (x * (_chromaSourceWidth - 1)).round();
    final cy = (y * (_chromaSourceHeight - 1)).round();
    // Use the exact pixel under the dot as the reference. Only average nearby
    // pixels of almost the SAME RGB color; averaging across a color boundary
    // would produce a different key color that was never selected.
    final center = (cy * _chromaSourceWidth + cx) * 4;
    final centerRed = pixels[center];
    final centerGreen = pixels[center + 1];
    final centerBlue = pixels[center + 2];
    var red = centerRed, green = centerGreen, blue = centerBlue, count = 1;
    for (var py = math.max(0, cy - 1);
        py <= math.min(_chromaSourceHeight - 1, cy + 1); py++) {
      for (var px = math.max(0, cx - 1);
          px <= math.min(_chromaSourceWidth - 1, cx + 1); px++) {
        if (px == cx && py == cy) continue;
        final i = (py * _chromaSourceWidth + px) * 4;
        if ((pixels[i] - centerRed).abs() > 20 ||
            (pixels[i + 1] - centerGreen).abs() > 20 ||
            (pixels[i + 2] - centerBlue).abs() > 20) continue;
        red += pixels[i]; green += pixels[i + 1]; blue += pixels[i + 2];
        count++;
      }
    }
    final color = ((red ~/ count) << 16) |
        ((green ~/ count) << 8) | (blue ~/ count);
    setState(() => _settings = _settings!.withOptions(
        chromaColor: color, chromaDraftEnabled: true));
    _chromaParametersChanged();
  }

  // Persist the current color as an immutable pass before leaving or
  // reopening chroma. Otherwise a later selection overwrites the old draft.
  CutoutSettings _withCommittedChromaDraft(CutoutSettings settings) {
    if (!settings.chromaEnabled || !settings.chromaDraftEnabled) return settings;
    return settings.withOptions(
      chromaPasses: [...settings.chromaPasses,
        ChromaKeyPass(color: settings.chromaColor,
          similarity: settings.chromaSimilarity, blend: settings.chromaBlend)],
      chromaDraftEnabled: false);
  }

  // Save the current key as a separate, immutable phase. New samples and
  // slider changes affect only the next phase; old transparency accumulates.
  void _commitChromaPass() {
    final settings = _settings;
    // Saving a phase must not be dropped while an old FFmpeg preview renders.
    if (settings == null || !settings.chromaEnabled ||
        !settings.chromaDraftEnabled) return;
    setState(() => _settings = _withCommittedChromaDraft(settings));
    _chromaParametersChanged();
    _refreshChromaMask();
    _scheduleChromaRender();
    _message('تم تثبيت المرحلة. اختر لونًا جديدًا لإزالة الأجزاء المتبقية.');
  }

  void _undoChromaPass() {
    final settings = _settings;
    if (settings == null || settings.chromaPasses.isEmpty) return;
    setState(() => _settings = settings.withOptions(
        chromaPasses: settings.chromaPasses.sublist(0, settings.chromaPasses.length - 1)));
    _chromaParametersChanged();
    _refreshChromaMask();
    _scheduleChromaRender();
  }

  // A committed key is re-evaluated on each paused source frame. It uses
  // the original RGB pixels, so passing over a transparent area is harmless.
  Future<void> _refreshChromaMask() async {
    final rgba = _chromaSourceRgba;
    final settings = _settings;
    final revision = ++_chromaMaskRevision;
    final frameRequest = _chromaFrameRequest;
    final previous = _chromaCommittedMaskImage;
    if (previous != null) {
      setState(() => _chromaCommittedMaskImage = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    if (rgba == null || settings == null || settings.chromaPasses.isEmpty ||
        _disposed || !mounted) return;
    try {
      final data = await compute(_tiniChromaCommittedMaskPixels, <String, Object>{
        'rgba': rgba,
        'passes': settings.chromaPasses.map((p) => <double>[
          p.color.toDouble(), p.similarity, p.blend]).toList(),
      });
      if (!mounted || _disposed || revision != _chromaMaskRevision ||
          frameRequest != _chromaFrameRequest) return;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(data, _chromaSourceWidth, _chromaSourceHeight,
          ui.PixelFormat.rgba8888, completer.complete,
          rowBytes: _chromaSourceWidth * 4);
      final image = await completer.future;
      if (!mounted || _disposed || revision != _chromaMaskRevision ||
          frameRequest != _chromaFrameRequest) {
        image.dispose();
        return;
      }
      setState(() => _chromaCommittedMaskImage = image);
    } catch (error) {
      if (mounted && !_disposed && revision == _chromaMaskRevision) {
        setState(() => _error = 'تعذر تجهيز قناع الكروما التراكمي: ${_shortError(error)}');
      }
    }
  }

  void _chromaParametersChanged() {
    if (!_chromaPreviewVisible && _mode == _CutoutMode.chroma) {
      _activePlayer?.pause();
      setState(() => _chromaPreviewVisible = true);
      _sourcePlayer?.seekTo(widget.sourceStart + _position);
      _loadChromaFrame();
    }
    _chromaRenderFresh = false;
    // Mark old FFmpeg output obsolete; do not start new renders on every drag.
    _chromaSettingsRevision++;
    _chromaRenderTimer?.cancel();
    _chromaPixelRevision++;
    if (_chromaShaderProgram == null) _scheduleChromaPixels();
  }

  void _scheduleChromaPixels() {
    if (_chromaShaderProgram != null ||
        (_chromaShaderLoading && !_chromaShaderUnavailable)) return;
    _chromaPixelTimer?.cancel();
    _chromaPixelTimer = Timer(const Duration(milliseconds: 16), _updateChromaPixels);
  }

  Future<void> _updateChromaPixels() async {
    final pixels = _chromaSourceRgba;
    final settings = _settings;
    if (_chromaPixelBusy || _disposed || _mode != _CutoutMode.chroma ||
        pixels == null || settings == null) return;
    _chromaPixelBusy = true;
    final revision = _chromaPixelRevision;
    final frameRequest = _chromaFrameRequest;
    try {
      final rgba = await compute(_tiniChromaPreviewPixels, <String, Object>{
        'rgba': pixels,
        'color': settings.chromaColor,
        'similarity': settings.chromaSimilarity,
        'blend': settings.chromaBlend,
        'draftEnabled': settings.chromaDraftEnabled,
        'passes': settings.chromaPasses.map((p) => <double>[
          p.color.toDouble(), p.similarity, p.blend]).toList(),
        'width': _chromaSourceWidth,
        'height': _chromaSourceHeight,
      });
      if (_disposed || !mounted || revision != _chromaPixelRevision ||
          frameRequest != _chromaFrameRequest) return;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(rgba, _chromaSourceWidth, _chromaSourceHeight,
          ui.PixelFormat.rgba8888, completer.complete,
          rowBytes: _chromaSourceWidth * 4);
      final image = await completer.future;
      if (_disposed || !mounted || revision != _chromaPixelRevision ||
          frameRequest != _chromaFrameRequest) {
        image.dispose();
        return;
      }
      final old = _chromaLiveImage;
      setState(() => _chromaLiveImage = image);
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    } catch (error) {
      if (mounted && !_disposed) {
        setState(() => _error = 'تعذر تحديث معاينة الكروما: ${_shortError(error)}');
      }
    } finally {
      _chromaPixelBusy = false;
      if (!_disposed && mounted && revision != _chromaPixelRevision) {
        _scheduleChromaPixels();
      }
    }
  }

  void _scheduleChromaRender() {
    _chromaRenderTimer?.cancel();
    _chromaRenderTimer = Timer(const Duration(milliseconds: 450), () {
      _chromaRenderTimer = null;
      if (!_disposed && _settings?.chromaEnabled == true) _queueRender();
    });
  }

  void _moveChromaTarget(Offset touch, Size videoSize) {
    if (videoSize.width <= 0 || videoSize.height <= 0) return;
    // The visible sampling dot stays 76 logical pixels ABOVE the fingertip.
    // At the top boundary it moves sideways instead of sitting under the finger.
    final target = touch.dy >= 110.0
        ? Offset(touch.dx, touch.dy - 76.0)
        : Offset(touch.dx + (touch.dx > videoSize.width * .5 ? -76.0 : 76.0),
            touch.dy);
    _sampleChromaColor(Offset(target.dx / videoSize.width,
        target.dy / videoSize.height));
  }

  void _leaveChromaMode() {
    _chromaRenderTimer?.cancel();
    _chromaPixelTimer?.cancel();
    _chromaFrameRequest++;
    _chromaPixelRevision++;
    _chromaPointer = null;
    _chromaPreviewVisible = false;
    _chromaSourceRgba = null;
    final source = _chromaSourceImage;
    final preview = _chromaLiveImage;
    final mask = _chromaCommittedMaskImage;
    _chromaMaskRevision++;
    _chromaSourceImage = null;
    _chromaLiveImage = null;
    _chromaCommittedMaskImage = null;
    // A rendered image must outlive the frame that last painted it.
    if (source != null || preview != null || mask != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        source?.dispose();
        preview?.dispose();
        mask?.dispose();
      });
    }
  }

  // Cache one frame per timeline position. The loupe only repaints that
  // frame while the finger moves; no video decoder or FFmpeg job runs per drag.
  Future<void> _captureMagnifierFrame() async {
    if (_disposed || _mode != _CutoutMode.custom) return;
    if (_magnifierLoading) {
      _magnifierRefreshPending = true;
      return;
    }
    final processed = !_showOriginal && !_manualPreviewPending &&
        _processedPath != null &&
        _processedPlayer?.value.isInitialized == true;
    final source = processed ? _processedPath! : _localPath;
    final timeMs = processed ? _position.inMilliseconds
        : (widget.sourceStart + _position).inMilliseconds;
    if (_magnifierImage != null && _magnifierFrameSource == source &&
        _magnifierFrameTimeMs == timeMs) return;
    final request = ++_magnifierRequestId;
    _magnifierLoading = true;
    try {
      final bytes = await vt.VideoThumbnail.thumbnailData(
        video: source, imageFormat: vt.ImageFormat.PNG,
        timeMs: timeMs, maxWidth: 720, quality: 95);
      if (bytes == null || _disposed) return;
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        if (!mounted || _disposed || request != _magnifierRequestId) {
          frame.image.dispose();
          return;
        }
        final previous = _magnifierImage;
        setState(() {
          _magnifierImage = frame.image;
          _magnifierFrameSource = source;
          _magnifierFrameTimeMs = timeMs;
        });
        // Dispose after the frame that stopped using the previous image.
        if (previous != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // A missing thumbnail must not disable brush input.
    } finally {
      _magnifierLoading = false;
      if (_magnifierRefreshPending && !_disposed) {
        _magnifierRefreshPending = false;
        _captureMagnifierFrame();
      }
    }
  }

  void _beginBrush(PointerDownEvent event, Size size) {
    if (_busy || _activeBrushPointer != null) return;
    _brushIdleTimer?.cancel();
    _brushIdleTimer = null;
    if (_settings?.hasMask != true || _settings?.manualMask == true) {
      setState(() => _manualPreviewPending = true);
    }
    _activeBrushPointer = event.pointer;
    _activePlayer?.pause();
    if (_manualPreviewPending) unawaited(_seekTo(_position));
    _appendPoint(event.localPosition, size, first: true);
    _captureMagnifierFrame();
  }

  void _moveBrush(PointerMoveEvent event, Size size) {
    if (_activeBrushPointer != event.pointer) return;
    _appendPoint(event.localPosition, size, first: false);
  }

  void _finishBrush(int pointer, {required bool cancelled}) {
    if (_activeBrushPointer != pointer) return;
    _activeBrushPointer = null;
    if (!cancelled) {
      _endStroke();
    } else if (mounted) {
      setState(() { _drawing = []; _finger = null; });
    }
  }


  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));

  void _appendPoint(Offset local, Size size, {required bool first}) {
    if (_busy || size.width <= 0 || size.height <= 0) return;
    final normalized = Offset((local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0));
    setState(() {
      if (first) { _drawing = [normalized]; } else { _drawing.add(normalized); }
      // Painter revisions avoid copying every point on every finger movement.
      _strokeRevision++;
      _finger = normalized;
    });
  }

  void _endStroke() {
    if (_drawing.isEmpty) return;
    final stroke = CutoutStroke(erase: _tool == _CutoutTool.eraser,
      quick: _tool == _CutoutTool.quick,
      radius: _tool == _CutoutTool.quick
          ? (_brushRadius * 1.8).clamp(.005, .20).toDouble() : _brushRadius,
      points: List.unmodifiable(_drawing));
    setState(() { _strokes.add(stroke); _redoStrokes.clear();
      _drawing = []; _finger = null; _strokeRevision++; });
    _scheduleBrushPreview();
  }

  // Debounce repeated touches: one preview is rendered one second after the
  // latest completed stroke, not for every pointer move or finger lift.
  void _scheduleBrushPreview() {
    _brushIdleTimer?.cancel();
    _brushIdleTimer = Timer(const Duration(seconds: 1), () {
      _brushIdleTimer = null;
      _applyBrushPreview();
    });
  }

  Future<void> _applyBrushPreview() async {
    _brushIdleTimer?.cancel();
    _brushIdleTimer = null;
    if (_disposed || !mounted) return;
    if (_strokes.isEmpty && (_settings?.manualMask == true ||
        _settings?.hasMask != true)) {
      setState(() {
        _manualPreviewPending = false;
        if (_settings?.manualMask == true) _showOriginal = true;
      });
      return;
    }
    if (_settings?.hasMask != true) {
      if (_strokes.isEmpty) return;
      setState(() { _busy = true; _error = null; });
      try {
        final created = await CropBackgroundEngine.createManualMasks(
          sourceStart: widget.sourceStart,
          duration: _clipDuration,
          aspectRatio: _videoRatio,
          firstStrokeErases: _strokes.first.erase,
        );
        if (!mounted || _disposed) {
          try { await Directory(created.maskDirectory).delete(recursive: true); } catch (_) {}
          return;
        }
        setState(() => _settings = created);
      } catch (error) {
        if (mounted && !_disposed) setState(() => _error = _shortError(error));
        return;
      } finally {
        if (mounted && !_disposed) setState(() => _busy = false);
      }
    }
    if (!_disposed && mounted) await _queueRender();
  }

  void _undo() {
    if (_strokes.isEmpty || _busy) return;
    setState(() { _redoStrokes.add(_strokes.removeLast());
      _drawing = []; _strokeRevision++;
      if (_settings?.manualMask == true) _manualPreviewPending = true; });
    _scheduleBrushPreview();
  }

  void _redo() {
    if (_redoStrokes.isEmpty || _busy) return;
    setState(() { _strokes.add(_redoStrokes.removeLast());
      _drawing = []; _strokeRevision++;
      if (_settings?.manualMask == true) _manualPreviewPending = true; });
    _scheduleBrushPreview();
  }

  Future<void> _reset() async {
    if (_busy) { await CropBackgroundEngine.cancel(); return; }
    _leaveChromaMode();
    _brushIdleTimer?.cancel();
    _brushIdleTimer = null;
    _manualPreviewPending = false;
    await _processedPlayer?.pause();
    final old = _processedPlayer;
    final oldPath = _processedPath;
    if (!mounted) return;
    setState(() {
      _settings = null; _strokes.clear(); _redoStrokes.clear();
      _strokeRevision++;
      _processedPlayer = null; _processedPath = null;
      _mode = _CutoutMode.main; _error = null;
      _showOriginal = false;
    });
    await old?.dispose();
    if (oldPath != null) { try { await File(oldPath).delete(); } catch (_) {} }
    await _seekTo(_position);
  }

  Future<void> _confirm() async {
    if (_busy) return;
    _chromaRenderTimer?.cancel();
    _edgeRenderTimer?.cancel();
    // Confirm commits even when the idle timer is pending or a previous
    // attempt to build the first manual mask failed.
    final pendingBrush = _brushIdleTimer != null ||
        (_strokes.isNotEmpty && _settings?.hasMask != true);
    if (pendingBrush) await _applyBrushPreview();
    if (!mounted || _disposed || _busy ||
        (_strokes.isNotEmpty && _error != null)) return;
    final settings = _settings == null ? null
        : _withCommittedChromaDraft(_settings!);
    Navigator.of(context).pop(CropCutoutResult(
      settings?.manualMask == true && _strokes.isEmpty
          ? null : settings?.withStrokes(_strokes)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _sourcePlayer?.pause();
      _processedPlayer?.pause();
    }
  }

  @override
  void dispose() {
    _leaveChromaMode();
    _brushIdleTimer?.cancel();
    _edgeRenderTimer?.cancel();
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    // Only cancel work still owned by this panel; confirmed edits are rendered by the parent.
    if (_busy && _mode != _CutoutMode.chroma) CropBackgroundEngine.cancel();
    _progressSubscription?.cancel();
    _magnifierRequestId++;
    _magnifierImage?.dispose();
    _sourcePlayer?.removeListener(_onVideoTick);
    _processedPlayer?.removeListener(_onVideoTick);
    _sourcePlayer?.dispose();
    _processedPlayer?.dispose();
    if (_processedPath != null) {
      File(_processedPath!).delete().catchError((Object _) => File(''));
    }
    super.dispose();
  }

  String _clock(Duration value) {
    final seconds = math.max(0, value.inSeconds);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _video() {
    final player = _activePlayer;
    final initialized = player?.value.isInitialized == true;
    final ratio = initialized && player!.value.aspectRatio > 0
        ? player.value.aspectRatio : _videoRatio;
    return LayoutBuilder(builder: (context, limits) {
      final width = math.min(limits.maxWidth - 22,
          (limits.maxHeight - 6) * ratio).clamp(0.0, limits.maxWidth).toDouble();
      final height = ratio > 0 ? width / ratio : 0.0;
      final videoLeft = (limits.maxWidth - width) / 2;
      final videoTop = (limits.maxHeight - height) / 2;
      final loupeSize = math.max(0.0, math.min(174.0,
          math.min(limits.maxWidth - 16, math.min(limits.maxHeight - 12,
              math.max(126.0, width * .48)))));
      final loupeLeft = (videoLeft - loupeSize * .5)
          .clamp(8.0, math.max(8.0, limits.maxWidth - loupeSize - 8))
          .toDouble();
      final loupeTop = (videoTop + 8)
          .clamp(6.0, math.max(6.0, limits.maxHeight - loupeSize - 6))
          .toDouble();
      return Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
        Positioned(left: videoLeft, top: videoTop, width: width, height: height,
          child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
            ColoredBox(color: Colors.black,
              child: initialized
                ? VideoPlayer(player!)
                : const Center(child: CircularProgressIndicator(color: Colors.white38))),
            if (_mode == _CutoutMode.chroma && !_showOriginal &&
                _chromaPreviewVisible &&
                ((_chromaSourceImage != null && _chromaShaderProgram != null &&
                    ((_settings?.chromaPasses.isEmpty ?? true) ||
                        _chromaCommittedMaskImage != null)) ||
                    _chromaLiveImage != null))
              Positioned.fill(child: IgnorePointer(child: Stack(
                fit: StackFit.expand, children: [
                  const ColoredBox(color: Colors.black),
                  if (widget.clip.backgroundPath != null)
                    Image.file(File(Uri.tryParse(widget.clip.backgroundPath!)?.scheme == 'file'
                        ? Uri.parse(widget.clip.backgroundPath!).toFilePath()
                        : widget.clip.backgroundPath!), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  if (_chromaSourceImage != null && _chromaShaderProgram != null &&
                      ((_settings?.chromaPasses.isEmpty ?? true) ||
                          _chromaCommittedMaskImage != null))
                    CustomPaint(painter: _TiniChromaGpuPainter(
                      image: _chromaSourceImage!, program: _chromaShaderProgram!,
                      committedMask: _chromaCommittedMaskImage,
                      draftEnabled: _settings?.chromaDraftEnabled ?? true,
                      chromaColor: _settings?.chromaColor ?? 0x00FF00,
                      similarity: _settings?.chromaSimilarity ?? .045,
                      blend: _settings?.chromaBlend ?? .025))
                  else if (_chromaLiveImage != null)
                    RawImage(image: _chromaLiveImage, fit: BoxFit.fill),
                ]))),
            IgnorePointer(child: Container(decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 1)))),
            if (_mode == _CutoutMode.custom)
              Listener(behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _beginBrush(e, Size(width, height)),
                onPointerMove: (e) => _moveBrush(e, Size(width, height)),
                onPointerUp: (e) => _finishBrush(e.pointer, cancelled: false),
                onPointerCancel: (e) => _finishBrush(e.pointer, cancelled: true),
                child: CustomPaint(painter: _CutoutBrushPainter(
                  strokes: _settings?.manualMask == true &&
                      !_manualPreviewPending && !_showOriginal
                      ? const [] : _strokes,
                  current: _drawing,
                  repaintRevision: _strokeRevision,
                  currentErase: _tool == _CutoutTool.eraser,
                  currentRadius: _tool == _CutoutTool.quick
                      ? (_brushRadius * 1.8).clamp(.005, .20).toDouble() : _brushRadius))),
            if (_mode == _CutoutMode.chroma)
              Listener(behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  if (_chromaPointer != null) return;
                  _chromaPointer = e.pointer;
                  _chromaRenderTimer?.cancel();
                  _activePlayer?.pause();
                  if (!_chromaPreviewVisible) {
                    setState(() => _chromaPreviewVisible = true);
                    _sourcePlayer?.seekTo(widget.sourceStart + _position);
                    _loadChromaFrame();
                  }
                  _moveChromaTarget(e.localPosition, Size(width, height));
                },
                onPointerMove: (e) {
                  if (_chromaPointer == e.pointer) {
                    _moveChromaTarget(e.localPosition, Size(width, height));
                  }
                },
                onPointerUp: (e) {
                  if (_chromaPointer == e.pointer) {
                    _chromaPointer = null;
                    _scheduleChromaRender();
                  }
                },
                onPointerCancel: (e) {
                  if (_chromaPointer == e.pointer) {
                    _chromaPointer = null;
                    _scheduleChromaRender();
                  }
                },
                child: Stack(fit: StackFit.expand, children: [
                  Positioned(
                    // The eyedropper target is offset from the user's finger.
                    left: _chromaPosition.dx * width - 34,
                    top: _chromaPosition.dy * height - 34,
                    width: 68, height: 68,
                    child: IgnorePointer(child: DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle,
                        color: Colors.black38,
                        border: Border.all(
                          color: Color(0xFF000000 | (_settings?.chromaColor ?? 0xFFFFFF)),
                          width: 7),
                        boxShadow: const [BoxShadow(color: Colors.black54,
                          blurRadius: 5, spreadRadius: 1)]),
                      child: Center(child: Container(width: 7, height: 7,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          color: Colors.white, border: Border.all(color: Colors.black, width: 1.2)))),
                    )),
                  ),
                ])),
            if (_busy && _mode != _CutoutMode.chroma)
              Positioned(left: 12, right: 12, bottom: 14,
              child: Container(padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: Colors.black54,
                  borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  InkWell(onTap: () => CropBackgroundEngine.cancel(),
                    child: const CircleAvatar(radius: 15,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.close, color: Colors.white, size: 19))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_mode == _CutoutMode.custom
                      ? 'تجري معالجة التحديد...' : 'تجري المعالجة  $_progress%',
                    style: const TextStyle(color: Colors.white, fontSize: 14))),
                ]))),
          ])),
        // Keep the loupe at the upper-left edge of the video. Painting it in
        // the outer Stack lets it extend beyond narrow portrait video frames.
        if (_finger != null && _mode == _CutoutMode.custom)
          Positioned(left: loupeLeft, top: loupeTop,
            width: loupeSize, height: loupeSize,
            child: IgnorePointer(child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)]),
              child: ClipRRect(borderRadius: BorderRadius.circular(13),
                child: _magnifierImage == null
                    ? const Center(child: Icon(Icons.center_focus_strong,
                        color: Colors.white70, size: 30))
                    : CustomPaint(painter: _CutoutMagnifierPainter(
                        image: _magnifierImage!, focus: _finger!,
                        strokes: _strokes, current: _drawing,
                        repaintRevision: _strokeRevision,
                        currentErase: _tool == _CutoutTool.eraser,
                        currentRadius: _tool == _CutoutTool.quick
                            ? (_brushRadius * 1.8).clamp(.005, .20).toDouble()
                            : _brushRadius)))))),
      ]);
    });
  }

  Widget _controls() => SizedBox(height: 53, child: Row(
    textDirection: TextDirection.ltr, children: [
    if (_settings != null) IconButton(tooltip: 'إظهار الأصل',
      icon: Icon(_showOriginal ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: Colors.white), onPressed: () => _switchPreview(!_showOriginal)),
    IconButton(tooltip: 'تراجع', icon: Icon(Icons.undo,
      color: _strokes.isNotEmpty ? Colors.white : Colors.white38),
      onPressed: _strokes.isNotEmpty ? _undo : null),
    IconButton(tooltip: 'إعادة', icon: Icon(Icons.redo,
      color: _redoStrokes.isNotEmpty ? Colors.white : Colors.white38),
      onPressed: _redoStrokes.isNotEmpty ? _redo : null),
    const Spacer(),
    IconButton(iconSize: 34, tooltip: _playing ? 'إيقاف' : 'تشغيل',
      icon: Icon(_playing ? Icons.pause : Icons.play_arrow,
        color: Colors.white), onPressed: _togglePlay),
    const Spacer(),
    Text('${_clock(_position)} / ${_clock(_clipDuration)}',
      textDirection: TextDirection.ltr,
      style: const TextStyle(color: Colors.white54, fontSize: 13)),
    const SizedBox(width: 9),
  ]));

  Widget _timeline() => SizedBox(height: 48, child: LayoutBuilder(
    builder: (context, bounds) {
      final fraction = _clipDuration.inMicroseconds == 0 ? 0.0
          : (_position.inMicroseconds / _clipDuration.inMicroseconds).clamp(0.0, 1.0).toDouble();
      return GestureDetector(behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _seekTo(Duration(microseconds:
          (_clipDuration.inMicroseconds * (d.localPosition.dx / bounds.maxWidth)
              .clamp(0.0, 1.0)).round())),
        onHorizontalDragUpdate: (d) => _seekTo(Duration(microseconds:
          (_clipDuration.inMicroseconds * (d.localPosition.dx / bounds.maxWidth)
              .clamp(0.0, 1.0)).round())),
        child: Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(5),
            child: Row(children: List.generate(10, (i) => Expanded(
              child: SizedBox.expand(child: i < _timelineFrames.length
                  ? Image.memory(_timelineFrames[i], fit: BoxFit.cover,
                      gaplessPlayback: true)
                  : Container(color: Color.lerp(Colors.grey.shade800,
                      Colors.grey.shade600, i / 10))))))),
          Positioned(left: math.max(1.0, fraction * (bounds.maxWidth - 3)).toDouble(),
            top: -2, bottom: -2, width: 3,
            child: DecoratedBox(decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(3)))),
        ]));
    }));

  Widget _squareOption(String label, IconData icon, VoidCallback onTap,
      {bool selected = false, bool enabled = true}) => InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(width: math.min(92.0, MediaQuery.sizeOf(context).width / 4 - 7),
      child: Column(children: [
      Container(width: 62, height: 62, alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: Colors.white, width: 2) : null),
        child: Icon(icon, size: 31,
          color: enabled ? Colors.white : Colors.white38)),
      const SizedBox(height: 9),
      Text(label, textAlign: TextAlign.center, maxLines: 2,
        style: TextStyle(color: enabled ? Colors.white : Colors.white38,
          fontSize: 12, height: 1.35)),
    ])));

  Widget _mainTools() => Column(children: [
    const Padding(padding: EdgeInsets.only(bottom: 13),
      child: Text('حدد كيفية استخدام قص الخلفية',
        style: TextStyle(color: Colors.white, fontSize: 13,
          fontWeight: FontWeight.w500))),
    Row(textDirection: TextDirection.ltr,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _squareOption('الحواف', Icons.blur_on, _openEdges),
      _squareOption('مفتاح\nالكروما', Icons.colorize, _openChroma),
      _squareOption('قص الخلفية\nالمخصص', Icons.touch_app_outlined, _openCustom),
      _squareOption('قص الخلفية\nالتلقائي', Icons.auto_awesome_mosaic,
        _generate, selected: _settings?.hasMask == true),
    ]),
  ]);

  Widget _brushTools() => Column(children: [
    Row(textDirection: TextDirection.ltr,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _squareOption('ممحاة', Icons.cleaning_services_outlined,
        () => setState(() => _tool = _CutoutTool.eraser),
        selected: _tool == _CutoutTool.eraser),
      _squareOption('فرشاة', Icons.brush,
        () => setState(() => _tool = _CutoutTool.brush),
        selected: _tool == _CutoutTool.brush),
      _squareOption('فرشاة سريعة', Icons.auto_fix_high,
        () => setState(() => _tool = _CutoutTool.quick),
        selected: _tool == _CutoutTool.quick),
    ]),
    const SizedBox(height: 18),
    Row(children: [
      Expanded(child: Slider(value: _brushRadius, min: .005, max: .10,
        activeColor: Colors.white, inactiveColor: Colors.white30,
        onChanged: _busy ? null : (v) => setState(() => _brushRadius = v))),
      const Text('حجم الفرشاة', style: TextStyle(color: Colors.white, fontSize: 12)),
    ]),
  ]);

  Widget _chromaTools() => Column(children: [
    const Text('مفتاح الكروما — حرّك إصبعك أسفل مؤشر اللون',
      style: TextStyle(color: Colors.white, fontSize: 12)),
    const SizedBox(height: 12),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 25, height: 25,
        decoration: BoxDecoration(shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          color: Color(0xFF000000 | (_settings?.chromaColor ?? 0x00FF00)))),
      const SizedBox(width: 10),
      const Expanded(child: Text('النقطة أمام إصبعك، واللون المحدد يُحذف فورًا',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70, fontSize: 12))),
    ]),
    const SizedBox(height: 9),
    Text('مراحل مثبتة: ${_settings?.chromaPasses.length ?? 0}'
        '${_settings?.chromaDraftEnabled == true ? ' — المرحلة الحالية نشطة' : ' — اختر لونًا للمرحلة التالية'}',
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white70, fontSize: 12)),
    const SizedBox(height: 6),
    Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
      TextButton.icon(onPressed: _settings?.chromaDraftEnabled != true
          ? null : _commitChromaPass,
        icon: const Icon(Icons.add_circle_outline, color: Colors.tealAccent),
        label: const Text('تثبيت المرحلة',
          style: TextStyle(color: Colors.tealAccent))),
      TextButton.icon(onPressed: (_settings?.chromaPasses.isEmpty ?? true)
          ? null : _undoChromaPass,
        icon: const Icon(Icons.undo, color: Colors.white70),
        label: const Text('تراجع عن آخر تثبيت',
          style: TextStyle(color: Colors.white70))),
    ]),
    const SizedBox(height: 9),
    _chromaSlider('الحدة', _settings?.chromaSimilarity ?? .045,
      min: .01, max: .12,
      onChange: (value) {
        setState(() => _settings = _settings!.withOptions(
            chromaSimilarity: value, chromaDraftEnabled: true));
        _chromaParametersChanged();
      }),
    _chromaSlider('الظل', _settings?.chromaBlend ?? .025,
      min: 0.0, max: .05,
      onChange: (value) {
        setState(() => _settings = _settings!.withOptions(
            chromaBlend: value, chromaDraftEnabled: true));
        _chromaParametersChanged();
      }),
  ]);

  Widget _chromaSlider(String label, double value, {required double min,
      required double max, required ValueChanged<double> onChange}) =>
    Row(children: [
      SizedBox(width: 50, child: Text(label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 12))),
      Expanded(child: Slider(value: value.clamp(min, max).toDouble(),
        min: min, max: max, activeColor: Colors.white,
        inactiveColor: Colors.white30,
        onChanged: onChange,
        onChangeEnd: (_) => _scheduleChromaRender())),
      SizedBox(width: 36, child: Text(
        '${(((value.clamp(min, max) - min) / (max - min)) * 100).round()}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 12))),
    ]);

  static const _edgeColors = <int>[
    0xFFFFFF, 0x151515, 0xFF445F, 0xFFDE2D, 0x36E6EE,
    0x42D66E, 0x4F83FF, 0x9B55FF, 0xFF4DAA, 0xFF914C,
  ];

  Widget _edgePreset(CutoutEdgeStyle style, String label, int color) {
    final selected = _settings?.edgeStyle == style;
    return GestureDetector(onTap: () => _changeEdge(style: style, color: color),
      child: SizedBox(width: 74, child: Column(children: [
        Container(width: 65, height: 69, alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF20232A),
            border: Border.all(color: selected ? Colors.tealAccent : Colors.white24,
              width: selected ? 2.3 : 1),
            borderRadius: BorderRadius.circular(10)),
          child: style == CutoutEdgeStyle.none
              ? const Icon(Icons.block, color: Colors.white70, size: 31)
              : CustomPaint(size: const Size(53, 58),
                  painter: _EdgePresetPainter(style, Color(0xFF000000 | color)))),
        const SizedBox(height: 5),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11,
            color: selected ? Colors.tealAccent : Colors.white70)),
      ])));
  }

  Widget _edgeSlider(String name, double value, ValueChanged<double> update) =>
    Row(children: [
      SizedBox(width: 62, child: Text(name, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 12))),
      Expanded(child: Slider(value: value.clamp(0.0, 1.0).toDouble(),
        min: 0, max: 1, activeColor: Colors.white,
        inactiveColor: Colors.white24,
        onChanged: (_busy && !_rendering) ? null : update,
        onChangeEnd: (_) => _scheduleEdgeRender())),
      SizedBox(width: 38, child: Text('${(value * 100).round()}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 12))),
    ]);

  Widget _edgesTools() {
    final settings = _settings;
    final style = settings?.edgeStyle ?? CutoutEdgeStyle.none;
    final distanceControl = style == CutoutEdgeStyle.doubleLine ||
        style == CutoutEdgeStyle.paper || style == CutoutEdgeStyle.dashed ||
        style == CutoutEdgeStyle.sparkle;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('تأثيرات الحواف', style: TextStyle(color: Colors.white,
        fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 11),
      SizedBox(height: 99, child: ListView(scrollDirection: Axis.horizontal,
        children: [
          _edgePreset(CutoutEdgeStyle.none, 'بدون', 0xFFFFFF),
          _edgePreset(CutoutEdgeStyle.cyan, 'فيروزي', 0x36E6EE),
          _edgePreset(CutoutEdgeStyle.glow, 'توهج', 0xFFDE2D),
          _edgePreset(CutoutEdgeStyle.doubleLine, 'مزدوج', 0x36E6EE),
          _edgePreset(CutoutEdgeStyle.paper, 'ورقي', 0xFFFFFF),
          _edgePreset(CutoutEdgeStyle.pink, 'وردي', 0xFF4DAA),
          _edgePreset(CutoutEdgeStyle.dashed, 'متقطع', 0xFFFFFF),
          _edgePreset(CutoutEdgeStyle.sparkle, 'زخارف', 0xFFDE2D),
        ])),
      if (style != CutoutEdgeStyle.none) ...[
        const SizedBox(height: 8),
        SizedBox(height: 34, child: ListView(scrollDirection: Axis.horizontal,
          children: [for (final color in _edgeColors)
            InkWell(onTap: () => _changeEdge(color: color),
              child: Container(width: 29, height: 29,
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Color(0xFF000000 | color),
                  border: Border.all(color: settings?.edgeColor == color
                    ? Colors.white : Colors.white38,
                    width: settings?.edgeColor == color ? 3 : 1))))])),
        const SizedBox(height: 4),
        _edgeSlider('الحجم', settings?.edgeSize ?? .45,
          (v) => _changeEdge(size: v)),
        if (distanceControl)
          _edgeSlider('المسافة', settings?.edgeDistance ?? .12,
            (v) => _changeEdge(distance: v))
        else
          _edgeSlider('التعتيم', settings?.edgeOpacity ?? .95,
            (v) => _changeEdge(opacity: v)),
      ],
      TextButton.icon(onPressed: () => setState(() =>
          _edgeFeatherVisible = !_edgeFeatherVisible),
        icon: Icon(_edgeFeatherVisible ? Icons.expand_less : Icons.expand_more,
          color: Colors.white70),
        label: const Text('تنعيم الحواف',
          style: TextStyle(color: Colors.white70, fontSize: 12))),
      if (_edgeFeatherVisible) Row(children: [
        Expanded(child: Slider(value: settings?.edgeFeather ?? .75,
          min: 0, max: 4, activeColor: Colors.white,
          onChanged: (_busy && !_rendering) ? null : (v) => setState(() =>
            _settings = _settings!.withOptions(edgeFeather: v)),
          onChangeEnd: (_) => _scheduleEdgeRender())),
        Text('${(settings?.edgeFeather ?? .75).toStringAsFixed(1)}',
          style: const TextStyle(color: Colors.white)),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: !_busy, child: Scaffold(backgroundColor: Colors.black,
      body: SafeArea(child: LayoutBuilder(builder: (context, limits) {
        final compact = limits.maxHeight < 660;
        return Column(children: [
          Expanded(flex: compact ? 7 : 10, child: _video()),
          _controls(),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _timeline()),
          if (_error != null) SizedBox(height: 42,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15),
              child: SingleChildScrollView(child: Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11))))),
          Expanded(flex: compact ? 5 : 6,
            child: Center(child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
              child: switch (_mode) {
                _CutoutMode.main => _mainTools(),
                _CutoutMode.custom => _brushTools(),
                _CutoutMode.chroma => _chromaTools(),
                _CutoutMode.edges => _edgesTools(),
              }))),
          Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(textDirection: TextDirection.ltr, children: [
              IconButton(tooltip: 'تأكيد', onPressed: _busy ? null : _confirm,
                icon: const Icon(Icons.check, color: Colors.white, size: 31)),
              if (_mode != _CutoutMode.main) TextButton.icon(
                onPressed: () {
                  final refresh = _mode == _CutoutMode.chroma &&
                      !_chromaRenderFresh;
                  final wasChroma = _mode == _CutoutMode.chroma;
                  if (wasChroma && _settings != null) {
                    _settings = _withCommittedChromaDraft(_settings!);
                    _chromaSettingsRevision++;
                  }
                  _leaveChromaMode();
                  setState(() => _mode = _CutoutMode.main);
                  if (wasChroma && _settings?.chromaEnabled == true && refresh) {
                    unawaited(_queueRender());
                  }
                },
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                label: const Text('الأدوات', style: TextStyle(color: Colors.white))),
              const Spacer(),
              TextButton.icon(onPressed: _reset,
                icon: const Icon(Icons.restore, color: Colors.white),
                label: const Text('إعادة تعيين',
                  style: TextStyle(color: Colors.white))),
            ])),
        ]);
      }))));
  }
}

class _CutoutBrushPainter extends CustomPainter {
  final List<CutoutStroke> strokes;
  final List<Offset> current;
  final int repaintRevision;
  final bool currentErase;
  final double currentRadius;
  const _CutoutBrushPainter({required this.strokes, required this.current,
    required this.repaintRevision, required this.currentErase,
    required this.currentRadius});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintPath(canvas, size, stroke.points, stroke.erase, stroke.radius, .31);
    }
    _paintPath(canvas, size, current, currentErase, currentRadius, .74);
    if (current.isNotEmpty) {
      final tip = Offset(current.last.dx * size.width,
          current.last.dy * size.height);
      canvas.drawCircle(tip, size.shortestSide * currentRadius,
          Paint()..color = Colors.white..strokeWidth = 1.3
            ..style = PaintingStyle.stroke);
    }
  }

  void _paintPath(Canvas canvas, Size size, List<Offset> points,
      bool erase, double radius, double opacity) {
    if (points.isEmpty) return;
    // Blue/cyan indicates erasing unwanted background; red means restoration.
    final color = (erase ? Colors.cyanAccent : Colors.redAccent)
        .withValues(alpha: opacity);
    final paint = Paint()..color = color..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.shortestSide * radius * 2
      ..style = PaintingStyle.stroke;
    if (points.length == 1) {
      canvas.drawCircle(Offset(points.first.dx * size.width,
        points.first.dy * size.height), paint.strokeWidth / 2,
        Paint()..color = color);
      return;
    }
    final path = Path()..moveTo(points.first.dx * size.width,
      points.first.dy * size.height);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CutoutBrushPainter old) =>
    old.strokes != strokes || old.current != current ||
    old.currentErase != currentErase || old.currentRadius != currentRadius ||
    old.repaintRevision != repaintRevision;
}


/// One decoded frame is magnified while the finger moves. The source image,
/// saved strokes, active stroke, and brush cursor share normalized coordinates.
/// No additional player or decoder is used during pointer movement.
class _CutoutMagnifierPainter extends CustomPainter {
  final ui.Image image;
  final Offset focus;
  final List<CutoutStroke> strokes;
  final List<Offset> current;
  final int repaintRevision;
  final bool currentErase;
  final double currentRadius;

  const _CutoutMagnifierPainter({required this.image, required this.focus,
    required this.strokes, required this.current,
    required this.repaintRevision, required this.currentErase,
    required this.currentRadius});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final side = math.min(image.width, image.height) * .32;
    final maxLeft = math.max(0.0, image.width - side);
    final maxTop = math.max(0.0, image.height - side);
    final left = (focus.dx * image.width - side / 2)
        .clamp(0.0, maxLeft).toDouble();
    final top = (focus.dy * image.height - side / 2)
        .clamp(0.0, maxTop).toDouble();
    final sample = Rect.fromLTWH(left, top, side, side);
    final full = Offset.zero & size;
    canvas.drawImageRect(image, sample, full,
        Paint()..filterQuality = FilterQuality.high);

    // Transform normalized video pixels through the identical crop used by
    // drawImageRect, so the loupe stroke stays exactly under the real brush.
    Offset locate(Offset p) => Offset(
        (p.dx * image.width - left) / side * size.width,
        (p.dy * image.height - top) / side * size.height);
    final brushScale = math.min(image.width, image.height) /
        side * size.shortestSide;

    void stroke(List<Offset> points, bool erase, double radius, double alpha) {
      if (points.isEmpty) return;
      final thickness = math.max(1.0, brushScale * radius * 2);
      final color = (erase ? Colors.cyanAccent : Colors.redAccent)
          .withValues(alpha: alpha);
      final paint = Paint()..color = color..strokeWidth = thickness
          ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
      if (points.length == 1) {
        canvas.drawCircle(locate(points.first), thickness / 2,
            Paint()..color = color);
      } else {
        final path = Path()..moveTo(locate(points.first).dx,
            locate(points.first).dy);
        for (final point in points.skip(1)) {
          final mapped = locate(point);
          path.lineTo(mapped.dx, mapped.dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    for (final item in strokes) {
      stroke(item.points, item.erase, item.radius, .34);
    }
    stroke(current, currentErase, currentRadius, .78);

    final cursor = locate(focus);
    final cursorRadius = brushScale * currentRadius;
    canvas.drawCircle(cursor, cursorRadius + 1.0,
        Paint()..color = Colors.black54..strokeWidth = 3.0
            ..style = PaintingStyle.stroke);
    canvas.drawCircle(cursor, cursorRadius,
        Paint()..color = Colors.white..strokeWidth = 1.8
            ..style = PaintingStyle.stroke);
    canvas.drawCircle(cursor, 2.3, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CutoutMagnifierPainter old) =>
      old.focus != focus || old.image != image ||
      old.strokes != strokes || old.current != current ||
      old.currentErase != currentErase || old.currentRadius != currentRadius ||
      old.repaintRevision != repaintRevision;
}

/// CPU fallback only. GPU is the normal picker/slider preview path.
/// Use the exact FFmpeg colorkey RGB-distance/alpha calculation (per pixel).
/// Including brightness prevents black from matching bright skin or beige.
// Match FFmpeg colorkey: RGB Euclidean distance normalized by sqrt(3).
double _tiniChromaKeep(int red, int green, int blue,
    int color, double similarity, double blend) {
  final dr = red - ((color >> 16) & 255);
  final dg = green - ((color >> 8) & 255);
  final db = blue - (color & 255);
  final distance = math.sqrt(dr * dr + dg * dg + db * db) /
      (255.0 * math.sqrt(3.0));
  final sim = similarity.clamp(.01, .12);
  final feather = blend.clamp(0.0, .05);
  return feather > .0001
      ? ((distance - sim) / feather).clamp(0.0, 1.0).toDouble()
      : (distance > sim ? 1.0 : 0.0);
}

/// Opaque greyscale image: mask intensity in RGB, alpha always 255.
/// It is used by the GPU only for previously committed color passes.
Uint8List _tiniChromaCommittedMaskPixels(Map<String, Object> data) {
  final source = data['rgba']! as Uint8List;
  final passes = data['passes']! as List<List<double>>;
  final result = Uint8List(source.length);
  for (var i = 0; i < source.length; i += 4) {
    var keep = 1.0;
    for (final pass in passes) {
      keep *= _tiniChromaKeep(source[i], source[i + 1], source[i + 2],
          pass[0].round(), pass[1], pass[2]);
      if (keep == 0.0) break;
    }
    final shade = (keep * 255).round();
    result[i] = shade;
    result[i + 1] = shade;
    result[i + 2] = shade;
    result[i + 3] = 255;
  }
  return result;
}

/// Fallback shows the same cumulative alpha as the GPU and FFmpeg paths.
Uint8List _tiniChromaPreviewPixels(Map<String, Object> data) {
  final source = data['rgba']! as Uint8List;
  final passes = data['passes']! as List<List<double>>;
  final currentEnabled = data['draftEnabled']! as bool;
  final color = data['color']! as int;
  final similarity = data['similarity']! as double;
  final blend = data['blend']! as double;
  final result = Uint8List.fromList(source);
  for (var i = 0; i < source.length; i += 4) {
    var keep = 1.0;
    for (final pass in passes) {
      keep *= _tiniChromaKeep(source[i], source[i + 1], source[i + 2],
          pass[0].round(), pass[1], pass[2]);
      if (keep == 0.0) break;
    }
    if (currentEnabled && keep != 0.0) {
      keep *= _tiniChromaKeep(source[i], source[i + 1], source[i + 2],
          color, similarity, blend);
    }
    result[i + 3] = (source[i + 3] * keep).round();
  }
  return result;
}

/// GPU preview: only shader uniforms change while the finger/slider moves.
/// No FFmpeg job or CPU isolate is launched for each pointer movement.
class _TiniChromaGpuPainter extends CustomPainter {
  final ui.Image image;
  final ui.FragmentProgram program;
  final ui.Image? committedMask;
  final bool draftEnabled;
  final int chromaColor;
  final double similarity;
  final double blend;

  const _TiniChromaGpuPainter({required this.image, required this.program,
    required this.committedMask, required this.draftEnabled,
    required this.chromaColor, required this.similarity, required this.blend});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shader = program.fragmentShader();
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, ((chromaColor >> 16) & 255) / 255.0);
    shader.setFloat(3, ((chromaColor >> 8) & 255) / 255.0);
    shader.setFloat(4, (chromaColor & 255) / 255.0);
    shader.setFloat(5, similarity.clamp(.01, .12).toDouble());
    shader.setFloat(6, blend.clamp(0.0, .05).toDouble());
    shader.setFloat(7, committedMask == null ? 0.0 : 1.0);
    shader.setFloat(8, draftEnabled ? 1.0 : 0.0);
    shader.setImageSampler(0, image, filterQuality: FilterQuality.low);
    shader.setImageSampler(1, committedMask ?? image,
        filterQuality: FilterQuality.low);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _TiniChromaGpuPainter old) =>
      old.image != image || old.program != program ||
      old.committedMask != committedMask ||
      old.draftEnabled != draftEnabled ||
      old.chromaColor != chromaColor ||
      old.similarity != similarity || old.blend != blend;
}

/// Lightweight preset thumbnails; output effects use mask-based FFmpeg layers.
class _EdgePresetPainter extends CustomPainter {
  final CutoutEdgeStyle style;
  final Color color;
  const _EdgePresetPainter(this.style, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .27, size.height * .88)
      ..lineTo(size.width * .20, size.height * .49)
      ..quadraticBezierTo(size.width * .25, size.height * .38,
          size.width * .34, size.height * .37)
      ..cubicTo(size.width * .15, size.height * .06,
          size.width * .76, -size.height * .06,
          size.width * .65, size.height * .37)
      ..quadraticBezierTo(size.width * .77, size.height * .40,
          size.width * .80, size.height * .50)
      ..lineTo(size.width * .73, size.height * .88)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF5A616E));
    if (style == CutoutEdgeStyle.doubleLine) {
      canvas.drawPath(path, Paint()..color = const Color(0xFFFF4DAA)
        ..style = PaintingStyle.stroke..strokeWidth = 8);
    }
    if (style == CutoutEdgeStyle.glow || style == CutoutEdgeStyle.pink) {
      // Preview the same broad + tight neon halo layers as FFmpeg output.
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: .55)
        ..style = PaintingStyle.stroke..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: .85)
        ..style = PaintingStyle.stroke..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
    final outline = Paint()..color = color..style = PaintingStyle.stroke
      ..strokeWidth = style == CutoutEdgeStyle.paper ? 6 : 3;
    if (style == CutoutEdgeStyle.dashed) {
      outline.strokeWidth = 2.2;
      final metrics = path.computeMetrics();
      for (final metric in metrics) {
        for (var offset = 0.0; offset < metric.length; offset += 8) {
          canvas.drawPath(metric.extractPath(offset,
              math.min(offset + 5, metric.length)), outline);
        }
      }
    } else if (style == CutoutEdgeStyle.sparkle) {
      final metric = path.computeMetrics().first;
      for (var x = 0.0; x < metric.length; x += 13) {
        final point = metric.getTangentForOffset(x)?.position;
        if (point == null) continue;
        canvas.drawLine(point.translate(-4, 0), point.translate(4, 0), outline);
        canvas.drawLine(point.translate(0, -4), point.translate(0, 4), outline);
      }
    } else {
      canvas.drawPath(path, outline);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePresetPainter old) =>
    old.style != style || old.color != color;
}
