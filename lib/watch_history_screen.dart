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
import 'user_documents.dart';

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
  final _selected = <String>{};

  static const _pageSize = 30;
  static const _server = GetOptions(source: Source.server);
  final _store = FirebaseFirestore.instance;
  final _firebaseAuth = FirebaseAuth.instance;
  final _documents = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  final _deletingIds = <String>{};
  final _deletedIds = <String, Timestamp?>{};
  final _ownerAccess = <String, Stream<bool>>{};
  final _scrollController = ScrollController();
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _recentSub;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  String? _uid;
  int _generation = 0;
  late DateTime _queryDay;
  bool _loading = true;
  bool _failed = false;
  bool _hasMore = false;
  bool _deleting = false;
  bool _opening = false;

  DateTime? _getDate(Map<String, dynamic> data) {
    final timestamp = data['watchedAt'];
    return timestamp is Timestamp ? timestamp.toDate() : null;
  }

  DateTime _day(DateTime date, [int offset = 0]) =>
      DateTime(date.year, date.month, date.day + offset);

  String _groupLabel(DateTime? date, DateTime today) {
    if (date == null) return 'أقدم';
    if (!date.isBefore(today)) return 'اليوم';
    if (!date.isBefore(_day(today, -1))) return 'أمس';
    if (!date.isBefore(_day(today, -6))) return 'هذا الأسبوع';
    if (!date.isBefore(_day(today, -29))) return 'هذا الشهر';
    return 'أقدم';
  }

  Query<Map<String, dynamic>> _query(String uid) {
    Query<Map<String, dynamic>> query = _history(
      uid,
    ).orderBy('watchedAt', descending: true);
    final today = _queryDay;
    final start = switch (_filter) {
      'اليوم' => today,
      'أمس' => _day(today, -1),
      '7 أيام' => _day(today, -6),
      '30 يوم' => _day(today, -29),
      _ => null,
    };
    if (start != null) {
      final end = _filter == 'أمس' ? today : _day(today, 1);
      query = query
          .where('watchedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('watchedAt', isLessThan: Timestamp.fromDate(end));
    }
    return query;
  }

  CollectionReference<Map<String, dynamic>> _history(String uid) =>
      _store.collection('users').doc(uid).collection('watchHistory');

  bool _current(String uid, int generation) =>
      mounted &&
      _uid == uid &&
      _firebaseAuth.currentUser?.uid == uid &&
      _generation == generation;

  String _formatViews(dynamic v) {
    int c = 0;
    if (v is int) c = v;
    if (v is String) c = int.tryParse(v) ?? 0;
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(1)}M';
    if (c >= 1000) return '${(c / 1000).toStringAsFixed(1)}K';
    return c.toString();
  }

  @override
  void initState() {
    super.initState();
    _authSub = _firebaseAuth.authStateChanges().listen((user) {
      if (!mounted) return;
      _uid = user?.uid;
      _ownerAccess.clear();
      _deleting = false;
      _opening = false;
      _reset();
    });
    _scrollController.addListener(() {
      if (_scrollController.position.extentAfter < 400 && !_failed) {
        unawaited(_fetchMore());
      }
    });
  }

  Future<void> _reset() async {
    final uid = _uid;
    _recentSub?.cancel();
    _recentSub = null;
    setState(() {
      _generation++;
      _queryDay = _day(DateTime.now());
      _documents.clear();
      _deletingIds.clear();
      _deletedIds.clear();
      _selected.clear();
      _selectMode = false;
      _cursor = null;
      _loading = false;
      _failed = false;
      _hasMore = uid != null;
    });
    final firstPage = _fetchMore();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await firstPage;
  }

  Future<void> _fetchMore() async {
    final uid = _uid;
    final generation = _generation;
    if (uid == null || !_current(uid, generation) || _loading || !_hasMore) {
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      var query = _query(uid);
      final cursor = _cursor;
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query
          .limit(_pageSize)
          .get(_server)
          .timeout(const Duration(seconds: 15));
      if (!_current(uid, generation)) return;
      setState(() {
        _mergePage(page.docs);
        if (page.docs.isNotEmpty) _cursor = page.docs.last;
        _hasMore = page.docs.length == _pageSize;
        _loading = false;
      });
      if (cursor == null) {
        final latest = page.docs.isEmpty
            ? null
            : page.docs.first.data()['watchedAt'];
        _listenForRecent(uid, generation, latest is Timestamp ? latest : null);
      }
    } catch (_) {
      if (!_current(uid, generation)) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _listenForRecent(String uid, int generation, Timestamp? latest) {
    // New watches and replays can move a row ahead of an older page's cursor.
    // Observe that range separately, without reopening queries for older pages.
    final query = _query(uid);
    final recent = latest == null
        ? query.limit(_pageSize)
        : query.where('watchedAt', isGreaterThanOrEqualTo: latest);
    final liveIds = <String>{};
    _recentSub = recent
        .snapshots(includeMetadataChanges: true)
        .listen(
          (page) {
            if (!_current(uid, generation) ||
                page.metadata.isFromCache ||
                page.metadata.hasPendingWrites) {
              return;
            }
            final ids = page.docs.map((doc) => doc.id).toSet();
            setState(() {
              if (latest != null) {
                for (final id in liveIds.difference(ids)) {
                  _documents.remove(id);
                  _selected.remove(id);
                }
              }
              for (final doc in page.docs) {
                if (!_deletedIds.containsKey(doc.id)) continue;
                final deletedAt = _deletedIds[doc.id];
                final watchedAt = doc.data()['watchedAt'];
                if (deletedAt == null ||
                    (watchedAt is Timestamp &&
                        watchedAt.compareTo(deletedAt) > 0)) {
                  _deletedIds.remove(doc.id);
                }
              }
              _mergePage(page.docs);
              liveIds
                ..clear()
                ..addAll(ids);
              if (_cursor == null && page.docs.isNotEmpty) {
                _cursor = page.docs.last;
                _hasMore = page.docs.length == _pageSize;
              }
            });
          },
          onError: (Object _) {
            if (!_current(uid, generation)) return;
            _recentSub = null;
          },
          cancelOnError: true,
        );
  }

  void _mergePage(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    for (final doc in docs) {
      if (_deletingIds.contains(doc.id) || _deletedIds.containsKey(doc.id)) {
        continue;
      }
      final old = _documents[doc.id];
      final previous = old == null ? null : _getDate(old.data());
      final updated = _getDate(doc.data());
      if (previous == null ||
          (updated != null && !updated.isBefore(previous))) {
        _documents[doc.id] = doc;
      }
    }
  }

  Future<void> _refreshHead(String uid, int generation) async {
    if (_filter == 'أمس' || _queryDay != _day(DateTime.now())) {
      await _reset();
      return;
    }
    if (_recentSub != null) return;
    try {
      final page = await _query(
        uid,
      ).limit(_pageSize).get(_server).timeout(const Duration(seconds: 15));
      if (_current(uid, generation)) setState(() => _mergePage(page.docs));
    } catch (_) {
      if (_current(uid, generation)) {
        _message('تعذّر تحديث سجل المشاهدة. اسحب لإعادة المحاولة');
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteSelected() async {
    final uid = _uid;
    final generation = _generation;
    if (uid == null ||
        !_current(uid, generation) ||
        _deleting ||
        _selected.isEmpty) {
      return;
    }
    final ids = _selected.toList();
    setState(() {
      _deleting = true;
      _deletingIds.addAll(ids);
    });
    var deleted = 0;
    try {
      while (deleted < ids.length && _current(uid, generation)) {
        final chunk = ids.skip(deleted).take(500).toList();
        // A transaction fails offline instead of queuing an unconfirmed deletion.
        await _store.runTransaction<void>((transaction) async {
          if (!_current(uid, generation)) throw StateError('Account changed');
          for (final id in chunk) {
            transaction.delete(_history(uid).doc(id));
          }
        }, timeout: const Duration(seconds: 15));
        if (!_current(uid, generation)) return;
        deleted += chunk.length;
        setState(() {
          for (final id in chunk) {
            final timestamp = _documents.remove(id)?.data()['watchedAt'];
            _deletedIds[id] = timestamp is Timestamp ? timestamp : null;
            _selected.remove(id);
          }
        });
      }
      if (!_current(uid, generation)) return;
      setState(() => _selectMode = false);
      _message('تم حذف العناصر المحددة من السجل');
    } catch (_) {
      if (_current(uid, generation)) {
        _message(
          deleted == 0
              ? 'تعذّر الحذف. حاول مرة أخرى'
              : 'تم حذف $deleted من العناصر. حاول حذف البقية مرة أخرى',
        );
      }
    } finally {
      if (_current(uid, generation)) {
        setState(() {
          _deletingIds.clear();
          _deleting = false;
        });
      }
    }
  }

  String _postId(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      (doc.data()['postId'] ?? doc.id).toString();

  bool _blocked(custom.AuthProvider auth, String owner) =>
      auth.blockedUsersSet.contains(owner) || auth.blockedBySet.contains(owner);

  bool _verified(DocumentSnapshot<Map<String, dynamic>> doc) =>
      !doc.metadata.isFromCache && !doc.metadata.hasPendingWrites;

  Stream<bool> _watchOwnerAccess(String uid, String owner) {
    if (uid == owner) return Stream.value(true);
    if (owner.isEmpty) return Stream.value(false);
    // Both streams reflect current data, including an unfollow while the grid is open.
    return Stream.multi((controller) {
      bool? isPrivate;
      bool? follows;
      void emit() {
        if (isPrivate == false) controller.add(true);
        if (isPrivate == true && follows != null) controller.add(follows!);
      }

      final profile = UserDocuments.readable(_store, owner)
          .snapshots(includeMetadataChanges: true)
          .listen(
            (doc) {
              final data = doc.data();
              if (!_verified(doc)) return;
              if (data == null) {
                controller.add(false);
              } else {
                isPrivate = data['isPrivate'] == true;
                emit();
              }
            },
            onError: (Object _) {
              isPrivate = null;
              controller.add(false);
            },
          );
      final following = _store
          .collection('users')
          .doc(uid)
          .collection('following')
          .doc(owner)
          .snapshots(includeMetadataChanges: true)
          .listen(
            (doc) {
              if (!_verified(doc)) return;
              follows = doc.exists;
              emit();
            },
            onError: (Object _) {
              follows = false;
              emit();
            },
          );
      controller.onCancel = () async {
        await Future.wait([profile.cancel(), following.cancel()]);
      };
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _readPlayable(
    String postId,
    String uid,
    int generation,
    custom.AuthProvider auth,
  ) async {
    if (!_current(uid, generation)) return null;
    final post = await _store.collection('posts').doc(postId).get(_server);
    final data = post.data();
    final owner = data?['uid']?.toString() ?? '';
    if (!_current(uid, generation) ||
        !_verified(post) ||
        data == null ||
        data['isDeleted'] == true ||
        owner.isEmpty ||
        _blocked(auth, owner)) {
      return null;
    }
    final verified = await AudienceAccess.instance.verifyPost(postId);
    if (!verified || !_current(uid, generation)) return null;
    if (owner != uid) {
      final profile = await UserDocuments.readable(_store, owner).get(_server);
      if (!_current(uid, generation) ||
          !_verified(profile) ||
          !profile.exists) {
        return null;
      }
      if (profile.data()?['isPrivate'] == true) {
        final following = await _store
            .collection('users')
            .doc(uid)
            .collection('following')
            .doc(owner)
            .get(_server);
        if (!_verified(following) || !following.exists) return null;
      }
      final user = _store.collection('users').doc(uid);
      final blocks = await Future.wait([
        user.collection('blocked').doc(owner).get(_server),
        user.collection('blockedBy').doc(owner).get(_server),
      ]);
      if (blocks.any((doc) => !_verified(doc) || doc.exists)) return null;
    }
    return _current(uid, generation) &&
            !_blocked(auth, owner) &&
            AudienceAccess.instance.canViewPost(data, postId: postId)
        ? post
        : null;
  }

  Future<void> _openVideo(String uid, String postId, List<String> ids) async {
    final generation = _generation;
    if (_opening || !_current(uid, generation)) return;
    final auth = context.read<custom.AuthProvider>();
    _opening = true;
    var opened = false;
    try {
      final selected = await _readPlayable(
        postId,
        uid,
        generation,
        auth,
      ).timeout(const Duration(seconds: 15));
      if (!_current(uid, generation)) return;
      if (selected == null) {
        _message('هذا الفيديو غير متاح');
        return;
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final navigation = Navigator.of(context);
      await TitiSingleEngine().lock();
      await TitiProfileEngine().unlock();
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          !_current(uid, generation)) {
        return;
      }

      final posts = ValueNotifier<List<DocumentSnapshot>>([selected]);
      final position = ids.indexOf(postId);
      var before = position - 1;
      var after = position + 1;
      var activeId = postId;
      var loadingBefore = false;
      var loadingAfter = false;
      var routeOpen = true;
      var activeOwner = '';
      StreamSubscription<bool>? playingOwnerAccess;
      StreamSubscription<DocumentSnapshot>? playingPost;
      late final MaterialPageRoute<void> route;

      void closeUnavailable(String watched) {
        if (activeId != watched || !routeOpen || !route.isActive) return;
        routeOpen = false;
        navigation.removeRoute(route);
        if (_current(uid, generation)) _message('هذا الفيديو غير متاح');
      }

      void checkActiveBlock() {
        if (_blocked(auth, activeOwner)) closeUnavailable(activeId);
      }

      void watchPlayingPost(DocumentSnapshot post) {
        final data = post.data() as Map<String, dynamic>;
        activeOwner = data['uid']?.toString() ?? '';
        final watched = post.id;
        playingOwnerAccess?.cancel();
        playingPost?.cancel();
        playingOwnerAccess = _ownerAccess
            .putIfAbsent(activeOwner, () => _watchOwnerAccess(uid, activeOwner))
            .listen((allowed) {
              if (!allowed) closeUnavailable(watched);
            });
        playingPost = post.reference.snapshots().listen(
          (latest) {
            if (latest.metadata.isFromCache) return;
            final current = latest.data() as Map<String, dynamic>?;
            if (current == null ||
                current['isDeleted'] == true ||
                current['uid'] != data['uid']) {
              closeUnavailable(watched);
            }
          },
          onError: (Object error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              closeUnavailable(watched);
            }
          },
        );
        checkActiveBlock();
      }

      Future<void> loadNeighbor(bool older) async {
        if (older ? loadingAfter : loadingBefore) return;
        if (older) {
          loadingAfter = true;
        } else {
          loadingBefore = true;
        }
        try {
          while (routeOpen && _current(uid, generation)) {
            final index = older ? after : before;
            if (index < 0 || index >= ids.length) return;
            DocumentSnapshot<Map<String, dynamic>>? neighbor;
            try {
              neighbor = await _readPlayable(
                ids[index],
                uid,
                generation,
                auth,
              ).timeout(const Duration(seconds: 15));
            } on FirebaseException catch (error) {
              if (error.code != 'permission-denied') rethrow;
            }
            if (!routeOpen || !_current(uid, generation)) return;
            if (older) {
              after++;
            } else {
              before--;
            }
            if (neighbor == null) continue;
            posts.value = older
                ? [...posts.value, neighbor]
                : [neighbor, ...posts.value];
            return;
          }
        } catch (_) {
          if (routeOpen && _current(uid, generation)) {
            _message('تعذّر تحميل الفيديو التالي. حاول مرة أخرى');
          }
        } finally {
          if (older) {
            loadingAfter = false;
          } else {
            loadingBefore = false;
          }
        }
      }

      route = MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<List<DocumentSnapshot>>(
          valueListenable: posts,
          builder: (_, loaded, _) => PostViewScreen(
            posts: loaded,
            initialIndex: loaded.indexWhere((post) => post.id == activeId),
            thumbnailUrl: selected.data()?['thumbnailUrl']?.toString(),
            isFromProfileGrid: true,
            watchHistoryAccount: uid,
            onWatchHistoryPostChanged: (post) {
              final index = loaded.indexWhere((entry) => entry.id == post.id);
              if (index < 0) return;
              if (activeId != post.id) {
                activeId = post.id;
                watchPlayingPost(post);
              }
              if (index == 0) unawaited(loadNeighbor(false));
              if (index == loaded.length - 1) unawaited(loadNeighbor(true));
            },
          ),
        ),
      );
      opened = true;
      final done = navigation.push(route);
      auth.addListener(checkActiveBlock);
      watchPlayingPost(selected);
      final authSubscription = _firebaseAuth.authStateChanges().listen((user) {
        if (user?.uid != uid && route.isActive) {
          routeOpen = false;
          navigation.removeRoute(route);
        }
      });
      unawaited(loadNeighbor(true));
      unawaited(loadNeighbor(false));
      try {
        await done;
      } finally {
        routeOpen = false;
        auth.removeListener(checkActiveBlock);
        await Future.wait([
          authSubscription.cancel(),
          ?playingOwnerAccess?.cancel(),
          ?playingPost?.cancel(),
        ]);
        await route.completed;
        posts.dispose();
        if (_current(uid, generation)) {
          await TitiProfileEngine().unlock();
          await TitiSingleEngine().lock();
        }
      }
    } catch (_) {
      if (_current(uid, generation)) _message('تعذّر فتح الفيديو');
    } finally {
      if (_current(uid, generation)) {
        _opening = false;
        if (opened) await _refreshHead(uid, generation);
      }
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _recentSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _showFilter() {
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
          const SizedBox(height: 10),
          const Text(
            'التصفية حسب التاريخ',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          for (var f in ['الكل', 'اليوم', 'أمس', '7 أيام', '30 يوم'])
            ListTile(
              title: Text(
                f,
                style: TextStyle(color: _filter == f ? titiTeal : Colors.white),
              ),
              trailing: _filter == f
                  ? Icon(Icons.check, color: titiTeal)
                  : null,
              onTap: () {
                Navigator.pop(context);
                if (_filter == f || _opening || _deleting) return;
                _filter = f;
                unawaited(_reset());
              },
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final auth = context.watch<custom.AuthProvider>();
    final docs = _firebaseAuth.currentUser?.uid == uid
        ? _documents.values.where((doc) {
            return !_blocked(auth, doc.data()['uid']?.toString() ?? '');
          }).toList()
        : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    docs.sort((a, b) {
      final x = a.data()['watchedAt'];
      final y = b.data()['watchedAt'];
      if (x is Timestamp && y is Timestamp) {
        final time = y.compareTo(x);
        if (time != 0) return time;
      }
      return b.id.compareTo(a.id);
    });
    final ids = docs.map(_postId).toSet().toList();
    final today = _day(DateTime.now());
    final groups =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final label = _groupLabel(_getDate(doc.data()), today);
      groups.putIfAbsent(label, () => []).add(doc);
    }

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
          'سجل المشاهدة',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        actions: [
          if (!_selectMode)
            TextButton(
              onPressed: () => setState(() => _selectMode = true),
              child: const Text('حدد', style: TextStyle(color: Colors.white)),
            )
          else ...[
            TextButton(
              onPressed: _selected.isEmpty || _deleting
                  ? null
                  : _deleteSelected,
              child: Text(
                'حذف (${_selected.length})',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _deleting
                  ? null
                  : () => setState(() {
                      _selectMode = false;
                      _selected.clear();
                    }),
            ),
          ],
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
                        _filter == 'الكل' ? 'التصفية حسب التاريخ' : _filter,
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
              onRefresh: () async {
                if (!_opening && !_deleting) await _reset();
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  for (final group in groups.entries) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          group.key,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 2,
                              childAspectRatio: 0.72,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (_, index) => _tile(uid!, group.value[index], ids),
                          childCount: group.value.length,
                        ),
                      ),
                    ),
                  ],
                  if (docs.isEmpty && !_loading && !_hasMore && !_failed)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          _filter == 'الكل'
                              ? 'لا يوجد سجل'
                              : 'لا توجد نتائج للتصفية',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    ),
                  if (_loading || _hasMore || _failed)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: _loading
                              ? CircularProgressIndicator(
                                  color: titiTeal,
                                  strokeWidth: 2,
                                )
                              : TextButton(
                                  onPressed: _fetchMore,
                                  child: Text(
                                    _failed
                                        ? 'تعذّر تحميل السجل. أعد المحاولة'
                                        : 'تحميل المزيد',
                                  ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    String uid,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    List<String> ids,
  ) {
    final data = doc.data();
    final owner = data['uid']?.toString() ?? '';
    final postId = _postId(doc);
    final thumb = data['thumbnailUrl']?.toString() ?? '';
    final selected = _selected.contains(doc.id);
    return StreamBuilder<bool>(
      key: ValueKey((uid, doc.id, owner)),
      stream: _ownerAccess.putIfAbsent(
        owner,
        () => _watchOwnerAccess(uid, owner),
      ),
      builder: (_, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return AudiencePostGate(
          post: data,
          postId: postId,
          child: GestureDetector(
            onTap: () {
              if (_deleting) return;
              if (_selectMode) {
                setState(() {
                  if (selected) {
                    _selected.remove(doc.id);
                  } else {
                    _selected.add(doc.id);
                  }
                });
              } else {
                unawaited(_openVideo(uid, postId, ids));
              }
            },
            onLongPress: () {
              if (_deleting) return;
              setState(() {
                _selectMode = true;
                _selected.add(doc.id);
              });
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: surfaceColor,
                  child: thumb.isNotEmpty
                      ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover)
                      : const Icon(Iconsax.video, color: Colors.white24),
                ),
                if (selected)
                  Container(
                    color: Colors.teal.withValues(alpha: 0.5),
                    child: const Icon(Icons.check_circle, color: Colors.white),
                  ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  right: 4,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _formatViews(data['views']),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
