import 'package:flutter/material.dart';
import 'audience_access.dart';
import 'audience_gate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'auth_provider.dart' as custom;
import 'story.dart';
import 'story_ring.dart';
import 'media_picker_screen.dart';
import 'chat_provider.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class StoriesBar extends StatelessWidget {
  final Color? backgroundColor;
  const StoriesBar({super.key, this.backgroundColor});

  // [Tini - Responsive Stories] - احسب ارتفاع الأسماء الفعلي عند اختلاف الخط والجهاز.
  // 72px للصورة، 6px للفاصل، 20px للحشو الأصلي، ومسافة أمان صغيرة للخطوط المختلفة.
  static double responsiveHeight(BuildContext context) {
    final labelStyle = DefaultTextStyle.of(context).style.merge(
      const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    );
    final textPainter = TextPainter(
      text: TextSpan(text: 'مستخدم', style: labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final neededHeight = 72.0 + 6.0 + textPainter.height + 20.0 + 6.0;
    return neededHeight > 115.0 ? neededHeight : 115.0;
  }

  final Color bgDark = const Color(0xFF0F1720);
  final Color surfaceCard = const Color(0xFF1A222C);
  final Color titiTeal = const Color(0xFF009688);

  Stream<List<Map<String, dynamic>>> _getStoriesUsers(String currentUid) {
    return FirebaseFirestore.instance
  .collection('users')
  .doc(currentUid)
  .collection('following')
  .snapshots()
  .asyncMap((followingSnap) async {
      final followingIds = followingSnap.docs.map((d) => d.id).toList();
      if (followingIds.isEmpty) return [];

      final usersWithMeta = await Future.wait(
        followingIds.map((id) async {
          try {
            final userDoc = await FirebaseFirestore.instance.collection('users').doc(id).get();
            if (!userDoc.exists) return null;

            final storySnap = await FirebaseFirestore.instance
          .collection('stories')
          .doc(id)
          .collection('items')
          .where('expiresAt', isGreaterThan: Timestamp.now())
          .limit(1)
          .get();

            final hasStory = storySnap.docs.isNotEmpty;
            final latestStory = hasStory? (storySnap.docs.first.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch?? 0 : 0;

            final interDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .collection('interactions')
          .doc(id)
          .get();
            final interactionScore = interDoc.exists? (interDoc.data()?['score']?? 0) as int : 0;

            return {
              'uid': id,
          ...userDoc.data() as Map<String, dynamic>,
              'latestStory': latestStory,
              'hasStory': hasStory,
              'interactionScore': interactionScore,
            };
          } catch (_) {
            // تعديل: لو فشل جلب الستوري، رجّع المستخدم عادي بدل ما نحذفه
            final userDoc = await FirebaseFirestore.instance.collection('users').doc(id).get();
            if (!userDoc.exists) return null;
            return {
              'uid': id,
            ...userDoc.data() as Map<String, dynamic>,
              'latestStory': 0,
              'hasStory': false,
              'interactionScore': 0,
            };
          }
        }),
      );

      final filtered = usersWithMeta.whereType<Map<String, dynamic>>().toList();

      filtered.sort((a, b) {
        final aHas = a['hasStory'] as bool;
        final bHas = b['hasStory'] as bool;
        if (aHas!= bHas) return bHas? 1 : -1;
        final timeCmp = (b['latestStory'] as int).compareTo(a['latestStory'] as int);
        if (timeCmp!= 0) return timeCmp;
        return (b['interactionScore'] as int).compareTo(a['interactionScore'] as int);
      });

      if (FirebaseAuth.instance.currentUser?.uid != currentUid) return [];
      return filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AudienceAccess.instance,
      builder: (context, _) {
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    final currentUid = FirebaseAuth.instance.currentUser?.uid?? '';

    if (currentUid.isEmpty) return const SizedBox.shrink();

      return Container(
      height: responsiveHeight(context),
      color: backgroundColor ?? surfaceCard,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        key: ValueKey(currentUid),
        stream: _getStoriesUsers(currentUid),
        builder: (context, snapshot) {
          final users = snapshot.data?? [];

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: users.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildCreateItem(context, auth, currentUid);
              }

              final user = users[index - 1];
              final uid = user['uid'] as String;
              final name = user['fullName']?? '';
              final profileImg = user['profileImg']?? '';

              return _buildUserStoryItem(context, uid, name, profileImg, currentUid);
            },
          );
        },
      ),
    );
      },
    );
  }

  Widget _buildCreateItem(BuildContext context, custom.AuthProvider auth, String currentUid) {
    // [Tini]: ضغطة منفصلة للصورة والزائد + فتح البروفايل لو ما في ستوري
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
    .collection('stories')
    .doc(currentUid)
    .collection('items')
    .where('expiresAt', isGreaterThan: Timestamp.now())
    .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs?? [];
        final hasStories = docs.isNotEmpty;
        final hasUnviewed = docs.any((d) {
          final viewedBy = List<String>.from(d['viewedBy']?? []);
          return!viewedBy.contains(currentUid);
        });

        Widget avatarWidget;

        if (hasStories && auth.profileImg.isNotEmpty) {
          // عندك ستوري + عندك صورة
          avatarWidget = StoryRing(
            imageUrl: auth.profileImg,
            size: 72,
            hasStories: true,
            hasUnviewed: hasUnviewed,
            heroTag: 'story-create-$currentUid',
          );
        } else if (hasStories && auth.profileImg.isEmpty) {
          // عندك ستوري بس ما عندك صورة = أول حرف + دائرة
          final String initial = auth.fullName.isNotEmpty? auth.fullName.trim()[0].toUpperCase() : '?';
          avatarWidget = Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasUnviewed
              ? const SweepGradient(
                      colors: [
                        Color(0xFF00E5FF),
                        Color(0xFF00BFFF),
                        Color(0xFF1E90FF),
                        Color(0xFF00E5FF),
                      ],
                      stops: [0.0, 0.33, 0.66, 1.0],
                    )
                  : null,
              border: hasUnviewed? null : Border.all(color: Colors.grey.shade700, width: 2.5),
            ),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0F1720),
              ),
              child: CircleAvatar(
                radius: 33,
                backgroundColor: const Color(0xFF1A222C),
                child: Text(
                  initial,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        } else {
          // ما عندك ستوري = الوضع العادي
          avatarWidget = Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgDark,
            ),
            child: CircleAvatar(
              radius: 33,
              backgroundColor: const Color(0xFF1A222C),
              backgroundImage: auth.profileImg.isNotEmpty
            ? CachedNetworkImageProvider(auth.profileImg)
                  : null,
              child: auth.profileImg.isEmpty
            ? const Icon(Iconsax.user, color: Colors.white30, size: 28)
                  : null,
            ),
          );
        }

        return Container(
          width: 78,
          margin: const EdgeInsets.only(left: 14),
          child: Column(
            children: [
              Stack(
                children: [
                  GestureDetector(
                    onTap: () {
  if (hasStories) {
    // عندك ستوري = افتحها
    Navigator.push(context, MaterialPageRoute(builder: (_) => Story(userId: currentUid)));
  } else {
    // ما عندك ستوري = افتح البروفايل
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }
},
                    child: avatarWidget,
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () {
                        // الزائد دايماً يفتح MediaPickerScreen
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MediaPickerScreen(),
                          ),
                        );
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: titiTeal,
                          shape: BoxShape.circle,
                          border: Border.all(color: surfaceCard, width: 2),
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hasStories? 'قصتك' : 'إنشاء',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserStoryItem(BuildContext context, String uid, String name, String profileImg, String currentUid) {
    return AudienceProfileGate(
      uid: uid,
      child: StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
    .collection('stories')
    .doc(uid)
    .collection('items')
    .where('expiresAt', isGreaterThan: Timestamp.now())
    .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs?? [];
        final hasStories = docs.isNotEmpty;
        final hasUnviewed = docs.any((d) {
          final viewedBy = List<String>.from(d['viewedBy']?? []);
          return!viewedBy.contains(currentUid);
        });

        final String initial = name.isNotEmpty? name.trim()[0].toUpperCase() : '?';
        final bool hasImage = profileImg.isNotEmpty;

        Widget avatarWidget;

        if (hasStories) {
          if (hasImage) {
            avatarWidget = StoryRing(
              imageUrl: profileImg,
              size: 72,
              hasStories: true,
              hasUnviewed: hasUnviewed,
              heroTag: 'story-bar-$uid',
            );
          } else {
            avatarWidget = GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => Story(userId: uid)));
              },
              child: Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: hasUnviewed
                  ? [const Color(0xFF00E5FF), titiTeal]
                        : [const Color(0xFF444444), const Color(0xFF444444)],
                  ),
                ),
                child: CircleAvatar(
                  radius: 33,
                  backgroundColor: const Color(0xFF1A222C),
                  child: Text(
                    initial,
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          }
        } else {
          avatarWidget = Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF0F1720),
            ),
            child: CircleAvatar(
              radius: 33,
              backgroundColor: const Color(0xFF1A222C),
              backgroundImage: hasImage? CachedNetworkImageProvider(profileImg) : null,
              child:!hasImage
            ? Text(
                      initial,
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
          );
        }

        return GestureDetector(
          onTap: () async {
            if (!AudienceAccess.instance.canViewProfile(uid)) return;
            if (hasStories) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => Story(userId: uid)));
            } else {
              final chatProvider = Provider.of<ChatProvider>(context, listen: false);
              await chatProvider.startChat(
                viewedUid: uid,
                displayFullName: name,
                displayProfileImg: profileImg,
                isFriend: true,
              );
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      viewedUid: uid,
                      displayFullName: name,
                      displayProfileImg: profileImg,
                      isFriend: true,
                    ),
                  ),
                );
              }
            }
          },
          child: Container(
            width: 78,
            margin: const EdgeInsets.only(left: 14),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    avatarWidget,
                    if (hasStories)
                      Positioned(
                        bottom: 0,
                        left: 4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: titiTeal,
                            shape: BoxShape.circle,
                            border: Border.all(color: surfaceCard, width: 2),
                          ),
                          child: const Icon(Iconsax.video_play, color: Colors.white, size: 10),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  name.isNotEmpty? name.split(' ').first : 'مستخدم',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }
}