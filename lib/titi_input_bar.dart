import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'chat_camera_screen.dart';
import 'tini_attachment_sheet.dart';
import 'emoji_sticker_sheet.dart';

class TitiInputBar extends StatefulWidget {
  final TextEditingController? textController;
  final Function(String text) onSendText;
  final Function(String path, Duration duration, List<int> waveform) onSendVoice;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickFile;
  final VoidCallback? onPickEmoji;
  final VoidCallback? onPickLocation;
  final VoidCallback? onPickDocument;
  final Function(String path, String caption, bool isVideo)? onSendMedia;
  final Future<void> Function(List<Map<String, dynamic>> items) onSendMediaAlbum;
  /// اختياري: يُستدعى عند إرسال "ملاحظة فيديو" (دائرية). إن لم يُمرَّر يبقى السلوك القديم.
  final Function(String path)? onSendVideoNote;
  /// اختياري: يُستدعى عند إرسال صورة/فيديو "للعرض مرة واحدة" من الكاميرا.
  final Function(String path, bool isVideo)? onSendViewOnce;
  /// اسم الجروب/الشخص الذي يظهر بجانب زر الإرسال في شاشة معاينة الكاميرا
  final String? cameraRecipientName;
  /// اختياري: true = (المجموعات) السماح باختيار عدة صور/فيديوهات (حد أقصى 5) في رسالة واحدة من الكاميرا.
  final bool allowMultiMedia;

  const TitiInputBar({
    super.key,
    this.textController,
    required this.onSendText,
    required this.onSendVoice,
    this.onPickCamera,
    this.onPickFile,
    this.onPickEmoji,
    this.onPickLocation,
    this.onPickDocument,
    this.onSendMedia,
    required this.onSendMediaAlbum,
    this.onSendVideoNote,
    this.onSendViewOnce,
    this.cameraRecipientName,
    this.allowMultiMedia = false,
  });

  @override
  State<TitiInputBar> createState() => _TitiInputBarState();
}

