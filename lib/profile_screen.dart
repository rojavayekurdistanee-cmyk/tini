import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'dart:ui';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom;
import 'settings_screen.dart';
import 'activities_screen.dart';
import 'post_view_screen.dart';
import 'follow_list_screen.dart';
import 'chat_provider.dart';
import 'chat_screen.dart';
import 'story.dart';
import 'story_ring.dart';
import 'wallet_screen.dart';
import 'app_colors.dart';
import 'visits_door_button.dart'; // زر باب الزيارات
import 'visits_screen.dart';
import 'home_screen.dart';
import 'activity_status_service.dart'; // [حالة النشاط]
import 'titi_single_engine.dart';
import 'titi_profile_engine.dart';
import 'share_profile_sheet.dart';
import 'open_link_with_settings.dart';
import 'package:flutter/rendering.dart';
import 'audience_access.dart';
import 'throne_earned_badge.dart';

/*
  [Tini Project - The Radar Trigger V3]
  تحديث ميكانيكا البروفايل "الرادار":
    1. تفعيل نظام الرادار السداسي لربط الشبكة بالمحركات الصامتة.
    2. بمجرد ظهور الفيديوهات على الشاشة، يتم إرسال روابطها للبروفايدر للشحن.
    3. الحفاظ على سرعة "المزعار" في الانتقال مع تصفير المحركات عند اللمس.
*/

class ProfileSubMenu extends StatelessWidget {
  const ProfileSubMenu({super.key});

