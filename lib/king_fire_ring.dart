import 'package:flutter/material.dart';

class KingFireRing extends StatelessWidget {
  final double size;
  final Widget child;
  
  const KingFireRing({
    super.key,
    required this.size,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: ClipOval(
            child: Transform.scale(
              scale: 1.2, // ← هذا يقص أطراف الفيديو ويخلي بس الحلقة النارية
              child: Image.asset(
                'assets/fire_ring.webp',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}