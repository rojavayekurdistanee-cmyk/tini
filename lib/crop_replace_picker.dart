import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

/// Selected media and its source in-point. The target duration is set by the
/// selected timeline segment, not by a different length of the source video.
class CropReplacementSelection {
  final File file;
  final Duration start;
  final Duration duration;
  final Duration sourceDuration;
  const CropReplacementSelection({
    required this.file,
    required this.start,
    required this.duration,
    required this.sourceDuration,
  });
}

/// Opened only by CropBottomSheet's Replace action. It does not navigate to
/// the ordinary upload/composer flow or mutate the gallery selection there.
class CropReplacePicker extends StatefulWidget {
  final Duration? targetDuration;
  const CropReplacePicker({super.key, this.targetDuration});

  @override
  State<CropReplacePicker> createState() => _CropReplacePickerState();
}

class _CropReplacePickerState extends State<CropReplacePicker> {
  List<AssetEntity> _videos = [];
  bool _loading = true;
  bool _choosing = false;
  int _page = 0;
  bool _hasMore = true;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 400 &&
          !_loading && _hasMore) _loadPage();
    });
    _loadPage();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    if (_loading && _page != 0) return;
    if (mounted) setState(() => _loading = true);
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth && !permission.hasAccess) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final folders = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: true,
        filterOption: FilterOptionGroup(orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ]),
      );
      if (folders.isEmpty) {
        if (mounted) setState(() { _videos = []; _loading = false; _hasMore = false; });
        return;
      }
      final next = await folders.first.getAssetListPaged(page: _page, size: 80);
      if (!mounted) return;
      setState(() {
        _videos.addAll(next);
        _page++;
        _hasMore = next.length == 80;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح معرض الفيديو: $error')),
        );
      }
    }
  }

  Future<void> _choose(AssetEntity asset) async {
    if (_choosing) return;
    setState(() => _choosing = true);
    try {
      final file = await asset.originFile;
      if (!mounted) return;
      if (file == null) throw StateError('تعذر الوصول إلى الفيديو المحدد');
      final target = widget.targetDuration;
      CropReplacementSelection? selection;
      if (target == null) {
        selection = CropReplacementSelection(
          file: file, start: Duration.zero,
          duration: Duration(seconds: asset.duration),
          sourceDuration: Duration(seconds: asset.duration),
        );
      } else {
        selection = await Navigator.of(context).push<CropReplacementSelection>(
          MaterialPageRoute(builder: (_) => _CropReplaceTrimScreen(
            file: file, requiredDuration: target,
          )),
        );
      }
      if (mounted && selection != null) Navigator.of(context).pop(selection);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر اختيار الفيديو: $error')),
      );
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('الألبوم', style: TextStyle(fontSize: 17)),
        actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))],
      ),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 9),
          child: Text('الفيديوهات', style: TextStyle(color: Colors.black87, fontSize: 14)),
        ),
        Expanded(child: _videos.isEmpty && !_loading
          ? const Center(child: Text('لا توجد فيديوهات متاحة'))
          : GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2,
                childAspectRatio: 0.85,
              ),
              itemCount: _videos.length,
              itemBuilder: (context, index) {
                final asset = _videos[index];
                final m = asset.duration ~/ 60;
                final s = asset.duration % 60;
                return InkWell(
                  onTap: _choosing ? null : () => _choose(asset),
                  child: Stack(fit: StackFit.expand, children: [
                    AssetEntityImage(asset, isOriginal: false,
                      thumbnailSize: const ThumbnailSize(240, 320), fit: BoxFit.cover),
                    const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 27)),
                    Positioned(bottom: 4, right: 5,
                      child: Text('$m:${s.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white, fontSize: 11,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)]))),
                  ]),
                );
              },
            )),
        if (_loading) const LinearProgressIndicator(color: Color(0xFFFF3B30)),
      ]),
    );
  }
}

class _CropReplaceTrimScreen extends StatefulWidget {
  final File file;
  final Duration requiredDuration;
  const _CropReplaceTrimScreen({required this.file, required this.requiredDuration});

  @override
  State<_CropReplaceTrimScreen> createState() => _CropReplaceTrimScreenState();
}

