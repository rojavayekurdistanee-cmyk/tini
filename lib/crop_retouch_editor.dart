import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'crop_retouch_model.dart';
import 'crop_retouch_engine.dart';
import 'crop_retouch_gpu.dart';
import 'crop_overlay_model.dart';
import 'crop_overlay_preview.dart';

/// Android previews use a hardware decoder and face-aware GPU processing.
/// Session changes are local until the user confirms with the check mark.
typedef CropRetouchStillRenderer =
    Future<CropRetouchStill> Function({
      required String input,
      required int positionMs,
      required CropRetouchSettings settings,
    });

class CropRetouchEditor extends StatefulWidget {
  final String basePath;
  // An expensive previously-edited preview may arrive after this route opens.
  // It never replaces the user's in-progress retouch slider settings.
  final Future<String>? preparedBase;
  final List<CropRetouchSegment> segments;
  final int selectedIndex;
  final List<CropOverlay> overlays;
  final CropRetouchStillRenderer stillRenderer;
  final VideoPlayerController Function(String)? playerFactory;
  const CropRetouchEditor({
    super.key,
    required this.basePath,
    this.preparedBase,
    required this.segments,
    this.selectedIndex = 0,
    this.overlays = const [],
    this.stillRenderer = CropRetouchEngine.still,
    this.playerFactory,
  });
  @override
  State<CropRetouchEditor> createState() => _CropRetouchEditorState();
}

