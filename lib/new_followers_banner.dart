import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_provider.dart';
import 'auth_provider.dart' as custom;
import 'follow_list_screen.dart';

class NewFollowersBanner extends StatefulWidget {
  const NewFollowersBanner({super.key});

  @override
  State<NewFollowersBanner> createState() => _NewFollowersBannerState();
}

class _NewFollowersBannerState extends State<NewFollowersBanner> {
  int _previousCount = 0;

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final int count = chatProvider.pendingFollowRequests;
    final Map<String, dynamic>? lastFollower = chatProvider.lastFollower;

    _previousCount = count;

    // استخدام الحقول الصحيحة من Firestore - مع قيم افتراضية للبانر الثابت
    final String lastName = lastFollower?['fullName']?? lastFollower?['name']?? 'لا يوجد';
    final String? lastPhoto = lastFollower?['profileImg']?? lastFollower?['photoUrl'];
    final String? lastUid = lastFollower?['uid'];

    return InkWell(
      onTap: () {
        final uid = FirebaseAuth.instance.currentUser?.uid?? '';
        // تصفير الإشعارات عند فتح البانر
        if (count > 0) {
          chatProvider.clearLastFollower();
        }
        Navigator.push(context, MaterialPageRoute(builder: (_) => FollowListScreen(
          userId: uid,
          userName: 'المتابعون',
          initialTab: 1,
        )));
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
                // أيقونة ثابتة 3 أشخاص
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFF2196F3),
                  child: Icon(Icons.group, color: Colors.white, size: 20),
                ),
                if (count > 0)...[
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF1C1C1E),
                    backgroundImage: lastPhoto!= null && lastPhoto.isNotEmpty
                     ? NetworkImage(lastPhoto)
                      : null,
                    child: lastPhoto == null || lastPhoto.isEmpty
                     ? Text(
                          lastName.isNotEmpty? lastName[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Tajawal',
                          ),
                        )
                      : null,
                  ),
                  const SizedBox(width: 12),
                ] else
                  const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        count > 0? 'متابع جديد ($count)' : 'المتابعون',
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
                        count > 0? 'بدأ $lastName في متابعتك' : 'اضغط لعرض الطلبات',
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
                const SizedBox(width: 12),
                if (count > 0 && lastUid!= null)
                  ElevatedButton(
                    onPressed: () async {
                      await Provider.of<custom.AuthProvider>(context, listen: false).toggleFollow(lastUid);
                      chatProvider.clearLastFollower();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    child: const Text('رد المتابعة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 13)),
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
                  count > 99? '99+' : '$count',
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