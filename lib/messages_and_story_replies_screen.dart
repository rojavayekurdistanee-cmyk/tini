import 'package:flutter/material.dart';
import 'message_requests_screen.dart';
import 'story_reply_settings_screen.dart';
import 'read_receipts_screen.dart';

const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);

class MessagesAndStoryRepliesScreen extends StatelessWidget {
  const MessagesAndStoryRepliesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kBg, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)), title: const Text('الرسائل والردود على القصص', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('طريقة تواصل الأشخاص معك', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 13)),
          const SizedBox(height: 10),
          Container(decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)), child: Column(children: [_tile(context, 'طلبات المراسلة', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessageRequestsScreen()))), _tile(context, 'الردود على القصص', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoryReplySettingsScreen())), showDivider: false)])),
          const SizedBox(height: 24),
          Container(decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)), child: _tile(context, 'عرض مؤشرات قراءة الرسائل', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadReceiptsScreen())), showDivider: false)),
        ],
      ),
    );
  }

  static Widget _tile(BuildContext context, String title, VoidCallback onTap, {bool showDivider = true}) {
    return Column(children: [
      InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15)), const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white54)]))),
      if (showDivider) const Divider(color: Colors.white10, height: 1, indent: 16, endIndent: 16),
    ]);
  }
}