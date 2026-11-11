import 'user_documents.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'audience_policy.dart';

/// Only server-confirmed documents may grant access. Cache/pending snapshots
/// can close a gate but cannot open it.
class AudienceDocument {
  final Map<String, dynamic>? data;
  final bool verified;
  const AudienceDocument(this.data, {this.verified = true});
}

abstract class AudienceBackend {
  String? get currentUid;
  Stream<String?> get viewerChanges;
  Stream<AudienceDocument> watchUser(String uid);
  Stream<AudienceDocument> watchPost(String postId);
  Future<AudienceDocument> readUser(String uid);
  Future<AudienceDocument> readPost(String postId);
}

class _FirebaseAudienceBackend implements AudienceBackend {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore store = FirebaseFirestore.instance;
  @override
  String? get currentUid => auth.currentUser?.uid;
  @override
  Stream<String?> get viewerChanges =>
      auth.authStateChanges().map((user) => user?.uid);
  AudienceDocument _document(DocumentSnapshot<Map<String, dynamic>> doc) =>
      AudienceDocument(
        doc.data(),
        verified: !doc.metadata.isFromCache && !doc.metadata.hasPendingWrites,
      );
  @override
  Stream<AudienceDocument> watchUser(String uid) => UserDocuments.readable(store, uid)
      .snapshots(includeMetadataChanges: true)
      .map(_document);
  @override
  Stream<AudienceDocument> watchPost(String postId) => store
      .collection('posts')
      .doc(postId)
      .snapshots(includeMetadataChanges: true)
      .map(_document);
  @override
  Future<AudienceDocument> readUser(String uid) async => _document(
    await UserDocuments.readable(store, uid)
        .get(const GetOptions(source: Source.server)),
  );
  @override
  Future<AudienceDocument> readPost(String postId) async => _document(
    await store
        .collection('posts')
        .doc(postId)
        .get(const GetOptions(source: Source.server)),
  );
}

/// Live, session-scoped age checks used by existing feeds and media players.
/// This is an additional audience gate; existing privacy/block rules still run.
class AudienceAccess extends ChangeNotifier with WidgetsBindingObserver {
  static AudienceAccess? _instance;
  static AudienceAccess get instance =>
      _instance ??= AudienceAccess._(_FirebaseAudienceBackend());

  final AudienceBackend _backend;
  final DateTime Function() _clock;
  StreamSubscription<String?>? _authSub;
  final Map<String, StreamSubscription<AudienceDocument>> _userSubs = {};
  final Map<String, StreamSubscription<AudienceDocument>> _postSubs = {};
  final Map<String, AudienceDocument> _users = {};
  final Map<String, AudienceDocument> _posts = {};
  final Map<String, int> _userVersions = {};
  final Map<String, int> _postVersions = {};
  final Set<String> _failedUsers = {};
  final Set<String> _failedPosts = {};
  final Map<String, Map<String, dynamic>> _knownPosts = {};
  String? _viewerUid;
  int _generation = 0;
  bool _disposed = false;
  bool _notificationQueued = false;

  AudienceAccess._(this._backend, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
    _setViewer(_backend.currentUid);
    _authSub = _backend.viewerChanges.listen((_) => _syncIdentity());
  }

  @visibleForTesting
  factory AudienceAccess.forTesting(
    AudienceBackend backend, {
    DateTime Function()? clock,
  }) => AudienceAccess._(backend, clock: clock);

  String? get viewerUid {
    _syncIdentity();
    return _viewerUid;
  }

  bool get isViewerAdult {
    _syncIdentity();
    final doc = _users[_viewerUid];
    return _viewerUid != null &&
        !_failedUsers.contains(_viewerUid) &&
        doc?.verified == true &&
        doc?.data != null &&
        AudiencePolicy.viewerIsAdult(doc!.data!, now: _clock());
  }

