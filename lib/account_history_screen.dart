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
  final _logs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _recentSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tailSub;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  String? _undatedCursor;
  String? _uid;
  int _generation = 0;
  bool _newestFirst = true;
  bool _loading = true;
  bool _hasMore = false;
  bool _failed = false;
  final _pendingExits = <String, DocumentSnapshot<Map<String, dynamic>>>{};
  Timer? _exitCheckTimer;
  bool _checkingExits = false;
  int _exitFailures = 0;
  final _liveTokens = <_LiveWindow, Object>{};
  final _liveRetries = <_LiveWindow, VoidCallback>{};
  bool _loadingUndated = false;
  bool _hasUndatedPages = false;
  bool _undatedFailed = false;

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
      _undatedCursor = null;
      _loading = false;
      _hasMore = _uid != null;
      _failed = false;
      _liveTokens.clear();
      _exitCheckTimer?.cancel();
      _exitCheckTimer = null;
      _pendingExits.clear();
      _checkingExits = false;
      _exitFailures = 0;
      _liveRetries.clear();
      _loadingUndated = false;
      _hasUndatedPages = _uid != null;
      _undatedFailed = false;
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
        _listenToFirstPage(
          uid,
          generation,
          visible.map((doc) => doc.id).toSet(),
        );
        if (page.docs.isEmpty) unawaited(_fetchUndated());
      } else if (!_newestFirst && !_hasMore) {
        // In oldest-first order, new logins arrive after the loaded tail.
        _listenToTail(
          uid,
          generation,
          cursor,
          visible.map((doc) => doc.id).toSet(),
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

  void _listenToFirstPage(String uid, int generation, Set<String> liveIds) {
    final boundary = _hasMore ? _cursor : null;
    final query = _datedHistory(uid);
    // A fixed boundary keeps new entries from pushing an unpaged row
    // out of both the live results and the next cursor page.
    final firstPage = boundary == null
        ? query.limit(_pageSize + 1)
        : query.endAtDocument(boundary);
    _watchLive(
      firstPage,
      uid,
      generation,
      _LiveWindow.first,
      (snapshot) {
        final visible = boundary == null
            ? snapshot.docs.take(_pageSize)
            : snapshot.docs;
        _mergeLiveRows(uid, generation, liveIds, visible, snapshot.docs);
        if (boundary == null) {
          _cursor = visible.isEmpty ? null : visible.last;
          _hasMore = snapshot.docs.length > _pageSize;
        }
      },
      afterSnapshot: () {
        if (boundary == null && _hasMore) {
          _listenToFirstPage(uid, generation, liveIds);
        }
      },
    );
  }

  void _listenToTail(
    String uid,
    int generation,
    QueryDocumentSnapshot<Map<String, dynamic>> cursor,
    Set<String> liveIds,
  ) {
    final tail = _datedHistory(uid).startAfterDocument(cursor);
    _watchLive(tail, uid, generation, _LiveWindow.tail, (snapshot) {
      _mergeLiveRows(uid, generation, liveIds, snapshot.docs, snapshot.docs);
    });
  }

  Future<void> _watchLive(
    Query<Map<String, dynamic>> query,
    String uid,
    int generation,
    _LiveWindow window,
    void Function(QuerySnapshot<Map<String, dynamic>>) apply, {
    VoidCallback? afterSnapshot,
  }) async {
    if (!_current(uid, generation)) return;
    final token = Object();
    _liveTokens[window] = token;
    bool isActive() =>
        _current(uid, generation) && identical(_liveTokens[window], token);

    final previous = window == _LiveWindow.first ? _recentSub : _tailSub;
    try {
      await previous?.cancel().timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('Login history listener cancellation failed: $error');
    }
    if (!isActive()) return;
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
    String uid,
    int generation,
    Set<String> liveIds,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> visible,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> returned,
  ) {
    final returnedIds = returned.map((doc) => doc.id).toSet();
    for (final id in returnedIds) {
      _pendingExits.remove(id);
    }
    for (final id in liveIds.difference(returnedIds)) {
      final previous = _logs[id];
      if (previous != null) _pendingExits[id] = previous;
    }
    liveIds.clear();
    for (final doc in visible) {
      _logs[doc.id] = doc;
      liveIds.add(doc.id);
    }
    if (_exitFailures >= 3) _exitFailures = 0;
    _scheduleExitCheck(uid, generation);
  }

  void _scheduleExitCheck(String uid, int generation) {
    if (!_current(uid, generation) ||
        _pendingExits.isEmpty ||
        _exitCheckTimer != null ||
        _checkingExits ||
        _exitFailures >= 3) {
      return;
    }
    final delay = _exitFailures == 0
        ? const Duration(milliseconds: 150)
        : Duration(seconds: 1 << _exitFailures);
    _exitCheckTimer = Timer(delay, () {
      _exitCheckTimer = null;
      unawaited(_checkLiveExits(uid, generation));
    });
  }

  Future<void> _checkLiveExits(String uid, int generation) async {
    if (!_current(uid, generation) || _pendingExits.isEmpty) return;
    _checkingExits = true;
    final batch = _pendingExits.entries.take(_pageSize).toList();
    try {
      final result = await _history(uid)
          .where(
            FieldPath.documentId,
            whereIn: batch.map((entry) => entry.key).toList(),
          )
          .get(_server)
          .timeout(_deadline);
      if (!_current(uid, generation)) return;
      if (result.metadata.isFromCache || result.metadata.hasPendingWrites) {
        throw StateError('Login history verification is not server-confirmed');
      }
      final confirmed = {for (final doc in result.docs) doc.id: doc};
      setState(() {
        for (final entry in batch) {
          if (!identical(_pendingExits[entry.key], entry.value)) continue;
          _pendingExits.remove(entry.key);
          if (!identical(_logs[entry.key], entry.value)) continue;
          final doc = confirmed[entry.key];
          if (doc == null) {
            _logs.remove(entry.key);
          } else {
            _logs[entry.key] = doc;
          }
        }
      });
      _exitFailures = 0;
    } catch (error) {
      if (!_current(uid, generation)) return;
      _exitFailures++;
      debugPrint('Login history row verification failed: $error');
    } finally {
      if (_current(uid, generation)) {
        _checkingExits = false;
        _scheduleExitCheck(uid, generation);
      }
    }
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
      // A timestamp sort excludes documents where that field is absent.
      var query = _history(uid).orderBy(FieldPath.documentId);
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
          if (_timestamp(doc.data()) == null) {
            _logs.putIfAbsent(doc.id, () => doc);
          }
        }
        _hasUndatedPages = page.docs.length > _pageSize;
        _loadingUndated = false;
      });
    } catch (error) {
      if (!_current(uid, generation)) return;
      debugPrint('Undated login history page failed: $error');
      setState(() {
        _loadingUndated = false;
        _undatedFailed = true;
      });
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

  Timestamp? _timestamp(Map<String, dynamic>? data) {
    final value = data?['timestamp'];
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
    _exitCheckTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final docs = uid != null && uid == _auth.currentUser?.uid
        ? _logs.values.toList()
        : <DocumentSnapshot<Map<String, dynamic>>>[];
    docs.sort((a, b) {
      final left = _timestamp(a.data());
      final right = _timestamp(b.data());
      if (left == null && right != null) return 1;
      if (left != null && right == null) return -1;
      final time = left == null || right == null ? 0 : left.compareTo(right);
      final order = time == 0 ? a.id.compareTo(b.id) : time;
      return _newestFirst ? -order : order;
    });
    final grouped = <String, List<DocumentSnapshot<Map<String, dynamic>>>>{};
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
                        final data = entry.data() ?? const <String, dynamic>{};
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
                      !_failed &&
                      !_loadingUndated &&
                      !_hasUndatedPages)
                    SliverFillRemaining(
                      hasScrollBody: false,
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
                  if (_hasMore && !_loading)
                    _pageAction(
                      _failed
                          ? 'تعذّر تحميل سجل الحساب. أعد المحاولة'
                          : 'تحميل المزيد',
                      _fetchMore,
                    ),
                  if (_hasUndatedPages &&
                      !_loadingUndated &&
                      !_loading &&
                      !_failed)
                    _pageAction(
                      _undatedFailed
                          ? 'تعذّر البحث عن السجلات بلا تاريخ. أعد المحاولة'
                          : _undatedCursor == null
                          ? 'البحث عن السجلات بلا تاريخ'
                          : 'البحث عن المزيد من السجلات بلا تاريخ',
                      _fetchUndated,
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
