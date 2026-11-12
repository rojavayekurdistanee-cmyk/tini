import 'package:flutter/material.dart';

/// Kept mounted when empty so dismissal completes its exit animation.
/// A stable child key updates a group without replaying its entrance.
class BannerTransition extends StatelessWidget {
  const BannerTransition({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: child == null,
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, -.25),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        ),
        child: child ?? const SizedBox.shrink(key: ValueKey('empty')),
      ),
    );
  }
}

/// Swipe up to dismiss. No Tooltip/Overlay dependency and no close button.
/// Both a deliberate slow drag and a short upward flick are supported.
class BannerDismissGesture extends StatefulWidget {
  const BannerDismissGesture({
    super.key,
    required this.child,
    required this.onDismiss,
    this.onTap,
  });
  final Widget child;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  @override
  State<BannerDismissGesture> createState() => _BannerDismissGestureState();
}

class _BannerDismissGestureState extends State<BannerDismissGesture> {
  double _verticalDistance = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    onVerticalDragStart: (_) => _verticalDistance = 0,
    onVerticalDragUpdate: (details) =>
        _verticalDistance += details.primaryDelta ?? 0,
    onVerticalDragCancel: () => _verticalDistance = 0,
    onVerticalDragEnd: (details) {
      final dismiss =
          _verticalDistance <= -32 || (details.primaryVelocity ?? 0) < -100;
      _verticalDistance = 0;
      if (dismiss) widget.onDismiss();
    },
    child: widget.child,
  );
}
