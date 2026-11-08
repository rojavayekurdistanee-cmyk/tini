import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Biji {
  static void show(BuildContext context, {VoidCallback? onFinished}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => BijiView(
        onDone: () {
          entry.remove();
          if (onFinished != null) onFinished();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class BijiView extends StatefulWidget {
  final VoidCallback onDone;
  const BijiView({super.key, required this.onDone});
  @override
  State<BijiView> createState() => _BijiViewState();
}

class _BijiViewState extends State<BijiView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<Animation<double>> _wordAnims;
  late final Animation<double> _scaleUp;
  late final Animation<double> _flyToHeart;

  static const List<Alignment> _directions = [
    Alignment.topLeft,
    Alignment.topCenter,
    Alignment.topRight,
    Alignment.centerRight,
    Alignment.bottomRight,
    Alignment.bottomCenter,
    Alignment.bottomLeft,
    Alignment.centerLeft,
  ];

  final List<bool> _vibrated = List.filled(8, false);

  // الكلمات تنبني مرة وحدة وتنعاد استخدامها (بدل بنائها كل فريم)
  double? _cachedSmall;
  double? _cachedBig;
  Widget? _smallWord;
  Widget? _bigWord;

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
      // أهم سطر: بدونه Flutter يختصر الأنيميشن إلى 5% من مدته
      // إذا كان في الجوال "إزالة الحركات" أو Animation scale = 0
      animationBehavior: AnimationBehavior.preserve,
    );

    _wordAnims = List.generate(8, (i) {
      final double start = i * 0.08;
      final double end = (start + 0.25) > 0.7 ? 0.7 : (start + 0.25);
      return CurvedAnimation(
        parent: _c,
        curve: Interval(start, end, curve: Curves.easeOutExpo),
      );
    });

    _scaleUp = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.68, 0.85, curve: Curves.elasticOut),
    );
    _flyToHeart = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.85, 1.0, curve: Curves.easeInBack),
    );

    _c.addListener(() {
      for (int i = 0; i < 8; i++) {
        if (!_vibrated[i] && _wordAnims[i].value >= 0.95) {
          _vibrated[i] = true;
          HapticFeedback.heavyImpact();
        }
      }
    });

    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });

    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // ShaderMask ياخد قياس الكلمة الحقيقي تلقائياً، فالتدرج ما ينقص أبداً
  Widget _gradientText(String text, double fontSize) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFF00A651),
          Color(0xFFED1C24),
          Color(0xFFFFEB00),
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(bounds),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: Colors.white, // ضروري عشان يظهر التدرج
        ),
      ),
    );
  }

  void _ensureWords(double small, double big) {
    if (_cachedSmall == small && _cachedBig == big) return;
    _cachedSmall = small;
    _cachedBig = big;
    _smallWord = RepaintBoundary(child: _gradientText("Bijî", small));
    _bigWord = RepaintBoundary(child: _gradientText("Bijî", big));
  }

  Widget _buildWord(int i) {
    return AnimatedBuilder(
      animation: _wordAnims[i],
      child: _smallWord,
      builder: (context, child) {
        final double v = _wordAnims[i].value;
        if (v <= 0 || v >= 1) return const SizedBox.shrink();
        final double opacity =
            v < 0.9 ? 1.0 : (1 - (v - 0.9) * 10).clamp(0.0, 1.0).toDouble();
        return Align(
          alignment: Alignment.lerp(_directions[i], Alignment.center, v)!,
          child: Opacity(opacity: opacity, child: child),
        );
      },
    );
  }

  Widget _buildBigWord(double flyDistance) {
    return AnimatedBuilder(
      animation: _c,
      child: _bigWord,
      builder: (context, child) {
        if (_c.value < 0.68) return const SizedBox.shrink();

        final double fly = _flyToHeart.value.clamp(0.0, 1.0).toDouble();
        final double scale =
            (1.0 + (_scaleUp.value * 0.8)).clamp(0.0, 3.0).toDouble();
        final double opacity = (1 - fly).clamp(0.0, 1.0).toDouble();

        return Center(
          child: Transform.scale(
            scale: (scale * (1 - fly * 0.9)).clamp(0.0, 3.0).toDouble(),
            child: Transform.translate(
              offset: Offset(0, fly * flyDistance),
              child: Opacity(opacity: opacity, child: child),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortestSide = size.shortestSide;

    // أحجام متجاوبة حسب حجم الشاشة
    final double smallFont =
        (shortestSide * 0.048).clamp(16.0, 24.0).toDouble();
    final double bigFont = (shortestSide * 0.12).clamp(38.0, 58.0).toDouble();
    final double flyDistance = size.height * 0.38;

    _ensureWords(smallFont, bigFont);

    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // 8 كلمات من الجوانب
            for (int i = 0; i < 8; i++) _buildWord(i),
            // الكلمة الكبيرة بالنص
            _buildBigWord(flyDistance),
          ],
        ),
      ),
    );
  }
}