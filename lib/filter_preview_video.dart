import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'filter_model.dart';
import 'filter_bottom_sheet.dart'; // ← عدلنا هون: FilterClip موجود بهذا الملف

class FilterPreviewVideo extends StatelessWidget {
  final VideoPlayerController controller;
  final List<FilterClip> filterClips; // ← بياخد كل الكليبات من التايملاين

  const FilterPreviewVideo({
    super.key,
    required this.controller,
    required this.filterClips,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F1720),
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: ValueListenableBuilder(
            valueListenable: controller, // بنراقب وقت الفيديو كل فريم
            builder: (context, value, child) {
              return _buildFilteredVideo(value.position);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFilteredVideo(Duration currentPosition) {
    final video = VideoPlayer(controller);
    
    // 1. دور على الكليب اللي شغال حاليا حسب الوقت
    FilterClip? activeClip;
    for (final clip in filterClips) {
      // ملاحظة: استخدمت <= للـ endTime عشان آخر فريم ينحسب
      if (currentPosition >= clip.startTime && currentPosition <= clip.endTime) {
        activeClip = clip;
        break;
      }
    }

    // 2. إذا ما في كليب شغال، اعرض الفيديو عادي بدون فلتر
    if (activeClip == null) {
      return video;
    }

    final activeFilter = activeClip.filter;

    // 3. إذا الكليب إفكت حركي استخدم effectBuilder من effect_widget.dart
    if (activeFilter.isEffect && activeFilter.effectBuilder != null) {
      return activeFilter.effectBuilder!(video);
    }

    // 4. إذا الكليب فلتر لوني استخدم ColorFiltered
    return ColorFiltered(
      colorFilter: activeFilter.colorFilter,
      child: video,
    );
  }
}