import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'galaxy_star.dart';
import 'galaxy_discovery_provider.dart';
import 'galaxy_discovery_service.dart';
import 'galaxy_user_star.dart';
import 'galaxy_user_stars_layer.dart';
import 'galaxy_user_card.dart';
import 'galaxy_match_entry_sheet.dart';
import 'profile_screen.dart';
import 'galaxy_starfield_painter.dart';

class GalaxyScreen extends StatefulWidget {
  final bool active;
  final GalaxyDiscoveryBackend? discoveryBackend;
  const GalaxyScreen({super.key, this.active = true, this.discoveryBackend});

  @override
  State<GalaxyScreen> createState() => _GalaxyScreenState();
}

class _GalaxyScreenState extends State<GalaxyScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock;
  late final List<GalaxyStar> _stars;
  late final GalaxyDiscoveryProvider _discovery;
  bool _cardOpen = false;
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
    _discovery = GalaxyDiscoveryProvider(
      widget.discoveryBackend ?? GalaxyDiscoveryService(),
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
    _discovery.setActive(
      widget.active && _visible && _resumed && _tickerEnabled,
    );
    final running =
        widget.active &&
        _visible &&
        _resumed &&
        _tickerEnabled &&
        !_reduceMotion &&
        !_cardOpen;
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
    _discovery.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _discovery,
    builder: (context, _) => _buildGalaxy(context),
  );

  Widget _buildGalaxy(BuildContext context) => VisibilityDetector(
    key: _visibilityKey,
    onVisibilityChanged: (info) {
      if (!mounted) return;
      _visible = info.visibleFraction > 0;
      _syncAnimation();
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final own = _discovery.ownStar;
        final point = own == null
            ? Offset.zero
            : GalaxyUserStarsLayer.screenPosition(own, size, _camera, _zoom);
        final entryLeft = point.dx + 76 < size.width
            ? point.dx + 36
            : point.dx - 72;
        return Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              label:
                  'المجرة، اسحب لاستكشاف النجوم واستخدم إصبعين للتكبير والتصغير',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (_) => _gestureZoom = _zoom,
                onScaleUpdate: (details) => setState(() {
                  final nextZoom = (_gestureZoom * details.scale).clamp(
                    0.6,
                    3.0,
                  );
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
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
                    AnimatedSwitcher(
                      duration: _reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 350),
                      // Old identities are removed immediately; only the incoming
                      // layer fades in, so revoked accounts cannot linger or be tapped.
                      layoutBuilder: (current, previous) =>
                          current ?? const SizedBox.expand(),
                      child: GalaxyUserStarsLayer(
                        key: ValueKey(
                          '${_discovery.ownStar?.uid ?? ''}:${_discovery.stars.map((s) => s.uid).join(',')}',
                        ),
                        stars: _discovery.stars,
                        ownStar: _discovery.ownStar,
                        camera: _camera,
                        zoom: _zoom,
                        clock: _clock,
                        reduceMotion: _reduceMotion,
                        onTap: _openStar,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (own != null &&
                GalaxyUserStarsLayer.inExplorableArea(point, size) &&
                entryLeft >= 0 &&
                entryLeft + 36 <= size.width &&
                point.dy - 18 >= 76 &&
                point.dy + 18 < size.height - 112)
              Positioned(
                left: entryLeft,
                top: point.dy - 18,
                width: 36,
                height: 36,
                child: IconButton.filledTonal(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  tooltip: 'النجمة الناقصة',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xCC163A40),
                    foregroundColor: const Color(0xFF80CBC4),
                  ),
                  onPressed: _openMatching,
                  icon: const Icon(Icons.extension_outlined),
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
            PositionedDirectional(
              bottom: 12,
              start: 16,
              end: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_discovery.loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (_discovery.error != null)
                    Text(
                      _discovery.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    )
                  else if (_discovery.stars.isEmpty)
                    const Text(
                      'لا توجد نجوم متاحة للاكتشاف حالياً',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  TextButton.icon(
                    onPressed: _discovery.loading ? null : _discovery.refresh,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('اكتشف نجوماً جديدة'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF80CBC4),
                      backgroundColor: const Color(0xB30F1720),
                    ),
                  ),
                  const IgnorePointer(
                    child: Text(
                      'اسحب للاستكشاف · استخدم إصبعين للتكبير',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _openMatching() async {
    if (_cardOpen || _discovery.ownStar == null) return;
    _cardOpen = true;
    _syncAnimation();
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF1A222C),
        isScrollControlled: true,
        builder: (_) => const GalaxyMatchEntrySheet(),
      );
    } finally {
      if (mounted) {
        _cardOpen = false;
        _syncAnimation();
      }
    }
  }

  Future<void> _openStar(GalaxyUserStar star) async {
    if (!_cardOpen && _discovery.ownStar?.uid == star.uid) {
      _cardOpen = true;
      _syncAnimation();
      try {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProfileScreen(userId: star.uid),
          ),
        );
      } finally {
        if (mounted) {
          _cardOpen = false;
          _syncAnimation();
        }
      }
      return;
    }
    if (_cardOpen || !_discovery.stars.any((s) => s.uid == star.uid)) return;
    _cardOpen = true;
    _syncAnimation();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A222C),
      builder: (sheetContext) => AnimatedBuilder(
        animation: _discovery,
        builder: (context, _) {
          final matches = _discovery.stars.where((s) => s.uid == star.uid);
          if (matches.isEmpty) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لم يعد هذا الحساب متاحاً',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }
          return GalaxyUserCard(
            star: matches.first,
            onVisit: () {
              if (!_discovery.stars.any((s) => s.uid == star.uid)) return;
              Navigator.pop(sheetContext);
              Navigator.of(this.context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProfileScreen(userId: star.uid),
                ),
              );
            },
          );
        },
      ),
    );
    if (!mounted) return;
    _cardOpen = false;
    _syncAnimation();
  }
}
