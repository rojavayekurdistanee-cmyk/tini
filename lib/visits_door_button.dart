import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VisitsDoorButton extends StatefulWidget {
  final VoidCallback onTap;
  final int badgeCount;
  final List<String> visitorIds;
  final bool isLoaded;
  final bool isActive;

  const VisitsDoorButton({
    super.key,
    required this.onTap,
    this.badgeCount = 0,
    this.visitorIds = const [],
    this.isLoaded = true,
    this.isActive = true,
  });

  @override
  State<VisitsDoorButton> createState() => _VisitsDoorButtonState();
}

class _VisitsDoorButtonState extends State<VisitsDoorButton>
    with SingleTickerProviderStateMixin {
  final LayerLink _positionLink = LayerLink();
  final OverlayPortalController _overlayController = OverlayPortalController();
  final Map<String, Stream<DocumentSnapshot<Map<String, dynamic>>>> _visitorStreams = {};
  late final AnimationController _controller;
  late final Animation<double> _expandedProgress;
  bool _playedIntro = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _expandedProgress = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 23,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 49),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 28,
      ),
    ]).animate(_controller);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _overlayController.hide();
      }
    });
    _syncVisitorStreams();
    _playIntroWhenLoaded();
  }

  @override
  void didUpdateWidget(covariant VisitsDoorButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.isActive && !widget.isActive) ||
        (oldWidget.badgeCount > 0 && widget.badgeCount == 0)) {
      _playedIntro = false;
      // لا نغيّر طبقة Overlay أثناء إعادة بناء شجرة البروفايل.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || (widget.isActive && widget.badgeCount > 0)) return;
        _controller.reset();
        _overlayController.hide();
      });
    }
    _syncVisitorStreams();
    _playIntroWhenLoaded();
  }

  void _syncVisitorStreams() {
    final currentIds = widget.visitorIds.where((id) => id.isNotEmpty).take(3).toSet();
    _visitorStreams.removeWhere((id, _) => !currentIds.contains(id));
    for (final id in currentIds) {
      _visitorStreams.putIfAbsent(
        id,
        () => FirebaseFirestore.instance
            .collection('users')
            .doc(id)
            .snapshots(),
      );
    }
  }

  void _playIntroWhenLoaded() {
    // لا نعرض حركة التمدد إلا عند وصول زيارات جديدة لم تُقرأ بعد.
    if (!widget.isLoaded || !widget.isActive ||
        widget.badgeCount <= 0 || _playedIntro) return;
    _playedIntro = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isLoaded || !widget.isActive ||
          widget.badgeCount <= 0) {
        _playedIntro = false;
        return;
      }
      if (MediaQuery.disableAnimationsOf(context)) return;
      _overlayController.show();
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _avatar(String uid, {required double size}) {
    final stream = _visitorStreams[uid];
    if (stream == null) {
      return _avatarCircle('', size: size);
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final photo = snapshot.data?.data()?['profileImg'];
        final photoUrl = photo is String ? photo.trim() : '';
        return _avatarCircle(photoUrl, size: size);
      },
    );
  }

  Widget _avatarCircle(String url, {required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.teal.withValues(alpha: 0.22),
        border: Border.all(color: const Color(0xFFEDEDED), width: 1),
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image(
                image: CachedNetworkImageProvider(url),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.person,
                  color: Colors.white70,
                  size: 12,
                ),
              )
            : const Icon(Icons.person, color: Colors.white70, size: 12),
      ),
    );
  }

  // آخر زائر يُرسم مرة واحدة في الموضع الثابت، وهنا نرسم الصورتين الأقدم فقط.
  Widget _smallAvatarRow() {
    final ids = widget.visitorIds.where((id) => id.isNotEmpty).take(3).toList();
    if (ids.isEmpty) return const SizedBox.shrink();
    const double size = 23;
    const double overlapStep = 14;
    return SizedBox(
      width: size + (ids.length - 1) * overlapStep,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = ids.length - 1; i >= 1; i--)
            Positioned(
              right: i * overlapStep,
              child: _avatar(ids[i], size: size),
            ),
        ],
      ),
    );
  }

  // تثبيت صورة آخر زائر في نفس الإحداثيات داخل Overlay والوضع المصغّر.
  // عرض النص منفصل حتى لا ينزاح موضع الصورة أثناء تبديل الطبقتين.
  Widget _compactContent({required String newestAvatarUrl, bool showAvatar = true}) {
    final hasVisitor = widget.visitorIds.any((id) => id.isNotEmpty);
    return Stack(
      children: [
        if (widget.badgeCount > 0)
          Positioned(
            right: hasVisitor ? 39 : 11,
            top: 0,
            bottom: 0,
            child: Center(
              child: Text(
                '${widget.badgeCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (hasVisitor && showAvatar)
          Positioned(
            right: 11,
            top: 5.5,
            child: _avatarCircle(newestAvatarUrl, size: 23),
          )
        else if (!hasVisitor && widget.badgeCount == 0)
          const Center(
            child: Icon(Icons.door_front_door_outlined, size: 22, color: Colors.white70),
          ),
      ],
    );
  }

  Widget _expandedContent() {
    return Row(
      textDirection: TextDirection.ltr,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${widget.badgeCount} زيارة للملف الشخصي',
              maxLines: 1,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: Color(0xFF181818),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _smallAvatarRow(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final compactWidth = (44.0 + '${widget.badgeCount}'.length * 8)
        .clamp(56.0, 94.0)
        .toDouble();
    final expandedWidth = (MediaQuery.sizeOf(context).width - 130)
        .clamp(compactWidth, 218.0)
        .toDouble();

    final availableIds = widget.visitorIds.where((id) => id.isNotEmpty);
    final newestId = availableIds.isEmpty ? null : availableIds.first;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: newestId == null ? null : _visitorStreams[newestId],
      builder: (context, newestSnapshot) {
        final photo = newestSnapshot.data?.data()?['profileImg'];
        final newestAvatarUrl = photo is String ? photo.trim() : '';
        return _buildDoorPortal(
          compactWidth: compactWidth,
          expandedWidth: expandedWidth,
          newestAvatarUrl: newestAvatarUrl,
        );
      },
    );
  }

  Widget _buildDoorPortal({
    required double compactWidth,
    required double expandedWidth,
    required String newestAvatarUrl,
  }) {
    return OverlayPortal(
      controller: _overlayController,
      // Stack يضمن مساحة hit-testing كاملة لشريط التمدد داخل Overlay.
      overlayChildBuilder: (context) => widget.badgeCount <= 0
          ? const SizedBox.shrink()
          : Stack(
        clipBehavior: Clip.none,
        children: [
          CompositedTransformFollower(
            link: _positionLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.topRight,
            child: Material(
              type: MaterialType.transparency,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final progress = _expandedProgress.value;
                  final width = compactWidth + (expandedWidth - compactWidth) * progress;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onTap,
                    child: SizedBox(
                      width: width,
                      height: 34,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              Colors.transparent,
                              const Color(0xFFEDEDED),
                              progress,
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.centerRight,
                            children: [
                              Positioned.fill(
                                child: Opacity(
                                  opacity: (1 - progress * 4).clamp(0.0, 1.0),
                                  child: _compactContent(
                                    newestAvatarUrl: newestAvatarUrl,
                                    showAvatar: false,
                                  ),
                                ),
                              ),
                              if (progress > 0.25)
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 11),
                                    child: Opacity(
                                      opacity: ((progress - 0.25) * 3).clamp(0.0, 1.0),
                                      child: _expandedContent(),
                                    ),
                                  ),
                                ),
                              // صورة آخر زائر لا تتبدل بين الطبقتين ولا تغير موضعها.
                              if (widget.visitorIds.any((id) => id.isNotEmpty))
                                Positioned(
                                  right: 11,
                                  top: 5.5,
                                  child: _avatarCircle(newestAvatarUrl, size: 23),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      child: CompositedTransformTarget(
        link: _positionLink,
        child: Semantics(
          button: true,
          label: widget.badgeCount > 0
              ? '${widget.badgeCount} زيارة جديدة للملف الشخصي'
              : 'سجل زيارات الملف الشخصي',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: SizedBox(
              width: compactWidth,
              height: 34,
              child: _compactContent(newestAvatarUrl: newestAvatarUrl),
            ),
          ),
        ),
      ),
    );
  }
}
