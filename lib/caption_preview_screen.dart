import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'crop_rotate_screen.dart';
import 'media_quality.dart';
import 'media_quality_sheet.dart';
import 'photo_draw_editor.dart';
import 'photo_text_editor.dart';
import 'sticker_layer.dart';
import 'sticker_widget.dart';
import 'video_processor.dart';
import 'emoji_sticker_sheet.dart';
import 'view_once_icon.dart';

/// شاشة المعاينة بعد التصوير/اختيار ملف (تصميم واتساب).
/// ترجع عند الإرسال: {path, caption, isVideo}
class CaptionPreviewScreen extends StatefulWidget {
  final File file;
  final bool isVideo;
  final Duration duration;
  final bool isVideoNote;
  final String? recipientName;

  /// وضع الشاشة المتعددة: الشاشة تُعرض داخل MultiMediaPreviewScreen (بدون إغلاق/إرسال مستقل).
  final bool embedded;

  /// شريط المصغّرات الذي يُعرض فوق خانة الشرح التوضيحي (وضع embedded فقط).
  final Widget Function()? stripBuilder;

  /// الضغط على زر "+" لإضافة صور/فيديوهات أخرى.
  final VoidCallback? onAddMore;

  /// إرسال كل العناصر دفعة واحدة (وضع embedded فقط).
  final Future<void> Function()? onSendAll;

  /// طلب إغلاق المعاينة (وضع embedded فقط).
  final VoidCallback? onCloseRequest;

  const CaptionPreviewScreen({
    super.key,
    required this.file,
    required this.isVideo,
    required this.duration,
    this.isVideoNote = false,
    this.recipientName,
    this.embedded = false,
    this.stripBuilder,
    this.onAddMore,
    this.onSendAll,
    this.onCloseRequest,
  });

  @override
  State<CaptionPreviewScreen> createState() => CaptionPreviewScreenState();
}

class CaptionPreviewScreenState extends State<CaptionPreviewScreen> with WidgetsBindingObserver {
  static const Color _green = Color(0xFF21C063);
  static const Color _btnBg = Color(0x80333333);
  static const Color _barBg = Color(0xFF111B21);

  final TextEditingController _captionController = TextEditingController();
  final FocusNode _focus = FocusNode();
  // لوحة الإيموجي المدمجة مع الشرح التوضيحي، بنفس تعويض حركة الكيبورد في الدردشة.
  bool _showCaptionEmoji = false;
  bool _holdCaptionEmoji = false;
  double _captionEmojiHeight = 300;
  double _captionKeyboardInset = 0;
  Timer? _captionEmojiReleaseTimer;

  double _readCaptionKeyboardInset() {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final inset = _readCaptionKeyboardInset();
    if ((inset - _captionKeyboardInset).abs() < 0.5) return;
    _captionKeyboardInset = inset;
    if (!_holdCaptionEmoji && inset > 150) _captionEmojiHeight = inset;
    if (_holdCaptionEmoji) {
      if (!_showCaptionEmoji && inset >= _captionEmojiHeight - 1) {
        _holdCaptionEmoji = false;
        _captionEmojiReleaseTimer?.cancel();
      }
      setState(() {});
    }
  }

