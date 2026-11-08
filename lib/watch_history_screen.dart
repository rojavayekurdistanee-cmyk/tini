import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
import 'post_view_screen.dart';
import 'titi_single_engine.dart';
import 'titi_profile_engine.dart';
import 'audience_access.dart';
import 'audience_gate.dart';

class WatchHistoryScreen extends StatefulWidget {
  const WatchHistoryScreen({super.key});

  @override
  State<WatchHistoryScreen> createState() => _WatchHistoryScreenState();
}

class _WatchHistoryScreenState extends State<WatchHistoryScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  String _filter = 'الكل';
  bool _selectMode = false;
  Set<String> _selected = {};

  // نظام 30 + 30 مثل البروفايل
  List<QueryDocumentSnapshot> _allHistoryDocs = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentLimit = 30;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _sub;
  StreamSubscription? _authSub;

  DateTime? _getDate(Map<String, dynamic> data) {
    final t = data['watchedAt'];
    if (t is Timestamp) return t.toDate();
    return null;
  }

  String _groupLabel(DateTime? d) {
    if (d == null) return 'أقدم';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    if (diff <= 7) return 'هذا الأسبوع';
    if (diff <= 30) return 'هذا الشهر';
    return 'أقدم';
  }

  bool _passFilter(DateTime? d) {
    if (_filter == 'الكل') return true;
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (_filter == 'اليوم') return diff == 0;
    if (_filter == 'أمس') return diff == 1;
    if (_filter == '7 أيام') return diff <= 7;
    if (_filter == '30 يوم') return diff <= 30;
    return true;
  }

  String _formatViews(dynamic v) {
    int c = 0;
    if (v is int) c = v;
    if (v is String) c = int.tryParse(v)?? 0;
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(1)}M';
    if (c >= 1000) return '${(c / 1000).toStringAsFixed(1)}K';
    return c.toString();
  }

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (!mounted) return;
      setState(() {
        _allHistoryDocs = [];
        _selected.clear();
        _selectMode = false;
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
      if (mounted) setState(() => _hasMore = false);
      return;
    }
    _sub = FirebaseFirestore.instance
       .collection('users')
       .doc(uid)
       .collection('watchHistory')
       .orderBy('watchedAt', descending: true)
       .limit(limit)
       .snapshots()
       .listen((snap) {
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() {
        _allHistoryDocs = snap.docs;
        _hasMore = snap.docs.length == limit;
        _isLoadingMore = false;
      });
    });
  }

  void _fetchMore() {
    if (_isLoadingMore ||!_hasMore) return;
    setState(() => _isLoadingMore = true);
    _currentLimit += 30;
    _listenWithLimit(_currentLimit);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _authSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _showFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 10),
          const Text('التصفية حسب التاريخ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (var f in ['الكل', 'اليوم', 'أمس', '7 أيام', '30 يوم'])
            ListTile(
              title: Text(f, style: TextStyle(color: _filter == f? titiTeal : Colors.white)),
              trailing: _filter == f? Icon(Icons.check, color: titiTeal) : null,
              onTap: () {
                setState(() => _filter = f);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid?? '';
    // فلترة حظر و تاريخ
    var docs = _allHistoryDocs;
    try {
      final auth = Provider.of<custom.AuthProvider>(context, listen: false);
      docs = docs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        final owner = (data['uid']?? '') as String;
        if (auth.blockedUsersSet.contains(owner)) return false;
        if (auth.blockedBySet.contains(owner)) return false;
        return true;
      }).toList();
    } catch (_) {}

    docs = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return _passFilter(_getDate(data));
    }).toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text('سجل المشاهدة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          if (!_selectMode)
            TextButton(onPressed: () => setState(() => _selectMode = true), child: const Text('حدد', style: TextStyle(color: Colors.white)))
          else...[
            TextButton(
              onPressed: _selected.isEmpty? null : () async {
                for (var id in _selected) {
                  await FirebaseFirestore.instance.collection('users').doc(uid).collection('watchHistory').doc(id).delete();
                }
                setState(() { _selected.clear(); _selectMode = false; });
              },
              child: Text('حذف (${_selected.length})', style: const TextStyle(color: Colors.redAccent)),
            ),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() { _selectMode = false; _selected.clear(); })),
          ]
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _showFilter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_filter == 'الكل'? 'التصفية حسب التاريخ' : _filter, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(width: 6),
                    const Icon(Iconsax.arrow_down_1, size: 14, color: Colors.white70),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(
            child: docs.isEmpty && _hasMore
               ? Center(child: CircularProgressIndicator(color: titiTeal))
                : docs.isEmpty
                   ? Center(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Iconsax.video_play, size: 70, color: Colors.white.withValues(alpha:0.1)),
                          const SizedBox(height: 10),
                          const Text('لا يوجد سجل', style: TextStyle(color: Colors.white54)),
                        ]),
                      )
                    : Builder(builder: (context) {
                        final Map<String, List<QueryDocumentSnapshot>> grouped = {};
                        for (var doc in docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          final label = _groupLabel(_getDate(data));
                          grouped.putIfAbsent(label, () => []).add(doc);
                        }
                        final order = ['اليوم', 'أمس', 'هذا الأسبوع', 'هذا الشهر', 'أقدم'];
                        final keys = grouped.keys.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));

                        return ListView.builder(
                          controller: _scrollController,
                          itemCount: keys.length + (_hasMore? 1 : 0),
                          itemBuilder: (context, gi) {
                            if (gi == keys.length) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(color: titiTeal, strokeWidth: 2)),
                              );
                            }
                            final label = keys[gi];
                            final gDocs = grouped[label]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2, childAspectRatio: 0.72),
                                  itemCount: gDocs.length,
                                  itemBuilder: (context, i) {
                                    final doc = gDocs[i];
                                    final data = doc.data() as Map<String, dynamic>;
                                    final thumb = data['thumbnailUrl']?? '';
                                    final views = data['views']?? 0;
                                    final isSel = _selected.contains(doc.id);
                                    return AudiencePostGate(
                                      post: data,
                                      postId: (data['postId'] ?? doc.id).toString(),
                                      child: GestureDetector(
                                      onTap: () async {
                                        final openingViewerUid = FirebaseAuth.instance.currentUser?.uid;
                                        if (_selectMode) {
                                          setState(() {
                                            if (isSel) _selected.remove(doc.id); else _selected.add(doc.id);
                                          });
                                          return;
                                        }
                                        final List<DocumentSnapshot> posts = [];
                                        for (var d in docs) {
                                          final dd = d.data() as Map<String, dynamic>;
                                          final pid = dd['postId']?? d.id;
                                          final pDoc = await FirebaseFirestore.instance.collection('posts').doc(pid).get();
                                          if (pDoc.exists && await AudienceAccess.instance.verifyPost(pid.toString())) posts.add(pDoc);
                                          if (FirebaseAuth.instance.currentUser?.uid != openingViewerUid) return;
                                        }
                                        final idx = posts.indexWhere((p) => p.id == (data['postId']?? doc.id));
                                        if (posts.isEmpty || idx < 0) return;

                                        try {
                                          await TitiSingleEngine().lock();
                                          await TitiProfileEngine().unlock();
                                        } catch (_) {}

                                        if (!context.mounted) return;
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PostViewScreen(
                                              posts: posts,
                                              initialIndex: idx == -1? 0 : idx,
                                              thumbnailUrl: data['thumbnailUrl'],
                                              isFromProfileGrid: true,
                                            ),
                                          ),
                                        ).then((_) async {
                                          try {
                                            await TitiProfileEngine().unlock();
                                            await TitiSingleEngine().lock();
                                          } catch (_) {}
                                        });
                                      },
                                      onLongPress: () => setState(() { _selectMode = true; _selected.add(doc.id); }),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Container(color: surfaceColor, child: thumb.isNotEmpty? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover) : const Icon(Iconsax.video, color: Colors.white24)),
                                          if (isSel) Container(color: Colors.teal.withValues(alpha:0.5), child: const Icon(Icons.check_circle, color: Colors.white)),
                                          Positioned(
                                            bottom: 4, left: 4, right: 4,
                                            child: Row(children: [
                                              const Icon(Icons.play_arrow, color: Colors.white, size: 12),
                                              const SizedBox(width: 2),
                                              Text(_formatViews(views), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ]),
                                          ),
                                        ],
                                      ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        );
                      }),
          ),
        ],
      ),
    );
  }
}
