import 'package:flutter/material.dart';
import 'audience_access.dart';
import 'audience_gate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_screen.dart'; // ← أضفنا الاستيراد
import 'story.dart';
import 'story_ring.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
import 'package:cached_network_image/cached_network_image.dart';
import 'titi_single_engine.dart'; // [Fix] مشان نوقف الفيديو بس لما نفتح البروفايل الكامل
import 'post_provider.dart';

class UserProfileSheet extends StatefulWidget {
  final String fullName;
  final String username;
  final String profileImg;
  final String uid;
  final bool isFollowing;
  final VoidCallback onFollowTap;
  final bool isFollowLoading;

  const UserProfileSheet({
    super.key,
    required this.fullName,
    required this.username,
    required this.profileImg,
    required this.uid,
    required this.isFollowing,
    required this.onFollowTap,
    this.isFollowLoading = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String fullName,
    required String username,
    required String profileImg,
    required String uid,
    required bool isFollowing,
    required VoidCallback onFollowTap,
    bool isFollowLoading = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UserProfileSheet(
        fullName: fullName,
        username: username,
        profileImg: profileImg,
        uid: uid,
        isFollowing: isFollowing,
        onFollowTap: onFollowTap,
        isFollowLoading: isFollowLoading,
      ),
    );
  }

  @override
  State<UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<UserProfileSheet> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isLoading = widget.isFollowLoading;
  }

  @override
  void didUpdateWidget(covariant UserProfileSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFollowLoading!= widget.isFollowLoading) {
      _isLoading = widget.isFollowLoading;
    }
  }

  void _handleFollow() async {
    if (!AudienceAccess.instance.canViewProfile(widget.uid)) return;
    setState(() => _isLoading = true);
    await Provider.of<custom.AuthProvider>(context, listen: false).toggleFollow(widget.uid);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openFullProfile() async {
    if (!AudienceAccess.instance.canViewProfile(widget.uid)) return;
    final rootNav = Navigator.of(context, rootNavigator: true);
    final String homeUrl = TitiSingleEngine().currentUrl;
    // نحفظ الـ Provider قبل ما نسكر الشيت مشان نقدر نفحص الفيديو الجديد بعد الرجوع
    final postProvider = Provider.of<PostProvider>(context, listen: false);
    try {
      await TitiSingleEngine().lock();
      if (!mounted || !AudienceAccess.instance.canViewProfile(widget.uid)) return;
    } catch (_) {}
    if (mounted) Navigator.pop(context, true);

    rootNav.push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: widget.uid),
      ),
    ).then((_) async {
      try {
        await TitiSingleEngine().unlockForNewUpload();
        // [FIX - نفس منطق البحث والزائد] - اذا في فيديو جديد انرفع اثناء وجودنا بالبروفايل شغلو هو
        String? newVideoUrl;
        try {
          final lastDoc = postProvider.lastUploadedPost;
          if (lastDoc != null) {
            final data = lastDoc.data() as Map<String, dynamic>?;
            newVideoUrl = data?['videoUrl'] as String?;
          }
        } catch (_) {}

        if (newVideoUrl != null && newVideoUrl.isNotEmpty &&
            AudienceAccess.instance.canPlayUrl(newVideoUrl)) {
          TitiSingleEngine().playUrl(newVideoUrl);
        } else if (homeUrl.isNotEmpty &&
            AudienceAccess.instance.canPlayUrl(homeUrl)) {
          TitiSingleEngine().playUrl(homeUrl);
        }
      } catch (_) {
        if (AudienceAccess.instance.canPlayUrl(homeUrl)) {
          TitiSingleEngine().resumeLast();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color surfaceColor = Color(0xFF1A222C);
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return AudienceProfileGate(
      uid: widget.uid,
      child: Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: const BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: Colors.teal.withAlpha(128),
            borderRadius: BorderRadius.circular(10),
          )),
          const SizedBox(height: 25),
          GestureDetector(
            onTap: _openFullProfile,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                 .collection('stories')
                 .doc(widget.uid)
                 .collection('items')
                 .where('expiresAt', isGreaterThan: Timestamp.now())
                 .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs?? [];
                final currentUserId = FirebaseAuth.instance.currentUser?.uid?? '';
                final hasStories = docs.isNotEmpty;
                final hasUnviewed = docs.any((d) {
                  final viewedBy = List<String>.from(d['viewedBy']?? []);
                  return!viewedBy.contains(currentUserId);
                });

                // [مُصحح] رجعنا منطق الحرف
                final bool hasImage = widget.profileImg.isNotEmpty;
                final String initial = widget.fullName.isNotEmpty? widget.fullName[0].toUpperCase() : '?';

                if (hasStories) {
                  return StoryRing(
                    imageUrl: widget.profileImg,
                    size: 100,
                    hasStories: true,
                    hasUnviewed: hasUnviewed,
                    heroTag: 'profile_avatar_hero_${widget.uid}',
                  );
                                } else if (hasImage) {
                  return CachedNetworkImage(
                    imageUrl: widget.profileImg,
                    cacheKey: widget.profileImg,
                    useOldImageOnUrlChange: false,
                    imageBuilder: (context, imageProvider) => CircleAvatar(
                      radius: 50,
                      backgroundImage: imageProvider,
                    ),
                    placeholder: (context, url) => CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.teal.withAlpha(51),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 2)),
                    ),
                    errorWidget: (context, url, error) => CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.teal.withAlpha(51),
                      child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                    ),
                  );
                } else {
                  return CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.teal.withAlpha(51),
                    child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 15),
          Text(widget.fullName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("@${widget.username}", style: const TextStyle(color: Colors.white70, fontSize: 14)),

          const SizedBox(height: 20),

          // زر المتابعة مربوط بـ Firestore
          if (currentUid!= null && currentUid!= widget.uid)
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                 .collection('users')
                 .doc(currentUid)
                 .collection('following')
                 .doc(widget.uid)
                 .snapshots(),
              builder: (context, snap) {
                final isFollowing = snap.hasData && snap.data!.exists;

                return SizedBox(
                  width: 140,
                  height: 40,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFollowing? Colors.teal : Colors.transparent,
                      foregroundColor: isFollowing? Colors.white : Colors.teal,
                      side: const BorderSide(color: Colors.teal, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _isLoading? null : _handleFollow,
                    icon: _isLoading
                       ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isFollowing? Colors.white : Colors.teal,
                            ),
                          )
                        : Icon(isFollowing? Icons.check : Icons.add, size: 18),
                    label: Text(isFollowing? "تتابعه" : "متابعة"),
                  ),
                );
              },
            ),

          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _openFullProfile,
              child: const Text("عرض البروفايل الكامل", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
      ),
    );
  }
}