  void _releaseCaptionEmojiWhenKeyboardOpens() {
    _captionEmojiReleaseTimer?.cancel();
    _captionEmojiReleaseTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && !_showCaptionEmoji && _holdCaptionEmoji) {
        setState(() => _holdCaptionEmoji = false);
      }
    });
  }

  void _toggleCaptionEmoji() {
    if (_viewOnce) return;
    if (_showCaptionEmoji) {
      _captionEmojiReleaseTimer?.cancel();
      setState(() => _showCaptionEmoji = false);
      _releaseCaptionEmojiWhenKeyboardOpens();
      _focus.requestFocus();
    } else {
      final keyboardHeight = _readCaptionKeyboardInset();
      if (keyboardHeight > 150) {
        _captionEmojiHeight = keyboardHeight;
      } else {
        final screenHeight = MediaQuery.sizeOf(context).height;
        _captionEmojiHeight = (screenHeight * 0.46).clamp(340.0, 440.0).toDouble();
      }
      _captionEmojiReleaseTimer?.cancel();
      setState(() {
        _captionKeyboardInset = keyboardHeight;
        _holdCaptionEmoji = true;
        _showCaptionEmoji = true;
      });
      _focus.unfocus();
    }
  }

  void _insertCaptionEmoji(String emoji) {
    final old = _captionController.value;
    final selection = old.selection;
    final start = selection.isValid ? selection.start : old.text.length;
    final end = selection.isValid ? selection.end : old.text.length;
    final safeStart = start.clamp(0, old.text.length);
    final safeEnd = end.clamp(safeStart, old.text.length);
    _captionController.value = TextEditingValue(
      text: old.text.replaceRange(safeStart, safeEnd, emoji),
      selection: TextSelection.collapsed(offset: safeStart + emoji.length),
    );
  }

  VideoPlayerController? _video;
  bool _muted = false;
  bool _hd = false;
  bool _viewOnce = false; // عرض مرة واحدة (صورة/فيديو فقط)
  ui.Image? _blankImg; // صورة شفافة 1x1 لرسم الخطوط فوق الفيديو

  // ---------- القص / GIF (حقيقي) ----------
  double _trimStart = 0.0; // 0..1 من مدة الفيديو الأصلية
  double _trimEnd = 1.0;
  bool _trimDragging = false;
  bool _trimWasPlaying = false;
  bool _trimLeft = true; // أي مقبض عم ينسحب (الأقرب لمكان اللمس)
  bool _gif = false; // false = فيديو ، true = GIF
  double? _preGifEnd; // نهاية القص قبل التحويل لـ GIF (للرجوع لها)
  double? _gifClampedEnd;
  bool _busy = false;
  Timer? _posTimer;
  bool _posBusy = false;
  final ValueNotifier<Duration> _playPos = ValueNotifier<Duration>(Duration.zero);
  static const int _kGifMaxMs = 6000; // أقصى مدة GIF (مثل واتساب)
  static const int _kMinTrimMs = 1000; // أقل مدة قص
  String? _toastMsg;
  bool _toastVisible = false;
  Timer? _toastTimer;
  List<String?> _thumbs = [];
  bool _sending = false;
  bool _active = true; // false = العنصر مخفي داخل الشاشة المتعددة (يتوقف تشغيله)
  File? _editedFile; // الصورة بعد الرسم (null = الأصلية)
  List<DrawStroke> _strokes = [];
  List<TextOverlay> _texts = [];
  List<StickerLayer> _stickerLayers = [];
  File? _textFile; // الصورة بعد إضافة النص
  File? _cropFile; // الصورة بعد القص/التدوير (null = الأصلية)
  File get _baseFile => _cropFile ?? widget.file;
  File get _curFile => _editedFile ?? _baseFile;
  Size? _imgSize;
  bool _loadingSize = false;
  bool _textDragging = false;
  bool _overTrash = false;
  bool _guideV = false;
  bool _guideH = false;
  double _rawX = 0, _rawY = 0, _s0 = 1, _r0 = 0;
  int _lastPc = 1;

  static const double _kStickerBase = 80.0;
  String? _stkId;
  double _stkS0 = 1, _stkR0 = 0;
  int _stkPc = 1;

  StickerLayer? _stkTarget(Offset p, {required bool anywhere}) {
    final size = MediaQuery.of(context).size;
    StickerLayer? best;
    double bestDist = double.infinity;
    for (final s in _stickerLayers) {
      final dist = (Offset(s.x * size.width, s.y * size.height) - p).distance;
      final radius = 40 * s.scale + 70;
      if (dist <= radius && dist < bestDist) {
        bestDist = dist;
        best = s;
      }
    }
    if (best == null && anywhere && _stickerLayers.isNotEmpty) {
      for (final s in _stickerLayers) {
        if (s.isSelected) best = s;
      }
      best ??= _stickerLayers.last;
    }
    return best;
  }

  void _stkBind(StickerLayer s, int pointers) {
    _focus.unfocus();
    _stkId = s.id;
    _stkS0 = s.scale;
    _stkR0 = s.rotation;
    _stkPc = pointers;
    if (!s.isSelected) _selectStickerLayer(s.id);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(() {
      if (!mounted) return;
      if (_focus.hasFocus && _showCaptionEmoji) {
        setState(() => _showCaptionEmoji = false);
        _releaseCaptionEmojiWhenKeyboardOpens();
      } else {
        setState(() {});
      }
    });
    if (widget.isVideo) {
      final c = VideoPlayerController.file(widget.file);
      _video = c;
      c.initialize().then((_) {
        if (!mounted) return;
        c.setLooping(true);
        c.addListener(() {
          if (mounted) setState(() {});
        });
        _applyVolume();
        _startPosTimer();
        setState(() {});
        if (!widget.isVideoNote) _buildThumbs();
      });
    }
  }

  Future<void> _buildThumbs() async {
    final c = _video;
    if (c == null) return;
    final totalMs = c.value.duration.inMilliseconds;
    if (totalMs <= 0) return;
    const count = 9;
    final List<String?> out = List<String?>.filled(count, null);
    for (int i = 0; i < count; i++) {
      try {
        out[i] = await VideoThumbnail.thumbnailFile(
          video: widget.file.path,
          imageFormat: ImageFormat.JPEG,
          timeMs: (totalMs * i / count).round(),
          maxHeight: 110,
          quality: 60,
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() => _thumbs = List<String?>.from(out));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captionEmojiReleaseTimer?.cancel();
    _toastTimer?.cancel();
    _posTimer?.cancel();
    _playPos.dispose();
    _blankImg?.dispose();
    _captionController.dispose();
    _focus.dispose();
    _video?.dispose();
    super.dispose();
  }

  // ---------- مساعدات ----------
  Duration get _total {
    final c = _video;
    if (c != null && c.value.isInitialized) return c.value.duration;
    return widget.duration;
  }

  String _fmt(Duration d) => '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  bool get _effMuted => _muted || _gif;

  /// مدة المقطع بعد القص
  Duration get _trimmedTotal {
    final ms = _total.inMilliseconds;
    if (ms <= 0) return _total;
    return Duration(milliseconds: (ms * (_trimEnd - _trimStart)).round());
  }

  /// تقدير حجم الناتج: يتناسب مع المدة المقصوصة، يصغر عند كتم الصوت، ويصغر أكثر في GIF
  String _fileInfoKb() {
    final int bytes = widget.file.lengthSync();
    double est = bytes.toDouble();
    if (widget.isVideo && !widget.isVideoNote) {
      final double totalSec = _total.inMilliseconds / 1000.0;
      if (totalSec > 0) {
        final double frac = (_trimEnd - _trimStart).clamp(0.0, 1.0).toDouble();
        final double audio = math.min(16000.0 * totalSec, bytes * 0.4); // ~128kbps
        final double videoPart = bytes - audio;
        est = videoPart * frac + (_effMuted ? 0.0 : audio * frac);
        if (_gif) est *= 0.6;
      }
    }
    final kb = math.max(1, (est / 1024).round());
    return '$kb كيلوبايت';
  }

  void _applyVolume() {
    _video?.setVolume(_effMuted ? 0 : 1);
  }

  // ---------- حلقة التشغيل داخل المستطيل + مؤشر التشغيل ----------
  void _startPosTimer() {
    _posTimer?.cancel();
    _posTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      final c = _video;
      if (c == null || !mounted || !_active || _posBusy || _trimDragging) return;
      if (!c.value.isInitialized) return;
      _posBusy = true;
      try {
        final p = await c.position;
        if (p == null || !mounted) return;
        _playPos.value = p;
        final int total = c.value.duration.inMilliseconds;
        if (total <= 0) return;
        final double sMs = total * _trimStart;
        final double eMs = total * _trimEnd;
        if (c.value.isPlaying && (p.inMilliseconds >= eMs || p.inMilliseconds < sMs - 300)) {
          await c.seekTo(Duration(milliseconds: sMs.round()));
        }
      } finally {
        _posBusy = false;
      }
    });
  }

  double _clampD(double v, double lo, double hi) {
    if (hi < lo) return lo;
    return v.clamp(lo, hi).toDouble();
  }

  void _trimDragStart() {
    _focus.unfocus();
    _trimWasPlaying = _isPlaying;
    _video?.pause();
    setState(() => _trimDragging = true);
  }

  void _trimDragUpdate(bool left, double dx, double stripW) {
    final int total = _total.inMilliseconds;
    if (total <= 0 || stripW <= 0) return;
    final double minF = math.min(1.0, _kMinTrimMs / total);
    final double maxF = _gif ? math.min(1.0, _kGifMaxMs / total) : 1.0;
    double s = _trimStart;
    double e = _trimEnd;
    final double d = dx / stripW;
    if (left) {
      s = _clampD(s + d, math.max(0.0, e - maxF), e - minF);
    } else {
      e = _clampD(e + d, s + minF, math.min(1.0, s + maxF));
    }
    setState(() {
      _trimStart = s;
      _trimEnd = e;
    });
    // معاينة الإطار تحت المقبض أثناء السحب
    final double at = left ? s : math.max(s, e - 0.001);
    _video?.seekTo(Duration(milliseconds: (total * at).round()));
    _playPos.value = Duration(milliseconds: (total * at).round());
  }

  void _trimDragEnd() {
    if (!_trimDragging) return;
    final int total = _total.inMilliseconds;
    setState(() => _trimDragging = false);
    if (total > 0) {
      _video?.seekTo(Duration(milliseconds: (total * _trimStart).round()));
    }
    if (_trimWasPlaying) _video?.play();
  }

  void _setGif(bool gif) {
    if (_gif == gif || !widget.isVideo || widget.isVideoNote) return;
    setState(() {
      _gif = gif;
      if (gif) {
        _preGifEnd = _trimEnd;
        final int total = _total.inMilliseconds;
        if (total > 0) {
          final double maxF = math.min(1.0, _kGifMaxMs / total);
          if (_trimEnd - _trimStart > maxF) _trimEnd = _trimStart + maxF;
        }
        _gifClampedEnd = _trimEnd;
      } else {
        final pre = _preGifEnd;
        final cl = _gifClampedEnd;
        // نرجع لنهاية القص السابقة فقط إذا المستخدم ما غيّرها وهو بوضع GIF
        if (pre != null && cl != null && (_trimEnd - cl).abs() < 1e-9) _trimEnd = pre;
        _preGifEnd = null;
        _gifClampedEnd = null;
      }
    });
    _applyVolume();
  }

  /// الفيديو النهائي بعد (القص / الكتم / GIF). إذا ما في تعديل يرجع الملف الأصلي.
  Future<File> _videoOut() async {
    if (!widget.isVideo || widget.isVideoNote) return widget.file;
    final bool trim = _trimStart > 0.001 || _trimEnd < 0.999;
    final String? overlay = await _renderVideoOverlay();
    if (!trim && !_effMuted && !_gif && overlay == null) return widget.file;
    final int total = _total.inMilliseconds;
    final Duration s = Duration(milliseconds: (total * _trimStart).round());
    final Duration e = Duration(milliseconds: (total * _trimEnd).round());
    final String? out = await VideoProcessor.exportEditedVideo(
      inputPath: widget.file.path,
      start: s,
      end: e,
      trim: trim,
      mute: _effMuted,
      gif: _gif,
      overlayPath: overlay,
    );
    if (out == null) {
      _snack('تعذر تطبيق التعديلات على الفيديو');
      return widget.file;
    }
    return File(out);
  }

  bool get _isPlaying => _video?.value.isPlaying ?? false;

  void _togglePlay() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      final int total = c.value.duration.inMilliseconds;
      final int p = c.value.position.inMilliseconds;
      if (total > 0 && (p >= total * _trimEnd - 30 || p < total * _trimStart - 300)) {
        c.seekTo(Duration(milliseconds: (total * _trimStart).round()));
      }
      c.play();
    }
    setState(() {});
  }

  void _toggleMute() {
    if (_gif) return; // بوضع GIF الصوت مقفول (صامت)
    setState(() => _muted = !_muted);
    _applyVolume();
  }

  Future<void> _download() async {
    try {
      final name = 'titi_${DateTime.now().millisecondsSinceEpoch}';
      if (widget.isVideo) {
        setState(() => _busy = true);
        final File v = await _videoOut();
        if (mounted) setState(() => _busy = false);
        if (_gif) {
          await PhotoManager.editor.saveImageWithPath(v.path, title: '$name.gif');
        } else {
          await PhotoManager.editor.saveVideo(v, title: '$name.mp4');
        }
      } else {
        final f = await _finalFile();
        await PhotoManager.editor.saveImageWithPath(f.path, title: '$name.jpg');
      }
      _snack('تم الحفظ في المعرض');
    } catch (e) {
      if (mounted && _busy) setState(() => _busy = false);
      _snack('تعذر الحفظ');
    }
  }

  bool get _hasEdits =>
      _cropFile != null ||
      _editedFile != null ||
      _strokes.isNotEmpty ||
      _texts.isNotEmpty ||
      _stickerLayers.isNotEmpty;

  /// زر ×: إذا في تعديلات (رسم) نسأل "هل تريد تجاهل الصورة؟" مثل واتساب
  Future<void> _confirmClose() async {
    if (widget.embedded) {
      widget.onCloseRequest?.call();
      return;
    }
    if (!_hasEdits) {
      Navigator.pop(context);
      return;
    }
    _focus.unfocus();
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF111B21),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          content: const Text(
            'هل تريد تجاهل الصورة؟',
            style: TextStyle(color: Color(0xFFB0B8BD), fontFamily: 'Tajawal', fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(color: _green, fontFamily: 'Tajawal', fontSize: 15)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تجاهل', style: TextStyle(color: _green, fontFamily: 'Tajawal', fontSize: 15)),
            ),
          ],
        ),
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Future<void> _openDraw() async {
    if (widget.isVideo) {
      await _openDrawOnVideo();
      return;
    }
    _focus.unfocus();
    final result = await Navigator.push<PhotoDrawResult>(
      context,
      PageRouteBuilder<PhotoDrawResult>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => PhotoDrawEditor(file: _baseFile, initialStrokes: _strokes),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _editedFile = result.file;
      _strokes = result.strokes;
    });
  }

  // ---------- الرسم / النص / الإيموجي على الفيديو ----------
  Future<void> _ensureBlank() async {
    if (_blankImg != null) return;
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(Rect.zero, Paint());
    _blankImg = await rec.endRecording().toImage(1, 1);
  }

  /// لقطة من الفيديو عند الموضع الحالي تُستخدم كخلفية لمحرر الرسم/النص
  Future<File?> _grabFrame() async {
    final c = _video;
    if (c == null || !c.value.isInitialized) return null;
    try {
      final String? p = await VideoThumbnail.thumbnailFile(
        video: widget.file.path,
        imageFormat: ImageFormat.JPEG,
        timeMs: c.value.position.inMilliseconds,
        maxWidth: 1080,
        quality: 90,
      );
      if (p == null) return null;
      return File(p);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openDrawOnVideo() async {
    if (widget.isVideoNote) return;
    _focus.unfocus();
    final bool wasPlaying = _isPlaying;
    _video?.pause();
    final File? frame = await _grabFrame();
    if (!mounted) return;
    if (frame == null) {
      _snack('تعذر تجهيز الفيديو للرسم');
      return;
    }
    final result = await Navigator.push<PhotoDrawResult>(
      context,
      PageRouteBuilder<PhotoDrawResult>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => PhotoDrawEditor(file: frame, initialStrokes: _strokes),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      await _ensureBlank();
      if (!mounted) return;
      setState(() => _strokes = result.strokes);
    }
    if (wasPlaying) _video?.play();
  }

  Future<void> _openTextOnVideo() async {
    if (widget.isVideoNote) return;
    _focus.unfocus();
    final bool wasPlaying = _isPlaying;
    _video?.pause();
    final File? frame = await _grabFrame();
    if (!mounted) return;
    if (frame == null) {
      _snack('تعذر تجهيز الفيديو للكتابة');
      return;
    }
    final r = await Navigator.push<TextOverlay>(
      context,
      PageRouteBuilder<TextOverlay>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => PhotoTextEditor(file: frame),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
    if (!mounted) return;
    if (r != null) {
      final k = _texts.length;
      r.dy = 0.5 + (k == 0 ? 0.0 : (k.isOdd ? 1 : -1) * 0.12 * ((k + 1) ~/ 2));
      setState(() => _texts = [..._texts, r]);
    }
    if (wasPlaying) _video?.play();
  }

  /// طبقة الخطوط المرسومة فوق الفيديو أثناء المعاينة
  List<Widget> _buildVideoStrokeLayer() {
    if (!widget.isVideo || widget.isVideoNote || _strokes.isEmpty) return [];
    final vs = _video?.value.size;
    final blank = _blankImg;
    if (vs == null || vs.width <= 0 || vs.height <= 0 || blank == null) return [];
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (ctx, c) {
              final double k = math.min(c.maxWidth / vs.width, c.maxHeight / vs.height);
              final Rect rect = Rect.fromLTWH(
                (c.maxWidth - vs.width * k) / 2,
                (c.maxHeight - vs.height * k) / 2,
                vs.width * k,
                vs.height * k,
              );
              return CustomPaint(size: Size.infinite, painter: _VideoStrokePainter(rect, blank, _strokes));
            },
          ),
        ),
      ),
    ];
  }

  /// يرسم (الخطوط + النصوص + الإيموجي) على PNG شفاف بحجم الفيديو لتثبيته عند التصدير.
  /// ملاحظة: أداة التمويه (البكسلة) لا تُطبَّق على الفيديو لأنها تحتاج صورة ثابتة تحتها.
  Future<String?> _renderVideoOverlay() async {
    final vs = _video?.value.size;
    if (vs == null || vs.width <= 0 || vs.height <= 0) return null;
    final strokes = _strokes.where((s) => s.tool != DrawTool.pixelate && s.points.isNotEmpty).toList();
    final emojis = _stickerLayers.where((s) => s.isEmoji).toList();
    if (strokes.isEmpty && _texts.isEmpty && emojis.isEmpty) return null;
    try {
      await _ensureBlank();
      final int ow = vs.width.round();
      final int oh = vs.height.round();
      final Size sz = Size(ow.toDouble(), oh.toDouble());
      final Size screen = MediaQuery.of(context).size;
      final double k = math.min(screen.width / sz.width, screen.height / sz.height);
      final double left = (screen.width - sz.width * k) / 2;
      final double top = (screen.height - sz.height * k) / 2;

      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      if (strokes.isNotEmpty) {
        paintDrawScene(canvas, Offset.zero & sz, _blankImg!, null, strokes);
      }
      for (final t in _texts) {
        paintTextOverlay(canvas, sz, t);
      }
      for (final s in emojis) {
        final double cx = (s.x * screen.width - left) / k;
        final double cy = (s.y * screen.height - top) / k;
        final tp = TextPainter(
          text: TextSpan(text: s.path, style: TextStyle(fontSize: _kStickerBase * s.scale / k)),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(s.rotation);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      }
      final img = await rec.endRecording().toImage(ow, oh);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (data == null) return null;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/vid_overlay_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(data.buffer.asUint8List());
      return f.path;
    } catch (e) {
      debugPrint('video overlay render error: $e');
      return null;
    }
  }

  Future<void> _rebuildText() async {
    if (_texts.isEmpty) {
      if (mounted) setState(() => _textFile = null);
      return;
    }
    final out = await renderTextsOnto(_editedFile ?? _baseFile, _texts);
    if (!mounted) return;
    setState(() => _textFile = out);
  }

  Future<void> _openText() async {
    if (widget.isVideo) {
      await _openTextOnVideo();
      return;
    }
    _focus.unfocus();
    final r = await Navigator.push<TextOverlay>(
      context,
      PageRouteBuilder<TextOverlay>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => PhotoTextEditor(file: _editedFile ?? _baseFile),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
    if (r == null || !mounted) return;
    final k = _texts.length;
    r.dy = 0.5 + (k == 0 ? 0.0 : (k.isOdd ? 1 : -1) * 0.12 * ((k + 1) ~/ 2));
    setState(() => _texts = [..._texts, r]);
  }

  /// زر HD: نافذة "جودة الوسائط" ثم رسالة تأكيد (مثل واتساب)
  Future<void> _openQuality() async {
    _focus.unfocus();
    final bool? hd = await showMediaQualitySheet(context, isHd: _hd);
    if (hd == null || !mounted) return;
    setState(() => _hd = hd);
    final bool v = widget.isVideo;
    _showToast(hd
        ? (v ? 'تم ضبط 1 فيديو واحد على الجودة عالية الدقة' : 'تم ضبط 1 صورة واحدة على الجودة عالية الدقة')
        : (v ? 'تم ضبط الفيديو على الجودة الافتراضية' : 'تم ضبط الصورة على الجودة الافتراضية'));
  }

  void _toggleViewOnce() {
    HapticFeedback.selectionClick();
    _focus.unfocus();
    final bool v = widget.isVideo && !_gif;
    setState(() => _viewOnce = !_viewOnce);
    _showToast(_viewOnce
        ? (v ? 'تم ضبط الفيديو للعرض مرة واحدة' : 'تم ضبط الصورة للعرض مرة واحدة')
        : (v ? 'تم إيقاف العرض مرة واحدة للفيديو' : 'تم إيقاف العرض مرة واحدة للصورة'));
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() {
      _toastMsg = msg;
      _toastVisible = true;
    });
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastVisible = false);
    });
  }

  /// تطبيق الجودة المختارة على الملف النهائي قبل الإرسال.
  /// عالية الدقة: الملف كما هو (والرفع/الضغط يقرآن العلامة من MediaQuality).
  /// قياسية: تصغير الصورة (حد أقصى 1600) وضغطها JPEG.
  Future<File> _applyQuality(File f) async {
    MediaQuality.setHd(f.path, _hd);
    if (widget.isVideo || _hd) return f;
    try {
      final dir = await getTemporaryDirectory();
      final out = '${dir.path}/std_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final x = await FlutterImageCompress.compressAndGetFile(
        f.path,
        out,
        minWidth: 1600,
        minHeight: 1600,
        quality: 75,
        format: CompressFormat.jpeg,
      );
      if (x != null) return File(x.path);
    } catch (_) {}
    return f;
  }

  /// زر القص/التدوير: يفتح شاشة القص ويرجع الصورة الجديدة (أو null عند الإلغاء)
  Future<void> _openCrop() async {
    if (widget.isVideo) return;
    _focus.unfocus();
    final File? result = await Navigator.push<File?>(context, CropRotateScreen.route(_curFile));
    if (result == null || !mounted) return;
    setState(() {
      // الرسم القديم صار جزءاً من الصورة المقصوصة
      _cropFile = result;
      _editedFile = null;
      _strokes = [];
      _textFile = null;
      _imgSize = null;
      _loadingSize = false;
    });
  }

    Future<void> _openEmojiSticker() async {
    _focus.unfocus();
    final StickerLayer? layer = await showModalBottomSheet<StickerLayer>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      builder: (_) => const EmojiStickerSheet(),
    );
    if (layer == null || !mounted) return;
    setState(() {
      for (final s in _stickerLayers) {
        s.isSelected = false;
      }
      _stickerLayers.add(layer.copyWith(x: 0.5, y: 0.45, isSelected: true));
    });
  }

  void _updateStickerLayer(StickerLayer updated) {
    final i = _stickerLayers.indexWhere((s) => s.id == updated.id);
    if (i != -1) setState(() => _stickerLayers[i] = updated);
  }

  void _deleteStickerLayer(String id) {
    setState(() => _stickerLayers.removeWhere((s) => s.id == id));
  }

  void _selectStickerLayer(String id) {
    setState(() {
      for (final s in _stickerLayers) {
        s.isSelected = s.id == id;
      }
    });
  }

  Future<File> _finalFile() async {
    if (widget.isVideo) return _videoOut();
    File f = _curFile;
    if (_texts.isNotEmpty) {
      f = await renderTextsOnto(f, _texts) ?? f;
    }
    if (_stickerLayers.isNotEmpty) {
      f = await _renderStickersOnto(f);
    }
    return f;
  }

  Future<File> _renderStickersOnto(File base) async {
    final screen = MediaQuery.of(context).size;
    final layers = List<StickerLayer>.from(_stickerLayers);
    try {
      final codec = await ui.instantiateImageCodec(await base.readAsBytes());
      final img = (await codec.getNextFrame()).image;
      final iw = img.width.toDouble();
      final ih = img.height.toDouble();

      final k = math.min(screen.width / iw, screen.height / ih);
      final left = (screen.width - iw * k) / 2;
      final top = (screen.height - ih * k) / 2;

      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawImage(img, Offset.zero, Paint());

      for (final s in layers) {
        if (!s.isEmoji) continue;
        final cx = (s.x * screen.width - left) / k;
        final cy = (s.y * screen.height - top) / k;
        final tp = TextPainter(
          text: TextSpan(
            text: s.path,
            style: TextStyle(fontSize: _kStickerBase * s.scale / k),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(s.rotation);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      }

      final out = await rec.endRecording().toImage(img.width, img.height);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      out.dispose();
      if (data == null) return base;
      final f = File('${Directory.systemTemp.path}/stk_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(data.buffer.asUint8List());
      return f;
    } catch (_) {
      return base;
    }
  }

  Future<void> _loadImgSize() async {
    if (_loadingSize) return;
    _loadingSize = true;
    try {
      final bytes = await _curFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final fr = await codec.getNextFrame();
      final s = Size(fr.image.width.toDouble(), fr.image.height.toDouble());
      fr.image.dispose();
      if (mounted) setState(() => _imgSize = s);
    } catch (_) {
      _loadingSize = false;
    }
  }

  Rect _imgRectIn(Size area) {
    final s = _imgSize!;
    final k = math.min(area.width / s.width, area.height / s.height);
    final w = s.width * k;
    final h = s.height * k;
    return Rect.fromLTWH((area.width - w) / 2, (area.height - h) / 2, w, h);
  }

  Widget _buildTrashBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: [
          const Spacer(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: _overTrash ? 46 : 39,
            height: _overTrash ? 46 : 39,
            decoration: BoxDecoration(color: _overTrash ? const Color(0xFFE53935) : _btnBg, shape: BoxShape.circle),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 23),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTextLayer() {
    if (_texts.isEmpty) return [];
    if (widget.isVideo) {
      final vs = _video?.value.size;
      if (vs == null || vs.width <= 0 || vs.height <= 0) return [];
      _imgSize = vs;
    } else if (_imgSize == null) {
      _loadImgSize();
      return [];
    }
    return [
      Positioned.fill(
        child: LayoutBuilder(
          builder: (ctx, c) {
            final rect = _imgRectIn(Size(c.maxWidth, c.maxHeight));
            final mq = MediaQuery.of(ctx);
            final trash = Rect.fromLTWH(mq.size.width - 70, mq.padding.top - 4, 70, 70);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _TextLayerPainter(rect, _texts))),
                if (_guideV)
                  Positioned(left: rect.center.dx - 0.75, top: 0, bottom: 0, width: 1.5, child: const IgnorePointer(child: ColoredBox(color: _green))),
                if (_guideH)
                  Positioned(top: rect.center.dy - 0.75, left: 0, right: 0, height: 1.5, child: const IgnorePointer(child: ColoredBox(color: _green))),
                for (final t in _texts) _textHit(t, rect, trash),
              ],
            );
          },
        ),
      ),
    ];
  }

  Widget _textHit(TextOverlay t, Rect rect, Rect trash) {
    final box = textOverlayBox(rect.size, t);
    const double pad = 22;
    return Positioned(
      key: ObjectKey(t),
      left: rect.left + t.dx * rect.width - (box.width / 2 + pad),
      top: rect.top + t.dy * rect.height - (box.height / 2 + pad),
      width: box.width + pad * 2,
      height: box.height + pad * 2,
      child: Transform.rotate(
        angle: t.rotation,
        child: Transform.scale(
          scale: t.scale,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (d) {
              _rawX = t.dx;
              _rawY = t.dy;
              _s0 = t.scale;
              _r0 = t.rotation;
              _lastPc = d.pointerCount;
              _focus.unfocus();
              setState(() => _textDragging = true);
            },
            onScaleUpdate: (d) {
              if (d.pointerCount != _lastPc) {
                _lastPc = d.pointerCount;
                _s0 = t.scale;
                _r0 = t.rotation;
              }
              _rawX = (_rawX + d.focalPointDelta.dx / rect.width).clamp(0.0, 1.0);
              _rawY = (_rawY + d.focalPointDelta.dy / rect.height).clamp(0.0, 1.0);
              double nx = _rawX;
              double ny = _rawY;
              final bool gv = (nx - 0.5).abs() * rect.width < 7;
              final bool gh = (ny - 0.5).abs() * rect.height < 7;
              if (gv) nx = 0.5;
              if (gh) ny = 0.5;
              if ((gv && !_guideV) || (gh && !_guideH)) HapticFeedback.selectionClick();
              t.dx = nx;
              t.dy = ny;
              if (d.pointerCount >= 2) {
                t.scale = (_s0 * d.scale).clamp(0.4, 6.0);
                t.rotation = _r0 + d.rotation;
              }
              setState(() {
                _guideV = gv;
                _guideH = gh;
                _overTrash = trash.contains(d.focalPoint);
              });
            },
            onScaleEnd: (_) {
              final bool del = _overTrash;
              setState(() {
                _textDragging = false;
                _guideV = false;
                _guideH = false;
                _overTrash = false;
                if (del) _texts = _texts.where((e) => !identical(e, t)).toList();
              });
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal'))));
  }

  // ---------- واجهة للشاشة المتعددة (embedded) ----------
  bool get hasEdits => _hasEdits;

  /// الملف الذي يُعرض كمصغّر (الصورة بعد التعديل/القص، أو الفيديو الأصلي)
  File get previewFile => widget.isVideo ? widget.file : _curFile;

  /// تفعيل/إيقاف العنصر عند التنقل بين العناصر (الإيقاف يوقف الفيديو ويخفي الكيبورد)
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (!active) {
      _focus.unfocus();
      _video?.pause();
    }
    if (mounted) setState(() {});
  }

  /// يجهّز نتيجة هذا العنصر (نفس ما يرجعه _send) بدون إغلاق الشاشة.
  Future<Map<String, dynamic>?> buildResult() async {
    if (widget.isVideo && !widget.isVideoNote && mounted) setState(() => _busy = true);
    File sendFile = await _finalFile();
    sendFile = await _applyQuality(sendFile);
    if (!mounted) return null;
    if (_busy) setState(() => _busy = false);
    return <String, dynamic>{
      'path': sendFile.path,
      'caption': (widget.isVideoNote || _viewOnce) ? '' : _captionController.text.trim(),
      'isVideo': widget.isVideo && !_gif,
      'isVideoNote': widget.isVideoNote,
      'viewOnce': _viewOnce && !widget.isVideoNote,
    };
  }

  Future<void> _send() async {
    if (widget.embedded) {
      final cb = widget.onSendAll;
      if (cb != null) await cb();
      return;
    }
    if (_sending) return;
    _sending = true;
    final nav = Navigator.of(context);
    if (widget.isVideo && !widget.isVideoNote && mounted) setState(() => _busy = true);
    File sendFile = await _finalFile();
    sendFile = await _applyQuality(sendFile);
    if (!mounted) return;
    final result = <String, dynamic>{
      'path': sendFile.path,
      'caption': (widget.isVideoNote || _viewOnce) ? '' : _captionController.text.trim(),
      'isVideo': widget.isVideo && !_gif,
      'isVideoNote': widget.isVideoNote,
      'viewOnce': _viewOnce && !widget.isVideoNote,
    };
    nav.pop(); // المعاينة
    nav.pop(result); // الكاميرا
  }

  // ---------- واجهة ----------
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final double w = mq.size.width;
    final double topPad = mq.padding.top;
    final bool keyboardOpen = mq.viewInsets.bottom > 0;
    final bool note = widget.isVideoNote;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: PopScope(
        canPop: widget.embedded ? true : !_hasEdits,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !widget.embedded) _confirmClose();
        },
        child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_focus.hasFocus) {
                    _focus.unfocus();
                  } else if (widget.isVideo) {
                    _togglePlay();
                  }
                },
                child: note ? _buildNoteMedia(w) : _buildMedia(),
              ),
            ),
            ..._buildVideoStrokeLayer(),
            if (_stickerLayers.isNotEmpty)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onScaleStart: (d) {
                    _stkId = null;
                    final t = _stkTarget(d.focalPoint, anywhere: d.pointerCount >= 2);
                    if (t != null) _stkBind(t, d.pointerCount);
                  },
                  onScaleUpdate: (d) {
                    final id = _stkId;
                    if (id == null) return;
                    final i = _stickerLayers.indexWhere((s) => s.id == id);
                    if (i == -1) return;
                    final s = _stickerLayers[i];
                    final size = MediaQuery.of(context).size;
                    if (d.pointerCount != _stkPc) {
                      _stkPc = d.pointerCount;
                      _stkS0 = s.scale;
                      _stkR0 = s.rotation;
                    }
                    var updated = s.copyWith(
                      x: (s.x + d.focalPointDelta.dx / size.width).clamp(0.0, 1.0),
                      y: (s.y + d.focalPointDelta.dy / size.height).clamp(0.0, 1.0),
                    );
                    if (d.pointerCount >= 2) {
                      updated = updated.copyWith(
                        scale: (_stkS0 * d.scale).clamp(0.3, 10.0),
                        rotation: _stkR0 + d.rotation,
                      );
                    }
                    _updateStickerLayer(updated);
                  },
                  onScaleEnd: (_) => _stkId = null,
                ),
              ),
            ..._buildTextLayer(),
            if (_stickerLayers.isNotEmpty)
              ..._stickerLayers.map((sticker) {
                return StickerWidget(
                  key: ValueKey(sticker.id),
                  sticker: sticker,
                  screenSize: MediaQuery.of(context).size,
                  onUpdate: _updateStickerLayer,
                  onDelete: _deleteStickerLayer,
                  onTap: _selectStickerLayer,
                );
              }),
            // الأزرار العلوية
            Positioned(
              top: topPad + 11,
              left: 0,
              right: 0,
              child: _textDragging ? _buildTrashBar() : (_trimDragging ? _buildTrimBubble() : (note ? _buildNoteTopBar() : _buildTopBar())),
            ),
            if (widget.isVideo && !note) ..._buildVideoExtras(topPad, w),
            // رسالة تأكيد الجودة (تظهر وسط الشاشة ثم تختفي)
            Positioned(
              left: 0,
              right: 0,
              top: mq.size.height * 0.483,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _toastVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
                      decoration: BoxDecoration(color: const Color(0xF2D6D3D2), borderRadius: BorderRadius.circular(28)),
                      child: Text(
                        _toastMsg ?? '',
                        style: const TextStyle(color: Color(0xFF1C1B1B), fontFamily: 'Tajawal', fontSize: 14.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // زر التشغيل
            if (widget.isVideo)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _isPlaying ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(color: Color(0x73000000), shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                      ),
                    ),
                  ),
                ),
              ),
            if (_busy)
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(
                    color: Colors.black54,
                    child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                  ),
                ),
              ),
            // الشريط السفلي
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 8, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!widget.isVideo && !keyboardOpen) _buildAiPill(),
                      if (widget.stripBuilder != null) widget.stripBuilder!(),
                      if (!note) _buildCaptionBar(),
                      const SizedBox(height: 14),
                      _buildSendRow(),
                      if (_holdCaptionEmoji)
                        SizedBox(
                          height: (_captionEmojiHeight - _captionKeyboardInset)
                              .clamp(0.0, _captionEmojiHeight).toDouble(),
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: _captionEmojiHeight,
                              maxHeight: _captionEmojiHeight,
                              child: EmojiStickerSheet(
                                inline: true,
                                inlineHeight: _captionEmojiHeight,
                                onEmojiSelected: _insertCaptionEmoji,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildMedia() {
    if (widget.isVideo) {
      final c = _video;
      if (c == null || !c.value.isInitialized) {
        return const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2));
      }
      return Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)));
    }
    return InteractiveViewer(
      child: Center(child: Image.file(_curFile, key: ValueKey(_curFile.path), fit: BoxFit.contain)),
    );
  }

  Widget _buildNoteMedia(double w) {
    final c = _video;
    final double d = w * 0.87;
    final double progress = (c != null && c.value.isInitialized && c.value.duration.inMilliseconds > 0)
        ? (c.value.position.inMilliseconds / c.value.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: SizedBox(
          width: d + 14,
          height: d + 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipOval(
                child: SizedBox(
                  width: d,
                  height: d,
                  child: (c != null && c.value.isInitialized)
                      ? FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: c.value.size.width,
                            height: c.value.size.height,
                            child: VideoPlayer(c),
                          ),
                        )
                      : const SizedBox(),
                ),
              ),
              SizedBox(
                width: d + 14,
                height: d + 14,
                child: CustomPaint(painter: _PreviewArcPainter(progress: progress)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleBtn(Widget child, VoidCallback onTap, {double size = 39}) {
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

  Widget _hdIcon() {
    final Widget box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: _hd ? Colors.white : Colors.transparent,
        border: Border.all(color: Colors.white, width: 1.8),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text('HD', style: TextStyle(color: _hd ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.w800, height: 1.1)),
    );
    if (!_hd) return box;
    // عالية الدقة: علامة صح صغيرة على الزاوية السفلية اليمنى
    return Stack(
      clipBehavior: Clip.none,
      children: [
        box,
        Positioned(
          right: -5,
          bottom: -5,
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(color: Color(0xFF2B2F31), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: [
          _circleBtn(const Icon(Icons.edit_outlined, color: Colors.white, size: 21), _openDraw),
          const SizedBox(width: 6),
          _circleBtn(const Text('Aa', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)), _openText),
          const SizedBox(width: 6),
          _circleBtn(const Icon(Icons.emoji_emotions_outlined, color: Colors.white, size: 22), _openEmojiSticker),
          if (!widget.isVideo) ...[
            const SizedBox(width: 6),
            _circleBtn(const Icon(Icons.crop_rotate_rounded, color: Colors.white, size: 22), _openCrop),
          ],
          const SizedBox(width: 6),
          _circleBtn(_hdIcon(), _openQuality),
          const SizedBox(width: 6),
          _circleBtn(const Icon(Icons.file_download_outlined, color: Colors.white, size: 23), _download),
          const Spacer(),
          _circleBtn(const Icon(Icons.close_rounded, color: Colors.white, size: 23), _confirmClose),
        ],
      ),
    );
  }

  Widget _buildNoteTopBar() {
    final c = _video;
    final Duration shown = (c != null && c.value.isInitialized && _isPlaying) ? c.value.position : _total;
    return SizedBox(
      height: 39,
      child: Stack(
        children: [
          Center(
            child: Text(_fmt(shown), style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          Positioned(
            right: 11,
            child: _circleBtn(const Icon(Icons.close_rounded, color: Colors.white, size: 23), () => Navigator.pop(context)),
          ),
        ],
      ),
    );
  }

  /// فقاعة الوقت أثناء سحب مقبض القص (تحل مكان الأزرار العلوية مثل واتساب)
  Widget _buildTrimBubble() {
    final int total = _total.inMilliseconds;
    final Duration s = Duration(milliseconds: (total * _trimStart).round());
    final Duration e = Duration(milliseconds: (total * _trimEnd).round());
    return SizedBox(
      height: 39,
      child: Center(
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0x99333333), borderRadius: BorderRadius.circular(15)),
          child: Text('${_fmt(e)} - ${_fmt(s)}', style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
      ),
    );
  }

  Widget _trimHit(double stripW, double sx, double ex) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) {
        final double x = d.localPosition.dx;
        _trimLeft = (x - sx).abs() <= (x - ex).abs();
        _trimDragStart();
      },
      onHorizontalDragUpdate: (d) => _trimDragUpdate(_trimLeft, d.delta.dx, stripW),
      onHorizontalDragEnd: (_) => _trimDragEnd(),
      onHorizontalDragCancel: _trimDragEnd,
      child: const SizedBox.expand(),
    );
  }

  Widget _modeSeg({required Widget child, required bool active, required double width, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: width,
        height: 24,
        alignment: Alignment.center,
        color: active ? _green : Colors.transparent,
        child: child,
      ),
    );
  }

  List<Widget> _buildVideoExtras(double topPad, double w) {
    final double stripTop = topPad + 11 + 39 + 14;
    final double pillTop = stripTop + 37 + 8;
    const double x0 = 14; // بداية شريط الإطارات من اليسار
    const double pad = 8; // مساحة إضافية فوق/تحت لمنطقة اللمس
    final double sw = w - 14 - 16; // عرض شريط الإطارات
    final double sx = x0 + _trimStart * sw;
    final double ex = x0 + _trimEnd * sw;
    const Color dim = Color(0x99000000);
    return [
      // شريط الإطارات (القص) - مستطيل قابل للسحب فعلياً
      Positioned(
        top: stripTop - pad,
        left: 0,
        right: 0,
        height: 37 + pad * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: x0,
              width: sw,
              top: pad,
              height: 37,
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    children: [
                      for (int i = 0; i < 9; i++)
                        Expanded(
                          child: (i < _thumbs.length && _thumbs[i] != null)
                              ? Image.file(File(_thumbs[i]!), fit: BoxFit.cover, height: 37)
                              : Container(color: const Color(0xFF1B1B1B)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // تعتيم خارج المستطيل (الجزء المقصوص)
            Positioned(left: x0, width: math.max(0.0, sx - x0), top: pad, height: 37, child: const IgnorePointer(child: ColoredBox(color: dim))),
            Positioned(left: ex, width: math.max(0.0, x0 + sw - ex), top: pad, height: 37, child: const IgnorePointer(child: ColoredBox(color: dim))),
            // إطار المستطيل
            Positioned(
              left: sx,
              width: math.max(0.0, ex - sx),
              top: pad,
              height: 37,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2.2), borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
            // مؤشر التشغيل داخل المستطيل
            ValueListenableBuilder<Duration>(
              valueListenable: _playPos,
              builder: (_, pos, __) {
                final int total = _total.inMilliseconds;
                if (total <= 0 || _trimDragging) return const SizedBox.shrink();
                final double f = (pos.inMilliseconds / total).clamp(_trimStart, _trimEnd).toDouble();
                return Positioned(
                  left: x0 + f * sw - 1.25,
                  top: pad - 2,
                  height: 41,
                  width: 2.5,
                  child: const IgnorePointer(
                    child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(1.5)))),
                  ),
                );
              },
            ),
            Positioned(left: sx - 5.5, top: pad + 37 / 2 - 5.5, child: IgnorePointer(child: _handleDot())),
            Positioned(left: ex - 5.5, top: pad + 37 / 2 - 5.5, child: IgnorePointer(child: _handleDot())),
            // مناطق اللمس للمقبضين
            Positioned(left: 0, right: 0, top: 0, height: 37 + pad * 2, child: _trimHit(sw, sx, ex)),
          ],
        ),
      ),
      // معلومات الملف + الصوت
      Positioned(
        top: pillTop,
        left: 14,
        right: 15,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: const Color(0x99505050), borderRadius: BorderRadius.circular(13)),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_fileInfoKb(), style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Tajawal')),
                  const SizedBox(width: 6),
                  const Text('•', style: TextStyle(color: Colors.white, fontSize: 12)),
                  const SizedBox(width: 6),
                  Text(_fmt(_trimmedTotal), style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Opacity(
              opacity: _gif ? 0.45 : 1.0,
              child: _circleBtn(
                Icon(_effMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white, size: 19),
                _toggleMute,
                size: 33,
              ),
            ),
          ],
        ),
      ),
      // مفتاح فيديو / GIF
      Positioned(
        top: pillTop + 26 + 8,
        left: 15,
        child: Container(
          height: 24,
          decoration: BoxDecoration(color: const Color(0x99505050), borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modeSeg(
                width: 36,
                active: !_gif,
                onTap: () => _setGif(false),
                child: Icon(Icons.videocam_rounded, color: _gif ? Colors.white70 : Colors.white, size: 17),
              ),
              _modeSeg(
                width: 34,
                active: _gif,
                onTap: () => _setGif(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(border: Border.all(color: _gif ? Colors.white : Colors.white70, width: 1.2), borderRadius: BorderRadius.circular(3)),
                  child: Text('GIF', style: TextStyle(color: _gif ? Colors.white : Colors.white70, fontSize: 7, fontWeight: FontWeight.w800, height: 1.2)),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _handleDot() {
    return Container(
      width: 11,
      height: 11,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    );
  }

  Widget _buildAiPill() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 22),
          GestureDetector(
            onTap: () => _snack('قريباً'),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: const Color(0xB31F1F1F), borderRadius: BorderRadius.circular(15)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 13),
                  SizedBox(width: 6),
                  Text('تجديد الشكل بالذكاء الاصطناعي', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Tajawal')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptionBar() {
    final bool focused = _focus.hasFocus || _showCaptionEmoji;
    return Container(
      constraints: const BoxConstraints(minHeight: 45),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: _barBg.withOpacity(0.92), borderRadius: BorderRadius.circular(26)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleViewOnce,
            child: SizedBox(
              width: 36,
              height: 45,
              child: Center(child: ViewOnceIcon(size: 24, filled: _viewOnce)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: TextField(
                controller: _captionController,
                focusNode: _focus,
                enabled: !_viewOnce,
                minLines: 1,
                maxLines: 5,
                cursorColor: _green,
                style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15.5),
                decoration: const InputDecoration(
                  hintText: 'إضافة شرح توضيحي...',
                  hintStyle: TextStyle(color: Color(0xCCFFFFFF), fontFamily: 'Tajawal', fontSize: 15.5),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _viewOnce
                ? null
                : focused
                    ? _toggleCaptionEmoji
                    : widget.onAddMore,
            child: Icon(
              focused ? (_showCaptionEmoji ? Icons.keyboard_outlined : Icons.emoji_emotions_outlined) : Icons.add_photo_alternate_outlined,
              color: _viewOnce ? Colors.white30 : Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendRow() {
    final name = widget.recipientName;
    return Row(
      children: [
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
            child: Center(
              child: Transform.flip(
                flipX: true,
                child: const Icon(Icons.send_rounded, color: Colors.black, size: 23),
              ),
            ),
          ),
        ),
        const Spacer(),
        if (name != null && name.trim().isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxWidth: 190),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: const Color(0xFF1F2428), borderRadius: BorderRadius.circular(15)),
            alignment: Alignment.center,
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontFamily: 'Tajawal')),
          ),
        if (widget.onAddMore != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onAddMore,
            child: Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(color: Color(0xFF1F2428), shape: BoxShape.circle),
              child: const Center(
                child: Icon(Icons.add_rounded, color: Colors.white, size: 27),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TextLayerPainter extends CustomPainter {
  final Rect rect;
  final List<TextOverlay> texts;
  _TextLayerPainter(this.rect, this.texts);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.left, rect.top);
    for (final t in texts) {
      paintTextOverlay(canvas, rect.size, t);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TextLayerPainter old) => true;
}

class _VideoStrokePainter extends CustomPainter {
  final Rect rect;
  final ui.Image blank;
  final List<DrawStroke> strokes;
  _VideoStrokePainter(this.rect, this.blank, this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    paintDrawScene(canvas, rect, blank, null, strokes);
  }

  @override
  bool shouldRepaint(covariant _VideoStrokePainter old) => true;
}

class _PreviewArcPainter extends CustomPainter {
  final double progress;
  const _PreviewArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 3.5;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(covariant _PreviewArcPainter old) => old.progress != progress;
}

/// أيقونة "عرض مرة واحدة": دائرة منقّطة بداخلها 1
class _ViewOncePainter extends CustomPainter {
  const _ViewOncePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    const int dashes = 9;
    const double sweep = 2 * math.pi / dashes;
    for (int i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
    final tp = TextPainter(
      text: const TextSpan(text: '1', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _ViewOncePainter old) => false;
}

class ExpandableCaption extends StatefulWidget {
  final String text;
  const ExpandableCaption({super.key, required this.text});

  @override
  State<ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<ExpandableCaption> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final bool isLong = widget.text.length > 80;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.text, maxLines: expanded ? null : 3, overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 14, height: 1.4)),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => expanded = !expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(expanded ? ' عرض أقل' : ' المزيد', style: const TextStyle(color: Color(0xFF53BDEB), fontFamily: 'Tajawal', fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}