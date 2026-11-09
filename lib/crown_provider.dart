import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class CrownProvider extends ChangeNotifier {
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
  Timer? _resetTimer;

  // Getters
  String? get currentKingUid => _currentKingUid;
  String? get currentKingName => _currentKingName;
  String? get currentKingAvatar => _currentKingAvatar;
  int get currentBid => _currentBid;
  Timestamp? get auctionEndsAt => _auctionEndsAt;
  bool get isLoading => _isLoading;
  int get myPoints => _myPoints;
  String get myCrownNumber => _myCrownNumber;
  bool get isKing => _currentKingUid == _auth.currentUser?.uid;
  bool get isThroneLocked => _isThroneLocked;
  Timestamp? get lockEndTime => _lockEndTime;

  CrownProvider() {
    _initListeners();
  }

  void _initListeners() {
    _throneSub?.cancel();
    _authSub?.cancel();
    _userSub?.cancel();

    // 1. مراقبة بيانات العرش لحظياً
    _throneSub = _firestore.collection('throne_data').doc('current').snapshots().listen((doc) {
      if (doc.exists) {
        final data = doc.data()!;
        _currentKingUid = data['kingUid'];
        _currentKingName = data['kingName'];
        _currentKingAvatar = data['kingAvatar'];
        _currentBid = data['currentBid'] ?? 0;
        _auctionEndsAt = data['auctionEndsAt'];
        _isThroneLocked = data['isLocked'] ?? false;
        _lockEndTime = data['lockEndTime'];
        
        _checkLockStatus();
        notifyListeners();
      }
    });

    // 2. مراقبة نقاط المستخدم الحالي
    _authSub = _auth.authStateChanges().listen((user) {
      _userSub?.cancel();
      if (user != null) {
        _userSub = _firestore.collection('users').doc(user.uid).snapshots().listen((doc) {
          if (doc.exists) {
            final data = doc.data()!;
            _myPoints = data['titiBalance'] ?? 0;
            _myCrownNumber = data['crownNumber'] ?? _generateCrownNumber(user.uid);
            notifyListeners();
          }
        });
      }
    });
  }

  void _checkLockStatus() {
    _resetTimer?.cancel();
    if (_isThroneLocked && _lockEndTime != null) {
      final remaining = _lockEndTime!.toDate().difference(DateTime.now());
      if (remaining.isNegative) {
        // الوقت خلص، نعمل ريست
        _resetThrone();
      } else {
        // نعمل تايمر للريست التلقائي
        _resetTimer = Timer(remaining, _resetThrone);
      }
    }
  }

  Future<void> _resetThrone() async {
    try {
      await _firestore.collection('throne_data').doc('current').set({
        'kingUid': null,
        'kingName': null,
        'kingAvatar': null,
        'currentBid': 1000,
        'auctionEndsAt': null,
        'isLocked': false,
        'lockEndTime': null,
        'lastResetAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Crown Reset Error]: $e');
    }
  }

  String _generateCrownNumber(String uid) {
    // رقم تاج ثابت بناء على UID: TITI-XXXXX
    final hash = uid.hashCode.abs().toString().padLeft(5, '0');
    return 'Tini-${hash.substring(0, 5)}';
  }

  Future<bool> placeBid(int newBid) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    if (_isThroneLocked) return false; // العرش مقفول
    if (newBid <= _currentBid) return false;
    if (newBid > maxBid) return false; // سقف 10,000
    if (newBid > _myPoints) return false;

    _isLoading = true;
    notifyListeners();

    try {
      await _firestore.runTransaction((transaction) async {
        final throneRef = _firestore.collection('throne_data').doc('current');
        final userRef = _firestore.collection('users').doc(uid);

        final throneSnap = await transaction.get(throneRef);
        final userSnap = await transaction.get(userRef);

        if (!userSnap.exists) throw Exception('User not found');

        final userData = userSnap.data()!;
        final currentPoints = userData['titiBalance'] ?? 0;
        final liveBid = throneSnap.data()?['currentBid'] ?? 0;
        final liveIsLocked = throneSnap.data()?['isLocked'] ?? false;

        if (liveIsLocked) throw Exception('Throne is locked');
        if (newBid <= liveBid) throw Exception('Bid too low');
        if (newBid > maxBid) throw Exception('Bid exceeds max');
        if (currentPoints < newBid) throw Exception('Not enough points');

        // خصم النقاط من المستخدم
        transaction.update(userRef, {'titiBalance': FieldValue.increment(-newBid)});

        // تحديث العرش
        final updateData = {
          'kingUid': uid,
          'kingName': userData['fullName'] ?? userData['username'],
          'kingAvatar': userData['profileImg'] ?? '',
          'currentBid': newBid,
          'lastBidAt': FieldValue.serverTimestamp(),
        };

        // اذا وصل السقف، نقفل العرش 7 أيام
        if (newBid >= maxBid) {
          updateData['isLocked'] = true;
          updateData['lockEndTime'] = Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 7)),
          );
          updateData['auctionEndsAt'] = null;
        } else {
          updateData['auctionEndsAt'] = Timestamp.fromDate(
            DateTime.now().add(const Duration(hours: 24)),
          );
        }

        transaction.set(throneRef, updateData, SetOptions(merge: true));

        // سجل المزايدة
        final bidRef = _firestore.collection('throne_bids').doc();
        transaction.set(bidRef, {
          'uid': uid,
          'username': userData['username'],
          'fullName': userData['fullName'],
          'bidAmount': newBid,
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      return true;
    } catch (e) {
      debugPrint('[Crown Error]: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addPointsToCurrentUser(int points) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).update({
      'titiBalance': FieldValue.increment(points),
    });
  }

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
    _resetTimer?.cancel();
    super.dispose();
  }
}