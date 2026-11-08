import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'post_view_screen.dart';
import 'titi_single_engine.dart';
import 'titi_profile_engine.dart';
import 'audience_access.dart';
import 'audience_gate.dart';

class CommentsHistoryScreen extends StatefulWidget {
  const CommentsHistoryScreen({super.key});

  @override
  State<CommentsHistoryScreen> createState() => _CommentsHistoryScreenState();
}

class _CommentsHistoryScreenState extends State<CommentsHistoryScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  List<QueryDocumentSnapshot> _allComments = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isInitialLoading = true;
  int _currentLimit = 30;
  bool _newestFirst = true;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _sub;
  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    // هذا هو السطر المصلح - كان _listenWithLimit مباشر وهاد كان يخلي الدائرة تدور بعد قفل التطبيق
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (!mounted) return;
      setState(() {
        _allComments = [];
        _isInitialLoading = true;
        _currentLimit = 30;
      });
      _listenWithLimit(_currentLimit);
    });
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        _fetchMore();
      }
    });
  }

  void _listenWithLimit(int limit) {
    _sub?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid?? '';
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _hasMore = false;
        });
      }
      return;
    }
    _sub = FirebaseFirestore.instance
      .collectionGroup('comments')
      .where('uid', isEqualTo: uid)
      .orderBy('timestamp', descending: _newestFirst)
      .limit(limit)
      .snapshots()
      .listen((snap) {
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() {
        _allComments = snap.docs;
        _hasMore = snap.docs.length == limit;
        _isLoadingMore = false;
        _isInitialLoading = false;
      });
    }, onError: (e) {
      debugPrint("CommentsHistory Error: $e");
      if (!mounted) return;
      setState(() {
        _isInitialLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
    });
  }

  void _fetchMore() {
    if (_isLoadingMore ||!_hasMore) return;
    setState(() => _isLoadingMore = true);
    _currentLimit += 30;
    _listenWithLimit(_currentLimit);
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 16),
          const Text('ترتيب حسب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          ListTile(
            title: const Text('الأحدث للأقدم', style: TextStyle(color: Colors.white)),
            trailing: _newestFirst? Icon(Icons.check_circle, color: titiTeal) : const Icon(Icons.circle_outlined, color: Colors.white24),
            onTap: () {
              setState(() { _newestFirst = true; _currentLimit = 30; _isInitialLoading = true; });
              _listenWithLimit(_currentLimit);
              Navigator.pop(context);
            },
          ),
          ListTile(
            title: const Text('من الأقدم إلى الأحدث', style: TextStyle(color: Colors.white)),
            trailing:!_newestFirst? Icon(Icons.check_circle, color: titiTeal) : const Icon(Icons.circle_outlined, color: Colors.white24),
            onTap: () {
              setState(() { _newestFirst = false; _currentLimit = 30; _isInitialLoading = true; });
              _listenWithLimit(_currentLimit);
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final months = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
    return "${d.day} ${months[d.month-1]}";
  }

  Future<Map<String, dynamic>?> _getParentComment(String postId, String parentId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('posts').doc(postId).collection('comments').doc(parentId).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) { return null; }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _authSub?.cancel();
    _scrollController.dispose();
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
        title: const Text("سجل التعليقات", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _showSortSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_newestFirst? 'الأحدث للأقدم' : 'من الأقدم إلى الأحدث', style: const TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(width: 6),
                    const Icon(Iconsax.arrow_down_1, size: 14, color: Colors.white70),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isInitialLoading
           ? Center(child: CircularProgressIndicator(color: titiTeal))
                : _allComments.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Iconsax.message, size: 70, color: Colors.white.withValues(alpha:0.1)), const SizedBox(height: 10), const Text('لا يوجد تعليقات', style: TextStyle(color: Colors.white54))]))
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _allComments.length + (_hasMore? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _allComments.length) {
                          return Padding(padding: const EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: titiTeal, strokeWidth: 2)));
                        }
                        final doc = _allComments[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final commentText = data['text']?? '';
                        final postId = doc.reference.parent.parent?.id?? '';
                        final parentId = data['parentId'] as String?;
                        final ts = data['timestamp'] as Timestamp?;
                        // الأسماء الحقيقية من UserModel + PostCommentsSheet
                        final String fullName = data['fullName']?? data['userName']?? 'أنت';
                        final String profileImg = data['profileImg']?? data['userImage']?? '';

                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('posts').doc(postId).get(),
                          builder: (context, postSnap) {
                            Map<String, dynamic> postData = {};
                            String thumb = '';
                            if (postSnap.hasData && postSnap.data!.exists) {
                              final pData = postSnap.data!.data() as Map<String, dynamic>?;
                              postData = pData ?? {};
                              thumb = pData?['thumbnailUrl']?? '';
                            }

                            return AudiencePostGate(
                              post: postData,
                              postId: postId,
                              child: InkWell(
                              onTap: () async {
                                if (postId.isEmpty) return;
                                if (!postSnap.hasData ||!postSnap.data!.exists) return;
                                if (!await AudienceAccess.instance.verifyPost(postId)) return;
                                final pDoc = postSnap.data!;
                                try { await TitiSingleEngine().lock(); await TitiProfileEngine().unlock(); } catch (_) {}
                                if (!context.mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PostViewScreen(
                                      posts: [pDoc],
                                      initialIndex: 0,
                                      isFromProfileGrid: true,
                                      openComments: true,
                                      highlightCommentId: doc.id,
                                    ),
                                  ),
                                ).then((_) async {
                                  try { await TitiProfileEngine().unlock(); await TitiSingleEngine().lock(); } catch (_) {}
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // اقصى اليسار: صورة الفيديو
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 55, height: 75, color: bgColor,
                                        child: thumb.isNotEmpty? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover) : const Icon(Iconsax.video, color: Colors.white24),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // اليمين: صورة البروفايل على اليمين والاسم على يسارها مباشرة
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Flexible(
                                                child: Text(fullName, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                                              ),
                                              const SizedBox(width: 8),
                                              CircleAvatar(
                                                radius: 20,
                                                backgroundColor: bgColor,
                                                backgroundImage: profileImg.isNotEmpty? CachedNetworkImageProvider(profileImg) : null,
                                                child: profileImg.isEmpty? Text(fullName.isNotEmpty? fullName[0].toUpperCase() : "?", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)) : null,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          if (parentId!= null)
                                            FutureBuilder<Map<String, dynamic>?>(
                                              future: _getParentComment(postId, parentId),
                                              builder: (context, parentSnap) {
                                                if (!parentSnap.hasData || parentSnap.data == null) {
                                                  return const Text("رد على تعليق", style: TextStyle(color: Colors.white38, fontSize: 11));
                                                }
                                                final parentName = parentSnap.data!['fullName']?? parentSnap.data!['userName']?? 'مستخدم';
                                                final parentText = parentSnap.data!['text']?? '';
                                                return Padding(
                                                  padding: const EdgeInsets.only(bottom: 4),
                                                  child: Text("رددت على @${parentName}: ${parentText}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                                );
                                              },
                                            ),
                                          // تحتهم: التعليق
                                          Text(commentText, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3)),
                                          const SizedBox(height: 6),
                                          Text(_formatDate(ts), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.arrow_forward_ios, color: Colors.white10, size: 12),
                                  ],
                                ),
                              ),
                              ),
                            );
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