class _CropReplaceTrimScreenState extends State<_CropReplaceTrimScreen> {
  static const MethodChannel _framesChannel = MethodChannel('titi_star/thumbnails');
  VideoPlayerController? _player;
  List<Uint8List> _frames = [];
  Duration _sourceDuration = Duration.zero;
  Duration _start = Duration.zero;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final player = VideoPlayerController.file(widget.file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _player = player;
    try {
      await player.initialize();
      if (!mounted) return;
      _sourceDuration = player.value.duration;
      if (_sourceDuration < widget.requiredDuration) {
        setState(() {
          _error = 'الفيديو المختار أقصر من المقطع الذي تريد استبداله';
          _loading = false;
        });
        return;
      }
      setState(() => _loading = false);
      try {
        final count = ((_sourceDuration.inMilliseconds / 1000) * 2).ceil().clamp(8, 80);
        final frames = await _framesChannel.invokeMethod<List<dynamic>>('getFrames', {
          'path': widget.file.path, 'count': count, 'thumbHeight': 90,
        });
        if (mounted && frames != null) setState(() {
          _frames = frames.whereType<Uint8List>().toList();
        });
      } catch (_) {
        // Native thumbnails are optional. Video seeking still works without them.
      }
    } catch (error) {
      if (mounted) setState(() { _error = 'تعذر فتح الفيديو: $error'; _loading = false; });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _setStart(int milliseconds) {
    final maxMs = (_sourceDuration - widget.requiredDuration).inMilliseconds;
    final safe = milliseconds.clamp(0, maxMs).toInt();
    setState(() => _start = Duration(milliseconds: safe));
    _player?.pause();
    _player?.seekTo(_start);
  }

  @override
  Widget build(BuildContext context) {
    final total = _sourceDuration.inMilliseconds;
    final chosen = widget.requiredDuration.inMilliseconds;
    final maxMs = (total - chosen).clamp(0, total);
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context)),
        title: const Text('اختيار المقطع البديل', style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Colors.teal))
        : _error != null
        ? Center(child: Padding(padding: const EdgeInsets.all(24),
            child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)))
        : Column(children: [
            Expanded(child: Center(child: (_player?.value.isInitialized ?? false)
              ? AspectRatio(aspectRatio: _player!.value.aspectRatio,
                  child: VideoPlayer(_player!))
              : const SizedBox.shrink())),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(children: [
                Text('حدد جزءاً بطول ${(chosen / 1000).toStringAsFixed(1)} ثانية',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 10),
                LayoutBuilder(builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final selectionWidth = total <= 0 ? w : (chosen / total * w).clamp(24.0, w).toDouble();
                  final left = total <= 0 ? 0.0 : (_start.inMilliseconds / total * w).clamp(0.0, w - selectionWidth).toDouble();
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      if (total > 0) _setStart(_start.inMilliseconds + (d.delta.dx / w * total).round());
                    },
                    child: SizedBox(height: 57, child: Stack(children: [
                      Row(children: List.generate(10, (i) => Expanded(
                        child: _frames.isEmpty
                          ? Container(color: i.isEven ? Colors.white12 : Colors.white24)
                          : Image.memory(_frames[(i * _frames.length ~/ 10).clamp(0, _frames.length - 1)],
                              height: 55, fit: BoxFit.cover, gaplessPlayback: true),
                      ))),
                      Positioned(left: left, width: selectionWidth, top: 0, bottom: 0,
                        child: IgnorePointer(child: Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3),
                            borderRadius: BorderRadius.circular(4)),
                          child: const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            ColoredBox(color: Colors.white, child: SizedBox(width: 6)),
                            ColoredBox(color: Colors.white, child: SizedBox(width: 6)),
                          ]),
                        ))),
                    ])),
                  );
                }),
                Slider(
                  value: _start.inMilliseconds.toDouble().clamp(0.0, maxMs.toDouble()).toDouble(),
                  min: 0, max: maxMs > 0 ? maxMs.toDouble() : 1.0,
                  activeColor: const Color(0xFFFF3B30),
                  onChanged: maxMs > 0 ? (v) => _setStart(v.round()) : null,
                ),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3B30),
                    foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(context, CropReplacementSelection(
                    file: widget.file, start: _start,
                    duration: widget.requiredDuration,
                    sourceDuration: _sourceDuration,
                  )),
                  child: const Text('استبدال'),
                )),
              ]),
            ),
          ]),
    );
  }
}
