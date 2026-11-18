import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';

class CrownProvider extends ChangeNotifier with WidgetsBindingObserver {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // السقف الجديد
  static const int maxBid = 10000;

  // بيانات العرش
  String? _currentKingUid;
  String? _currentKingName;
  String? _currentKingAvatar;
  int _currentBid = 0;
  Timestamp? _auctionEndsAt;
  bool _isLoading = false;

  // قفل العرش
  bool _isThroneLocked = false;
  Timestamp? _lockEndTime;

  // بيانات المستخدم الحالي
  int _myPoints = 0;
  String _myCrownNumber = '';

  StreamSubscription? _throneSub;
  StreamSubscription? _authSub;
  StreamSubscription? _userSub;

  final FirebaseFunctions _functions;

  String? auctionId;
  String? leaderUid;
  String? leaderName;
  String? leaderAvatar;
  String? coronationId;
  String? lastError;

  bool _ready = false;
  bool? _enabled;
  String? _availabilityReason;
  bool _checkingAvailability = false;
  bool _disposed = false;
  Duration _serverOffset = Duration.zero;

  String? _pendingRequest;
  String? _pendingAuction;
  int? _pendingAmount;
  int _reserved = 0;
  int _bidSession = 0;
  String? _pendingOwnerUid;
  bool _pendingReady = false;
  Future<void>? _pendingLoad;

  int get reservedPoints => _reserved;
  bool get hasPendingBid => _pendingRequest != null;
  bool get needsPendingBidCheck =>
      _auth.currentUser != null &&
      (!_pendingReady ||
          _pendingOwnerUid != _auth.currentUser?.uid ||
          hasPendingBid);
  bool get isRestoringPendingBid => _pendingLoad != null;
  bool get enabled => _ready && _enabled == true;
  bool get canRefreshAvailability =>
      _auth.currentUser != null && !_checkingAvailability;

  String? get availabilityMessage {
    if (!_ready) return 'نظام العرش بانتظار تفعيل السيرفر';
    if (_enabled == true) return null;
    if (_auth.currentUser == null) return 'سجّل الدخول للمزايدة';
    if (_checkingAvailability) return 'جارٍ التحقق من توفر المزايدات…';
    if (_enabled == false) {
      return switch (_availabilityReason) {
        'wallet_migration_in_progress' =>
          'المزايدات متوقفة أثناء تحديث المحفظة',
        'wallet_migration_required' => 'المزايدات بانتظار إكمال تهيئة المحفظة',
        'wallet_disabled' => 'المزايدات متوقفة لأن المحفظة غير مفعّلة',
        'throne_activation_required' =>
          'المزايدات بانتظار تفعيل نظام العرش من الإدارة',
        'throne_disabled' => 'المزايدات موقوفة من الإدارة',
        'throne_schema_required' =>
          'المزايدات بانتظار تحديث بيانات العرش من الإدارة',
        'throne_wallet_migration_required' =>
          'المزايدات بانتظار ربط العرش بالمحفظة الحالية',
        _ => 'المزايدات غير مفعلة حالياً',
      };
    }
    return switch (_availabilityReason) {
      'not-found' =>
        'تعذر الوصول إلى خدمة المزايدات؛ يلزم التحقق من نشر الدالة',
      'unauthenticated' => 'تعذر التحقق من جلسة الدخول أو توثيق التطبيق',
      'permission-denied' => 'رفض السيرفر التحقق من توفر المزايدات',
      'unavailable' ||
      'deadline-exceeded' => 'تعذر الاتصال بخدمة المزايدات؛ أعد المحاولة',
      _ => 'تعذر التحقق من توفر المزايدات',
    };
  }

  DateTime get serverNow => DateTime.now().add(_serverOffset);

