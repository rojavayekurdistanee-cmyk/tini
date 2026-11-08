import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// نمط خلفية النص: 0 بدون خلفية (لون النص = الشريط) - 1 مربع ممتلئ - 2 مربع نصف شفاف
const int kTextBgModes = 3;

/// حجم الخط كنسبة من عرض الصورة
const double _kTextSizeFrac = 0.08;

class TitiTextFont {
  final String? family;
  final FontWeight weight;
  final FontStyle style;
  const TitiTextFont(this.family, this.weight, [this.style = FontStyle.normal]);
}

/// 8 خطوط (صف "Aa" فوق الكيبورد). غيّر/زِد عليها لاحقاً بسهولة.
const List<TitiTextFont> kTitiTextFonts = [
  TitiTextFont('Tajawal', FontWeight.w500),
  TitiTextFont('Tajawal', FontWeight.w900),
  TitiTextFont('serif', FontWeight.w700),
  TitiTextFont('serif', FontWeight.w400, FontStyle.italic),
  TitiTextFont('monospace', FontWeight.w600),
  TitiTextFont('cursive', FontWeight.w400),
  TitiTextFont('sans-serif-condensed', FontWeight.w700),
  TitiTextFont('casual', FontWeight.w400),
];

/// نص واحد على الصورة. dy = موقعه العمودي كنسبة (0..1) من ارتفاع الصورة.
class TextOverlay {
  final String text;
  final int bgMode;
  final Color color;
  final int fontIndex;
  final TextAlign align;
  // الموقع (نسبة من عرض/ارتفاع الصورة) + التكبير + التدوير (راديان): قابلة للتعديل بالسحب
  double dx;
  double dy;
  double scale;
  double rotation;
  TextOverlay({
    required this.text,
    required this.bgMode,
    required this.color,
    required this.fontIndex,
    required this.align,
    this.dx = 0.5,
    this.dy = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
  });
}

bool _hasArabic(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

Color _contrast(Color c) => c.computeLuminance() > 0.55 ? Colors.black : Colors.white;

/// شريط الألوان: أسود ← أبيض ← أحمر ← طيف الألوان (نفس شريط الرسم)
Color textColorAt(double t) {
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

TextStyle _styleFor(TextOverlay t, double fs) {
  final f = kTitiTextFonts[t.fontIndex.clamp(0, kTitiTextFonts.length - 1)];
  final Color txt = t.bgMode == 0 ? t.color : _contrast(t.color);
  return TextStyle(
    color: txt,
    fontSize: fs,
    fontFamily: f.family,
    fontFamilyFallback: const ['Tajawal'],
    fontWeight: f.weight,
    fontStyle: f.style,
    height: 1.25,
  );
}

TextPainter _layoutText(TextOverlay t, double fs, double maxW) {
  return TextPainter(
    text: TextSpan(text: t.text, style: _styleFor(t, fs)),
    textDirection: _hasArabic(t.text) ? TextDirection.rtl : TextDirection.ltr,
    textAlign: t.align,
  )..layout(maxWidth: maxW);
}

/// حجم مربع النص (قبل التكبير والتدوير) على صورة بحجم size.
Size textOverlayBox(Size size, TextOverlay t) {
  final double fs = size.width * _kTextSizeFrac;
  final tp = _layoutText(t, fs, size.width * 0.8);
  final double padH = t.bgMode == 0 ? 0 : fs * 0.5;
  final double padV = t.bgMode == 0 ? 0 : fs * 0.25;
  return Size(tp.width + padH * 2, tp.height + padV * 2);
}

/// نفس الدالة للعرض على الشاشة وللتصدير: ترسم نصاً واحداً على كانفس بحجم الصورة.
void paintTextOverlay(Canvas canvas, Size size, TextOverlay t) {
  final double fs = size.width * _kTextSizeFrac;
  final tp = _layoutText(t, fs, size.width * 0.8);
  final double padH = t.bgMode == 0 ? 0 : fs * 0.5;
  final double padV = t.bgMode == 0 ? 0 : fs * 0.25;
  final rect = Rect.fromCenter(
    center: Offset.zero,
    width: tp.width + padH * 2,
    height: tp.height + padV * 2,
  );
  canvas.save();
  canvas.translate(t.dx * size.width, t.dy * size.height);
  canvas.rotate(t.rotation);
  canvas.scale(t.scale);
  if (t.bgMode != 0) {
    final Color bg = t.bgMode == 1 ? t.color : t.color.withOpacity(0.6);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(fs * 0.3)), Paint()..color = bg);
  }
  tp.paint(canvas, Offset(rect.left + padH, rect.top + padV));
  canvas.restore();
}

