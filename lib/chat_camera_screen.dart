import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'caption_preview_screen.dart';
import 'media_picker_screen.dart';
import 'multi_media_preview_screen.dart';
import 'preview_media_item.dart';

enum ChatCameraMode { video, photo, videoNote }

/// شاشة كاميرا الشات (تصميم واتساب).
/// ترجع: Map {path, caption, isVideo}  أو  Map {paths: List<String>} عند الاختيار من المعرض.
class ChatCameraScreen extends StatefulWidget {
  /// اسم الجروب/الشخص الذي يظهر بجانب زر الإرسال في شاشة المعاينة.
  final String? recipientName;

  /// true = (المجموعات) السماح باختيار عدة صور/فيديوهات وشاشة معاينة متعددة (حد أقصى 5).
  /// false = السلوك القديم (عنصر واحد).
  /// عند الإرسال بعدة عناصر ترجع: Map {items: [ {path, caption, isVideo, isVideoNote, viewOnce}, ... ]}
  final bool allowMulti;
  const ChatCameraScreen({super.key, this.recipientName, this.allowMulti = false});

  /// انتقال fade مثل واتساب
  static Route<dynamic> route({String? recipientName, bool allowMulti = false}) {
    return PageRouteBuilder<dynamic>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => ChatCameraScreen(recipientName: recipientName, allowMulti: allowMulti),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  State<ChatCameraScreen> createState() => _ChatCameraScreenState();
}

class _ChatCameraScreenState extends State<ChatCameraScreen> with WidgetsBindingObserver {
  // ---------- ثوابت التصميم (dp) مقاسة من تسجيلات واتساب ----------
  static const double _topBtn = 37;
  static const double _sideBtn = 48;
  static const double _wandBtn = 37;
  static const double _ringIdle = 64;
  static const double _ringTap = 77; // فيديو / ملاحظة فيديو (ضغطة)
  static const double _ringHold = 124; // ضغط مطوّل من وضع الصورة
  static const double _stripH = 67;
  static const double _previewTopGap = 21;
  static const int _maxVideoSeconds = 600;
  static const int _maxNoteSeconds = 60;
  static const Color _red = Color(0xFFE5384D);
  static const Color _btnBg = Color(0x61000000);

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  int? _indexBeforeNote;
  bool _isInitialized = false;
  bool _permissionDenied = false;
  bool _switching = false;
  ChatCameraMode _mode = ChatCameraMode.photo;

  bool _isRecording = false;
  bool _holdStyle = false;
  bool _starting = false;
  bool _stopRequested = false;
  bool _stopping = false;
  Timer? _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _elapsed = Duration.zero;

  List<AssetEntity> _recentAssets = [];
  static List<AssetEntity> _recentCache = [];
  AssetPathEntity? _recentPath;
  bool _loadingMore = false;
  bool _recentDone = false;
  static const int _pageSize = 80;
  int? _queuedIndex;
  bool _flashOn = false;
  bool _shutterFlash = false;

  // اختيار متعدد من شريط المعرض (يعمل فقط عند allowMulti)
  final List<AssetEntity> _selected = [];
  bool _openingSelected = false;

  static const List<ChatCameraMode> _order = [
    ChatCameraMode.videoNote,
    ChatCameraMode.photo,
    ChatCameraMode.video,
  ];

  @override
  void initState() {
    super.initState();
    _recentAssets = _recentCache; // عرض فوري لآخر صور محمّلة سابقاً
    WidgetsBinding.instance.addObserver(this);
    _initAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      if (_isRecording) return;
      c.dispose();
      _controller = null;
      if (mounted) setState(() => _isInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _startController(_cameraIndex);
    }
  }

  Future<void> _initAll() async {
    final statuses = await [Permission.camera, Permission.microphone, Permission.photos].request();
    if (statuses[Permission.camera] != PermissionStatus.granted) {
      if (mounted) setState(() => _permissionDenied = true);
      return;
    }
    try {
      _cameras = await availableCameras();
    } catch (e) {
      debugPrint('Camera list error: $e');
    }
    if (_cameras.isEmpty) return;
    _cameraIndex = _indexOf(CameraLensDirection.back) ?? 0;
    _loadRecent(); // بالتوازي مع تشغيل الكاميرا، بدون انتظار
    await _startController(_cameraIndex);
  }