  bool get canBid =>
      _auth.currentUser != null &&
      _pendingReady &&
      _pendingOwnerUid == _auth.currentUser?.uid &&
      !hasPendingBid &&
      enabled &&
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
    final uid = _auth.currentUser?.uid;
    final session = _bidSession;
    if (uid == null ||
        !_sameBidSession(uid, session) ||
        _checkingAvailability) {
      return;
    }
    _checkingAvailability = true;
    notifyListeners();
    try {
      final start = DateTime.now();
      final result = await _functions.httpsCallable('syncThrone').call();
      if (!_sameBidSession(uid, session)) return;
      final midpoint = start.add(DateTime.now().difference(start) ~/ 2);
      _serverOffset = DateTime.fromMillisecondsSinceEpoch(
        (result.data['serverNow'] as num).toInt(),
      ).difference(midpoint);
      _enabled = result.data['enabled'] as bool?;
      _availabilityReason = result.data['availabilityReason'] as String?;
    } on FirebaseFunctionsException catch (error) {
      if (_sameBidSession(uid, session)) {
        _enabled = null;
        _availabilityReason = error.code;
      }
    } catch (_) {
      if (_sameBidSession(uid, session)) {
        _enabled = null;
        _availabilityReason = null;
      }
    } finally {
      if (_sameBidSession(uid, session)) {
        _checkingAvailability = false;
        notifyListeners();
      }
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

  CrownProvider({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1') {
    WidgetsBinding.instance.addObserver(this);
    _initListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  bool _sameBidSession(String uid, int session) =>
      !_disposed &&
      _auth.currentUser?.uid == uid &&
      _pendingOwnerUid == uid &&
      _bidSession == session;

  Future<void> _restorePending() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || _disposed || _pendingOwnerUid != uid || _pendingReady)
      return;
    final existing = _pendingLoad;
    if (existing != null) return existing;
    final session = _bidSession;
    final load = _loadPending(uid, session);
    _pendingLoad = load;
    notifyListeners();
    try {
      await load;
    } finally {
      if (_sameBidSession(uid, session) && identical(_pendingLoad, load)) {
        _pendingLoad = null;
        notifyListeners();
      }
    }
  }

  Future<void> _loadPending(String uid, int session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_sameBidSession(uid, session)) return;
      final raw = prefs.getString('tini_throne_pending_$uid');
      if (raw != null) {
        final pending = jsonDecode(raw) as Map<String, dynamic>;
        final request = pending['requestId'] as String;
        final auction = pending['auctionId'] as String;
        final amount = pending['amount'] as int;
        if (request.isEmpty ||
            auction.isEmpty ||
            amount < 1 ||
            amount > maxBid) {
          throw const FormatException('Invalid pending bid');
        }
        _pendingRequest = request;
        _pendingAuction = auction;
        _pendingAmount = amount;
      }
      _pendingReady = true;
    } catch (_) {
      if (_sameBidSession(uid, session)) {
        // Do not overwrite an unreadable record with a new financial request.
        _pendingReady = false;
        lastError = 'تعذر استعادة الطلب السابق؛ أعد التحقق قبل مزايدة جديدة';
      }
    }
  }

  Future<bool> _clearPending(String uid, int session, String requestId) async {
    if (!_sameBidSession(uid, session) || _pendingRequest != requestId)
      return false;
    final prefs = await SharedPreferences.getInstance();
    if (!_sameBidSession(uid, session) || _pendingRequest != requestId)
      return false;
    if (!await prefs.remove('tini_throne_pending_$uid')) {
      throw StateError('Could not clear pending bid');
    }
    if (!_sameBidSession(uid, session) || _pendingRequest != requestId)
      return false;
    _pendingRequest = null;
    _pendingAuction = null;
    _pendingAmount = null;
    return true;
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

              _ready = data['schemaVersion'] == 3;
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

    // 2. مراقبة الرصيد والنقاط المحجوزة ورقم التاج باشتراك واحد
    _authSub = _auth.authStateChanges().listen((user) {
      _userSub?.cancel();
      _bidSession++;
      _pendingOwnerUid = user?.uid;
      _pendingLoad = null;
      _pendingReady = user == null;
      _myPoints = 0;
      _reserved = 0;
      _myCrownNumber = '';
      _pendingRequest = null;
      _pendingAuction = null;
      _pendingAmount = null;
      _enabled = null;
      _availabilityReason = null;
      _checkingAvailability = false;
      notifyListeners();

      if (user != null) {
        unawaited(_restorePending());
        unawaited(sync());

        _userSub = _firestore
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen(
              (doc) {
                if (_disposed || _auth.currentUser?.uid != user.uid) return;

                final data = doc.data();
                final points = data?['walletVersion'] == 2
                    ? (data?['tiniBalance'] as num? ?? 0).toInt()
                    : 0;
                final reserved = (data?['throneReservedPoints'] as num? ?? 0)
                    .toInt();
                final crownNumber = doc.exists
                    ? (data?['crownNumber'] ?? _generateCrownNumber(user.uid))
                    : _myCrownNumber;

                // لا نحدّث الواجهة إذا لم تتغير القيم المستخدمة.
                if (_myPoints == points &&
                    _reserved == reserved &&
                    _myCrownNumber == crownNumber) {
                  return;
                }

                _myPoints = points;
                _reserved = reserved;
                _myCrownNumber = crownNumber;
                notifyListeners();
              },
              onError: (Object error) {
                if (_disposed || _auth.currentUser?.uid != user.uid) return;

                const message = 'تعذر تحديث نقاط العرش؛ أعد المحاولة';
                final changed =
                    _myPoints != 0 || _reserved != 0 || lastError != message;

                _myPoints = 0;
                _reserved = 0;
                lastError = message;

                if (changed) notifyListeners();
              },
            );
      }
    });
  }

  String _generateCrownNumber(String uid) {
    // رقم تاج ثابت بناء على UID: Tini-XXXXX
    final hash = uid.hashCode.abs().toString().padLeft(5, '0');
    return 'Tini-${hash.substring(0, 5)}';
  }

  Future<bool> placeBid(int newBid) async {
    if (_isLoading || _disposed) return false;
    final uid = _auth.currentUser?.uid;
    final session = _bidSession;
    if (uid == null) {
      lastError = 'يجب تسجيل الدخول';
      return false;
    }
    await _restorePending();
    if (!_sameBidSession(uid, session) || _isLoading || !_pendingReady)
      return false;
    if (hasPendingBid) {
      lastError = 'تحقق من نتيجة المزايدة السابقة قبل تقديم مزايدة جديدة';
      notifyListeners();
      return false;
    }
    final id = auctionId;
    if (!_ready || id == null) {
      lastError = 'النظام بانتظار تفعيل السيرفر';
      return false;
    }
    return _submit(newBid, id, _firestore.collection('throne_bids').doc().id);
  }

  Future<bool> retryPendingBid() async {
    if (_isLoading || _disposed) return false;
    final uid = _auth.currentUser?.uid;
    final session = _bidSession;
    if (uid == null) return false;
    await _restorePending();
    if (!_sameBidSession(uid, session) || !_pendingReady) return false;
    if (_pendingRequest == null ||
        _pendingAuction == null ||
        _pendingAmount == null) {
      lastError = 'لا توجد مزايدة معلقة؛ يمكنك تقديم مزايدة جديدة';
      notifyListeners();
      return false;
    }
    // Deliberately allowed when the auction changes, is paused or becomes locked:
    // the server checks this request's receipt before current auction eligibility.
    return _submit(_pendingAmount!, _pendingAuction!, _pendingRequest!);
  }

  Future<bool> _submit(int amount, String id, String requestId) async {
    if (_isLoading || _disposed || !_pendingReady) return false;
    if (hasPendingBid &&
        (_pendingRequest != requestId ||
            _pendingAuction != id ||
            _pendingAmount != amount))
      return false;
    lastError = null;
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      lastError = 'يجب تسجيل الدخول';
      return false;
    }
    final session = _bidSession;
    _isLoading = true;
    _pendingAmount = amount;
    _pendingAuction = id;
    _pendingRequest = requestId;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_sameBidSession(uid, session)) return false;
      // Persist before sending, so an app restart cannot turn a lost response into a new charge.
      final saved = await prefs.setString(
        'tini_throne_pending_$uid',
        jsonEncode({'amount': amount, 'auctionId': id, 'requestId': requestId}),
      );
      if (!saved) throw StateError('Could not persist pending bid');
      if (!_sameBidSession(uid, session)) return false;
      final result = await _functions.httpsCallable('placeThroneBid').call({
        'amount': amount,
        'auctionId': id,
        'requestId': requestId,
        'uid': uid,
      });
      if (!_sameBidSession(uid, session)) return false;
      if (result.data['accepted'] != true) {
        lastError = 'نتيجة الطلب غير مؤكدة؛ أعد التحقق من المزايدة السابقة';
        return false;
      }
      return await _clearPending(uid, session, requestId);
    } on FirebaseFunctionsException catch (e) {
      if (_sameBidSession(uid, session)) {
        lastError = e.message ?? 'تعذر تأكيد الطلب؛ أعد المحاولة';
        if (![
          'unavailable',
          'deadline-exceeded',
          'internal',
          'unknown',
          'cancelled',
          'unauthenticated',
          'permission-denied',
        ].contains(e.code)) {
          try {
            await _clearPending(uid, session, requestId);
          } catch (_) {
            if (_sameBidSession(uid, session)) {
              lastError = 'تعذر حفظ نتيجة الطلب؛ أعد التحقق قبل مزايدة جديدة';
            }
          }
        }
      }
      return false;
    } catch (_) {
      if (_sameBidSession(uid, session)) {
        lastError = 'تعذر تأكيد الطلب؛ استخدم التحقق من نتيجة المزايدة';
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