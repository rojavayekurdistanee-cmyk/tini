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

  static const _pageSize = 30;
  static const _deadline = Duration(seconds: 15);
  static const _server = GetOptions(source: Source.server);

  final _store = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _comments = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  final _postReads = <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};
  final _parentReads =
      <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};
  final _scrollController = ScrollController();
  StreamSubscription<User?>? _authSub;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  String? _uid;
  int _generation = 0;
  bool _loading = true;
  bool _hasMore = false;
  bool _newestFirst = true;
  bool _opening = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _authSub = _auth.authStateChanges().listen((user) {
      if (!mounted) return;
      _uid = user?.uid;
      unawaited(_reset());
    });
    _scrollController.addListener(() {
      if (_scrollController.position.extentAfter < 400 && _loadError == null) {
        unawaited(_fetchPage());
      }
    });
  }

  bool _isCurrent(String uid, int generation) =>
      mounted &&
      _uid == uid &&
      _auth.currentUser?.uid == uid &&
      _generation == generation;

  Future<void> _reset() async {
    setState(() {
      _generation++;
      _comments.clear();
      _postReads.clear();
      _parentReads.clear();
      _cursor = null;
      _loading = false;
      _hasMore = _uid != null;
      _opening = false;
      _loadError = null;
    });
    final firstPage = _fetchPage();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await firstPage;
  }

  Future<void> _fetchPage() async {
    final uid = _uid;
    final generation = _generation;
    if (uid == null || !_isCurrent(uid, generation) || _loading || !_hasMore) {
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      var query = _store
          .collectionGroup('comments')
          .where('uid', isEqualTo: uid)
          .orderBy('timestamp', descending: _newestFirst);
      final cursor = _cursor;
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query
          .limit(_pageSize + 1)
          .get(_server)
          .timeout(_deadline);
      if (!_isCurrent(uid, generation)) return;
      final visible = page.docs.take(_pageSize);
      setState(() {
        for (final doc in visible) {
          _comments[doc.reference.path] = doc;
          _cursor = doc;
        }
        _hasMore = page.docs.length > _pageSize;
        _loading = false;
      });
    } catch (error) {
      if (!_isCurrent(uid, generation)) return;
      debugPrint('CommentsHistory: $error');
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  String get _loadErrorMessage {
    final error = _loadError;
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'تعذّر تحميل سجل التعليقات بسبب صلاحيات القراءة';
    }
    return 'تعذّر تحميل سجل التعليقات';
  }

  void _setOrder(bool newestFirst) {
    Navigator.pop(context);
    if (_newestFirst == newestFirst) return;
    _newestFirst = newestFirst;
    unawaited(_reset());
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'ترتيب حسب',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            title: const Text(
              'الأحدث للأقدم',
              style: TextStyle(color: Colors.white),
            ),
            trailing: _newestFirst
                ? Icon(Icons.check_circle, color: titiTeal)
                : const Icon(Icons.circle_outlined, color: Colors.white24),
            onTap: () => _setOrder(true),
          ),
          ListTile(
            title: const Text(
              'من الأقدم إلى الأحدث',
              style: TextStyle(color: Colors.white),
            ),
            trailing: !_newestFirst
                ? Icon(Icons.check_circle, color: titiTeal)
                : const Icon(Icons.circle_outlined, color: Colors.white24),
            onTap: () => _setOrder(false),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return "${d.day} ${months[d.month - 1]}";
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _readPost(String postId) =>
      _postReads.putIfAbsent(
        postId,
        () => _store.collection('posts').doc(postId).get().timeout(_deadline),
      );

  Future<DocumentSnapshot<Map<String, dynamic>>> _readParent(
    DocumentReference<Map<String, dynamic>> reference,
  ) => _parentReads.putIfAbsent(
    reference.path,
    () => reference.get().timeout(_deadline),
  );

  Future<void> _openComment(String postId, String commentId) async {
    final uid = _uid;
    final generation = _generation;
    if (uid == null || !_isCurrent(uid, generation) || _opening) return;
    _opening = true;
    try {
      final post = await _store
          .collection('posts')
          .doc(postId)
          .get(_server)
          .timeout(_deadline);
      if (!_isCurrent(uid, generation)) return;
      final playable =
          post.exists &&
          post.data()?['isDeleted'] != true &&
          await AudienceAccess.instance.verifyPost(postId).timeout(_deadline);
      if (!_isCurrent(uid, generation)) return;
      if (!playable) {
        _message('هذا الفيديو غير متاح');
        return;
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      try {
        await TitiSingleEngine().lock();
        await TitiProfileEngine().unlock();
      } catch (_) {
        // The player also manages its own engine when entering the route.
      }
      if (!_isCurrent(uid, generation) ||
          !mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final navigator = Navigator.of(context);
      final route = MaterialPageRoute<void>(
        builder: (_) => PostViewScreen(
          posts: [post],
          initialIndex: 0,
          isFromProfileGrid: true,
          openComments: true,
          highlightCommentId: commentId,
        ),
      );
      final closed = navigator.push(route);
      final account = _auth.authStateChanges().listen((user) {
        if (user?.uid != uid && route.isActive) navigator.removeRoute(route);
      });
      try {
        await closed;
      } finally {
        unawaited(account.cancel());
        if (_isCurrent(uid, generation)) {
          try {
            await TitiProfileEngine().unlock();
            await TitiSingleEngine().lock();
          } catch (_) {
            // Engine cleanup must not prevent refreshing the history.
          }
        }
      }
      if (_isCurrent(uid, generation)) await _reset();
    } catch (_) {
      if (_isCurrent(uid, generation)) _message('تعذّر فتح التعليق');
    } finally {
      if (_isCurrent(uid, generation)) _opening = false;
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Widget _pageStatus() => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: _loading
          ? CircularProgressIndicator(color: titiTeal, strokeWidth: 2)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loadError != null)
                  Text(
                    _loadErrorMessage,
                    style: const TextStyle(color: Colors.white70),
                  ),
                TextButton(
                  onPressed: _fetchPage,
                  child: Text(
                    _loadError == null ? 'تحميل المزيد' : 'أعد المحاولة',
                  ),
                ),
              ],
            ),
    ),
  );

  @override
  void dispose() {
    _authSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comments = _uid == _auth.currentUser?.uid
        ? _comments.values.toList()
        : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "سجل التعليقات",
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _newestFirst ? 'الأحدث للأقدم' : 'من الأقدم إلى الأحدث',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Iconsax.arrow_down_1,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reset,
              child: comments.isEmpty
                  ? CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: _loading || _loadError != null || _hasMore
                                ? _pageStatus()
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Iconsax.message,
                                        size: 70,
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'لا يوجد تعليقات',
                                        style: TextStyle(color: Colors.white54),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount:
                          comments.length +
                          (_loading || _hasMore || _loadError != null ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == comments.length) return _pageStatus();
                        return _commentTile(comments[index]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final commentText = data['text'] ?? '';
    final collection = doc.reference.parent;
    final post = collection.parent;
    if (post == null || post.parent.path != 'posts') {
      return const SizedBox.shrink();
    }
    final postId = post.id;
    final parentId = data['parentId'] as String?;
    final ts = data['timestamp'] as Timestamp?;
    // الأسماء الحقيقية من UserModel + PostCommentsSheet
    final String fullName = data['fullName'] ?? data['userName'] ?? 'أنت';
    final String profileImg = data['profileImg'] ?? data['userImage'] ?? '';

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      key: ValueKey((_generation, doc.reference.path)),
      future: _readPost(postId),
      builder: (context, postSnap) {
        if (postSnap.hasError) {
          return TextButton(
            onPressed: () => setState(() => _postReads.remove(postId)),
            child: const Text('تعذّر تحميل الفيديو. أعد المحاولة'),
          );
        }
        final postData = postSnap.data?.data();
        if (postData == null || postData['isDeleted'] == true) {
          return const SizedBox.shrink();
        }
        final thumb = postData['thumbnailUrl']?.toString() ?? '';

        return AudiencePostGate(
          post: postData,
          postId: postId,
          child: InkWell(
            onTap: () => _openComment(postId, doc.id),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // اقصى اليسار: صورة الفيديو
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 55,
                      height: 75,
                      color: bgColor,
                      child: thumb.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                            )
                          : const Icon(Iconsax.video, color: Colors.white24),
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
                              child: Text(
                                fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: bgColor,
                              backgroundImage: profileImg.isNotEmpty
                                  ? CachedNetworkImageProvider(profileImg)
                                  : null,
                              child: profileImg.isEmpty
                                  ? Text(
                                      fullName.isNotEmpty
                                          ? fullName[0].toUpperCase()
                                          : "?",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (parentId != null &&
                            parentId.isNotEmpty &&
                            !parentId.contains('/'))
                          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            future: _readParent(collection.doc(parentId)),
                            builder: (context, parentSnap) {
                              if (parentSnap.hasError) {
                                return TextButton(
                                  onPressed: () => setState(
                                    () => _parentReads.remove(
                                      collection.doc(parentId).path,
                                    ),
                                  ),
                                  child: const Text(
                                    'تعذّر تحميل التعليق الأصلي. أعد المحاولة',
                                  ),
                                );
                              }
                              final parent = parentSnap.data?.data();
                              if (parent == null) {
                                return const Text(
                                  "رد على تعليق",
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                );
                              }
                              final parentName =
                                  parent['fullName'] ??
                                  parent['userName'] ??
                                  'مستخدم';
                              final parentText = parent['text'] ?? '';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  "رددت على @${parentName}: ${parentText}",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                              );
                            },
                          ),
                        // تحتهم: التعليق
                        Text(
                          commentText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatDate(ts),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white10,
                    size: 12,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