class _CropRetouchEditorState extends State<CropRetouchEditor> {
  late VideoPlayerController _base;
  VideoPlayerController? _processed;
  String? _processedPath, _processedKey;
  late String _currentBasePath;
  int _baseGeneration = 0;
  bool _preparingBase = false;
  String? _baselineWarning;
  late List<CropRetouchSettings> _settings;
  late int _selected;
  int _control = 0, _stillRequest = 0, _renderRequest = 0;
  int _positionMs = 0;
  bool _ready = false, _rendering = false, _compare = false, _closed = false;
  double _progress = 0;
  String? _error;
  bool? _hasFace;
  Uint8List? _still;
  final Map<int, Uint8List> _thumbnails = {};
  Timer? _debounce;
  CropRetouchSegment get _segment => widget.segments[_selected];
  CropRetouchSettings get _value => _settings[_selected];
  String get _key => '$_selected|${_value.smooth}|${_value.teeth}';
  bool get _hasProcessed =>
      _processedKey == _key && _processed?.value.isInitialized == true;
  VideoPlayerController get _player =>
      _hasProcessed && !_compare ? _processed! : _base;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedIndex.clamp(0, widget.segments.length - 1);
    _settings = widget.segments.map((s) => s.settings).toList();
    _currentBasePath = widget.basePath;
    _preparingBase = widget.preparedBase != null;
    _base = _createBasePlayer(_currentBasePath);
    final opened = _open();
    if (widget.preparedBase != null) {
      unawaited(_adoptPreparedBase(opened));
    }
  }

  VideoPlayerController _createBasePlayer(String path) =>
      widget.playerFactory?.call(path) ??
      (Platform.isAndroid
          ? CropRetouchGpuController(path)
          : VideoPlayerController.file(File(path)));

  Future<void> _adoptPreparedBase(Future<void> opened) async {
    try {
      final path = await widget.preparedBase!;
      await opened;
      if (!mounted || _closed || path == _currentBasePath) return;
      final next = _createBasePlayer(path);
      var adopted = false;
      try {
        await next.initialize();
        if (!mounted || _closed) return;
        final target = _positionMs.clamp(
          0, (next.value.duration.inMilliseconds - 1).clamp(0, 1 << 31),
        ).toInt();
        await next.seekTo(Duration(milliseconds: target));
        if (!mounted || _closed) return;
        await _pause();
        if (!mounted || _closed) return;
        final previous = _base;
        final processed = _processed, processedPath = _processedPath;
        ++_renderRequest;
        ++_stillRequest;
        _debounce?.cancel();
        previous.removeListener(_tick);
        processed?.removeListener(_tick);
        next.addListener(_tick);
        setState(() {
          _base = next;
          _ready = true;
          _currentBasePath = path;
          _baseGeneration++;
          _processed = null;
          _processedPath = null;
          _processedKey = null;
          _rendering = false;
          _progress = 0;
          _still = null;
          _hasFace = null;
          _error = null;
          _preparingBase = false;
          _thumbnails.clear();
        });
        adopted = true;
        _requestStill();
        unawaited(_loadThumbnails());
        unawaited(_releasePreview(processed, processedPath));
        unawaited(previous.dispose());
      } finally {
        if (!adopted) await next.dispose();
      }
    } catch (error) {
      if (mounted && !_closed) {
        setState(() {
          _preparingBase = false;
          _baselineWarning =
              'تعذر تجهيز معاينة المؤثرات السابقة؛ يمكنك المتابعة وسيعاد تجهيزها عند النشر. $error';
        });
      }
    }
  }

  Future<void> _open() async {
    try {
      await _base.initialize();
      if (!mounted) return;
      await _base.seekTo(Duration(milliseconds: _segment.startMs));
      if (!mounted) return;
      _positionMs = _segment.startMs;
      _base.addListener(_tick);
      setState(() => _ready = true);
      _requestStill();
      _loadThumbnails();
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر فتح الفيديو: $error');
    }
  }

  Future<void> _loadThumbnails() async {
    final generation = _baseGeneration;
    final path = _currentBasePath;
    for (var i = 0; i < widget.segments.length && mounted &&
        generation == _baseGeneration; i++) {
      try {
        final frame = await VideoThumbnail.thumbnailData(
          video: path,
          timeMs: widget.segments[i].startMs,
          maxWidth: 120,
          quality: 65,
        );
        if (mounted && generation == _baseGeneration && frame != null) {
          setState(() => _thumbnails[i] = frame);
        }
      } catch (_) {
        /* The video remains usable without gallery thumbnails. */
      }
    }
  }

  void _tick() {
    if (!mounted || !_ready) return;
    final player = _player;
    if (player is CropRetouchGpuController) {
      _hasFace = player.faceCount < 0 ? null : player.faceCount > 0;
      _error = player.thermalPaused
          ? 'تم إيقاف المعاينة مؤقتاً حتى تنخفض حرارة الجهاز'
          : player.value.errorDescription;
    }
    var position = player.value.position.inMilliseconds;
    if (player == _processed) position += _segment.startMs;
    if (position >= _segment.endMs - 20 && player.value.isPlaying) {
      player.pause();
      if (player == _base) {
        player.seekTo(Duration(milliseconds: _segment.endMs - 1));
      }
    }
    setState(
      () => _positionMs = position.clamp(_segment.startMs, _segment.endMs),
    );
  }

  Future<void> _pause() async {
    if (_base.value.isPlaying) await _base.pause();
    if (_processed?.value.isPlaying == true) await _processed!.pause();
  }

  void _requestStill() {
    _debounce?.cancel();
    final request = ++_stillRequest;
    final gpu = _base;
    if (gpu is CropRetouchGpuController) {
      gpu.apply(_compare ? const CropRetouchSettings() : _value).catchError((
        Object error,
      ) {
        if (mounted && request == _stillRequest) {
          setState(() => _error = 'تعذرت معاينة التنميق: $error');
        }
      });
      return;
    }
    final settings = _value;
    final key = _key;
    final at = _positionMs.clamp(
      _segment.startMs,
      (_segment.endMs - 40).clamp(_segment.startMs, 1 << 31),
    );
    if (!settings.enabled) {
      setState(() {
        _still = null;
        _hasFace = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final frame = await widget.stillRenderer(
          input: _currentBasePath,
          positionMs: at,
          settings: settings,
        );
        if (!mounted || request != _stillRequest || key != _key) return;
        setState(() {
          _still = frame.png;
          _hasFace = frame.hasFace;
          _error = null;
        });
      } catch (error) {
        if (mounted && request == _stillRequest) {
          setState(() => _error = 'تعذرت معاينة التنميق: $error');
        }
      }
    });
  }

  void _change(CropRetouchSettings value) {
    _pause();
    ++_renderRequest;
    setState(() {
      _settings[_selected] = value;
      _still = null;
      _error = null;
    });
    if (_base is! CropRetouchGpuController) {
      _base.seekTo(Duration(milliseconds: _positionMs));
    }
    _requestStill();
  }

  Future<void> _select(int index) async {
    ++_renderRequest;
    ++_stillRequest;
    _debounce?.cancel();
    await _pause();
    if (!mounted) return;
    setState(() {
      _selected = index;
      _still = null;
      _hasFace = null;
      _error = null;
      _positionMs = _segment.startMs;
    });
    await _base.seekTo(Duration(milliseconds: _positionMs));
    if (mounted) _requestStill();
  }

  Future<void> _seek(double fraction) async {
    await _pause();
    if (!mounted) return;
    final pos =
        (_segment.startMs + fraction * (_segment.endMs - _segment.startMs - 1))
            .round();
    await _base.seekTo(Duration(milliseconds: pos));
    if (_hasProcessed) {
      await _processed!.seekTo(Duration(milliseconds: pos - _segment.startMs));
    }
    if (!mounted) return;
    setState(() => _positionMs = pos);
    _requestStill();
  }

  Future<void> _play() async {
    ++_stillRequest;
    _debounce?.cancel();
    setState(() => _still = null);
    if (_player.value.isPlaying) {
      await _pause();
      if (mounted) _requestStill();
      return;
    }
    if (_base is CropRetouchGpuController) {
      try {
        if (_positionMs >= _segment.endMs - 40) {
          await _base.seekTo(Duration(milliseconds: _segment.startMs));
        }
        await _base.play();
      } catch (error) {
        if (mounted) setState(() => _error = 'تعذر تشغيل المعاينة: $error');
      }
      return;
    }
    if (_rendering) return;
    if (!_value.enabled) {
      if (_positionMs >= _segment.endMs - 40) {
        await _base.seekTo(Duration(milliseconds: _segment.startMs));
      }
      await _base.play();
      return;
    }
    if (_hasProcessed) {
      if (_processed!.value.position.inMilliseconds >=
          _segment.endMs - _segment.startMs - 40) {
        await _processed!.seekTo(Duration.zero);
      }
      await _processed!.play();
      return;
    }
    final request = ++_renderRequest, key = _key;
    final sourcePath = _currentBasePath;
    final settings = _value, segment = _segment;
    setState(() {
      _rendering = true;
      _progress = 0;
      _error = null;
    });
    String? path;
    try {
      final result = await CropRetouchEngine.render(
        input: sourcePath,
        settings: settings,
        sourceStartMs: segment.startMs,
        durationMs: segment.endMs - segment.startMs,
        width: _base.value.size.width.round(),
        height: _base.value.size.height.round(),
        cancelled: () => _closed || request != _renderRequest,
        onProgress: (v) {
          if (mounted && request == _renderRequest) {
            setState(() => _progress = v);
          }
        },
      );
      if (result.path != sourcePath) path = result.path;
      if (!mounted || request != _renderRequest) return;
      setState(() => _hasFace = result.faceFrames > 0);
      if (path == null) {
        await _base.seekTo(Duration(milliseconds: segment.startMs));
        await _base.play();
        return;
      }
      final controller = VideoPlayerController.file(File(path));
      try {
        await controller.initialize();
      } catch (_) {
        await controller.dispose();
        rethrow;
      }
      if (!mounted || request != _renderRequest) {
        await controller.dispose();
        return;
      }
      final previous = _processed, oldPath = _processedPath;
      final at = _positionMs >= segment.endMs - 40
          ? 0
          : (_positionMs - segment.startMs).clamp(
              0,
              segment.endMs - segment.startMs - 1,
            );
      await controller.seekTo(Duration(milliseconds: at));
      if (!mounted || request != _renderRequest) {
        await controller.dispose();
        return;
      }
      controller.addListener(_tick);
      setState(() {
        _processed = controller;
        _processedKey = key;
        _processedPath = path;
      });
      path = null;
      await previous?.dispose();
      if (oldPath != null) {
        try {
          await File(oldPath).delete();
        } catch (_) {}
      }
      await controller.play();
    } on CropRetouchCancelled {
      /* The newer settings own the next preview. */
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر تشغيل المعاينة: $error');
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _compareDown() async {
    final at = _positionMs;
    setState(() => _compare = true);
    await _pause();
    if (_base is CropRetouchGpuController) {
      _requestStill();
    } else {
      await _base.seekTo(Duration(milliseconds: at));
    }
  }

  void _compareUp() {
    setState(() => _compare = false);
    _requestStill();
  }

  @override
  void dispose() {
    _closed = true;
    ++_stillRequest;
    ++_renderRequest;
    _debounce?.cancel();
    _base.dispose();
    final player = _processed, path = _processedPath;
    _releasePreview(player, path);
    super.dispose();
  }

  Future<void> _releasePreview(
    VideoPlayerController? player,
    String? path,
  ) async {
    await player?.dispose();
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  String _time(int ms) => '${(ms / 1000).toStringAsFixed(1)}ث';
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('التنميق'),
        leading: IconButton(
          tooltip: 'إلغاء التنميق',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: !_ready
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!, style: const TextStyle(color: Colors.white)),
            )
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _base.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          cropRetouchVideo(_player),
                          if (!_compare &&
                              !_player.value.isPlaying &&
                              _still != null)
                            Image.memory(
                              _still!,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                          if (widget.overlays.isNotEmpty)
                            IgnorePointer(
                              child: CropOverlayCanvas(
                                overlays: widget.overlays,
                                positionMs: _positionMs,
                                playing: _player.value.isPlaying,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTapDown: (_) => _compareDown(),
                      onTapUp: (_) => _compareUp(),
                      onTapCancel: _compareUp,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.compare, color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'تشغيل معاينة التنميق',
                      onPressed: _rendering ? null : _play,
                      icon: Icon(
                        _player.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        '${_time(_positionMs - _segment.startMs)} / ${_time(_segment.endMs - _segment.startMs)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Slider(
                    value:
                        ((_positionMs - _segment.startMs) /
                                (_segment.endMs - _segment.startMs))
                            .clamp(0.0, 1.0),
                    onChanged: _seek,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                  ),
                ),
                SizedBox(
                  height: 58,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.segments.length,
                    separatorBuilder: (_, index) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => InkWell(
                      onTap: () => _select(index),
                      child: Container(
                        width: 78,
                        decoration: BoxDecoration(
                          color: const Color(0xFF26323B),
                          image: _thumbnails[index] == null
                              ? null
                              : DecorationImage(
                                  image: MemoryImage(_thumbnails[index]!),
                                  fit: BoxFit.cover,
                                  colorFilter: const ColorFilter.mode(
                                    Color(0x44000000),
                                    BlendMode.darken,
                                  ),
                                ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: index == _selected
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'مقطع ${index + 1}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_preparingBase)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'جار تحديث معاينة المؤثرات السابقة بالخلفية…',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_baselineWarning != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      _baselineWarning!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 10),
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'إعادة تعيين التنميق',
                              onPressed: () =>
                                  _change(const CropRetouchSettings()),
                              icon: const Icon(
                                Icons.restart_alt,
                                color: Colors.white,
                              ),
                            ),
                            const Expanded(
                              child: Text(
                                'إعادة التعيين',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            IconButton(
                              tooltip: 'تأكيد التنميق',
                              onPressed: _rendering
                                  ? null
                                  : () => Navigator.pop(
                                      context,
                                      List<CropRetouchSettings>.unmodifiable(
                                        _settings,
                                      ),
                                    ),
                              icon: const Icon(
                                Icons.check,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _tool(
                              const Icon(
                                Icons.face_retouching_natural_outlined,
                                color: Colors.white,
                                size: 31,
                              ),
                              'تنميق تلقائي',
                              _value.automatic,
                              () => _change(
                                _value.automatic
                                    ? const CropRetouchSettings()
                                    : CropRetouchSettings.auto,
                              ),
                            ),
                            _tool(
                              const Icon(
                                Icons.water_drop_outlined,
                                color: Colors.white,
                                size: 31,
                              ),
                              'تنعيم',
                              _control == 0,
                              () => setState(() => _control = 0),
                            ),
                            _tool(
                              const FaIcon(
                                FontAwesomeIcons.tooth,
                                color: Colors.white,
                                size: 31,
                              ),
                              'بريق الأسنان',
                              _control == 1,
                              () => setState(() => _control = 1),
                            ),
                          ],
                        ),
                        Slider(
                          value: _control == 0 ? _value.smooth : _value.teeth,
                          activeColor: Colors.white,
                          inactiveColor: Colors.white12,
                          onChanged: (v) => _change(
                            _control == 0
                                ? _value.copyWith(smooth: v, automatic: false)
                                : _value.copyWith(teeth: v, automatic: false),
                          ),
                        ),
                        Text(
                          '${((_control == 0 ? _value.smooth : _value.teeth) * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        if (_rendering)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: [
                                LinearProgressIndicator(value: _progress),
                                const SizedBox(height: 5),
                                Text(
                                  'جار تجهيز المعاينة ${(_progress * 100).round()}%',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        if (_hasFace == false && _value.enabled)
                          const Padding(
                            padding: EdgeInsets.all(6),
                            child: Text(
                              'لم يُكتشف وجه واضح في هذه اللقطة',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              _error!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => setState(() {
                              _settings = List.filled(_settings.length, _value);
                            }),
                            icon: const Icon(
                              Icons.layers_outlined,
                              color: Colors.white70,
                            ),
                            label: const Text(
                              'تطبيق على الكل',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
  Widget _tool(Widget icon, String label, bool selected, VoidCallback onTap) =>
      Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFF343434),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      icon,
                      if (label == 'تنميق تلقائي' && _value.automatic)
                        const Positioned(
                          right: 7,
                          bottom: 5,
                          child: Icon(
                            Icons.check,
                            color: Color(0xFF25C68D),
                            size: 25,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
}