/// يرسم كل النصوص فوق الصورة ويرجع ملف جديد (الأصل ما يتغير).
Future<File?> renderTextsOnto(File base, List<TextOverlay> texts) async {
  try {
    final Uint8List bytes = await base.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final img = (await codec.getNextFrame()).image;
    final double scale = math.min(1.0, 2048 / math.max(img.width, img.height));
    final int ow = math.max(1, (img.width * scale).round());
    final int oh = math.max(1, (img.height * scale).round());
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    for (final t in texts) {
      paintTextOverlay(c, Size(ow.toDouble(), oh.toDouble()), t);
    }
    final out = await rec.endRecording().toImage(ow, oh);
    final bd = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    img.dispose();
    if (bd == null) return null;
    Uint8List data = bd.buffer.asUint8List();
    String ext = 'png';
    try {
      final jpg = await FlutterImageCompress.compressWithList(
        data,
        format: CompressFormat.jpeg,
        quality: 92,
        minWidth: ow,
        minHeight: oh,
      );
      if (jpg.isNotEmpty) {
        data = jpg;
        ext = 'jpg';
      }
    } catch (_) {}
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/text_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await f.writeAsBytes(data);
    return f;
  } catch (e) {
    debugPrint('renderTextsOnto error: $e');
    return null;
  }
}

/// شاشة كتابة النص (مثل واتساب): خلفية الصورة معتّمة، زر نمط الخلفية، زر المحاذاة،
/// شريط الألوان، صف الخطوط فوق الكيبورد، وزر "تم". ترجع TextOverlay (أو null).
class PhotoTextEditor extends StatefulWidget {
  final File file;
  const PhotoTextEditor({super.key, required this.file});

  @override
  State<PhotoTextEditor> createState() => _PhotoTextEditorState();
}

class _PhotoTextEditorState extends State<PhotoTextEditor> {
  static const Color _btnBg = Color(0xFF383C3F);

  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  int _bgMode = 1;
  double _t = 0.12; // أبيض
  int _font = 0;
  int _alignIdx = 0; // 0 وسط - 1 يسار - 2 يمين
  bool _dragSlider = false;

  static const List<TextAlign> _aligns = [TextAlign.center, TextAlign.left, TextAlign.right];
  static const List<IconData> _alignIcons = [
    Icons.format_align_center_rounded,
    Icons.format_align_left_rounded,
    Icons.format_align_right_rounded,
  ];

  Color get _color => textColorAt(_t);

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _finish() {
    final txt = _ctrl.text.trim();
    _focus.unfocus();
    if (txt.isEmpty) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(
      context,
      TextOverlay(text: txt, bgMode: _bgMode, color: _color, fontIndex: _font, align: _aligns[_alignIdx]),
    );
  }

