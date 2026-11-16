import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
import 'package:iconsax/iconsax.dart';
import 'who_can_see_posts_screen.dart';
import 'comment_settings_screen.dart';
import 'following_list_privacy_sheet.dart';
import 'messages_and_story_replies_screen.dart';
import 'mention_tag_privacy_screen.dart';
import 'liked_videos_privacy_sheet.dart';
import 'favorite_videos_privacy_sheet.dart';

class PrivateAccountScreen extends StatefulWidget {
  const PrivateAccountScreen({super.key});

  @override
  State<PrivateAccountScreen> createState() => _PrivateAccountScreenState();
}

class _PrivateAccountScreenState extends State<PrivateAccountScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;


  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<custom.AuthProvider>(context);
    
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
          "حساب خاص",
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(top: 10, bottom: 40),
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "حساب خاص",
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    Switch(
                      value: auth.isPrivate,
                      activeThumbColor: Colors.white,
                      activeTrackColor: titiTeal,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      onChanged: (val) async {
                        await auth.updatePrivateAccount(val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "عند استخدام حساب خاص، يمكن للمستخدمين الذين وافقتهم عليهم فقط متابعتك ومشاهدة فيديوهاتك. لن يؤثر هذا على المتابعين الموجودين بالفعل.",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha:0.5),
                    fontSize: 12.5,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),

          
          const _GalaxyPrivacySetting(),
          _buildSectionHeader("إعدادات التحكم"),
          _buildActivityGroup([
            _buildActivityTile(
              Iconsax.eye, 
              "من يرى منشوراتك",
              subtitle: auth.defaultPrivacy == 'friends' 
                  ? "الأصدقاء" 
                  : auth.defaultPrivacy == 'only_me' 
                      ? "أنا فقط" 
                      : "الجميع",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const WhoCanSeePostsScreen()),
                );
              },
            ),
            _buildActivityTile(
              Iconsax.messages, 
              "التحكم بالتعليقات",
              subtitle: auth.commentPrivacy == 'comment_friends'
                  ? "الأصدقاء"
                  : auth.commentPrivacy == 'comment_nobody'
                      ? "لا أحد"
                      : "الجميع",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CommentSettingsScreen()),
                );
              },
            ),
            _buildActivityTile(
              Iconsax.user_add,
              "قائمة المتابعة",
              subtitle: auth.whoCanSeeFollowingList == 'follow_list_mutual' ? "مخصص لك" : "الكل",
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const FollowingListPrivacySheet(),
                );
              },
            ),
            _buildActivityTile(
             Iconsax.direct, 
             "رسائل خاصة",
              subtitle: auth.messageRequestPrivacy == 'followers' ? "متابعوك" : auth.messageRequestPrivacy == 'nobody' ? "لا أحد" : "الجميع",
              onTap: () {
             Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesAndStoryRepliesScreen()));
            },
          ),
            _buildActivityTile(
              Iconsax.tag, "الذِكر والإشارات",
              subtitle: auth.mentionPrivacy == 'following'
                  ? "الأشخاص الذين تتابعهم"
                  : auth.mentionPrivacy == 'friends'
                      ? "الأصدقاء"
                      : auth.mentionPrivacy == 'nobody' ? "لا أحد" : "الجميع",
              onTap: () {
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MentionTagPrivacyScreen()));
              },
            ),
            // [Tini - Liked Videos Privacy]: إعداد ظهور قائمة الإعجابات للآخرين.
            _buildActivityTile(
              Iconsax.heart, "فيديوهات أعجبتك",
              subtitle: auth.likedVideosPrivacy == 'everyone' ? "الجميع" : "لك فقط",
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const LikedVideosPrivacySheet(),
                );
              },
            ),
            // [Tini - Favorite Videos Privacy]: نفس إعداد الإعجابات، للمفضلة بشكل مستقل.
            _buildActivityTile(
              Iconsax.archive_1, "فيديوهاتك المفضلة",
              subtitle: auth.favoriteVideosPrivacy == 'everyone' ? "الجميع" : "لك فقط",
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const FavoriteVideosPrivacySheet(),
                );
              },
            ),
          ]),
                ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 25, bottom: 10),
      child: Text(title, style: TextStyle(color: titiTeal.withValues(alpha:0.8), fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildActivityGroup(List<Widget> tiles) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(18)),
      child: Column(children: tiles),
    );
  }

  Widget _buildActivityTile(IconData icon, String title, {String? subtitle, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap ?? () {
        if (title == "من يرى منشوراتك") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const WhoCanSeePostsScreen()),
          );
        } else if (title == "التحكم بالتعليقات") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CommentSettingsScreen()),
          );
        }
      },
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14.5)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subtitle != null)
            Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_ios, color: Colors.white10, size: 14),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }

  Widget _buildSwitchTile(IconData icon, String title, bool value, Function(bool) onChanged) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(icon, color: Colors.white54, size: 22),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14.5)),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: Colors.teal,
          inactiveThumbColor: Colors.white54,
          inactiveTrackColor: const Color(0xFF2A3542),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      ),
    );
  }
}

class _GalaxyPrivacySetting extends StatefulWidget {
  const _GalaxyPrivacySetting();
  @override
  State<_GalaxyPrivacySetting> createState() => _GalaxyPrivacySettingState();
}

class _GalaxyPrivacySettingState extends State<_GalaxyPrivacySetting> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final uid = context.watch<custom.AuthProvider>().uid;
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      key: ValueKey(uid),
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(color: const Color(0xFF1A222C), borderRadius: BorderRadius.circular(18)),
          child: SwitchListTile(
            title: const Text('إظهار حسابي في المجرة', style: TextStyle(color: Colors.white, fontSize: 15)),
            subtitle: Text(data?['isPrivate'] == true
              ? 'الحساب الخاص لا يظهر في المجرة. يُحفظ اختيارك للحساب العام.'
              : 'اسمح للآخرين باكتشاف نجمتك داخل مجرة Tini',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
            value: data?['showInGalaxy'] != false,
            activeTrackColor: Colors.teal,
            onChanged: data == null || snapshot.hasError || _saving ? null : (value) async {
              setState(() => _saving = true);
              try {
                if (FirebaseAuth.instance.currentUser?.uid != uid) return;
                await FirebaseFirestore.instance.collection('users').doc(uid).update({'showInGalaxy': value});
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تعذّر حفظ الإعداد. أعد المحاولة.')));
                }
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
          ),
        );
      },
    );
  }
}
