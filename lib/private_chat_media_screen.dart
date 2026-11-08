import 'dart:async';
import 'audience_access.dart';
import 'package:flutter/material.dart';
import 'audience_message_gate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';

const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);
const Color kFieldFill = Color(0xFF1C1C1E);

/// معرض الوسائط المتبادلة ضمن محادثة خاصة واحدة.
class PrivateChatMediaScreen extends StatelessWidget {
  final String roomId;

  const PrivateChatMediaScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        foregroundColor: Colors.white,
        title: const Text('الوسائط', style: TextStyle(
          color: Colors.white, fontFamily: 'Tajawal', fontSize: 18)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text('الوسائط التي تمت مشاركتها',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white, fontFamily: 'Tajawal',
                fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),
          Expanded(
            child:
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chat_rooms')
                    .doc(roomId)
                    .collection('messages')
                    .where('type', whereIn: ['image', 'video', 'album'])
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      child: Text('تعذر تحميل الوسائط: ${snap.error}',
                        style: const TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 11),
                        textAlign: TextAlign.center)),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white54));
                  }
                  // كل ألبوم له معاينة واحدة فقط بنفس قياس الوسائط الفردية؛
                  // تبقى جميع عناصر الألبوم متاحة بالسحب داخل العارض.
                  final entries = <_PrivateMediaEntry>[];
                  for (final doc in snap.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['viewOnce'] == true || data['mediaDeleted'] == true || data['isDeleted'] == true) continue;
                    final type = (data['type'] ?? '').toString();
                    final caption = (data['text'] ?? data['caption'] ?? '').toString();
                    if (type == 'album' && data['mediaItems'] is List) {
                      final album = <_PrivateMediaEntry>[];
                      for (final raw in data['mediaItems'] as List) {
                        if (raw is! Map) continue;
                        if (raw['viewOnce'] == true || raw['mediaDeleted'] == true) continue;
                        final item = Map<String, dynamic>.from(raw);
                        final url = (item['url'] ?? item['mediaUrl'] ?? '').toString();
                        if (url.isEmpty) continue;
                        album.add(_PrivateMediaEntry(
                          url: url,
                          isVideo: item['isVideo'] == true || item['type'] == 'video',
                          caption: (item['caption'] ?? '').toString().isNotEmpty
                              ? item['caption'].toString() : caption,
                          source: {'mediaUrl': url,
                            ...AudienceMessagePolicy.sourceFields({...data, ...item,
                              'mediaUrl': url})},
                        ));
                      }
                      if (album.isEmpty) continue;
                      // اعرض غلاف الألبوم فقط في الشبكة، ولا تفرد عناصره.
                      entries.add(album.first.withAlbum(album, 0));
                    } else if (type == 'image' || type == 'video') {
                      final url = (data['mediaUrl'] ?? '').toString();
                      if (url.isNotEmpty) {
                        entries.add(_PrivateMediaEntry(url: url,
                          isVideo: type == 'video', caption: caption,
                          source: {'mediaUrl': url,
                            ...AudienceMessagePolicy.sourceFields(data)}));
                      }
                    }
                  }
                  if (entries.isEmpty) {
                    return const Center(
                      child: Text('ستظهر هنا الصور ومقاطع الفيديو التي تمت مشاركتها في هذه الدردشة.',
                        style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 14),
                        textAlign: TextAlign.center),
                    );
                  }
                  return GridView.builder(
                    shrinkWrap: false,
                    padding: const EdgeInsets.fromLTRB(2, 0, 2, 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2,
                      childAspectRatio: 1),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final item = entries[i];
                      Future<void> open({VideoPlayerController? preparedController,
                          Future<bool>? preparedReady}) async {
                        if (!AudienceMessagePolicy.canView(item.source)) return;
                        if (item.album != null) {
                          await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AudienceMessageGate(message: item.source,
                              child: _PrivateAlbumViewer(
                              items: item.album!, initialIndex: item.albumIndex,
                              preparedController: preparedController,
                              preparedReady: preparedReady))));
                        } else if (item.isVideo) {
                          await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AudienceMessageGate(message: item.source,
                              child: _PrivateVideoViewerScreen(
                              videoUrl: item.url, caption: item.caption, source: item.source))));
                        } else {
                          await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AudienceMessageGate(message: item.source,
                              child: _PrivateImageViewerScreen(
                              imageUrl: item.url, caption: item.caption))));
                        }
                      }
                      if (item.isVideo) {
                        return AudienceMessageGate(message: item.source,
                          child: ClipRect(child: Stack(fit: StackFit.expand, children: [
                          _PrivateInfoVideoTile(
                            key: ValueKey('${item.url}_${item.albumIndex}'),
                            videoUrl: item.url, caption: item.caption,
                            source: item.source,
                            onOpen: item.album == null ? null : (controller, ready) async {
                              // إذا فشلت تهيئة المعاينة، جرّب مشغلاً جديداً عند الفتح.
                              if (await ready) {
                                await open(preparedController: controller, preparedReady: ready);
                              } else {
                                await open();
                              }
                            },
                          ),
                          if (item.album != null)
                            const Positioned(left: 6, top: 6,
                              child: IgnorePointer(child: Icon(Icons.collections_rounded,
                                color: Colors.white, size: 20))),
                        ])));
                      }
                      return AudienceMessageGate(message: item.source,
                        child: GestureDetector(
                        onTap: open,
                        child: ClipRect(child: Stack(fit: StackFit.expand, children: [
                          Image.network(item.url, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(color: kFieldFill)),
                          if (item.album != null)
                            const Positioned(left: 6, top: 6,
                              child: Icon(Icons.collections_rounded,
                                color: Colors.white, size: 20)),
                          if (item.caption.trim().isNotEmpty)
                            const Positioned(right: 6, bottom: 6,
                              child: Icon(Icons.notes_rounded, color: Colors.white, size: 19)),
                        ])),
                      ));
                    },
                  );
                },
              ),
          ),
        ],
      ),
    );
  }
}

