import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'crop_overlay_model.dart';
import 'crop_model.dart';
import 'crop_overlay_project_player.dart';
import 'filter_bottom_sheet.dart';
import 'crop_overlay_preview.dart';
import 'crop_overlay_timeline.dart';
import 'crop_retouch_gpu.dart';
import 'crop_retouch_model.dart';

/// Transactional editor: back/cancel never changes the parent project. The base
/// is a preview render of existing edits, never a replacement for their metadata.
class CropOverlayEditor extends StatefulWidget {
  final String basePath;
  final List<CropOverlay> initial;
  final List<CropRetouchSegment> retouchRegions;
  // Optional immutable project snapshot for the instant, non-destructive view.
  final List<CropClip> projectClips;
  final List<FilterClip> filterClips;
  final Size? projectSize;
  final String? backgroundPreviewPath;
  final String? backgroundPreviewClipId;
  const CropOverlayEditor({
    super.key,
    required this.basePath,
    required this.initial,
    this.retouchRegions = const [],
    this.projectClips = const [],
    this.filterClips = const [],
    this.projectSize,
    this.backgroundPreviewPath,
    this.backgroundPreviewClipId,
  });
  @override
  State<CropOverlayEditor> createState() => _CropOverlayEditorState();
}

class _CropOverlayEditorState extends State<CropOverlayEditor> {
  VideoPlayerController? _base;
  CropOverlayProjectPlayer? _project;
  late CropOverlayHistory _history;
  List<CropOverlay>? _draft;
  CropOverlay? _gestureOriginal;
  Offset? _gestureFocal;
  String? _selected;
  bool _loading = true, _picking = false;
  String? _error;
  final _baseFrames = <Uint8List>[];
  final _layerFrames = <String, Uint8List>{};
  List<CropOverlay> get _layers => _draft ?? _history.value;
  CropOverlay? get _current =>
      _layers.where((o) => o.id == _selected).firstOrNull;
  int get _duration =>
      _project?.durationMs ?? _base!.value.duration.inMilliseconds;
  int get _position =>
      _project?.positionMs ?? _base!.value.position.inMilliseconds;

  Future<void> _pause() => _project?.pause() ?? _base!.pause();
  Future<void> _play() => _project?.play() ?? _base!.play();
  ValueListenable<VideoPlayerValue> get _videoState =>
      _project?.state ?? _base!;

  @override
  void initState() {
    super.initState();
    _history = CropOverlayHistory(widget.initial);
    _selected = widget.initial.lastOrNull?.id;
    if (widget.projectClips.isNotEmpty) {
      _project = CropOverlayProjectPlayer(
        sourcePath: widget.basePath,
        projectClips: widget.projectClips,
        originalSize: widget.projectSize ?? const Size(9, 16),
        filters: widget.filterClips,
        existingBackgroundPath: widget.backgroundPreviewPath,
        existingBackgroundClipId: widget.backgroundPreviewClipId,
      );
    } else {
      // Preserve the legacy single-source editor for existing callers.
      _base = widget.retouchRegions.any((r) => r.settings.enabled)
          ? CropRetouchGpuController(widget.basePath)
          : VideoPlayerController.file(File(widget.basePath));
    }
    _open();
  }

