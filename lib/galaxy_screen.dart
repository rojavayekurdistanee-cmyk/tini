import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'galaxy_star.dart';
import 'galaxy_starfield_painter.dart';

class GalaxyScreen extends StatefulWidget {
  final bool active;
  const GalaxyScreen({super.key, this.active = true});

  @override
  State<GalaxyScreen> createState() => _GalaxyScreenState();
}

class _GalaxyScreenState extends State<GalaxyScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock;
  late final List<GalaxyStar> _stars;
  final _visibilityKey = UniqueKey();
  Offset _camera = GalaxyStar.worldSize.center(Offset.zero);
  double _zoom = 1;
  double _gestureZoom = 1;
  bool _visible = false;
  bool _resumed = true;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _stars = GalaxyStar.generate();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant GalaxyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _syncAnimation();
  }

  void _syncAnimation() {
    final running =
        widget.active &&
        _visible &&
        _resumed &&
        _tickerEnabled &&
        !_reduceMotion;
    if (running && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!running && _clock.isAnimating) {
      _clock.stop();
    }
  }

  void _reset() => setState(() {
    _camera = GalaxyStar.worldSize.center(Offset.zero);
    _zoom = 1;
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VisibilityDetector(
    key: _visibilityKey,
    onVisibilityChanged: (info) {
      if (!mounted) return;
      _visible = info.visibleFraction > 0;
      _syncAnimation();
    },
    child: Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: 'المجرة، اسحب لاستكشاف النجوم واستخدم إصبعين للتكبير والتصغير',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) => _gestureZoom = _zoom,
            onScaleUpdate: (details) => setState(() {
              final nextZoom = (_gestureZoom * details.scale).clamp(0.6, 3.0);
              // Anchor zoom at the fingers rather than jumping to the center.
              final box = context.findRenderObject() as RenderBox;
              final focal =
                  details.localFocalPoint - box.size.center(Offset.zero);
              final nextCamera =
                  _camera +
                  focal / _zoom -
                  focal / nextZoom -
                  details.focalPointDelta / nextZoom;
              _camera = Offset(
                nextCamera.dx.clamp(0.0, GalaxyStar.worldSize.width),
                nextCamera.dy.clamp(0.0, GalaxyStar.worldSize.height),
              );
              _zoom = nextZoom;
            }),
            child: RepaintBoundary(
              child: CustomPaint(
                painter: GalaxyStarfieldPainter(
                  stars: _stars,
                  clock: _clock,
                  camera: _camera,
                  zoom: _zoom,
                  reduceMotion: _reduceMotion,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          top: 12,
          end: 12,
          child: IconButton.filledTonal(
            tooltip: 'العودة إلى مركز المجرة',
            onPressed: _reset,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xCC142C36),
              foregroundColor: const Color(0xFF80CBC4),
            ),
            icon: const Icon(Icons.center_focus_strong_outlined),
          ),
        ),
        const PositionedDirectional(
          bottom: 16,
          start: 16,
          end: 16,
          child: IgnorePointer(
            child: Text(
              'اسحب للاستكشاف · استخدم إصبعين للتكبير',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 12),
            ),
          ),
        ),
      ],
    ),
  );
}
