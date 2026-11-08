import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);
const Color kTeal = Colors.teal;
const Color kHighlight = Color(0xFFFF3B30);

class MessageRequestsScreen extends StatelessWidget {
  const MessageRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<custom.AuthProvider>();
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text('طلبات المراسلة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('عندما يرسل إليك شخص لا تتابعه أو لم تدردش معه من قبل رسالة، ستتلقاها على شكل طلب مراسلة.', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13, height: 1.5)),
          const SizedBox(height: 8),
          const Text('تعرف على المزيد عن الأشخاص الذين يمكنهم مراسلتك', style: TextStyle(color: kHighlight, fontFamily: 'Tajawal', fontSize: 13)),
          const SizedBox(height: 24),
          const Text('الأشخاص الذين يمكنهم إرسال طلبات مراسلة إليك', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                _radioTile('الجميع', auth.messageRequestPrivacy == 'all', () => auth.updateMessageRequestPrivacy('all')),
                _radioTile('متابعوك', auth.messageRequestPrivacy == 'followers', () => auth.updateMessageRequestPrivacy('followers')),
                _radioTile('لا أحد', auth.messageRequestPrivacy == 'nobody', () => auth.updateMessageRequestPrivacy('nobody'), showDivider: false),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text('الأشخاص الذين يمكنهم إضافتك إلى الدردشات الجماعية', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                _radioTile('الجميع', auth.groupAddPrivacy == 'all', () => auth.updateGroupAddPrivacy('all')),
                _radioTile('الأشخاص الذين تتابعهم أو راسلتهم مسبقًا', auth.groupAddPrivacy == 'following', () => auth.updateGroupAddPrivacy('following'), showDivider: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _radioTile(String title, bool selected, VoidCallback onTap, {bool showDivider = true}) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15))),
                Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? kTeal : Colors.white54, width: 2)), child: selected ? Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: kTeal, shape: BoxShape.circle))) : null),
              ],
            ),
          ),
        ),
        if (showDivider) const Divider(color: Colors.white10, height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}