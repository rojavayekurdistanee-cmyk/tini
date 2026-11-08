import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'view_once_icon.dart';

/// تفعيل/إلغاء منع لقطة الشاشة وتسجيل الشاشة (FLAG_SECURE) عبر MainActivity.
class ViewOnceSecure {
  static const MethodChannel _ch = MethodChannel('titi_star/thumbnails');
  static Future<void> set(bool secure) async {
    try {
      await _ch.invokeMethod('setSecure', {'secure': secure});
    } catch (_) {}
  }
}

const Color _kGreen = Color(0xFF21C063);
const Color _kSheetBg = Color(0xFF1A222C);

/// الورقة التعريفية اللي تظهر أول مرة يفتح فيها المستلم رسالة عرض مرة واحدة.
/// ترجع true إذا ضغط "موافق" (أو كان وافق سابقاً).
Future<bool> showViewOnceIntro(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('view_once_intro_seen') == true) return true;
  if (!context.mounted) return false;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: _kSheetBg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ),
              Center(child: ViewOnceIcon(size: 64, color: _kGreen)),
              const SizedBox(height: 20),
              const Text(
                'هذه رسالة للعرض مرة واحدة لذا فهي أكثر خصوصية',
                style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
              ),
              const SizedBox(height: 20),
              _introRow(Icons.timelapse_rounded, 'ستختفي من الدردشة بعد إغلاقها.'),
              const SizedBox(height: 14),
              _introRow(Icons.lock_outline_rounded, 'ولا يمكنك أيضًا مشاركتها أو إعادة توجيهها أو نسخها أو حفظها أو أخذ لقطة شاشة لها.'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('موافق', style: TextStyle(fontFamily: 'Tajawal', fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => showDialog(
                    context: ctx,
                    builder: (dctx) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: AlertDialog(
                        backgroundColor: _kSheetBg,
                        title: const Text('عرض مرة واحدة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
                        content: const Text(
                          'تُحذف الصور والفيديوهات المرسلة للعرض مرة واحدة من الخادم بعد أن يفتحها جميع الأعضاء. ومع ذلك يمكن لأي شخص تصويرها بكاميرا هاتف آخر، لذلك أرسل فقط لمن تثق بهم.',
                          style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', height: 1.5),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dctx),
                            child: const Text('حسناً', style: TextStyle(color: _kGreen, fontFamily: 'Tajawal')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: const Text('معرفة المزيد', style: TextStyle(color: _kGreen, fontFamily: 'Tajawal', fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (ok == true) {
    await prefs.setBool('view_once_intro_seen', true);
    return true;
  }
  return false;
}

Widget _introRow(IconData icon, String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Colors.white70, size: 22),
      const SizedBox(width: 14),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15, height: 1.5),
        ),
      ),
    ],
  );
}

/// عارض الصورة/الفيديو لمرة واحدة. بيمنع لقطة الشاشة طول فترة العرض.
class ViewOnceViewerScreen extends StatefulWidget {
  final String url;
  final bool isVideo;
  final String senderName;

  // [عرض مرة واحدة - الخاص] اختياري؛ المجموعات تستمر بالطريقة الأصلية.
  final VideoPlayerController? preparedVideo;
  final Future<bool>? preparedVideoReady;

  const ViewOnceViewerScreen({
    super.key,
    required this.url,
    required this.isVideo,
    this.senderName = '',
    this.preparedVideo,
    this.preparedVideoReady,
  });

  @override
  State<ViewOnceViewerScreen> createState() => _ViewOnceViewerScreenState();
}

class _ViewOnceViewerScreenState extends State<ViewOnceViewerScreen> {
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _videoFailed = false;

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ViewOnceSecure.set(true);
    if (widget.isVideo) {
      final c = widget.preparedVideo ??
          VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _video = c;
      final Future<bool> ready = widget.preparedVideoReady ??
          c.initialize().then<bool>((_) => true).catchError((_) => false);
      ready.then((ok) {
        if (!mounted) return;
        if (!ok) {
          setState(() => _videoFailed = true);
          return;
        }
        c.addListener(_onVideoChanged);
        setState(() => _videoReady = true);
        c.play();
      });
    }
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideoChanged);
    _video?.dispose();
    ViewOnceSecure.set(false);
    super.dispose();
  }

  void _togglePlay() {
    final c = _video;
    if (c == null || !_videoReady) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      final v = c.value;
      if (v.position >= v.duration - const Duration(milliseconds: 150)) {
        c.seekTo(Duration.zero);
      }
      c.play();
    }
  }

  Widget _failed() => const Text(
        'تعذر تحميل المحتوى',
        style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 15),
      );

  Widget _buildBody() {
    if (!widget.isVideo) {
      return InteractiveViewer(
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          loadingBuilder: (c, child, p) => p == null ? child : const CircularProgressIndicator(color: _kGreen),
          errorBuilder: (_, __, ___) => _failed(),
        ),
      );
    }
    if (_videoFailed) return _failed();
    final c = _video;
    if (c == null || !_videoReady) return const CircularProgressIndicator(color: _kGreen);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
          if (!c.value.isPlaying)
            Container(
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              padding: const EdgeInsets.all(14),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 44),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: _kGreen)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: Center(child: _buildBody())),
            Positioned(
              top: 4,
              left: 4,
              right: 12,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  children: [
                    const ViewOnceIcon(size: 22, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