class _TitiInputBarState extends State<TitiInputBar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static bool _looksLikeVideo(String path) {
    final l = path.toLowerCase();
    return l.endsWith('.mp4') || l.endsWith('.mov') || l.endsWith('.avi') || l.endsWith('.mkv') || l.endsWith('.3gp') || l.endsWith('.webm');
  }

  // ---- colors ----
  static const _inputBg = Color(0xFF202C33);
  static const _panelBg = Color(0xFF1F2C34);
  static const _pillBg = Color(0xFF111B21);
  static const _teal = Color(0xFF00A884);
  static const _iconGrey = Color(0xFF8696A0);
  static const _red = Color(0xFFEF5350);

  // ---- tuning (غيّرها لو بدك تضبط الإحساس) ----
  static const double _lockDist = 100; // مسافة السحب لفوق للقفل
  static const double _cancelDist = 70; // مسافة السحب للإلغاء
  static const double _recScale = 1.8; // حجم المايك وقت الضغط
  static const Duration _holdDelay = Duration(milliseconds: 180);

  late TextEditingController _controller;
  bool _isInternal = false;
  bool _isTyping = false;
  bool _showEmojiPanel = false;
  double _emojiPanelHeight = 300;
  // الشيت يبقى معروضاً (بارتفاع معوَّض) أثناء تبديل الكيبورد/الإيموجي حتى ما يتحرك مستطيل الكتابة
  bool _holdPanel = false;
  double _kbInset = 0; // ارتفاع الكيبورد الحالي الفعلي (يتغير أثناء الأنيميشن)
  Timer? _releaseTimer;
  final FocusNode _textFocus = FocusNode();

  bool _isRecording = false;
  bool _isLocked = false;
  bool _isPaused = false;
  bool _showLockBadge = false;
  bool _micDown = false;
  bool _dragging = false;
  bool _starting = false;
  Duration _duration = Duration.zero;
  Timer? _timer;
  Timer? _holdTimer;
   List<double> _waveData = [];
  final List<double> _ampSamples = [];
  double _dragX = 0; // موجب = لليمين (إلغاء)
  double _dragY = 0; // سالب = لفوق (قفل)
  int _axis = 0; // 0 لسا، 1 أفقي، 2 عمودي

  int? _pointer;
  Offset _downPos = Offset.zero;
  bool _tapSend = false;

  late final AnimationController _cancelCtrl;
  final _audioRecorder = AudioRecorder();

  double get _lockProgress => (-_dragY / _lockDist).clamp(0.0, 1.0);
  double get _cancelProgress => (_dragX / _cancelDist).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cancelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _textFocus.addListener(() {
      if (_textFocus.hasFocus && _showEmojiPanel && mounted) {
        // الانتقال من الإيموجي إلى الكيبورد: الشيت يبقى مكانه ويتغطى تدريجياً بالكيبورد
        setState(() => _showEmojiPanel = false);
        _armHoldRelease();
      }
    });
    _controller = widget.textController ?? TextEditingController();
    _isInternal = widget.textController == null;
    _controller.addListener(() {
      if (!mounted) return;
      final t = _controller.text.trim().isNotEmpty;
      if (t != _isTyping) setState(() => _isTyping = t);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseTimer?.cancel();
    _timer?.cancel();
    _holdTimer?.cancel();
    _cancelCtrl.dispose();
    _textFocus.dispose();
    _audioRecorder.dispose();
    if (_isInternal) _controller.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // تبديل الكيبورد/الإيموجي بدون أي قفزة في مستطيل الكتابة
  // ------------------------------------------------------------------

  double _readInset() {
    final v = View.of(context);
    return v.viewInsets.bottom / v.devicePixelRatio;
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final inset = _readInset();
    if ((inset - _kbInset).abs() < 0.5) return;
    _kbInset = inset;
    // نتذكر ارتفاع الكيبورد الحقيقي لما يكون مفتوحاً بالكامل وبدون تبديل جارٍ
    if (!_holdPanel && inset > 150) _emojiPanelHeight = inset;
    if (_holdPanel) {
      // انتهى فتح الكيبورد: الكيبورد غطّى مكان الشيت بالكامل، نزيل الشيت
      if (!_showEmojiPanel && inset >= _emojiPanelHeight - 1) {
        _holdPanel = false;
        _releaseTimer?.cancel();
      }
      setState(() {});
    }
  }

  void _armHoldRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && !_showEmojiPanel && _holdPanel) {
        setState(() => _holdPanel = false);
      }
    });
  }

  // ------------------------------------------------------------------
  // Recording logic
  // ------------------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (!_isPaused && _isRecording) {
        double level = 0.1;
        try {
          final a = await _audioRecorder.getAmplitude();
          level = ((a.current + 45) / 45).clamp(0.05, 1.0).toDouble();
        } catch (_) {}
        if (!mounted || !_isRecording) return;
        setState(() {
          _duration += const Duration(milliseconds: 80);
          if (_waveData.length > 55) _waveData.removeAt(0);
          _waveData.add(level);
          _ampSamples.add(level);
        });
      }
    });
  }

  List<int> _downsample(List<double> s, {int bars = 40}) {
    if (s.isEmpty) return [];
    return List.generate(bars, (i) {
      final start = (i * s.length / bars).floor();
      final end = ((i + 1) * s.length / bars).ceil().clamp(start + 1, s.length);
      double peak = 0;
      for (int j = start; j < end; j++) {
        if (s[j] > peak) peak = s[j];
      }
      return (peak * 100).round();
    });
  }

  Future<void> _startRecording() async {
    if (_isRecording || _starting) return;
    _starting = true;
    try {
      if (!await _audioRecorder.hasPermission()) {
        _starting = false;
        if (mounted) setState(() => _micDown = false);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(const RecordConfig(), path: path);
    } catch (_) {
      _starting = false;
      if (mounted) setState(() => _micDown = false);
      return;
    }
    _starting = false;
    if (!mounted) return;

    // الإصبع انرفع قبل ما يبدأ التسجيل فعلياً
    if (_pointer == null) {
      final p = await _audioRecorder.stop();
      if (p != null) {
        try {
          File(p).deleteSync();
        } catch (_) {}
      }
      if (mounted) setState(() => _micDown = false);
      return;
    }

    HapticFeedback.lightImpact();
    _cancelCtrl.value = 0;
    setState(() {
      _isRecording = true;
      _isLocked = false;
      _isPaused = false;
      _duration = Duration.zero;
      _waveData = [0.1, 0.2, 0.3];
      _ampSamples.clear();
      _dragX = 0;
      _dragY = 0;
      _axis = 0;
    });
    _startTimer();
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    _timer?.cancel();
    final wasRecording = _isRecording;
    final dur = _duration;
    final samples = List<double>.from(_ampSamples);
    setState(() {
      _isRecording = false;
      _isLocked = false;
      _isPaused = false;
      _showLockBadge = false;
      _micDown = false;
      _dragging = false;
      _dragX = 0;
      _dragY = 0;
      _axis = 0;
    });
    if (cancel && wasRecording) {
      HapticFeedback.mediumImpact();
      _cancelCtrl.forward(from: 0);
    }

    final path = await _audioRecorder.stop();
    if (!cancel &&
        path != null &&
        File(path).existsSync() &&
        dur.inMilliseconds > 400) {
      widget.onSendVoice(path, dur, _downsample(samples));
    } else if (cancel && path != null) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _duration = Duration.zero;
        _waveData = [];
      });
    }
  }

  void _lock() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isLocked = true;
      _showLockBadge = true;
      _dragging = false;
      _dragX = 0;
      _dragY = 0;
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showLockBadge = false);
    });
  }

  Future<void> _togglePause() async {
    final willPause = !_isPaused;
    setState(() => _isPaused = willPause);
    try {
      if (willPause) {
        await _audioRecorder.pause();
      } else {
        await _audioRecorder.resume();
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Pointer handling (Listener بدل GestureDetector عشان ما نفقد الإصبع
  // وقت يتغير شكل الواجهة من عادي إلى تسجيل)
  // ------------------------------------------------------------------

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _downPos = e.position;
    _axis = 0;
    if (_isTyping) {
      _tapSend = true;
      return;
    }
    _tapSend = false;
    setState(() => _micDown = true);
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDelay, () {
      if (_pointer != null) _startRecording();
    });
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer || !_isRecording || _isLocked) return;
    final d = e.position - _downPos;
    if (_axis == 0 && d.distance > 10) {
      _axis = d.dx.abs() > d.dy.abs() ? 1 : 2;
    }
    setState(() {
      _dragging = true;
      _dragX = _axis == 1 ? d.dx.clamp(0.0, 140.0) : 0;
      _dragY = _axis == 2 ? d.dy.clamp(-(_lockDist + 20), 0.0) : 0;
    });
    if (_axis == 2 && -_dragY >= _lockDist && !_isLocked) _lock();
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _holdTimer?.cancel();

    if (_tapSend) {
      _tapSend = false;
      if ((e.position - _downPos).distance < 24) {
        final text = _controller.text.trim();
        if (text.isNotEmpty) {
          widget.onSendText(text);
          _controller.clear();
        }
      }
      return;
    }

    setState(() => _dragging = false);
    if (!_isRecording) {
      if (!_starting) setState(() => _micDown = false);
      return;
    }
    if (_isLocked) return;
    if (_dragX >= _cancelDist) {
      _stopRecording(cancel: true);
    } else {
      _stopRecording();
    }
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _holdTimer?.cancel();
    _tapSend = false;
    setState(() => _dragging = false);
    if (_isRecording && !_isLocked) {
      _stopRecording(cancel: true);
    } else if (!_isRecording && !_starting) {
      setState(() => _micDown = false);
    }
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  bool get _blinkOn => (_duration.inMilliseconds ~/ 600) % 2 == 0;

  Future<void> _openExistingCamera() async {
              final result = await Navigator.push(
                context,
                ChatCameraScreen.route(
                  recipientName: widget.cameraRecipientName,
                  allowMulti: widget.allowMultiMedia,
                ),
              );
              if (result is Map && result['items'] is List) {
                final items = (result['items'] as List)
                    .whereType<Map>()
                    .where((e) => e['path'] != null)
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
                if (items.isNotEmpty) {
                  if (items.any((e) => e['viewOnce'] == true || e['isVideoNote'] == true)) {
                    for (final item in items) {
                      final path = item['path'].toString();
                      final isVideo = item['isVideo'] == true;
                      final dynamic sent = item['isVideoNote'] == true && widget.onSendVideoNote != null
                          ? widget.onSendVideoNote!(path)
                          : item['viewOnce'] == true && widget.onSendViewOnce != null
                              ? widget.onSendViewOnce!(path, isVideo)
                              : widget.onSendMedia?.call(path, (item['caption'] ?? '').toString(), isVideo);
                      if (sent is Future) await sent;
                    }
                  } else {
                    unawaited(widget.onSendMediaAlbum(items));
                  }
                }
              } else if (result is Map && result['paths'] is List) {
                final items = (result['paths'] as List)
                    .map((path) => <String, dynamic>{'path': path.toString(), 'isVideo': _looksLikeVideo(path.toString())})
                    .toList();
                if (items.isNotEmpty) unawaited(widget.onSendMediaAlbum(items));
              } else if (result is Map && result['path'] != null && result['isVideoNote'] == true && widget.onSendVideoNote != null) {
                widget.onSendVideoNote!.call(result['path']);
              } else if (result is Map && result['path'] != null && result['viewOnce'] == true && widget.onSendViewOnce != null) {
                widget.onSendViewOnce!.call(result['path'], result['isVideo'] ?? false);
              } else if (result is Map && result['path'] != null) {
                widget.onSendMedia?.call(result['path'], result['caption'] ?? '', result['isVideo'] ?? false);
              } else if (widget.onSendMedia == null) {
                // السلوك القديم للشاشات التي لا تمرّر onSendMedia
                widget.onPickCamera?.call();
              }
  }

  void _toggleEmojiPanel() {
    if (_showEmojiPanel) {
      // إيموجي -> كيبورد: الشيت يبقى معروضاً بارتفاع معوَّض حتى يغطيه الكيبورد
      // فيبقى مستطيل الكتابة في مكانه بدون أي قفزة.
      _releaseTimer?.cancel();
      setState(() => _showEmojiPanel = false);
      _armHoldRelease();
      _textFocus.requestFocus();
    } else {
      // كيبورد -> إيموجي: الشيت يظهر فوراً بالارتفاع الكامل بينما الكيبورد ينزل،
      // ومجموع الاثنين ثابت فيبقى مستطيل الكتابة في مكانه.
      final keyboardHeight = _readInset();
      if (keyboardHeight > 150) {
        _emojiPanelHeight = keyboardHeight;
      } else {
        // عند فتح الإيموجي والكيبورد مغلق (أول مرة أو بعد إغلاقه)،
        // نعيد احتساب الارتفاع المناسب للشاشة بدلاً من استعمال قياس
        // جزئي سُجّل أثناء نزول الكيبورد في didChangeMetrics.
        final screenHeight = MediaQuery.sizeOf(context).height;
        _emojiPanelHeight = (screenHeight * 0.46).clamp(340.0, 440.0).toDouble();
      }
      _releaseTimer?.cancel();
      setState(() {
        _kbInset = keyboardHeight;
        _holdPanel = true;
        _showEmojiPanel = true;
      });
      _textFocus.unfocus();
    }
  }

  void _insertEmoji(String emoji) {
    final old = _controller.value;
    final selection = old.selection;
    final start = selection.isValid ? selection.start : old.text.length;
    final end = selection.isValid ? selection.end : old.text.length;
    final safeStart = start.clamp(0, old.text.length);
    final safeEnd = end.clamp(safeStart, old.text.length);
    final updated = old.text.replaceRange(safeStart, safeEnd, emoji);
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: safeStart + emoji.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        layoutBuilder: (current, previous) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [...previous, if (current != null) current],
        ),
        child: _isLocked ? _buildLocked() : _buildBar(),
          ),
          if (_holdPanel && !_isLocked)
            SizedBox(
              // الارتفاع المعوَّض = ارتفاع الشيت الكامل - ارتفاع الكيبورد الحالي
              height: (_emojiPanelHeight - _kbInset).clamp(0.0, _emojiPanelHeight).toDouble(),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: _emojiPanelHeight,
                  maxHeight: _emojiPanelHeight,
                  child: EmojiStickerSheet(
                    inline: true,
                    inlineHeight: _emojiPanelHeight,
                    onEmojiSelected: _insertEmoji,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- الشريط العادي + وقت الضغط المطول ----------
  Widget _buildBar() {
    final p = _lockProgress;
    final pillH = 104.0 - 60.0 * p;

    return Padding(
      key: const ValueKey('bar'),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // كبسولة القفل (ورا المايك)
          if (_isRecording)
            Positioned(
              left: 4,
              bottom: 170 - pillH,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  builder: (context, v, child) => Opacity(
                    opacity: v,
                    child: Transform.translate(
                      offset: Offset(0, (1 - v) * 24),
                      child: child,
                    ),
                  ),
                  child: Container(
                    width: 44,
                    height: pillH,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: _pillBg,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 13,
                          left: 0,
                          right: 0,
                          child: Icon(
                            p > 0.6 ? Icons.lock : Icons.lock_open,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                        Positioned(
                          top: 34,
                          left: 0,
                          right: 0,
                          child: Opacity(
                            opacity: (1 - p * 2).clamp(0.0, 1.0),
                            child: const Icon(
                              Icons.keyboard_arrow_up,
                              size: 18,
                              color: _iconGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _buildField()),
              const SizedBox(width: 8),
              _buildMic(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMic() {
    final p = _lockProgress;
    double scale = 1.0;
    if (_isRecording) {
      scale = _recScale - (_recScale - 0.55) * Curves.easeIn.transform(p);
    } else if (_micDown) {
      scale = 1.15;
    }
    final tx = _isRecording ? _dragX : 0.0;
    final ty = _isRecording ? _dragY * 0.6 : 0.0;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: AnimatedContainer(
        duration:
            _dragging ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 52,
        height: 52,
        transformAlignment: Alignment.center,
        transform: Matrix4.diagonal3Values(scale, scale, 1)
          ..setTranslationRaw(tx, ty, 0),
        decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Icon(
            _isTyping ? Icons.send : Icons.mic,
            key: ValueKey(_isTyping),
            color: Colors.white,
            size: _isTyping ? 22 : 28,
          ),
        ),
      ),
    );
  }

  Widget _buildField() {
    final c = _cancelProgress;

    final idleRow = Row(
      children: [
        _emojiSlot(),
        const SizedBox(width: 2),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _textFocus,
            minLines: 1,
            maxLines: 5,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontFamily: 'Tajawal'),
            decoration: const InputDecoration(
              hintText: "مراسلة",
              hintStyle: TextStyle(
                  color: _iconGrey, fontSize: 16, fontFamily: 'Tajawal'),
              border: InputBorder.none,
              filled: true,
              fillColor: _inputBg,
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            ),
          ),
        ),
        IconButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
            builder: (_) => TiniAttachmentSheet(
              onGallery: () => widget.onPickFile?.call(),
              onCamera: _openExistingCamera,
              onLocation: () => widget.onPickLocation?.call(),
              onDocument: () => widget.onPickDocument?.call(),
            ),
          ),
          icon: const Icon(Icons.attach_file_outlined,
              color: _iconGrey, size: 24),
        ),
        if (!_isTyping)
          IconButton(
            onPressed: _openExistingCamera,
            icon: const Icon(Icons.camera_alt_outlined,
                color: _iconGrey, size: 26),
          ),
        const SizedBox(width: 4),
      ],
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _inputBg,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedOpacity(
            opacity: _isRecording ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(ignoring: _isRecording, child: idleRow),
          ),
          if (_isRecording)
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 150),
                  builder: (context, v, child) =>
                      Opacity(opacity: v, child: child),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mic,
                          size: 20,
                          color: _red.withOpacity(_blinkOn ? 1.0 : 0.35),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _fmt(_duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Opacity(
                              opacity: (1 - c * 1.4).clamp(0.0, 1.0),
                              child: Transform.translate(
                                offset: Offset(_dragX * 0.5, 0),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "اسحب للإلغاء",
                                      style: TextStyle(
                                        color: _iconGrey,
                                        fontSize: 14,
                                        fontFamily: 'Tajawal',
                                      ),
                                    ),
                                    SizedBox(width: 2),
                                    Icon(Icons.chevron_left,
                                        size: 18, color: _iconGrey),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // مكان الإيموجي: وقت الإلغاء بتنزل فيه المايك الحمرا بسلة المهملات
  Widget _emojiSlot() {
    return SizedBox(
      width: 40,
      height: 40,
      child: AnimatedBuilder(
        animation: _cancelCtrl,
        builder: (context, _) {
          final t = _cancelCtrl.value;
          final active = _cancelCtrl.isAnimating;

          double binOp = 0;
          double micY = 0, rot = 0, micScale = 1, micOp = 0, lid = 0;
          if (active) {
            if (t < 0.08) {
              binOp = t / 0.08;
            } else if (t > 0.9) {
              binOp = (1 - t) / 0.1;
            } else {
              binOp = 1;
            }
            binOp = binOp.clamp(0.0, 1.0);

            if (t < 0.45) {
              micY = -58 * Curves.easeOut.transform(t / 0.45);
            } else {
              final u =
                  Curves.easeIn.transform(((t - 0.45) / 0.4).clamp(0.0, 1.0));
              micY = -58 + 62 * u;
              micScale = 1 - 0.5 * u;
            }
            rot = pi * Curves.easeInOut.transform((t / 0.85).clamp(0.0, 1.0));
            micOp = t < 0.8 ? 1 : ((0.9 - t) / 0.1).clamp(0.0, 1.0);

            if (t < 0.25) {
              lid = 0;
            } else if (t < 0.45) {
              lid = (t - 0.25) / 0.2;
            } else if (t < 0.8) {
              lid = 1;
            } else if (t < 0.95) {
              lid = (0.95 - t) / 0.15;
            }
          }

          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: 1 - binOp,
                child: IgnorePointer(
                  ignoring: active,
                  child: IconButton(
                    onPressed: _toggleEmojiPanel,
                    icon: Icon(_showEmojiPanel ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
                        color: _iconGrey, size: 26),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
              if (active)
                Opacity(
                  opacity: binOp,
                  child: CustomPaint(
                    size: const Size(26, 26),
                    painter: _TrashPainter(lid, _iconGrey),
                  ),
                ),
              if (active)
                Opacity(
                  opacity: micOp,
                  child: Transform.translate(
                    offset: Offset(0, micY),
                    child: Transform.rotate(
                      angle: rot,
                      child: Transform.scale(
                        scale: micScale,
                        child: const Icon(Icons.mic, size: 20, color: _red),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---------- وضع القفل ----------
  Widget _buildLocked() {
    final topRow = Row(
      children: [
        Text(
          _fmt(_duration),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 30,
            child: CustomPaint(
              painter: _WavePainter(_waveData, const Color(0xFFB8C2C8)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(
          Icons.circle,
          size: 10,
          color: _isPaused
              ? _iconGrey
              : _red.withOpacity(_blinkOn ? 1.0 : 0.35),
        ),
        const SizedBox(width: 4),
      ],
    );

    final bottomRow = Row(
      children: [
        GestureDetector(
          onTap: () => _stopRecording(cancel: true),
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
                color: Color(0xFF3B2A2E), shape: BoxShape.circle),
            child: const Icon(Icons.delete_outline, color: _red, size: 24),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: _togglePause,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2A3942),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isPaused ? "متابعة" : "إيقاف مؤقت",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'Tajawal'),
                  ),
                  const SizedBox(width: 8),
                  Icon(_isPaused ? Icons.mic : Icons.pause,
                      size: 18, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _stopRecording(),
          child: Container(
            width: 48,
            height: 48,
            decoration:
                const BoxDecoration(color: _teal, shape: BoxShape.circle),
            child: const Icon(Icons.send, color: Colors.white, size: 22),
          ),
        ),
      ],
    );

    return Padding(
      key: const ValueKey('locked'),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
            decoration: BoxDecoration(
              color: _panelBg,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                topRow,
                const SizedBox(height: 10),
                bottomRow,
              ],
            ),
          ),
          // دائرة القفل بتظهر لحظة وبتختفي
          Positioned(
            left: 4,
            top: -54,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showLockBadge ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                      color: _pillBg, shape: BoxShape.circle),
                  child: const Icon(Icons.lock, size: 20, color: _teal),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// الموجة: الأعمدة الجديدة بتدخل من اليمين (جنب التايمر) والباقي نقاط
class _WavePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  _WavePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 5.0;
    final count = (size.width / gap).floor();
    final bar = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = color.withOpacity(0.35);
    final cy = size.height / 2;

    for (int i = 0; i < count; i++) {
      final x = size.width - (i + 0.5) * gap;
      if (i < data.length) {
        final v = data[data.length - 1 - i].clamp(0.05, 1.0);
        final h = max(4.0, v * size.height * 0.85);
        canvas.drawLine(Offset(x, cy - h / 2), Offset(x, cy + h / 2), bar);
      } else {
        canvas.drawCircle(Offset(x, cy), 1.1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}

// سلة المهملات مع غطاء بينفتح
class _TrashPainter extends CustomPainter {
  final double open; // 0..1
  final Color color;
  _TrashPainter(this.open, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width, h = size.height;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * .22, h * .38, w * .78, h * .92),
        const Radius.circular(3),
      ),
      p,
    );
    canvas.drawLine(Offset(w * .40, h * .52), Offset(w * .40, h * .78), p);
    canvas.drawLine(Offset(w * .60, h * .52), Offset(w * .60, h * .78), p);

    canvas.save();
    canvas.translate(w * .14, h * .28);
    canvas.rotate(-open * 0.7);
    canvas.drawLine(Offset.zero, Offset(w * .72, 0), p);
    canvas.drawLine(Offset(w * .26, -h * .08), Offset(w * .46, -h * .08), p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TrashPainter old) =>
      old.open != open || old.color != color;
}