  @override
  Widget build(BuildContext context) {
    const Color bgColor = Color(0xFF0F1720);
    const Color titiTeal = Colors.teal;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
  onPressed: () {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
        (route) => false,
      );
    }
  },
),
        title: const Text(
          "الإعدادات",
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
        children: [
          _buildSettingsTile(
            icon: Iconsax.activity,
            title: "الأنشطة",
            color: titiTeal,
            onTap: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const ActivitiesScreen(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildSettingsTile(
            icon: Iconsax.setting_2,
            title: "الإعدادات والخصوصية",
            color: titiTeal,
            onTap: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const SettingsScreen(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return Material(
      color: const Color(0xFF1A222C),
      borderRadius: BorderRadius.circular(15),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        leading: Icon(icon, color: color),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
        onTap: onTap,
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final String? userId;
  final VoidCallback? onBackToHome;
  const ProfileScreen({super.key, this.userId, this.onBackToHome});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late TabController _tabController;

  // [Tini - Dynamic Profile Tabs]: التبويبات المبنية على المحتوى والصلاحيات.
  List<String> _visibleProfileTabs = ['posts', 'shares'];
  Map<String, dynamic>? _liveProfilePrivacy;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profilePrivacySub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _followAccessSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _likedPresenceSub;
  StreamSubscription<bool>? _favoritesPresenceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _privatePresenceSub;
  bool _hasPrivatePosts = false;
  bool _canReadLikedPosts = false;
  bool _canReadFavorites = false;
  bool _hasLikedPosts = false;
  bool _hasFavorites = false;

  // [Tini - Visits Door] إبقاء اشتراك الزيارات ثابتاً أثناء إعادة بناء البروفايل.
  String? _visitsStreamUserId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _visitsOverviewStream;

  Stream<QuerySnapshot<Map<String, dynamic>>> _visitsStreamFor(String userId) {
    if (_visitsOverviewStream == null || _visitsStreamUserId != userId) {
      _visitsStreamUserId = userId;
      _visitsOverviewStream = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('visits')
          .orderBy('timestamp', descending: true)
          .snapshots();
    }
    return _visitsOverviewStream!;
  }

  Stream<QuerySnapshot>? postsStream;

  final Color bgColor = const Color(0xFF0F1720);
  final Color titiTeal = Colors.teal;
  final Color surfaceColor = const Color(0xFF1A222C);

  // إضافة دعم عرض بروفايل مستخدم آخر
  Map<String, dynamic>? viewedUserData;
  bool isOwnProfile = true;
  String viewedUid = '';
  String followingStatus = 'none'; // none / following / follower / friends

  // [AUDIENCE CONTROL - ADDITION]
  final AudienceAccess _audience = AudienceAccess.instance;
  List<DocumentSnapshot<Map<String, dynamic>>> _favoritePresencePosts = [];
  bool _viewerIsAdult = false;
  bool _viewedIsAdultContent = false;

  bool _checkIfUserIsAdultContent(Map<String, dynamic>? data) {
    // قرار الحساب من حالته الحالية، لا من حقول مالك منسوخة داخل الفيديو.
    return !_audience.canViewProfile(viewedUid);
  }

  void _onAudienceChanged() {
    if (!mounted) return;
    setState(() {
      isOwnProfile = viewedUid.isNotEmpty && viewedUid == (FirebaseAuth.instance.currentUser?.uid ?? '');
      _viewerIsAdult = _audience.isViewerAdult;
      _viewedIsAdultContent = !_audience.canViewProfile(viewedUid);
      _hasFavorites = _favoritePresencePosts.any((doc) =>
          _favoritePostIsVisible(doc.data(), doc.id));
    });
    _syncProfileTabAccess();
  }

  Future<void> _logProfileVisit(String profileOwnerId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    if (currentUser.uid == profileOwnerId) return;

    try {
      // 1. افحص اذا انت مطفي الزر - اذا مطفي لا تسجل زيارتك عند حدا
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      final myEnabled = (myDoc.data()?['isVisitsEnabled']?? true) as bool;
      if (!myEnabled) return;

      // 2. افحص اذا هو مطفي الزر - اذا مطفي لا تسجل عندو
      final ownerDoc = await FirebaseFirestore.instance.collection('users').doc(profileOwnerId).get();
      final ownerEnabled = (ownerDoc.data()?['isVisitsEnabled']?? true) as bool;
      if (!ownerEnabled) return;

      await FirebaseFirestore.instance
         .collection('users')
         .doc(profileOwnerId)
         .collection('visits')
         .doc(currentUser.uid)
         .set({
        'visitorId': currentUser.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'isSeen': false,
      }, SetOptions(merge: true));

      // 3. اضافة اشعار داخل شاشة النشاط
      await FirebaseFirestore.instance.collection('activities').add({
        'toUid': profileOwnerId,
        'fromUid': currentUser.uid,
        'type': 'view',
        'text': 'قام بزيارة ملفك الشخصي',
        'timestamp': FieldValue.serverTimestamp(),
        'seen': false,
      });

    } catch (e) {
      debugPrint("Visit log error: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _audience.addListener(_onAudienceChanged);

    final String currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
    viewedUid = widget.userId?? currentUid;
    isOwnProfile = viewedUid == currentUid;
    _visibleProfileTabs = ['posts', 'shares'];
    _tabController = TabController(length: _visibleProfileTabs.length, vsync: this);

    if (viewedUid.isNotEmpty) {
      if (isOwnProfile) {
        // [Tini - Private Tab]: لا يظهر القفل إلا إذا كان هناك فيديو خاص فعلي.
        _privatePresenceSub = FirebaseFirestore.instance.collection('posts')
            .where('uid', isEqualTo: viewedUid)
            .where('privacy', isEqualTo: 'private')
            .snapshots().listen((snapshot) {
          if (!mounted) return;
          _hasPrivatePosts = snapshot.docs.any((doc) => doc.data()['isDeleted'] != true);
          _updateVisibleProfileTabs();
        }, onError: (Object error) {
          debugPrint('Tini private posts visibility error: $error');
          if (!mounted) return;
          _hasPrivatePosts = false;
          _updateVisibleProfileTabs();
        });
        // AuthProvider يتابع مستند صاحب الحساب أصلاً؛ لا نكرر الاشتراك.
        _syncProfileTabAccess();
      } else {
        // افحص خصوصية الحساب لحظياً قبل إنشاء أي استعلام عن إعجاباته أو مفضلته.
        _profilePrivacySub = FirebaseFirestore.instance
            .collection('users').doc(viewedUid).snapshots().listen((snapshot) {
          if (!mounted) return;
          final data = snapshot.data();
          _liveProfilePrivacy = data;
          setState(() {
            viewedUserData = data;
            _viewedIsAdultContent = _checkIfUserIsAdultContent(data);
          });
          _syncProfileTabAccess();
        }, onError: (Object error) {
          debugPrint('Tini profile privacy read error: $error');
          _liveProfilePrivacy = null;
          _syncProfileTabAccess();
        });

        if (currentUid.isNotEmpty) {
          // تأكد من تحديث الصلاحيات بعد المتابعة أو إلغائها.
          _followAccessSub = FirebaseFirestore.instance
              .collection('users').doc(currentUid)
              .collection('following').doc(viewedUid).snapshots()
              .listen((_) => _fetchFollowingStatus(), onError: (Object error) {
                debugPrint('Tini profile follow permission error: $error');
              });
        }
      }
    }

    // هاد السطر الجديد يلي بيحفظ الزيارة
    if (!isOwnProfile && viewedUid.isNotEmpty) {
      _logProfileVisit(viewedUid);
    }

    if (viewedUid.isNotEmpty) {
      postsStream = FirebaseFirestore.instance
     .collection('posts')
     .where('uid', isEqualTo: viewedUid)
     .orderBy('createdAt', descending: true)
     .limit(30) // توفير: بدل ما يجيب 500 فيديو يجيب 30 بس
     .snapshots();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (isOwnProfile) {
            Provider.of<custom.AuthProvider>(context, listen: false).fetchUserData();
          } else {
            // بيانات الزائر والخصوصية تُحدّث الآن من الاشتراك المباشر أعلاه.
            // [AUDIENCE CONTROL] - حالة المشاهد الحالي
            try {
              _viewerIsAdult = _audience.isViewerAdult;
              // اذا البيانات لسه ما اجت، افحصها من viewedUserData القديم
              _viewedIsAdultContent = _checkIfUserIsAdultContent(viewedUserData);
            } catch (_) {
              _viewerIsAdult = false;
            }
          }
        }
      });
    }
  }

  Future<void> _fetchFollowingStatus() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || isOwnProfile) return;
    try {
      final followingDoc = await FirebaseFirestore.instance
     .collection('users')
     .doc(currentUid)
     .collection('following')
     .doc(viewedUid)
     .get();

      final followerDoc = await FirebaseFirestore.instance
     .collection('users')
     .doc(viewedUid)
     .collection('following')
     .doc(currentUid)
     .get();

      final amFollowing = followingDoc.exists;
      final isFollower = followerDoc.exists;

      String status = 'none';
      if (amFollowing && isFollower) status = 'friends';
      else if (amFollowing) status = 'following';
      else if (isFollower) status = 'follower';

      if (mounted && followingStatus != status) {
        setState(() {
          followingStatus = status;
        });
        _syncProfileTabAccess();
      }
    } catch (e) {
      debugPrint('Error fetching following status: $e');
    }
  }

  // [Tini - Dynamic Profile Tabs]: استعلام وجود واحد فقط، ولا نقرأ قائمة الزائر إلا إذا سُمح له.
  void _syncProfileTabAccess() {
    if (!mounted || viewedUid.isEmpty) return;
    final privacy = _liveProfilePrivacy;
    final isFollower = followingStatus == 'following' || followingStatus == 'friends';
    final visitorCanRead = !isOwnProfile && FirebaseAuth.instance.currentUser != null &&
        _audience.canViewProfile(viewedUid) && privacy != null && (privacy['isPrivate'] != true || isFollower);
    final allowLikes = isOwnProfile ||
        (visitorCanRead && privacy?['likedVideosPrivacy'] == 'everyone');
    final allowFavorites = isOwnProfile ||
        (visitorCanRead && privacy?['favoriteVideosPrivacy'] == 'everyone');

    if (_canReadLikedPosts != allowLikes) {
      _canReadLikedPosts = allowLikes;
      _likedPresenceSub?.cancel();
      _likedPresenceSub = null;
      _hasLikedPosts = false;
      if (allowLikes) {
        _likedPresenceSub = FirebaseFirestore.instance.collection('users')
            .doc(viewedUid).collection('likedPosts').limit(1).snapshots()
            .listen((snapshot) {
          if (!mounted || !_canReadLikedPosts) return;
          _hasLikedPosts = snapshot.docs.isNotEmpty;
          _updateVisibleProfileTabs();
        }, onError: (Object error) {
          debugPrint('Tini liked posts visibility error: $error');
          if (!mounted) return;
          _hasLikedPosts = false;
          _updateVisibleProfileTabs();
        });
      }
    }

    if (_canReadFavorites != allowFavorites) {
      _canReadFavorites = allowFavorites;
      _favoritesPresenceSub?.cancel();
      _favoritesPresenceSub = null;
      _hasFavorites = false;
      _favoritePresencePosts = [];
      if (allowFavorites) {
        _favoritesPresenceSub = FirebaseFirestore.instance.collection('users')
            .doc(viewedUid).collection('favorites').limit(30).snapshots()
            .asyncMap(_containsVisibleFavoriteVideo)
            .listen((hasVideo) {
          if (!mounted || !_canReadFavorites) return;
          _hasFavorites = hasVideo;
          _updateVisibleProfileTabs();
        }, onError: (Object error) {
          debugPrint('Tini favorite posts visibility error: $error');
          if (!mounted) return;
          _hasFavorites = false;
          _updateVisibleProfileTabs();
        });
      }
    }
    _updateVisibleProfileTabs();
  }

  // [Tini - Favorite Tab]: نفس مصدر الشبكة: نقرأ معرفات المفضلة ثم الفيديوهات الموجودة.
  // لا نظهر أيقونة المفضلة إذا كانت الشبكة ستبقى فارغة.
  Future<bool> _containsVisibleFavoriteVideo(QuerySnapshot<Map<String, dynamic>> snapshot) async {
    if (!mounted || snapshot.docs.isEmpty) {
      _favoritePresencePosts = [];
      return false;
    }
    final viewerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final posts = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final favorite in snapshot.docs) {
      try {
        final rawId = favorite.data()['postId'];
        final postId = rawId is String && rawId.isNotEmpty ? rawId : favorite.id;
        final postDoc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
        if (!mounted || viewerUid != (FirebaseAuth.instance.currentUser?.uid ?? '')) return false;
        if (!postDoc.exists) continue;
        posts.add(postDoc);
        final data = postDoc.data();
        if (data != null) _audience.trackPost(data, postId: postId);
      } catch (error) {
        debugPrint('Tini favorite video verification error: $error');
      }
    }
    _favoritePresencePosts = posts;
    return posts.any((post) => _favoritePostIsVisible(post.data(), post.id));
  }

  bool _favoritePostIsVisible(Map<String, dynamic>? data, String postId) {
    if (data == null || data['isDeleted'] == true) return false;
    if (!_audience.canViewPost(data, postId: postId)) return false;
    final viewerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    if (!isOwnProfile) {
      final privacy = data['privacy'] ?? 'public';
      if (privacy == 'private') return false;
      if (privacy == 'friends') {
        final owner = (data['uid'] ?? '').toString();
        if (owner != viewerUid && !auth.isFriendSync(owner)) return false;
      }
    }
    if (data['isMysteryBox'] == true) {
      final owner = data['uid'];
      final boxOwner = data['boxOwnedByUid'];
      if (viewerUid != owner && viewerUid != boxOwner) return false;
    }
    return true;
  }

  bool _profileTabUpdatePending = false;

  void _updateVisibleProfileTabs() {
    if (!mounted) return;
    final nextTabs = <String>[
      'posts',
      if (_canReadLikedPosts && _hasLikedPosts) 'likes',
      if (_canReadFavorites && _hasFavorites) 'favorites',
      'shares',
      if (isOwnProfile && _hasPrivatePosts) 'private',
    ];
    if (nextTabs.join('|') == _visibleProfileTabs.join('|')) return;

    // [Tini - Stable Profile Tabs]: لا تبدّل المتحكم أثناء الضغط أو السحب بين التبويبات.
    if (_tabController.indexIsChanging || _tabController.offset.abs() > 0.0001) {
      if (!_profileTabUpdatePending) {
        _profileTabUpdatePending = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _profileTabUpdatePending = false;
          if (mounted) _updateVisibleProfileTabs();
        });
      }
      return;
    }

    // حافظ على نوع التبويب المحدد، لا على رقمه الذي قد يتغير بعد إخفاء تبويب.
    final activeTab = _visibleProfileTabs[_tabController.index];
    final nextIndex = nextTabs.indexOf(activeTab);
    final previousController = _tabController;
    setState(() {
      _visibleProfileTabs = nextTabs;
      _tabController = TabController(
        length: nextTabs.length,
        vsync: this,
        initialIndex: nextIndex < 0 ? 0 : nextIndex,
      );
    });
    // يتخلص Flutter من اشتراكات TabBar/TabBarView القديمة قبل إغلاق المتحكم.
    WidgetsBinding.instance.addPostFrameCallback((_) => previousController.dispose());
  }

  @override
  void dispose() {
    _audience.removeListener(_onAudienceChanged);
    _profilePrivacySub?.cancel();
    _followAccessSub?.cancel();
    _likedPresenceSub?.cancel();
    _favoritesPresenceSub?.cancel();
    _privatePresenceSub?.cancel();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _showFullImage(BuildContext context, String imageUrl, String heroTag) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
                            child: imageUrl.isNotEmpty
             ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      cacheKey: imageUrl,
                      useOldImageOnUrlChange: false,
                      placeholder: (context, url) => const CircularProgressIndicator(color: Colors.teal),
                      errorWidget: (context, url, error) => const Icon(Iconsax.user, size: 100, color: Colors.white24),
                      fit: BoxFit.contain,
                    )
                  : const Image(image: AssetImage('assets/images/default_avatar.png'), fit: BoxFit.contain),
            ),
        ),
      ),
    );
  }

  void _showAvatarOptions(BuildContext context, custom.AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 15),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Icon(Iconsax.eye, color: titiTeal),
                title: const Text("عرض الصورة", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  final String heroTag = 'profile_avatar_hero_$viewedUid';
                  _showFullImage(context, auth.profileImg, heroTag);
                },
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Icon(Iconsax.camera, color: titiTeal),
                title: const Text("تغيير صورة البروفايل", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await auth.pickAndUploadImage();
                },
              ),
            ),
            if (auth.profileImg.isNotEmpty)
              Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: const Icon(Iconsax.trash, color: Colors.redAccent),
                  title: const Text("حذف صورة البروفايل", style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    await auth.deleteProfileImage();
                  },
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showFullBioDialog(BuildContext context, String fullBio) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Iconsax.document_text, color: titiTeal, size: 22),
              const SizedBox(width: 10),
              const Text("البايو الكامل", style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: _buildLinkableBio(fullBio, isPreview: false),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("إغلاق", style: TextStyle(color: titiTeal, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }


  void _showEditProfileSheet(BuildContext context, custom.AuthProvider auth) {
    final nameController = TextEditingController(text: auth.fullName);
    final usernameController = TextEditingController(text: auth.username);
    final bioController = TextEditingController(text: auth.bio);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, top: 20, left: 20, right: 20),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Text("تعديل الملف الشخصي", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 25),
            _buildEditField("الاسم الكامل", nameController, Iconsax.user),
            _buildEditField("اسم المستخدم", usernameController, Iconsax.personalcard),
            _buildEditField("البايو (Bio)", bioController, Iconsax.document_text, maxLines: 3),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: titiTeal,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: () async {
                bool success = await auth.updateUserProfile(
                  nameController.text,
                  usernameController.text,
                  bioController.text,
                );

                if (success) {
                  if (context.mounted) Navigator.pop(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("تم تحديث بيانات Tini بنجاح", textAlign: TextAlign.center),
                        backgroundColor: Colors.teal,
                      ),
                    );
                  }
                }
              },
              child: auth.isLoading
             ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("حفظ التغييرات", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, IconData icon, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          prefixIcon: Icon(icon, color: titiTeal, size: 20),
          filled: true,
          fillColor: bgColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: titiTeal)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<custom.AuthProvider>(
      builder: (context, auth, child) {
        final double maxExtended = isOwnProfile
           ? MediaQuery.of(context).size.height * 0.46
            : MediaQuery.of(context).size.height * 0.58;
        const double toolbarHeight = 48.0;
        final double statusBarHeight = MediaQuery.of(context).padding.top;
        final double scrollRange = maxExtended - (statusBarHeight + toolbarHeight);

        final String displayFullName = isOwnProfile? auth.fullName : (viewedUserData?['fullName']?? '');

        // [AUDIENCE CONTROL] - تحديث حالة المشاهد والمشاهد له فورياً - FIXED V2
        isOwnProfile = viewedUid.isNotEmpty && viewedUid == (FirebaseAuth.instance.currentUser?.uid ?? '');
        _viewerIsAdult = _audience.isViewerAdult;
        _viewedIsAdultContent = !_audience.canViewProfile(viewedUid);

        // [Tini: Phase 3 - البروفايل - الحظر الكامل - مركزي - Two Way]
        final blockedSet = auth.blockedUsersSet.isNotEmpty? auth.blockedUsersSet : auth.blockedUsers.toSet();
        final bool iBlockedHim = blockedSet.contains(viewedUid) || auth.isBlocked(viewedUid);
        final List targetBlockedList = viewedUserData?['blockedUsers']?? viewedUserData?['blocked']?? [];
        final bool heBlockedMe = targetBlockedList.contains(auth.uid) || (viewedUserData?['blockedBy']!= null && (viewedUserData?['blockedBy'] as List).contains(auth.uid));
        if (!isOwnProfile && (iBlockedHim || heBlockedMe)) {
          return Scaffold(
            backgroundColor: bgColor,
            appBar: AppBar(
              backgroundColor: bgColor,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
                  }
                },
              ),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                    child: const Icon(Icons.block, color: Colors.white24, size: 48),
                  ),
                  const SizedBox(height: 20),
                  Text(iBlockedHim? "لقد قمت بحظر هذا الحساب" : "هذا الحساب غير متاح", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(iBlockedHim? "لن تتمكن من رؤية فيديوهاته ولن يتمكن من العثور عليك في البحث ولن تصلك رسائله" : "لا يمكنك عرض هذا الملف الشخصي", style: TextStyle(color: Colors.white.withValues(alpha:0.5), fontSize: 13), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 24),
                  if (iBlockedHim)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () async {
                        // لحظي مركزي - Set
                        try {
                          auth.blockedUsersSet.remove(viewedUid);
                          auth.removeFromBlockedLocally(viewedUid);
                        } catch (_) {}
                        if (mounted) setState(() {});

                        // حذف من عندي
                        await FirebaseFirestore.instance.collection('users').doc(auth.uid).collection('blocked').doc(viewedUid).delete();
                        await FirebaseFirestore.instance.collection('users').doc(auth.uid).update({
                          'blockedUsers': FieldValue.arrayRemove([viewedUid]),
                          'blocked': FieldValue.arrayRemove([viewedUid]),
                        });

                        // [مهم - حل مشكلة الفيد] حذف الـ blockedBy من عنده مشان فيديوهاتك ما عاد تطلع عنده بالـ For You
                        try {
                          await FirebaseFirestore.instance.collection('users').doc(viewedUid).collection('blockedBy').doc(auth.uid).delete();
                        } catch (_) {}

                        await auth.fetchUserData();
                        if (context.mounted) setState(() {});
                      },
                      child: const Text("إلغاء الحظر", style: TextStyle(color: Colors.white)),
                    )
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("رجوع", style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
            ),
          );
        }

        // [AUDIENCE CONTROL] - اذا البروفايل 18+ والمشاهد تحت 18 -> احجب البروفايل كامل
        if (!isOwnProfile && _viewedIsAdultContent && !_viewerIsAdult) {
          return Scaffold(
            backgroundColor: bgColor,
            appBar: AppBar(
              backgroundColor: bgColor,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
                  }
                },
              ),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                    child: const Icon(Icons.no_adult_content, color: Colors.white, size: 48),
                  ),
                  const SizedBox(height: 20),
                  const Text("هذا الحساب للبالغين فقط 18+", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text("هذا الحساب محجوب للمستخدمين تحت 18 سنة ولا يمكن عرض اسمه أو محتواه", style: TextStyle(color: Colors.white.withValues(alpha:0.5), fontSize: 13), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("رجوع", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: bgColor,
          body: AnimatedBuilder(
            animation: _scrollController,
            builder: (context, _) {
              double offset = _scrollController.hasClients? _scrollController.offset.clamp(0.0, scrollRange) : 0.0;
              double scrollPercent = offset / scrollRange;
              double profileOpacity = (1.0 - (scrollPercent / 0.8)).clamp(0.0, 1.0);
              double titleOpacity = scrollPercent > 0.6? ((scrollPercent - 0.6) / 0.4).clamp(0.0, 1.0) : 0.0;

              return NestedScrollView(
                controller: _scrollController,
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverAppBar(
                    expandedHeight: maxExtended,
                    pinned: true,
                    backgroundColor: bgColor,
                    elevation: 0,
                    centerTitle: true,
                    leading: IconButton(
    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
    onPressed: () async {
      try {
        await TitiProfileEngine().lock();
        await TitiSingleEngine().lock();
      } catch (_) {}
      if (widget.onBackToHome!= null) {
        widget.onBackToHome!();
        return;
      }
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    },
  ),
actionsPadding: EdgeInsets.zero,
actions: [
  if (isOwnProfile)
    Transform.translate(
      offset: const Offset(10, 0), // حرك باب الزيارات لليمين - زود الرقم بيقرب اكتر
      child: Builder(
        builder: (context) {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) return const SizedBox.shrink();
          // داخل الواجهة الرئيسية يبقى البروفايل محفوظاً حتى وهو مخفي.
          // بدء الحركة عند فتح تبويب «ملفي»، وليس أثناء إنشاء الشاشة المخفية.
          final isProfileVisible = Visibility.of(context);
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _visitsStreamFor(currentUser.uid),
            builder: (context, snap) {
              final visits = snap.data?.docs;
              final visitorIds = (visits ?? [])
                  .map((doc) {
                    final id = doc.data()['visitorId'];
                    return id is String && id.trim().isNotEmpty
                        ? id.trim()
                        : doc.id;
                  })
                  .where((id) => id.isNotEmpty)
                  .take(3)
                  .toList();
              // عدد الزيارات الجديدة فقط؛ تبقى هوية آخر زائر حتى بعد القراءة.
              final unreadCount = (visits ?? [])
                  .where((doc) => doc.data()['isSeen'] == false)
                  .length;
              return VisitsDoorButton(
                badgeCount: unreadCount,
                visitorIds: visitorIds,
                isLoaded: snap.hasData,
                isActive: isProfileVisible,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VisitsScreen()),
                  );
                },
              );
            },
          );
        },
      ),
    ),
if (isOwnProfile)
    Transform.translate(
      offset: const Offset(10, 0), // حرك زر المشاركة لليمين - هون بتتحكم فيه لحالو
      child: IconButton(
        icon: const Icon(Iconsax.share, color: Colors.white, size: 25),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        onPressed: () {
          final parentCtx = context;
          showModalBottomSheet(
            context: parentCtx,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (sheetCtx) => ShareProfileSheet(
              profileUserId: viewedUid,
              showBlockButton: false,
              rootContext: parentCtx,
            ),
          );
        },
      ),
    ),
if (!isOwnProfile)
    Transform.translate(
      offset: const Offset(0, 0),
      child: IconButton(
        icon: const Icon(Iconsax.share, color: Colors.white, size: 25),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        onPressed: () {
          final parentCtx = context;
          showModalBottomSheet(
            context: parentCtx,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (sheetCtx) => ShareProfileSheet(
              profileUserId: viewedUid,
              showBlockButton: true,
              rootContext: parentCtx,
            ),
          );
        },
      ),
    ),
  if (isOwnProfile)
    IconButton(
      icon: const Icon(Iconsax.menu_1, color: Colors.white, size: 25),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      onPressed: () {
        TitiProfileEngine().stop();
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const ProfileSubMenu(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
    ),
],
                    title: Opacity(
                      opacity: titleOpacity,
                      child: Text(displayFullName, style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      collapseMode: CollapseMode.pin,
                      background: Opacity(
                        opacity: profileOpacity,
                        child: _buildVisualHeader(auth),
                      ),
                    ),
                    bottom: _buildTitiTabBarVisual(),
                  ),
                ],
                                body: TabBarView(
                  controller: _tabController,
                  children: _visibleProfileTabs.map((type) {
                    final content = type == 'likes'
                        ? _buildLikedVideosTab(viewedUid, viewedUserData: viewedUserData, isOwn: isOwnProfile, followingStatus: followingStatus)
                        : _buildTitiGridWrapper(viewedUid, type, viewedUserData: viewedUserData, isOwn: isOwnProfile, followingStatus: followingStatus);
                    // المفتاح يحمي حالة شبكة الفيديوهات من الانتقال إلى تبويب مختلف عند الإخفاء.
                    return KeyedSubtree(key: ValueKey('tini_profile_${viewedUid}_$type'), child: content);
                  }).toList(),
                ),
              );
            },
          ),
        );
      },
    );
  }

    Widget _buildLinkableBio(String bio, {bool isPreview = false}) {
    final RegExp linkRegExp = RegExp(r'(https?:\/\/[^\s]+|www\.[^\s]+)');
    final matches = linkRegExp.allMatches(bio);
    
    if (matches.isEmpty) {
      return GestureDetector(
        onTap: () => isPreview ? _showFullBioDialog(context, bio) : null,
        child: Text(
          bio,
          textAlign: TextAlign.center,
          maxLines: isPreview ? 1 : null,
          overflow: isPreview ? TextOverflow.ellipsis : null,
          style: TextStyle(
            color: Colors.white.withValues(alpha:0.85),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      );
    }

    List<InlineSpan> spans = [];
    int lastIndex = 0;
    for (var match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: bio.substring(lastIndex, match.start),
          style: TextStyle(color: Colors.white.withValues(alpha:0.85), fontSize: 13, height: 1.4),
        ));
      }
      final String urlText = bio.substring(match.start, match.end);
      spans.add(WidgetSpan(
        child: GestureDetector(
          onTap: () => OpenLinkWithSettings.open(context, urlText),
          child: Text(urlText, style: const TextStyle(color: Colors.teal, fontSize: 13, height: 1.4, decoration: TextDecoration.underline)),
        ),
      ));
      lastIndex = match.end;
    }
    if (lastIndex < bio.length) {
      spans.add(TextSpan(
        text: bio.substring(lastIndex),
        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.4),
      ));
    }

    return GestureDetector(
      onTap: () => isPreview ? _showFullBioDialog(context, bio) : null,
      child: RichText(
        textAlign: TextAlign.center,
        maxLines: isPreview ? 1 : null,
        overflow: isPreview ? TextOverflow.ellipsis : TextOverflow.visible,
        text: TextSpan(children: spans),
      ),
    );
  }

  Widget _buildVisualHeader(custom.AuthProvider auth) {
    final String fullName = isOwnProfile? auth.fullName : (viewedUserData?['fullName']?? '');
    final String username = isOwnProfile? auth.username : (viewedUserData?['username']?? '');
    final String profileImg = isOwnProfile? auth.profileImg : (viewedUserData?['profileImg']?? '');
    final String bio = isOwnProfile? auth.bio : (viewedUserData?['bio']?? '');
    final int followers = isOwnProfile? auth.followers : (viewedUserData?['followers']?? 0);
    final int following = isOwnProfile? auth.following : (viewedUserData?['following']?? 0);
    final int likes = isOwnProfile? auth.likes : (viewedUserData?['likes']?? 0);

    return SafeArea(
      bottom: false, // مهم مشان ما يحسب مسافة زيادة من تحت
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          _buildTitiAvatarMasterVisual(size: isOwnProfile? 110 : 100, imageUrl: profileImg, auth: auth, isOwn: isOwnProfile),
          const SizedBox(height: 12),
          _buildIdentityVisual(auth, fullName, username, bio, isOwnProfile),
          const SizedBox(height: 10),
          _buildStatsVisual(followers, following, likes),
          const SizedBox(height: 8),
          if (!isOwnProfile)
            Padding(
              padding: const EdgeInsets.only(bottom: 14), // ببعدو عن التبويبات
              child: Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: titiTeal,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
                    final currentUid = FirebaseAuth.instance.currentUser?.uid;
                    if (currentUid == null) return;
                    bool isActuallyFriend;
                    try {
                      isActuallyFriend = await chatProvider.checkIfFriend(currentUid, viewedUid);
                    } catch (e) {
                      if (context.mounted) showTiniChatAccessNotice(context, ChatFailureReason.technicalError);
                      return;
                    }
                    if (!context.mounted || FirebaseAuth.instance.currentUser?.uid != currentUid) return;
                    final result = await chatProvider.startChatWithReason(
                      viewedUid: viewedUid,
                      displayFullName: fullName,
                      displayProfileImg: profileImg,
                      isFriend: isActuallyFriend,
                    );
                    if (!context.mounted || FirebaseAuth.instance.currentUser?.uid != currentUid) return;
                    if (!result.isSuccess) {
                      showTiniChatAccessNotice(context, result.failureReason);
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          viewedUid: viewedUid,
                          displayFullName: fullName,
                          displayProfileImg: profileImg,
                          isFriend: isActuallyFriend,
                        ),
                      ),
                    );
                  },
                  child: const Text("مراسلة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _openFollowList(int initialTab) {
    final String name = isOwnProfile
   ? Provider.of<custom.AuthProvider>(context, listen: false).fullName
        : (viewedUserData?['fullName']?? '');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowListScreen(
          userId: viewedUid,
          userName: name,
          initialTab: initialTab,
        ),
      ),
    );
  }

  Widget _buildTitiAvatarMasterVisual({required double size, required String imageUrl, required custom.AuthProvider auth, bool isOwn = true}) {
    final String displayName = isOwn? auth.fullName : (viewedUserData?['fullName']?? '');
    final String initial = displayName.isNotEmpty? displayName.trim()[0].toUpperCase() : '?';
    final String heroTag = 'profile_avatar_hero_$viewedUid';
    final String currentUid = FirebaseAuth.instance.currentUser?.uid?? '';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('stories').doc(viewedUid).collection('items').where('expiresAt', isGreaterThan: Timestamp.now()).snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs?? [];
        final bool hasStories = docs.isNotEmpty;
        final bool hasUnviewed = docs.any((d) =>!(List.from(d['views']?? [])).contains(currentUid));

        final bool hasImage = imageUrl.isNotEmpty;

        Widget avatarWidget;

        if (hasStories) {
          avatarWidget = StoryRing(
            imageUrl: imageUrl,
            size: size,
            hasStories: true,
            hasUnviewed: hasUnviewed,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => Story(userId: viewedUid)));
            },
          );
                } else if (hasImage) {
          avatarWidget = GestureDetector(
            onTap: () => _showFullImage(context, imageUrl, heroTag),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              cacheKey: imageUrl,
              useOldImageOnUrlChange: false,
              maxWidthDiskCache: 400,
              imageBuilder: (context, imageProvider) => CircleAvatar(
                radius: size / 2,
                backgroundImage: imageProvider,
              ),
              placeholder: (context, url) => CircleAvatar(
                radius: size / 2,
                backgroundColor: titiTeal.withAlpha(51),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: titiTeal, strokeWidth: 2)),
              ),
              errorWidget: (context, url, error) => CircleAvatar(
                radius: size / 2,
                backgroundColor: titiTeal.withAlpha(51),
                child: Text(initial, style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.bold)),
              ),
            ),
          );
        } else {
          avatarWidget = CircleAvatar(
            radius: size / 2,
            backgroundColor: titiTeal.withAlpha(51),
            child: Text(initial, style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.bold)),
          );
        }

        return Stack(
  children: [
    avatarWidget,
    if (isOwn)
      Positioned(
        bottom: 0,
        left: 0,
        child: GestureDetector(
          onTap: () => _showAvatarOptions(context, auth),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF00A38C),
              shape: BoxShape.circle,
              border: Border.all(color: bgColor, width: 2),
            ),
            child: auth.isLoading
           ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Iconsax.camera, color: Colors.white, size: 16),
          ),
        ),
      ),
    if (!isOwn)
      Positioned(
        bottom: 0,
        right: 0,
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
         .collection('users')
         .doc(FirebaseAuth.instance.currentUser?.uid?? '')
         .collection('following')
         .doc(viewedUid)
         .snapshots(),
          builder: (context, snapshot) {
            final bool isFollowing = snapshot.hasData && snapshot.data!.exists;
            return GestureDetector(
              onTap: () {
                Provider.of<custom.AuthProvider>(context, listen: false).toggleFollow(viewedUid);
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isFollowing? Colors.white : titiTeal,
                  shape: BoxShape.circle,
                  border: Border.all(color: bgColor, width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha:0.3), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
                child: Icon(
                  isFollowing? Icons.check : Icons.add,
                  color: isFollowing? titiTeal : Colors.white,
                  size: 18,
                ),
              ),
            );
          },
        ),
      ),
  ],
);
      },
    );
  }

  Widget _buildIdentityVisual(custom.AuthProvider auth, String name, String username, String bio, bool isOwn) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isOwn)
              GestureDetector(
                onTap: () => _showEditProfileSheet(context, auth),
                child: Icon(Iconsax.edit, color: titiTeal, size: 20),
              ),
            if (isOwn) const SizedBox(width: 15),
            Flexible(child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            )),
            if (viewedUid.isNotEmpty) EarnedThroneBadge(uid: viewedUid),
            const SizedBox(width: 15),
                        Material(
              color: Colors.transparent,
              child: InkWell(
  onTap: () {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const WalletScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  },
  child: const Icon(Iconsax.wallet_3, color: Colors.amber, size: 20),
),
),
          ],
        ),
                const SizedBox(height: 4),
        Text(
          "@$username",
          style: TextStyle(color: titiTeal, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        // [حالة النشاط] عرض نشط الآن / آخر ظهور
                if (!isOwn)
  StreamBuilder<DocumentSnapshot>(
    stream: FirebaseFirestore.instance.collection('users').doc(viewedUid).snapshots(),
    builder: (context, targetSnap) {
      if (!targetSnap.hasData ||!targetSnap.data!.exists) return const SizedBox.shrink();
      final targetData = targetSnap.data!.data() as Map<String, dynamic>;
      final bool targetShow = targetData['showActivityStatus']?? true;
      final bool isOnline = targetData['isOnline']?? false;
      final Timestamp? lastSeen = targetData['lastSeen'] as Timestamp?;

      // شرط جديد: لازم يكون صديق
      if (followingStatus!= 'friends') {
        return const SizedBox.shrink();
      }

      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
        builder: (context, mySnap) {
          final myData = mySnap.data?.data() as Map<String, dynamic>?;
          final bool myShow = myData?['showActivityStatus']?? true;

          if (!ActivityStatusService.canViewStatus(myShowActivity: myShow, targetShowActivity: targetShow)) {
            return const SizedBox.shrink();
          }

          return Text(
            ActivityStatusService.formatLastSeenFromTimestamp(lastSeen, isOnline),
            style: TextStyle(
              color: isOnline? Colors.greenAccent : Colors.white54,
              fontSize: 12,
            ),
          );
        },
      );
    },
  ),
        if (bio.isNotEmpty)...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 45),
            child: _buildLinkableBio(bio, isPreview: true),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsVisual(int followers, int following, int likes) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(child: _buildStatItem("إعجاب", likes.toString(), onTap: null)),
          _buildStatDivider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(viewedUid).collection('following').snapshots(),
              builder: (context, snap) {
                final count = snap.hasData ? snap.data!.docs.length : following;
                return _buildStatItem("أتابع", count.toString(), onTap: () => _openFollowList(0));
              },
            ),
          ),
          _buildStatDivider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(viewedUid).collection('followers').snapshots(),
              builder: (context, snap) {
                final count = snap.hasData ? snap.data!.docs.length : followers;
                return _buildStatItem("متابعين", count.toString(), onTap: () => _openFollowList(1));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {VoidCallback? onTap}) {
    Widget content = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 5),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
    Widget padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Center(child: content),
    );
    if (onTap == null) return padded;
    return Material(
  color: Colors.transparent,
  borderRadius: BorderRadius.circular(8),
  child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: padded),
);
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 18, color: Colors.white.withValues(alpha: 0.1), margin: const EdgeInsets.symmetric(horizontal: 2));
  }

  PreferredSizeWidget _buildTitiTabBarVisual() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(50),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        labelPadding: EdgeInsets.zero,
        indicatorColor: titiTeal,
        indicatorSize: TabBarIndicatorSize.label,
        tabs: _visibleProfileTabs.map((type) {
          switch (type) {
            case 'likes':
              return const Tab(icon: Icon(Iconsax.heart, size: 22));
            case 'favorites':
              return const Tab(icon: Icon(Iconsax.archive_1, size: 22));
            case 'shares':
              return const Tab(icon: Icon(Iconsax.repeat, size: 22));
            case 'private':
              return const Tab(icon: Icon(Iconsax.lock, size: 22));
            default:
              return const Tab(icon: Icon(Iconsax.grid_1, size: 22));
          }
        }).toList(),
      ),
    );
  }
}