  Widget _topBtn(Widget child, VoidCallback onTap, {double size = 44}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: _btnBg, shape: BoxShape.circle),
        child: Center(child: child),
      ),
    );
  }

  /// أيقونة نمط الخلفية: A داخل مربع (فاضي / ممتلئ / نصف شفاف)
  Widget _bgIcon() {
    final bool none = _bgMode == 0;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _bgMode == 1 ? Colors.white : (_bgMode == 2 ? Colors.white54 : Colors.transparent),
        border: Border.all(color: Colors.white, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'A',
        style: TextStyle(
          color: none ? Colors.white : Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final double w = mq.size.width;
    final double h = mq.size.height;
    final double kb = mq.viewInsets.bottom;
    const double fontRowH = 56;
    final double topPad = mq.padding.top;
    final double sliderTop = topPad + 74;
    final double avail = h - kb - fontRowH - sliderTop - 20;
    final double sliderH = avail.clamp(80.0, h * 0.32).toDouble();
    final double fs = w * _kTextSizeFrac;

    final overlay = TextOverlay(
      text: _ctrl.text,
      bgMode: _bgMode,
      color: _color,
      fontIndex: _font,
      align: _aligns[_alignIdx],
    );
    final TextStyle style = _styleFor(overlay, fs);
    final bool box = _bgMode != 0;
    final Color boxColor = _bgMode == 1 ? _color : _color.withOpacity(0.6);
    final TextDirection dir = _hasArabic(_ctrl.text) ? TextDirection.rtl : TextDirection.ltr;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // خلفية الصورة المعتّمة
            Positioned.fill(
              child: Image.file(widget.file, fit: BoxFit.cover),
            ),
            Positioned.fill(child: Container(color: const Color(0x99000000))),
            // مساحة الكتابة (وسط الشاشة)
            Positioned(
              left: 0,
              right: 0,
              top: sliderTop - 10,
              bottom: kb + fontRowH,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: w * 0.1),
                  child: Container(
                    padding: box ? EdgeInsets.symmetric(horizontal: fs * 0.5, vertical: fs * 0.25) : EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: box ? boxColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(fs * 0.3),
                    ),
                    child: IntrinsicWidth(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        autofocus: true,
                        minLines: 1,
                        maxLines: null,
                        textDirection: dir,
                        textAlign: _aligns[_alignIdx],
                        cursorColor: box ? _contrast(_color) : _color,
                        style: style,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: 'إضافة نص',
                          hintStyle: style.copyWith(color: Colors.white54),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // الأزرار العلوية
            Positioned(
              top: topPad + 10,
              left: 14,
              right: 13,
              child: Row(
                children: [
                  _topBtn(_bgIcon(), () => setState(() => _bgMode = (_bgMode + 1) % kTextBgModes)),
                  const SizedBox(width: 6),
                  _topBtn(
                    Icon(_alignIcons[_alignIdx], color: Colors.white, size: 23),
                    () => setState(() => _alignIdx = (_alignIdx + 1) % _aligns.length),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _finish,
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 17),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _btnBg, borderRadius: BorderRadius.circular(17)),
                      child: const Text(
                        'تم',
                        style: TextStyle(color: Colors.white, fontSize: 15.5, fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // شريط الألوان العمودي
            Positioned(
              top: sliderTop,
              left: 8,
              width: 40,
              height: sliderH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => setState(() => _t = (d.localPosition.dy / sliderH).clamp(0.0, 1.0)),
                onVerticalDragStart: (d) => setState(() {
                  _dragSlider = true;
                  _t = (d.localPosition.dy / sliderH).clamp(0.0, 1.0);
                }),
                onVerticalDragUpdate: (d) => setState(() => _t = (d.localPosition.dy / sliderH).clamp(0.0, 1.0)),
                onVerticalDragEnd: (_) => setState(() => _dragSlider = false),
                onVerticalDragCancel: () => setState(() => _dragSlider = false),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 15,
                      top: 0,
                      bottom: 0,
                      width: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [for (int i = 0; i <= 40; i++) textColorAt(i / 40)],
                          ),
                        ),
                      ),
                    ),
                    if (_dragSlider)
                      Positioned(
                        left: 7,
                        top: _t * sliderH - 13,
                        child: Container(
                          width: 26,
                          height: 26,
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
            // صف الخطوط فوق الكيبورد
            Positioned(
              left: 0,
              right: 0,
              bottom: kb,
              height: fontRowH,
              child: Row(
                children: [
                  for (int i = 0; i < kTitiTextFonts.length; i++)
                    Expanded(
                      child: Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _font = i);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _font == i ? Colors.white : const Color(0x33FFFFFF),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              'Aa',
                              style: TextStyle(
                                color: _font == i ? Colors.black : Colors.white,
                                fontSize: 14,
                                fontFamily: kTitiTextFonts[i].family,
                                fontFamilyFallback: const ['Tajawal'],
                                fontWeight: kTitiTextFonts[i].weight,
                                fontStyle: kTitiTextFonts[i].style,
                              ),
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
    );
  }
}