import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'watch_history_screen.dart'; // [إضافة V1]
import 'comments_history_screen.dart';
import 'search_history_screen.dart';
import 'tag_duet_history_screen.dart';
import 'account_history_screen.dart';
import 'time_on_app_screen.dart';
import 'deleted_videos_screen.dart';


/*
  [Tini Project Rules]:
    1. File Name: activities_screen.dart
    2. Concept: User Activity Logs with Modern Synonyms.
    3. UI Style: Dark Surface (0xFF1A222C), Background (0xFF0F1720), Teal Accents.
    4. Navigation: Smooth transitions, no flicker.
*/

class ActivitiesScreen extends StatelessWidget {
  const ActivitiesScreen({super.key});

  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "مركز الأنشطة",
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 40, top: 10),
        children: [
          // --- القسم الأول: سجلات التفاعل ---
          _buildSectionHeader("نشاطك على Tini"),
          _buildActivityGroup([
            _buildActivityTile(
              Iconsax.video_play,
              "فيديوهات شاهدتها",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WatchHistoryScreen()),
                );
              },
            ),
            _buildActivityTile(Iconsax.message_text, "تعليقاتي السابقة", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CommentsHistoryScreen()));
           }),
            _buildActivityTile(
  Iconsax.search_normal,
  "عمليات البحث",
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchHistoryScreen()),
    );
  },
),
            _buildActivityTile(Iconsax.activity, "نشاطاتي"),
          ]),

          // --- القسم الثاني: التفاعلات الخارجية ---
          _buildSectionHeader("التفاعلات والإشارات"),
          _buildActivityGroup([
            _buildActivityTile(Iconsax.link, "إعلانات تفاعلت معها"),
            _buildActivityTile(Iconsax.user_tag, "سجل الذكر", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const TagDuetHistoryScreen()));
            }),
            _buildActivityTile(Iconsax.user_edit, "تحديثات الحساب", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountHistoryScreen()));
}),
          ]),

          // --- القسم الثالث: إدارة المحتوى والوقت ---
          _buildSectionHeader("المحتوى والوقت"),
          _buildActivityGroup([
            _buildActivityTile(Iconsax.clock, "مدة الاستخدام", onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TimeOnAppScreen()));
            }),
            _buildActivityTile(Iconsax.trash, "المحذوفات", onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DeletedVideosScreen()));
}),
          ]),
        ],
      ),
    );
  }

  // بناء عنوان القسم
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 25, bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: titiTeal.withValues(alpha: 0.8),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // بناء حاوية المجموعة
  Widget _buildActivityGroup(List<Widget> tiles) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: tiles),
    );
  }

  // بناء الخيار الفردي - [تعديل V1: يدعم onTap مخصص لزر فيديوهات شاهدتها]
  Widget _buildActivityTile(IconData icon, String title, {VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap ??
          () {
            // سيتم ربط كل قسم بملفه البرمجي الخاص لاحقاً
          },
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 14.5),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        color: Colors.white10,
        size: 14,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }
}