// معاينة الفيديو تُجهّز المشغّل مرة واحدة، ويُعاد استخدامه عند فتح الفيديو.
// يبقى مالك المشغّل هو عنصر الشبكة، فلا يحدث تحميل ثانٍ عند الانتقال.
class _PrivateInfoVideoTile extends StatefulWidget {
  final String videoUrl;
  final String caption;
  final Map<String, dynamic> source;
  final Future<void> Function(VideoPlayerController, Future<bool>)? onOpen;
  const _PrivateInfoVideoTile({super.key, required this.videoUrl, required this.caption,
    required this.source, this.onOpen});

  @override
  State<_PrivateInfoVideoTile> createState() => _PrivateInfoVideoTileState();
}

class _PrivateInfoVideoTileState extends State<_PrivateInfoVideoTile>
    with AutomaticKeepAliveClientMixin {
  late final VideoPlayerController _controller;
  late final Future<bool> _ready;
  bool _initialized = false;
  bool _viewerOpen = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _ready = _controller.initialize().then((_) {
      if (!mounted || !AudienceMessagePolicy.canView(widget.source)) return false;
      setState(() => _initialized = true);
      return true;
    }).catchError((Object error) {
      debugPrint('Private media thumbnail init failed: $error');
      return false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      onTap: () async {
        // لا نعرض نفس VideoPlayer في الشبكة والعارض بنفس اللحظة.
        // هذا يمنع تنازع سطح الفيديو أثناء فتح عناصر الألبوم.
        if (_viewerOpen || !AudienceMessagePolicy.canView(widget.source)) return;
        setState(() => _viewerOpen = true);
        try {
          if (widget.onOpen != null) {
            await widget.onOpen!(_controller, _ready);
          } else {
            final thumbnailReady = await _ready;
            if (!mounted || !AudienceMessagePolicy.canView(widget.source)) return;
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => AudienceMessageGate(message: widget.source,
                child: _PrivateVideoViewerScreen(
                videoUrl: widget.videoUrl,
                caption: widget.caption,
                source: widget.source,
                preparedController: thumbnailReady ? _controller : null,
                preparedReady: thumbnailReady ? _ready : null,
              )),
            ));
          }
        } finally {
          if (mounted) {
            if (_controller.value.isInitialized) {
              await _controller.pause();
              await _controller.seekTo(Duration.zero);
            }
            if (mounted) setState(() => _viewerOpen = false);
          }
        }
      },
      child: Stack(fit: StackFit.expand, children: [
        Container(color: kFieldFill),
        if (_initialized && !_viewerOpen)
          FittedBox(fit: BoxFit.cover, child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ))
        else
          const Center(child: Icon(Icons.videocam_outlined, color: Colors.white38)),
        Container(color: Colors.black26,
          child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 32))),
        if (widget.caption.trim().isNotEmpty)
          const Positioned(right: 6, bottom: 6,
            child: Icon(Icons.notes_rounded, color: Colors.white, size: 19)),
      ]),
    );
  }
}

// النص الطويل قابل للفتح بكلمة «المزيد» والتمرير داخل مساحة محددة.
class _PrivateMediaCaption extends StatefulWidget {
  final String caption;
  const _PrivateMediaCaption({required this.caption});
  @override
  State<_PrivateMediaCaption> createState() => _PrivateMediaCaptionState();
}

