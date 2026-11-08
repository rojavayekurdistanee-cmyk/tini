import 'package:flutter/material.dart';
import 'audience_access.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'post_view_screen.dart';
import 'home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'titi_single_engine.dart';

class TitiFriendsTab extends StatefulWidget {
  final bool isHomeActive;
  const TitiFriendsTab({super.key, this.isHomeActive = true});

  @override
  State<TitiFriendsTab> createState() => _TitiFriendsTabState();
}

class _TitiFriendsTabState extends State<TitiFriendsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Fix الأصدقاء يتذكر وين كان

  final Color titiBG = const Color(0xFF000000);
  final List<DocumentSnapshot> _allPosts = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isInitialLoading = true;
  final _firestore = FirebaseFirestore.instance;
  TabController? _tabController;
  bool get _isFeedActive => widget.isHomeActive &&
      (_tabController?.index ?? 3) == 1 && !(_tabController?.indexIsChanging ?? false);
  int _currentVideoIndex = 0;

  // [AUDIENCE CONTROL - ADDITION - صمام أمان ثانوي]
  // [إصلاح V2] اذا age = 0 احسبه من birthDate او dob
  // أصبح تحقق الميلاد والبيانات القديمة موحداً في سياسة الجمهور.
  final _audience = AudienceAccess.instance;
  String? _loadedUid;

  List<DocumentSnapshot> get _visiblePosts => _allPosts.where((doc) {
    final data = doc.data() as Map<String, dynamic>?;
    return data != null && _audience.canViewPost(data, postId: doc.id);
  }).toList();

  void _onAudienceChanged() {
    if (!mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != _loadedUid) {
      _loadedUid = uid;
      _allPosts.clear();
      _currentVideoIndex = 0;
      if (_isFeedActive) TitiSingleEngine().pause();
      if (uid != null) _initialLoad(uid);
    }
    setState(() {});
  }

  // فلتر الخصوصية - يمنع فيديوهات أنا فقط
  bool _passesPrivacyFilter(Map<String, dynamic> data) {
    final String privacy = (data['privacy'] ?? data['defaultPrivacy'] ?? 'everyone').toString().toLowerCase().trim();
    if (privacy == 'only_me' || privacy == 'private') {
      return false;
    }
    return true;
  }

  bool _passesAudienceFilter(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return true;
    if (data['isDeleted'] == true) return false;

    // [إصلاح] أول شي نفحص الخصوصية
    if (!_passesPrivacyFilter(data)) return false;

    // فحص الجمهور الحي عند العرض، مع الاحتفاظ بالمرشحين لعودة الفيديو بعد إلغاء التقييد.
    return true;
  }

  @override
  void initState() {
    super.initState();
    _audience.addListener(_onAudienceChanged);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _loadedUid = uid;
    if (uid != null) _initialLoad(uid);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newController = DefaultTabController.of(context);
    if (newController!= _tabController) {
      _tabController?.removeListener(_onTopTabChanged);
      _tabController = newController;
      _tabController?.addListener(_onTopTabChanged);
    }
  }

  void _onTopTabChanged() {
    if (!mounted) return;
    setState(() {});
    final isMyTabActive = _isFeedActive;
    if (isMyTabActive) {
      final visiblePosts = _visiblePosts;
      if (visiblePosts.isEmpty) {
        // لا تعمل stop كامل، خليه pause مشان ما يمسح ذاكرة التبويبات التانية
        TitiSingleEngine().pause();
        return;
      }
      if (_currentVideoIndex >= visiblePosts.length) {
        _currentVideoIndex = 0;
      }
      final data = visiblePosts[_currentVideoIndex].data() as Map<String, dynamic>?;
      // Fix: استخدم hlsPath اول بعدين videoUrl متل الـ Engine
      String url = (data?['hlsPath'] as String?)?.trim() ?? "";
      if (url.isEmpty) url = data?['videoUrl'] as String? ?? '';
      if (url.isNotEmpty) {
        TitiSingleEngine().playUrl(url);
      } else {
        TitiSingleEngine().pause();
      }
    }
  }

  @override
  void dispose() {
    _audience.removeListener(_onAudienceChanged);
    _tabController?.removeListener(_onTopTabChanged);
    super.dispose();
  }

  Future<void> _initialLoad(String uid) async {
    if (!mounted) return;
    setState(() => _isInitialLoading = true);
    _allPosts.clear();
    _lastDoc = null;
    _hasMore = true;
    _isLoadingMore = false;
    final snap = await _firestore.collection('users').doc(uid).collection('friendsFeed').orderBy('createdAt', descending: true).limit(20).get();
    if (!mounted || uid != FirebaseAuth.instance.currentUser?.uid) return;
    // [AUDIENCE CONTROL] - فلترة احتياطية
    final filtered = snap.docs.where((d) => _passesAudienceFilter(d)).toList();
    _allPosts.addAll(filtered);
    if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
    if (snap.docs.length < 20) _hasMore = false;
    if (!mounted) return;
    setState(() => _isInitialLoading = false);

    // [الحل] شغل أول فيديو مباشرة بعد التحميل - فقط اذا كنا لسا بهاد التبويب
    final visiblePosts = _visiblePosts;
    if (visiblePosts.isNotEmpty && _isFeedActive) {
      final data = visiblePosts[_currentVideoIndex.clamp(0, visiblePosts.length - 1)].data() as Map<String, dynamic>?;
      String url = (data?['hlsPath'] as String?)?.trim()?? "";
      if (url.isEmpty) url = data?['videoUrl'] as String? ?? '';
      if (url.isNotEmpty) {
        TitiSingleEngine().playUrl(url);
      }
    }
  }

  Future<void> _loadMore(String uid) async {
    if (_isLoadingMore ||!_hasMore) return;
    if (!mounted) return;
    setState(() => _isLoadingMore = true);
    Query q = _firestore.collection('users').doc(uid).collection('friendsFeed').orderBy('createdAt', descending: true).limit(20);
    if (_lastDoc!= null) q = q.startAfterDocument(_lastDoc!);
    final snap = await q.get();
    if (!mounted || uid != FirebaseAuth.instance.currentUser?.uid) return;
    if (snap.docs.isNotEmpty) {
      _lastDoc = snap.docs.last;
      final filtered = snap.docs.where((d) => _passesAudienceFilter(d)).toList();
      _allPosts.addAll(filtered);
    }
    if (snap.docs.length < 20) _hasMore = false;
    if (!mounted) return;
    setState(() => _isLoadingMore = false);
  }

  Future<void> _refresh(String uid) async {
    _allPosts.clear();
    _lastDoc = null;
    _hasMore = true;
    final snap = await _firestore.collection('users').doc(uid).collection('friendsFeed').orderBy('createdAt', descending: true).limit(20).get();
    if (!mounted || uid != FirebaseAuth.instance.currentUser?.uid) return;
    setState(() {
      final filtered = snap.docs.where((d) => _passesAudienceFilter(d)).toList();
      _allPosts.addAll(filtered);
      if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
      if (snap.docs.length < 20) _hasMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // مهم مع AutomaticKeepAlive
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final visiblePosts = _visiblePosts;
    if (currentUserId == null) {
      return Scaffold(backgroundColor: titiBG);
    }
    if (_currentVideoIndex >= visiblePosts.length) _currentVideoIndex = visiblePosts.isEmpty ? 0 : visiblePosts.length - 1;
    if (_isInitialLoading) {
      return Scaffold(
        backgroundColor: titiBG,
        body: const Center(child: CircularProgressIndicator(color: Colors.teal)),
      );
    }
    if (visiblePosts.isEmpty) {
      return Scaffold(
        backgroundColor: titiBG,
        body: RefreshIndicator(
          onRefresh: () => _refresh(currentUserId),
          color: Colors.teal,
          backgroundColor: titiBG,
          child: ListView(
            children: const [
              SizedBox(height: 300),
              Center(child: Text("أصدقاؤك لم ينشروا بعد", style: TextStyle(color: Colors.white70, fontSize: 16))),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: titiBG,
      body: RefreshIndicator(
        onRefresh: () => _refresh(currentUserId),
        color: Colors.teal,
        backgroundColor: titiBG,
        child: PostViewScreen(
                  isFeedActive: _isFeedActive,
                  isEmbeddedFeed: true,
          key: ValueKey('friends_${visiblePosts.length}_${_currentVideoIndex}'),
          posts: visiblePosts,
          initialIndex: _currentVideoIndex,
          thumbnailUrl: null,
          hideBars: true,
          enablePeopleCarousel: true,
          onIndexChanged: (i) {
            _currentVideoIndex = i;
            final data = visiblePosts[i].data() as Map<String, dynamic>?;
            String url = (data?['hlsPath'] as String?)?.trim()?? "";
            if (url.isEmpty) url = data?['videoUrl'] as String? ?? '';
            if (_isFeedActive && url.isNotEmpty) {
              TitiSingleEngine().playUrl(url);
            }
            if (!_isLoadingMore && _hasMore && i >= visiblePosts.length - 2) {
              _loadMore(currentUserId);
            }
          },
          onCommentsToggle: (isOpen) {
            if (!mounted) return;
            final homeState = context.findAncestorStateOfType<HomeScreenState>();
            homeState?.toggleCommentsPanel(isOpen);
          },
        ),
      ),
    );
  }
}