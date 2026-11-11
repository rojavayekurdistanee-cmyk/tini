import 'user_documents.dart';
import 'dart:async';
import 'audience_access.dart';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
        _userPointsSub = UserDocuments.readable(_firestore, uid)
            .snapshots()
            .listen((doc) {
              if (doc.exists && !_isDisposed && _auth.currentUser?.uid == uid) {
                _userPoints = doc.data()?['tiniBalance'] ?? 0;
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
        final userDoc = await UserDocuments.readable(_firestore, userId).get();
        isAdmin = userDoc.data()?['isAdmin'] ?? false;
      } catch (_) {}
    }

    if (_isDisposed ||
        generation != _postsGeneration ||
        userId != _auth.currentUser?.uid) {
      return;
    }
    _boxesViewerUid = userId;
    _boxPosts
      ..clear()
      ..addEntries(snap.docs.map((doc) => MapEntry(doc.id, doc.data())));

    _boxes = snap.docs.map((doc) => BoxModel.fromPostDoc(doc)).where((box) {
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
    }).toList();

    notifyListeners();
  }

  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<dynamic> _callMoney(
    String name,
    String postId, {
    bool reserve = false,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('يجب تسجيل الدخول');
    final key = 'box_request_${uid}_$postId';
    var requestId = await _secureStorage.read(key: key);
    requestId ??= List.generate(
      24,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _secureStorage.write(key: key, value: requestId);
    var token = await _secureStorage.read(key: 'box_token_${uid}_$postId');
    if (!reserve && token == null) {
      final post = await _firestore
          .collection('posts')
          .doc(postId)
          .get(const GetOptions(source: Source.server));
      token = post.data()?['boxSecureHash'] as String?;
    }
    final result = await _functions.httpsCallable(name).call({
      'uid': uid,
      'postId': postId,
      'requestId': requestId,
      'token': token,
    });
    if (_auth.currentUser?.uid != uid) throw Exception('تغير الحساب');
    if (reserve) {
      if (result.data['status'] != 'held') {
        await _secureStorage.delete(key: key);
        throw Exception('انتهى الحجز السابق؛ اضغط الحجز من جديد');
      }
      await _secureStorage.write(
        key: 'box_token_${uid}_$postId',
        value: result.data['token'] as String,
      );
    } else {
      await _secureStorage.delete(key: key);
      // Keep the server reservation token for safe repeated confirmation of a sold box.
    }
    return result.data;
  }

  Future<bool> reserveBox(String postId) async {
    _isLoading = true;
    _errorMsg = '';
    notifyListeners();
    try {
      await _callMoney('reserveTiniBox', postId, reserve: true);
      return true;
    } catch (e) {
      _errorMsg = e is FirebaseFunctionsException
          ? e.message ?? e.code
          : e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<DocumentSnapshot?> confirmPurchase(String postId) async {
    try {
      final result = await _callMoney('confirmTiniBox', postId);
      if (result['completed'] != true) {
        throw Exception('انتهت مهلة الحجز وأعيدت النقاط');
      }
      return await _firestore
          .collection('posts')
          .doc(postId)
          .get(const GetOptions(source: Source.server));
    } catch (e) {
      _errorMsg = e is FirebaseFunctionsException
          ? e.message ?? e.code
          : e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> cancelReservation(String postId) async {
    try {
      await _callMoney('cancelTiniBox', postId);
    } catch (e) {
      _errorMsg = e is FirebaseFunctionsException
          ? e.message ?? e.code
          : e.toString();
      notifyListeners();
    }
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