// [Tini - Profile Vertical Scroll]: even an empty grid remains scrollable,
// so a swipe anywhere under the tabs can expand/collapse the profile header.
Widget _tiniScrollableProfileTabState(Widget child) {
  return CustomScrollView(
    primary: true,
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
  );
}

// [Tini - Liked Videos Privacy]: منع فتح قائمة إعجابات الآخرين قبل التحقق من الخيار المباشر.
// تحديث الإعداد يغلق القائمة فوراً، دون التأثير على شبكة البروفايل أو أي تبويب آخر.
Widget _buildLikedVideosTab(String uid, {Map<String, dynamic>? viewedUserData, bool isOwn = true, String followingStatus = 'none'}) {
  if (isOwn) {
    return _buildTitiGridWrapper(uid, 'likes', viewedUserData: viewedUserData, isOwn: true, followingStatus: followingStatus);
  }
  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        if (snapshot.hasError) {
          return _tiniScrollableProfileTabState(const Center(child: Text('تعذّر تحميل خصوصية الإعجابات', style: TextStyle(color: Colors.white70))));
        }
        return _tiniScrollableProfileTabState(const Center(child: CircularProgressIndicator(color: Colors.teal)));
      }
      final data = snapshot.data!.data() ?? <String, dynamic>{};
      if (data['likedVideosPrivacy'] != 'everyone') {
        return _tiniScrollableProfileTabState(const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Iconsax.lock_1, color: Colors.white24, size: 42),
              SizedBox(height: 16),
              Text('فيديوهات أعجبتك خاصة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('صاحب الحساب اختار عرضها له فقط', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ));
      }
      // الحساب الخاص يحتفظ بقفل المتابعة الموجود أصلاً قبل إنشاء استعلام الإعجابات.
      final isPrivate = data['isPrivate'] == true;
      final isFollower = followingStatus == 'following' || followingStatus == 'friends';
      if (isPrivate && !isFollower) {
        return _tiniScrollableProfileTabState(const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Iconsax.lock_1, color: Colors.white24, size: 42),
              SizedBox(height: 16),
              Text('هذا الحساب خاص', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('تابع هذا الحساب لمشاهدة محتواه', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ));
      }
      return _buildTitiGridWrapper(uid, 'likes', viewedUserData: data, isOwn: false, followingStatus: followingStatus);
    },
  );
}

