import 'banner_manager.dart';
import 'user_documents.dart';
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

/*
  [Tini Project Rules]:
    1. File Name: tag_duet_history_screen.dart
    2. Concept: سجل الذكر - tag + duet فقط - أرشيف دائم
    3. ذكر السيرة الذاتية ملغي نهائياً
*/

class TagDuetHistoryScreen extends StatefulWidget {
  const TagDuetHistoryScreen({super.key});

  @override
  State<TagDuetHistoryScreen> createState() => _TagDuetHistoryScreenState();
}

class _TagDuetHistoryScreenState extends State<TagDuetHistoryScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  List<QueryDocumentSnapshot> _allZekr = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isInitialLoading = true;
  int _currentLimit = 30;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _sub;
  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    final viewer = FirebaseAuth.instance.currentUser?.uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && FirebaseAuth.instance.currentUser?.uid == viewer) {
        BannerManager.instance.clearTypes({BannerType.mention});
      }
    });
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (!mounted) return;
      setState(() {
        _allZekr = [];
        _isInitialLoading = true;
        _currentLimit = 30;
      });
      _listenWithLimit(_currentLimit);
    });
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        _fetchMore();
      }
    });
  }

  void _listenWithLimit(int limit) {
    _sub?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid?? '';
    if (uid.isEmpty) {
      setState(() { _isInitialLoading = false; _hasMore = false; });
      return;
    }
    _sub = FirebaseFirestore.instance
      .collection('activities')
      .where('toUid', isEqualTo: uid)
      .where('type', whereIn: ['mention', 'duet'])
      .orderBy('timestamp', descending: true)
      .limit(limit)
      .snapshots()
      .listen((snap) {
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() {
        _allZekr = snap.docs;
        _hasMore = snap.docs.length == limit;
        _isLoadingMore = false;
        _isInitialLoading = false;
      });
    });
  }

  void _fetchMore() {
    if (_isLoadingMore ||!_hasMore) return;
    setState(() => _isLoadingMore = true);
    _currentLimit += 30;
    _listenWithLimit(_currentLimit);
  }

  String _formatDateHeader(DateTime d) {
    final months = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
    return "${d.day} ${months[d.month-1]} ${d.year}";
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final d = ts.toDate();
    final diff = now.difference(d);
    if (diff.inMinutes < 60) return "منذ ${diff.inMinutes} دقيقة";
    if (diff.inHours < 24) return "منذ ${diff.inHours} ساعة";
    if (diff.inDays < 7) return "منذ ${diff.inDays} يوم";
    return "${d.day}/${d.month}";
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
    Map<String, List<QueryDocumentSnapshot>> grouped = {};
    Map<String, DateTime> groupDates = {};
    for (var doc in _allZekr) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data['timestamp'] as Timestamp?;
      if (ts == null) continue;
      final date = ts.toDate();
      final key = _formatDateHeader(date);
      grouped.putIfAbsent(key, () => []).add(doc);
      groupDates[key] = date;
    }
    final sortedKeys = grouped.keys.toList()..sort((a,b) => groupDates[b]!.compareTo(groupDates[a]!));

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text("سجل الذكر", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: _isInitialLoading
        ? Center(child: CircularProgressIndicator(color: titiTeal))
          : _allZekr.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                 Icon(Iconsax.user_tag, size: 70, color: Colors.white.withValues(alpha:0.1)),
                 const SizedBox(height: 12),
                 const Text('سجل الذكر فارغ', style: TextStyle(color: Colors.white54)),
               ]))
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: sortedKeys.length + (_hasMore?1:0),
                  itemBuilder: (context, groupIndex) {
                    if (groupIndex == sortedKeys.length) {
                      return Padding(padding: const EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: titiTeal, strokeWidth: 2)));
                    }
                    final dateKey = sortedKeys[groupIndex];
                    final items = grouped[dateKey]!;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 22, bottom: 8),
                        child: Text(dateKey, style: TextStyle(color: titiTeal.withValues(alpha:0.8), fontSize: 13, fontWeight: FontWeight.bold))),
                     ...items.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final fromUid = data['fromUid']?? '';
                        final type = data['type']?? 'mention';
                        final ts = data['timestamp'] as Timestamp?;
                        final postId = data['postId']?? '';
                        final isDuet = type == 'duet';
                        final textType = isDuet? "عمل ديو مع فيديو لك" : "ذكرك في وصف فيديو";
                        return FutureBuilder<DocumentSnapshot>(
                          future: UserDocuments.readable(FirebaseFirestore.instance, fromUid).get(),
                          builder: (context, userSnap) {
                            String fullName = 'مستخدم'; String profileImg = '';
                            if (userSnap.hasData && userSnap.data!.exists) {
                              final uData = userSnap.data!.data() as Map<String, dynamic>?;
                              fullName = uData?['fullName']?? uData?['username']?? 'مستخدم';
                              profileImg = uData?['profileImg']?? '';
                            }
                            return FutureBuilder<DocumentSnapshot>(
                              future: postId.isNotEmpty? FirebaseFirestore.instance.collection('posts').doc(postId).get() : null,
                              builder: (context, postSnap) {
                                Map<String, dynamic> postData = {};
                                String thumb = '';
                                if (postSnap!=null && postSnap.hasData && postSnap.data!.exists) {
                                  final pData = postSnap.data!.data() as Map<String, dynamic>?;
                                  postData = pData ?? {};
                                  thumb = pData?['thumbnailUrl']?? '';
                                }
                                return AudiencePostGate(
                                  post: postData,
                                  postId: postId.toString(),
                                  child: InkWell(
                                  onTap: () async {
                                    if (postSnap==null ||!postSnap.hasData ||!postSnap.data!.exists) return;
                                    if (!await AudienceAccess.instance.verifyPost(postId.toString())) return;
                                    final pDoc = postSnap.data!;
                                    try { await TitiSingleEngine().lock(); await TitiProfileEngine().unlock(); } catch(_){}
                                    if (!context.mounted) return;
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => PostViewScreen(posts: [pDoc], initialIndex: 0, isFromProfileGrid: true)))
                                    .then((_) async { try { await TitiProfileEngine().unlock(); await TitiSingleEngine().lock(); } catch(_){} });
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)),
                                    child: Row(children: [
                                      ClipRRect(borderRadius: BorderRadius.circular(8),
                                        child: Container(width: 55, height: 75, color: bgColor,
                                          child: thumb.isNotEmpty? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover) : const Icon(Iconsax.video, color: Colors.white24))),
                                      const SizedBox(width: 12),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                          Flexible(child: Text(fullName, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
                                          const SizedBox(width: 8),
                                          CircleAvatar(radius: 20, backgroundColor: bgColor, backgroundImage: profileImg.isNotEmpty? CachedNetworkImageProvider(profileImg):null,
                                            child: profileImg.isEmpty? Text(fullName.isNotEmpty?fullName[0].toUpperCase():"?", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)):null),
                                        ]),
                                        const SizedBox(height: 6),
                                        Row(children: [Icon(isDuet?Iconsax.repeat:Iconsax.user_tag, size: 14, color: titiTeal), const SizedBox(width: 4), Expanded(child: Text(textType, style: TextStyle(color: titiTeal, fontSize: 13)))]),
                                        const SizedBox(height: 4),
                                        Text(_formatTime(ts), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                      ])),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_ios, color: Colors.white10, size: 12),
                                    ]),
                                  ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      }).toList(),
                    ]);
                  },
                ),
    );
  }
}