import 'dart:math';
import 'audience_access.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
import 'profile_screen.dart';
import 'post_view_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PeopleYouMayKnowCarousel extends StatefulWidget {
  final VoidCallback? onEmpty;
  const PeopleYouMayKnowCarousel({super.key, this.onEmpty});
  static int getRandomPosition() {
    return Random().nextInt(1000);
  }
  @override
  State<PeopleYouMayKnowCarousel> createState() => _PeopleYouMayKnowCarouselState();
}

class _PeopleYouMayKnowCarouselState extends State<PeopleYouMayKnowCarousel> {
  final PageController _pageController = PageController(viewportFraction: 0.92);
  List<Map<String, dynamic>> _suggested = [];
  Map<String, List<DocumentSnapshot>> _postsCache = {};
  Map<String, List<String>> _mutualNames = {};
  Map<String, bool> _isFollower = {};
  int _currentPage = 0;
  bool _isEnabled = true;
  String? _loadedForUid;
  int _loadGeneration = 0;

    final List<List<Color>> _bgGradients = [
    [Color(0xFF1A222C), Color(0xFF1E3A3A)],
    [Color(0xFF1A222C), Color(0xFF3A1E2A)],
    [Color(0xFF1A222C), Color(0xFF2E3A1E)],
    [Color(0xFF1A222C), Color(0xFF1E2A3A)],
    [Color(0xFF1A222C), Color(0xFF3A2E1E)],
    [Color(0xFF1A222C), Color(0xFF2A1E3A)],
    [Color(0xFF1A222C), Color(0xFF1E3A2E)],
    [Color(0xFF1A222C), Color(0xFF3A1E1E)],
    [Color(0xFF1A222C), Color(0xFF1E2E3A)],
    [Color(0xFF1A222C), Color(0xFF3A3320)],
    [Color(0xFF1A222C), Color(0xFF2A3A1E)],
    [Color(0xFF1A222C), Color(0xFF3A1E33)],
    [Color(0xFF1A222C), Color(0xFF1E393A)],
    [Color(0xFF1A222C), Color(0xFF342A1E)],
    [Color(0xFF1A222C), Color(0xFF2D1E3A)],
    [Color(0xFF1A222C), Color(0xFF1E3A35)],
    [Color(0xFF1A222C), Color(0xFF3A211E)],
    [Color(0xFF1A222C), Color(0xFF1E263A)],
    [Color(0xFF1A222C), Color(0xFF3A2E28)],
    [Color(0xFF1A222C), Color(0xFF223A1E)],
    [Color(0xFF1A222C), Color(0xFF3A1E26)],
    [Color(0xFF1A222C), Color(0xFF1E343A)],
    [Color(0xFF1A222C), Color(0xFF3A301E)],
    [Color(0xFF1A222C), Color(0xFF2E1E3A)],
    [Color(0xFF1A222C), Color(0xFF1E3A28)],
    [Color(0xFF1A222C), Color(0xFF3A271E)],
    [Color(0xFF1A222C), Color(0xFF1E2D3A)],
    [Color(0xFF1A222C), Color(0xFF3A1E2E)],
    [Color(0xFF1A222C), Color(0xFF303A1E)],
    [Color(0xFF1A222C), Color(0xFF251E3A)],
  ];

      @override
  void initState() {
    super.initState();
    _loadedForUid = FirebaseAuth.instance.currentUser?.uid;
    AudienceAccess.instance.addListener(_onAudienceChanged);
    _checkIfEnabled();
  }

  @override
  void dispose() {
    AudienceAccess.instance.removeListener(_onAudienceChanged);
    _loadGeneration++;
    _pageController.dispose();
    super.dispose();
  }

  void _onAudienceChanged() {
    if (!mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_loadedForUid != uid) {
      _loadedForUid = uid;
      _suggested.clear();
      _postsCache.clear();
      _mutualNames.clear();
      _isFollower.clear();
      _currentPage = 0;
      _checkIfEnabled();
    }
    setState(() {});
  }

