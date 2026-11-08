import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'post_provider.dart';
import 'titi_single_engine.dart';
import 'titi_profile_engine.dart';
import 'audience_access.dart';
import 'audience_gate.dart';

class DeletedVideosScreen extends StatefulWidget {
  const DeletedVideosScreen({super.key});

  @override
  State<DeletedVideosScreen> createState() => _DeletedVideosScreenState();
}

class _DeletedVideosScreenState extends State<DeletedVideosScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  List<QueryDocumentSnapshot> _allDocs = [];
  StreamSubscription? _sub;
  StreamSubscription? _authSub;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (!mounted) return;
      setState(() {
        _allDocs = [];
        _isLoading = true;
      });
      _listenTrash();
    });
  }

  void _listenTrash() {
    _sub?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid?? '';
    if (uid.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    _sub = FirebaseFirestore.instance
   .collection('posts')
   .where('uid', isEqualTo: uid)
   .where('isDeleted', isEqualTo: true)
   .orderBy('deletedAt', descending: true)
   .snapshots()
   .listen((snap) {
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() {
        _allDocs = snap.docs;
        _isLoading = false;
      });
    }, onError: (e) {
      debugPrint("⚠ Trash Index Missing: $e");
      if (!mounted) return;
      setState(() => _isLoading = false);
    });
  }

  String _remainingText(Timestamp? expireAt) {
    if (expireAt == null) return 'متبقي 30 يوم';
    final diff = expireAt.toDate().difference(DateTime.now()).inDays;
    if (diff <= 0) return 'متبقي أقل من يوم';
    if (diff == 1) return 'متبقي يوم';
    return 'متبقي $diff يوم';
  }

  void _showInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('المحذوفات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        content: const Text('سيتم حذف المنشورات نهائياً بعد الوقت الموضح.', style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('حسناً', style: TextStyle(color: titiTeal)))],
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text('المحذوفات', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Iconsax.info_circle, color: Colors.white70), onPressed: _showInfo)],
      ),
      body: _isLoading
     ? Center(child: CircularProgressIndicator(color: titiTeal))
          : _allDocs.isEmpty
         ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Iconsax.trash, size: 70, color: Colors.white.withValues(alpha: 0.1)),
                    const SizedBox(height: 12),
                    const Text('لا يوجد فيديوهات محذوفة', style: TextStyle(color: Colors.white54)),
                  ]),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(2),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2, childAspectRatio: 0.72),
                  itemCount: _allDocs.length,
                  itemBuilder: (context, index) {
                    final doc = _allDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final thumb = data['thumbnailUrl']?? '';
                    final expireAt = data['expireAt'] as Timestamp?;
                    return AudiencePostGate(
                      post: data,
                      postId: doc.id,
                      child: GestureDetector(
                      onTap: () async {
                        if (!await AudienceAccess.instance.verifyPost(doc.id)) return;
                        try {
                          await TitiSingleEngine().lock();
                          await TitiProfileEngine().unlock();
                        } catch (_) {}
                        if (!context.mounted) return;
                        Navigator.push(context, MaterialPageRoute(builder: (_) => DeletedVideoPreviewScreen(allDocs: _allDocs, initialIndex: index)));
                      },
                      child: Container(
                        color: surfaceColor,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            thumb.isNotEmpty? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover) : const Icon(Iconsax.video, color: Colors.white24),
                            Positioned(bottom: 0, left: 0, right: 0, child: Container(color: Colors.black.withValues(alpha: 0.7), padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_remainingText(expireAt), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center))),
                          ],
                        ),
                      ),
                      ),
                    );
                  },
                ),
    );
  }
}

class DeletedVideoPreviewScreen extends StatefulWidget {
  final List<QueryDocumentSnapshot> allDocs;
  final int initialIndex;
  const DeletedVideoPreviewScreen({super.key, required this.allDocs, required this.initialIndex});

  @override
  State<DeletedVideoPreviewScreen> createState() => _DeletedVideoPreviewScreenState();
}

class _DeletedVideoPreviewScreenState extends State<DeletedVideoPreviewScreen> {
  late int _currentIndex;
  late PageController _pageController;
  bool _isRestoring = false;
  String? _openingUid;
  StreamSubscription? _authSub;
  bool _sessionChanged = false;

  String _getBestUrl(Map<String, dynamic> data) {
    final hls = (data['hlsPath'] as String?)?.trim()?? "";
    if (hls.isNotEmpty) return hls;
    return (data['videoUrl'] as String?)?? "";
  }

