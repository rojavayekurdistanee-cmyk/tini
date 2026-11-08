import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// أدوات الرسم (بنفس ترتيب واتساب من اليسار لليمين):
/// تمويه (بكسلة) - قلم عريض - قلم متوسط - قلم رفيع
enum DrawTool { pixelate, thick, medium, thin }

/// ضربة رسم واحدة. النقاط مخزّنة بإحداثيات نسبية (0..1) داخل الصورة
/// حتى يكون الرسم نفسه على الشاشة وعلى الصورة المحفوظة بأي دقّة.
class DrawStroke {
  final DrawTool tool;
  final Color color;
  final List<Offset> points;
  DrawStroke({required this.tool, required this.color, List<Offset>? points}) : points = points ?? [];
}

/// نتيجة المحرر: file = الصورة بعد الرسم (null إذا ما في رسم)، strokes = الرسومات لمتابعة التعديل لاحقاً.
class PhotoDrawResult {
  final File? file;
  final List<DrawStroke> strokes;
  PhotoDrawResult(this.file, this.strokes);
}

// عرض الضربة كنسبة من عرض الصورة (مقاسة من لقطات واتساب)
double _widthFrac(DrawTool t) {
  switch (t) {
    case DrawTool.thick:
      return 0.040;
    case DrawTool.medium:
      return 0.0216;
    case DrawTool.thin:
      return 0.0085;
    case DrawTool.pixelate:
      return 0.085;
  }
}

// حجم مربع البكسلة كنسبة من عرض الصورة
const double _pixelBlockFrac = 0.022;