Widget _buildTitiGridWrapper(String uid, String type, {Map<String, dynamic>? viewedUserData, bool isOwn = true, String followingStatus = 'none'}) {
  return _TitiProfileGridInternal(
    uid: uid,
    type: type,
    viewedUserData: viewedUserData,
    isOwnProfile: isOwn,
    followingStatus: followingStatus,
  );
}

class _TitiProfileGridInternal extends StatefulWidget {
  final String uid;
  final String type;
  final Map<String, dynamic>? viewedUserData;
  final bool isOwnProfile;
  final String followingStatus;
  const _TitiProfileGridInternal({
    required this.uid,
    required this.type,
    this.viewedUserData,
    this.isOwnProfile = true,
    this.followingStatus = 'none',
  });

  @override
  State<_TitiProfileGridInternal> createState() => _TitiProfileGridInternalState();
}

// إضافة AutomaticKeepAliveClientMixin هو الحل الجذري لمنع الرمشة وإعادة تحميل التبويب عند التنقل
class _TitiProfileGridInternalState extends State<_TitiProfileGridInternal> with AutomaticKeepAliveClientMixin {
  List<DocumentSnapshot> _allPosts = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isInitialLoading = true;
  bool _hasLoadError = false;
  Timer? _gridLoadTimeout;
  int _gridListenVersion = 0;
  bool _gridPaginationCheckQueued = false;
  StreamSubscription? _firstBatchSub;
  int _currentLimit = 30;
  final AudienceAccess _audience = AudienceAccess.instance;