  String _remainingText(Timestamp? expireAt) {
    if (expireAt == null) return 'متبقي 30 يوم';
    final diff = expireAt.toDate().difference(DateTime.now()).inDays;
    if (diff <= 0) return 'متبقي أقل من يوم';
    if (diff == 1) return 'متبقي يوم';
    return 'متبقي $diff يوم';
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _openingUid = FirebaseAuth.instance.currentUser?.uid;
    AudienceAccess.instance.addListener(_playCurrent);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || user?.uid == _openingUid) return;
      TitiProfileEngine().stop();
      setState(() => _sessionChanged = true);
      if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _playCurrent());
  }

  String? _allowedUrl(int index) {
    if (index < 0 || index >= widget.allDocs.length) return null;
    final doc = widget.allDocs[index];
    final data = doc.data() as Map<String, dynamic>;
    if (!AudienceAccess.instance.canViewPost(data, postId: doc.id)) return null;
    return _getBestUrl(data);
  }

  void _playCurrent() {
    if (!mounted || _sessionChanged || FirebaseAuth.instance.currentUser?.uid != _openingUid) return;
    if (ModalRoute.of(context)?.isCurrent != true || widget.allDocs.isEmpty) return;
    final data = widget.allDocs[_currentIndex].data() as Map<String, dynamic>;
    final url = _getBestUrl(data);
    if (url.isEmpty) return;
    if (_allowedUrl(_currentIndex) == null) {
      // انتظار التحقق لا يقفل المحرك عن صاحب الفيديو بعد عودة الاتصال.
      TitiProfileEngine().pause();
      return;
    }

    String? prev, prevPrev, next, nextNext, nextNextNext;
    if (_currentIndex - 1 >= 0) prev = _allowedUrl(_currentIndex - 1);
    if (_currentIndex - 2 >= 0) prevPrev = _allowedUrl(_currentIndex - 2);
    if (_currentIndex + 1 < widget.allDocs.length) next = _allowedUrl(_currentIndex + 1);
    if (_currentIndex + 2 < widget.allDocs.length) nextNext = _allowedUrl(_currentIndex + 2);
    if (_currentIndex + 3 < widget.allDocs.length) nextNextNext = _allowedUrl(_currentIndex + 3);

    TitiProfileEngine().playSingleUrl(url, prevUrl: prev, prevPrevUrl: prevPrev, nextUrl: next, nextNextUrl: nextNext, nextNextNextUrl: nextNextNext);
  }

  @override
  void dispose() {
    AudienceAccess.instance.removeListener(_playCurrent);
    _authSub?.cancel();
    _pageController.dispose();
    TitiProfileEngine().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionChanged) return const Scaffold(backgroundColor: Colors.black);
    final double screenHeight = MediaQuery.of(context).size.height;
    final double topBarHeight = screenHeight * 0.032;
    final double bottomBarHeight = screenHeight * 0.0775;
    const Color titiDarkBG = Color(0xFF000000);

    final currentData = widget.allDocs[_currentIndex].data() as Map<String, dynamic>;
    final expireAt = currentData['expireAt'] as Timestamp?;

    return Scaffold(
      backgroundColor: titiDarkBG,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: widget.allDocs.length,
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              _playCurrent();
            },
            itemBuilder: (context, index) {
              final doc = widget.allDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final videoUrl = _getBestUrl(data);
              final thumb = data['thumbnailUrl'] as String?;

              // نفس مكان TitiVideoPlayer بس فيديو يملي الشاشة
              return AudiencePostGate(
                post: data,
                postId: doc.id,
                child: SizedBox.expand(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb!= null && thumb.isNotEmpty)
                      CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover),
                    ValueListenableBuilder<List<String>>(
                      valueListenable: TitiProfileEngine().playerUrlsNotifier,
                      builder: (context, urls, _) {
                        final myIdx = urls.indexOf(videoUrl);
                        if (myIdx == -1) return const SizedBox.shrink();
                        return Video(
                          controller: TitiProfileEngine().getControllerByIndex(myIdx),
                          fit: BoxFit.cover,
                          fill: Colors.transparent,
                          controls: (s) => const SizedBox.shrink(),
                        );
                      },
                    ),
                  ],
                ),
                ),
              );
            },
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: topBarHeight + MediaQuery.of(context).padding.top,
              color: Colors.black,
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18), onPressed: () => Navigator.pop(context)),
                  Expanded(child: Text(_remainingText(expireAt), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: bottomBarHeight,
              color: Colors.black,
              child: Center(
                child: SizedBox(
                  width: 110,
                  height: 36,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    onPressed: _isRestoring? null : () async {
                      setState(() => _isRestoring = true);
                      try {
                        final currentDocId = widget.allDocs[_currentIndex].id;
                        if (FirebaseAuth.instance.currentUser?.uid != _openingUid ||
                            !await AudienceAccess.instance.verifyPost(currentDocId)) return;
                        if (!context.mounted) return;
                        await Provider.of<PostProvider>(context, listen: false).restorePost(currentDocId);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت استعادة الفيديو'), backgroundColor: Colors.teal));
                          if (widget.allDocs.length == 1) Navigator.pop(context);
                        }
                      } finally {
                        if (mounted) setState(() => _isRestoring = false);
                      }
                    },
                    child: _isRestoring? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('استعادة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
