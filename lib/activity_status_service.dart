import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_model.dart';

class ActivityStatusService with WidgetsBindingObserver {
  static final ActivityStatusService _instance = ActivityStatusService._internal();
  factory ActivityStatusService() => _instance;
  ActivityStatusService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Timer? _heartbeatTimer;
  Timer? _backgroundTimer;
  bool _isInitialized = false;
  bool _isActivityEnabled = true;

  String? get _uid => _auth.currentUser?.uid;

    Future<void> init() async {
    if (_isInitialized) return;
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
    if (_uid != null) {
      try {
        final doc = await _firestore.collection('users').doc(_uid).get(
          const GetOptions(source: Source.server),
        );
        _isActivityEnabled = doc.data()?['showActivityStatus'] ?? true;
      } catch (_) {
        _isActivityEnabled = true;
      }
    }
    if (_isActivityEnabled) {
      await setOnline();
      startHeartbeat();
    }
  }

  void disposeService() {
    WidgetsBinding.instance.removeObserver(this);
    stopHeartbeat();
    _backgroundTimer?.cancel();
    _isInitialized = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_uid == null) return;
    if (!_isActivityEnabled) return;

    if (state == AppLifecycleState.resumed) {
      _backgroundTimer?.cancel();
      setOnline();
      startHeartbeat();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _backgroundTimer?.cancel();
      setOffline();
      stopHeartbeat();
    }
  }

  Future<void> setOnline() async {
    if (_uid == null) return;
    if (!_isActivityEnabled) return;
    try {
      await _firestore.collection('users').doc(_uid).set({
        
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('ActivityStatus Error setOnline: $e');
    }
  }

  Future<void> setOffline() async {
    if (_uid == null) return;
    try {
      await _firestore.collection('users').doc(_uid).set({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('ActivityStatus Error setOffline: $e');
    }
  }

  void startHeartbeat() {
    if (!_isActivityEnabled) return;
    stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_uid == null) return;
      if (!_isActivityEnabled) return;
      try {
        await _firestore.collection('users').doc(_uid).update({
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
        });
      } catch (e) {
        debugPrint('Heartbeat Error: $e');
      }
    });
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // الأساسي - يشتغل مع UserModel يلي انت عامله (DateTime)
  static String formatLastSeen(DateTime? lastSeen, bool isOnline) {
    if (isOnline) return 'نشط الآن';
    if (lastSeen == null) return 'غير متصل';

    final now = DateTime.now();
    final diff = now.difference(lastSeen);

        if (diff.inMinutes < 1) return 'آخر ظهور منذ لحظات';
    if (diff.inMinutes == 1) return 'آخر ظهور منذ دقيقة';
    if (diff.inMinutes < 60) return 'آخر ظهور منذ ${diff.inMinutes} دقائق';
    if (diff.inHours == 1) return 'آخر ظهور منذ ساعة';
    if (diff.inHours < 24) return 'آخر ظهور منذ ${diff.inHours} ساعات';
    if (diff.inDays == 1) return 'آخر ظهور منذ يوم';
    if (diff.inDays < 7) return 'آخر ظهور منذ ${diff.inDays} أيام';
    return 'آخر ظهور منذ ${diff.inDays ~/ 7} أسابيع';
  }

  // نسخة ثانية للاستخدام المباشر من Firestore بقلب profile_screen و follow_list_screen
  static String formatLastSeenFromTimestamp(Timestamp? lastSeen, bool isOnline) {
    if (lastSeen == null) return formatLastSeen(null, isOnline);
    return formatLastSeen(lastSeen.toDate(), isOnline);
  }

  // فحص الخصوصية المتبادلة - نسخة bool
  static bool canViewStatus({
    required bool myShowActivity,
    required bool targetShowActivity,
  }) {
    if (!myShowActivity) return false;
    if (!targetShowActivity) return false;
    return true;
  }

  // فحص الخصوصية المتبادلة - نسخة UserModel جاهزة لمشروعك
static bool canViewStatusForUsers(UserModel myUser, UserModel targetUser) {
  if (!myUser.showActivityStatus) return false;
  if (!targetUser.showActivityStatus) return false;
  return true;
}

// جديد: فحص هل اصدقاء - متابعة متبادلة
static Future<bool> isMutualFriend(String myUid, String otherUid) async {
  if (myUid == otherUid) return true;
  try {
    final myFollowingDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .collection('following')
        .doc(otherUid)
        .get();
    if (!myFollowingDoc.exists) return false;

    final otherFollowingDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(otherUid)
        .collection('following')
        .doc(myUid)
        .get();
    
    return otherFollowingDoc.exists;
  } catch (e) {
    return false;
  }
}

      Future<void> setShowActivityStatus(bool show, String uid) async {  // ← ضفنا String uid هون
  // احذف السطرين هدول:
  // final uid = _auth.currentUser?.uid;
  // if (uid == null) return;
  
  try {
    stopHeartbeat();
    _backgroundTimer?.cancel();
    if (show) {
      await _firestore.collection('users').doc(uid).set({
        'showActivityStatus': true,
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _isActivityEnabled = true;
      _isInitialized = true;
      WidgetsBinding.instance.addObserver(this);
      startHeartbeat();
    } else {
      await _firestore.collection('users').doc(uid).set({
        'showActivityStatus': false,
      }, SetOptions(merge: true));
      await _firestore.collection('users').doc(uid).set({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _isActivityEnabled = false;
      _isInitialized = false;
      try { WidgetsBinding.instance.removeObserver(this); } catch (_){}
    }
  } catch (e) {
    debugPrint('ERROR $e');
    rethrow;
  }
}
}