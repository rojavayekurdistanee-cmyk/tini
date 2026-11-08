import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// شاشة القص والتدوير (تصميم واتساب).
/// تُفتح من زر التدوير في الأزرار العلوية لشاشة المعاينة.
/// ترجع: File جديد (بعد القص/التدوير)، أو null عند الإلغاء أو عدم وجود تغيير.
class CropRotateScreen extends StatefulWidget {
  final File file;
  const CropRotateScreen({super.key, required this.file});

  /// انتقال fade مثل بقية محررات الصورة
  static Route<File?> route(File file) {
    return PageRouteBuilder<File?>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, __, ___) => CropRotateScreen(file: file),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  State<CropRotateScreen> createState() => _CropRotateScreenState();
}

class _CropRotateScreenState extends State<CropRotateScreen> with SingleTickerProviderStateMixin {
  // ---------- ثوابت التصميم (مقاسة من تسجيل واتساب) ----------
  static const Color _green = Color(0xFF21C063);
  static const Color _bg = Color(0xFF030508); // خلفية منطقة الصورة
  static const Color _barBg = Color(0xFF080F11); // خلفية الشريط السفلي
  static const double _sideMargin = 6; // هامش الصورة يمين/يسار
  static const double _topGap = 16; // فراغ فوق الصورة تحت شريط الحالة
  static const double _barH = 72; // ارتفاع الشريط السفلي
  static const double _slop = 30; // مساحة اللمس حول حواف الإطار
  static const double _minSide = 56; // أصغر مقاس للإطار
  static const Duration _rotDur = Duration(milliseconds: 340);

  ui.Image? _img;
  int _turns = 0; // عدد اللفّات 90° عكس عقارب الساعة (المثبّتة)
  Rect _crop = const Rect.fromLTRB(0, 0, 1, 1); // إطار القص نسبةً لأبعاد الصورة بعد التدوير
  late final AnimationController _rot;
  bool _rotating = false;
  bool _busy = false;

  // حالة السحب
  Offset _dragStart = Offset.zero;
  Rect _dragStartRect = Rect.zero;
  bool _dl = false, _dt = false, _dr = false, _db = false;

  @override
  void initState() {
    super.initState();
    _rot = AnimationController(vsync: this, duration: _rotDur);
    _load();
  }

