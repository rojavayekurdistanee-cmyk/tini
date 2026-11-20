import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/*
  [Tini Project Rules]:
    1. File Name: account_history_screen.dart
    2. Concept: Account Login History (مثل تيك توك - سجل الحساب)
    3. UI Style: Dark Surface (0xFF1A222C), Background (0xFF0F1720), Teal Accents.
    4. Design Ref: صور تيك توك المرفقة - مقسم بالتاريخ + كارد فيه الجهاز والمكان والوقت
*/

enum _LiveWindow { first, tail }

class AccountHistoryScreen extends StatefulWidget {
  const AccountHistoryScreen({super.key});

  @override
  State<AccountHistoryScreen> createState() => _AccountHistoryScreenState();
}

class _AccountHistoryScreenState extends State<AccountHistoryScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  static const _pageSize = 30;
  static const _deadline = Duration(seconds: 15);
  static const _server = GetOptions(source: Source.server);
  final _auth = FirebaseAuth.instance;
  final _store = FirebaseFirestore.instance;
  final _scrollController = ScrollController();
  final _logs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _recentSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tailSub;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  String? _uid;
  int _generation = 0;
  bool _newestFirst = true;
  bool _loading = true;
  bool _hasMore = false;
  bool _failed = false;
  final _liveRetries = <_LiveWindow, VoidCallback>{};
  final _liveTokens = <_LiveWindow, Object>{};

  CollectionReference<Map<String, dynamic>> _history(String uid) =>
      _store.collection('users').doc(uid).collection('login_history');

  Query<Map<String, dynamic>> _datedHistory(String uid) =>
      _history(uid).orderBy('timestamp', descending: _newestFirst);

  bool _current(String uid, int generation) =>
      mounted &&
      uid == _uid &&
      uid == _auth.currentUser?.uid &&
      generation == _generation;

  @override
  void initState() {
    super.initState();
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
    unawaited(_recentSub?.cancel());
    unawaited(_tailSub?.cancel());
    _recentSub = null;
    _tailSub = null;
    setState(() {
      _generation++;
      _logs.clear();
      _cursor = null;
      _loading = false;
      _hasMore = _uid != null;
      _failed = false;
      _liveRetries.clear();
      _liveTokens.clear();
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
    final cursor = _cursor;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      var query = _datedHistory(uid);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query
          .limit(_pageSize + 1)
          .get(_server)
          .timeout(_deadline);
      if (!_current(uid, generation)) return;
      final visible = page.docs.take(_pageSize);
      setState(() {
        for (final doc in visible) {
          _logs[doc.id] = doc;
          _cursor = doc;
        }
        _hasMore = page.docs.length > _pageSize;
        _loading = false;
      });
      if (cursor == null) {
        _listenToFirstPage(uid, generation);
        if (!_newestFirst && !_hasMore && _cursor != null) {
          _listenToTail(uid, generation, _cursor!);
        }
      } else if (!_newestFirst && !_hasMore && _cursor != null) {
        // In oldest-first order, new logins arrive after the loaded tail.
        _listenToTail(
          uid,
          generation,
          _cursor!,
        );
      }
    } catch (error) {
      if (!_current(uid, generation)) return;
      debugPrint('Login history page failed: $error');
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  // Keep the first live query bounded. Pagination owns _cursor, so incoming
  // records cannot move the cursor and cause skipped older pages.
  void _listenToFirstPage(String uid, int generation) {
    final boundary = _cursor;
    final query = _datedHistory(uid);
    final firstPage = boundary == null
        ? query.limit(_pageSize)
        : query.endAtDocument(boundary).limit(_pageSize);
    _watchLive(firstPage, uid, generation, _LiveWindow.first, (snapshot) {
      _mergeLiveRows(snapshot.docs);
      // In ascending order, new logins fall after the last loaded record.
      if (!_newestFirst && !_hasMore && _cursor != null &&
          _tailSub == null) {
        _listenToTail(uid, generation, _cursor!);
      }
    });
  }

  void _listenToTail(
    String uid,
    int generation,
    QueryDocumentSnapshot<Map<String, dynamic>> cursor,
  ) {
    // Only watch the newest 30 records after the loaded ascending cursor.
    // An unbounded tail would charge reads for the whole remaining history.
    final tail = _datedHistory(uid)
        .startAfterDocument(cursor)
        .limitToLast(_pageSize);
    _watchLive(tail, uid, generation, _LiveWindow.tail, (snapshot) {
      _mergeLiveRows(snapshot.docs);
    });
  }

  void _watchLive(
    Query<Map<String, dynamic>> query,
    String uid,
    int generation,
    _LiveWindow window,
    void Function(QuerySnapshot<Map<String, dynamic>>) apply, {
    VoidCallback? afterSnapshot,
  }) {
    if (!_current(uid, generation)) return;
    final token = Object();
    _liveTokens[window] = token;
    bool isActive() =>
        _current(uid, generation) && identical(_liveTokens[window], token);
    final previous = window == _LiveWindow.first ? _recentSub : _tailSub;
    unawaited(previous?.cancel());
    final subscription = query
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (!isActive() ||
                snapshot.metadata.isFromCache ||
                snapshot.metadata.hasPendingWrites) {
              return;
            }
            setState(() {
              apply(snapshot);
              _liveRetries.remove(window);
            });
            afterSnapshot?.call();
          },
          onError: (Object error) {
            if (!isActive()) return;
            debugPrint('Login history live update failed: $error');
            setState(() {
              _liveRetries[window] = () => _watchLive(
                query,
                uid,
                generation,
                window,
                apply,
                afterSnapshot: afterSnapshot,
              );
            });
          },
          cancelOnError: true,
        );
    if (window == _LiveWindow.first) {
      _recentSub = subscription;
    } else {
      _tailSub = subscription;
    }
  }

  void _retryLiveUpdates() {
    for (final retry in _liveRetries.values.toList()) {
      retry();
    }
  }

  void _mergeLiveRows(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> visible,
  ) {
    // Never treat a query-window exit as deletion of a stored login.
    for (final doc in visible) {
      _logs[doc.id] = doc;
    }
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

  Timestamp? _timestamp(Map<String, dynamic> data) {
    final value = data['timestamp'];
    return value is Timestamp ? value : null;
  }

  String _text(Object? value) => value is String ? value.trim() : '';

  String _location(Map<String, dynamic> data) {
    final saved = _text(data['location']);
    if (saved.isNotEmpty && saved != 'تسجيل دخول جديد') return saved;
    return [
      _text(data['city']),
      _text(data['country']),
    ].where((part) => part.isNotEmpty).join('، ');
  }

  Widget _pageAction(String label, VoidCallback action) => SliverToBoxAdapter(
    child: Center(
      child: TextButton(onPressed: action, child: Text(label)),
    ),
  );

  String _getDateKey(Timestamp ts) {
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
    final now = DateTime.now();
    if (d.year != now.year) {
      return "${d.day} ${months[d.month - 1]}، ${d.year}";
    } else {
      return "${d.day} ${months[d.month - 1]}";
    }
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return 'وقت غير معروف';
    final d = ts.toDate();
    int hour = d.hour;
    final minute = d.minute.toString().padLeft(2, '0');
    final isAm = hour < 12;
    if (hour == 0) hour = 12;
    if (hour > 12) hour -= 12;
    return "$hour:$minute ${isAm ? 'ص' : 'م'}";
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _recentSub?.cancel();
    _tailSub?.cancel();
    _liveTokens.clear();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final docs = uid != null && uid == _auth.currentUser?.uid
        ? _logs.values.toList()
        : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    docs.sort((a, b) {
      final left = _timestamp(a.data());
      final right = _timestamp(b.data());
      if (left == null && right != null) return 1;
      if (left != null && right == null) return -1;
      final time = left == null || right == null ? 0 : left.compareTo(right);
      final order = time == 0 ? a.id.compareTo(b.id) : time;
      return _newestFirst ? -order : order;
    });
    final grouped =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final stamp = _timestamp(doc.data());
      final label = stamp == null ? 'تاريخ غير معروف' : _getDateKey(stamp);
      grouped.putIfAbsent(label, () => []).add(doc);
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
          "سجل الحساب",
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: surfaceColor.withValues(alpha: 0.6),
            child: const Text(
              "هنا يظهر سجل تسجيل الدخول إلى حسابك. إذا لم تتعرف على أي نشاط، فيمكنك مراجعة معلومات الحساب لديك أو إدارة الأجهزة.",
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12.5,
                height: 1.6,
              ),
            ),
          ),
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
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  if (_liveRetries.isNotEmpty)
                    _pageAction(
                      'تعذّر تحديث سجل الحساب. أعد المحاولة',
                      _retryLiveUpdates,
                    ),
                  for (final group in grouped.entries) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          right: 20,
                          left: 20,
                          top: 18,
                          bottom: 10,
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            group.key,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: group.value.length,
                      itemBuilder: (_, index) {
                        final entry = group.value[index];
                        final data = entry.data();
                        final name = _text(data['deviceName']);
                        final legacyDevice = _text(data['device']);
                        final device = name.isNotEmpty ? name : legacyDevice;
                        return _buildLoginCard(
                          key: ValueKey((_generation, entry.id)),
                          timestamp: _timestamp(data),
                          deviceText: device.isEmpty
                              ? 'جهاز غير معروف'
                              : device,
                          locationText: _location(data),
                        );
                      },
                    ),
                  ],
                  if (docs.isEmpty &&
                      !_loading &&
                      !_hasMore &&
                      !_failed)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 56),
                        child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Iconsax.security_safe,
                            size: 70,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'لا يوجد سجل حساب',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                        ),
                      ),
                    ),
                  if (_loading)
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
                  if (_hasMore && !_loading)
                    _pageAction(
                      _failed
                          ? 'تعذّر تحميل سجل الحساب. أعد المحاولة'
                          : 'تحميل المزيد',
                      _fetchMore,
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 30)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard({
    required Key key,
    required Timestamp? timestamp,
    required String deviceText,
    required String locationText,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                "الحساب مسجل الدخول",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Iconsax.login_1,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "لقد سجلت الدخول إلى حسابك",
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            locationText.isNotEmpty
                ? "من $deviceText في $locationText"
                : "من $deviceText",
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatTime(timestamp),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}