  int? _indexOf(CameraLensDirection dir) {
    for (int i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == dir) return i;
    }
    return null;
  }

  Future<void> _startController(int index) async {
    if (_cameras.isEmpty) return;
    if (_switching) {
      _queuedIndex = index; // نكمل بعد انتهاء التبديل الحالي بدل تجاهل الطلب
      return;
    }
    _switching = true;
    try {
      final old = _controller;
      _controller = null;
      if (mounted) setState(() => _isInitialized = false);
      // نترك إطاراً لإزالة المعاينة القديمة قبل إغلاق الكاميرا
      await Future.delayed(const Duration(milliseconds: 50));
      await old?.dispose();
      // أندرويد يحتاج وقتاً قصيراً لتحرير الكاميرا قبل فتح غيرها (سبب الشاشة السوداء)
      await Future.delayed(const Duration(milliseconds: 250));
      CameraController? c;
      for (int attempt = 0; attempt < 2; attempt++) {
        final tmp = CameraController(_cameras[index], ResolutionPreset.high, enableAudio: true);
        try {
          await tmp.initialize();
          c = tmp;
          break;
        } catch (e) {
          debugPrint('Camera init attempt $attempt failed: $e');
          try {
            await tmp.dispose();
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      if (c == null) return;
      if (!mounted) {
        await c.dispose();
        return;
      }
      _controller = c;
      _cameraIndex = index;
      if (_flashOn && _cameras[index].lensDirection == CameraLensDirection.back) {
        try {
          await c.setFlashMode(FlashMode.torch);
        } catch (_) {}
      }
      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    } finally {
      _switching = false;
    }
    final q = _queuedIndex;
    _queuedIndex = null;
    if (q != null && q != _cameraIndex && mounted) await _startController(q);
  }

Future<void> _loadRecent() async {
  try {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!(ps.isAuth || ps == PermissionState.limited)) return;
    // ترتيب صريح: الأحدث أولاً (حسب تاريخ الإنشاء) مع التحميل على دفعات
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.common,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (paths.isEmpty) return;
    // أول دفعة بسرعة (الأحدث أولاً)، والباقي يُحمّل تلقائياً أثناء السحب
    _recentPath = paths[0];
    final List<AssetEntity> assets = await paths[0].getAssetListRange(start: 0, end: _pageSize);
    _recentDone = assets.length < _pageSize;
    _recentCache = assets;
    if (mounted) setState(() => _recentAssets = assets);
  } catch (e) {
    debugPrint('Recent assets error: $e');
  }
}

  Future<void> _loadMoreRecent() async {
    final path = _recentPath;
    if (path == null || _loadingMore || _recentDone) return;
    _loadingMore = true;
    try {
      final start = _recentAssets.length;
      final more = await path.getAssetListRange(start: start, end: start + _pageSize);
      if (more.length < _pageSize) _recentDone = true;
      if (more.isNotEmpty && mounted) {
        final all = [..._recentAssets, ...more];
        _recentCache = all;
        setState(() => _recentAssets = all);
      }
    } catch (e) {
      debugPrint('Load more assets error: $e');
    } finally {
      _loadingMore = false;
    }
  }

  // ---------- أوضاع ----------
  Future<void> _setMode(ChatCameraMode m) async {
    if (_isRecording || _starting || m == _mode) return;
    final prev = _mode;
    HapticFeedback.selectionClick();
    setState(() => _mode = m);
    if (m == ChatCameraMode.videoNote) {
      final front = _indexOf(CameraLensDirection.front);
      if (front != null && front != _cameraIndex) {
        _indexBeforeNote = _cameraIndex;
        await _startController(front);
      }
    } else if (prev == ChatCameraMode.videoNote && _indexBeforeNote != null) {
      final back = _indexBeforeNote!;
      _indexBeforeNote = null;
      if (back != _cameraIndex) await _startController(back);
    }
  }

  void _onSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 300) return;
    final i = _order.indexOf(_mode);
    final next = v < 0 ? i + 1 : i - 1;
    if (next < 0 || next >= _order.length) return;
    _setMode(_order[next]);
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2 || _switching) return;
    HapticFeedback.selectionClick();
    final dir = _cameras[_cameraIndex].lensDirection;
    final target = _indexOf(dir == CameraLensDirection.back ? CameraLensDirection.front : CameraLensDirection.back);
    if (target == null || target == _cameraIndex) return;
    if (_isRecording) return; // التبديل أثناء التسجيل غير مدعوم في camera plugin
    await _startController(target);
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _flashOn = !_flashOn;
    try {
      await c.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  // ---------- التقاط ----------
  Future<void> _takePhoto() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture || _isRecording) return;
    HapticFeedback.lightImpact();
    setState(() => _shutterFlash = true);
    Future.delayed(const Duration(milliseconds: 90), () {
      if (mounted) setState(() => _shutterFlash = false);
    });
    try {
      final XFile file = await c.takePicture();
      if (!mounted) return;
      _goToPreview(File(file.path), isVideo: false);
    } catch (e) {
      debugPrint('takePicture error: $e');
    }
  }

  Future<void> _startRecording({required bool hold}) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _isRecording || _starting || c.value.isRecordingVideo) return;
    _starting = true;
    _stopRequested = false;
    HapticFeedback.mediumImpact();
    try {
      await c.startVideoRecording();
    } catch (e) {
      debugPrint('startVideoRecording error: $e');
      _starting = false;
      return;
    }
    _starting = false;
    if (!mounted) return;
    _stopwatch
      ..reset()
      ..start();
    setState(() {
      _isRecording = true;
      _holdStyle = hold;
      _elapsed = Duration.zero;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsed = _stopwatch.elapsed);
      final max = _mode == ChatCameraMode.videoNote ? _maxNoteSeconds : _maxVideoSeconds;
      if (_elapsed.inSeconds >= max) _stopRecording();
    });
    if (_stopRequested) _stopRecording();
  }

  Future<void> _stopRecording() async {
    if (_starting) {
      _stopRequested = true;
      return;
    }
    if (!_isRecording || _stopping) return;
    _stopping = true;
    _ticker?.cancel();
    _stopwatch.stop();
    final dur = _stopwatch.elapsed;
    XFile? file;
    try {
      file = await _controller?.stopVideoRecording();
    } catch (e) {
      debugPrint('stopVideoRecording error: $e');
    }
    _stopping = false;
    if (!mounted) return;
    final wasNote = _mode == ChatCameraMode.videoNote;
    setState(() => _isRecording = false);
    if (file != null) {
      _goToPreview(File(file.path), isVideo: true, duration: dur, isNote: wasNote);
    }
  }

  void _onShutterTap() {
    switch (_mode) {
      case ChatCameraMode.photo:
        _takePhoto();
        break;
      case ChatCameraMode.video:
      case ChatCameraMode.videoNote:
        if (_isRecording) {
          _stopRecording();
        } else {
          _startRecording(hold: false);
        }
        break;
    }
  }

  void _goToPreview(File file, {required bool isVideo, Duration duration = Duration.zero, bool isNote = false}) {
    if (widget.allowMulti && !isNote) {
      Navigator.push(
        context,
        MultiMediaPreviewScreen.route(
          items: [PreviewMediaItem(file: file, isVideo: isVideo, duration: duration)],
          recipientName: widget.recipientName,
        ),
      ).then((result) {
        if (mounted && result != null) Navigator.pop(context, result);
      });
      return;
    }
    Navigator.push(
      context,
      PageRouteBuilder<dynamic>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => CaptionPreviewScreen(
          file: file,
          isVideo: isVideo,
          duration: duration,
          isVideoNote: isNote,
          recipientName: widget.recipientName,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  Future<void> _openAsset(AssetEntity asset) async {
    HapticFeedback.selectionClick();
    final File? f = await asset.originFile ?? await asset.file;
    if (f == null || !mounted) return;
    final isVideo = asset.type == AssetType.video;
    _goToPreview(f, isVideo: isVideo, duration: isVideo ? asset.videoDuration : Duration.zero);
  }

  void _toggleSelect(AssetEntity a) {
    final int idx = _selected.indexWhere((e) => e.id == a.id);
    setState(() {
      if (idx != -1) {
        HapticFeedback.selectionClick();
        _selected.removeAt(idx);
      } else if (_selected.length < MultiMediaPreviewScreen.kMaxItems) {
        HapticFeedback.selectionClick();
        _selected.add(a);
      } else {
        HapticFeedback.heavyImpact();
      }
    });
  }

  Future<void> _openSelected() async {
    if (_openingSelected || _selected.isEmpty) return;
    _openingSelected = true;
    final List<PreviewMediaItem> items = [];
    try {
      for (final AssetEntity a in _selected) {
        final File? f = await a.originFile ?? await a.file;
        if (f == null) continue;
        final bool isVideo = a.type == AssetType.video;
        items.add(PreviewMediaItem(
          file: f,
          isVideo: isVideo,
          duration: isVideo ? a.videoDuration : Duration.zero,
        ));
      }
    } catch (e) {
      debugPrint('openSelected error: $e');
    }
    _openingSelected = false;
    if (!mounted || items.isEmpty) return;
    final result = await Navigator.push(
      context,
      MultiMediaPreviewScreen.route(items: items, recipientName: widget.recipientName),
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context, result);
      return;
    }
    setState(() => _selected.clear());
  }

  Future<void> _openGallery() async {
    if (_isRecording) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MediaPickerScreen(isForChat: true)),
    );
    if (!mounted) return;
    if (result is List<String> && result.isNotEmpty) {
      if (widget.allowMulti) {
        final previewResult = await Navigator.push(
          context,
          MultiMediaPreviewScreen.route(
            items: result.map((p) => PreviewMediaItem.fromPath(p)).toList(),
            recipientName: widget.recipientName,
          ),
        );
        if (mounted && previewResult != null) Navigator.pop(context, previewResult);
        return;
      }
      Navigator.pop(context, {'paths': result});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ---------- واجهة ----------
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final double w = mq.size.width;
    final double top = mq.padding.top + _previewTopGap;
    final double avail = mq.size.height - top - 92;
    final double h = math.min(w * 16 / 9, avail);
    final double previewBottom = top + h;
    final double cy = previewBottom - 49; // مركز الزر الأبيض
    final bool note = _mode == ChatCameraMode.videoNote;
    final bool photo = _mode == ChatCameraMode.photo;
    final bool showStrip = photo && !_isRecording && _recentAssets.isNotEmpty;
    final bool hideChrome = _isRecording; // الأزرار العلوية والسفلية تختفي أثناء التسجيل

    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _permissionDenied
              ? _buildDenied()
              : Stack(
                  children: [
                    // المعاينة
                    Positioned(
                      top: top,
                      left: 0,
                      width: w,
                      height: h,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragEnd: _onSwipe,
                        child: _buildPreview(w, h, note),
                      ),
                    ),
                    // تظليل علوي وسفلي خفيف
                    Positioned(
                      top: top,
                      left: 0,
                      right: 0,
                      height: 130,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black.withOpacity(note ? 0 : 0.45), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: previewBottom - 230,
                      left: 0,
                      right: 0,
                      height: 230,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(note ? 0 : 0.4)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // فلاش الالتقاط
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _shutterFlash ? 0.75 : 0,
                          duration: const Duration(milliseconds: 90),
                          child: Container(color: Colors.white),
                        ),
                      ),
                    ),
                    _buildTopBar(top, w, hideChrome, photo),
                    // الشريط الصغير للمعرض
                    _buildStrip(w, cy, showStrip),
                    // السهم لأعلى (فيديو / ملاحظة)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: cy - 32 - 26,
                      child: IgnorePointer(
                        ignoring: photo || hideChrome,
                        child: AnimatedOpacity(
                          opacity: (photo || hideChrome) ? 0 : 1,
                          duration: const Duration(milliseconds: 150),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _openGallery,
                            child: const SizedBox(
                              height: 22,
                              child: Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _buildBottomRow(w, cy, note, hideChrome),
                    _buildShutter(w, cy, note),
                    _buildModes(w, previewBottom, hideChrome),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDenied() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('يلزم السماح باستخدام الكاميرا', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: openAppSettings,
            child: const Text('فتح الإعدادات', style: TextStyle(color: Color(0xFF21C063), fontFamily: 'Tajawal')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal')),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(double w, double h, bool note) {
    final c = _controller;
    final double circleD = w * 0.87;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: note ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final double bw = w + (circleD - w) * t;
        final double bh = h + (circleD - h) * t;
        final double r = (circleD / 2) * t;
        Widget inner;
        if (!_isInitialized || c == null || !c.value.isInitialized) {
          inner = const SizedBox();
        } else {
          final size = c.value.previewSize ?? const Size(1280, 720);
          inner = FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(width: size.height, height: size.width, child: CameraPreview(c)),
          );
        }
        final bool showArc = note && _isRecording;
        final int maxSec = _maxNoteSeconds;
        return Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(r),
              child: SizedBox(width: bw, height: bh, child: inner),
            ),
            if (showArc)
              SizedBox(
                width: circleD + 14,
                height: circleD + 14,
                child: CustomPaint(
                  painter: _ArcPainter(
                    progress: (_elapsed.inMilliseconds / (maxSec * 1000)).clamp(0.0, 1.0),
                    color: Colors.white,
                    stroke: 3.5,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _circleBtn({required Widget child, required VoidCallback onTap, double size = _topBtn}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: _btnBg, shape: BoxShape.circle),
        child: Center(child: child),
      ),
    );
  }

  Widget _buildTopBar(double top, double w, bool hide, bool photo) {
    final double y = top + 12;
    final bool showTimerPill = !photo || _isRecording;
    return Stack(
      children: [
        Positioned(
          top: y,
          left: 11,
          child: IgnorePointer(
            ignoring: hide,
            child: AnimatedOpacity(
              opacity: hide ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: _circleBtn(
                onTap: _toggleFlash,
                child: Icon(_flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
        Positioned(
          top: y,
          right: 11,
          child: IgnorePointer(
            ignoring: hide,
            child: AnimatedOpacity(
              opacity: hide ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: _circleBtn(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
        Positioned(
          top: y + 3,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: showTimerPill ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isRecording ? _red : _btnBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _fmt(_elapsed),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStrip(double w, double cy, bool show) {
    final double stripBottom = cy - 41;
    final double stripTop = stripBottom - _stripH;
    return Stack(
      children: [
        // المقبض
        Positioned(
          top: stripTop - 12,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Center(
                child: Container(
                  width: 24,
                  height: 3.5,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: stripTop,
          left: 0,
          right: 0,
          height: _stripH,
          child: IgnorePointer(
            ignoring: !show,
            child: AnimatedSlide(
              offset: show ? Offset.zero : const Offset(0, 0.25),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _recentAssets.length,
                    itemExtent: 73,
                    itemBuilder: (context, i) {
                      if (i >= _recentAssets.length - 20) _loadMoreRecent();
                      final a = _recentAssets[i];
                      final bool isVid = a.type == AssetType.video;
                      final bool picked = widget.allowMulti && _selected.any((e) => e.id == a.id);
                      return GestureDetector(
                        onTap: () {
                          if (widget.allowMulti && _selected.isNotEmpty) {
                            _toggleSelect(a);
                          } else {
                            _openAsset(a);
                          }
                        },
                        onLongPress: widget.allowMulti ? () => _toggleSelect(a) : null,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 1.5),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AssetEntityImage(
                                a,
                                isOriginal: false,
                                thumbnailSize: const ThumbnailSize.square(220),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1B1B1B)),
                              ),
                              if (isVid)
                                const Positioned(
                                  left: 5,
                                  bottom: 4,
                                  child: Icon(Icons.videocam_rounded, color: Colors.white, size: 16, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                                ),
                              if (picked) Container(color: const Color(0x66000000)),
                              if (picked) const Center(child: Icon(Icons.check_rounded, color: Colors.white, size: 28)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.allowMulti && show && _selected.isNotEmpty)
          Positioned(
            left: 14,
            top: stripTop - 18 - 46,
            child: GestureDetector(
              onTap: _openSelected,
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(color: Color(0xFF21C063), shape: BoxShape.circle),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                    Positioned(
                      left: 8,
                      bottom: 6,
                      child: Text(
                        '${_selected.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomRow(double w, double cy, bool note, bool hide) {
    final bool showFlip = !hide || (!_holdStyle && _isRecording);
    final bool showWand = !hide;
    final bool showGallery = !hide && !note;
    Widget fade(bool visible, Widget child) => IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(opacity: visible ? 1 : 0, duration: const Duration(milliseconds: 150), child: child),
        );
    return Stack(
      children: [
        Positioned(
          left: 11,
          top: cy - _sideBtn / 2,
          child: fade(
            showFlip,
            _circleBtn(
              size: _sideBtn,
              onTap: _toggleCamera,
              child: const Icon(Icons.flip_camera_android_rounded, color: Colors.white, size: 25),
            ),
          ),
        ),
        Positioned(
          left: w / 2 + 75 - _wandBtn / 2,
          top: cy - _wandBtn / 2,
          child: fade(
            showWand,
            _circleBtn(
              size: _wandBtn,
              onTap: () {},
              child: const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: cy - _sideBtn / 2,
          child: fade(
            showGallery,
            _circleBtn(
              size: _sideBtn,
              onTap: _openGallery,
              child: const Icon(Icons.photo_outlined, color: Colors.white, size: 25),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShutter(double w, double cy, bool note) {
    final bool tapStyleRec = _isRecording && !_holdStyle;
    final bool holdStyleRec = _isRecording && _holdStyle;
    final double ring = holdStyleRec ? _ringHold : (tapStyleRec ? _ringTap : _ringIdle);
    final double progress = _isRecording
        ? (_elapsed.inMilliseconds / ((note ? _maxNoteSeconds : _maxVideoSeconds) * 1000)).clamp(0.0, 1.0)
        : 0.0;
    const dur = Duration(milliseconds: 180);
    const double box = _ringHold + 6;
    return Positioned(
      left: w / 2 - box / 2,
      top: cy - box / 2,
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: AnimatedContainer(
              duration: dur,
              curve: Curves.easeOutCubic,
              width: ring,
              height: ring,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? const Color(0x991A1A1A) : Colors.transparent,
                border: Border.all(color: Colors.white, width: 3.5),
              ),
            ),
          ),
          if (_isRecording)
            IgnorePointer(
              child: AnimatedContainer(
                duration: dur,
                width: ring,
                height: ring,
                child: CustomPaint(painter: _ArcPainter(progress: math.max(progress, 0.004), color: _red, stroke: 3.5)),
              ),
            ),
          IgnorePointer(
            child: AnimatedContainer(
              duration: dur,
              curve: Curves.easeOutCubic,
              width: holdStyleRec ? 30 : (tapStyleRec ? 28 : 46),
              height: holdStyleRec ? 30 : (tapStyleRec ? 28 : 46),
              decoration: BoxDecoration(
                color: _isRecording ? _red : Colors.white,
                borderRadius: BorderRadius.circular(holdStyleRec ? 15 : (tapStyleRec ? 7 : 23)),
              ),
            ),
          ),
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onShutterTap,
              onLongPressStart: (_) {
                if (_mode == ChatCameraMode.photo) _startRecording(hold: true);
              },
              onLongPressEnd: (_) {
                if (_mode == ChatCameraMode.photo) _stopRecording();
              },
              child: const SizedBox(width: 84, height: 84),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModes(double w, double previewBottom, bool hide) {
    const items = <ChatCameraMode, String>{
      ChatCameraMode.videoNote: 'ملاحظة فيديو',
      ChatCameraMode.photo: 'صورة',
      ChatCameraMode.video: 'فيديو',
    };
    const Map<ChatCameraMode, double> widths = {
      ChatCameraMode.videoNote: 118,
      ChatCameraMode.photo: 66,
      ChatCameraMode.video: 66,
    };
    const double gap = 6;
    double start = 0;
    double selCenter = 0;
    for (final m in _order) {
      final iw = widths[m]!;
      if (m == _mode) selCenter = start + iw / 2;
      start += iw + gap;
    }
    final double tx = w / 2 - selCenter;
    return Positioned(
      left: 0,
      right: 0,
      top: previewBottom + 5,
      height: 38,
      child: IgnorePointer(
        ignoring: hide,
        child: AnimatedOpacity(
          opacity: hide ? 0 : 1,
          duration: const Duration(milliseconds: 150),
          child: ClipRect(
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  left: tx,
                  top: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final m in _order)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _setMode(m),
                          child: Padding(
                            padding: const EdgeInsets.only(right: gap),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: widths[m],
                              height: 37,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: m == _mode ? const Color(0xFF262626) : Colors.transparent,
                                borderRadius: BorderRadius.circular(19),
                              ),
                              child: Text(
                                items[m]!,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(m == _mode ? 1 : 0.88),
                                  fontSize: 14.5,
                                  fontFamily: 'Tajawal',
                                  fontWeight: m == _mode ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double stroke;
  _ArcPainter({required this.progress, required this.color, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.progress != progress || old.color != color;
}