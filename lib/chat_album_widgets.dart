import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// عنصر الألبوم: {url: رابط الوسيط, isVideo: true/false}
class ChatAlbumGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const ChatAlbumGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final visible = items.take(4).toList();
    return SizedBox(
      width: 230,
      height: visible.length <= 2 ? 115 : 230,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 2, crossAxisSpacing: 2,
        ),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final item = visible[index];
          final url = item['url']?.toString() ?? '';
          final isVideo = item['isVideo'] == true;
          final more = items.length - 4;
          return GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChatAlbumViewer(items: items, initialIndex: index),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(fit: StackFit.expand, children: [
                isVideo
                    ? _AlbumVideoThumbnail(url: url)
                    : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                if (isVideo) const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 32)),
                if (index == 3 && more > 0)
                  Container(color: Colors.black54, alignment: Alignment.center,
                    child: Text('+$more', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold))),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class ChatAlbumViewer extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  const ChatAlbumViewer({super.key, required this.items, required this.initialIndex});
  @override
  State<ChatAlbumViewer> createState() => _ChatAlbumViewerState();
}

class _ChatAlbumViewerState extends State<ChatAlbumViewer> {
  late final PageController _pages;
  late int _index;
  VideoPlayerController? _video;
  bool _zoomGestureActive = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pages = PageController(initialPage: _index);
    _prepareVideo();
  }

  Future<void> _prepareVideo() async {
    final current = widget.items[_index];
    final old = _video;
    _video = null;
    if (old != null) await old.dispose();
    if (!mounted) return;
    if (current['isVideo'] != true) { setState(() {}); return; }
    final controller = VideoPlayerController.networkUrl(Uri.parse(current['url'].toString()));
    _video = controller;
    try {
      await controller.initialize();
      if (!mounted || _video != controller) return;
      await controller.play();
      setState(() {});
    } catch (_) { if (mounted) setState(() {}); }
  }

  void _setZoomGestureActive(bool active) {
    if (!mounted || _zoomGestureActive == active) return;
    setState(() => _zoomGestureActive = active);
  }

  @override
  void dispose() {
    _pages.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, title: Text('${_index + 1} / ${widget.items.length}')),
    body: PageView.builder(
      controller: _pages,
      itemCount: widget.items.length,
      physics: _zoomGestureActive ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
      onPageChanged: (index) { setState(() { _index = index; _zoomGestureActive = false; }); _prepareVideo(); },
      itemBuilder: (context, index) {
        final item = widget.items[index];
        if (item['isVideo'] == true) {
          if (index != _index) return const SizedBox.shrink();
          if (_video == null || !_video!.value.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }
          return _AlbumZoomContent(
            key: ValueKey('album_video_$index'),
            onGestureLockChanged: _setZoomGestureActive,
            child: GestureDetector(
              onTap: () { _video!.value.isPlaying ? _video!.pause() : _video!.play(); setState(() {}); },
              child: AspectRatio(aspectRatio: _video!.value.aspectRatio, child: VideoPlayer(_video!)),
            ),
          );
        }
        return _AlbumZoomContent(
          key: ValueKey('album_image_$index'),
          onGestureLockChanged: _setZoomGestureActive,
          child: Image.network(item['url'].toString(), fit: BoxFit.contain),
        );
      },
    ),
  );
}

// عارض الزوم داخل الألبوم: يعزل حركة الإصبعين عن سحب صفحات الألبوم.
class _AlbumZoomContent extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool> onGestureLockChanged;
  const _AlbumZoomContent({super.key, required this.child, required this.onGestureLockChanged});

  @override
  State<_AlbumZoomContent> createState() => _AlbumZoomContentState();
}

class _AlbumZoomContentState extends State<_AlbumZoomContent> {
  final TransformationController _transformation = TransformationController();
  int _pointers = 0;
  bool _locked = false;

  void _syncLock() {
    final scale = _transformation.value.getMaxScaleOnAxis();
    final shouldLock = _pointers >= 2 || (scale - 1.0).abs() > 0.01;
    if (_locked == shouldLock) return;
    _locked = shouldLock;
    widget.onGestureLockChanged(shouldLock);
  }

  @override
  void dispose() {
    // لا نرسل تغييرات للأب أثناء إزالة الصفحة.
    _transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) { _pointers++; _syncLock(); },
    onPointerUp: (_) { if (_pointers > 0) _pointers--; _syncLock(); },
    onPointerCancel: (_) { if (_pointers > 0) _pointers--; _syncLock(); },
    child: InteractiveViewer(
      transformationController: _transformation,
      minScale: 0.5,
      maxScale: 4.0,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      onInteractionUpdate: (_) => _syncLock(),
      onInteractionEnd: (_) => _syncLock(),
      child: SizedBox.expand(child: Center(child: widget.child)),
    ),
  );
}

// صورة معاينة للفيديو بدون تشغيله داخل فقاعة الدردشة.
class _AlbumVideoThumbnail extends StatefulWidget {
  final String url;
  const _AlbumVideoThumbnail({required this.url});
  @override
  State<_AlbumVideoThumbnail> createState() => _AlbumVideoThumbnailState();
}

class _AlbumVideoThumbnailState extends State<_AlbumVideoThumbnail> {
  VideoPlayerController? _controller;
  @override
  void initState() {
    super.initState();
    _load();
  }
  Future<void> _load() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      if (mounted) setState(() {});
    } catch (_) { if (mounted) setState(() {}); }
  }
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container(color: Colors.black54);
    }
    return FittedBox(fit: BoxFit.cover, child: SizedBox(
      width: controller.value.size.width,
      height: controller.value.size.height,
      child: VideoPlayer(controller),
    ));
  }
}
