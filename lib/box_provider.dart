import 'dart:async';
import 'audience_access.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'box_model.dart';

class BoxProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
      resetOnError: true,
      storageNamespace: 'TitiStar_V5_FinalSafe',
      preferencesKeyPrefix: 'titi_star_v5',
    ),
  );

  List<BoxModel> _boxes = [];
  final Map<String, Map<String, dynamic>> _boxPosts = {};
  QuerySnapshot<Map<String, dynamic>>? _latestPosts;
  String? _boxesViewerUid;
  int _postsGeneration = 0;
  bool _isLoading = false;
  String _errorMsg = '';
  int _userPoints = 0;

  List<BoxModel> get boxes {
    if (_boxesViewerUid != _auth.currentUser?.uid) return [];
    return _boxes.where((box) {
      final post = _boxPosts[box.id];
      return post != null &&
          AudienceAccess.instance.canViewPost(post, postId: box.id);
    }).toList();
  }
  bool get isLoading => _isLoading;
  String get errorMsg => _errorMsg;
  int get userPoints => _userPoints;

  StreamSubscription? _postsSub;
  StreamSubscription? _authSub;
  StreamSubscription? _userPointsSub;
  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }

  BoxProvider() {
    AudienceAccess.instance.addListener(_onAudienceChanged);
    _initListeners();
  }

  void _onAudienceChanged() {
    notifyListeners();
  }

  void _initListeners() {
    _postsSub?.cancel();
    _authSub?.cancel();
    _userPointsSub?.cancel();

    _postsSub = _firestore
        .collection('posts')
        .where('isMysteryBox', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      _latestPosts = snap;
      _refreshBoxes();
    });

    _authSub = _auth.authStateChanges().listen((user) {
      _userPointsSub?.cancel();
      _userPoints = 0;
      _refreshBoxes();
      if (user != null) {
        final uid = user.uid;
        _userPointsSub = _firestore.collection('users').doc(uid).snapshots().listen((doc) {
          if (doc.exists && !_isDisposed && _auth.currentUser?.uid == uid) {
            _userPoints = doc.data()?['titiBalance'] ?? 0;
            notifyListeners();
          }
        });
      }
      notifyListeners();
    });
  }

  Future<void> _refreshBoxes() async {
      final snap = _latestPosts;
      if (snap == null) return;
      final generation = ++_postsGeneration;
      final now = DateTime.now();
      final currentUser = _auth.currentUser;
      final userId = currentUser?.uid;
      
      bool isAdmin = false;
      if (userId != null) {
        try {
          final userDoc = await _firestore.collection('users').doc(userId).get();
          isAdmin = userDoc.data()?['isAdmin'] ?? false;
        } catch (_) {}

      }
      
      if (_isDisposed || generation != _postsGeneration ||
          userId != _auth.currentUser?.uid) return;
      _boxesViewerUid = userId;
      _boxPosts
        ..clear()
        ..addEntries(snap.docs.map((doc) => MapEntry(doc.id, doc.data())));

      _boxes = snap.docs
          .map((doc) => BoxModel.fromPostDoc(doc))
          .where((box) {
            // 1. الصناديق المتاحة: ظاهرة للكل
            if (box.status == BoxStatus.available) {
              return true;
            }

            // 2. صندوق محجوز أو مباع: بس المشتري + البائع + الأدمن بيشوفوه
            final isOwner = userId != null && userId == box.userId;
            final isBuyer = userId != null && userId == box.ownedByUid;

            if (!isOwner && !isBuyer && !isAdmin) {
              return false; // اخفيه فوراً عن باقي الناس
            }

            // 3. حتى هدول الثلاثة، الصندوق المفتوح بيختفي بعد 24 ساعة
            if (box.status == BoxStatus.sold && box.boxOpenedAt != null) {
              final openedTime = box.boxOpenedAt!.toDate();
              final expiryTime = openedTime.add(const Duration(hours: 24));
              return now.isBefore(expiryTime);
            }

            // 4. محجوز onHold: بيضل ظاهر للمشتري/البائع/أدمن لحتى ينتهي الحجز أو ينباع
            return true;
          })
          .toList();
      
      _checkExpiredReservations();
      notifyListeners();
  }

  void _checkExpiredReservations() {
    for (var box in _boxes) {
      if (box.status == BoxStatus.onHold && box.isExpired) {
        _releaseBox(box.id);
      }
    }
  }

  Future<void> _releaseBox(String postId) async {
    await _firestore.collection('posts').doc(postId).update({
      'boxOwnedByUid': null,
      'boxOwnedByName': null,
      'boxReservedAt': null,
      'boxExpiresAt': null, // ← جديد
      'boxSecureHash': null,
    });
  }

  String _generateSecureHash(String boxId, String uid, int timestamp) {
    final key = utf8.encode('TITI_BOX_$boxId$uid$timestamp');
    final bytes = utf8.encode('$boxId-$uid-$timestamp');
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return digest.toString();
  }

  Future<bool> reserveBox(String postId) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    _isLoading = true;
    _errorMsg = '';
    notifyListeners();

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final postDoc = await _firestore.collection('posts').doc(postId).get();
      if (!postDoc.exists) throw Exception('الصندوق غير موجود');

      final box = BoxModel.fromPostDoc(postDoc);
      final userData = userDoc.data()!;

      if (box.userId == user.uid) throw Exception('ما بتقدر تشتري صندوقك');
      bool isAdmin = userData['isAdmin'] ?? false;
      if (box.status != BoxStatus.available) throw Exception('الصندوق محجوز حالياً');
      if (!isAdmin && _userPoints < box.price) throw Exception('نقاطك لا تكفي');

      final now = DateTime.now();
      final expiryDate = now.add(const Duration(minutes: 10)); // ← الحجز 10 دقايق
      final secureHash = _generateSecureHash(postId, user.uid, now.millisecondsSinceEpoch);

      await _firestore.runTransaction((transaction) async {
        final freshPostDoc = await transaction.get(postDoc.reference);
        final freshBox = BoxModel.fromPostDoc(freshPostDoc);
        if (freshBox.status != BoxStatus.available) throw Exception('تم حجز الصندوق للتو');

        if (!isAdmin) {
          transaction.update(userDoc.reference, {
            'titiBalance': FieldValue.increment(-box.price),
          });
        }

        transaction.update(postDoc.reference, {
          'boxOwnedByUid': user.uid,
          'boxOwnedByName': userData['fullName'] ?? userData['username'],
          'boxReservedAt': FieldValue.serverTimestamp(),
          'boxExpiresAt': Timestamp.fromDate(expiryDate), // ← جديد
          'boxSecureHash': secureHash,
        });
      });

      await _secureStorage.write(key: 'box_reservation_$postId', value: secureHash);
      return true;
    } catch (e) {
      _errorMsg = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<DocumentSnapshot?> confirmPurchase(String postId) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    _errorMsg = '';
    try {
      final postRef = _firestore.collection('posts').doc(postId);
      final postDoc = await postRef.get(GetOptions(source: Source.server));
      if (!postDoc.exists) throw Exception('الصندوق غير موجود');
      final box = BoxModel.fromPostDoc(postDoc);

      // إذا مباع إلك من قبل، امنح الشارة وارجع نسخة فريش من السيرفر
      if (box.status == BoxStatus.sold && box.ownedByUid == user.uid) {
        await _grantBadge(user.uid, box.rarity);
        return await postRef.get(GetOptions(source: Source.server));
      }

      final storedHash = await _secureStorage.read(key: 'box_reservation_$postId');
      if (storedHash == null) throw Exception('لم يتم العثور على حجز');
      if (box.ownedByUid != user.uid) throw Exception('هذا الصندوق محجوز لشخص آخر');

      await postRef.update({
        'boxSold': true,
        'boxSoldAt': FieldValue.serverTimestamp(),
        'boxOpenedAt': FieldValue.serverTimestamp(),
        'boxExpiresAt': null, // ← نمسحه بعد الشراء
      });

      // نقاط البائع - set merge عشان ما يفشل
      try {
        await _firestore.collection('users').doc(box.userId).set({
          'titiBalance': FieldValue.increment(box.price),
        }, SetOptions(merge: true));
      } catch (_) {}

      final badgeOk = await _grantBadge(user.uid, box.rarity);
      if (!badgeOk) throw Exception(_errorMsg);

      await _secureStorage.delete(key: 'box_reservation_$postId');
      return await postRef.get(GetOptions(source: Source.server));
    } catch (e) {
      _errorMsg = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  Future<bool> _grantBadge(String uid, BoxRarity rarity) async {
    try {
      final userRef = _firestore.collection('users').doc(uid);
      final userDoc = await userRef.get();
      final data = userDoc.data();
      final currentBadge = data?['badge'] as String?;
      final currentEndsAt = data?['badgeEndsAt'] as Timestamp?;

      DateTime baseDate = currentEndsAt?.toDate() ?? DateTime.now();
      if (baseDate.isBefore(DateTime.now())) baseDate = DateTime.now();
      DateTime newEndDate = baseDate.add(const Duration(days: 7));

      final powers = {'diamond': 4, 'gold': 3, 'silver': 2, 'bronze': 1};
      int newPower = powers[rarity.name.toLowerCase()] ?? 0;
      int currentPower = powers[currentBadge?.toLowerCase()] ?? 0;

      String newBadgeType;
      if (currentBadge == null || newPower >= currentPower) {
        newBadgeType = rarity.name.toLowerCase();
      } else {
        newBadgeType = currentBadge;
      }

      await userRef.set({
        'badge': newBadgeType,
        'badgeEndsAt': Timestamp.fromDate(newEndDate),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      _errorMsg = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> cancelReservation(String postId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final postDoc = await _firestore.collection('posts').doc(postId).get();
    if (!postDoc.exists) return;
    final box = BoxModel.fromPostDoc(postDoc);
    if (box.ownedByUid != user.uid) return;
    await _firestore.collection('users').doc(user.uid).update({
      'titiBalance': FieldValue.increment(box.price),
    });
    await _releaseBox(postId);
    await _secureStorage.delete(key: 'box_reservation_$postId');
  }

  @override
  void dispose() {
    _isDisposed = true;
    _postsGeneration++;
    AudienceAccess.instance.removeListener(_onAudienceChanged);
    _postsSub?.cancel();
    _authSub?.cancel();
    _userPointsSub?.cancel();
    super.dispose();
  }
}