class _PrivateMediaCaptionState extends State<_PrivateMediaCaption> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    if (widget.caption.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(color: Colors.black87),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _expanded ? 190 : 48),
          child: SingleChildScrollView(
            child: Text(widget.caption, textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5)),
          ),
        ),
        if (widget.caption.length > 65 || widget.caption.contains('\n'))
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(padding: const EdgeInsets.only(top: 5),
              child: Text(_expanded ? 'أقل' : 'المزيد',
                style: const TextStyle(color: Color(0xFF21C063), fontSize: 14))),
          ),
      ]),
    );
  }
}

class _PrivateImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final String caption;
  const _PrivateImageViewerScreen({required this.imageUrl, this.caption = ''});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: Stack(children: [
        Positioned.fill(child: Center(child: InteractiveViewer(minScale: 0.5, maxScale: 4.0, child: Image.network(imageUrl)))),
        if (caption.trim().isNotEmpty)
          Positioned(left: 0, right: 0, bottom: 0,
            child: SafeArea(top: false, child: _PrivateMediaCaption(caption: caption))),
      ]),
    );
  }
}

class _PrivateVideoViewerScreen extends StatefulWidget {
  final String videoUrl;
  final Map<String, dynamic> source;
  final String caption;
  final VideoPlayerController? preparedController;
  final Future<bool>? preparedReady;
  const _PrivateVideoViewerScreen({required this.videoUrl, this.caption = '',
    required this.source, this.preparedController, this.preparedReady});

  @override
  State<_PrivateVideoViewerScreen> createState() => _PrivateVideoViewerScreenState();
}

class _PrivateVideoViewerScreenState extends State<_PrivateVideoViewerScreen> {
  late VideoPlayerController _controller;
  bool _isInit = false;
  bool _isMuted = false;
  bool _failed = false;

  bool get _canView => mounted && AudienceMessagePolicy.canView(widget.source);

  void _onAudienceChanged() {
    if (!_canView) {
      unawaited(_controller.setVolume(0));
      unawaited(_controller.pause());
    }
  }

  Future<void> _playAuthorized() async {
    if (!_canView) return;
    await _controller.play();
    if (!_canView) {
      await _controller.setVolume(0);
      await _controller.pause();
    }
  }

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.preparedController ??
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    AudienceAccess.instance.addListener(_onAudienceChanged);
    final ready = widget.preparedReady ??
        _controller.initialize().then((_) => true).catchError((Object _) => false);
    ready.then((ok) async {
      if (!_canView) return;
      if (!ok) {
        setState(() => _failed = true);
        return;
      }
      _controller.addListener(_onVideoChanged);
      setState(() => _isInit = true);
      await _controller.setLooping(true);
      await _playAuthorized();
    });
  }

  @override
  void dispose() {
    AudienceAccess.instance.removeListener(_onAudienceChanged);
    _controller.removeListener(_onVideoChanged);
    if (widget.preparedController == null) {
      _controller.dispose();
    } else {
      _controller.pause();
      _controller.setLooping(false);
      _controller.setVolume(1);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: _failed
              ? const Text('تعذر تحميل الفيديو', style: TextStyle(color: Colors.white70))
              : _isInit
                  ? InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: GestureDetector(
                      onTap: () => _controller.value.isPlaying
                          ? _controller.pause() : _playAuthorized(),
                      child: Stack(alignment: Alignment.center, children: [
                        AspectRatio(aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller)),
                        if (!_controller.value.isPlaying)
                          Container(padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow, color: Colors.white, size: 48)),
                      ]),
                    ),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
        ),
        SafeArea(child: Padding(padding: const EdgeInsets.all(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(onTap: () => Navigator.pop(context),
              child: Container(padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 22))),
            GestureDetector(onTap: _isInit ? () {
              if (!_canView) return;
              setState(() => _isMuted = !_isMuted);
              _controller.setVolume(_isMuted ? 0 : 1);
            } : null,
              child: Container(padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: Icon(_isMuted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white, size: 22))),
          ]))),
        if (_isInit)
          Positioned(bottom: 0, left: 0, right: 0,
            child: SafeArea(top: false, child: VideoProgressIndicator(
              _controller, allowScrubbing: true,
              colors: const VideoProgressColors(playedColor: Colors.white,
                bufferedColor: Colors.white24, backgroundColor: Colors.transparent),
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10)))),
        if (widget.caption.trim().isNotEmpty)
          Positioned(left: 0, right: 0, bottom: 35,
            child: SafeArea(top: false, child: _PrivateMediaCaption(caption: widget.caption))),
      ]),
    );
  }
}

// عناصر الألبوم في معرض معلومات المجموعة، دون تغيير بيانات الرسائل الأصلية.
class _PrivateMediaEntry {
  final String url;
  final bool isVideo;
  final String caption;
  final List<_PrivateMediaEntry>? album;
  final int albumIndex;
  final Map<String, dynamic> source;

