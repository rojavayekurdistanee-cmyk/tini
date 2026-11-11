import 'user_documents.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom;
import 'block_service.dart'; // [المركز]
import 'profile_screen.dart';
import 'story.dart';
import 'story_ring.dart';
import 'activity_status_service.dart'; // [حالة النشاط
import 'package:cached_network_image/cached_network_image.dart';

class FollowListScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final int initialTab;
  const FollowListScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.initialTab = 0,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<String> _getOwnerPrivacy() async {
    try {
      final doc = await UserDocuments.readable(FirebaseFirestore.instance, widget.userId).get();
      return doc.data()?['whoCanSeeFollowingList'] ?? 'follow_list_public';
    } catch (_) {
      return 'follow_list_public';
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUsersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final docs = await Future.wait(
      ids.map((id) => UserDocuments.readable(FirebaseFirestore.instance, id).get()),
    );
    return docs.where((d) => d.exists).map((d) => {'uid': d.id,...d.data() as Map<String, dynamic>}).toList();
  }

  Stream<List<Map<String, dynamic>>> _followingStream() {
    return FirebaseFirestore.instance
 .collection('users')
 .doc(widget.userId)
 .collection('following')
 .snapshots()
 .asyncMap((snap) async {
          if (snap.docs.isEmpty) return [];
          final ids = snap.docs.toList()
       ..sort((a,b){
              final ta = (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch?? 0;
              final tb = (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch?? 0;
              return tb.compareTo(ta);
            });
          return _fetchUsersByIds(ids.map((d)=>d.id).toList());
        });
  }

  Stream<List<Map<String, dynamic>>> _followersStream() {
    return FirebaseFirestore.instance
 .collection('users')
 .doc(widget.userId)
 .collection('followers')
 .snapshots()
 .asyncMap((snap) async {
          if (snap.docs.isEmpty) return [];
          final ids = snap.docs.toList()
       ..sort((a,b){
              final ta = (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch?? 0;
              final tb = (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch?? 0;
              return tb.compareTo(ta);
            });
          return _fetchUsersByIds(ids.map((d)=>d.id).toList());
        });
  }

  Stream<List<Map<String, dynamic>>> _friendsStream() {
    // أصدقاء = تقاطع following و followers
    return FirebaseFirestore.instance
 .collection('users')
 .doc(widget.userId)
 .collection('following')
 .snapshots()
 .asyncMap((followingSnap) async {
          if (followingSnap.docs.isEmpty) return [];
          final followingIds = followingSnap.docs.map((d)=>d.id).toSet();

          final followersSnap = await FirebaseFirestore.instance
       .collection('users')
       .doc(widget.userId)
       .collection('followers')
       .get();

          final followersIds = followersSnap.docs.map((d)=>d.id).toSet();
          final mutual = followingIds.intersection(followersIds).toList();
          return _fetchUsersByIds(mutual);
        });
  }

  Stream<List<Map<String, dynamic>>> _suggestedStream() {
    return FirebaseFirestore.instance
.collection('users')
.doc(widget.userId)
.collection('following')
.snapshots()
.asyncMap((myFollowingSnap) async {
          final myFollowingIds = myFollowingSnap.docs.map((d)=>d.id).toList();

          // إذا ما بتتابع حدا، رجع عينة عشوائية مفلترة
          if (myFollowingIds.isEmpty) {
            final snap = await FirebaseFirestore.instance
       .collection('public_profiles')
       .where('profileImg', isNotEqualTo: '')
       .limit(30)
       .get();
            return snap.docs
       .where((d) => d.id!= widget.userId)
       .map((d) => {'uid': d.id,...d.data() as Map<String, dynamic>})
       .toList();
          }

          // جيب following لكل شخص أنت متابعه
          final futures = myFollowingIds.map((uid) =>
            FirebaseFirestore.instance.collection('users').doc(uid).collection('following').get()
          );
          final snaps = await Future.wait(futures);

          final Map<String, int> baseScore = {};
          for (var snap in snaps) {
            for (var doc in snap.docs) {
              final candidateId = doc.id;
              if (candidateId == widget.userId || myFollowingIds.contains(candidateId)) continue;
              baseScore[candidateId] = (baseScore[candidateId]?? 0) + 1;
            }
          }

          if (baseScore.isEmpty) return [];

          // جيب بيانات المرشحين
          final candidateIds = baseScore.keys.toList();
          final users = await _fetchUsersByIds(candidateIds);

          // فلترة + scoring
          final List<Map<String, dynamic>> scored = [];
          for (var user in users) {
            final String uid = user['uid'];
            final String img = user['profileImg']?? '';
            if (img.isEmpty) continue;

            final int followers = (user['followers']?? 0) as int;
            final int count = baseScore[uid]?? 0;

            final double boost = 1.0 + (followers / 10000.0).clamp(0.0, 1.0);
            final double finalScore = count * boost;

            scored.add({...user, '_score': finalScore});
          }

          scored.sort((a, b) => (b['_score'] as double).compareTo(a['_score'] as double));

          return scored.take(30).map((u) {
            u.remove('_score');
            return u;
          }).toList();
        });
  }

  void _openProfile(String uid) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)));
  }

  void _toggleFollow(String targetUid) {
    Provider.of<custom.AuthProvider>(context, listen: false).toggleFollow(targetUid);
  }

  void _removeFollower(String followerUid) {
    Provider.of<custom.AuthProvider>(context, listen: false).removeFollower(followerUid);
  }

  void _showOptionsSheet(String type, String name, String uid) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            if (type == 'following')
              _buildSheetAction('إلغاء المتابعة', Colors.redAccent, () {
                Navigator.pop(context);
                _toggleFollow(uid);
              }),
            if (type == 'followers')
              _buildSheetAction('إزالة هذا المتابع', Colors.redAccent, () {
                Navigator.pop(context);
                _removeFollower(uid);
              }),
            const Divider(color: Colors.white10, thickness: 5),
            _buildSheetAction('إلغاء', Colors.white, () => Navigator.pop(context), isBold: true),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetAction(String text, Color color, VoidCallback onTap, {bool isBold = false}) {
    return Material(
  color: Colors.transparent,
  child: InkWell(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 16, fontWeight: isBold? FontWeight.bold : FontWeight.normal)),
    ),
  ),
);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: titiTeal,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: 'أتابعه'),
            Tab(text: 'متابعون'),
            Tab(text: 'الأصدقاء'),
            Tab(text: 'مقترح'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildListTab(_followingStream(), 'following'),
                _buildListTab(_followersStream(), 'followers'),
                _buildListTab(_friendsStream(), 'friends'),
                _buildListTab(_suggestedStream(), 'suggested'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Container(
        height: 40,
        decoration: BoxDecoration(color: Colors.white.withAlpha(13), borderRadius: BorderRadius.circular(8)),
        child: TextField(
          controller: _searchController,
          textAlign: TextAlign.right,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'بحث',
            hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
            prefixIcon: Icon(Iconsax.search_normal, color: Colors.grey, size: 18),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildListTab(Stream<List<Map<String, dynamic>>> stream, String type) {
    return FutureBuilder<String>(
      future: _getOwnerPrivacy(),
      builder: (context, privacySnap) {
        final String ownerPrivacy = privacySnap.data ?? 'follow_list_public';
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.teal));
            }
            final rawList = snapshot.data?? [];
            final blockedSet = Provider.of<custom.AuthProvider>(context).blockedUsersSet; // [المركز Set]
            var list = BlockService.filterBlockedMaps(rawList, blockedSet); // [HARD BLOCK - مركزي]

            // [FOLLOW LIST PRIVACY - OWNER FRIENDS ONLY - يحل مثال علي]
            final auth = Provider.of<custom.AuthProvider>(context, listen: false);
            final bool isOwner = FirebaseAuth.instance.currentUser?.uid == widget.userId;
            if (!isOwner && ownerPrivacy == 'follow_list_mutual') {
              final bool viewerIsFriendWithOwner = auth.followingList.contains(widget.userId) && auth.followersList.contains(widget.userId);
              if (!viewerIsFriendWithOwner) {
                list = [];
              } else {
                // فلترة على أصدقائي أنا صاحب البروفايل فقط
                // علي بيتابعني بس أنا مو متابعه -> مو صديقي -> ما رح يطلع لأحمد نهائي
                return FutureBuilder<List<String>>(
                  future: () async {
                    final followingSnap = await FirebaseFirestore.instance.collection('users').doc(widget.userId).collection('following').get();
                    final followersSnap = await FirebaseFirestore.instance.collection('users').doc(widget.userId).collection('followers').get();
                    final f1 = followingSnap.docs.map((d) => d.id).toSet();
                    final f2 = followersSnap.docs.map((d) => d.id).toSet();
                    return f1.intersection(f2).toList();
                  }(),
                  builder: (context, ownerFriendsSnap) {
                    if (!ownerFriendsSnap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.teal));
                    }
                    final ownerFriendsSet = ownerFriendsSnap.data!.toSet();
                    var ownerFilteredList = list.where((u) => ownerFriendsSet.contains(u['uid'] as String)).toList();

                    final filtered2 = _searchQuery.isEmpty
                       ? ownerFilteredList
                        : ownerFilteredList.where((u) {
                            final name = (u['fullName']?? '').toString().toLowerCase();
                            final username = (u['username']?? '').toString().toLowerCase();
                            return name.contains(_searchQuery) || username.contains(_searchQuery);
                          }).toList();

                    if (filtered2.isEmpty) return _buildEmptyState();

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      itemCount: filtered2.length,
                      itemBuilder: (context, index) {
                        final user = filtered2[index];
                        final uid = user['uid'] as String;
                        final name = user['fullName']?? '';
                        final username = user['username']?? '';
                        final avatar = user['profileImg']?? '';
                        return FadeInUp(
                          duration: Duration(milliseconds: 200 + (index * 30)),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _openProfile(uid),
                                    behavior: HitTestBehavior.opaque,
                                    child: Row(
                                      children: [
                                        _buildAvatar(uid, avatar, name),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                              Text('@$username', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                                              FutureBuilder<bool>(
                                                future: ActivityStatusService.isMutualFriend(FirebaseAuth.instance.currentUser!.uid, uid),
                                                builder: (context, friendSnap) {
                                                  if (friendSnap.data!= true) return const SizedBox.shrink();
                                                  return StreamBuilder<DocumentSnapshot>(
                                                    stream: UserDocuments.readable(FirebaseFirestore.instance, uid).snapshots(),
                                                    builder: (context, userSnap) {
                                                      if (!userSnap.hasData ||!userSnap.data!.exists) return const SizedBox.shrink();
                                                      final liveUserData = userSnap.data!.data() as Map<String, dynamic>;
                                                      final bool targetShow = liveUserData['showActivityStatus']?? true;
                                                      final bool isOnline = liveUserData['isOnline']?? false;
                                                      final Timestamp? lastSeen = liveUserData['lastSeen'] as Timestamp?;
                                                      return StreamBuilder<DocumentSnapshot>(
                                                        stream: UserDocuments.readable(FirebaseFirestore.instance, FirebaseAuth.instance.currentUser!.uid).snapshots(),
                                                        builder: (context, mySnap) {
                                                          final myData = mySnap.data?.data() as Map<String, dynamic>?;
                                                          final bool myShow = myData?['showActivityStatus']?? true;
                                                          if (!ActivityStatusService.canViewStatus(myShowActivity: myShow, targetShowActivity: targetShow)) {
                                                            return const SizedBox.shrink();
                                                          }
                                                          return Text(ActivityStatusService.formatLastSeenFromTimestamp(lastSeen, isOnline), style: TextStyle(color: isOnline? Colors.greenAccent : Colors.white38, fontSize: 11));
                                                        },
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _buildActionButton(uid, type),
                                if (type!= 'suggested')...[
                                  const SizedBox(width: 10),
                                  GestureDetector(onTap: () => _showOptionsSheet(type, name, uid), child: Icon(Icons.more_vert, color: Colors.grey.shade600, size: 20)),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              }
            }
            // [END OWNER FRIENDS ONLY]

            final filtered = _searchQuery.isEmpty
        ? list
                : list.where((u) {
                    final name = (u['fullName']?? '').toString().toLowerCase();
                    final username = (u['username']?? '').toString().toLowerCase();
                    return name.contains(_searchQuery) || username.contains(_searchQuery);
                  }).toList();

        if (filtered.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final user = filtered[index];
            final uid = user['uid'] as String;
            final name = user['fullName']?? '';
            final username = user['username']?? '';
            final avatar = user['profileImg']?? '';

            return FadeInUp(
              duration: Duration(milliseconds: 200 + (index * 30)),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openProfile(uid),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            _buildAvatar(uid, avatar, name), // [مُصحح] مررنا الاسم للحرف
                            const SizedBox(width: 12),
                                                        Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text('@$username', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
// [حالة النشاط - اصدقاء + زر النشاط] - النسخة الصحيحة اللحظية
FutureBuilder<bool>(
  future: ActivityStatusService.isMutualFriend(
    FirebaseAuth.instance.currentUser!.uid,
    uid,
  ),
  builder: (context, friendSnap) {
    if (friendSnap.data != true) return const SizedBox.shrink();
    
    // هون التعديل المهم: StreamBuilder على وثيقة اليوزر نفسه
    return StreamBuilder<DocumentSnapshot>(
      stream: UserDocuments.readable(FirebaseFirestore.instance, uid).snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData || !userSnap.data!.exists) return const SizedBox.shrink();
        
        final liveUserData = userSnap.data!.data() as Map<String, dynamic>;
        final bool targetShow = liveUserData['showActivityStatus'] ?? true;
        final bool isOnline = liveUserData['isOnline'] ?? false;
        final Timestamp? lastSeen = liveUserData['lastSeen'] as Timestamp?;
        
        // StreamBuilder على وثيقتك انت عشان زر النشاط
        return StreamBuilder<DocumentSnapshot>(
          stream: UserDocuments.readable(FirebaseFirestore.instance, FirebaseAuth.instance.currentUser!.uid).snapshots(),
          builder: (context, mySnap) {
            final myData = mySnap.data?.data() as Map<String, dynamic>?;
            final bool myShow = myData?['showActivityStatus'] ?? true;
            
            if (!ActivityStatusService.canViewStatus(myShowActivity: myShow, targetShowActivity: targetShow)) {
              return const SizedBox.shrink();
            }
            
            return Text(
              ActivityStatusService.formatLastSeenFromTimestamp(lastSeen, isOnline),
              style: TextStyle(
                color: isOnline ? Colors.greenAccent : Colors.white38,
                fontSize: 11,
              ),
            );
          },
        );
      },
    );
  },
),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildActionButton(uid, type),
                    if (type!= 'suggested')...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _showOptionsSheet(type, name, uid),
                        child: Icon(Icons.more_vert, color: Colors.grey.shade600, size: 20),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  );
  }

  // [مُصحح] رجعنا منطق الحرف كامل
  Widget _buildAvatar(String uid, String url, String name) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
       .collection('stories')
       .doc(uid)
       .collection('items')
       .where('expiresAt', isGreaterThan: Timestamp.now())
       .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs?? [];
        final currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
        final hasStories = docs.isNotEmpty;
        final hasUnviewed = docs.any((d) {
          final viewedBy = List<String>.from(d['viewedBy']?? []);
          return!viewedBy.contains(currentUid);
        });

        final bool hasImage = url.isNotEmpty;
        final String initial = name.isNotEmpty? name[0].toUpperCase() : '?';

        if (hasStories) {
          return StoryRing(
            imageUrl: url,
            size: 56,
            hasStories: true,
            hasUnviewed: hasUnviewed,
            heroTag: 'follow-avatar-$uid',
          );
                                } else if (hasImage) {
          return CachedNetworkImage(
            imageUrl: url,
            cacheKey: url,
            useOldImageOnUrlChange: false,
            imageBuilder: (context, imageProvider) => CircleAvatar(radius: 28, backgroundImage: imageProvider),
            placeholder: (context, u) => CircleAvatar(radius: 28, backgroundColor: Colors.grey[800]),
            errorWidget: (context, u, e) => CircleAvatar(radius: 28, backgroundColor: Colors.grey[800], child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
          );
        } else {
          return CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey[800],
            child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          );
        }
      },
    );
  }

  Widget _buildActionButton(String targetUid, String type) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (targetUid == currentUid) return const SizedBox.shrink();

    if (type == 'suggested') {
      return _customButton('متابعة', isPrimary: true, onTap: () => _toggleFollow(targetUid), width: 80);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(currentUid).collection('following').doc(targetUid).snapshots(),
      builder: (context, snap) {
        final isFollowing = snap.hasData && snap.data!.exists;
        final String followText = type == 'followers'? 'رد المتابعة' : 'متابعة';
        return _customButton(isFollowing? 'إلغاء' : followText, isPrimary:!isFollowing, onTap: () => _toggleFollow(targetUid));
      },
    );
  }

  Widget _customButton(String text, {bool isPrimary = false, VoidCallback? onTap, double? width}) {
    return SizedBox(
      width: width,
      height: 32,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary? titiTeal : Colors.white10,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Iconsax.user_remove, size: 60, color: titiTeal.withAlpha(51)),
          const SizedBox(height: 15),
          Text('لا توجد بيانات هنا حالياً', style: TextStyle(color: Colors.white.withAlpha(128))),
        ],
      ),
    );
  }
}