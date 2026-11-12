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