  Future<void> _load() async {
    try {
      final Uint8List bytes = await widget.file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _img = frame.image);
    } catch (e) {
      debugPrint('CropRotateScreen load error: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _rot.dispose();
    _img?.dispose();
    super.dispose();
  }

  // ---------- هندسة العرض ----------
  /// أبعاد الصورة بعد التدوير المثبّت
  Size get _orient {
    final i = _img!;
    final w = i.width.toDouble(), h = i.height.toDouble();
    return _turns.isOdd ? Size(h, w) : Size(w, h);
  }

  /// مستطيل الصورة على الشاشة (داخل صندوق المنطقة)
  Rect _imageRect(Size box) {
    final o = _orient;
    final s = _fitScale(o, 0, box);
    return Rect.fromCenter(center: box.center(Offset.zero), width: o.width * s, height: o.height * s);
  }

  Rect _cropRect(Size box) {
    final r = _imageRect(box);
    return Rect.fromLTRB(
      r.left + _crop.left * r.width,
      r.top + _crop.top * r.height,
      r.left + _crop.right * r.width,
      r.top + _crop.bottom * r.height,
    );
  }

  // ---------- السحب (تغيير حجم الإطار) ----------
  void _onPanStart(DragStartDetails d, Size box) {
    if (_img == null || _rotating || _busy) return;
    final p = d.localPosition;
    final r = _cropRect(box);
    final inY = p.dy >= r.top - _slop && p.dy <= r.bottom + _slop;
    final inX = p.dx >= r.left - _slop && p.dx <= r.right + _slop;
    bool l = inY && (p.dx - r.left).abs() <= _slop;
    bool rr = inY && (p.dx - r.right).abs() <= _slop;
    bool t = inX && (p.dy - r.top).abs() <= _slop;
    bool b = inX && (p.dy - r.bottom).abs() <= _slop;
    if (l && rr) {
      if ((p.dx - r.left).abs() <= (p.dx - r.right).abs()) {
        rr = false;
      } else {
        l = false;
      }
    }
    if (t && b) {
      if ((p.dy - r.top).abs() <= (p.dy - r.bottom).abs()) {
        b = false;
      } else {
        t = false;
      }
    }
    _dl = l;
    _dr = rr;
    _dt = t;
    _db = b;
    _dragStart = p;
    _dragStartRect = r;
    if (l || rr || t || b) HapticFeedback.selectionClick();
  }

  void _onPanUpdate(DragUpdateDetails d, Size box) {
    if (!(_dl || _dr || _dt || _db)) return;
    final img = _imageRect(box);
    final dx = d.localPosition.dx - _dragStart.dx;
    final dy = d.localPosition.dy - _dragStart.dy;
    final s = _dragStartRect;
    double left = s.left, right = s.right, top = s.top, bottom = s.bottom;
    if (_dl) left = (s.left + dx).clamp(img.left, s.right - _minSide).toDouble();
    if (_dr) right = (s.right + dx).clamp(s.left + _minSide, img.right).toDouble();
    if (_dt) top = (s.top + dy).clamp(img.top, s.bottom - _minSide).toDouble();
    if (_db) bottom = (s.bottom + dy).clamp(s.top + _minSide, img.bottom).toDouble();
    setState(() {
      _crop = Rect.fromLTRB(
        (left - img.left) / img.width,
        (top - img.top) / img.height,
        (right - img.left) / img.width,
        (bottom - img.top) / img.height,
      );
    });
  }

  void _onPanEnd() {
    _dl = _dr = _dt = _db = false;
  }

  // ---------- التدوير 90° عكس عقارب الساعة مع أنيميشن ----------
  Future<void> _rotate() async {
    if (_img == null || _rotating || _busy) return;
    HapticFeedback.selectionClick();
    setState(() => _rotating = true);
    await _rot.forward(from: 0);
    if (!mounted) return;
    setState(() {
      // تثبيت اللفّة: الإطار يدور مع الصورة
      final c = _crop;
      _crop = Rect.fromLTRB(c.top, 1 - c.right, c.bottom, 1 - c.left);
      _turns = (_turns + 1) % 4;
      _rot.value = 0;
      _rotating = false;
    });
  }

  // ---------- حفظ النتيجة ----------
  bool get _unchanged =>
      _turns == 0 &&
      _crop.left <= 0.0005 &&
      _crop.top <= 0.0005 &&
      _crop.right >= 0.9995 &&
      _crop.bottom >= 0.9995;

  Future<void> _done() async {
    if (_busy || _rotating) return;
    final img = _img;
    if (img == null || _unchanged) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    try {
      final o = _orient;
      final int cl = (_crop.left * o.width).round();
      final int ct = (_crop.top * o.height).round();
      final int cw = math.max(1, (_crop.right * o.width).round() - cl);
      final int ch = math.max(1, (_crop.bottom * o.height).round() - ct);
      final double k = math.min(1.0, 2048 / math.max(cw, ch));
      final int ow = math.max(1, (cw * k).round());
      final int oh = math.max(1, (ch * k).round());

      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()));
      canvas.scale(k);
      canvas.translate(-cl.toDouble(), -ct.toDouble());
      canvas.translate(o.width / 2, o.height / 2);
      canvas.rotate(-_turns * math.pi / 2);
      canvas.drawImage(
        img,
        Offset(-img.width / 2, -img.height / 2),
        Paint()..filterQuality = FilterQuality.high,
      );
      final out = await rec.endRecording().toImage(ow, oh);
      final bd = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (bd == null) throw Exception('encode failed');
      Uint8List bytes = bd.buffer.asUint8List();
      String ext = 'png';
      try {
        final jpg = await FlutterImageCompress.compressWithList(
          bytes,
          format: CompressFormat.jpeg,
          quality: 92,
          minWidth: ow,
          minHeight: oh,
        );
        if (jpg.isNotEmpty) {
          bytes = jpg;
          ext = 'jpg';
        }
      } catch (_) {}
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/crop_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await f.writeAsBytes(bytes);
      if (!mounted) return;
      Navigator.pop(context, f);
    } catch (e) {
      debugPrint('CropRotateScreen export error: $e');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ الصورة', style: TextStyle(fontFamily: 'Tajawal'))),
        );
      }
    }
  }

  // ---------- واجهة ----------
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: _bg,
          body: Column(
            children: [
              SizedBox(height: mq.padding.top + _topGap),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _sideMargin),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final box = Size(c.maxWidth, c.maxHeight);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) => _onPanStart(d, box),
                        onPanUpdate: (d) => _onPanUpdate(d, box),
                        onPanEnd: (_) => _onPanEnd(),
                        onPanCancel: _onPanEnd,
                        child: _img == null
                            ? const SizedBox.expand()
                            : CustomPaint(
                                size: Size.infinite,
                                painter: _CropPainter(
                                  img: _img!,
                                  turns: _turns,
                                  crop: _crop,
                                  rot: _rot,
                                ),
                              ),
                      );
                    },
                  ),
                ),
              ),
              _buildBar(mq.padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBar(double bottomInset) {
    const TextStyle txt = TextStyle(color: _green, fontFamily: 'Tajawal', fontSize: 15.5, fontWeight: FontWeight.w500);
    return Container(
      height: _barH + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      color: _barBg,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _done,
              child: Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _green))
                      : const Text('تم', style: txt),
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _rotate,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _rotating ? const Color(0x33FFFFFF) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.rotate_90_degrees_ccw_rounded, color: Colors.white, size: 26),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!_busy) Navigator.pop(context);
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 24),
                child: const Align(
                  alignment: Alignment.centerRight,
                  child: Text('إلغاء', style: txt),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// أكبر مقياس يجعل الصورة (بعد تدويرها بزاوية phi) تدخل بالكامل داخل المنطقة.
double _fitScale(Size o, double phi, Size box) {
  final c = math.cos(phi).abs();
  final s = math.sin(phi).abs();
  final bw = o.width * c + o.height * s;
  final bh = o.width * s + o.height * c;
  return math.min(box.width / bw, box.height / bh);
}

class _CropPainter extends CustomPainter {
  final ui.Image img;
  final int turns;
  final Rect crop;
  final AnimationController rot;

  _CropPainter({required this.img, required this.turns, required this.crop, required this.rot})
      : super(repaint: rot);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = img.width.toDouble(), h = img.height.toDouble();
    final Size o = turns.isOdd ? Size(h, w) : Size(w, h);
    // زاوية الأنيميشن الإضافية (0 → 90° عكس عقارب الساعة)
    final double phi = Curves.easeInOutCubic.transform(rot.value) * math.pi / 2;
    final double s = _fitScale(o, phi, size);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-phi);
    canvas.scale(s);

    // الصورة (بعد التدوير المثبّت)
    canvas.save();
    canvas.rotate(-turns * math.pi / 2);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, w, h),
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    final Rect imgR = Rect.fromCenter(center: Offset.zero, width: o.width, height: o.height);
    final Rect cr = Rect.fromLTRB(
      imgR.left + crop.left * o.width,
      imgR.top + crop.top * o.height,
      imgR.left + crop.right * o.width,
      imgR.top + crop.bottom * o.height,
    );

    // تعتيم خارج الإطار
    final Path dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(imgR),
      Path()..addRect(cr),
    );
    canvas.drawPath(dim, Paint()..color = const Color(0x8C000000));

    // الشبكة 3×3
    final double hair = 1.0 / s;
    final Paint grid = Paint()
      ..color = const Color(0x8CFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = hair;
    for (int i = 1; i < 3; i++) {
      final double x = cr.left + cr.width * i / 3;
      final double y = cr.top + cr.height * i / 3;
      canvas.drawLine(Offset(x, cr.top), Offset(x, cr.bottom), grid);
      canvas.drawLine(Offset(cr.left, y), Offset(cr.right, y), grid);
    }
    // حدّ رفيع للإطار
    canvas.drawRect(cr, grid);

    // زوايا الإطار + علامات منتصف الأضلاع
    final double th = 3.0 / s;
    final double len = 24.0 / s;
    final double midLen = 28.0 / s;
    final Paint br = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = th
      ..strokeCap = StrokeCap.butt;
    final double hf = th / 2;
    final Rect ir = cr.deflate(hf); // الخط يُرسم داخل الإطار
    final Path p = Path()
      // أعلى اليسار
      ..moveTo(ir.left, ir.top + len)
      ..lineTo(ir.left, ir.top)
      ..lineTo(ir.left + len, ir.top)
      // أعلى اليمين
      ..moveTo(ir.right - len, ir.top)
      ..lineTo(ir.right, ir.top)
      ..lineTo(ir.right, ir.top + len)
      // أسفل اليمين
      ..moveTo(ir.right, ir.bottom - len)
      ..lineTo(ir.right, ir.bottom)
      ..lineTo(ir.right - len, ir.bottom)
      // أسفل اليسار
      ..moveTo(ir.left + len, ir.bottom)
      ..lineTo(ir.left, ir.bottom)
      ..lineTo(ir.left, ir.bottom - len)
      // منتصف الأضلاع
      ..moveTo(cr.center.dx - midLen / 2, ir.top)
      ..lineTo(cr.center.dx + midLen / 2, ir.top)
      ..moveTo(cr.center.dx - midLen / 2, ir.bottom)
      ..lineTo(cr.center.dx + midLen / 2, ir.bottom)
      ..moveTo(ir.left, cr.center.dy - midLen / 2)
      ..lineTo(ir.left, cr.center.dy + midLen / 2)
      ..moveTo(ir.right, cr.center.dy - midLen / 2)
      ..lineTo(ir.right, cr.center.dy + midLen / 2);
    canvas.drawPath(p, br);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.img != img || old.turns != turns || old.crop != crop;
}