import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// ملاحظة فيديو دائرية بأسلوب واتساب:
/// - دائرة صغيرة مع زر تشغيل ومدة الفيديو.
/// - عند الضغط تكبر الدائرة بحركة سلسة داخل الدردشة (بدون فول سكرين).
/// - حلقة تقدّم حول الحافة وعدّاد للوقت أثناء التشغيل.
/// - عند الانتهاء ترجع تصغر وترجع للبداية.
class VideoNoteBubble extends StatefulWidget {
  final String videoUrl;
  final int durationSeconds;
  final String timeText;
  final bool isMe;
  final bool isSeen;
  final Color accentColor;

  const VideoNoteBubble({
    super.key,
    required this.videoUrl,
    required this.durationSeconds,
    required this.timeText,
    required this.isMe,
    required this.isSeen,
    this.accentColor = Colors.teal,
  });

  @override
  State<VideoNoteBubble> createState() => _VideoNoteBubbleState();
}

class _VideoNoteBubbleState extends State<VideoNoteBubble> {
  static const double _smallSize = 200;
  static const Duration _animDuration = Duration(milliseconds: 320);

  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _expanded = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller.initialize().then((_) {
      if (!mounted) return;
      _controller.setLooping(false);
      _controller.seekTo(Duration.zero);
      setState(() => _initialized = true);
    });
    _controller.addListener(_onTick);
  }

  bool _atEnd(VideoPlayerValue v) =>
      v.duration > Duration.zero &&
      v.position >= v.duration - const Duration(milliseconds: 300);

  void _onTick() {
    if (!mounted || !_initialized) return;
    final v = _controller.value;
    if (_expanded && !_resetting && v.isCompleted && _atEnd(v)) {
      _finishAndCollapse();
      return;
    }
    setState(() {});
  }

  /// بعد كل تشغيل نبدّل المشغّل بمشغّل جديد (نفس ما يحصل عند السكرول)،
  /// لأن إعادة استخدام نفس المشغّل بعد seekTo عدة مرات قد يعلق على أندرويد.
  Future<void> _finishAndCollapse() async {
    _resetting = true;
    if (mounted) setState(() => _expanded = false);
    final old = _controller;
    final fresh = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    try {
      await fresh.initialize();
      await fresh.setLooping(false);
      if (!mounted) {
        await fresh.dispose();
        return;
      }
      old.removeListener(_onTick);
      fresh.addListener(_onTick);
      setState(() => _controller = fresh);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    } catch (_) {
      // فشل التحميل (مثلاً بدون إنترنت): نرجع للطريقة القديمة
      try {
        await fresh.dispose();
      } catch (_) {}
      try {
        await old.pause();
        await old.seekTo(Duration.zero);
      } catch (_) {}
    }
    _resetting = false;
    if (mounted) setState(() {});
  }

  Future<void> _onTap() async {
    if (!_initialized || _resetting) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
      if (mounted) setState(() {});
    } else {
      if (_atEnd(_controller.value)) {
        await _controller.seekTo(Duration.zero);
      }
      if (!mounted) return;
      setState(() => _expanded = true);
      await _controller.play();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final double bigSize = (screenW * 0.78).clamp(_smallSize, 360.0);
    final double size = _expanded ? bigSize : _smallSize;

    final total = _initialized && _controller.value.duration > Duration.zero
        ? _controller.value.duration
        : Duration(seconds: widget.durationSeconds);
    final position = _initialized ? _controller.value.position : Duration.zero;
    final double progress = total.inMilliseconds == 0
        ? 0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final bool isPlaying = _initialized && _controller.value.isPlaying;
    final bool showTimerUp = _expanded;
    final String label = showTimerUp ? _fmt(position) : _fmt(total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: AnimatedContainer(
            duration: _animDuration,
            curve: Curves.easeInOutCubic,
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // الفيديو بشكل دائرة
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: ClipOval(
                      child: Container(
                        color: const Color(0xFF1A222C),
                        child: _initialized
                            ? FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _controller.value.size.width,
                                  height: _controller.value.size.height,
                                  child: VideoPlayer(_controller),
                                ),
                              )
                            : const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                // الإطار + حلقة التقدم
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _RingPainter(
                        progress: _expanded ? progress : 0,
                        baseColor: widget.accentColor,
                        showProgress: _expanded,
                      ),
                    ),
                  ),
                ),
                // زر التشغيل
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: isPlaying ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                    ),
                  ),
                ),
                // عدّاد الوقت أسفل الدائرة
                Positioned(
                  bottom: size * 0.07,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.timeText, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              if (widget.isMe) ...[
                const SizedBox(width: 4),
                Icon(widget.isSeen ? Icons.done_all : Icons.done,
                    size: 14, color: widget.isSeen ? Colors.white : Colors.white54),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color baseColor;
  final bool showProgress;

  _RingPainter({required this.progress, required this.baseColor, required this.showProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1.5;

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = baseColor.withOpacity(showProgress ? 0.35 : 0.9);
    canvas.drawCircle(center, radius, base);

    if (showProgress && progress > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.5
        ..color = Colors.white;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -1.5707963267948966,
        6.283185307179586 * progress,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.showProgress != showProgress || old.baseColor != baseColor;
}