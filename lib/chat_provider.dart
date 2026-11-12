import 'banner_event_cursor.dart';
import 'audience_access.dart';
import 'user_documents.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tini_chat_read_checkpoint.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'r2_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'follow_request_service.dart';
import 'banner_manager.dart'; // [Tini] مدير البانرات المركزي

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final String type;
  final String? mediaUrl;
  final DateTime timestamp;
  final String? reaction;
  final int? bubbleColor;
  final Map<String, dynamic>? replyTo;
  final int? durationSeconds;
  final bool isSeen;
  final bool isDelivered; // ✅ NEW - للصح الواحد
  // [عرض مرة واحدة - الدردشات الخاصة]
  final bool viewOnce;
  final List<String> viewedBy;
  final bool mediaDeleted;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    this.mediaUrl,
    required this.timestamp,
    this.reaction,
    this.bubbleColor,
    this.replyTo,
    this.durationSeconds,
    this.isSeen = false,
    this.isDelivered = false, // ✅ NEW
    this.viewOnce = false,
    this.viewedBy = const [],
    this.mediaDeleted = false,
  });
}

// [Tini - Messaging]: نتيجة تفصيلية لكل محاولة، بدون تخزين حالة مشتركة بين العمليات.
// واجهات startChat وsendMessage القديمة تظل متوافقة مع جميع الاستدعاءات الحالية.
enum ChatFailureReason {
  requestsDisabled,
  followersOnly,
  nobody,
  blocked,
  waitingForReply,
  accountUnavailable,
  privacyUnavailable,
  permissionDenied,
  roomNotFound,
  notAuthenticated,
  invalidMedia,
  technicalError,
}

extension ChatFailureReasonDetails on ChatFailureReason {
  String get userMessage {
    switch (this) {
      case ChatFailureReason.requestsDisabled:
        return 'هذا الحساب لم يفعّل استقبال طلبات المراسلة.';
      case ChatFailureReason.followersOnly:
        return 'هذا الحساب يستقبل طلبات المراسلة من متابعيه فقط.';
      case ChatFailureReason.nobody:
        return 'هذا الحساب لا يستقبل طلبات مراسلة جديدة.';
      case ChatFailureReason.blocked:
        return 'لا يمكنك مراسلة هذا الحساب حالياً.';
      case ChatFailureReason.waitingForReply:
        return 'طلب المراسلة قيد الانتظار. يمكنك إرسال المزيد بعد رد الطرف الآخر.';
      case ChatFailureReason.accountUnavailable:
        return 'تعذّر الوصول إلى هذا الحساب للمراسلة.';
      case ChatFailureReason.privacyUnavailable:
        return 'تعذّر التحقق من إمكانية المراسلة. حاول مرة أخرى.';
      case ChatFailureReason.permissionDenied:
        return 'تعذّر إتمام المراسلة بسبب قيود الوصول. حاول مرة أخرى.';
      case ChatFailureReason.roomNotFound:
        return 'المحادثة غير متاحة. حاول فتحها من جديد.';
      case ChatFailureReason.notAuthenticated:
        return 'يرجى تسجيل الدخول للمراسلة.';
      case ChatFailureReason.invalidMedia:
        return 'تعذّر إرسال الوسائط. تحقق من الملف وحاول مرة أخرى.';
      case ChatFailureReason.technicalError:
        return 'تعذّر إتمام العملية. تحقق من اتصالك وحاول مرة أخرى.';
    }
  }

  bool get isPrivacyRestriction {
    switch (this) {
      case ChatFailureReason.requestsDisabled:
      case ChatFailureReason.followersOnly:
      case ChatFailureReason.nobody:
      case ChatFailureReason.blocked:
      case ChatFailureReason.waitingForReply:
        return true;
      default:
        return false;
    }
  }
}

class ChatActionResult<T> {
  final T? value;
  final ChatFailureReason? failureReason;

  const ChatActionResult.success(T result) : value = result, failureReason = null;
  const ChatActionResult.failure(ChatFailureReason reason)
      : value = null, failureReason = reason;

  bool get isSuccess => failureReason == null;
  String? get failureMessage => failureReason?.userMessage;
  bool get isPrivacyRestriction => failureReason?.isPrivacyRestriction ?? false;
}

class ChatProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final R2Service _r2 = R2Service();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // [Phase 6 - HARD BLOCK ONLY] - إضافة فقط - حظر رسائل
  Set<String> _blockedIds = {};
  Set<String> get blockedIds => _blockedIds;

  Future<void> loadBlockedIds() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final generation = _bannerGeneration;
    try {
      final doc = await UserDocuments.readable(_firestore, uid).get();
      if (!_sessionIs(uid, generation)) return;
      final List fromField = doc.data()?['blockedUsers']?? doc.data()?['blocked']?? [];
      _blockedIds = fromField.map((e) => e.toString()).toSet();
      final snap = await _firestore.collection('users').doc(uid).collection('blocked').get();
      if (!_sessionIs(uid, generation)) return;
      _blockedIds.addAll(snap.docs.map((d) => d.id));
    } catch (_) {}
  }

  bool isBlocked(String uid) => _blockedIds.contains(uid);

  // [Tini] مدير البانرات المركزي - كل البانرات انتقلت لملف banner_manager.dart
  final BannerManager _bannerManager = BannerManager.instance;

  // [NEW] حالة النشاط أونلاين - للمراقبة فقط
  Map<String, StreamSubscription> _friendStatusListeners = {};
  StreamSubscription? _followingSub;
  StreamSubscription? _followersSub;
  StreamSubscription? _activitiesSub;
  StreamSubscription? _visitsSub;
  StreamSubscription? _globalDeliveredSub;

  // متغيرات المتابعة المباشرة
  final FollowRequestService _followService = FollowRequestService();
  int _pendingFollowRequests = 0;
  Map<String, dynamic>? _lastFollower;
  String? _currentUid;
  int _lastKnownFollowersCount = 0;
  bool _initialized = false;

  int get pendingFollowRequests => _pendingFollowRequests;
  Map<String, dynamic>? get lastFollower => _lastFollower;

  // متغيرات النشاط
  int _pendingActivities = 0;
  Map<String, dynamic>? _lastActivity;

  int get pendingActivities => _pendingActivities;
  Map<String, dynamic>? get lastActivity => _lastActivity;

  String _getRoomId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('_');
  }

  // [Tini] دالة فحص الصداقة - متابعة متبادلة
  Future<bool> checkIfFriend(String currentUid, String otherUid) async {
    if (currentUid == otherUid) return true; // انا صديق حالي

    try {
      // 1. بشوف اذا انا متابعه
      final followingDoc = await _firestore
        .collection('users')
        .doc(currentUid)
        .collection('following')
        .doc(otherUid)
        .get();

      if (!followingDoc.exists) return false; // مش متابعه = مش صديق

      // 2. بشوف اذا هو متابعني
      final followerDoc = await _firestore
        .collection('users')
        .doc(currentUid)
        .collection('followers')
        .doc(otherUid)
        .get();

      return followerDoc.exists; // صديق = متابعة متبادلة
    } catch (e) {
      debugPrint('Error checking friendship: $e');
      return false; // لو صار خطأ، اعتبره مش صديق للأمان
    }
  }

  // بدء الاستماع للمتابعين الجدد - نظام مباشر
  void startFollowRequestsListener() {
    final uid = _auth.currentUser?.uid;
    if (_disposed || uid == null || _currentUid != uid || _followersSub != null) return;
    final generation = _bannerGeneration;
    _followersSub = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('followers')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .listen((snap) {
      if (!_sessionIs(uid, generation)) return;
      final newCount = snap.docs.length;

      // أول مرة: خد العدد الحالي كمرجع ولا تحسبه
      if (!_initialized) {
        _lastKnownFollowersCount = newCount;
        _initialized = true;
        notifyListeners();
        return;
      }

      if (newCount > _lastKnownFollowersCount && snap.docs.isNotEmpty) {
        final diff = newCount - _lastKnownFollowersCount;
        _pendingFollowRequests += diff;

        final lastDoc = snap.docs.first;
        UserDocuments.readable(FirebaseFirestore.instance, lastDoc.id).get().then((userDoc) {
          if (_sessionIs(uid, generation) && userDoc.exists) {
            _lastFollower = userDoc.data();
            _lastFollower!['uid'] = lastDoc.id;
            notifyListeners();
          }
        });
      } else if (newCount == 0) {
        _pendingFollowRequests = 0;
        _lastFollower = null;
      }

      _lastKnownFollowersCount = newCount;
      notifyListeners();
    });
  }

  // Presentation is serialized separately; counters always reflect every document.
  StreamSubscription? _bannerAuthSub;
  bool _disposed = false;
  int _bannerGeneration = 0;
  bool _bannerReady = false;
  DateTime? _bannerSessionStartedAt;
  Future<void> _bannerWork = Future.value();
  final Map<String, Map<String, dynamic>> _bannerUsers = {};
  final Map<String, DateTime> _bannerUserFetchedAt = {};
  final Map<String, DateTime> _verifiedBannerPosts = {};

  bool _sessionIs(String uid, int generation) => !_disposed &&
      _auth.currentUser?.uid == uid && _currentUid == uid && generation == _bannerGeneration;

  void _queueBannerWork(Future<void> Function() action) {
    _bannerWork = _bannerWork.then((_) => action()).catchError((Object error) {
      debugPrint('Banner event skipped: $error');
    });
  }

  Future<void> _submitBanner(String uid, int generation, String eventId,
      BannerType type, Map<String, dynamic> data) async {
    if (!_sessionIs(uid, generation)) return;
    final at = data['timestamp'];
    final actor = (data['fromUid'] ?? data['visitorId'])?.toString() ?? '';
    if (at is! Timestamp) {
      debugPrint('[Banner] skipped type=${type.name} reason=missing_server_timestamp');
      return;
    }
    if (actor.isEmpty || actor == uid || isBlocked(actor) || !_bannerManager.enabled(type)) return;
    if (DateTime.now().difference(at.toDate()) > BannerPolicy.expiry) {
      debugPrint('[Banner] skipped type=${type.name} reason=expired_event');
      return;
    }
    // Reuse a short verification window for bursts on the same post.
    final postId = data['postId']?.toString() ?? '';
    if ({BannerType.like, BannerType.comment, BannerType.mention}.contains(type)) {
      if (postId.isEmpty) return;
      final verified = _verifiedBannerPosts[postId];
      if (verified == null || DateTime.now().difference(verified) > const Duration(seconds: 10)) {
        if (!await AudienceAccess.instance.verifyPost(postId) || !_sessionIs(uid, generation)) return;
        final post = await _firestore.collection('posts').doc(postId).get();
        if (!_sessionIs(uid, generation) || !post.exists || post.data()?['isDeleted'] == true) return;
        if (_verifiedBannerPosts.length >= 100) _verifiedBannerPosts.remove(_verifiedBannerPosts.keys.first);
        _verifiedBannerPosts[postId] = DateTime.now();
      }
    }
    // Start the live actor gate while fetching its public presentation data.
    AudienceAccess.instance.canViewProfile(actor);
    var user = _bannerUsers[actor];
    if (user == null || DateTime.now().difference(_bannerUserFetchedAt[actor]!) > const Duration(minutes: 5)) {
      final doc = await UserDocuments.readable(_firestore, actor).get();
      if (!_sessionIs(uid, generation)) return;
      if (!doc.exists) {
        debugPrint('[Banner] skipped type=${type.name} reason=missing_public_profile');
        return;
      }
      user = doc.data()!;
      if (_bannerUsers.length >= 100) {
        final oldest = _bannerUsers.keys.first;
        _bannerUsers.remove(oldest); _bannerUserFetchedAt.remove(oldest);
      }
      _bannerUsers[actor] = user;
      _bannerUserFetchedAt[actor] = DateTime.now();
    }
    if (!_sessionIs(uid, generation) || isBlocked(actor)) return;
    _bannerManager.submit(BannerEvent(eventId, type, {
      ...data, 'uid': actor, 'name': user['fullName'] ?? user['username'] ?? 'مستخدم',
      'img': user['profileImg'] ?? '', 'activityType': data['type'],
    }, at.toDate()));
  }

  void startActivitiesListener() {
    final uid = _auth.currentUser?.uid;
    if (_disposed || uid == null || _currentUid != uid || !_bannerReady || _activitiesSub != null) return;
    final generation = _bannerGeneration;
    final cursor = BannerEventCursor(_bannerSessionStartedAt ?? DateTime.now());
    var initialized = false;
    _activitiesSub = _firestore.collection('activities')
      .where('toUid', isEqualTo: uid).where('seen', isEqualTo: false)
      .orderBy('timestamp', descending: true)
      .snapshots(includeMetadataChanges: true).listen((snapshot) {
        if (!_sessionIs(uid, generation)) return;
        _pendingActivities = snapshot.docs.length;
        _lastActivity = snapshot.docs.isEmpty ? null : {
          'type': snapshot.docs.first.data()['type'],
          'text': snapshot.docs.first.data()['text'],
          'uid': snapshot.docs.first.data()['fromUid'],
          'postId': snapshot.docs.first.data()['postId'],
        };
        notifyListeners();
        if (snapshot.metadata.isFromCache) return;
        final firstServerSnapshot = !initialized;
        final candidates = firstServerSnapshot ? snapshot.docs : snapshot.docChanges
          .where((change) => change.type != DocumentChangeType.removed).map((change) => change.doc);
        if (!snapshot.metadata.hasPendingWrites) initialized = true;
        for (final doc in candidates) {
          final data = doc.data();
          final at = data?['timestamp'];
          if (data == null || at is! Timestamp || !cursor.accept(doc.id, at.toDate(),
              fromCache: doc.metadata.isFromCache, pendingWrites: doc.metadata.hasPendingWrites,
              firstServerSnapshot: firstServerSnapshot)) { continue; }
          final type = switch (data['type']) {
            'like' => BannerType.like, 'comment' || 'reply' => BannerType.comment,
            'follow' => BannerType.follow, 'mention' => BannerType.mention,
            'story_new' => BannerType.story, _ => null,
          };
          if (type != null) _queueBannerWork(() => _submitBanner(uid, generation, 'activity:${doc.id}', type, data));
        }
      }, onError: (Object e) => debugPrint('Activities listener: $e'));
  }

  void startVisitsListener() {
    final uid = _auth.currentUser?.uid;
    if (_disposed || uid == null || _currentUid != uid || !_bannerReady || _visitsSub != null) return;
    final generation = _bannerGeneration;
    final cursor = BannerEventCursor(_bannerSessionStartedAt ?? DateTime.now());
    var initialized = false;
    _visitsSub = _firestore.collection('users').doc(uid).collection('visits')
      .where('isSeen', isEqualTo: false).orderBy('timestamp', descending: true)
      .snapshots(includeMetadataChanges: true).listen((snapshot) {
        if (!_sessionIs(uid, generation)) return;
        if (snapshot.metadata.isFromCache) return;
        final firstServerSnapshot = !initialized;
        final candidates = firstServerSnapshot ? snapshot.docs : snapshot.docChanges
          .where((change) => change.type != DocumentChangeType.removed).map((change) => change.doc);
        if (!snapshot.metadata.hasPendingWrites) initialized = true;
        for (final doc in candidates) {
          final data = doc.data();
          final at = data?['timestamp'];
          if (data == null || at is! Timestamp || !cursor.accept(doc.id, at.toDate(),
              fromCache: doc.metadata.isFromCache, pendingWrites: doc.metadata.hasPendingWrites,
              firstServerSnapshot: firstServerSnapshot)) { continue; }
          final version = at.microsecondsSinceEpoch;
          _queueBannerWork(() => _submitBanner(uid, generation,
            'visit:${doc.id}:$version', BannerType.visit, data));
        }
        if (!snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites) initialized = true;
      }, onError: (Object e) => debugPrint('Visits listener: $e'));
  }

    void startGlobalDeliveredListener() {
    final uid = _auth.currentUser?.uid;
    if (_disposed || uid == null || _currentUid != uid || _globalDeliveredSub != null) return;
    final generation = _bannerGeneration;
    _globalDeliveredSub = _firestore
        .collection('chat_rooms')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((roomsSnap) async {
      final userDoc = await UserDocuments.readable(_firestore, uid).get();
      if (!_sessionIs(uid, generation)) return;
      final bool allowRead = userDoc.data()?['showReadReceipts'] ?? true;
      for (var roomDoc in roomsSnap.docs) {
        _firestore
            .collection('chat_rooms')
            .doc(roomDoc.id)
            .collection('messages')
            .where('isDelivered', isEqualTo: false)
            .get()
            .then((msgSnap) {
          if (!_sessionIs(uid, generation) || msgSnap.docs.isEmpty) return;
          final batch = _firestore.batch();
          int c = 0;
          for (var d in msgSnap.docs) {
            final data = d.data();
            if (data['senderId'] == uid) continue;
            batch.update(d.reference, {'isDelivered': true, 'deliveredAt': FieldValue.serverTimestamp(), 'lockedGray': !allowRead});
            c++;
          }
          if (c > 0) batch.commit();
        });
      }
    });
  }

  void initialize() {
    if (_disposed || _bannerAuthSub != null) return;
    _bannerAuthSub = _auth.authStateChanges().listen((user) async {
      final uid = user?.uid;
      if (_disposed || (uid == _currentUid && uid != null)) return;
      final generation = ++_bannerGeneration;
      _bannerReady = false;
      _bannerSessionStartedAt = DateTime.now();
      _currentUid = uid;
      _bannerWork = Future.value();
      _followersSub?.cancel(); _followersSub = null;
      _activitiesSub?.cancel(); _activitiesSub = null;
      _followingSub?.cancel(); _followingSub = null;
      _visitsSub?.cancel(); _visitsSub = null;
      _globalDeliveredSub?.cancel(); _globalDeliveredSub = null;
      for (final sub in _friendStatusListeners.values) { sub.cancel(); }
      _friendStatusListeners.clear();
      _bannerUsers.clear(); _bannerUserFetchedAt.clear(); _verifiedBannerPosts.clear(); _blockedIds.clear();
      _pendingActivities = 0; _lastActivity = null;
      _pendingFollowRequests = 0; _lastFollower = null;
      _initialized = false; _lastKnownFollowersCount = 0;
      notifyListeners();
      await _bannerManager.bindUser(uid);
      if (uid == null || !_sessionIs(uid, generation)) return;
      await loadBlockedIds();
      if (!_sessionIs(uid, generation)) return;
      _bannerReady = true;
      debugPrint('[Banner] session_ready');
      _bannerManager.foregroundActivity = (payload) async {
        if (!_sessionIs(uid, generation)) return false;
        final id = payload['activityId']?.toString() ?? '';
        if (id.isEmpty) return false;
        try {
          final doc = await _firestore.collection('activities').doc(id).get();
          final data = doc.data();
          if (!_sessionIs(uid, generation) || data == null || data['toUid'] != uid) return false;
          final type = switch (data['type']) {
            'like' => BannerType.like, 'comment' || 'reply' => BannerType.comment,
            'follow' => BannerType.follow, 'mention' => BannerType.mention,
            _ => null,
          };
          if (type == null) return false;
          if (data['seen'] == true) return true;
          _queueBannerWork(() => _submitBanner(uid, generation, 'activity:$id', type, data));
          return true;
        } catch (_) { return false; }
      };
      startFollowRequestsListener(); startActivitiesListener();
      startActivityOnlineListener(); startVisitsListener(); startGlobalDeliveredListener();
      notifyListeners();
    });
  }

  void clearLastFollower() {
    _lastFollower = null;
    _pendingFollowRequests = 0;
    notifyListeners();
  }

  Future<void> clearActivities() async {
    await markAllActivitiesSeen(_auth.currentUser?.uid?? '');
  }

  // جديد: تعليم الكل مقروء
  Future<void> markAllActivitiesSeen(String uid) async {
    if (uid.isEmpty) return;

    final q = await _firestore
      .collection('activities')
      .where('toUid', isEqualTo: uid)
      .where('seen', isEqualTo: false)
      .get();

    if (q.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (var doc in q.docs) {
      batch.update(doc.reference, {'seen': true});
    }
    await batch.commit();

    _lastActivity = null;
    _pendingActivities = 0;
    notifyListeners();
  }

  void listenToFollowRequests(String uid) {
    if (uid != _auth.currentUser?.uid || uid != _currentUid) return;
    startFollowRequestsListener();
  }

  void refreshFollowRequests() {
    if (_currentUid!= null) {
      listenToFollowRequests(_currentUid!);
    }
    notifyListeners();
  }

  // [Tini]: فلترة الغرف المخفية والمؤرشفة زي تيك توك - ✅ معدل
  Stream<QuerySnapshot> getConversations(String uid) {
    return _firestore
      .collection('chat_rooms')
      .where('participants', arrayContains: uid)
      .orderBy('lastMessageTime', descending: true)
      .snapshots()
      .map((snapshot) {
      final docs = snapshot.docs.where((doc) {
        final data = doc.data();
        final deletedFor = Map<String, dynamic>.from(data['deletedFor']?? {});
        final archivedBy = List<String>.from(data['archivedBy']?? []);
        if (deletedFor[uid]== true || archivedBy.contains(uid)) return false;
        // [إضافة فقط - HARD BLOCK] - اخفي محادثات المحظورين
        final List parts = List.from(data['participants']?? []);
        for (var p in parts) {
          if (p!= uid && _blockedIds.contains(p.toString())) return false;
        }
        return true;
      }).toList();

      // ترتيب: المثبتين أول
      docs.sort((a, b) {
        final aData = a.data();
        final bData = b.data();
        final aPinned = Map<String, dynamic>.from(aData['pinned']?? {})[uid]?? false;
        final bPinned = Map<String, dynamic>.from(bData['pinned']?? {})[uid]?? false;
        if (aPinned &&!bPinned) return -1;
        if (!aPinned && bPinned) return 1;
        final aTime = aData['lastMessageTime'] as Timestamp?;
        final bTime = bData['lastMessageTime'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return _FakeQuerySnapshot(docs, snapshot.metadata, snapshot.docChanges);
    });
  }

  // [Tini]: جلب المحادثات المؤرشفة فقط - ✅ معدل
  Stream<QuerySnapshot> getArchivedConversations(String uid) {
    return _firestore
      .collection('chat_rooms')
      .where('archivedBy', arrayContains: uid)
      .snapshots()
      .map((snapshot) {
      final docs = snapshot.docs.where((doc) {
        final data = doc.data();
        final archivedBy = List<String>.from(data['archivedBy']?? []);
        final deletedFor = Map<String, dynamic>.from(data['deletedFor']?? {});
        final participants = List<String>.from(data['participants'] ?? []);
        return participants.contains(uid) && archivedBy.contains(uid) && deletedFor[uid]!= true;
      }).toList();
      docs.sort((a, b) {
        final ta = a.data()['lastMessageTime'] as Timestamp?;
        final tb = b.data()['lastMessageTime'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      return _FakeQuerySnapshot(docs, snapshot.metadata, snapshot.docChanges);
    });
  }

  // [Tini]: جلب عدد المحادثات المؤرشفة - ✅ معدل نهائي
  Future<int> getArchivedCount(String uid) async {
    final snap = await _firestore
      .collection('chat_rooms')
      .where('archivedBy', arrayContains: uid)
      .get(); // Fetch only archived rooms, not all conversations.

    final docs = snap.docs.where((doc) {
      final data = doc.data();
      final archivedBy = List<String>.from(data['archivedBy']?? []);
      final deletedFor = Map<String, dynamic>.from(data['deletedFor']?? {});
      final participants = List<String>.from(data['participants'] ?? []);
      return participants.contains(uid) && archivedBy.contains(uid) && deletedFor[uid]!= true; // ✅ فلترة يدوية
    }).toList();

    return docs.length;
  }

  Stream<List<ChatMessage>> messagesStream(String otherUid) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
    if (currentUid.isEmpty || otherUid.isEmpty) {
      return Stream.value([]);
    }
    final roomId = _getRoomId(currentUid, otherUid);
    return _firestore
      .collection('chat_rooms')
      .doc(roomId)
      .collection('messages')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((snap) {
      return snap.docs.map((d) {
        final data = d.data();
        final ts = data['timestamp'] as Timestamp?;
        return ChatMessage(
          id: d.id,
          senderId: data['senderId']?? '',
          text: data['text']?? '',
          type: data['type']?? 'text',
          mediaUrl: data['mediaUrl'],
          timestamp: ts?.toDate()?? DateTime.now(),
          reaction: data['reaction'],
          bubbleColor: data['bubbleColor'],
          replyTo: data['replyTo']!= null
            ? Map<String, dynamic>.from(data['replyTo'])
              : null,
          durationSeconds: data['durationSeconds'] as int?,
          isDelivered: data['isDelivered'] ?? false,
          isSeen: data['isSeen'] ?? false,
          viewOnce: data['viewOnce'] == true,
          viewedBy: List<String>.from(data['viewedBy'] ?? []),
          mediaDeleted: data['mediaDeleted'] == true,
        );
      }).toList();
    });
  }

  // [Tini]: التحقق من موافقة المستلم وخصوصية طلب المراسلة الأولى.
  // هذا الفحص لا يغيّر حالة الطلب ولا يمنع الرد ضمن محادثة بدأت بالفعل.
  // null = مسموح؛ غير null = سبب الرفض المحدد لهذه العملية فقط.
  Future<ChatFailureReason?> _firstMessageFailureReason({
    required String senderUid,
    required String receiverUid,
  }) async {
    try {
      // قراءة الخادم حتى لا نسمح بطلب جديد بناءً على إعداد مخزّن قديم.
      final receiverDoc = await UserDocuments.readable(_firestore, receiverUid)
          .get(const GetOptions(source: Source.server));
      final receiverData = receiverDoc.data();
      if (receiverData == null) {
        debugPrint('--- [MSG PRIVACY]: receiver account not found ---');
        return ChatFailureReason.accountUnavailable;
      }
      if (receiverData['allowMessageRequests'] != true) {
        debugPrint('--- [MSG PRIVACY]: message requests not allowed ---');
        return ChatFailureReason.requestsDisabled;
      }

      final String privacy = receiverData['messageRequestPrivacy'] ?? 'followers';
      if (privacy == 'all') return null;
      if (privacy == 'nobody') {
        debugPrint('--- [MSG PRIVACY]: nobody - blocked ---');
        return ChatFailureReason.nobody;
      }
      if (privacy == 'followers') {
        // "متابعوك" تعني أن المرسل يتابع المستلم، وليس العكس.
        final followerDoc = await _firestore.collection('users').doc(receiverUid)
            .collection('followers').doc(senderUid)
            .get(const GetOptions(source: Source.server));
        if (!followerDoc.exists) {
          debugPrint('--- [MSG PRIVACY]: sender is not a follower ---');
          return ChatFailureReason.followersOnly;
        }
        return null;
      }

      // لا نسمح بطلب جديد عند وجود قيمة خصوصية غير معروفة.
      debugPrint('--- [MSG PRIVACY]: unknown privacy setting: $privacy ---');
      return ChatFailureReason.privacyUnavailable;
    } catch (e) {
      // تعذّر التحقق لا يُعتبر موافقة، ولا يغيّر المحادثات الحالية.
      debugPrint('--- [MSG PRIVACY]: failed to verify first-message permission: $e ---');
      return ChatFailureReason.privacyUnavailable;
    }
  }

  Future<String> startChat({
    required String viewedUid,
    required String displayFullName,
    required String displayProfileImg,
    required bool isFriend,
    String? currentUserName,
    String? currentUserImg,
  }) async {
    final result = await startChatWithReason(
      viewedUid: viewedUid,
      displayFullName: displayFullName,
      displayProfileImg: displayProfileImg,
      isFriend: isFriend,
      currentUserName: currentUserName,
      currentUserImg: currentUserImg,
    );
    return result.value ?? '';
  }

  // النسخة التفصيلية للمسارات التي تحتاج عرض سبب منع فتح المحادثة.
  Future<ChatActionResult<String>> startChatWithReason({
    required String viewedUid,
    required String displayFullName,
    required String displayProfileImg,
    required bool isFriend,
    String? currentUserName,
    String? currentUserImg,
  }) async {
    try {
      final String currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
      if (currentUid.isEmpty) return const ChatActionResult<String>.failure(ChatFailureReason.notAuthenticated);
      // [إضافة فقط - HARD BLOCK] - ممنوع تبدأ شات مع محظور
      if (_blockedIds.contains(viewedUid)) {
        debugPrint('--- [HARD BLOCK]: blocked user cannot start chat ---');
        return const ChatActionResult<String>.failure(ChatFailureReason.blocked);
      }

      final List<String> sortedIds = [currentUid, viewedUid]..sort();
      final roomId = sortedIds.join('_');
      final roomRef = _firestore.collection('chat_rooms').doc(roomId);
      final doc = await roomRef.get();

      // التحقق مطلوب عند بدء أول رسالة فقط، وليس عند فتح محادثة جارية.
      final bool hasFirstMessage = doc.exists &&
          (doc.data()?['lastMessageSenderId'] ?? '').toString().isNotEmpty;
      if (!hasFirstMessage) {
        final failureReason = await _firstMessageFailureReason(
          senderUid: currentUid, receiverUid: viewedUid);
        if (failureReason != null) return ChatActionResult<String>.failure(failureReason);
      }

      final oldRoom = doc.data();
      final oldInfo = Map<String, dynamic>.from(oldRoom?['participantsInfo'] ?? {});
      final ownInfo = Map<String, dynamic>.from(oldInfo[currentUid] ?? {});
      final peerInfo = Map<String, dynamic>.from(oldInfo[viewedUid] ?? {});
      String myName = currentUserName?.isNotEmpty == true
          ? currentUserName! : (ownInfo['name'] ?? '').toString();
      String myImg = currentUserImg?.isNotEmpty == true
          ? currentUserImg! : (ownInfo['profileImg'] ?? '').toString();

      if (myName.isEmpty || !ownInfo.containsKey('profileImg')) {
        final myDoc = await UserDocuments.readable(_firestore, currentUid).get();
        final myData = myDoc.data() ?? {};
        myName = myName.isEmpty ? (myData['fullName'] ?? myData['username'] ?? 'مستخدم').toString() : myName;
        myImg = myImg.isEmpty ? (myData['profileImg'] ?? '').toString() : myImg;
      }

      // [Tini Fix]: لازم الاثنين نفس قيمة isFriend عشان منطق القفل يزبط
      final Map<String, dynamic> data = {
        'participants': sortedIds,
        'participantsInfo': {
          currentUid: {
            'name': myName,
            'profileImg': myImg,
            'isFriend': isFriend, // ← تم التعديل: نفس قيمة الطرف الثاني
          },
          viewedUid: {
            'name': displayFullName,
            'profileImg': displayProfileImg,
            'isFriend': isFriend, // هو اللي بيتحدد حسب هو صديقي ولا لأ
          },
        },
      };

      if (!doc.exists) {
        // [Tini]: نظام طلبات الرسائل - لو مش صديق = طلب
        final bool isRequest =!isFriend;
        data.addAll({
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageSenderId': '',
          'unreadCount': {
            currentUid: 0,
            viewedUid: 0,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'isRequest': isRequest,
          'canSendMore': {
            currentUid: true, // صاحب الطلب بقدر يبعت رسالة وحدة
            viewedUid: true, // ← تم التعديل: المستقبل دايماً بقدر يرد
          },
          'archivedBy': [], // ✅ جديد: نضيف الليست فاضية
        });
        debugPrint('--- [Tini]: تم إنشاء غرفة جديدة isRequest: $isRequest | isFriend: $isFriend ---');
      }

      // Opening an unchanged existing room must not write to Firestore.
      final unchanged = doc.exists &&
          ownInfo['name'] == myName &&
          ownInfo['profileImg'] == myImg &&
          ownInfo['isFriend'] == isFriend &&
          peerInfo['name'] == displayFullName &&
          peerInfo['profileImg'] == displayProfileImg &&
          peerInfo['isFriend'] == isFriend;
      if (!unchanged) {
        await roomRef.set(data, SetOptions(merge: true));
        notifyListeners();
      }
      return ChatActionResult<String>.success(roomId);
    } on FirebaseException catch (e) {
      debugPrint('Error starting chat: $e');
      return ChatActionResult<String>.failure(e.code == 'permission-denied'
          ? ChatFailureReason.permissionDenied : ChatFailureReason.technicalError);
    } catch (e) {
      debugPrint('Error starting chat: $e');
      return const ChatActionResult<String>.failure(ChatFailureReason.technicalError);
    }
  }

  Future<bool> sendMessage({
    required String roomId,
    required String senderId,
    required String receiverId,
    required String type,
    String? text,
    String? mediaUrl,
    required bool isFriend,
    Map<String, dynamic>? replyTo,
    int? durationSeconds,
    Map<String, dynamic>? extraData,
    bool viewOnce = false, // [عرض مرة واحدة - الدردشات الخاصة]
  }) async {
    final result = await sendMessageWithReason(
      roomId: roomId,
      senderId: senderId,
      receiverId: receiverId,
      type: type,
      text: text,
      mediaUrl: mediaUrl,
      isFriend: isFriend,
      replyTo: replyTo,
      durationSeconds: durationSeconds,
      extraData: extraData,
      viewOnce: viewOnce,
    );
    return result.isSuccess;
  }

  // النسخة التفصيلية للمسارات التي تحتاج عرض سبب فشل إرسال الرسالة.
  Future<ChatActionResult<bool>> sendMessageWithReason({
    required String roomId,
    required String senderId,
    required String receiverId,
    required String type,
    String? text,
    String? mediaUrl,
    required bool isFriend,
    Map<String, dynamic>? replyTo,
    int? durationSeconds,
    Map<String, dynamic>? extraData,
    bool viewOnce = false, // [عرض مرة واحدة - الدردشات الخاصة]
  }) async {
    try {
      final roomRef = _firestore.collection('chat_rooms').doc(roomId);
      final roomSnap = await roomRef.get();
      if (!roomSnap.exists) return const ChatActionResult<bool>.failure(ChatFailureReason.roomNotFound);

      final roomData = roomSnap.data()?? {};
      // [إضافة فقط - HARD BLOCK] - ممنوع ترسل لمحظور
      if (_blockedIds.contains(receiverId)) {
        debugPrint('--- [HARD BLOCK]: cannot send to blocked ---');
        return const ChatActionResult<bool>.failure(ChatFailureReason.blocked);
      }

      // [Tini]: قراءة حالة الغرفة للفحص المسبق - الحماية الحقيقية بالقواعد
      final participantsInfo = Map<String, dynamic>.from(roomData['participantsInfo']?? {});
      final senderInfo = Map<String, dynamic>.from(participantsInfo[senderId]?? {});
      final bool actualIsFriend = senderInfo['isFriend']?? false;

      final bool isRequest = roomData['isRequest']?? false;
      final Map<String, dynamic> canSendMoreMap = Map<String, dynamic>.from(roomData['canSendMore']?? {});
      final bool canSenderSend = canSendMoreMap[senderId]?? true;
      final String lastMessageSenderId = roomData['lastMessageSenderId']?? '';

      // حتى لو كانت الغرفة موجودة مسبقاً دون رسائل، يجب التحقق قبل أول إرسال.
      if (lastMessageSenderId.isEmpty) {
        final failureReason = await _firstMessageFailureReason(
          senderUid: senderId, receiverUid: receiverId);
        if (failureReason != null) return ChatActionResult<bool>.failure(failureReason);
      }

      // فحص مسبق عشان الـ UI بس - لو رجع false القواعد رح تمنع الكتابة كمان
      if (isRequest &&!canSenderSend &&!actualIsFriend) {
        debugPrint('--- [Tini]: ممنوع الإرسال، بانتظار رد الطرف الآخر ---');
        return const ChatActionResult<bool>.failure(ChatFailureReason.waitingForReply);
      }

      // [عرض مرة واحدة] لا نسمح بتطبيق الخيار على رسائل غير الصور والفيديو.
      if (viewOnce && type != 'image' && type != 'video') {
        return const ChatActionResult<bool>.failure(ChatFailureReason.invalidMedia);
      }
      if (viewOnce && (mediaUrl == null || mediaUrl.isEmpty)) {
        return const ChatActionResult<bool>.failure(ChatFailureReason.invalidMedia);
      }

      String preview = '';
      if (type == 'text') {
        preview = text?? '';
      } else if (type == 'album') {
        preview = '📷 صور وفيديوهات';
      } else if (type == 'image') {
        preview = '📷 صورة';
      } else if (type == 'video') {
        preview = '🎥 فيديو';
      } else if (type == 'video_note') {
        preview = '⭕ ملاحظة فيديو';
      } else if (type == 'audio') {
        preview = '🎤 رسالة صوتية';
      } else if (type == 'location') {
        preview = '📍 موقع';
      } else if (type == 'document') {
        preview = '📄 مستند';
      } else if (type == 'profile_share') {
        preview = 'شارك ملف شخصي';
      }

      if (viewOnce) preview = type == 'image' ? '📷 صورة لمرة واحدة' : '🎥 فيديو لمرة واحدة';

      final messageData = <String, dynamic>{
        'senderId': senderId,
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
        'isDelivered': false, // ✅ NEW - صح واحد رمادي
        'isSeen': false, // ✅ NEW - صحين ازرق
        'seen': false,
      };
      if (text!= null) messageData['text'] = text;
      if (mediaUrl!= null) messageData['mediaUrl'] = mediaUrl;
      if (replyTo!= null) messageData['replyTo'] = replyTo;
      if (durationSeconds!= null) messageData['durationSeconds'] = durationSeconds;
      if (extraData!= null) messageData.addAll(extraData!);
      // [عرض مرة واحدة] نكتب الحقول بعد extraData حتى لا يمكن تجاوزها بالخطأ.
      if (viewOnce) {
        messageData['viewOnce'] = true;
        messageData['viewedBy'] = <String>[];
        messageData['mediaDeleted'] = false;
        messageData.remove('thumbnailUrl');
      }

      final batch = _firestore.batch();

      final msgRef = roomRef.collection('messages').doc();
      batch.set(msgRef, messageData);

      final Map<String, dynamic> updateData = {
        'lastMessage': preview,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
        'unreadCount.$receiverId': FieldValue.increment(1),
        'deletedFor.$receiverId': false, // ← [Tini]: ترجع الغرفة تظهر للمستقبل زي تيك توك
        'archivedBy': FieldValue.arrayRemove([receiverId]), // ✅ تم التعديل: طلعها من الأرشيف لو اجتها رسالة
      };

      // [Tini]: تحديث حالة الطلب - القواعد بتحمي لو نسيت هون
      if (isRequest) {
        // 1. لو مش صديق وهاي أول رسالة بالغرفة = اقفل عليه بعدها
        if (!actualIsFriend && lastMessageSenderId == '') {
          updateData['canSendMore.$senderId'] = false;
          debugPrint('--- [Tini]: قفلنا على $senderId بعد أول رسالة ---');
        }

        // 2. لو فيه رسالة سابقة وصاحبها مش المرسل الحالي = الطرف الثاني رد
        if (lastMessageSenderId!= '' && lastMessageSenderId!= senderId) {
          updateData['isRequest'] = false;
          updateData['canSendMore.$senderId'] = true;
          updateData['canSendMore.$receiverId'] = true;
          debugPrint('--- [Tini]: فتحنا الشات - الطرف الثاني رد ---');
        }
      }

      batch.update(roomRef, updateData);

      // لو القواعد رفضت، هاد السطر رح يرمي Exception
      await batch.commit();

            // [ACTIVITY] تسجيل رسالة جديدة - مع المضمون
      try {
        final senderDoc = await UserDocuments.readable(_firestore, senderId).get();
        final senderName = senderDoc.data()?['fullName']?? senderDoc.data()?['username']?? 'مستخدم';
        String bodyText = preview;
        if (type == 'text' && text != null && text.isNotEmpty) {
          bodyText = text;
        }
                await _firestore.collection('activities').add({
          'toUid': receiverId,
          'fromUid': senderId,
          'type': 'message',
          'text': bodyText,
          'postId': roomId,
          'mediaUrl': viewOnce ? '' : (mediaUrl ?? ""), // <-- جديد
          'messageType': type, // <-- جديد
          'thumbnailUrl': viewOnce ? '' : (extraData?['thumbnailUrl'] ?? ''), // <-- سطر جديد
          'timestamp': FieldValue.serverTimestamp(),
          'seen': false,
        });
      } catch (e) {}

      notifyListeners();
      return const ChatActionResult<bool>.success(true);
    } on FirebaseException catch (e) {
      // لو القواعد رفضت الكتابة
      if (e.code == 'permission-denied') {
        debugPrint('--- [Tini]: القواعد منعت الإرسال - permission-denied ---');
      } else {
        debugPrint('Error sending message: $e');
      }
      return ChatActionResult<bool>.failure(e.code == 'permission-denied'
          ? ChatFailureReason.permissionDenied : ChatFailureReason.technicalError);
    } catch (e) {
      debugPrint('Error sending message: $e');
      return const ChatActionResult<bool>.failure(ChatFailureReason.technicalError);
    }
  }

  // ===== [عرض مرة واحدة - الدردشات الخاصة] =====
  /// يحجز فتح الوسيط للمستلم مرة واحدة فقط، حتى لو حاول فتحه من جهازين.
  /// يتطلب تحديث قواعد Firestore للسماح بتعديل viewedBy بشروط صارمة.
  Future<bool> claimViewOnce({required String roomId, required String messageId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final roomRef = _firestore.collection('chat_rooms').doc(roomId);
    final msgRef = roomRef.collection('messages').doc(messageId);
    try {
      return await _firestore.runTransaction<bool>((tx) async {
        final roomSnap = await tx.get(roomRef);
        if (!roomSnap.exists) return false;
        final participants = List<String>.from(roomSnap.data()?['participants'] ?? []);
        if (participants.length != 2 || !participants.contains(uid)) return false;

        final msgSnap = await tx.get(msgRef);
        if (!msgSnap.exists) return false;
        final data = msgSnap.data() ?? <String, dynamic>{};
        if (data['viewOnce'] != true || data['senderId'] == uid) return false;
        if (data['type'] != 'image' && data['type'] != 'video') return false;
        if (data['mediaDeleted'] == true) return false;
        if ((data['mediaUrl'] ?? '').toString().isEmpty) return false;
        final viewed = List<String>.from(data['viewedBy'] ?? []);
        if (viewed.contains(uid)) return false;

        tx.update(msgRef, {'viewedBy': FieldValue.arrayUnion([uid])});
        return true;
      });
    } catch (e) {
      debugPrint('claimViewOnce private error: $e');
      return false;
    }
  }

  /// يحذف وسيط المرة الواحدة بعد أن يفتحه المستلم ويغلق العارض.
  /// يستحسن نقل التنظيف لاحقاً إلى الخادم لضمان التنفيذ إذا انقطع الاتصال.
  Future<void> cleanupViewOnce({required String roomId, required String messageId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final roomRef = _firestore.collection('chat_rooms').doc(roomId);
      final roomSnap = await roomRef.get();
      if (!roomSnap.exists) return;
      final participants = List<String>.from(roomSnap.data()?['participants'] ?? []);
      if (participants.length != 2 || !participants.contains(uid)) return;

      final msgRef = roomRef.collection('messages').doc(messageId);
      final msgSnap = await msgRef.get();
      if (!msgSnap.exists) return;
      final data = msgSnap.data() ?? <String, dynamic>{};
      if (data['viewOnce'] != true || data['senderId'] == uid) return;
      if (data['mediaDeleted'] == true) return;
      if (!List<String>.from(data['viewedBy'] ?? []).contains(uid)) return;
      final url = (data['mediaUrl'] ?? '').toString();
      if (url.isEmpty) return;

      await _r2.deleteByUrl(url);
      await msgRef.update({'mediaUrl': null, 'mediaDeleted': true});
    } catch (e) {
      debugPrint('cleanupViewOnce private error: $e');
    }
  }

  final Map<String, Future<void>> _privateReadJobs = {};
  final Set<String> _privateReadAgain = {};

  Future<void> markAsRead(String roomId, String uid) {
    final key = '$uid/$roomId';
    final running = _privateReadJobs[key];
    if (running != null) {
      _privateReadAgain.add(key);
      return running;
    }
    final operation = _markPrivateReadUntilCaughtUp(roomId, uid, key);
    _privateReadJobs[key] = operation;
    return operation.whenComplete(() {
      _privateReadJobs.remove(key);
      _privateReadAgain.remove(key);
    });
  }

  Future<void> _markPrivateReadUntilCaughtUp(
      String roomId, String uid, String key) async {
    do {
      _privateReadAgain.remove(key);
      await _markPrivateReadOnce(roomId, uid);
    } while (_privateReadAgain.remove(key));
  }

  Future<void> _markPrivateReadOnce(String roomId, String uid) async {
    try {
      final roomRef = _firestore.collection('chat_rooms').doc(roomId);
      await roomRef.update({'unreadCount.$uid': 0});
      final userDoc = await UserDocuments.readable(_firestore, uid).get();
      final bool allowRead = userDoc.data()?['showReadReceipts'] ?? true;

      final last = await TiniChatReadCheckpoint.get('read-private', roomId, uid);
      final query = TiniChatReadCheckpoint.since(
          roomRef.collection('messages').orderBy('timestamp'), last);
      QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
      Timestamp? mostRecent = last;
      var allFromServer = true;
      while (true) {
        var pageQuery = query.limit(200);
        if (cursor != null) pageQuery = pageQuery.startAfterDocument(cursor);
        final page = await pageQuery.get();
        if (page.metadata.isFromCache) allFromServer = false;
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        var count = 0;
        for (final doc in page.docs) {
          final data = doc.data();
          final ts = data['timestamp'];
          if (ts is Timestamp &&
              (mostRecent == null || ts.compareTo(mostRecent) > 0)) {
            mostRecent = ts;
          }
          if (data['senderId'] == uid || data['lockedGray'] == true) continue;
          if (allowRead) {
            if (data['isSeen'] == true) continue;
            batch.update(doc.reference, {
              'isDelivered': true,
              'isSeen': true,
              'seen': true,
              'deliveredAt': FieldValue.serverTimestamp(),
              'seenAt': FieldValue.serverTimestamp(),
            });
          } else {
            if (data['isDelivered'] == true) continue;
            batch.update(doc.reference, {
              'isDelivered': true,
              'deliveredAt': FieldValue.serverTimestamp(),
            });
          }
          count++;
        }
        if (count > 0) await batch.commit();
        cursor = page.docs.last;
        if (page.docs.length < 200) break;
      }
      if (allFromServer) {
        await TiniChatReadCheckpoint.save('read-private', roomId, uid, mostRecent);
        await TiniChatReadCheckpoint.save('delivered-private', roomId, uid, mostRecent);
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Error marking as read: $error');
    }
  }

  // ✅ NEW - للتسليم الفوري ✓✓ رمادي وانت اونلاين حتى بدون فتح الشات
  Future<void> markAsDelivered(String roomId, String uid) async {
    try {
      final roomRef = _firestore.collection('chat_rooms').doc(roomId);
      final last = await TiniChatReadCheckpoint.get('delivered-private', roomId, uid);
      final query = TiniChatReadCheckpoint.since(
          roomRef.collection('messages').orderBy('timestamp'), last);
      QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
      Timestamp? mostRecent = last;
      var allFromServer = true;
      while (true) {
        var pageQuery = query.limit(200);
        if (cursor != null) pageQuery = pageQuery.startAfterDocument(cursor);
        final page = await pageQuery.get();
        if (page.metadata.isFromCache) allFromServer = false;
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        var count = 0;
        for (final doc in page.docs) {
          final data = doc.data();
          final ts = data['timestamp'];
          if (ts is Timestamp &&
              (mostRecent == null || ts.compareTo(mostRecent) > 0)) {
            mostRecent = ts;
          }
          if (data['senderId'] == uid || data['isDelivered'] == true) continue;
          batch.update(doc.reference, {
            'isDelivered': true,
            'deliveredAt': FieldValue.serverTimestamp(),
          });
          count++;
        }
        if (count > 0) await batch.commit();
        cursor = page.docs.last;
        if (page.docs.length < 200) break;
      }
      if (allFromServer) {
        await TiniChatReadCheckpoint.save('delivered-private', roomId, uid, mostRecent);
      }
    } catch (error) {
      debugPrint('Error marking as delivered: $error');
    }
  }

  Future<void> updateParticipantInfo(String roomId, String uid, Map<String, dynamic> info) async {
    try {
      await _firestore.collection('chat_rooms').doc(roomId).update({
        'participantsInfo.$uid': info,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating participant info: $e');
    }
  }

  // [Tini]: اخفاء غرف الشات من عندي فقط زي تيك توك
  Future<void> hideChatRooms(List<String> roomIds) async {
    if (roomIds.isEmpty) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final batch = _firestore.batch();
      for (final roomId in roomIds) {
        final roomRef = _firestore.collection('chat_rooms').doc(roomId);
        batch.update(roomRef, {
          'deletedFor.$uid': true, // ← هاي اللي بتخفيها من عندك
          'unreadCount.$uid': 0,
        });
      }
      await batch.commit();
      debugPrint('--- [Tini]: تم اخفاء الغرف من عندي ---');
    } catch (e) {
      debugPrint('Error hiding chat rooms: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // [Tini]: تثبيت/إلغاء تثبيت محادثة - حسب وقت التثبيت
  Future<void> pinChat(String roomId, bool pin) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore.collection('chat_rooms').doc(roomId).update({
        'pinned.$uid': pin,
        'pinnedAt.$uid': pin? FieldValue.serverTimestamp() : FieldValue.delete(),
      });
      debugPrint('--- [Tini]: ${pin? 'تثبيت' : 'إلغاء تثبيت'} الغرفة $roomId ---');
      notifyListeners();
    } catch (e) {
      debugPrint('Error pin chat: $e');
    }
  }

  // [Tini]: أرشفة/إلغاء أرشفة محادثة - ✅ معدل
  Future<void> archiveChat(String roomId, bool archive) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore.collection('chat_rooms').doc(roomId).update({
        'archivedBy': archive
          ? FieldValue.arrayUnion([uid]) // ✅ ضيف uid للستة
            : FieldValue.arrayRemove([uid]), // ✅ احذف uid من الستة
        'unreadCount.$uid': 0,
      });
      debugPrint('--- [Tini]: ${archive? 'أرشفة' : 'إلغاء أرشفة'} الغرفة $roomId ---');
      notifyListeners();
    } catch (e) {
      debugPrint('Error archive chat: $e');
    }
  }

  // [Tini]: كتم/إلغاء كتم محادثة - حل اكيد
  Future<void> muteChat(String roomId, bool mute) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final roomRef = _firestore.collection('chat_rooms').doc(roomId);
      if (mute) {
        await roomRef.set({
          'muted': {uid: true}
        }, SetOptions(merge: true));
      } else {
        await roomRef.update({
          'muted.$uid': FieldValue.delete(),
        });
      }
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('muted_rooms')?? [];
      if (mute) {
        if (!list.contains(roomId)) list.add(roomId);
      } else {
        list.remove(roomId);
      }
      await prefs.setStringList('muted_rooms', list);
      debugPrint('--- [Tini]: ${mute? 'كتم' : 'إلغاء كتم'} الغرفة $roomId ---');
      notifyListeners();
    } catch (e) {
      debugPrint('Error mute chat: $e');
    }
  }

  // [Tini]: حذف غرف الشات مع الميديا - خليناها للادمن بس
  Future<void> deleteChatRooms(List<String> roomIds) async {
    if (roomIds.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      for (final roomId in roomIds) {
        final roomRef = _firestore.collection('chat_rooms').doc(roomId);

        // 1. جيب كل المسجات
        final messagesSnap = await roomRef.collection('messages').get();

                // 2. احذف الميديا من R2
        final r2 = R2Service();
        for (final msgDoc in messagesSnap.docs) {
          final data = msgDoc.data();
          final mediaUrl = data['mediaUrl'] as String?;
          if (mediaUrl!= null && mediaUrl.isNotEmpty) {
            try {
              await r2.deleteByUrl(mediaUrl);
            } catch (e) {
              debugPrint('Failed to delete media from R2: $mediaUrl - $e');
            }
          }
        }

        // 3. احذف كل المسجات batch
        final batch = _firestore.batch();
        for (final msgDoc in messagesSnap.docs) {
          batch.delete(msgDoc.reference);
        }
        await batch.commit();

        // 4. احذف الغرفة نفسها
        await roomRef.delete();
        debugPrint('--- [Tini]: تم حذف الغرفة $roomId مع الميديا ---');
      }
    } catch (e) {
      debugPrint('Error deleting chat rooms: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void startActivityOnlineListener() {
    final uid = _auth.currentUser?.uid;
    if (_disposed || uid == null || _currentUid != uid || _followingSub != null) return;
    final generation = _bannerGeneration;
    var followingVersion = 0;
    _followingSub = _firestore.collection('users').doc(uid).collection('following').snapshots().listen((snap) async {
      final version = ++followingVersion;
      bool valid() => _sessionIs(uid, generation) && version == followingVersion;
      if (!valid()) return;
      for (final sub in _friendStatusListeners.values) { sub.cancel(); }
      _friendStatusListeners.clear();
      final friends = <String>[];
      for (final doc in snap.docs) {
        if (doc.id == uid) continue;
        try {
          final follower = await _firestore.collection('users').doc(uid).collection('followers').doc(doc.id).get();
          if (!valid()) return;
          if (follower.exists) friends.add(doc.id);
        } catch (error) {
          if (!valid()) return;
          debugPrint('Friend status unavailable: $error');
        }
      }
      for (var i = 0; i < friends.length; i += 10) {
        final batch = friends.skip(i).take(10).toList();
        final statuses = <String, bool>{};
        var initialized = false;
        final sub = _firestore.collection('public_profiles')
          .where(FieldPath.documentId, whereIn: batch)
          .snapshots(includeMetadataChanges: true).listen((snapshot) {
            if (!valid() || (initialized && snapshot.metadata.isFromCache)) return;
            for (final doc in snapshot.docs) {
              final data = doc.data();
              final online = data['isOnline'] == true;
              final previous = statuses[doc.id];
              statuses[doc.id] = online;
              if (!initialized || snapshot.metadata.isFromCache || doc.metadata.hasPendingWrites || previous != false || !online) continue;
              final now = DateTime.now();
              final day = now.toIso8601String().split('T').first;
              final actor = doc.id;
              _queueBannerWork(() async {
                if (!valid() || isBlocked(actor)) return;
                // Persistent event identity enforces once per friend per calendar day.
                await _submitBanner(uid, generation, 'online:$actor:$day', BannerType.activity,
                  {...data, 'fromUid': actor, 'timestamp': Timestamp.fromDate(now)});
              });
            }
            if (!snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites) initialized = true;
          }, onError: (Object e) => debugPrint('Online listener: $e'));
        _friendStatusListeners[batch.join('_')] = sub;
      }
    }, onError: (Object e) => debugPrint('Following listener: $e'));
  }

  @override
  void dispose() {
    _disposed = true;
    _bannerGeneration++;
    _bannerAuthSub?.cancel();
    unawaited(_bannerManager.bindUser(null));
    _followersSub?.cancel();
    _activitiesSub?.cancel();
    _followingSub?.cancel();
    _visitsSub?.cancel();
    _globalDeliveredSub?.cancel();
    for (var sub in _friendStatusListeners.values) {
      sub.cancel();
    }
    _friendStatusListeners.clear();
    super.dispose();
  }
}

// [Tini]: كلاس مساعد لفلترة الـ Snapshot - تم تصليح العداد فقط
class _FakeQuerySnapshot implements QuerySnapshot {
  final List<QueryDocumentSnapshot> _docs;
  @override
  final SnapshotMetadata metadata;
  @override
  final List<DocumentChange> docChanges;

  _FakeQuerySnapshot(this._docs, this.metadata, this.docChanges);

  @override
  List<QueryDocumentSnapshot> get docs => _docs;

  @override
  int get size => _docs.length;
}