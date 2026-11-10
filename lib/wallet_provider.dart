import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class Transaction {
  final String id;
  final int amount;
  final String type;
  final DateTime createdAt;
  final String? packageId;
  Transaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.createdAt,
    this.packageId,
  });
  factory Transaction.fromMap(String id, Map<String, dynamic> data) =>
      Transaction(
        id: id,
        amount: (data['amount'] as num? ?? 0).toInt(),
        type: data['type'] as String? ?? 'purchase',
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        packageId: data['packageId'] as String?,
      );
  bool get isCredit => [
    'purchase',
    'reward',
    'throne_refund',
    'box_refund',
    'box_sale',
    'test_grant',
    'migration',
    'refund_reversed',
  ].contains(type);
  bool get isSettlement => ['throne_settle', 'box_settle'].contains(type);
  String get label =>
      const {
        'purchase': 'شراء عملات',
        'throne_reserve': 'حجز مزايدة العرش',
        'throne_refund': 'إعادة حجز العرش',
        'throne_settle': 'تسوية حجز التتويج',
        'box_reserve': 'حجز صندوق',
        'box_refund': 'إعادة حجز صندوق',
        'box_sale': 'بيع صندوق',
        'box_settle': 'تسوية شراء صندوق',
        'chargeback': 'استرجاع دفعة',
        'refund_reversed': 'إلغاء استرجاع دفعة',
        'test_grant': 'رصيد اختبار',
        'migration': 'رصيد الانتقال',
      }[type] ??
      'عملية محفظة';
}

class WalletProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _store = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
  final _iap = InAppPurchase.instance;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _walletSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSub;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  final Map<String, PurchaseDetails> _pending = {};
  final Set<String> _processing = {};
  bool _disposed = false,
      _started = false,
      _loading = false,
      _iapAvailable = false;
  int _generation = 0, _tiniBalance = 0, _reserved = 0, _debt = 0;
  String? _accountToken;
  String? error;
  String purchaseStatus = '';
  List<ProductDetails> _products = [];
  List<Transaction> _transactions = [];
  bool get isLoading => _loading;
  bool get iapAvailable => _iapAvailable;
  int get tiniBalance => _tiniBalance;
  int get reservedPoints => _reserved;
  int get debt => _debt;
  List<ProductDetails> get products => _products;
  List<Transaction> get transactions => _transactions;
  bool get hasPendingPurchases => _pending.isNotEmpty;
  static const _productIds = {
    'coins_100',
    'coins_500',
    'coins_1200',
    'coins_2500',
  };
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void startWalletSync() {
    if (_started) return;
    _started = true;
    // Attach before any store request so purchases cannot be missed.
    _purchaseSub = _iap.purchaseStream.listen(
      (purchases) {
        for (final purchase in purchases) {
          unawaited(_handle(purchase));
        }
      },
      onError: (Object _) {
        error = 'تعذر استقبال نتيجة المتجر؛ أعد المحاولة';
        notifyListeners();
      },
    );
    _authSub = _auth.authStateChanges().listen(_bind);
    unawaited(_loadProducts());
  }

  void _bind(User? user) {
    final generation = ++_generation;
    _walletSub?.cancel();
    _txSub?.cancel();
    _tiniBalance = 0;
    _reserved = 0;
    _debt = 0;
    _accountToken = null;
    _transactions = [];
    error = null;
    purchaseStatus = '';
    notifyListeners();
    if (user == null) return;
    _walletSub = _store
        .doc('users/${user.uid}')
        .snapshots()
        .listen(
          (doc) {
            if (generation != _generation) return;
            final data = doc.data();
            final ready = data?['walletVersion'] == 2;
            _tiniBalance = ready
                ? (data?['tiniBalance'] as num? ?? 0).toInt()
                : 0;
            _reserved = ready
                ? (data?['throneReservedPoints'] as num? ?? 0).toInt() +
                      (data?['boxReservedPoints'] as num? ?? 0).toInt()
                : 0;
            _debt = (data?['walletDebt'] as num? ?? 0).toInt();
            _accountToken = ready
                ? (data?['purchaseAccountToken'] as String?)
                : null;
            if (doc.exists && !ready && !_loading) {
              unawaited(initWallet());
            }
            notifyListeners();
          },
          onError: (Object _) {
            if (generation == _generation) {
              error = 'تعذر تحديث المحفظة';
              notifyListeners();
            }
          },
        );
    _txSub = _store
        .collection('users/${user.uid}/transactions')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .listen((snap) {
          if (generation != _generation) return;
          _transactions = snap.docs
              .map((d) => Transaction.fromMap(d.id, d.data()))
              .toList();
          notifyListeners();
        });
    unawaited(initWallet());
  }

  Future<void> _loadProducts() async {
    try {
      _iapAvailable = await _iap.isAvailable();
      if (!_iapAvailable) {
        error = 'المتجر غير متاح على هذا الجهاز';
        return;
      }
      final response = await _iap.queryProductDetails(_productIds);
      _products = response.productDetails;
      if (response.error != null || response.notFoundIDs.isNotEmpty) {
        error = 'بعض باقات المتجر غير متاحة حالياً';
      }
      await _iap.restorePurchases();
    } catch (_) {
      error = 'تعذر الاتصال بالمتجر';
    } finally {
      notifyListeners();
    }
  }

  Future<void> initWallet() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      _loading = true;
      notifyListeners();
      final result = await _functions.httpsCallable('createTiniWallet').call({
        'uid': uid,
      });
      if (_auth.currentUser?.uid != uid) return;
      _accountToken = result.data['accountToken'] as String?;
      error = null;
      if (_pending.isNotEmpty) unawaited(retryPendingPurchases());
    } catch (e) {
      if (_auth.currentUser?.uid == uid) {
        error = e is FirebaseFunctionsException
            ? e.message ?? e.code
            : 'تعذر تجهيز المحفظة';
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    final key =
        '${purchase.productID}:${purchase.purchaseID}:${purchase.verificationData.serverVerificationData}';
    if (purchase.status == PurchaseStatus.pending) {
      purchaseStatus = 'بانتظار إتمام الدفع في المتجر';
      notifyListeners();
      return;
    }
    if (purchase.status == PurchaseStatus.error ||
        purchase.status == PurchaseStatus.canceled) {
      purchaseStatus = purchase.status == PurchaseStatus.canceled
          ? 'ألغي الشراء'
          : 'تعذر إتمام الشراء';
      notifyListeners();
      return;
    }
    _pending[key] = purchase;
    if (_processing.contains(key)) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      error = 'سجل الدخول إلى حساب الشراء لإكمال تسليمه';
      notifyListeners();
      return;
    }
    _processing.add(key);
    try {
      purchaseStatus = 'جاري التحقق من الشراء وتسليم العملات';
      notifyListeners();
      final result = await _functions.httpsCallable('verifyTiniPurchase').call({
        'uid': uid,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'productId': purchase.productID,
        'proof': purchase.verificationData.serverVerificationData,
      });
      if (result.data['delivered'] != true) throw StateError('Not delivered');
      // Consume/finish only after the server confirms durable delivery.
      if (Platform.isAndroid) {
        final addition = _iap
            .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        final consumed = await addition.consumePurchase(purchase);
        if (consumed.responseCode != BillingResponse.ok &&
            consumed.responseCode != BillingResponse.itemNotOwned) {
          throw StateError('Store finalization pending');
        }
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      _pending.remove(key);
      if (_auth.currentUser?.uid == uid) {
        purchaseStatus = 'تم تسليم العملات إلى المحفظة';
        error = null;
      }
    } catch (e) {
      if (_auth.currentUser?.uid == uid) {
        error = e is FirebaseFunctionsException
            ? e.message ?? e.code
            : 'التسليم أو تأكيد المتجر معلق؛ اضغط إعادة المحاولة';
        purchaseStatus = 'الشراء بانتظار التأكيد';
      }
    } finally {
      _processing.remove(key);
      notifyListeners();
    }
  }

  Future<void> retryPendingPurchases() async {
    for (final purchase in List<PurchaseDetails>.of(_pending.values)) {
      await _handle(purchase);
    }
    await restorePurchases();
  }

  Future<void> purchaseCoins(String productId) async {
    if (!_iapAvailable || _accountToken == null || _auth.currentUser == null) {
      error = 'المحفظة أو المتجر غير جاهز';
      notifyListeners();
      return;
    }
    try {
      final product = _products.firstWhere((p) => p.id == productId);
      final started = await _iap.buyConsumable(
        autoConsume: false,
        purchaseParam: PurchaseParam(
          productDetails: product,
          applicationUserName: _accountToken,
        ),
      );
      if (!started) throw StateError('Store did not start');
    } catch (_) {
      error = 'تعذر بدء الشراء';
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases(applicationUserName: _accountToken);
    } catch (_) {
      error = 'تعذر البحث عن المشتريات المعلقة';
      notifyListeners();
    }
  }

  Future<void> fetchBalance() async {
    await initWallet();
  }

  void stopWalletSync() {
    _generation++;
    _started = false;
    _authSub?.cancel();
    _walletSub?.cancel();
    _txSub?.cancel();
    _purchaseSub?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    stopWalletSync();
    super.dispose();
  }
}