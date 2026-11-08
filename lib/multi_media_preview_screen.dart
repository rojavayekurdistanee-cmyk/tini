import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'caption_preview_screen.dart';
import 'media_strip_picker_sheet.dart';
import 'preview_media_item.dart';

/// شاشة المعاينة المتعددة (تصميم واتساب): شريط مصغّرات + زر "+" لإضافة المزيد + حذف عنصر.
/// كل عنصر له شاشة معاينة/تحرير مستقلة (CaptionPreviewScreen بوضع embedded) مع شرح توضيحي خاص به.
///
/// ترجع عند الإرسال:
///  - عنصر واحد: نفس الشكل القديم {path, caption, isVideo, isVideoNote, viewOnce}
///  - أكثر من عنصر: {items: [ {path, caption, isVideo, isVideoNote, viewOnce}, ... ]}
class MultiMediaPreviewScreen extends StatefulWidget {
  /// الحد الأقصى للعناصر في الرسالة الواحدة.
  static const int kMaxItems = 5;

  final List<PreviewMediaItem> initialItems;
  final String? recipientName;
  final int maxItems;

  /// true = بعد الإرسال نغلق المعاينة + الشاشة التي قبلها (الكاميرا). false = نغلق المعاينة فقط.
  final bool popCameraToo;

  const MultiMediaPreviewScreen({
    super.key,
    required this.initialItems,
    this.recipientName,
    this.maxItems = kMaxItems,
    this.popCameraToo = true,
  });

  /// انتقال fade مثل باقي شاشات المعاينة
  static Route<dynamic> route({
    required List<PreviewMediaItem> items,
    String? recipientName,
    int maxItems = kMaxItems,
    bool popCameraToo = true,
  }) {
    return PageRouteBuilder<dynamic>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, __, ___) => MultiMediaPreviewScreen(
        initialItems: items,
        recipientName: recipientName,
        maxItems: maxItems,
        popCameraToo: popCameraToo,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  /// يحوّل نتيجة المعاينة (عنصر واحد أو عدة عناصر) إلى قائمة موحدة من الخرائط.
  static List<Map<String, dynamic>> normalizeResult(dynamic r) {
    if (r is Map) {
      final dynamic items = r['items'];
      if (items is List) {
        return [
          for (final e in items)
            if (e is Map) Map<String, dynamic>.from(e),
        ];
      }
      if (r['path'] != null) return [Map<String, dynamic>.from(r)];
    }
    return <Map<String, dynamic>>[];
  }

  @override
  State<MultiMediaPreviewScreen> createState() => _MultiMediaPreviewScreenState();
}

class _MultiMediaPreviewScreenState extends State<MultiMediaPreviewScreen> {
  static const Color _green = Color(0xFF21C063);

