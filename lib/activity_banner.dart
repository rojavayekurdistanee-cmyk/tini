import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chat_provider.dart';
import 'activity_screen.dart'; // <-- جديد

class ActivityBanner extends StatelessWidget {
  const ActivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    
    final int count = chatProvider.pendingActivities;
    final Map<String, dynamic>? lastActivity = chatProvider.lastActivity;
    
    final String lastText = lastActivity?['text'] ?? 'لا يوجد نشاط جديد';
    final String lastType = lastActivity?['type'] ?? 'like';

    IconData getIcon() {
      switch (lastType) {
        case 'comment': return Icons.chat_bubble_outline;
        case 'view': return Icons.visibility_outlined;
        case 'share': return Icons.reply_all_rounded;
        case 'favorite': return Icons.bookmark_border_rounded;
        case 'follow': return Icons.person_add_alt_1;
        case 'duet': return Icons.duo_rounded;
        case 'download': return Icons.download_for_offline_outlined;
        case 'mention': return Icons.alternate_email;
        case 'comment_like': return Icons.favorite;
        case 'reply': return Icons.reply;
        case 'message': return Icons.message_outlined;
        case 'comment_disabled': return Icons.comments_disabled_outlined;
        case 'like':
        default: return Icons.favorite_border_rounded;
      }
    }

    return InkWell(
      onTap: () {
        // فتح صفحة النشاط الجديدة
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => const ActivityScreen(),
        ));
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A222C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFFFF9800),
                  child: Icon(Icons.notifications, color: Colors.white, size: 20),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF1C1C1E),
                    child: Icon(getIcon(), color: Colors.white70, size: 20),
                  ),
                  const SizedBox(width: 12),
                ] else
                  const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        count > 0 ? 'نشاط جديد ($count)' : 'النشاط',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          fontFamily: 'Tajawal',
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        count > 0 ? lastText : 'اضغط لعرض التفاعلات',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontFamily: 'Tajawal',
                        ),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (count > 0)
            Positioned(
              top: -4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFF0F1720), width: 2),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}