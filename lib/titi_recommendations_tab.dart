import 'package:flutter/material.dart';
import 'audience_access.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'post_view_screen.dart';
import 'home_screen.dart'; // [استدعاء]: للوصول إلى HomeScreenState بعد جعلها Public
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'titi_single_engine.dart'; // [Fix]: مشان نتحكم بالصوت لما التبويب يصير مو نشط
import 'post_provider.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom; // [Two-Way Block] - مشان نجيب blockedBySet

// [STRIPPED 70 bytes]
// [Tini]: ملف تبويب التوصيات النظيف والخالص (titi_recommendations_tab.dart)
// [تعديل For You]: صار يقرأ من forYouFeed حسب السكور بدون حذف مميزاتك
// [STRIPPED 70 bytes]

class TitiRecommendationsTab extends StatefulWidget {
  final bool isHomeActive;
  const TitiRecommendationsTab({super.key, this.isHomeActive = true});

  @override
  State<TitiRecommendationsTab> createState() => _TitiRecommendationsTabState();
}

class _TitiRecommendationsTabState extends State<TitiRecommendationsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Fix تذكر مكان الفيديو: خلي التبويب ما ينحذف من الذاكرة ابدا

  // ألوان الهوية الرسمية المعتمدة لتطبيق Tini
  final Color titiBG = const Color(0xFF000000); // الأساس الزيتي الداكن

  // [حل مشكلة 3]: منع طلبات متكررة عند التحميل التدريجي
  bool _isFetchingMore = false;
  final List<DocumentSnapshot> _forYouPosts = [];
  final List<String> _seenIds = [];
  bool _isFirstLoading = true;
  TabController? _tabController;
  bool get _isFeedActive => widget.isHomeActive &&
      (_tabController?.index ?? 3) == 3 && !(_tabController?.indexIsChanging ?? false);
  int _currentVideoIndex = 0; // [Fix]: نحفظ وين واقف بهاد التبويب
  String? _lastHandledUploadId;
  List<DocumentSnapshot> _visiblePosts = []; // [Fix]: نفس القائمة المفلترة الظاهرة للمشغّل

  // [TIKTOK FLIP - ADDITION]
  bool _wasHandlingFlip = false;

  // [AUDIENCE CONTROL - ADDITION]
  // [إصلاح V2] اذا age = 0 احسبه من birthDate او dob
  // أصبح تحقق الميلاد والبيانات القديمة موحداً في سياسة الجمهور.
  final _audience = AudienceAccess.instance;
  String? _loadedUid;

  void _onAudienceChanged() {
    if (!mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != _loadedUid) {
      _loadedUid = uid;
      _forYouPosts.clear();
      _seenIds.clear();
      _visiblePosts = [];
      _currentVideoIndex = 0;
      _isFetchingMore = false;
      _isFirstLoading = true;
      if (_isFeedActive) TitiSingleEngine().pause();
      if (uid != null) _fetchForYou();
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _audience.addListener(_onAudienceChanged);
    _loadedUid = FirebaseAuth.instance.currentUser?.uid;
    // [AUDIENCE CONTROL] - حالة المشاهد قبل الجلب
    // تُقرأ مركزياً وتُطبّق عند العرض.
    _fetchForYou();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = DefaultTabController.of(context);
    if (_tabController!= nextController) {
      _tabController?.removeListener(_onTopTabChanged);
      _tabController = nextController;
      _tabController?.addListener(_onTopTabChanged);
    }
  }

  void _onTopTabChanged() {
    if (!mounted) return;
    setState(() {});
    final isMyTabActive = _isFeedActive;
    if (isMyTabActive) {
      // رجعت على توصيات - شغل الفيديو اللي كنت واقف عليه بهاد التبويب
      final visiblePosts = _visiblePosts;
      if (visiblePosts.isNotEmpty && _currentVideoIndex < visiblePosts.length) {
        final data = visiblePosts[_currentVideoIndex].data() as Map<String, dynamic>?;
        if (data == null || !_audience.canViewPost(data, postId: visiblePosts[_currentVideoIndex].id)) {
          TitiSingleEngine().pause();
          return;
        }
        // استخدم نفس الدالة يلي بيستخدمها الـ VideoPlayer: hls اول بعدين videoUrl
        String url = (data['hlsPath'] as String?)?.trim()?? "";
        if (url.isEmpty) url = data['videoUrl'] as String? ?? '';
        if (url.isNotEmpty) {
          TitiSingleEngine().playUrl(url);
        }
      } else {
        // اذا لسا ما في بوستات، خلي المحرك يرجع يصحى لحالو
        // [Fix]: لا تستأنف فيديو غير ظاهر على الشاشة.
        TitiSingleEngine().pause();
      }
    } else {
      // طلعت من توصيات - احفظ رابطي الحالي بالهوم مشان يرجعني لنفس المكان
      // الهوم عنده الخريطة _innerTabLastUrl
    }
  }

  @override
  void dispose() {
    _audience.removeListener(_onAudienceChanged);
    _tabController?.removeListener(_onTopTabChanged);
    super.dispose();
  }

  Future<void> _fetchForYou() async {
    if (_isFetchingMore) return;
    _isFetchingMore = true;
    final requestUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final r = await FirebaseFunctions.instanceFor(region: 'europe-west1')
    .httpsCallable('getForYouOnScroll')
    .call({"seenIds": _seenIds});
            if (!mounted || requestUid != FirebaseAuth.instance.currentUser?.uid) return;
            for (var p in (r.data['posts'] as List)) {
        final String pid = (p is String)? p : p['id'].toString();
        _seenIds.add(pid);
        final doc = await FirebaseFirestore.instance.collection('posts').doc(pid).get();
        if (!mounted || requestUid != FirebaseAuth.instance.currentUser?.uid) return;
               if (doc.exists) {
                  final data = doc.data();
                  if (data!= null && data['isDeleted'] == true) continue;
                  final String privacy = (data?['privacy'] ?? data?['defaultPrivacy'] ?? 'everyone').toString();
                  if (privacy == 'only_me' || privacy == 'friends' || privacy == 'private') continue;
                  if (data != null) _audience.trackPost(data, postId: doc.id);
                  // [HARD BLOCK - مركزي - Two Way]
                  try {
                    final uid = data?['uid']?.toString()?? '';
                    if (uid.isNotEmpty) {
                      final blockedSet = context.read<PostProvider>().hardBlockedIds.toSet();
                      Set<String> blockedBySet = {};
                      try { blockedBySet = context.read<custom.AuthProvider>().blockedBySet; } catch (_) {}
                      if (blockedSet.contains(uid) || blockedBySet.contains(uid)) continue;
                    }
                  } catch (_) {}
          if (!_forYouPosts.any((existing) => existing.id == doc.id)) _forYouPosts.add(doc);
        }
      }
      // [اضافة هاشتاغ]: اذا السيرفر رجع فاضي جرب المحلي حسب اهتماماتو
      if (_forYouPosts.isEmpty && _seenIds.isEmpty) {
        await _fetchFromHashtagInterests();
      }
    } catch (e) {
      if (!mounted || requestUid != FirebaseAuth.instance.currentUser?.uid) return;
      debugPrint("ForYou $e");
      // [اضافة هاشتاغ]: fallback محلي اذا الـ Function فشلت
      await _fetchFromHashtagInterests();
    }
    if (mounted) {
      setState(() {
        _isFirstLoading = false;
        _isFetchingMore = false;
      });
    }
  }

  // [اضافة جديدة فقط - لا تمس اي ميزة قديمة]: جلب حسب hashtagInterests اللي بنيناه + AUDIENCE CONTROL
  Future<void> _fetchFromHashtagInterests() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final interestsSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('hashtagInterests')
        .orderBy('count', descending: true)
        .limit(5)
        .get();
      if (!mounted || uid != FirebaseAuth.instance.currentUser?.uid) return;
      if (interestsSnap.docs.isEmpty) return;
      List<String> topTags = interestsSnap.docs.map((d) => d.id).toList();
      if (topTags.isEmpty) return;

      final postsSnap = await FirebaseFirestore.instance
        .collection('posts')
        .where('hashtags', arrayContainsAny: topTags)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();

      if (!mounted || uid != FirebaseAuth.instance.currentUser?.uid) return;
      for (var doc in postsSnap.docs) {
        if (_seenIds.contains(doc.id)) continue;
        final data = doc.data() as Map<String, dynamic>?;
        if (data!= null && data['isDeleted'] == true) continue;
        final String privacy = (data?['privacy'] ?? data?['defaultPrivacy'] ?? 'everyone').toString();
        if (privacy == 'only_me' || privacy == 'friends' || privacy == 'private') continue;
        if (data != null) _audience.trackPost(data, postId: doc.id);
        // [HARD BLOCK - مركزي - Two Way]
        try {
          final uid = data?['uid']?.toString()?? '';
          if (uid.isNotEmpty) {
            final blockedSet = context.read<PostProvider>().hardBlockedIds.toSet();
            Set<String> blockedBySet = {};
            try { blockedBySet = context.read<custom.AuthProvider>().blockedBySet; } catch (_) {}
            if (blockedSet.contains(uid) || blockedBySet.contains(uid)) continue;
          }
        } catch (_) {}
        _seenIds.add(doc.id);
        _forYouPosts.add(doc);
      }
    } catch (e) {
      debugPrint("HashtagInterests fallback $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // مهم جدا مع AutomaticKeepAliveClientMixin
    final currentUser = FirebaseAuth.instance.currentUser;

if (currentUser == null) {
  return const Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: Text(
        'يرجى تسجيل الدخول',
        style: TextStyle(color: Colors.white),
      ),
    ),
  );
}