  void _onAudienceChanged() {
    if (mounted) setState(() {});
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _audience.addListener(_onAudienceChanged);
    _listenWithLimit(_currentLimit);
  }

  // [Tini - Profile Vertical Scroll]: Inner grids use the NestedScrollView
  // primary controller; observe scroll notifications only for pagination.
  bool _onGridScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification.metrics.extentAfter > 300 ||
        notification is! ScrollUpdateNotification && notification is! ScrollEndNotification ||
        _isInitialLoading || _isLoadingMore || !_hasMore || _gridPaginationCheckQueued) {
      return false;
    }
    _gridPaginationCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gridPaginationCheckQueued = false;
      if (mounted && !_isInitialLoading && !_isLoadingMore && _hasMore) _fetchMore();
    });
    return false;
  }

  // [Titi New Logic] - يقرا الـ IDs من subcollection وبعدين يجيب البوستات
  Stream<List<DocumentSnapshot>> getPostsFromSubcollectionStream(String subName) {
    return FirebaseFirestore.instance
       .collection('users')
       .doc(widget.uid)
       .collection(subName)
       .limit(30)
       .snapshots()
       .asyncMap((subSnap) async {
          if (subSnap.docs.isEmpty) return <DocumentSnapshot>[];
          List<DocumentSnapshot> posts = [];
          Object? firstReadError;
          StackTrace? firstReadStack;
          for (var doc in subSnap.docs) {
            try {
              String postId = doc.id;
              if (doc.data().containsKey('postId')) {
                postId = doc.data()['postId']?? doc.id;
              }
              final postDoc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
              if (postDoc.exists) posts.add(postDoc);
            } catch (error, stackTrace) {
              firstReadError ??= error;
              firstReadStack ??= stackTrace;
              debugPrint('Tini profile ${widget.type} video read error: $error');
            }
          }
          if (posts.isEmpty && firstReadError != null) {
            Error.throwWithStackTrace(firstReadError, firstReadStack ?? StackTrace.current);
          }
          return posts;
        });
  }

  Query _getBaseQuery() {
    final col = FirebaseFirestore.instance.collection('posts');
    return col.where('uid', isEqualTo: widget.uid).orderBy('createdAt', descending: true);
  }

  // [Tini - Grid Loading]: جميع التبويبات تنهي التحميل عند النجاح أو الخطأ أو الانقطاع.
  void _applyGridResult(List<DocumentSnapshot> posts, bool hasMore, int version) {
    if (!mounted || version != _gridListenVersion) return;
    _gridLoadTimeout?.cancel();
    setState(() {
      _allPosts = posts;
      _hasMore = hasMore;
      _isInitialLoading = false;
      _isLoadingMore = false;
      _hasLoadError = false;
    });
  }

  void _handleGridLoadError(Object error, StackTrace stackTrace, int version) {
    debugPrint('Tini profile ${widget.type} loading error: $error');
    if (!mounted || version != _gridListenVersion) return;
    _gridLoadTimeout?.cancel();
    setState(() {
      _isInitialLoading = false;
      _isLoadingMore = false;
      _hasMore = false;
      _hasLoadError = true;
      // عند سحب الصلاحية لا نترك فيديوهات زائر محمّلة سابقاً على الشاشة.
      if (widget.type == 'likes' || widget.type == 'favorites' || widget.type == 'shares') {
        _allPosts = [];
      }
    });
  }

  void _handleGridStreamDone(int version) {
    if (!mounted || version != _gridListenVersion) return;
    _gridLoadTimeout?.cancel();
    if (!_isInitialLoading && !_isLoadingMore) return;
    setState(() {
      _isInitialLoading = false;
      _isLoadingMore = false;
      _hasMore = false;
    });
  }

  void _listenWithLimit(int limit) {
    final version = ++_gridListenVersion;
    _firstBatchSub?.cancel();
    _gridLoadTimeout?.cancel();
    // لا نسمح للانتظار الأول أو جلب الصفحة التالية بالبقاء بلا نهاية.
    if (_isInitialLoading || _isLoadingMore) {
      _gridLoadTimeout = Timer(const Duration(seconds: 20), () {
        if (!mounted || version != _gridListenVersion) return;
        if (_isInitialLoading || _isLoadingMore) {
          _handleGridLoadError(
            TimeoutException('Tini profile ${widget.type} load timed out'),
            StackTrace.current,
            version,
          );
        }
      });
    }

    if (widget.type == 'likes' || widget.type == 'favorites' || widget.type == 'shares') {
      final subName = widget.type == 'likes'
          ? 'likedPosts'
          : widget.type == 'favorites' ? 'favorites' : 'sharedPosts';
      _firstBatchSub = getPostsFromSubcollectionStream(subName).listen(
        (posts) => _applyGridResult(posts, false, version),
        onError: (Object error, StackTrace stackTrace) => _handleGridLoadError(error, stackTrace, version),
        onDone: () => _handleGridStreamDone(version),
      );
      return;
    }
    _firstBatchSub = _getBaseQuery().limit(limit).snapshots().listen(
      (snap) => _applyGridResult(snap.docs, snap.docs.length == limit, version),
      onError: (Object error, StackTrace stackTrace) => _handleGridLoadError(error, stackTrace, version),
      onDone: () => _handleGridStreamDone(version),
    );
  }

  Future<void> _fetchMore() async {
    if (_isLoadingMore ||!_hasMore) return;
    if (widget.type == 'likes' || widget.type == 'favorites' || widget.type == 'shares') return;
    setState(() => _isLoadingMore = true);
    _currentLimit += 30;
    _listenWithLimit(_currentLimit);
  }

  @override
  void dispose() {
    _audience.removeListener(_onAudienceChanged);
    _gridListenVersion++;
    _gridLoadTimeout?.cancel();
    _firstBatchSub?.cancel();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  super.build(context);
  // [AUDIENCE CONTROL - ADDITION] - حجب 18+ داخل الشبكة ايضاً - FIXED V2
  if (!_audience.canViewProfile(widget.uid)) {
      return _tiniScrollableProfileTabState(Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.05), shape: BoxShape.circle), child: const Icon(Icons.no_adult_content, color: Colors.white24, size: 42)),
            const SizedBox(height: 16),
            const Text("محتوى للبالغين فقط 18+", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text("هذا الحساب لا يظهر للمستخدمين تحت 18 سنة", style: TextStyle(color: Colors.white.withValues(alpha:0.4), fontSize: 13)),
          ],
        ),
      ));
  }
  // [Tini - Private Account Lock ALL TABS]
  final bool isPrivateAccount = widget.viewedUserData?['isPrivate'] == true;
  final bool isFollower = widget.followingStatus == 'following' || widget.followingStatus == 'friends';
  if (!widget.isOwnProfile && isPrivateAccount &&!isFollower) {
    return _tiniScrollableProfileTabState(Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.05), shape: BoxShape.circle),
            child: const Icon(Iconsax.lock_1, color: Colors.white24, size: 42),
          ),
          const SizedBox(height: 16),
          const Text("هذا الحساب خاص", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text("تابع هذا الحساب لمشاهدة محتواه", style: TextStyle(color: Colors.white.withValues(alpha:0.4), fontSize: 13)),
        ],
      ),
    ));
  }

  if (_isInitialLoading) {
    return _tiniScrollableProfileTabState(const Center(child: CircularProgressIndicator(color: AppColors.primary)));
  }
  if (_hasLoadError && _allPosts.isEmpty) {
    return _buildLoadError();
  }

  final allDocs = _allPosts;
  List<DocumentSnapshot> filteredPosts;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid?? '';

  if (widget.type == 'posts') {
    filteredPosts = allDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      // [Trash V31 - فلترة المحذوفات]
      if (data['isDeleted'] == true) return false;
      final privacy = data['privacy']?? 'public';
      final isMystery = data['isMysteryBox'] == true;
      final boxSold = data['boxSold'] == true;
      final boxOwnedByUid = data['boxOwnedByUid'];
      final ownerUid = data['uid'];
      if (isMystery) {
        final canView = currentUserId == ownerUid || currentUserId == boxOwnedByUid;
        if (!canView) return false;
        if (!boxSold && currentUserId!= ownerUid) return false;
      }
      if (privacy == 'public') return true;
      if (privacy == 'friends') return currentUserId == widget.uid;
      return false;
    }).toList();
  } else if (widget.type == 'private') {
    filteredPosts = allDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final privacy = data['privacy']?? 'public';
      if (currentUserId!= widget.uid) return false;
      return privacy == 'private';
    }).toList();
  } else {
    // إعجابات، مفضلة، مشاركات
    filteredPosts = allDocs.where((doc) {
      // [Tini - Liked Videos Privacy]: لا تعرض فيديو خاصاً أو محذوفاً ضمن إعجابات زائر آخر.
      if ((widget.type == 'likes' || widget.type == 'favorites') && !widget.isOwnProfile) {
        final likedData = doc.data() as Map<String, dynamic>;
        if (likedData['isDeleted'] == true) return false;
        final likedPrivacy = likedData['privacy'] ?? 'public';
        if (likedPrivacy == 'private') return false;
        if (likedPrivacy == 'friends') {
          final owner = (likedData['uid'] ?? '').toString();
          final auth = Provider.of<custom.AuthProvider>(context, listen: false);
          if (owner != currentUserId && !auth.isFriendSync(owner)) return false;
        }
      }
      final data = doc.data() as Map<String, dynamic>;
      final isMystery = data['isMysteryBox'] == true;
      if (!isMystery) return true;
      final boxOwnedByUid = data['boxOwnedByUid'];
      final ownerUid = data['uid'];
      return currentUserId == ownerUid || currentUserId == boxOwnedByUid;
    }).toList();
  }

  final audiencePending = filteredPosts.any((doc) {
    final data = doc.data() as Map<String, dynamic>?;
    return data != null && _audience.isPostPending(data, postId: doc.id);
  });
  filteredPosts = filteredPosts.where((doc) {
    final data = doc.data() as Map<String, dynamic>?;
    return data != null && _audience.canViewPost(data, postId: doc.id);
  }).toList();

  if (filteredPosts.isEmpty && _hasMore) {
    // يمكن أن تكون أول دفعة خاصة أو محذوفة؛ ابحث عن فيديو قابل للعرض في الدفعة التالية.
    if (!_isLoadingMore && !audiencePending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isLoadingMore && _hasMore && !_isInitialLoading) _fetchMore();
      });
    }
    return _tiniScrollableProfileTabState(const Center(child: CircularProgressIndicator(color: AppColors.primary)));
  }
  if (filteredPosts.isEmpty) {
    return _hasLoadError ? _buildLoadError() : _buildEmptyState();
  }

  return NotificationListener<ScrollNotification>(
    onNotification: _onGridScrollNotification,
    child: GridView.builder(
      primary: true,
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 1.5,
        mainAxisSpacing: 1.5,
        childAspectRatio: 0.72,
      ),
      itemCount: filteredPosts.length + (_isLoadingMore? 1 : 0),
      itemBuilder: (context, index) {
        if (index == filteredPosts.length) {
          return const Center(child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 2));
        }
        final postDoc = filteredPosts[index];
        final postData = postDoc.data() as Map<String, dynamic>;
        final String docId = postDoc.id;
        return TitiGridItem(
          key: ValueKey(docId),
          postData: postData,
          postId: docId,
          index: index,
          posts: filteredPosts,
          postDoc: postDoc,
          enableOwnerReactionsOverlay: widget.isOwnProfile && widget.type == 'posts',
        );
      },
    ),
  );
}

  // نفس تصميم الحالة الفارغة، لكن الخطأ لا يُعرض على أنه لا توجد فيديوهات.
  Widget _buildLoadError() {
    return _tiniScrollableProfileTabState(const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: AppColors.iconInactive, size: 64),
          SizedBox(height: 10),
          Text('تعذّر تحميل الفيديوهات', style: TextStyle(color: AppColors.iconInactive)),
        ],
      ),
    ));
  }

  // دالة موحدة لعرض حالة التبويب الفارغ بناءً على النوع
  Widget _buildEmptyState() {
    IconData emptyIcon;
    String emptyText;

    if (widget.type == 'likes') {
      emptyIcon = Iconsax.heart;
      emptyText = "لم تعجب بأي فيديو بعد";
    } else if (widget.type == 'favorites') {
      emptyIcon = Iconsax.archive_add;
      emptyText = "قائمة المفضلة فارغة";
    } else if (widget.type == 'shares') {
      emptyIcon = Iconsax.send_2;
      emptyText = "لم تقم بمشاركة أي تألق بعد";
    } else if (widget.type == 'private') {
      emptyIcon = Iconsax.lock;
      emptyText = "لا توجد فيديوهات خاصة هنا";
    } else {
      emptyIcon = Iconsax.video_play;
      emptyText = "لم تنشر أي تألق بعد";
    }

    return _tiniScrollableProfileTabState(Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(emptyIcon, color: AppColors.textPrimary.withValues(alpha:0.1), size: 80),
          const SizedBox(height: 10),
          Text(emptyText, style: const TextStyle(color: AppColors.iconInactive)),
        ],
      ),
    ));
  }
}

