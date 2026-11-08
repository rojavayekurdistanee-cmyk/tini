import 'package:flutter/material.dart';
import 'audience_access.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'post_view_screen.dart';
import 'home_screen.dart';
import 'package:provider/provider.dart';
import 'post_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'titi_single_engine.dart'; // [Fix]
import 'auth_provider.dart' as custom; // [Two-Way] - مشان blockedBySet

class TitiTrendingTab extends StatefulWidget {
  final bool isHomeActive;
  const TitiTrendingTab({super.key, this.isHomeActive = true});

  @override
  State<TitiTrendingTab> createState() => _TitiTrendingTabState();
}

class _TitiTrendingTabState extends State<TitiTrendingTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Fix تذكر مكان الفيديو برائج

  final Color titiBG = const Color(0xFF000000);
  TabController? _tabController;
  bool get _isFeedActive => widget.isHomeActive &&
      (_tabController?.index ?? 3) == 2 && !(_tabController?.indexIsChanging ?? false);
  int _currentVideoIndex = 0;
  List<DocumentSnapshot> _currentPosts = [];

  // [AUDIENCE CONTROL - ADDITION]
  // [إصلاح V2] اذا age = 0 احسبه من birthDate او dob
  // أصبح تحقق الميلاد والبيانات القديمة موحداً في سياسة الجمهور.
  final _audience = AudienceAccess.instance;

  void _onAudienceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _audience.addListener(_onAudienceChanged);

  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = DefaultTabController.of(context);
    if (_tabController != nextController) {
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
      if (_currentPosts.isEmpty) {
        // لا تعمل stop كامل، خليه pause مشان ما يمسح ذاكرة التبويبات التانية
        TitiSingleEngine().pause();
        return;
      }
      if (_currentVideoIndex >= _currentPosts.length) {
        _currentVideoIndex = 0;
      }
      final data = _currentPosts[_currentVideoIndex].data() as Map<String, dynamic>?;
      if (data == null || !_audience.canViewPost(data, postId: _currentPosts[_currentVideoIndex].id)) {
        TitiSingleEngine().pause();
        return;
      }
      // Fix: استخدم hlsPath اول بعدين videoUrl متل الـ Engine
      String url = (data['hlsPath'] as String?)?.trim()?? "";
      if (url.isEmpty) url = data['videoUrl'] as String? ?? '';
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // مهم مع AutomaticKeepAlive
    return Scaffold(
      backgroundColor: titiBG,
      body: Padding(
        padding: EdgeInsets.zero,
        child: StreamBuilder<QuerySnapshot>(
          // التعديل الوحيد هنا: صرنا نقرا من الصندوق الجاهز بدل posts كلها
          stream: FirebaseFirestore.instance
              .collection('trendingFeed')
              .doc('global')
              .collection('posts')
              .orderBy('trendingScore', descending: true)
              .limit(100) // اتفقنا 1000
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.teal),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text("لا توجد منشورات متاحة حالياً",
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
              );
            }

            final currentUid = FirebaseAuth.instance.currentUser?.uid;
            return StreamBuilder<QuerySnapshot>(
              stream: currentUid != null
                  ? FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUid)
                      .collection('blockedChannels')
                      .snapshots()
                  : const Stream.empty(),
              builder: (context, blockSnap) {
                final blockedIds = blockSnap.data?.docs.map((d) => d.id).toSet() ?? {};

                List<DocumentSnapshot> filteredList = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['isDeleted'] == true) return false;
                  if (blockedIds.contains(data['uid'])) return false; // حجب شخصي للرائج - عنك بس - قديم ما منلمسو
                  if (context.watch<PostProvider>().hardBlockedIds.toSet().contains(data['uid'])) return false; // [HARD BLOCK مركزي]
                  try { if (context.watch<custom.AuthProvider>().blockedBySet.contains(data['uid'])) return false; } catch (_) {} // [Two-Way] اذا هو حاظرني لا تطلع فيديوهاتي عنده بالرائج
                  // [AUDIENCE CONTROL] - 18+ ما يظهر للقاصر - قديم ما منلمسو
                  if (!_audience.canViewPost(data, postId: doc.id)) return false;
                  final privacy = (data['privacy'] ?? data['defaultPrivacy'] ?? 'everyone').toString();
                  final ownerIsPrivateAccount = data['ownerIsPrivateAccount'] == true;
                  if (privacy == 'private' || privacy == 'only_me' || privacy == 'friends') return false;
                  if (ownerIsPrivateAccount) return false;
                  return true;
                }).toList();

                 if (filteredList.isEmpty) {
                  _currentPosts = [];
                  if (_isFeedActive) TitiSingleEngine().pause();
                  return const Center(
                    child: Text("لا توجد منشورات رائجة حالياً",
                        style: TextStyle(color: Colors.white70, fontSize: 16)),
                  );
                }

                // [Fix نهائي]: اذا الفيديو يلي مشغول هلا انحظر وقف صوتو فوراً - Two Way
                if (_currentPosts.isNotEmpty) {
                  final currentId = _currentPosts.length > _currentVideoIndex? (_currentPosts[_currentVideoIndex].data() as Map<String, dynamic>)['uid'] : null;
                  bool isBlockedByMe = currentId!= null && (blockedIds.contains(currentId) || context.read<PostProvider>().hardBlockedIds.toSet().contains(currentId));
                  bool isBlockedByOther = false;
                  try { isBlockedByOther = currentId!= null && context.read<custom.AuthProvider>().blockedBySet.contains(currentId); } catch (_) {}
                  if (currentId!= null && (isBlockedByMe || isBlockedByOther)) {
                    if (_isFeedActive) TitiSingleEngine().pause();
                    _currentVideoIndex = 0;
                  }
                }

                _currentPosts = filteredList;
                return PostViewScreen(
                  isFeedActive: _isFeedActive,
                  isEmbeddedFeed: true,
                  key: ValueKey('trending_${filteredList.length}_${blockedIds.length}'),
                  posts: filteredList,
                  initialIndex: _currentVideoIndex.clamp(0, filteredList.length - 1),
                  thumbnailUrl: null,
                  hideBars: true,
                  onIndexChanged: (i) {
                    _currentVideoIndex = i; // [Fix]: احفظ مكاني برائج
                  },
                  onCommentsToggle: (isOpen) {
                    if (!mounted) return;
                    final homeState = context.findAncestorStateOfType<HomeScreenState>();
                    if (homeState!= null) {
                      homeState.toggleCommentsPanel(isOpen);
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}