import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);
const Color kTeal = Colors.teal;

class StoryReplySettingsScreen extends StatelessWidget {
  const StoryReplySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<custom.AuthProvider>();
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kBg, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)), title: const Text('الردود على القصص', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('الأشخاص الذين يمكنهم الرد على قصصك', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              _radioTile('السماح بالردود من كل المتابعين', auth.storyReplyPrivacy == 'all_followers', () => auth.updateStoryReplyPrivacy('all_followers')),
              _radioTile('السماح بالردود من متابعين لك تتابعهم', auth.storyReplyPrivacy == 'mutual', () => auth.updateStoryReplyPrivacy('mutual')),
              _radioTile('عدم السماح بالردود على القصص', auth.storyReplyPrivacy == 'none', () => auth.updateStoryReplyPrivacy('none'), showDivider: false),
            ]),
          ),
        ],
      ),
    );
  }

  static Widget _radioTile(String title, bool selected, VoidCallback onTap, {bool showDivider = true}) {
    return Column(children: [
      InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15))), Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? kTeal : Colors.white54, width: 2)), child: selected ? Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: kTeal, shape: BoxShape.circle))) : null)]))),
      if (showDivider) const Divider(color: Colors.white10, height: 1, indent: 16, endIndent: 16),
    ]);
  }
}