class TitiGridItem extends StatefulWidget {
  final Map<String, dynamic> postData;
  final String postId;
  final int index;
  final List<DocumentSnapshot> posts;
  final DocumentSnapshot postDoc; // الإضافة الثانية: استقبال مستند الفيديو بدون المساس بالبنية والأقواس الأصلية
  // [Tini - Owner Reactions Overlay] - فقط تبويب فيديوهات صاحب الحساب.
  final bool enableOwnerReactionsOverlay;

  const TitiGridItem({
    super.key,
    required this.postData,
    required this.postId,
    required this.index,
    required this.posts,
    required this.postDoc, // الإضافة الثالثة: تثبيته داخل الـ Constructor
    this.enableOwnerReactionsOverlay = false,
  });

  @override
  State<TitiGridItem> createState() => _TitiGridItemState();
}

class _TitiGridItemState extends State<TitiGridItem> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // [اضافة الوان الندرة] - نفس دوال MysterySeaGrid
  List<Color> _getRarityColors(String? rarityStr) {
    switch (rarityStr) {
      case 'bronze':
        return [Colors.brown.shade400, Colors.brown.shade700];
      case 'silver':
        return [Colors.grey.shade400, Colors.grey.shade600];
      case 'gold':
        return [Colors.amber.shade400, Colors.amber.shade700];
      case 'diamond':
        return [Colors.cyan.shade300, Colors.blue.shade700];
      default:
        return [AppColors.surface, AppColors.background];
    }
  }

  IconData _getRarityIcon(String? rarityStr) {
    switch (rarityStr) {
      case 'bronze':
        return Icons.workspace_premium;
      case 'silver':
        return Icons.military_tech;
      case 'gold':
        return Icons.emoji_events;
      case 'diamond':
        return Icons.diamond;
      default:
        return Icons.inventory_2;
    }
  }

  String _getRarityName(String? rarityStr) {
    switch (rarityStr) {
      case 'bronze':
        return 'برونزي';
      case 'silver':
        return 'فضي';
      case 'gold':
        return 'ذهبي';
      case 'diamond':
        return 'ماسي';
      default:
        return 'نادر';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final auth = Provider.of<custom.AuthProvider>(context, listen: true);
    final String thumbnailUrl = widget.postData['thumbnailUrl']?? '';
    final String processingStatus = widget.postData['processingStatus']?? 'ready';
    final String privacyStatus = widget.postData['privacy']?? 'public';

    // [غباش حسب المتابعين - FIX إعادة التشغيل] - صاحب الفيديو + متابعينه واضح - الغريب مغبش - مستقل عن جمهور 18+
    final bool isBlurred = widget.postData['isBlurred'] == true;
    final String blurOwnerUid = widget.postData['uid'] ?? '';
    final String blurMyUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool blurIsOwner = blurMyUid.isNotEmpty && blurMyUid == blurOwnerUid;
    final bool blurIsFollower = auth.followingList.contains(blurOwnerUid) || auth.isFollowingSync(blurOwnerUid);
    final bool blurIt = isBlurred && !blurIsOwner && !blurIsFollower;


    // [اضافة قفل الصناديق النادرة] - فحص الصلاحية
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid?? '';
    final bool isMystery = widget.postData['isMysteryBox'] == true;
    final bool boxSold = widget.postData['boxSold'] == true;
    final String boxOwnedByUid = widget.postData['boxOwnedByUid']?? '';
    final String ownerUid = widget.postData['uid']?? '';
    final String? boxRarity = widget.postData['boxRarity']; // bronze, silver, gold, diamond

    bool canViewMystery = true;
    if (isMystery) {
      canViewMystery = currentUserId == ownerUid || currentUserId == boxOwnedByUid;
      if (!boxSold && currentUserId!= ownerUid) canViewMystery = false;
    }

    final rarityColors = _getRarityColors(boxRarity);
    final bool showRarityFrame = isMystery && canViewMystery;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () async {
          if (!AudienceAccess.instance.canViewPost(widget.postData, postId: widget.postId)) return;
          if (isMystery &&!canViewMystery) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('هذا الصندوق خاص بصاحبه والمشتري فقط', textAlign: TextAlign.center),
                backgroundColor: AppColors.error,
              ),
            );
            return;
          }

          try {
            // نطفي الهوم مشان ما يضل شغال بالخلفية، ومنخلي البروفايل هو اللي ياخد المهمة
            await TitiSingleEngine().lock();
            await TitiProfileEngine().unlock();
          } catch (_) {}

          await Future.delayed(const Duration(milliseconds: 50));
          if (!mounted || !AudienceAccess.instance.canViewPost(widget.postData, postId: widget.postId)) return;

          Navigator.push(
            context,
            PageRouteBuilder(
              opaque: true,
              barrierColor: const Color(0xFF0F1720),
              transitionDuration: const Duration(milliseconds: 300),
              reverseTransitionDuration: const Duration(milliseconds: 200),
              pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
                opacity: animation,
                child: PostViewScreen(
                  posts: widget.posts,
                  initialIndex: widget.index,
                  thumbnailUrl: (widget.postDoc.data() as Map<String,dynamic>)['thumbnailUrl'],
                  isFromProfileGrid: true, // هون بيشتغل محرك البروفايل 3 بلاير
                  showOwnerReactionsOverlay: widget.enableOwnerReactionsOverlay && auth.uid == ownerUid,
                ),
              ),
            ),
          ).then((_) async {
            // رجعنا للشبكة - البروفايل بضل مفتوح لاننا لسا بتبويب ملفي
            try {
              await TitiProfileEngine().unlock();
              await TitiSingleEngine().lock();
            } catch (_) {}
          });
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: showRarityFrame
        ? Border.all(color: rarityColors[0], width: 2.5)
              : null,
            boxShadow: showRarityFrame
        ? [
                  BoxShadow(
                    color: rarityColors[0].withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Builder(
                  builder: (context) {
                    if (!AudienceAccess.instance.canViewPost(widget.postData, postId: widget.postId)) {
                      return Container(
                        color: Colors.black,
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("🔞", style: TextStyle(fontSize: 28)),
                              SizedBox(height: 4),
                              Text("+18", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ),
                      );
                    }
                    if (blurIt) {
                      return ClipRect(
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: thumbnailUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: thumbnailUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(color: AppColors.background),
                                )
                              : const Center(child: Icon(Iconsax.video_play, color: AppColors.iconInactive, size: 35)),
                        ),
                      );
                    } else {
                      return thumbnailUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: thumbnailUrl,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              memCacheHeight: 400,
                              placeholder: (context, url) => Container(color: AppColors.background),
                              errorWidget: (context, url, error) => const Icon(Iconsax.video_play, color: AppColors.iconInactive),
                            )
                          : const Center(child: Icon(Iconsax.video_play, color: AppColors.iconInactive, size: 35));
                    }
                  },
                ),
                // [اضافة شارة الصندوق النادر] - تظهر للمالك والمشتري فقط
                if (isMystery && canViewMystery)
                  Positioned(
                    top: 5,
                    left: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: rarityColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: [
                          BoxShadow(
                            color: rarityColors[0].withValues(alpha: 0.7),
                            blurRadius: 6,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getRarityIcon(boxRarity),
                            color: AppColors.black, size: 11),
                          const SizedBox(width: 2),
                          Text(
                            _getRarityName(boxRarity),
                            style: const TextStyle(
                              color: AppColors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // [اضافة قفل الصناديق النادرة] - overlay القفل
                if (isMystery &&!canViewMystery)
                  Container(
                    color: AppColors.background.withValues(alpha: 0.8),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock, color: AppColors.primary, size: 40),
                          SizedBox(height: 8),
                          Text(
                            'صندوق خاص',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (privacyStatus == 'friends')
                  const Positioned(
                    top: 5,
                    right: 5,
                    child: Icon(Icons.people, color: AppColors.greyText, size: 16),
                  ),
                if (privacyStatus == 'private')
                  const Positioned(
                    top: 5,
                    right: 5,
                    child: Icon(Icons.lock, color: AppColors.greyText, size: 16),
                  ),
                if (processingStatus == 'processing')
                  Container(
                    color: Colors.black.withValues(alpha:0.6),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "HLS جاري التحويل",
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 7, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 35,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withValues(alpha:0.5), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  left: 6,
                  right: 6,
                  child: Builder(
                    builder: (context) {
                      final int views = widget.postData['views']?? 0;
                      final int likes = widget.postData['likesCount']?? 0;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Iconsax.play, color: AppColors.textPrimary, size: 12),
                              const SizedBox(width: 2),
                              Text(views.toString(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Iconsax.heart5, color: AppColors.textPrimary, size: 11),
                              const SizedBox(width: 2),
                              Text(likes.toString(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}