  void _emit() {
    if (_disposed || _notificationQueued) return;
    _notificationQueued = true;
    scheduleMicrotask(() {
      _notificationQueued = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _syncIdentity() {
    if (!_disposed && _viewerUid != _backend.currentUid) {
      _setViewer(_backend.currentUid);
    }
  }

  void _setViewer(String? uid) {
    _generation++;
    for (final sub in _userSubs.values) {
      unawaited(sub.cancel());
    }
    for (final sub in _postSubs.values) {
      unawaited(sub.cancel());
    }
    _userSubs.clear();
    _postSubs.clear();
    _users.clear();
    _posts.clear();
    _knownPosts.clear();
    _userVersions.clear();
    _postVersions.clear();
    _failedUsers.clear();
    _failedPosts.clear();
    _viewerUid = uid;
    if (uid != null) _trackUser(uid);
    _emit();
  }

  // Only the fields that affect age eligibility may invalidate a verified
  // decision. Firestore emits a temporary pending-write snapshot when likes,
  // views or follower counters change; those counters are NOT an age change.
  bool _sameUserAudience(
    String uid,
    AudienceDocument previous,
    AudienceDocument next,
  ) {
    if (previous.data == null || next.data == null) return false;
    if (AudiencePolicy.isAccountRestricted(previous.data!) !=
        AudiencePolicy.isAccountRestricted(next.data!)) {
      return false;
    }
    if (uid == _viewerUid &&
        AudiencePolicy.viewerIsAdult(previous.data!, now: _clock()) !=
            AudiencePolicy.viewerIsAdult(next.data!, now: _clock())) {
      return false;
    }
    return true;
  }

  bool _samePostAudience(AudienceDocument previous, AudienceDocument next) {
    final oldData = previous.data;
    final newData = next.data;
    if (oldData == null || newData == null) return false;
    if (AudiencePolicy.ownerUid(oldData) != AudiencePolicy.ownerUid(newData) ||
        AudiencePolicy.isVideoRestricted(oldData) !=
            AudiencePolicy.isVideoRestricted(newData) ||
        AudiencePolicy.isTrue(oldData['isDeleted']) !=
            AudiencePolicy.isTrue(newData['isDeleted'])) {
      return false;
    }
    // Media URLs must remain bound to the server-confirmed post. An updated
    // URL is an actual access change, unlike a views/likes counter.
    for (final key in ['videoUrl', 'hlsPath', 'hlsUrl']) {
      if (oldData[key] != newData[key]) return false;
    }
    return true;
  }

  void _acceptUser(String uid, AudienceDocument next) {
    final previous = _users[uid];
    final same = previous != null && _sameUserAudience(uid, previous, next);
    // Keep the already server-confirmed audience decision if the local write
    // changes only an unrelated field. Do not grant access for a *new*
    // unconfirmed decision (including turning adult restrictions off).
    if (previous?.verified == true && !next.verified && same) return;
    _users[uid] = next;
    final recovered = next.verified && _failedUsers.remove(uid);
    if (recovered || previous == null || previous.verified != next.verified || !same) {
      _emit();
    }
  }

  void _acceptPost(String id, AudienceDocument next) {
    final previous = _posts[id];
    final same = previous != null && _samePostAudience(previous, next);
    if (previous?.verified == true && !next.verified && same) return;
    _posts[id] = next;
    final recovered = next.verified && _failedPosts.remove(id);
    if (next.data != null) {
      _trackUser(AudiencePolicy.ownerUid(next.data!));
    }
    if (recovered || previous == null || previous.verified != next.verified || !same) {
      _emit();
    }
  }

  void _trackUser(String uid) {
    if (_disposed ||
        uid.isEmpty ||
        _failedUsers.contains(uid) ||
        _userSubs.containsKey(uid)) {
      return;
    }
    final generation = _generation;
    _userSubs[uid] = _backend
        .watchUser(uid)
        .listen(
          (doc) {
            if (_disposed ||
                generation != _generation ||
                _viewerUid != _backend.currentUid) {
              return;
            }
            _userVersions[uid] = (_userVersions[uid] ?? 0) + 1;
            _acceptUser(uid, doc);
          },
          onError: (Object error) {
            if (_disposed || generation != _generation) return;
            _userVersions[uid] = (_userVersions[uid] ?? 0) + 1;
            _users[uid] = const AudienceDocument(null, verified: false);
            _failedUsers.add(uid);
            unawaited(_userSubs.remove(uid)?.cancel());
            _emit();
          },
          onDone: () {
            if (_disposed || generation != _generation) return;
            _userVersions[uid] = (_userVersions[uid] ?? 0) + 1;
            _users[uid] = const AudienceDocument(null, verified: false);
            _failedUsers.add(uid);
            _userSubs.remove(uid);
            _emit();
          },
        );
  }

  String _postId(Map<String, dynamic> data, String? postId) =>
      (postId ?? data['postId'] ?? data['id'] ?? '').toString();

  void trackPost(Map<String, dynamic> data, {String? postId}) {
    _syncIdentity();
    if (_disposed) return;
    final id = _postId(data, postId);
    final key = id.isNotEmpty
        ? id
        : 'url:${data['videoUrl'] ?? data['hlsPath'] ?? data.hashCode}';
    _knownPosts[key] = Map<String, dynamic>.from(data);
    _trackUser(AudiencePolicy.ownerUid(data));
    if (id.isEmpty || _failedPosts.contains(id) || _postSubs.containsKey(id)) {
      return;
    }
    final generation = _generation;
    _postSubs[id] = _backend
        .watchPost(id)
        .listen(
          (doc) {
            if (_disposed ||
                generation != _generation ||
                _viewerUid != _backend.currentUid) {
              return;
            }
            _postVersions[id] = (_postVersions[id] ?? 0) + 1;
            _acceptPost(id, doc);
          },
          onError: (Object error) {
            if (_disposed || generation != _generation) return;
            _postVersions[id] = (_postVersions[id] ?? 0) + 1;
            _posts[id] = const AudienceDocument(null, verified: false);
            _failedPosts.add(id);
            unawaited(_postSubs.remove(id)?.cancel());
            _emit();
          },
          onDone: () {
            if (_disposed || generation != _generation) return;
            _postVersions[id] = (_postVersions[id] ?? 0) + 1;
            _posts[id] = const AudienceDocument(null, verified: false);
            _failedPosts.add(id);
            _postSubs.remove(id);
            _emit();
          },
        );
  }

  bool canViewProfile(String uid) {
    _syncIdentity();
    if (_disposed || uid.isEmpty) return false;
    _trackUser(uid);
    if (_viewerUid != null && uid == _viewerUid) return true;
    if (isViewerAdult) return true;
    if (_failedUsers.contains(uid)) return false;
    final owner = _users[uid];
    return owner?.verified == true &&
        owner?.data != null &&
        !AudiencePolicy.isAccountRestricted(owner!.data!);
  }

  bool canViewPost(Map<String, dynamic> data, {String? postId}) {
    trackPost(data, postId: postId);
    final id = _postId(data, postId);
    Map<String, dynamic> current = data;
    if (id.isNotEmpty) {
      final canonical = _posts[id];
      if (_failedPosts.contains(id) ||
          canonical?.verified != true ||
          canonical?.data == null) {
        return false;
      }
      current = canonical!.data!;
    }
    final owner = AudiencePolicy.ownerUid(current);
    if (_disposed || owner.isEmpty) return false;
    if (_viewerUid != null && owner == _viewerUid) return true;
    if (AudiencePolicy.isTrue(current['isDeleted'])) return false;
    if (isViewerAdult) return true;
    return !AudiencePolicy.isVideoRestricted(current) && canViewProfile(owner);
  }

  /// Unverified or failed reads are a loading/unavailable state, never proof
  /// that a normal video is 18+. A confirmed restriction is not pending.
  bool isPostPending(Map<String, dynamic> data, {String? postId}) {
    trackPost(data, postId: postId);
    final id = _postId(data, postId);
    final canonical = id.isNotEmpty ? _posts[id] : null;
    if (id.isNotEmpty && canonical?.verified != true) return true;
    final current = id.isNotEmpty ? canonical?.data : data;
    if (current == null) return false;
    final owner = AudiencePolicy.ownerUid(current);
    if (owner.isEmpty || owner == _viewerUid || isViewerAdult ||
        AudiencePolicy.isVideoRestricted(current)) {
      return false;
    }
    return _users[owner]?.verified != true;
  }

  /// Only label a denial as an age restriction when confirmed account or
  /// moderation data actually establishes that restriction.
  bool isPostAgeRestricted(Map<String, dynamic> data, {String? postId}) {
    trackPost(data, postId: postId);
    if (isViewerAdult) return false;
    final id = _postId(data, postId);
    final canonical = id.isNotEmpty ? _posts[id] : null;
    if (id.isNotEmpty &&
        (canonical?.verified != true || canonical?.data == null)) {
      return false;
    }
    final current = id.isNotEmpty ? canonical!.data! : data;
    final owner = AudiencePolicy.ownerUid(current);
    if (owner.isEmpty || owner == _viewerUid) return false;
    if (AudiencePolicy.isVideoRestricted(current)) return true;
    final user = _users[owner];
    return user?.verified == true && user?.data != null &&
        AudiencePolicy.isAccountRestricted(user!.data!);
  }

  bool canPlayUrl(String url) {
    _syncIdentity();
    if (_disposed || url.isEmpty) return false;
    bool matches(Map<String, dynamic> data) =>
        ['videoUrl', 'hlsPath', 'hlsUrl'].any((key) => data[key] == url);
    final records = _knownPosts.entries.toList();
    final canonicalRecords = records
        .where(
          (entry) =>
              !entry.key.startsWith('url:') &&
              (matches(entry.value) || matches(_posts[entry.key]?.data ?? {})),
        )
        .toList();
    // A canonical record supersedes every earlier URL-only/cache observation.
    // A revoked or changed canonical URL must never fall back to the old map.
    if (canonicalRecords.isNotEmpty) {
      return canonicalRecords.every((entry) {
        final doc = _posts[entry.key];
        return doc?.verified == true &&
            doc?.data != null &&
            matches(doc!.data!) &&
            canViewPost(entry.value, postId: entry.key);
      });
    }
    return records.any(
      (entry) => matches(entry.value) && canViewPost(entry.value),
    );
  }

  void _retryWatches() {
    final users = _failedUsers.toList();
    final posts = _failedPosts.toList();
    _failedUsers.clear();
    _failedPosts.clear();
    for (final id in users) {
      _trackUser(id);
    }
    for (final id in posts) {
      trackPost(_knownPosts[id] ?? {}, postId: id);
    }
  }

  Future<bool> _readUser(String id, int generation, String? uid) async {
    final version = (_userVersions[id] ?? 0) + 1;
    _userVersions[id] = version;
    AudienceDocument doc;
    try {
      doc = await _backend.readUser(id).timeout(const Duration(seconds: 8));
    } catch (_) {
      doc = const AudienceDocument(null, verified: false);
    }
    if (!_disposed &&
        generation == _generation &&
        uid == _backend.currentUid &&
        _userVersions[id] == version) {
      // An isolated server-read failure during resume must not wipe a
      // previously verified live stream state. Unknown users still fail closed.
      if (doc.verified || _users[id]?.verified != true) {
        _acceptUser(id, doc);
      }
    }
    // An intervening verified stream update is newer than this read.
    return !_disposed && generation == _generation &&
        uid == _backend.currentUid &&
        (doc.verified ||
            (_userVersions[id] != version && _users[id]?.verified == true));
  }

  Future<bool> _readPost(String id, int generation, String? uid) async {
    final version = (_postVersions[id] ?? 0) + 1;
    _postVersions[id] = version;
    AudienceDocument doc;
    try {
      doc = await _backend.readPost(id).timeout(const Duration(seconds: 8));
    } catch (_) {
      doc = const AudienceDocument(null, verified: false);
    }
    if (!_disposed &&
        generation == _generation &&
        uid == _backend.currentUid &&
        _postVersions[id] == version) {
      if (doc.verified || _posts[id]?.verified != true) {
        _acceptPost(id, doc);
      }
    }
    return !_disposed && generation == _generation &&
        uid == _backend.currentUid &&
        (doc.verified ||
            (_postVersions[id] != version && _posts[id]?.verified == true));
  }

  /// Explicit server verification for notification images and copied history.
  /// Read tickets prevent an old read from replacing a newer stream update.
  Future<bool> verifyPost(String postId) async {
    _syncIdentity();
    if (_disposed || postId.isEmpty) return false;
    _retryWatches();
    // Observe changes even while the first explicit read awaits owner data.
    trackPost(_knownPosts[postId] ?? {}, postId: postId);
    final generation = _generation;
    final uid = _viewerUid;
    final postConfirmed = await _readPost(postId, generation, uid);
    if (!postConfirmed || _disposed || generation != _generation ||
        uid != _backend.currentUid) {
      return false;
    }
    final post = _posts[postId];
    if (post?.verified != true || post?.data == null) {
      _emit();
      return false;
    }
    final ownerUid = AudiencePolicy.ownerUid(post!.data!);
    if (ownerUid.isEmpty) return false;
    final usersConfirmed = await Future.wait<bool>([
      for (final id in {ownerUid, ?uid}) _readUser(id, generation, uid),
    ]);
    if (usersConfirmed.any((confirmed) => !confirmed) ||
        _disposed || generation != _generation || uid != _backend.currentUid) {
      return false;
    }
    // The canonical post may have changed owner/classification while awaiting.
    final latest = _posts[postId];
    if (latest?.verified != true || latest?.data == null) {
      _emit();
      return false;
    }
    trackPost(latest!.data!, postId: postId);
    _emit();
    return canViewPost(latest.data!, postId: postId);
  }

  Future<void> refresh() async {
    _syncIdentity();
    if (_disposed) return;
    _retryWatches();
    final generation = _generation;
    final uid = _viewerUid;
    final users = _userSubs.keys.toList();
    final posts = _postSubs.keys.toList();
    // Never clear a valid decision merely because a background refresh began.
    // Incoming server-confirmed changes still replace it immediately.
    await Future.wait([
      for (final id in users) _readUser(id, generation, uid),
      for (final id in posts) _readPost(id, generation, uid),
    ]);
    // _acceptUser/_acceptPost notify only for actual access changes.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSub?.cancel());
    for (final sub in _userSubs.values) {
      unawaited(sub.cancel());
    }
    for (final sub in _postSubs.values) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}
