import 'dart:async';
import 'package:flutter/foundation.dart';
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

const _trashRetention = Duration(days: 30);
typedef _TrashDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

String _remainingText(Map<String, dynamic> data) {
  final expires = data['expireAt'];
  final deleted = data['deletedAt'];
  final deadline = expires is Timestamp
      ? expires.toDate()
      : deleted is Timestamp
      ? deleted.toDate().add(_trashRetention)
      : null;
  if (deadline == null) return 'المدة غير معروفة';
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) return 'انتهت المدة';
  final seconds = remaining.inSeconds;
  if (seconds < 3600) return 'متبقي أقل من ساعة';
  final hours = seconds ~/ 3600;
  final days = hours ~/ 24;
  final remainder = hours % 24;
  if (days == 0) return 'متبقي $hours ساعة';
  return remainder == 0
      ? 'متبقي $days يوم'
      : 'متبقي $days يوم و$remainder ساعة';
}

class DeletedVideosScreen extends StatefulWidget {
  const DeletedVideosScreen({super.key});

  @override
  State<DeletedVideosScreen> createState() => _DeletedVideosScreenState();
}

class _DeletedVideosScreenState extends State<DeletedVideosScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  static const _pageSize = 30;
  final _auth = FirebaseAuth.instance;
  final _store = FirebaseFirestore.instance;
  final _scroll = ScrollController();
  final _docs = ValueNotifier<List<_TrashDoc>>([]);
  final _pages = <List<_TrashDoc>>[];
  final _listeners =
      <int, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final _watchTokens = <int, Object>{};
  final _failedWatches = <int, VoidCallback>{};
  final _restored = <String, Timestamp?>{};
  StreamSubscription<User?>? _authSub;
  Timer? _clock;
  _TrashDoc? _cursor;
  String? _uid;
  int _generation = 0;
  bool _loading = true;
  bool _hasMore = false;
  bool _pageFailed = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _authSub = _auth.authStateChanges().listen((user) {
      if (!mounted) return;
      _uid = user?.uid;
      unawaited(_reset());
    });
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400 && !_pageFailed) {
        unawaited(_fetchMore());
      }
    });
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  bool _current(String uid, int generation) =>
      mounted &&
      _uid == uid &&
      _auth.currentUser?.uid == uid &&
      generation == _generation;

  Query<Map<String, dynamic>> _query(String uid) => _store
      .collection('posts')
      .where('uid', isEqualTo: uid)
      .where('isDeleted', isEqualTo: true)
      .orderBy('deletedAt', descending: true);

  Future<void> _reset() async {
    for (final sub in _listeners.values) {
      unawaited(sub.cancel());
    }
    _listeners.clear();
    setState(() {
      _generation++;
      _pages.clear();
      _watchTokens.clear();
      _failedWatches.clear();
      _restored.clear();
      _docs.value = [];
      _cursor = null;
      _loading = false;
      _hasMore = _uid != null;
      _pageFailed = false;
      _opening = false;
    });
    await _fetchMore();
  }

  void _publish() {
    final unique = <String, _TrashDoc>{};
    for (final page in _pages) {
      for (final doc in page) {
        final deleted = doc.data()['deletedAt'];
        if (_restored.containsKey(doc.id)) {
          final previous = _restored[doc.id];
          if (deleted is! Timestamp ||
              (previous != null && deleted.compareTo(previous) <= 0))
            continue;
          _restored.remove(doc.id);
        }
        unique.putIfAbsent(doc.id, () => doc);
      }
    }
    _docs.value = unique.values.toList();
  }

  int _newestFirst(_TrashDoc left, _TrashDoc right) {
    final a = left.data()['deletedAt'];
    final b = right.data()['deletedAt'];
    if (a is Timestamp && b is Timestamp) {
      final dateOrder = b.compareTo(a);
      if (dateOrder != 0) return dateOrder;
    } else if (a is Timestamp || b is Timestamp) {
      return a is Timestamp ? -1 : 1;
    }
    return right.id.compareTo(left.id);
  }

  Future<void> _fetchMore() async {
    final uid = _uid;
    final generation = _generation;
    if (uid == null || !_current(uid, generation) || _loading || !_hasMore)
      return;
    setState(() {
      _loading = true;
      _pageFailed = false;
    });
    try {
      var query = _query(uid);
      final cursor = _cursor;
      if (cursor != null) query = query.startAfterDocument(cursor);
      final result = await query
          .limit(_pageSize + 1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (!_current(uid, generation)) return;
      final visible = result.docs.take(_pageSize).toList();
      final index = _pages.length;
      final end = visible.isEmpty ? null : visible.last;
      setState(() {
        _pages.add(visible);
        _hasMore = result.docs.length > _pageSize;
        _cursor = end ?? cursor;
        _loading = false;
        _publish();
      });
      _watchPage(uid, generation, index, query, _hasMore ? end : null);
    } catch (error) {
      if (!_current(uid, generation)) return;
      debugPrint('Trash page failed: $error');
      setState(() {
        _loading = false;
        _pageFailed = true;
      });
    }
  }

  Future<void> _watchPage(
    String uid,
    int generation,
    int index,
    Query<Map<String, dynamic>> query,
    _TrashDoc? end,
  ) async {
    if (!_current(uid, generation)) return;
    final token = Object();
    _watchTokens[index] = token;
    bool active() =>
        _current(uid, generation) && identical(_watchTokens[index], token);
    try {
      await _listeners[index]?.cancel().timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('Trash listener cancellation failed: $error');
    }
    if (!active()) return;
    final bounded = end == null
        ? query.limit(_pageSize + 1)
        : query.endAtDocument(end);
    _listeners[index] = bounded
        .snapshots(includeMetadataChanges: true)
        .listen(
          (result) {
            if (!active() ||
                result.metadata.isFromCache ||
                result.metadata.hasPendingWrites)
              return;
            final lastWindow = index == _pages.length - 1;
            if (end == null && lastWindow && result.docs.length > _pageSize) {
              // A limited snapshot can evict a still-deleted video. Extend
              // the fixed range through the previous oldest visible row.
              final merged = <String, _TrashDoc>{
                for (final entry in _pages[index]) entry.id: entry,
                for (final entry in result.docs.take(_pageSize))
                  entry.id: entry,
              };
              final expanded = merged.values.toList()..sort(_newestFirst);
              final boundary = expanded.last;
              setState(() {
                _failedWatches.remove(index);
                _pages[index] = expanded;
                _hasMore = true;
                _cursor = boundary;
                _publish();
              });
              unawaited(_watchPage(uid, generation, index, query, boundary));
              return;
            }
            setState(() {
              _failedWatches.remove(index);
              _pages[index] = result.docs;
              if (end == null && !_loading && lastWindow) {
                _hasMore = false;
                if (result.docs.isNotEmpty) _cursor = result.docs.last;
              }
              _publish();
            });
          },
          onError: (Object error) {
            if (!active()) return;
            debugPrint('Trash update failed: $error');
            setState(
              () =>
                  _failedWatches[index] = () =>
                      _watchPage(uid, generation, index, query, end),
            );
          },
          cancelOnError: true,
        );
  }

  Future<void> _open(_TrashDoc doc) async {
    final uid = _uid;
    final generation = _generation;
    if (_opening || uid == null || !_current(uid, generation)) return;
    _opening = true;
    try {
      if (!await AudienceAccess.instance
          .verifyPost(doc.id)
          .timeout(const Duration(seconds: 15)))
        return;
      if (!_current(uid, generation) ||
          !_docs.value.any((entry) => entry.id == doc.id))
        return;
      try {
        await TitiSingleEngine().lock();
        await TitiProfileEngine().unlock();
      } catch (_) {
        // The preview also unlocks its playback engine.
      }
      if (!mounted ||
          !_current(uid, generation) ||
          ModalRoute.of(context)?.isCurrent != true ||
          !_docs.value.any((entry) => entry.id == doc.id))
        return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DeletedVideoPreviewScreen(
            docs: _docs,
            initialId: doc.id,
            loadMore: _fetchMore,
            onRestored: (entry) {
              if (!_current(uid, generation)) return;
              final deleted = entry.data()['deletedAt'];
              setState(() {
                _restored[entry.id] = deleted is Timestamp ? deleted : null;
                _publish();
              });
            },
          ),
        ),
      );
    } catch (_) {
      if (_current(uid, generation)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذّر فتح الفيديو')));
      }
    } finally {
      if (_current(uid, generation)) _opening = false;
    }
  }

  void _showInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          'المحذوفات',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'سيتم حذف المنشورات نهائياً بعد الوقت الموضح.',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('حسناً', style: TextStyle(color: titiTeal)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final sub in _listeners.values) {
      unawaited(sub.cancel());
    }
    _authSub?.cancel();
    _clock?.cancel();
    _scroll.dispose();
    _docs.dispose();
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
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'المحذوفات',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.info_circle, color: Colors.white70),
            onPressed: _showInfo,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reset,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_failedWatches.isNotEmpty)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: () {
                    for (final retry in _failedWatches.values.toList()) {
                      retry();
                    }
                  },
                  child: const Text('تعذّر تحديث المحذوفات. أعد المحاولة'),
                ),
              ),
            if (_auth.currentUser?.uid == _uid)
              SliverPadding(
                padding: const EdgeInsets.all(2),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: _docs.value.length,
                  itemBuilder: (context, index) {
                    final doc = _docs.value[index];
                    final data = doc.data();
                    final thumb = data['thumbnailUrl']?.toString() ?? '';
                    return AudiencePostGate(
                      post: data,
                      postId: doc.id,
                      child: GestureDetector(
                        onTap: () => _open(doc),
                        child: Container(
                          color: surfaceColor,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              thumb.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: thumb,
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(
                                      Iconsax.video,
                                      color: Colors.white24,
                                    ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    _remainingText(data),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_docs.value.isEmpty &&
                !_loading &&
                !_hasMore &&
                !_pageFailed &&
                _failedWatches.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Iconsax.trash,
                      size: 70,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'لا يوجد فيديوهات محذوفة',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            if (_loading || _hasMore || _pageFailed)
              SliverToBoxAdapter(
                child: Center(
                  child: _loading
                      ? CircularProgressIndicator(color: titiTeal)
                      : TextButton(
                          onPressed: _fetchMore,
                          child: Text(
                            _pageFailed
                                ? 'تعذّر تحميل المحذوفات. أعد المحاولة'
                                : 'تحميل المزيد',
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DeletedVideoPreviewScreen extends StatefulWidget {
  final ValueListenable<List<_TrashDoc>> docs;
  final String initialId;
  final Future<void> Function() loadMore;
  final ValueChanged<_TrashDoc> onRestored;
  const DeletedVideoPreviewScreen({
    super.key,
    required this.docs,
    required this.initialId,
    required this.loadMore,
    required this.onRestored,
  });

  @override
  State<DeletedVideoPreviewScreen> createState() =>
      _DeletedVideoPreviewScreenState();
}

class _DeletedVideoPreviewScreenState extends State<DeletedVideoPreviewScreen> {
  late int _currentIndex;
  late PageController _pageController;
  bool _isRestoring = false;
  late List<_TrashDoc> _visible;
  Timer? _clock;
  int _selectionRevision = 0;
  Future<void>? _stoppingPlayback;
  bool _adjustingPage = false;
  String? _openingUid;
  StreamSubscription? _authSub;
  bool _sessionChanged = false;

  String _getBestUrl(Map<String, dynamic> data) {
    final hls = (data['hlsPath'] as String?)?.trim() ?? "";
    if (hls.isNotEmpty) return hls;
    return (data['videoUrl'] as String?) ?? "";
  }

  @override
  void initState() {
    super.initState();
    _visible = widget.docs.value;
    final initial = _visible.indexWhere(
      (entry) => entry.id == widget.initialId,
    );
    _currentIndex = initial < 0 ? 0 : initial;
    _pageController = PageController(initialPage: _currentIndex);
    widget.docs.addListener(_updateDocs);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
    _openingUid = FirebaseAuth.instance.currentUser?.uid;
    AudienceAccess.instance.addListener(_playCurrent);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || user?.uid == _openingUid) return;
      TitiProfileEngine().stop();
      setState(() => _sessionChanged = true);
      if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_visible.isEmpty) {
        _closeWhenEmpty();
      } else {
        _playCurrent();
        _loadNearEnd();
      }
    });
  }

  void _loadNearEnd() {
    if (_currentIndex >= _visible.length - 3) unawaited(widget.loadMore());
  }

  void _closeWhenEmpty() {
    if (mounted &&
        _visible.isEmpty &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
    }
  }

  void _updateDocs() {
    if (!mounted) return;
    final oldIndex = _currentIndex;
    final previous = _visible.isEmpty ? null : _visible[oldIndex];
    final next = widget.docs.value;
    final current = next.indexWhere((doc) => doc.id == previous?.id);
    final lostCurrent = current < 0 && previous != null;
    final nextIndex = next.isEmpty
        ? 0
        : current >= 0
        ? current
        : oldIndex.clamp(0, next.length - 1).toInt();
    final selected = next.isEmpty ? null : next[nextIndex];
    final needsPlayback =
        selected != null &&
        (previous == null ||
            lostCurrent ||
            previous.data()['trashPurgeStartedAt'] !=
                selected.data()['trashPurgeStartedAt'] ||
            _getBestUrl(previous.data()) != _getBestUrl(selected.data()));
    if (!_adjustingPage && !lostCurrent && nextIndex == oldIndex) {
      setState(() => _visible = next);
      if (needsPlayback) _playCurrent();
      return;
    }
    if (lostCurrent) _stoppingPlayback = TitiProfileEngine().stop();
    final revision = ++_selectionRevision;
    _adjustingPage = true;
    setState(() {
      _visible = next;
      _currentIndex = nextIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || revision != _selectionRevision) return;
      if (_visible.isEmpty) {
        _closeWhenEmpty();
        return;
      }
      if (_pageController.hasClients) _pageController.jumpToPage(_currentIndex);
      final wasStopping = _stoppingPlayback != null;
      if (_stoppingPlayback case final stop?) {
        await stop;
        if (!mounted || revision != _selectionRevision || _sessionChanged)
          return;
        await TitiProfileEngine().unlock();
        if (!mounted || revision != _selectionRevision || _sessionChanged)
          return;
        _stoppingPlayback = null;
      }
      _adjustingPage = false;
      if (needsPlayback || wasStopping) _playCurrent();
      _loadNearEnd();
    });
  }

  Future<void> _restoreCurrent() async {
    if (_isRestoring ||
        _visible.isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != _openingUid)
      return;
    final doc = _visible[_currentIndex];
    final provider = context.read<PostProvider>();
    final onRestored = widget.onRestored;
    setState(() => _isRestoring = true);
    try {
      if (!await AudienceAccess.instance
          .verifyPost(doc.id)
          .timeout(const Duration(seconds: 15))) {
        throw StateError('Video is unavailable for restore');
      }
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != _openingUid)
        return;
      await provider.restorePost(doc.id);
      if (mounted && FirebaseAuth.instance.currentUser?.uid == _openingUid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت استعادة الفيديو'),
            backgroundColor: Colors.teal,
          ),
        );
      }
      onRestored(doc);
    } catch (error) {
      if (mounted && FirebaseAuth.instance.currentUser?.uid == _openingUid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّرت استعادة الفيديو. حاول مرة أخرى'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  String? _allowedUrl(int index) {
    if (index < 0 || index >= _visible.length) return null;
    final doc = _visible[index];
    final data = doc.data();
    if (data['trashPurgeStartedAt'] != null ||
        !AudienceAccess.instance.canViewPost(data, postId: doc.id))
      return null;
    return _getBestUrl(data);
  }

  void _playCurrent() {
    if (!mounted ||
        _sessionChanged ||
        FirebaseAuth.instance.currentUser?.uid != _openingUid)
      return;
    if (ModalRoute.of(context)?.isCurrent != true || _visible.isEmpty) return;
    final data = _visible[_currentIndex].data();
    final url = _getBestUrl(data);
    if (_adjustingPage) return;
    if (url.isEmpty) {
      unawaited(TitiProfileEngine().pause());
      return;
    }
    if (_allowedUrl(_currentIndex) == null) {
      // انتظار التحقق لا يقفل المحرك عن صاحب الفيديو بعد عودة الاتصال.
      TitiProfileEngine().pause();
      return;
    }

    String? prev, prevPrev, next, nextNext, nextNextNext;
    if (_currentIndex - 1 >= 0) prev = _allowedUrl(_currentIndex - 1);
    if (_currentIndex - 2 >= 0) prevPrev = _allowedUrl(_currentIndex - 2);
    if (_currentIndex + 1 < _visible.length)
      next = _allowedUrl(_currentIndex + 1);
    if (_currentIndex + 2 < _visible.length)
      nextNext = _allowedUrl(_currentIndex + 2);
    if (_currentIndex + 3 < _visible.length)
      nextNextNext = _allowedUrl(_currentIndex + 3);

    TitiProfileEngine().playSingleUrl(
      url,
      prevUrl: prev,
      prevPrevUrl: prevPrev,
      nextUrl: next,
      nextNextUrl: nextNext,
      nextNextNextUrl: nextNextNext,
    );
  }

  @override
  void dispose() {
    widget.docs.removeListener(_updateDocs);
    _clock?.cancel();
    AudienceAccess.instance.removeListener(_playCurrent);
    _authSub?.cancel();
    _pageController.dispose();
    TitiProfileEngine().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionChanged || _visible.isEmpty)
      return const Scaffold(backgroundColor: Colors.black);
    final double screenHeight = MediaQuery.of(context).size.height;
    final double topBarHeight = screenHeight * 0.032;
    final double bottomBarHeight = screenHeight * 0.0775;
    const Color titiDarkBG = Color(0xFF000000);

    final currentData = _visible[_currentIndex].data();

    return Scaffold(
      backgroundColor: titiDarkBG,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _visible.length,
            onPageChanged: (i) {
              if (_adjustingPage || i >= _visible.length) return;
              setState(() => _currentIndex = i);
              _playCurrent();
              _loadNearEnd();
            },
            itemBuilder: (context, index) {
              final doc = _visible[index];
              final data = doc.data();
              final videoUrl = _getBestUrl(data);
              final thumb = data['thumbnailUrl'] as String?;

              // نفس مكان TitiVideoPlayer بس فيديو يملي الشاشة
              return AudiencePostGate(
                key: ValueKey(doc.id),
                post: data,
                postId: doc.id,
                child: SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumb != null && thumb.isNotEmpty)
                        CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover),
                      ValueListenableBuilder<List<String>>(
                        valueListenable: TitiProfileEngine().playerUrlsNotifier,
                        builder: (context, urls, _) {
                          final myIdx = urls.indexOf(videoUrl);
                          if (myIdx == -1) return const SizedBox.shrink();
                          return Video(
                            controller: TitiProfileEngine()
                                .getControllerByIndex(myIdx),
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
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 18,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      _remainingText(currentData),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed:
                        _isRestoring ||
                            _visible[_currentIndex]
                                    .data()['trashPurgeStartedAt'] !=
                                null
                        ? null
                        : _restoreCurrent,
                    child: _isRestoring
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'استعادة',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
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