  const _PrivateMediaEntry({required this.url, required this.isVideo,
    required this.caption, this.album, this.albumIndex = 0, this.source = const {}});

  _PrivateMediaEntry withAlbum(List<_PrivateMediaEntry> items, int index) =>
      _PrivateMediaEntry(url: url, isVideo: isVideo, caption: caption,
        album: items, albumIndex: index, source: source);
}

// سحب أفقي بين كل صور وفيديوهات الرسالة المجمعة، مع وصف كل عنصر.
class _PrivateAlbumViewer extends StatefulWidget {
  final List<_PrivateMediaEntry> items;
  final int initialIndex;
  final VideoPlayerController? preparedController;
  final Future<bool>? preparedReady;
  const _PrivateAlbumViewer({required this.items, required this.initialIndex,
    this.preparedController, this.preparedReady});

  @override
  State<_PrivateAlbumViewer> createState() => _PrivateAlbumViewerState();
}

class _PrivateAlbumViewerState extends State<_PrivateAlbumViewer> {
  late final PageController _pages;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final item = widget.items[i];
              return AudienceMessageGate(message: item.source,
                child: Stack(children: [
                Positioned.fill(child: Center(
                  child: item.isVideo
                    ? (i == _index ? _PrivateAlbumVideoPage(key: ValueKey(item.url), url: item.url,
                        source: item.source,
                        preparedController: i == widget.initialIndex ? widget.preparedController : null,
                        preparedReady: i == widget.initialIndex ? widget.preparedReady : null)
                        : const SizedBox.shrink())
                    : InteractiveViewer(minScale: 0.5, maxScale: 4.0, child: Image.network(item.url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text('تعذر تحميل الصورة',
                          style: TextStyle(color: Colors.white70)))),
                )),
                if (item.caption.trim().isNotEmpty)
                  Positioned(left: 0, right: 0, bottom: 0,
                    child: _PrivateMediaCaption(caption: item.caption)),
              ]));
            },
          ),
          Positioned(top: 4, left: 12, right: 12,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white)),
              Text('${_index + 1} / ${widget.items.length}',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            ])),
        ]),
      ),
    );
  }
}

class _PrivateAlbumVideoPage extends StatefulWidget {
  final String url;
  final Map<String, dynamic> source;
  final VideoPlayerController? preparedController;
  final Future<bool>? preparedReady;
  const _PrivateAlbumVideoPage({super.key, required this.url,
    required this.source, this.preparedController, this.preparedReady});
  @override
  State<_PrivateAlbumVideoPage> createState() => _PrivateAlbumVideoPageState();
}

class _PrivateAlbumVideoPageState extends State<_PrivateAlbumVideoPage> {
  late final VideoPlayerController _video;
  bool _ready = false;
  bool _failed = false;

  bool get _canView => mounted && AudienceMessagePolicy.canView(widget.source);

  void _onAudienceChanged() {
    if (!_canView) {
      unawaited(_video.setVolume(0));
      unawaited(_video.pause());
    }
  }

  Future<void> _playAuthorized() async {
    if (!_canView) return;
    await _video.play();
    if (!_canView) {
      await _video.setVolume(0);
      await _video.pause();
    }
  }

  void _changed() { if (mounted) setState(() {}); }

  @override
  void initState() {
    super.initState();
    _video = widget.preparedController ??
        VideoPlayerController.networkUrl(Uri.parse(widget.url));
    AudienceAccess.instance.addListener(_onAudienceChanged);
    final ready = widget.preparedReady ??
        _video.initialize().then<bool>((_) => true).catchError((Object error) {
          debugPrint('Private album video initialization failed: $error');
          return false;
        });
    ready.then((ok) {
      if (!ok) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      if (!_canView) return;
      _video.addListener(_changed);
      setState(() => _ready = true);
      _playAuthorized();
    });
  }

  @override
  void dispose() {
    AudienceAccess.instance.removeListener(_onAudienceChanged);
    _video.removeListener(_changed);
    if (widget.preparedController == null) {
      _video.dispose();
    } else {
      _video.pause();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('تعذر تحميل الفيديو', style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 12),
      const Text('تحقق من الاتصال أو جرّب فتح الفيديو من الدردشة',
        style: TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
    if (!_ready) return const CircularProgressIndicator(color: Colors.white);
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: GestureDetector(
      onTap: () => _video.value.isPlaying ? _video.pause() : _playAuthorized(),
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: _video.value.aspectRatio, child: VideoPlayer(_video)),
        if (!_video.value.isPlaying)
          const Icon(Icons.play_circle_fill, color: Colors.white, size: 54),
        Positioned(left: 0, right: 0, bottom: 0,
          child: VideoProgressIndicator(_video, allowScrubbing: true,
            colors: const VideoProgressColors(playedColor: Colors.white))),
      ]),
      ),
    );
  }
}
