import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';

class CrownProvider extends ChangeNotifier with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // السقف الجديد
  static const int maxBid = 10000;

  // بيانات العرش
  String? _currentKingUid;
  String? _currentKingName;
  String? _currentKingAvatar;
  int _currentBid = 0;
  Timestamp? _auctionEndsAt;
  bool _isLoading = false;

  // جديد: قفل العرش
  bool _isThroneLocked = false;
  Timestamp? _lockEndTime;

  // بيانات المستخدم الحالي
  int _myPoints = 0;
  String _myCrownNumber = '';

  StreamSubscription? _throneSub;
  StreamSubscription? _authSub;
  StreamSubscription? _userSub;
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
  String? auctionId;
  String? leaderUid;
  String? leaderName;
  String? leaderAvatar;
  String? coronationId;
  String? lastError;
  bool _ready = false;
  bool _enabled = false;
  bool _disposed = false;
  Duration _serverOffset = Duration.zero;
  String? _pendingRequest;
  String? _pendingAuction;
  int? _pendingAmount;
  int _reserved = 0;
  int get reservedPoints => _reserved;
  bool get hasPendingBid => _pendingRequest != null;
  bool get enabled => _ready && _enabled;
  String? get availabilityMessage => !_ready
      ? 'نظام العرش بانتظار تفعيل السيرفر'
      : !_enabled
      ? 'المزايدات غير مفعلة حالياً'
      : null;
  DateTime get serverNow => DateTime.now().add(_serverOffset);
  bool get canBid =>
      _ready &&
      _enabled &&
      !_isThroneLocked &&
      _auctionEndsAt != null &&
      _auctionEndsAt!.toDate().isAfter(serverNow);
  String? get displayUid =>
      (!_ready || _isThroneLocked) ? _currentKingUid : leaderUid;
  String? get displayName =>
      (!_ready || _isThroneLocked) ? _currentKingName : leaderName;
  String? get displayAvatar =>
      (!_ready || _isThroneLocked) ? _currentKingAvatar : leaderAvatar;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> sync() async {
    if (_auth.currentUser == null) return;
    try {
      final start = DateTime.now();
      final result = await _functions.httpsCallable('syncThrone').call();
      _enabled = result.data['enabled'] == true;
      final midpoint = start.add(DateTime.now().difference(start) ~/ 2);
      _serverOffset = DateTime.fromMillisecondsSinceEpoch(
        (result.data['serverNow'] as num).toInt(),
      ).difference(midpoint);
      notifyListeners();
    } catch (_) {
      /* Firestore listeners remain usable offline; bids still require server confirmation. */
    }
  }

  // Getters
  String? get currentKingUid => _currentKingUid;
  String? get currentKingName => _currentKingName;
  String? get currentKingAvatar => _currentKingAvatar;
  int get currentBid => _currentBid;
  Timestamp? get auctionEndsAt => _auctionEndsAt;
  bool get isLoading => _isLoading;
  int get myPoints => _myPoints;
  String get myCrownNumber => _myCrownNumber;
  bool get isKing =>
      _currentKingUid != null && _currentKingUid == _auth.currentUser?.uid;
  bool get isThroneLocked => _isThroneLocked;
  Timestamp? get lockEndTime => _lockEndTime;

  CrownProvider() {
    WidgetsBinding.instance.addObserver(this);
    _initListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  Future<void> _loadPending(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('tini_throne_pending_$uid');
      if (raw == null ||
          _auth.currentUser?.uid != uid ||
          _disposed ||
          _isLoading) {
        return;
      }
      final pending = jsonDecode(raw) as Map<String, dynamic>;
      _pendingRequest = pending['requestId'] as String;
      _pendingAuction = pending['auctionId'] as String;
      _pendingAmount = pending['amount'] as int;
      notifyListeners();
    } catch (_) {
      /* Malformed local retry state never authorizes a financial operation. */
    }
  }

  void _initListeners() {
    _throneSub?.cancel();
    _authSub?.cancel();
    _userSub?.cancel();

    // 1. مراقبة بيانات العرش لحظياً
    _throneSub = _firestore
        .collection('throne_data')
        .doc('current')
        .snapshots()
        .listen(
          (doc) {
            if (!doc.exists) {
              _ready = false;
              _currentKingUid = null;
              _currentKingName = null;
              _currentKingAvatar = null;
              leaderUid = null;
              leaderName = null;
              leaderAvatar = null;
              auctionId = null;
              coronationId = null;
              _currentBid = 0;
              _auctionEndsAt = null;
              _lockEndTime = null;
              _isThroneLocked = false;
              notifyListeners();
              return;
            }
            if (doc.exists) {
              final data = doc.data()!;
              _currentKingUid = data['kingUid'];
              _currentKingName = data['kingName'];
              _currentKingAvatar = data['kingAvatar'];
              _currentBid = data['currentBid'] ?? 0;
              _auctionEndsAt = data['auctionEndsAt'];
              _isThroneLocked = data['isLocked'] ?? false;
              _lockEndTime = data['lockEndTime'];

              _ready = data['schemaVersion'] == 2;
              auctionId = data['auctionId'];
              leaderUid = data['leaderUid'];
              leaderName = data['leaderName'];
              leaderAvatar = data['leaderAvatar'];
              coronationId = data['coronationId'];
              notifyListeners();
            }
          },
          onError: (Object error) {
            _ready = false;
            lastError = 'تعذر تحديث العرش؛ تحقق من الاتصال';
            notifyListeners();
          },
        );

    // 2. مراقبة نقاط المستخدم الحالي
    _authSub = _auth.authStateChanges().listen((user) {
      _userSub?.cancel();
      _myPoints = 0;
      _reserved = 0;
      _myCrownNumber = '';
      _pendingRequest = null;
      _pendingAuction = null;
      _pendingAmount = null;
      _enabled = false;
      notifyListeners();
      if (user != null) {
        unawaited(_loadPending(user.uid));
        unawaited(sync());
        _userSub = _firestore
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen((doc) {
              if (doc.exists) {
                final data = doc.data()!;
                if (_auth.currentUser?.uid != user.uid) return;
                _myPoints = (data['titiBalance'] as num? ?? 0).toInt();
                _reserved = (data['throneReservedPoints'] as num? ?? 0).toInt();
                _myCrownNumber =
                    data['crownNumber'] ?? _generateCrownNumber(user.uid);
                notifyListeners();
              }
            });
      }
    });
  }

  String _generateCrownNumber(String uid) {
    // رقم تاج ثابت بناء على UID: Tini-XXXXX
    final hash = uid.hashCode.abs().toString().padLeft(5, '0');
    return 'Tini-${hash.substring(0, 5)}';
  }

  Future<bool> placeBid(int newBid) async {
    if (_isLoading) return false;
    final id = auctionId;
    if (!_ready || id == null) {
      lastError = 'النظام بانتظار تفعيل السيرفر';
      return false;
    }
    final requestId =
        _pendingRequest != null &&
            _pendingAmount == newBid &&
            _pendingAuction == id
        ? _pendingRequest!
        : _firestore.collection('throne_bids').doc().id;
    return _submit(newBid, id, requestId);
  }

  Future<bool> retryPendingBid() async {
    if (_pendingRequest == null ||
        _pendingAuction == null ||
        _pendingAmount == null) {
      return false;
    }
    return _submit(_pendingAmount!, _pendingAuction!, _pendingRequest!);
  }

  Future<bool> _submit(int amount, String id, String requestId) async {
    if (_isLoading) return false;
    lastError = null;
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      lastError = 'يجب تسجيل الدخول';
      return false;
    }
    _isLoading = true;
    _pendingAmount = amount;
    _pendingAuction = id;
    _pendingRequest = requestId;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      // Persist before sending, so an app restart cannot turn a lost response into a new charge.
      await prefs.setString(
        'tini_throne_pending_$uid',
        jsonEncode({'amount': amount, 'auctionId': id, 'requestId': requestId}),
      );
      if (_auth.currentUser?.uid != uid) return false;
      final result = await _functions.httpsCallable('placeThroneBid').call({
        'amount': amount,
        'auctionId': id,
        'requestId': requestId,
        'uid': uid,
      });
      if (result.data['accepted'] != true) return false;
      await prefs.remove('tini_throne_pending_$uid');
      if (_auth.currentUser?.uid != uid) return false;
      _pendingRequest = null;
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (_auth.currentUser?.uid == uid) {
        lastError = e.message ?? 'تعذر تأكيد الطلب؛ أعد المحاولة';
        if (![
          'unavailable',
          'deadline-exceeded',
          'internal',
          'unknown',
          'cancelled',
        ].contains(e.code)) {
          _pendingRequest = null;
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('tini_throne_pending_$uid');
        }
      }
      return false;
    } catch (_) {
      if (_auth.currentUser?.uid == uid) {
        lastError = 'تعذر تأكيد الطلب؛ استخدم تأكيد آخر طلب';
      }
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Client-side point minting is deliberately unavailable. No callers exist.
  Future<void> addPointsToCurrentUser(int points) =>
      Future.error(StateError('إضافة النقاط تتطلب عملية موثقة من السيرفر'));

  Stream<QuerySnapshot> getBidHistoryStream() {
    return _firestore
        .collection('throne_bids')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots();
  }

  @override
  void dispose() {
    _throneSub?.cancel();
    _authSub?.cancel();
    _userSub?.cancel();
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}