  Future<void> _checkIfEnabled() async {
    final generation = ++_loadGeneration;
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    final prefs = await SharedPreferences.getInstance();
    bool localVal = prefs.getBool('people_you_may_know_2')?? true;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid!= null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.data()?['notificationSettings']?['people_you_may_know_2'] is bool) {
          localVal = doc.data()!['notificationSettings']['people_you_may_know_2'];
        }
      } catch(e){}
    }

    if (!mounted || generation != _loadGeneration ||
        viewerUid != FirebaseAuth.instance.currentUser?.uid) return;
    if (!localVal) {
      setState(() => _isEnabled = false);
      return; // لا تحمل أي شيء
    }
    _isEnabled = true;
    _loadSuggestedWithMutuals();
  }

 Future<List<Map<String, dynamic>>> _fetchUsersByIds(List<String> ids) async {
  if (ids.isEmpty) return [];
  try {
    final docs = await Future.wait(
      ids.map((id) async {
        try {
          return await FirebaseFirestore.instance
             .collection('users')
             .doc(id)
             .get();
        } catch (_) {
          return null;
        }
      }),
    );

    return docs
       .where((d) => d!= null && d!.exists)
       .map((d) => {'uid': d!.id,...d!.data()! as Map<String, dynamic>})
       .toList();
  } catch (_) {
    return [];
  }
}

  Future<void> _loadSuggestedWithMutuals() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final generation = _loadGeneration;
    if (myUid == null) return;
    final followerStatus = <String, bool>{};
    final postsCache = <String, List<DocumentSnapshot>>{};
    final mutualNames = <String, List<String>>{};
    final hiddenSnap = await FirebaseFirestore.instance.collection('users').doc(myUid).collection('hiddenSuggestions').get();
    final hiddenIds = hiddenSnap.docs.map((d) => d.id).toSet();
    // [HARD BLOCK - مركزي Set]
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(myUid).get();
    final List blockedFromField = userDoc.data()?['blockedUsers']?? userDoc.data()?['blocked']?? [];
    final blockedIds = blockedFromField.map((e) => e.toString()).toSet();
    final myFollowingSnap = await FirebaseFirestore.instance.collection('users').doc(myUid).collection('following').get();
    final myFollowingIds = myFollowingSnap.docs.map((d) => d.id).toList();
    final myFollowingUsers = await _fetchUsersByIds(myFollowingIds);
    final myFollowingNamesMap = {for (var u in myFollowingUsers) u['uid']: (u['fullName']?? 'صديق')};
    final myFollowersSnap = await FirebaseFirestore.instance.collection('users').doc(myUid).collection('followers').get();
    final myFollowersIds = myFollowersSnap.docs.map((d) => d.id).toList();
    Map<String, int> baseScore = {};
    Map<String, List<String>> candidateToMutuals = {};
    for (var followerId in myFollowersIds) {
      if (followerId == myUid || myFollowingIds.contains(followerId) || hiddenIds.contains(followerId) || blockedIds.contains(followerId)) continue;
      baseScore[followerId] = 10;
      followerStatus[followerId] = true;
    }
    if (myFollowingIds.isNotEmpty) {
      final futures = myFollowingIds.map((uid) => FirebaseFirestore.instance.collection('users').doc(uid).collection('following').get());
      final snaps = await Future.wait(futures);
      for (int i = 0; i < snaps.length; i++) {
        final followingId = myFollowingIds[i];
        final snap = snaps[i];
        for (var doc in snap.docs) {
          final candidateId = doc.id;
          if (candidateId == myUid || myFollowingIds.contains(candidateId) || hiddenIds.contains(candidateId) || blockedIds.contains(candidateId)) continue;
          baseScore[candidateId] = (baseScore[candidateId]?? 0) + 1;
          candidateToMutuals.putIfAbsent(candidateId, () => []).add(myFollowingNamesMap[followingId]?? 'صديق');
          if (!followerStatus.containsKey(candidateId)) {
            followerStatus[candidateId] = false;
          }
        }
      }
    }
    List<Map<String, dynamic>> users = [];
    if (baseScore.isEmpty) {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      users = snap.docs.where((d) => d.id!= myUid &&!myFollowingIds.contains(d.id) &&!hiddenIds.contains(d.id) &&!blockedIds.contains(d.id)).map((d) => {'uid': d.id,...d.data() as Map<String, dynamic>}).toList();
    } else {
      final candidateIds = baseScore.keys.toList()..sort((a, b) => baseScore[b]!.compareTo(baseScore[a]!));
      users = await _fetchUsersByIds(candidateIds);
      users.sort((a, b) => (baseScore[b['uid']]?? 0).compareTo(baseScore[a['uid']]?? 0));
    }
    if (!mounted || generation != _loadGeneration ||
        myUid != FirebaseAuth.instance.currentUser?.uid) return;
    if (users.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onEmpty?.call();
      });
      return;
    }
    for (var u in users) {
      final uid = u['uid'] as String;
      final posts = await FirebaseFirestore.instance.collection('posts').where('uid', isEqualTo: uid).orderBy('createdAt', descending: true).limit(3).get();
      postsCache[uid] = posts.docs;
      mutualNames[uid] = candidateToMutuals[uid]?? [];
    }
    if (mounted && generation == _loadGeneration &&
        myUid == FirebaseAuth.instance.currentUser?.uid) {
      setState(() {
        _suggested = users;
        _postsCache = postsCache;
        _mutualNames = mutualNames;
        _isFollower = followerStatus;
      });
    }
  }

  String _getSubText(String uid) {
    final isFollower = _isFollower[uid]?? false;
    final mutuals = _mutualNames[uid]?? [];
    if (isFollower && mutuals.isEmpty) return "يتابعك";
    if (isFollower && mutuals.isNotEmpty) return "يتابعك • يتابعه ${mutuals.first}";
    if (mutuals.isEmpty) return "أشخاص قد تعرفهم";
    if (mutuals.length == 1) return "يتابعه ${mutuals.first}";
    if (mutuals.length == 2) return "يتابعه ${mutuals.first} وشخص آخر";
    return "يتابعه ${mutuals.first} و ${mutuals.length - 1} آخرين";
  }

  Future<void> _openUserPosts(BuildContext context, String uid, String tappedPostId) async {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final snap = await FirebaseFirestore.instance.collection('posts').where('uid', isEqualTo: uid).orderBy('createdAt', descending: true).get();
      if (!context.mounted || viewerUid != FirebaseAuth.instance.currentUser?.uid ||
          !AudienceAccess.instance.canViewProfile(uid)) return;
      final allPosts = snap.docs.where((doc) =>
        AudienceAccess.instance.canViewPost(doc.data(), postId: doc.id)).toList();
      if (allPosts.isEmpty) return;
      final int safeIndex = allPosts.indexWhere((doc) => doc.id == tappedPostId);
      if (safeIndex < 0) return;
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostViewScreen(
            posts: allPosts,
            initialIndex: safeIndex,
            isFromProfileGrid: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint("openUserPosts error: $e");
    }
  }

  void _safeRemove(String uid) {
    if (!mounted) return;
    setState(() => _suggested.removeWhere((user) => user['uid'] == uid));
    if (_suggested.isEmpty) {
      widget.onEmpty?.call();
    }
  }

    @override
  Widget build(BuildContext context) {
    if (!_isEnabled) return const SizedBox.shrink(); // <-- الزر مطفي
    if (_loadedForUid != FirebaseAuth.instance.currentUser?.uid) {
      return const SizedBox.shrink();
    }
    final suggested = _suggested.where((user) =>
      AudienceAccess.instance.canViewProfile(user['uid'] as String)).toList();
    if (suggested.isEmpty) return const SizedBox.shrink();
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final bgColor = _suggested.isNotEmpty
 ? _bgGradients[_currentPage % _bgGradients.length][1]
        : const Color(0xFF0F1720);

    final bool isSmall = screenHeight < 750;
    final double cardHeight = isSmall? 390 : 430;
    final double avatarRadius = isSmall? 42 : 50;
    final double postHeight = isSmall? 95 : 110;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: screenWidth,
      height: screenHeight,
      color: bgColor,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
                    SizedBox(
            height: cardHeight,
            width: screenWidth,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (page) {
                if (page!= _currentPage && mounted) {
                  setState(() => _currentPage = page);
                }
              },
              physics: const PageScrollPhysics(),
              itemCount: suggested.length,
              itemBuilder: (context, index) {
                final user = suggested[index];
                final uid = user['uid'] as String;
                final name = user['fullName']?? 'مستخدم';
                final avatar = user['profileImg']?? '';
                final posts = (_postsCache[uid]?? []).where((doc) {
                  final data = doc.data() as Map<String, dynamic>?;
                  return data != null && AudienceAccess.instance.canViewPost(
                    data, postId: doc.id);
                }).toList();
                final subText = _getSubText(uid);
                final gradient = _bgGradients[index % _bgGradients.length];
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _safeRemove(uid),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 16, color: Colors.white70),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid))),
                        child: avatar.isNotEmpty
                      ? CachedNetworkImage(
                              imageUrl: avatar,
                              cacheKey: avatar,
                              imageBuilder: (c, p) => CircleAvatar(radius: avatarRadius, backgroundColor: Colors.grey.shade800, backgroundImage: p),
                              placeholder: (c, u) => CircleAvatar(radius: avatarRadius, backgroundColor: Colors.grey.shade800),
                              errorWidget: (c, u, e) => CircleAvatar(radius: avatarRadius, backgroundColor: Colors.grey.shade800, child: Text(name.isNotEmpty? name[0].toUpperCase() : '?', style: TextStyle(fontSize: isSmall? 30 : 36, color: Colors.white, fontWeight: FontWeight.bold))),
                            )
                          : CircleAvatar(
                              radius: avatarRadius,
                              backgroundColor: Colors.grey.shade800,
                              child: Text(name.isNotEmpty? name[0].toUpperCase() : '?', style: TextStyle(fontSize: isSmall? 30 : 36, color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                      ),
                      SizedBox(height: isSmall? 8 : 12),
                      Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(subText, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                      SizedBox(height: isSmall? 10 : 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: List.generate(3, (i) {
                            if (i >= posts.length) {
                              return Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 4), height: postHeight, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12))));
                            }
                            final data = posts[i].data() as Map<String, dynamic>;
                            final thumb = data['thumbnailUrl']?? '';
                            final views = (data['views']?? 0).toString();
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (AudienceAccess.instance.canViewPost(data,
                                      postId: posts[i].id)) {
                                    _openUserPosts(context, uid, posts[i].id);
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  height: postHeight,
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.black),
                                  child: Stack(
                                    children: [
                                      if (thumb.isNotEmpty)
                                        Positioned.fill(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover),
                                          ),
                                        ),
                                      Positioned(
                                        bottom: 5,
                                        left: 5,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                                          child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.play_arrow, size: 12, color: Colors.white), const SizedBox(width: 2), Text(views, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))]),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  Provider.of<custom.AuthProvider>(context, listen: false).toggleFollow(uid);
                                  _safeRemove(uid);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFE2C55),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  elevation: 0,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text("متابعة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  final myUid = FirebaseAuth.instance.currentUser?.uid;
                                  if (myUid!= null) {
                                    await FirebaseFirestore.instance.collection('users').doc(myUid).collection('hiddenSuggestions').doc(uid).set({'createdAt': FieldValue.serverTimestamp()});
                                  }
                                  if (mounted) {
                                    _safeRemove(uid);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  elevation: 0,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text("غير مهتم", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: Colors.white.withValues(alpha: 0.5)),
              SizedBox(width: 4),
              Text(
                "اسحب للأعلى لمتابعة المشاهدة",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}