Path _smoothPath(List<Offset> p) {
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  if (p.length == 2) {
    path.lineTo(p[1].dx, p[1].dy);
    return path;
  }
  for (int i = 1; i < p.length - 1; i++) {
    final mid = (p[i] + p[i + 1]) / 2;
    path.quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(p.last.dx, p.last.dy);
  return path;
}

void _drawStroke(Canvas canvas, List<Offset> pts, double w, Color color) {
  final paint = Paint()
    ..color = color
    ..isAntiAlias = true;
  if (pts.length == 1) {
    canvas.drawCircle(pts[0], w / 2, paint);
    return;
  }
  paint
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(_smoothPath(pts), paint);
}

/// نفس الدالة تُستخدم للعرض على الشاشة وللتصدير، فيطلع الناتج مطابقاً لما تراه.
void paintDrawScene(Canvas canvas, Rect dst, ui.Image base, ui.Image? pix, List<DrawStroke> strokes) {
  canvas.save();
  canvas.clipRect(dst);
  canvas.drawImageRect(
    base,
    Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
    dst,
    Paint()..filterQuality = FilterQuality.high,
  );
  for (final s in strokes) {
    if (s.points.isEmpty) continue;
    final pts = s.points.map((p) => Offset(dst.left + p.dx * dst.width, dst.top + p.dy * dst.height)).toList();
    final w = _widthFrac(s.tool) * dst.width;
    if (s.tool == DrawTool.pixelate) {
      if (pix == null) continue;
      canvas.saveLayer(dst, Paint());
      _drawStroke(canvas, pts, w, Colors.white);
      canvas.drawImageRect(
        pix,
        Rect.fromLTWH(0, 0, pix.width.toDouble(), pix.height.toDouble()),
        dst,
        Paint()
          ..blendMode = BlendMode.srcIn
          ..filterQuality = FilterQuality.none,
      );
      canvas.restore();
    } else {
      _drawStroke(canvas, pts, w, s.color);
    }
  }
  canvas.restore();
}

class PhotoDrawEditor extends StatefulWidget {
  final File file;
  final List<DrawStroke> initialStrokes;
  const PhotoDrawEditor({super.key, required this.file, this.initialStrokes = const []});

  @override
  State<PhotoDrawEditor> createState() => _PhotoDrawEditorState();
}

class _PhotoDrawEditorState extends State<PhotoDrawEditor> {
  static const Color _btnBg = Color(0xFF383C3F);
  static const Color _selBg = Color(0xFF454749);
  static const double _defaultT = 0.5725; // أخضر فاتح مثل واتساب

  ui.Image? _base;
  ui.Image? _pix;
  late final List<DrawStroke> _strokes;
  DrawStroke? _current;
  int? _pointerId;
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  DrawTool _tool = DrawTool.medium;
  double _t = _defaultT;
  bool _dragSlider = false;
  bool _busy = false;
  Rect _imgRect = Rect.zero;

  Color get _color => _colorAt(_t);

  @override
  void initState() {
    super.initState();
    _strokes = List<DrawStroke>.of(widget.initialStrokes);
    _load();
  }

  Future<void> _load() async {
    try {
      final Uint8List bytes = await widget.file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final base = frame.image;
      final pix = await _makePixelated(base);
      if (!mounted) {
        base.dispose();
        pix.dispose();
        return;
      }
      setState(() {
        _base = base;
        _pix = pix;
      });
    } catch (e) {
      debugPrint('PhotoDrawEditor load error: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<ui.Image> _makePixelated(ui.Image base) async {
    final int bw = math.max(8, (1 / _pixelBlockFrac).round());
    final int bh = math.max(8, (bw * base.height / base.width).round());
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImageRect(
      base,
      Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
      Rect.fromLTWH(0, 0, bw.toDouble(), bh.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    return rec.endRecording().toImage(bw, bh);
  }

  /// شريط الألوان: أسود ← أبيض ← أحمر ← طيف الألوان ← وردي
  static Color _colorAt(double t) {
    if (t <= 0.12) {
      final v = (t / 0.12 * 255).round().clamp(0, 255);
      return Color.fromARGB(255, v, v, v);
    }
    if (t <= 0.235) {
      final k = (t - 0.12) / (0.235 - 0.12);
      return Color.lerp(Colors.white, HSVColor.fromAHSV(1, 0, 0.8, 1).toColor(), k)!;
    }
    final hue = ((t - 0.235) / (1 - 0.235) * 340).clamp(0.0, 340.0);
    return HSVColor.fromAHSV(1, hue, 0.8, 1).toColor();
  }

  Offset _norm(Offset p) {
    final r = _imgRect;
    return Offset(
      ((p.dx - r.left) / r.width).clamp(0.0, 1.0),
      ((p.dy - r.top) / r.height).clamp(0.0, 1.0),
    );
  }

  void _down(PointerDownEvent e) {
    if (_busy || _base == null || _current != null) return;
    if (!_imgRect.contains(e.localPosition)) return;
    _pointerId = e.pointer;
    _current = DrawStroke(tool: _tool, color: _color)..points.add(_norm(e.localPosition));
    _tick.value++;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointerId || _current == null) return;
    final n = _norm(e.localPosition);
    final last = _current!.points.last;
    if ((n - last).distance < 0.0008) return;
    _current!.points.add(n);
    _tick.value++;
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointerId) return;
    final s = _current;
    _current = null;
    _pointerId = null;
    if (s != null) {
      setState(() => _strokes.add(s));
    }
    _tick.value++;
  }

  void _undo() {
    if (_strokes.isEmpty || _busy) return;
    HapticFeedback.selectionClick();
    setState(() => _strokes.removeLast());
    _tick.value++;
  }

  void _setSliderFromDy(double dy, double height) {
    setState(() => _t = (dy / height).clamp(0.0, 1.0));
  }

  Future<void> _done() async {
    if (_busy) return;
    final base = _base;
    if (base == null) {
      Navigator.pop(context);
      return;
    }
    if (_strokes.isEmpty) {
      Navigator.pop(context, PhotoDrawResult(null, const []));
      return;
    }
    setState(() => _busy = true);
    try {
      final double scale = math.min(1.0, 2048 / math.max(base.width, base.height));
      final int ow = math.max(1, (base.width * scale).round());
      final int oh = math.max(1, (base.height * scale).round());
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      paintDrawScene(c, Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()), base, _pix, _strokes);
      final img = await rec.endRecording().toImage(ow, oh);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
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
      final f = File('${dir.path}/draw_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await f.writeAsBytes(bytes);
      if (!mounted) return;
      Navigator.pop(context, PhotoDrawResult(f, List<DrawStroke>.of(_strokes)));
    } catch (e) {
      debugPrint('PhotoDrawEditor export error: $e');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ الرسم', style: TextStyle(fontFamily: 'Tajawal'))),
        );
      }
    }
  }

  @override
  void dispose() {
    _base?.dispose();
    _pix?.dispose();
    _tick.dispose();
    super.dispose();
  }

  Rect _fitRect(Rect area, ui.Image img) {
    final double s = math.min(area.width / img.width, area.height / img.height);
    final double w = img.width * s;
    final double h = img.height * s;
    return Rect.fromLTWH(area.left + (area.width - w) / 2, area.top + (area.height - h) / 2, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final double w = mq.size.width;
    final double h = mq.size.height;
    final double u = w / 411; // وحدة قياس نسبية (≈ dp على شاشة 411)
    final double topInset = mq.padding.top + 36 * u;
    final double bottomInset = mq.padding.bottom + 63 * u;
    final base = _base;
    if (base != null) {
      _imgRect = _fitRect(Rect.fromLTWH(0, topInset, w, h - topInset - bottomInset), base);
    }

    final bool pix = _tool == DrawTool.pixelate;
    final double btn = 44 * u;
    final double sliderTop = mq.padding.top + 78 * u;
    final double sliderH = 229 * u;
    final double sliderX = 55 * u;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // لوح الرسم
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                child: CustomPaint(
                  painter: _ScenePainter(
                    base: base,
                    pix: _pix,
                    strokes: _strokes,
                    getCurrent: () => _current,
                    rect: _imgRect,
                    repaint: _tick,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            // زر القلم (لونه = اللون المختار) + زر التراجع
            Positioned(
              top: mq.padding.top + 10 * u,
              left: 14 * u,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _done,
                    child: Container(
                      width: btn,
                      height: btn,
                      decoration: BoxDecoration(color: pix ? _btnBg : _color, shape: BoxShape.circle),
                      child: Icon(Icons.edit_rounded, color: Colors.white, size: 21 * u),
                    ),
                  ),
                  if (_strokes.isNotEmpty) ...[
                    SizedBox(width: 6 * u),
                    GestureDetector(
                      onTap: _undo,
                      child: Container(
                        width: btn,
                        height: btn,
                        decoration: const BoxDecoration(color: _btnBg, shape: BoxShape.circle),
                        child: Icon(Icons.undo_rounded, color: Colors.white, size: 23 * u),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // زر تم
            Positioned(
              top: mq.padding.top + 15 * u,
              right: 13 * u,
              child: GestureDetector(
                onTap: _done,
                child: Container(
                  height: 34 * u,
                  padding: EdgeInsets.symmetric(horizontal: 17 * u),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _btnBg, borderRadius: BorderRadius.circular(17 * u)),
                  child: Text('تم', style: TextStyle(color: Colors.white, fontSize: 15.5 * u, fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            // شريط الألوان العمودي
            Positioned(
              top: sliderTop,
              left: sliderX - 15 * u,
              width: 40 * u,
              height: sliderH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _setSliderFromDy(d.localPosition.dy, sliderH),
                onVerticalDragStart: (d) {
                  _dragSlider = true;
                  _setSliderFromDy(d.localPosition.dy, sliderH);
                },
                onVerticalDragUpdate: (d) => _setSliderFromDy(d.localPosition.dy, sliderH),
                onVerticalDragEnd: (_) => setState(() => _dragSlider = false),
                onVerticalDragCancel: () => setState(() => _dragSlider = false),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 15 * u,
                      top: 0,
                      bottom: 0,
                      width: 10 * u,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5 * u),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [for (int i = 0; i <= 40; i++) _colorAt(i / 40)],
                          ),
                        ),
                      ),
                    ),
                    if (_dragSlider)
                      Positioned(
                        left: 20 * u - 13 * u,
                        top: _t * sliderH - 13 * u,
                        child: Container(
                          width: 26 * u,
                          height: 26 * u,
                          decoration: BoxDecoration(
                            color: _color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // شريط الأدوات السفلي
            Positioned(
              left: 0,
              right: 0,
              bottom: mq.padding.bottom + 30 * u - 25.5 * u,
              child: Center(
                child: SizedBox(
                  width: w * 0.9,
                  height: 51 * u,
                  child: Row(
                    children: [
                      for (final t in DrawTool.values)
                        Expanded(
                          child: Center(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _tool = t);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 51 * u,
                                height: 51 * u,
                                decoration: BoxDecoration(
                                  color: _tool == t ? _selBg : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: CustomPaint(
                                    size: Size(30 * u, 30 * u),
                                    painter: _ToolIconPainter(t),
                                  ),
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
            if (_base == null || _busy)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: _busy ? Colors.black45 : Colors.transparent,
                    child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  final ui.Image? base;
  final ui.Image? pix;
  final List<DrawStroke> strokes;
  final DrawStroke? Function() getCurrent;
  final Rect rect;

  _ScenePainter({
    required this.base,
    required this.pix,
    required this.strokes,
    required this.getCurrent,
    required this.rect,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final b = base;
    if (b == null) return;
    final cur = getCurrent();
    paintDrawScene(canvas, rect, b, pix, cur == null ? strokes : [...strokes, cur]);
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => true;
}

/// أيقونات الأدوات (مرسومة بالكود): تمويه / عريض / متوسط / رفيع (مفرّغ)
class _ToolIconPainter extends CustomPainter {
  final DrawTool tool;
  _ToolIconPainter(this.tool);

  Path _squiggle(Size s) {
    final w = s.width, h = s.height;
    final p = Path()..moveTo(0.14 * w, 0.82 * h);
    p.cubicTo(0.40 * w, 0.98 * h, 0.90 * w, 0.82 * h, 0.62 * w, 0.58 * h);
    p.cubicTo(0.45 * w, 0.44 * h, 0.24 * w, 0.52 * h, 0.40 * w, 0.34 * h);
    p.cubicTo(0.54 * w, 0.18 * h, 0.78 * w, 0.22 * h, 0.90 * w, 0.10 * h);
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (tool == DrawTool.pixelate) {
      final cell = size.width / 6;
      final paint = Paint()..color = Colors.white;
      for (int r = 0; r < 6; r++) {
        for (int c = 0; c < 6; c++) {
          if ((r - c).abs() <= 1 && (r + c).isEven) {
            canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell * 0.92, cell * 0.92), paint);
          }
        }
      }
      return;
    }
    final path = _squiggle(size);
    final double sw = tool == DrawTool.thick ? 6.4 : (tool == DrawTool.medium ? 4.4 : 3.6);
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (tool == DrawTool.thin) {
      // شكل مفرّغ (حدود فقط)
      canvas.saveLayer(Offset.zero & size, Paint());
      canvas.drawPath(path, stroke..strokeWidth = 7);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.clear,
      );
      canvas.restore();
    } else {
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _ToolIconPainter old) => old.tool != tool;
}