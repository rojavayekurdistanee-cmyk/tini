import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Retrieves only the newest [pageSize] chat messages at startup.
///
/// Older pages are requested via a Firestore document cursor. Every *loaded*
/// page stays synchronized, so edits, reactions, read receipts and deletion
/// still appear in the UI. Unvisited history is never fetched on startup.
/// The caller owns this controller and must dispose it with the chat screen.
class TiniChatMessagePager extends ChangeNotifier {
  TiniChatMessagePager({
    required Query<Map<String, dynamic>> query,
    this.pageSize = 40,
    this.timestampField = 'timestamp',
    this.pinnedQuery,
  })  : assert(pageSize > 0),
        _query = query;

  final Query<Map<String, dynamic>> _query;
  final int pageSize;
  final String timestampField;
  // Inbox-only supplemental listener: preserves pinned chats outside the
  // newest page. Message screens do not provide this query.
  final Query<Map<String, dynamic>>? pinnedQuery;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pinnedSubscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pinned = [];
  Object? _pinnedError;
  Object? get pinnedError => _pinnedError;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _recentSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _olderSubscription;
  QueryDocumentSnapshot<Map<String, dynamic>>? _initialRecentBoundary;
  final Set<String> _liveOlderIds = <String>{};
  final Set<String> _displacedRecentIds = <String>{};
  int _olderGeneration = 0;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _recent = [];
  final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> _older = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _documents = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _oldestCursor;

  bool _initialized = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _disposed = false;
  Object? _error;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get documents =>
      List.unmodifiable(_documents);
  bool get initialized => _initialized;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  Object? get error => _error;

  void start() {
    if (_disposed || _recentSubscription != null) return;
    if (pinnedQuery != null) {
      _pinnedSubscription = pinnedQuery!.snapshots().listen((snapshot) {
        if (_disposed) return;
        _pinned = snapshot.docs;
        _pinnedError = null;
        _rebuild();
      }, onError: (Object error, StackTrace stackTrace) {
        if (_disposed) return;
        _pinnedError = error;
        notifyListeners();
      });
    }
    _recentSubscription = _query.limit(pageSize).snapshots().listen((snapshot) {
      if (_disposed) return;
      final ids = snapshot.docs.map((doc) => doc.id).toSet();
      final tailTime = snapshot.docs.isNotEmpty
          ? snapshot.docs.last.data()[timestampField]
          : null;

      // A limited live query ejects older items when newer messages arrive.
      // Retain genuinely displaced messages without retaining deleted ones.
      for (final doc in _recent) {
        if (ids.contains(doc.id)) continue;
        final previousTime = doc.data()[timestampField];
        if (snapshot.docs.length == pageSize &&
            previousTime is Timestamp &&
            tailTime is Timestamp &&
            previousTime.compareTo(tailTime) < 0) {
          _older.putIfAbsent(doc.id, () => doc);
          _displacedRecentIds.add(doc.id);
        } else if (!_liveOlderIds.contains(doc.id)) {
          _older.remove(doc.id);
          _displacedRecentIds.remove(doc.id);
        }
      }

      _recent = snapshot.docs;
      _initialized = true;
      _error = null;
      _oldestCursor ??= snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _initialRecentBoundary ??= snapshot.docs.isNotEmpty ? snapshot.docs.last : null;

      if (snapshot.docs.isEmpty && !snapshot.metadata.isFromCache) {
        _older.clear();
        _displacedRecentIds.clear();
        _liveOlderIds.clear();
        _hasMore = false;
      } else if (!snapshot.metadata.isFromCache &&
          snapshot.docs.length < pageSize &&
          _older.isEmpty) {
        _hasMore = false;
      }
      _rebuild();
    }, onError: (Object error, StackTrace stackTrace) {
      if (_disposed) return;
      _error = error;
      _initialized = true;
      notifyListeners();
    });
  }

  Future<void> loadOlder() async {
    if (_disposed || !_initialized || _loadingMore || !_hasMore) return;
    final cursor = _oldestCursor;
    if (cursor == null) {
      _hasMore = false;
      notifyListeners();
      return;
    }
    _loadingMore = true;
    _error = null;
    notifyListeners();

    try {
      final page = await _query.startAfterDocument(cursor).limit(pageSize).get();
      if (_disposed) return;
      for (final doc in page.docs) {
        _older[doc.id] = doc;
      }
      if (page.docs.isNotEmpty) {
        _oldestCursor = page.docs.last;
      }
      if (page.docs.length < pageSize && !page.metadata.isFromCache) {
        _hasMore = false;
      }
      _rebuild();
      if (page.docs.isNotEmpty) {
        await _listenToLoadedHistory();
      }
    } catch (error) {
      if (_disposed) return;
      _error = error;
    } finally {
      if (!_disposed) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> _listenToLoadedHistory() async {
    final firstBoundary = _initialRecentBoundary;
    final lastBoundary = _oldestCursor;
    if (firstBoundary == null || lastBoundary == null) return;
    final generation = ++_olderGeneration;
    await _olderSubscription?.cancel();
    if (_disposed || generation != _olderGeneration) return;
    // One bounded range instead of N listeners: loaded historical messages
    // still receive live edits, reactions, read receipts and deletion updates.
    final range = _query.startAfterDocument(firstBoundary)
        .endAtDocument(lastBoundary);
    _olderSubscription = range.snapshots().listen((snapshot) {
      if (_disposed || generation != _olderGeneration) return;
      final incomingIds = snapshot.docs.map((doc) => doc.id).toSet();
      if (!snapshot.metadata.isFromCache) {
        for (final id in _liveOlderIds.difference(incomingIds)) {
          if (!_displacedRecentIds.contains(id) &&
              !_recent.any((doc) => doc.id == id)) {
            _older.remove(id);
          }
        }
      }
      _liveOlderIds
        ..clear()
        ..addAll(incomingIds);
      for (final doc in snapshot.docs) {
        _older[doc.id] = doc;
      }
      _rebuild();
    }, onError: (Object error, StackTrace stackTrace) {
      if (_disposed || generation != _olderGeneration) return;
      _error = error;
      notifyListeners();
    });
  }

  void _rebuild() {
    final unique = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in _older.values) {
      unique[doc.id] = doc;
    }
    for (final doc in _recent) {
      unique[doc.id] = doc;
    }
    for (final doc in _pinned) {
      unique[doc.id] = doc;
    }
    final sorted = unique.values.toList();
    sorted.sort((a, b) {
      final at = a.data()[timestampField];
      final bt = b.data()[timestampField];
      if (at is Timestamp && bt is Timestamp) {
        final comparison = bt.compareTo(at);
        if (comparison != 0) return comparison;
      } else if (at is Timestamp) {
        return 1;
      } else if (bt is Timestamp) {
        return -1;
      }
      return b.id.compareTo(a.id);
    });
    _documents = sorted;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _recentSubscription?.cancel();
    _pinnedSubscription?.cancel();
    _pinned.clear();
    _olderGeneration++;
    _olderSubscription?.cancel();
    _liveOlderIds.clear();
    _displacedRecentIds.clear();
    _recent.clear();
    _older.clear();
    _documents.clear();
    super.dispose();
  }
}
