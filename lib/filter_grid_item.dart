import 'package:flutter/material.dart';
import 'filter_model.dart';

class FilterGridItem extends StatelessWidget {
  final FilterModel filter;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? thumbnail;

  const FilterGridItem({
    super.key,
    required this.filter,
    required this.isSelected,
    required this.onTap,
    this.thumbnail,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary( // ← مهم جداً عشان الأداء
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.teal : const Color(0xFF1A222C),
                  width: isSelected ? 2 : 1,
                ),
                color: const Color(0xFF1A222C),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildPreview(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filter.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    // لو في thumbnail مخصص استخدمه
    if (thumbnail != null) return thumbnail!;

    // لو كان إفكت: ما تستخدم ColorFiltered نهائياً - بس أيقونة خفيفة
    if (filter.isEffect) {
      return const ColoredBox(
        color: Color(0xFF2A3441),
        child: Center(
          child: Icon(
            Icons.auto_awesome,
            color: Colors.white54,
            size: 28,
          ),
        ),
      );
    }

    // لو كان فلتر عادي: استخدم لون بسيط بدل ColorFiltered التقيل
    return ColoredBox(
      color: const Color(0xFF374151), // رمادي ثابت أخف من ColorFiltered
      child: Center(
        child: Icon(
          Icons.photo_filter,
          color: Colors.white30,
          size: 24,
        ),
      ),
    );
  }
}