  Future<void> _open() async {
    try {
      if (_project != null) {
        await _project!.initialize();
      } else {
        await _base!.initialize();
        if (!mounted) return;
        if (_base is CropRetouchGpuController) {
          await (_base! as CropRetouchGpuController).apply(
            const CropRetouchSettings(),
            regions: widget.retouchRegions,
          );
          if (!mounted) return;
        }
        await _base!.setLooping(false);
      }
      if (!mounted) return;
      final initial = widget.initial
          .map((o) => o.fit(_duration))
          .whereType<CropOverlay>()
          .toList();
      // Clamp previews to the current project length after parent trim changes.
      _history = CropOverlayHistory(initial);
      setState(() => _loading = false);
      _loadFrames();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر فتح معاينة الفيديو: $error';
        });
      }
    }
  }

  Future<void> _loadFrames() async {
    for (var i = 0; i < 8 && mounted; i++) {
      try {
        final time = (_duration * i / 8).round();
        final frame = _project == null
            ? await VideoThumbnail.thumbnailData(
                video: widget.basePath,
                timeMs: time,
                maxWidth: 120,
                quality: 65,
              )
            : await _project!.thumbnailAt(time);
        if (!mounted) return;
        if (frame != null) setState(() => _baseFrames.add(frame));
      } catch (_) {
        break;
      }
    }
    for (final o in List<CropOverlay>.of(_layers)) {
      await _thumbnail(o);
    }
  }

  Future<void> _thumbnail(CropOverlay o) async {
    try {
      final bytes = o.isVideo
          ? await VideoThumbnail.thumbnailData(
              video: o.path,
              timeMs: o.sourceStartMs,
              maxWidth: 120,
              quality: 65,
            )
          : await File(o.path).readAsBytes();
      if (mounted && bytes != null) setState(() => _layerFrames[o.id] = bytes);
    } catch (_) {
      /* Media itself still previews when thumbnail decoding fails. */
    }
  }

  Future<void> _seek(int value) async {
    if (_project != null) {
      await _project!.seek(value);
    } else {
      await _pause();
      await _base!.seekTo(
        Duration(milliseconds: value.clamp(0, math.max(0, _duration - 1))),
      );
    }
  }

  void _beginEdit() {
    _pause();
    _draft ??= List.of(_history.value);
  }

  void _change(CropOverlay next) {
    setState(() {
      _draft ??= List.of(_history.value);
      _draft = [
        for (final o in _draft!)
          if (o.id == next.id) next else o,
      ];
    });
  }

  void _endEdit() {
    final next = _draft;
    if (next != null) _history.commit(next);
    setState(() {
      _draft = null;
      _gestureOriginal = null;
      _gestureFocal = null;
    });
  }

  void _commit(List<CropOverlay> next) {
    _pause();
    setState(() {
      _history.commit(next);
      _draft = null;
    });
  }

  Future<void> _pick({CropOverlay? replacing}) async {
    if (_picking) return;
    await _pause();
    if (!mounted) return;
    final type = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined, color: Colors.white),
              title: const Text(
                'إضافة صورة',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined, color: Colors.white),
              title: const Text(
                'إضافة فيديو',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    setState(() => _picking = true);
    try {
      final picker = ImagePicker();
      final picked = type
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(
              source: ImageSource.gallery,
              requestFullMetadata: false,
            );
      if (picked == null || !mounted) return;
      final temp = await getTemporaryDirectory();
      final id = 'overlay_${DateTime.now().microsecondsSinceEpoch}';
      double aspect;
      var sourceDuration = 0;
      String path;
      if (type) {
        final suffix = picked.path.split('.').last;
        path =
            '${temp.path}/$id.${RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(suffix) ? suffix : 'mp4'}';
        await File(picked.path).copy(path);
        final probe = VideoPlayerController.file(File(path));
        try {
          await probe.initialize();
          aspect = probe.value.aspectRatio;
          sourceDuration = probe.value.duration.inMilliseconds;
          if (sourceDuration <= 0) throw StateError('الفيديو فارغ');
        } finally {
          await probe.dispose();
        }
      } else {
        // Normalize orientation/HEIC to a PNG that Flutter and FFmpeg both read.
        final codec = await ui.instantiateImageCodec(
          await picked.readAsBytes(),
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            aspect = frame.image.width / frame.image.height;
            final bytes = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (bytes == null) throw StateError('تعذر قراءة الصورة');
            path = '${temp.path}/$id.png';
            await File(path).writeAsBytes(bytes.buffer.asUint8List());
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
      if (!mounted) return;
      final start =
          replacing?.startMs ??
          _position.clamp(0, math.max(0, _duration - 100));
      final end =
          replacing?.endMs ??
          (type ? math.min(_duration, start + sourceDuration) : _duration);
      final layer = CropOverlay(
        id: replacing?.id ?? id,
        path: path,
        isVideo: type,
        aspectRatio: aspect,
        startMs: start,
        endMs: end,
        centerX: replacing?.centerX ?? .5,
        centerY: replacing?.centerY ?? .5,
        width: replacing?.width ?? .45,
        sourceDurationMs: sourceDuration,
      );
      _commit(
        replacing == null
            ? [..._layers, layer]
            : [
                for (final o in _layers)
                  if (o.id == replacing.id) layer else o,
              ],
      );
      setState(() => _selected = layer.id);
      await _seek(start);
      await _thumbnail(layer);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر إضافة الوسائط: $error')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void dispose() {
    _project?.dispose();
    _base?.dispose();
    super.dispose();
  }

  String _time(int ms) =>
      '${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('التراكب'),
          leading: IconButton(
            tooltip: 'إلغاء',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          actions: [
            IconButton(
              tooltip: 'حفظ التراكبات',
              onPressed: _loading || _picking || _error != null
                  ? null
                  : () {
                      if (_draft != null) _endEdit();
                      Navigator.pop(
                        context,
                        List<CropOverlay>.unmodifiable(_history.value),
                      );
                    },
              icon: const Icon(Icons.check),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _videoState,
                builder: (context, video, _) => Column(
                  children: [
                    Expanded(
                      flex: 5,
                      child: LayoutBuilder(
                        builder: (context, bounds) {
                          final ratio = video.aspectRatio;
                          final w = math.min(
                            bounds.maxWidth,
                            bounds.maxHeight * ratio,
                          );
                          final h = w / ratio;
                          return Center(
                            child: SizedBox(
                              width: w,
                              height: h,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: _project?.buildPicture() ??
                                        cropRetouchVideo(_base!),
                                  ),
                                  if (_project?.backgroundLoading == true)
                                    const Positioned(
                                      top: 8,
                                      left: 8,
                                      right: 8,
                                      child: IgnorePointer(
                                        child: Center(
                                          child: Text(
                                            'جار تجهيز معاينة الخلفية…',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_project?.backgroundError != null ||
                                      _project?.playbackError != null)
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      right: 8,
                                      child: IgnorePointer(
                                        child: Text(
                                          _project?.playbackError ??
                                              _project!.backgroundError!,
                                          style: const TextStyle(
                                            color: Color(0xFFE53935),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned.fill(
                                    child: CropOverlayCanvas(
                                      overlays: _layers,
                                      positionMs: video.position.inMilliseconds,
                                      playing: video.isPlaying,
                                      selectedId: _selected,
                                      onSelect: (id) =>
                                          setState(() => _selected = id),
                                      onGestureStart: (o, d) {
                                        _beginEdit();
                                        _gestureOriginal = o;
                                        _gestureFocal = d.focalPoint;
                                        setState(() => _selected = o.id);
                                      },
                                      onGestureUpdate: (o, d, size) {
                                        final original = _gestureOriginal;
                                        if (original == null ||
                                            _gestureFocal == null) {
                                          return;
                                        }
                                        final delta =
                                            d.focalPoint - _gestureFocal!;
                                        _change(
                                          original.copyWith(
                                            width: original.width * d.scale,
                                            centerX:
                                                original.centerX +
                                                delta.dx / size.width,
                                            centerY:
                                                original.centerY +
                                                delta.dy / size.height,
                                          ),
                                        );
                                      },
                                      onGestureEnd: _endEdit,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'تراجع',
                          onPressed: _history.canUndo
                              ? () {
                                  _pause();
                                  setState(() {
                                    _draft = null;
                                    _history.undo();
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.undo, color: Colors.white70),
                        ),
                        IconButton(
                          tooltip: 'إعادة',
                          onPressed: _history.canRedo
                              ? () {
                                  _pause();
                                  setState(() {
                                    _draft = null;
                                    _history.redo();
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.redo, color: Colors.white70),
                        ),
                        IconButton(
                          tooltip: 'تشغيل أو إيقاف',
                          onPressed: () async {
                            if (video.isPlaying) {
                              await _pause();
                            } else {
                              if (_position >= _duration - 50) {
                                await _seek(0);
                              }
                              await _play();
                            }
                          },
                          icon: Icon(
                            video.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_time(_position)} / ${_time(_duration)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Slider(
                        value: _position
                            .clamp(0, math.max(1, _duration))
                            .toDouble(),
                        max: math.max(1, _duration).toDouble(),
                        onChanged: (v) => _seek(v.round()),
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: CropOverlayTimeline(
                              overlays: _layers,
                              durationMs: _duration,
                              positionMs: _position,
                              selectedId: _selected,
                              baseFrames: _baseFrames,
                              layerFrames: _layerFrames,
                              onSelect: (id) => setState(() => _selected = id),
                              onSeek: _seek,
                              onChanged: _change,
                              onEditStart: _beginEdit,
                              onEditEnd: _endEdit,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_picking) const LinearProgressIndicator(minHeight: 2),
                    if (_current != null) _controls(_current!),
                    SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _tool(
                              Icons.add_photo_alternate_outlined,
                              'إضافة تراكب',
                              _picking ? null : () => _pick(),
                            ),
                            _tool(
                              Icons.swap_horiz,
                              'استبدال',
                              _current == null || _picking
                                  ? null
                                  : () => _pick(replacing: _current),
                            ),
                            _tool(
                              Icons.content_cut,
                              'انقسام',
                              _current == null ||
                                      _position <= _current!.startMs ||
                                      _position >= _current!.endMs
                                  ? null
                                  : () {
                                      final o = _current!;
                                      final parts = o.split(
                                        _position,
                                        'overlay_${DateTime.now().microsecondsSinceEpoch}',
                                      );
                                      _commit([
                                        for (final layer in _layers)
                                          if (layer.id == o.id)
                                            ...parts
                                          else
                                            layer,
                                      ]);
                                      if (_layerFrames[o.id] != null) {
                                        _layerFrames[parts.last.id] =
                                            _layerFrames[o.id]!;
                                      }
                                    },
                            ),
                            _tool(
                              Icons.delete_outline,
                              'حذف',
                              _current == null
                                  ? null
                                  : () {
                                      _commit(
                                        _layers
                                            .where((o) => o.id != _selected)
                                            .toList(),
                                      );
                                      setState(
                                        () =>
                                            _selected = _layers.lastOrNull?.id,
                                      );
                                    },
                            ),
                            _tool(
                              Icons.center_focus_strong,
                              'توسيط',
                              _current == null
                                  ? null
                                  : () => _commit([
                                      for (final o in _layers)
                                        if (o.id == _selected)
                                          o.copyWith(
                                            centerX: .5,
                                            centerY: .5,
                                            width: .45,
                                          )
                                        else
                                          o,
                                    ]),
                            ),
                            _tool(
                              Icons.layers,
                              'للأمام',
                              _current == null
                                  ? null
                                  : () {
                                      final o = _current!;
                                      _commit([
                                        ..._layers.where((v) => v.id != o.id),
                                        o,
                                      ]);
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _controls(CropOverlay o) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text('الحجم', style: TextStyle(color: Colors.white70)),
            Expanded(
              child: Slider(
                value: math.log(o.width / .02) / math.log(400),
                onChangeStart: (_) => _beginEdit(),
                onChanged: (v) =>
                    _change(o.copyWith(width: .02 * math.pow(400, v))),
                onChangeEnd: (_) => _endEdit(),
              ),
            ),
            Text(
              '${(o.width * 100).round()}%',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              '${_time(o.startMs)} – ${_time(o.endMs)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _commit([
                for (final layer in _layers)
                  if (layer.id == o.id)
                    layer.copyWith(startMs: 0, endMs: _duration)
                  else
                    layer,
              ]),
              child: const Text('طوال الفيديو'),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _tool(IconData icon, String label, VoidCallback? action) => SizedBox(
    width: 82,
    child: TextButton(
      onPressed: action,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: action == null ? Colors.white24 : Colors.white),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: action == null ? Colors.white24 : Colors.white70,
            ),
          ),
        ],
      ),
    ),
  );
}
