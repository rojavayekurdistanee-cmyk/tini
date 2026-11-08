import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class StoryRing extends StatelessWidget {
  final String imageUrl;
  final double size;
  final bool hasStories;
  final bool hasUnviewed;
  final VoidCallback? onTap;
  final String? heroTag;

  const StoryRing({
    super.key,
    required this.imageUrl,
    this.size = 80,
    this.hasStories = false,
    this.hasUnviewed = false,
    this.onTap,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    Widget avatar = CircleAvatar(
      radius: (size - 18) / 2,
      backgroundColor: const Color(0xFF1A222C),
      backgroundImage: imageUrl.isNotEmpty ? CachedNetworkImageProvider(imageUrl) : null,
      child: imageUrl.isEmpty ? const Icon(Icons.person, color: Colors.white30) : null,
    );

    Widget ring = hasStories
        ? Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasUnviewed
                  ? const SweepGradient(
                      colors: [
                        Color(0xFF00E5FF),
                        Color(0xFF00BFFF),
                        Color(0xFF1E90FF),
                        Color(0xFF00E5FF),
                      ],
                      stops: [0.0, 0.33, 0.66, 1.0],
                    )
                  : null,
              color: hasUnviewed ? null : Colors.grey.shade700,
              boxShadow: hasUnviewed
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha:0.35),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0F1720),
              ),
              child: avatar,
            ),
          )
        : SizedBox(
            width: size,
            height: size,
            child: Padding(padding: const EdgeInsets.all(3), child: avatar),
          );

    Widget child = GestureDetector(onTap: onTap, child: ring);
    return heroTag != null ? Hero(tag: heroTag!, child: child) : child;
  }
}