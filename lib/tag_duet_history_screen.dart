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
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

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

  static const _pageSize = 30;
  static const _deadline = Duration(seconds: 15);
  static const _server = GetOptions(source: Source.server);
  final _store = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _scrollController = ScrollController();
  final _activities = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  final _users = <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};
  final _posts = <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};
  final _ownerAccess = <String, Stream<bool>>{};
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _recentSub;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  String? _undatedCursor;
  String? _uid;
  int _generation = 0;
  bool _loading = true;
  bool _hasMore = false;
  bool _failed = false;
  bool _liveFailed = false;
  bool _loadingUndated = false;
  bool _hasUndatedPages = false;
  bool _undatedFailed = false;
  bool _opening = false;

  Query<Map<String, dynamic>> _activitiesFor(String uid) => _store
      .collection('activities')
      .where('toUid', isEqualTo: uid)
      .where('type', whereIn: ['mention', 'duet']);

  Query<Map<String, dynamic>> _byTime(String uid) =>
      _activitiesFor(uid).orderBy('timestamp', descending: true);

  bool _current(String uid, int generation) =>
      mounted &&
      uid == _uid &&
      uid == _auth.currentUser?.uid &&
      generation == _generation;

  @override
  void initState() {
    super.initState();
    final viewer = _auth.currentUser?.uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _auth.currentUser?.uid == viewer) {
        BannerManager.instance.clearTypes({BannerType.mention});
      }
    });
    _authSub = _auth.authStateChanges().listen((user) {
      if (!mounted) return;
      _uid = user?.uid;
      unawaited(_reset());
    });
    _scrollController.addListener(() {
      if (_scrollController.position.extentAfter < 400 && !_failed) {
        unawaited(_fetchMore());
      }
    });
  }

  Future<void> _reset() async {
    _recentSub?.cancel();
    _recentSub = null;
    setState(() {
      _generation++;
      _activities.clear();
      _users.clear();
      _posts.clear();
      _ownerAccess.clear();
      _cursor = null;
      _undatedCursor = null;
      _loading = false;
      _hasMore = _uid != null;
      _failed = false;
      _liveFailed = false;
      _loadingUndated = false;
      _hasUndatedPages = _uid != null;
      _undatedFailed = false;
      _opening = false;
    });
    final first = _fetchMore();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await first;
  }

  Future<void> _fetchMore() async {
    final uid = _uid;
    final generation = _generation;
    if (uid == null || !_current(uid, generation) || _loading || !_hasMore) {
      return;
    }
    final cursor = _cursor;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      var query = _byTime(uid);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query
          .limit(_pageSize + 1)
          .get(_server)
          .timeout(_deadline);
      if (!_current(uid, generation)) return;
      setState(() {
        for (final doc in page.docs.take(_pageSize)) {
          _activities[doc.id] = doc;
          _cursor = doc;
        }
        _hasMore = page.docs.length > _pageSize;
        _loading = false;
      });
      if (cursor == null) {
        _watchRecent(uid, generation, _cursor);
        unawaited(_fetchUndated());
      }
    } catch (error) {
      if (!_current(uid, generation)) return;
      debugPrint('Tag history page failed: $error');
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _watchRecent(
    String uid,
    int generation,
    QueryDocumentSnapshot<Map<String, dynamic>>? firstPageEnd,
  ) {
    final query = _byTime(uid);
    // Keep the first page's boundary fixed so new activities cannot push an
    // unpaged activity out of both the live results and the older pages.
    final recent = firstPageEnd == null
        ? query.limit(1)
        : query.endAtDocument(firstPageEnd);
    final liveIds = firstPageEnd == null
        ? <String>{}
        : _activities.keys.toSet();
    _recentSub = recent
        .snapshots(includeMetadataChanges: true)
        .listen(
          (page) {
            if (!_current(uid, generation) ||
                page.metadata.isFromCache ||
                page.metadata.hasPendingWrites) {
              return;
            }
            if (firstPageEnd == null) {
              if (page.docs.isNotEmpty) unawaited(_reset());
              return;
            }
            final ids = page.docs.map((doc) => doc.id).toSet();
            setState(() {
              for (final id in liveIds.difference(ids)) {
                _activities.remove(id);
              }
              for (final doc in page.docs) {
                _activities[doc.id] = doc;
              }
              liveIds
                ..clear()
                ..addAll(ids);
            });
          },
          onError: (Object _) {
            if (_current(uid, generation)) setState(() => _liveFailed = true);
          },
          cancelOnError: true,
        );
  }

  Future<void> _fetchUndated() async {
    final uid = _uid;
    final generation = _generation;
    if (uid == null ||
        !_current(uid, generation) ||
        _loadingUndated ||
        !_hasUndatedPages) {
      return;
    }
    setState(() {
      _loadingUndated = true;
      _undatedFailed = false;
    });
    try {
      // Ordering by timestamp excludes documents that lack the field.
      var query = _activitiesFor(uid).orderBy(FieldPath.documentId);
      final cursor = _undatedCursor;
      if (cursor != null) query = query.startAfter([cursor]);
      final page = await query
          .limit(_pageSize + 1)
          .get(_server)
          .timeout(_deadline);
      if (!_current(uid, generation)) return;
      setState(() {
        for (final doc in page.docs.take(_pageSize)) {
          _undatedCursor = doc.id;
          if (_dateOf(doc.data()) == null) {
            _activities.putIfAbsent(doc.id, () => doc);
          }
        }
        _hasUndatedPages = page.docs.length > _pageSize;
        _loadingUndated = false;
      });
    } catch (error) {
      if (!_current(uid, generation)) return;
      debugPrint('Tag history undated page failed: $error');
      setState(() {
        _loadingUndated = false;
        _undatedFailed = true;
      });
    }
  }

  DateTime? _dateOf(Map<String, dynamic> data) {
    final stamp = data['timestamp'];
    return stamp is Timestamp ? stamp.toDate().toLocal() : null;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _readUser(String uid) =>
      _users.putIfAbsent(
        uid,
        () => UserDocuments.readable(_store, uid).get().timeout(_deadline),
      );

  Future<DocumentSnapshot<Map<String, dynamic>>> _readPost(
    String uid,
    String postId,
  ) {
    final generation = _generation;
    return _posts.putIfAbsent(postId, () async {
      final post = await _store
          .collection('posts')
          .doc(postId)
          .get(_server)
          .timeout(_deadline);
      if (_current(uid, generation) &&
          post.exists &&
          !post.metadata.hasPendingWrites &&
          post.data()?['isDeleted'] != true) {
        await AudienceAccess.instance.verifyPost(postId).timeout(_deadline);
      }
      return post;
    });
  }

  bool _blocked(custom.AuthProvider auth, String uid) =>
      auth.blockedUsersSet.contains(uid) || auth.blockedBySet.contains(uid);

  DocumentReference<Map<String, dynamic>> _following(
    String uid,
    String owner,
  ) => _store.collection('users').doc(uid).collection('following').doc(owner);

  Stream<bool> _watchOwner(String uid, String owner) => Stream.multi((output) {
    if (uid == owner || owner.isEmpty) {
      output.add(uid == owner);
      unawaited(output.close());
      return;
    }
    bool? private;
    bool? follows;
    final deadline = Timer(_deadline, () => output.add(false));
    void publish() {
      if (private == false || (private == true && follows != null)) {
        deadline.cancel();
      }
      if (private == false) output.add(true);
      if (private == true && follows != null) output.add(follows!);
    }

    final profile = UserDocuments.readable(_store, owner)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (doc) {
            if (doc.metadata.isFromCache || doc.metadata.hasPendingWrites) {
              return;
            }
            if (!doc.exists) {
              private = null;
              output.add(false);
              return;
            }
            private = doc.data()?['isPrivate'] == true;
            publish();
          },
          onError: (Object _) {
            private = null;
            output.add(false);
          },
        );
    final following = _following(uid, owner)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (doc) {
            if (doc.metadata.isFromCache || doc.metadata.hasPendingWrites) {
              return;
            }
            follows = doc.exists;
            publish();
          },
          onError: (Object _) {
            follows = false;
            publish();
          },
        );
    output.onCancel = () async {
      deadline.cancel();
      await Future.wait([profile.cancel(), following.cancel()]);
    };
  });

  Future<void> _openVideo(String uid, String postId, String sender) async {
    final generation = _generation;
    if (_opening || !_current(uid, generation)) return;
    _opening = true;
    final auth = context.read<custom.AuthProvider>();
    try {
      final post = await _store
          .collection('posts')
          .doc(postId)
          .get(_server)
          .timeout(_deadline);
      if (!_current(uid, generation)) return;
      final data = post.data();
      final owner = data?['uid']?.toString() ?? '';
      var allowed =
          data != null &&
          !post.metadata.hasPendingWrites &&
          data['isDeleted'] != true &&
          owner.isNotEmpty &&
          !_blocked(auth, owner) &&
          !_blocked(auth, sender) &&
          await AudienceAccess.instance.verifyPost(postId).timeout(_deadline);
      if (!_current(uid, generation)) return;
      if (allowed && uid != owner) {
        final profile = await UserDocuments.readable(
          _store,
          owner,
        ).get(_server).timeout(_deadline);
        allowed = profile.exists && !profile.metadata.hasPendingWrites;
        if (allowed && profile.data()?['isPrivate'] == true) {
          if (!_current(uid, generation)) return;
          final following = await _following(
            uid,
            owner,
          ).get(_server).timeout(_deadline);
          allowed = following.exists && !following.metadata.hasPendingWrites;
        }
      }
      if (!_current(uid, generation)) return;
      if (!allowed || _blocked(auth, owner) || _blocked(auth, sender)) {
        _message('الفيديو غير متاح');
        return;
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      try {
        await TitiSingleEngine().lock();
        await TitiProfileEngine().unlock();
      } catch (_) {
        // The player manages its engine when it enters the route.
      }
      if (!_current(uid, generation) ||
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
        ),
      );
      final done = navigator.push(route);
      final account = _auth.authStateChanges().listen((user) {
        if (user?.uid != uid && route.isActive) navigator.removeRoute(route);
      });
      try {
        await done;
      } finally {
        unawaited(account.cancel());
        if (_current(uid, generation)) {
          try {
            await TitiProfileEngine().unlock();
            await TitiSingleEngine().lock();
          } catch (_) {
            // Engine cleanup must not prevent reopening the same activity.
          }
        }
      }
    } catch (_) {
      if (_current(uid, generation)) _message('تعذّر فتح الفيديو');
    } finally {
      if (_current(uid, generation)) _opening = false;
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  String _formatDateHeader(DateTime d) {
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
    return "${d.day} ${months[d.month - 1]} ${d.year}";
  }

  String _formatTime(DateTime? date, DateTime now) {
    if (date == null) return 'تاريخ غير معروف';
    final diff = now.difference(date);
    if (diff.isNegative) return _formatDateHeader(date);
    if (diff.inSeconds < 60) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
    return _formatDateHeader(date);
  }

  @override
  void dispose() {
    _recentSub?.cancel();
    _authSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<custom.AuthProvider>();
    final uid = _uid;
    final docs = uid != null && uid == _auth.currentUser?.uid
        ? _activities.values.toList()
        : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    docs.sort((a, b) {
      final left = _dateOf(a.data());
      final right = _dateOf(b.data());
      if (left == null && right != null) return 1;
      if (left != null && right == null) return -1;
      final time = left == null || right == null ? 0 : right.compareTo(left);
      return time != 0 ? time : b.id.compareTo(a.id);
    });
    final grouped =
        <DateTime?, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final date = _dateOf(doc.data());
      final day = date == null
          ? null
          : DateTime(date.year, date.month, date.day);
      grouped.putIfAbsent(day, () => []).add(doc);
    }
    final now = DateTime.now();

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
          "سجل الذكر",
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reset,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_liveFailed)
              SliverToBoxAdapter(
                child: _action('تعذّر تحديث سجل الذكر. أعد المحاولة', _reset),
              ),
            for (final group in grouped.entries) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 22,
                    bottom: 8,
                  ),
                  child: Text(
                    group.key == null
                        ? 'تاريخ غير معروف'
                        : _formatDateHeader(group.key!),
                    style: TextStyle(
                      color: titiTeal.withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: group.value.length,
                itemBuilder: (_, index) =>
                    _tile(uid!, auth, group.value[index], now),
              ),
            ],
            if (docs.isEmpty &&
                !_failed &&
                !_hasMore &&
                !_loading &&
                !_loadingUndated &&
                !_hasUndatedPages)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Iconsax.user_tag,
                      size: 70,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'سجل الذكر فارغ',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            if (_loading || _loadingUndated)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: titiTeal,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
            if (!_loading && _hasMore)
              SliverToBoxAdapter(
                child: _action(
                  _failed
                      ? 'تعذّر تحميل سجل الذكر. أعد المحاولة'
                      : 'تحميل المزيد',
                  _fetchMore,
                ),
              ),
            if (!_loadingUndated && _hasUndatedPages && !_failed && !_loading)
              SliverToBoxAdapter(
                child: _action(
                  _undatedFailed
                      ? 'تعذّر البحث عن الأنشطة بلا تاريخ. أعد المحاولة'
                      : 'البحث عن المزيد من الأنشطة بلا تاريخ',
                  _fetchUndated,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _action(String text, VoidCallback action) => Center(
    child: TextButton(onPressed: action, child: Text(text)),
  );

  Widget _placeholder(String text, {VoidCallback? retry}) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(12),
    ),
    child: retry == null
        ? Text(text, style: const TextStyle(color: Colors.white54))
        : _action(text, retry),
  );

  Widget _tile(
    String uid,
    custom.AuthProvider auth,
    QueryDocumentSnapshot<Map<String, dynamic>> activity,
    DateTime now,
  ) {
    final data = activity.data();
    final sender = data['fromUid']?.toString() ?? '';
    final postId = data['postId']?.toString() ?? '';
    final isDuet = data['type'] == 'duet';
    final isComment = data['commentId']?.toString().isNotEmpty == true;
    final textType = isDuet
        ? 'عمل ديو مع فيديو لك'
        : isComment
        ? 'ذكرك في تعليق'
        : 'ذكرك في وصف فيديو';
    final time = _formatTime(_dateOf(data), now);
    if (postId.isEmpty || postId.contains('/') || _blocked(auth, sender)) {
      return _placeholder('الفيديو غير متاح');
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      key: ValueKey((_generation, activity.id)),
      future: _readPost(uid, postId),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _placeholder('جاري التحقق من الفيديو');
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is FirebaseException && error.code == 'permission-denied') {
            return _placeholder('الفيديو غير متاح');
          }
          return _placeholder(
            'تعذّر التحقق من الفيديو. أعد المحاولة',
            retry: () => setState(() => _posts.remove(postId)),
          );
        }
        final post = snapshot.data?.data();
        final owner = post?['uid']?.toString() ?? '';
        if (post == null ||
            snapshot.data!.metadata.hasPendingWrites ||
            post['isDeleted'] == true ||
            owner.isEmpty ||
            owner.contains('/') ||
            _blocked(auth, owner)) {
          return _placeholder('الفيديو غير متاح');
        }
        final audience = AudienceAccess.instance;
        return ListenableBuilder(
          listenable: audience,
          builder: (_, _) {
            if (!audience.canViewPost(post, postId: postId)) {
              return _placeholder('الفيديو غير متاح');
            }
            return StreamBuilder<bool>(
              stream: _ownerAccess.putIfAbsent(
                owner,
                () => _watchOwner(uid, owner),
              ),
              builder: (_, access) {
                if (!access.hasData) {
                  return _placeholder('جاري التحقق من الفيديو');
                }
                if (access.data != true) {
                  return _placeholder('الفيديو غير متاح');
                }
                return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: sender.isEmpty || sender.contains('/')
                      ? null
                      : _readUser(sender),
                  builder: (_, user) {
                    final profile = user.data?.data();
                    final fullName =
                        (profile?['fullName'] ??
                                profile?['username'] ??
                                'مستخدم')
                            .toString();
                    final profileImg = profile?['profileImg']?.toString() ?? '';
                    final thumb = post['thumbnailUrl']?.toString() ?? '';
                    return InkWell(
                      onTap: () => _openVideo(uid, postId, sender),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
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
                                    : const Icon(
                                        Iconsax.video,
                                        color: Colors.white24,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
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
                                            ? CachedNetworkImageProvider(
                                                profileImg,
                                              )
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
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        isDuet
                                            ? Iconsax.repeat
                                            : Iconsax.user_tag,
                                        size: 14,
                                        color: titiTeal,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          textType,
                                          style: TextStyle(
                                            color: titiTeal,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    time,
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
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