final myUid = currentUser.uid;
    final postProv = context.watch<PostProvider>();
    // [TIKTOK FLIP - ADDITION] - اذا في فيديو جديد من post_provider حطو اول واحد واقلب عليه
    // [TIKTOK FLIP - FIX] - عالج كل رفع مرة واحدة واستبعد فيديوهاتي الأقدم من قائمة التوصيات نفسها.
    final latestUpload = postProv.lastUploadedPost;
    if (latestUpload!= null && latestUpload.id!= _lastHandledUploadId) {
      _lastHandledUploadId = latestUpload.id;
      _forYouPosts.removeWhere((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return doc.id == latestUpload.id || data?['uid'] == myUid;
      });
      _forYouPosts.insert(0, latestUpload);
      _seenIds.removeWhere((id) => id == latestUpload.id);
      _seenIds.insert(0, latestUpload.id);
      _currentVideoIndex = 0;
    }

    // [تعديل Tini الهيكلي الجراحي]: تصفير مساحة الأمان هنا لأنها محجوزة ومحسوبة بدقة داخل الـ HomeScreen منعاً للتداخل وضغط الفيديو
    return Scaffold(
      backgroundColor: titiBG,
      body: Padding(
        padding: EdgeInsets.zero, // 👈 جعل البادينج صفر لتفرش شاشة عرض الفيديوهات بالكامل وتطرد السواد
        // [قاعدة الإضافة فقط]: تم استبدال النص الثابت بالـ StreamBuilder لتشغيل شاشة العرض مباشرة
        child: _isFirstLoading
       ? Builder(builder: (context) {
              final cached = context.watch<PostProvider>().initialPosts;
              // [FIX - مشكلة ظهور فيديوي ثانيتين] - فلترة فيديوهاتي من كاش البداية فقط
              final filteredCached = cached.where((doc) {
                final data = doc.data() as Map<String, dynamic>?;
                if (data == null) return false;
                if (data['isDeleted'] == true) return false;
                if (!_audience.canViewPost(data, postId: doc.id)) return false;
                return data['uid'] != myUid;
              }).toList();
              if (filteredCached.isNotEmpty) {
                return PostViewScreen(
                  isFeedActive: _isFeedActive,
                  isEmbeddedFeed: true,
                  posts: filteredCached,
                  initialIndex: 0,
                  thumbnailUrl: null,
                  hideBars: true,
                  enablePeopleCarousel: true,
                  onCommentsToggle: (isOpen) {
                    final homeState = context.findAncestorStateOfType<HomeScreenState>();
                    if (homeState!= null) homeState.toggleCommentsPanel(isOpen);
                  },
                );
              }
              return Container(color: Colors.black);
            })
          : _forYouPosts.isEmpty
            // [حل مشكلة 4 - الفيد الفاضي]: اذا forYouFeed فاضي ترجع ترند عام كـ fallback بدل شاشة فاضية
         ? StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
               .collection('trendingFeed')
               .doc('global')
               .collection('posts')
               .orderBy('trendingScore', descending: true)
               .limit(100)
               .snapshots(),
                builder: (context, fallbackSnap) {
                  if (fallbackSnap.connectionState == ConnectionState.waiting) {
                    final cached = context.read<PostProvider>().initialPosts;
                    final filteredCached = cached.where((doc) {
                      final data = doc.data() as Map<String, dynamic>?;
                      if (data == null) return false;
                      if (!_audience.canViewPost(data, postId: doc.id)) return false;
                      return data['uid'] != myUid;
                    }).toList();
                    if (filteredCached.isNotEmpty) {
                      return PostViewScreen(
                  isFeedActive: _isFeedActive,
                  isEmbeddedFeed: true,
                        posts: filteredCached,
                        initialIndex: 0,
                        thumbnailUrl: null,
                        hideBars: true,
                        enablePeopleCarousel: true,
                        onCommentsToggle: (isOpen) {
                          final homeState = context.findAncestorStateOfType<HomeScreenState>();
                          if (homeState!= null) homeState.toggleCommentsPanel(isOpen);
                        },
                      );
                    }
                    return Container(color: Colors.black);
                  }
                  if (!fallbackSnap.hasData || fallbackSnap.data!.docs.isEmpty) {
                    return const Center(
                      child: Text(
                        "لا توجد توصيات حالياً - تفاعل أكثر",
                        style: TextStyle(
                          color: Colors.white70, // اللون الثانوي المعتمد للنصوص
                          fontSize: 16,
                        ),
                      ),
                    );
                  }
                  // 4. استخراج قائمة المستندات الحية - فلترة نهائية + حماية الحساب الخاص (للـ fallback) + AUDIENCE CONTROL + Two Way
                  List<DocumentSnapshot> fallbackPosts = fallbackSnap.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['isDeleted'] == true) return false;
                    if (context.watch<PostProvider>().blockedOwnerIds.contains(data['uid'])) return false;
                    if (context.watch<PostProvider>().hardBlockedIds.toSet().contains(data['uid'])) return false; // [HARD BLOCK مركزي]
                    try { if (context.watch<custom.AuthProvider>().blockedBySet.contains(data['uid'])) return false; } catch (_) {}
                    // [AUDIENCE CONTROL] - 18+ ما يظهر للقاصر
                    if (!_audience.canViewPost(data, postId: doc.id)) return false;
                    final privacy = (data['privacy'] ?? data['defaultPrivacy'] ?? 'everyone').toString();
                    // [إصلاح ثغرة الخصوصية]: منع ظهور فيديوهات الحساب الخاص للغرباء
                    final ownerIsPrivateAccount = data['ownerIsPrivateAccount'] == true;
                    // 2. لا تظهر اي منشور خاص
                    if (privacy == 'private' || privacy == 'only_me' || privacy == 'friends') return false;
                    // 3. [جديد]: لا تظهر فيديوهات اصحاب الحسابات الخاصة ابدا هنا
                    if (ownerIsPrivateAccount) return false;
                    return true;
                  }).toList();

                  _visiblePosts = fallbackPosts;
                  // 6. الاستدعاء والنقل الكامل: تشغيل محرك عرض الفيديوهات وحركة السحب (للـ fallback)
                  return PostViewScreen(
                  isFeedActive: _isFeedActive,
                  isEmbeddedFeed: true,
                    posts: fallbackPosts, // تمرير قائمة الفيديوهات الحية بالكامل
                    initialIndex: fallbackPosts.isEmpty? 0 : _currentVideoIndex.clamp(0, fallbackPosts.length - 1),
                    thumbnailUrl: null,
                    hideBars: true, // غطاء الفيديو المبدئي بحسب بنية ملفك
                    enablePeopleCarousel: true, // [جديد] يطلع بتبويب التوصيات كمان
                    // [إضافة]: الربط الهيكلي مع HomeScreen للتحكم في الشريط السفلي
                    onCommentsToggle: (isOpen) {
                      final homeState = context.findAncestorStateOfType<HomeScreenState>();
                      // 👈 التعديل: تحقق من أن homeState ليس null قبل استدعاء الدالة
                      if (homeState!= null) {
                        homeState.toggleCommentsPanel(isOpen);
                      }
                    },
                  );
                },
              )
            : Builder(
                builder: (context) {
                  // [TIKTOK FLIP - ADDITION] - آخر فيديو مرفوع موجود مسبقاً في القائمة، والتشغيل من شاشة العرض فقط.

                  // 4. استخراج قائمة المستندات الحية - فلترة نهائية + حماية الحساب الخاص + AUDIENCE CONTROL + Two Way
                  List<DocumentSnapshot> postsList = _forYouPosts.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['isDeleted'] == true) return false;
                    if (context.watch<PostProvider>().blockedOwnerIds.contains(data['uid'])) return false;
                    if (context.watch<PostProvider>().hardBlockedIds.toSet().contains(data['uid'])) return false; // [HARD BLOCK مركزي]
                    try { if (context.watch<custom.AuthProvider>().blockedBySet.contains(data['uid'])) return false; } catch (_) {}
                    // [AUDIENCE CONTROL] - 18+ ما يظهر للقاصر
                    if (!_audience.canViewPost(data, postId: doc.id)) return false;
                    final privacy = (data['privacy'] ?? data['defaultPrivacy'] ?? 'everyone').toString();
                    // [إصلاح ثغرة الخصوصية]: منع ظهور فيديوهات الحساب الخاص للغرباء
                    final ownerIsPrivateAccount = data['ownerIsPrivateAccount'] == true;
                    // 2. لا تظهر اي منشور خاص
                    if (privacy == 'private' || privacy == 'only_me' || privacy == 'friends') return false;
                    // 3. [جديد]: لا تظهر فيديوهات اصحاب الحسابات الخاصة ابدا هنا
                    if (ownerIsPrivateAccount) return false;
                    // [FIX - خوارزمية عدم ظهور فيديوهاتي] - لا تظهر فيديوهاتي الا اذا كانت هي فيديو الرفع الجديد
                    final isOwn = data['uid'] == myUid;
                    final isLastUpload = postProv.lastUploadedPost != null && doc.id == postProv.lastUploadedPost!.id;
                    if (isOwn && !isLastUpload) return false;
                    return true;
                  }).toList();

                  _visiblePosts = postsList;
                  if (_currentVideoIndex >= postsList.length) _currentVideoIndex = postsList.isEmpty ? 0 : postsList.length - 1;
                  // 6. الاستدعاء والنقل الكامل: تشغيل محرك عرض الفيديوهات وحركة السحب
                  return PostViewScreen(
                  isFeedActive: _isFeedActive,
                  isEmbeddedFeed: true,
                    posts: postsList, // تمرير قائمة الفيديوهات الحية بالكامل
                    initialIndex: postsList.isEmpty? 0 : _currentVideoIndex.clamp(0, postsList.length - 1),
                    thumbnailUrl: null,
                    hideBars: true, // غطاء الفيديو المبدئي بحسب بنية ملفك
                    enablePeopleCarousel: true, // [جديد] يطلع بتبويب التوصيات كمان
                                        // [حل مشكلة 3 - الـ 100 فيديو]: تحميل تدريجي لما يقرب يخلص
                    onIndexChanged: (currentIndex) {
                      _currentVideoIndex = currentIndex; // [Fix]: احفظ مكاني بهاد التبويب
                      if (currentIndex >= postsList.length - 20 &&!_isFetchingMore) {
                        _fetchForYou();
                        FirebaseFirestore.instance.collection('userInteractions').add({
                          'userId': myUid,
                          'postId': postsList[currentIndex].id,
                          'scrollDeep': true,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                      }
                    },
                    // [إضافة]: الربط الهيكلي مع HomeScreen للتحكم في الشريط السفلي
                    onCommentsToggle: (isOpen) {
                      final homeState = context.findAncestorStateOfType<HomeScreenState>();
                      // 👈 التعديل: تحقق من أن homeState ليس null قبل استدعاء الدالة
                      if (homeState!= null) {
                        homeState.toggleCommentsPanel(isOpen);
                      }
                    },
                  );
                },
              ),
      ),
    );
  }
}