  late List<PreviewMediaItem> _items;
  final Map<String, GlobalKey<CaptionPreviewScreenState>> _keys = {};
  final Map<String, String?> _vidThumbs = {};
  int _cur = 0;
  bool _sending = false;
  String? _toastMsg;
  bool _toastOn = false;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems.take(widget.maxItems).toList();
    for (final PreviewMediaItem it in _items) {
      _register(it);
    }
    if (widget.initialItems.length > widget.maxItems) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showToast('تم اختيار أول ${widget.maxItems} عناصر فقط (الحد الأقصى)');
      });
    }
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _register(PreviewMediaItem it) {
    _keys.putIfAbsent(it.id, () => GlobalKey<CaptionPreviewScreenState>());
    if (it.isVideo) _makeVideoThumb(it);
  }

  Future<void> _makeVideoThumb(PreviewMediaItem it) async {
    try {
      final String? p = await VideoThumbnail.thumbnailFile(
        video: it.file.path,
        imageFormat: ImageFormat.JPEG,
        timeMs: 0,
        maxHeight: 160,
        quality: 60,
      );
      if (!mounted) return;
      setState(() => _vidThumbs[it.id] = p);
    } catch (_) {}
  }

  /// يضمن أن العنصر الحالي فقط هو النشط (الباقي متوقف).
  void _syncActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (int i = 0; i < _items.length; i++) {
        _keys[_items[i].id]?.currentState?.setActive(i == _cur);
      }
    });
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() {
      _toastMsg = msg;
      _toastOn = true;
    });
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastOn = false);
    });
  }

  void _select(int i) {
    if (_sending || i == _cur || i < 0 || i >= _items.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _cur = i);
    _syncActive();
  }

  void _removeAt(int i) {
    if (_sending || i < 0 || i >= _items.length) return;
    if (_items.length == 1) {
      Navigator.pop(context);
      return;
    }
    final PreviewMediaItem removed = _items[i];
    setState(() {
      _items.removeAt(i);
      _keys.remove(removed.id);
      _vidThumbs.remove(removed.id);
      if (i < _cur) _cur -= 1;
      if (_cur >= _items.length) _cur = _items.length - 1;
      if (_cur < 0) _cur = 0;
    });
    _syncActive();
  }

  Future<void> _addMore() async {
    if (_sending) return;
    final int remaining = widget.maxItems - _items.length;
    if (remaining <= 0) {
      _showToast('الحد الأقصى ${widget.maxItems} عناصر في الرسالة الواحدة');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _keys[_items[_cur].id]?.currentState?.setActive(false);
    final List<PreviewMediaItem>? added = await showMediaStripPicker(context, maxSelect: remaining);
    if (!mounted) return;
    if (added == null || added.isEmpty) {
      _syncActive();
      return;
    }
    final int firstNew = _items.length;
    setState(() {
      for (final PreviewMediaItem it in added) {
        if (_items.length >= widget.maxItems) break;
        _items.add(it);
        _register(it);
      }
      if (firstNew < _items.length) _cur = firstNew;
    });
    _syncActive();
  }

  bool get _anyEdits {
    for (final PreviewMediaItem it in _items) {
      if (_keys[it.id]?.currentState?.hasEdits == true) return true;
    }
    return false;
  }

  Future<void> _requestClose() async {
    if (_sending) return;
    if (!_anyEdits) {
      Navigator.pop(context);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF111B21),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          content: const Text(
            'هل تريد تجاهل الوسائط؟',
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

  Future<void> _sendAll() async {
    if (_sending) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _sending = true);
    final NavigatorState nav = Navigator.of(context);
    final List<Map<String, dynamic>> results = [];
    final List<PreviewMediaItem> snapshot = List<PreviewMediaItem>.from(_items);
    for (final PreviewMediaItem it in snapshot) {
      final CaptionPreviewScreenState? st = _keys[it.id]?.currentState;
      if (st == null) continue;
      try {
        final Map<String, dynamic>? r = await st.buildResult();
        if (r != null) results.add(r);
      } catch (e) {
        debugPrint('MultiMediaPreview buildResult error: $e');
      }
    }
    if (!mounted) return;
    if (results.isEmpty) {
      setState(() => _sending = false);
      _showToast('تعذر تجهيز الوسائط للإرسال');
      return;
    }
    final dynamic out = results.length == 1 ? results.first : <String, dynamic>{'items': results};
    // نعيد النتيجة من المعاينة أولاً، وتغلق الكاميرا نفسها بعد استلامها.
    nav.pop(out);
  }

  // ---------- شريط المصغّرات ----------
  Widget _buildStrip() {
    if (_items.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 56,
        child: Center(
          child: ListView.separated(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => _stripTile(i),
          ),
        ),
      ),
    );
  }

  Widget _stripTile(int i) {
    final PreviewMediaItem it = _items[i];
    final bool sel = i == _cur;
    Widget img;
    if (it.isVideo) {
      final String? tp = _vidThumbs[it.id];
      img = tp != null
          ? Image.file(File(tp), key: ValueKey(tp), fit: BoxFit.cover)
          : Container(color: const Color(0xFF1B1B1B));
    } else {
      final File f = _keys[it.id]?.currentState?.previewFile ?? it.file;
      img = Image.file(
        f,
        key: ValueKey(f.path),
        fit: BoxFit.cover,
        cacheWidth: 140,
        errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1B1B1B)),
      );
    }
    return GestureDetector(
      onTap: () {
        if (sel) {
          _removeAt(i);
        } else {
          _select(i);
        }
      },
      child: Container(
        width: 44,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: sel ? Colors.white : Colors.transparent, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              img,
              if (it.isVideo && !sel)
                const Positioned(
                  left: 3,
                  bottom: 3,
                  child: Icon(Icons.videocam_rounded, color: Colors.white, size: 14, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                ),
              if (sel)
                Container(
                  color: const Color(0x73000000),
                  child: const Center(child: Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChild(PreviewMediaItem it) {
    return CaptionPreviewScreen(
      key: _keys[it.id],
      file: it.file,
      isVideo: it.isVideo,
      duration: it.duration,
      recipientName: widget.recipientName,
      embedded: true,
      stripBuilder: _buildStrip,
      onAddMore: _addMore,
      onSendAll: _sendAll,
      onCloseRequest: _requestClose,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenH = MediaQuery.of(context).size.height;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _requestClose();
        },
        child: Material(
          color: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: _cur,
                  children: [for (final PreviewMediaItem it in _items) _buildChild(it)],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: screenH * 0.483,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _toastOn ? 1 : 0,
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
              if (_sending)
                Positioned.fill(
                  child: AbsorbPointer(
                    child: Container(
                      color: Colors.black54,
                      child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}