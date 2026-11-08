import 'package:flutter/material.dart';
import 'dart:math' as math;

/// --- 1. إفكت الهزة Shake ---
class ShakeWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double offset;

  const ShakeWidget({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.offset = 10.0,
  });

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat();
    _animation = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final dx = math.sin(_animation.value * math.pi * 8) * widget.offset;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// --- 2. إفكت الزوم النابض Zoom Pulse ---
class ZoomPulseWidget extends StatefulWidget {
  final Widget child;

  const ZoomPulseWidget({super.key, required this.child});

  @override
  State<ZoomPulseWidget> createState() => _ZoomPulseWidgetState();
}

class _ZoomPulseWidgetState extends State<ZoomPulseWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: widget.child,
    );
  }
}

/// --- 3. إفكت التشويش اللوني Glitch Color ---
class GlitchColorWidget extends StatefulWidget {
  final Widget child;

  const GlitchColorWidget({super.key, required this.child});

  @override
  State<GlitchColorWidget> createState() => _GlitchColorWidgetState();
}

class _GlitchColorWidgetState extends State<GlitchColorWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final offset = _controller.value * 4;
        return Stack(
          children: [
            Transform.translate(
              offset: Offset(-offset, 0),
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(Colors.red, BlendMode.lighten),
                child: widget.child,
              ),
            ),
            Transform.translate(
              offset: Offset(offset, 0),
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(Colors.cyan, BlendMode.lighten),
                child: widget.child,
              ),
            ),
            widget.child,
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// --- 4. إفكت الزلزال Earthquake ---
class EarthquakeWidget extends StatefulWidget {
  final Widget child;
  final double intensity;

  const EarthquakeWidget({
    super.key,
    required this.child,
    this.intensity = 8.0,
  });

  @override
  State<EarthquakeWidget> createState() => _EarthquakeWidgetState();
}

class _EarthquakeWidgetState extends State<EarthquakeWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final dx = (_random.nextDouble() * 2 - 1) * widget.intensity;
        final dy = (_random.nextDouble() * 2 - 1) * widget.intensity;
        final scale = 1.0 + _random.nextDouble() * 0.03;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// --- 5. إفكت الوميض Flash Cut ---
class FlashCutWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const FlashCutWidget({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<FlashCutWidget> createState() => _FlashCutWidgetState();
}

class _FlashCutWidgetState extends State<FlashCutWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 50),
    ]).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Opacity(
              opacity: _animation.value,
              child: Container(color: Colors.white),
            );
          },
        ),
      ],
    );
  }
}

/// --- 6. إفكت قلبة بطاقة 3D Card Flip ---
class CardFlip3DWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const CardFlip3DWidget({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<CardFlip3DWidget> createState() => _CardFlip3DWidgetState();
}

class _CardFlip3DWidgetState extends State<CardFlip3DWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: 0, end: math.pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final isBack = _animation.value >= math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(_animation.value),
          child: isBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: child,
                )
              : child,
        );
      },
      child: widget.child,
    );
  }
}

/// --- 7. إفكت جيلي Jello ---
class JelloWidget extends StatefulWidget {
  final Widget child;

  const JelloWidget({super.key, required this.child});

  @override
  State<JelloWidget> createState() => _JelloWidgetState();
}

class _JelloWidgetState extends State<JelloWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.75), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.75, end: 1.15), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 10),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final scaleY = _animation.value;
        final scaleX = 2.0 - scaleY;
        return Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// --- 8. إفكت VHS قديم ---
class VHSWidget extends StatefulWidget {
  final Widget child;

  const VHSWidget({super.key, required this.child});

  @override
  State<VHSWidget> createState() => _VHSWidgetState();
}

class _VHSWidgetState extends State<VHSWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            widget.child,
            Opacity(
              opacity: 0.3,
              child: CustomPaint(
                painter: _VHSLinesPainter(_controller.value),
                child: Container(),
              ),
            ),
            Transform.translate(
              offset: Offset(math.sin(_controller.value * math.pi * 2) * 2, 0),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.white.withValues(alpha: 0.05),
                  BlendMode.lighten,
                ),
                child: widget.child,
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class _VHSLinesPainter extends CustomPainter {
  final double progress;
  _VHSLinesPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.1);
    for (double i = 0; i < size.height; i += 4) {
      canvas.drawLine(Offset(0, i + progress * 4), Offset(size.width, i + progress * 4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VHSLinesPainter oldDelegate) => true;
}

/// --- 9. إفكت لكمة زوم Zoom Punch ---
class ZoomPunchWidget extends StatefulWidget {
  final Widget child;

  const ZoomPunchWidget({super.key, required this.child});

  @override
  State<ZoomPunchWidget> createState() => _ZoomPunchWidgetState();
}

class _ZoomPunchWidgetState extends State<ZoomPunchWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: widget.child,
    );
  }
}

/// --- 10. إفكت فصل ألوان RGB Split ---
class RGBSplitWidget extends StatefulWidget {
  final Widget child;
  final double offset;

  const RGBSplitWidget({
    super.key,
    required this.child,
    this.offset = 6.0,
  });

  @override
  State<RGBSplitWidget> createState() => _RGBSplitWidgetState();
}

class _RGBSplitWidgetState extends State<RGBSplitWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final o = widget.offset * _controller.value;
        return Stack(
          children: [
            Transform.translate(
              offset: Offset(-o, 0),
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(Colors.red, BlendMode.lighten),
                child: widget.child,
              ),
            ),
            Transform.translate(
              offset: Offset(o, 0),
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(Colors.blue, BlendMode.lighten),
                child: widget.child,
              ),
            ),
            ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.green, BlendMode.lighten),
              child: widget.child,
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// --- 11. إفكت ارتداد دخول Bounce Scale ---
class BounceScaleWidget extends StatefulWidget {
  final Widget child;

  const BounceScaleWidget({super.key, required this.child});

  @override
  State<BounceScaleWidget> createState() => _BounceScaleWidgetState();
}

class _BounceScaleWidgetState extends State<BounceScaleWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.1), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 0.95), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: widget.child,
    );
  }
}

/// --- 12. إفكت أثر شبحي Ghost Trail ---
class GhostTrailWidget extends StatefulWidget {
  final Widget child;

  const GhostTrailWidget({super.key, required this.child});

  @override
  State<GhostTrailWidget> createState() => _GhostTrailWidgetState();
}

class _GhostTrailWidgetState extends State<GhostTrailWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            Opacity(opacity: 0.2, child: widget.child),
            Transform.translate(
              offset: Offset(-2, -2),
              child: Opacity(opacity: 0.15, child: widget.child),
            ),
            Transform.translate(
              offset: Offset(2, 2),
              child: Opacity(opacity: 0.15, child: widget.child),
            ),
            widget.child,
          ],
        );
      },
      child: widget.child,
    );
  }
}