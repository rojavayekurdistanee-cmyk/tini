import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart'; // [Tini: إضافة IAP]
import 'dart:async';
import 'dart:io'; // [Tini: IAP] - عشان Platform.isIOS

/*
  [Tini Project Rules]:
    1. No line deletion.
    2. Addition only.
    3. Consistent naming with Firestore keys.
    4. Rules Followed: Return full code, professional status management.
    5. Wallet Module V2: Manages Titi Coins with Google Play + App Store IAP.
*/

// [Tini: إضافة IAP] - لازم تعرف هذا في main.dart عشان نستخدم الكونتكست
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class Transaction {
  final String id;
  final int amount;
  final String type; // 'purchase' | 'spend' | 'reward'
  final DateTime createdAt;
  final String? packageId;

  Transaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.createdAt,
    this.packageId,
  });

  factory Transaction.fromMap(String id, Map<String, dynamic> data) {
    return Transaction(
      id: id,
      amount: data['amount']?? 0,
      type: data['type']?? 'purchase',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate()?? DateTime.now(),
      packageId: data['packageId'],
    );
  }
}

class WalletProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  int _titiBalance = 0;
  int get titiBalance => _titiBalance;

  List<Transaction> _transactions = [];
  List<Transaction> get transactions => _transactions;

  StreamSubscription<DocumentSnapshot>? _walletSubscription;
  StreamSubscription<QuerySnapshot>? _transactionsSubscription;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  // [Tini: إضافة IAP] - متغيرات الشراء
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;
  bool _iapAvailable = false;
  bool get iapAvailable => _iapAvailable;

  // [Tini: إضافة IAP] - معرفات المنتجات لازم تكون نفسها في جوجل وآبل
  static const Set<String> _productIds = {
    'coins_100',
    'coins_500', 
    'coins_1200',
    'coins_2500',
  };

  // [إضافة Tini]: بدء المزامنة اللحظية للرصيد
  void startWalletSync() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _walletSubscription?.cancel();
    _transactionsSubscription?.cancel();
    _purchaseSubscription?.cancel();

    // [Tini: إضافة IAP] - تهيئة نظام الشراء
    _initIAP();

    _walletSubscription = FirebaseFirestore.instance
       .collection('users')
       .doc(user.uid)
       .snapshots()
       .listen((doc) {
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        _titiBalance = data['titiBalance']?? 0;
        notifyListeners();
        print("--- [Tini Wallet]: الرصيد الآن متزامن: $_titiBalance ---");
      } else {
        initWallet();
      }
    }, onError: (error) {
      print("--- [Tini Wallet Error]: فشل مزامنة الرصيد: $error ---");
    });

    _transactionsSubscription?.cancel();
    _transactionsSubscription = FirebaseFirestore.instance
       .collection('users')
       .doc(user.uid)
       .collection('transactions')
       .orderBy('createdAt', descending: true)
       .limit(20)
       .snapshots()
       .listen((snapshot) {
      _transactions = snapshot.docs
         .map((doc) => Transaction.fromMap(doc.id, doc.data()))
         .toList();
      notifyListeners();
    }, onError: (error) {
      print("--- [Tini Wallet Error]: فشل جلب العمليات: $error ---");
      _transactions = [];
      notifyListeners();
    });
  }

  // [Tini: إضافة IAP] - تهيئة نظام الشراء من جوجل وآبل
  Future<void> _initIAP() async {
    _iapAvailable = await _iap.isAvailable();
    if (!_iapAvailable) {
      print("--- [Tini Wallet Error]: المتجر غير متاح على هذا الجهاز ---");
      return;
    }

    // جلب المنتجات من المتجر
    await _loadProducts();

    // الاستماع لنتائج الدفع
    _purchaseSubscription = _iap.purchaseStream.listen(
      (List<PurchaseDetails> purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList);
      },
      onDone: () {
        _purchaseSubscription?.cancel();
      },
      onError: (error) {
        print("--- [Tini Wallet Error]: خطأ في stream الشراء: $error ---");
      },
    );
  }

  // [Tini: إضافة IAP] - جلب المنتجات من جوجل بلاي وآب ستور
  Future<void> _loadProducts() async {
    try {
      final ProductDetailsResponse response = await _iap.queryProductDetails(_productIds);
      if (response.notFoundIDs.isNotEmpty) {
        print("--- [Tini Wallet Warning]: منتجات غير موجودة: ${response.notFoundIDs} ---");
      }
      _products = response.productDetails;
      notifyListeners();
      print("--- [Tini Wallet]: تم جلب ${products.length} منتجات من المتجر ---");
    } catch (e) {
      print("--- [Tini Wallet Error]: فشل جلب المنتجات: $e ---");
    }
  }

  // [Tini: إضافة IAP] - معالجة نتيجة الشراء من جوجل/آبل
  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        print("--- [Tini Wallet]: عملية شراء معلقة... ---");
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          print("--- [Tini Wallet Error]: فشل الشراء: ${purchaseDetails.error} ---");
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          // [Tini: تعديل IAP] - نحفظ في pending_purchases بدل استدعاء Function
          await _savePurchaseToFirestore(purchaseDetails);
        }
        // إنهاء العملية عشان ما يرجع جوجل الفلوس
        if (purchaseDetails.pendingCompletePurchase) {
          await _iap.completePurchase(purchaseDetails);
        }
      }
    }
  }

  // [Tini: تعديل IAP] - حفظ الفاتورة في Firestore عشان الـ Function تشتغل
  Future<void> _savePurchaseToFirestore(PurchaseDetails purchaseDetails) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      _setLoading(true);
      
      // [Tini: مهم] - هذي البيانات اللي بتروح للـ Function processTitiPurchase
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('pending_purchases')
          .add({
        'productId': purchaseDetails.productID,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'purchaseToken': purchaseDetails.verificationData.serverVerificationData, // للأندرويد
        'receiptData': purchaseDetails.verificationData.localVerificationData, // للآيفون
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      print("--- [Tini Wallet]: تم إرسال الفاتورة للسيرفر للتحقق ---");
      
    } catch (e) {
      print("--- [Tini Wallet Error]: فشل حفظ الفاتورة: $e ---");
    } finally {
      _setLoading(false);
    }
  }

  // [إضافة Tini]: إيقاف المزامنة
  void stopWalletSync() {
    _walletSubscription?.cancel();
    _transactionsSubscription?.cancel();
    _purchaseSubscription?.cancel(); // [Tini: إضافة IAP]
  }

  // [إضافة Tini]: إنشاء المحفظة أول مرة - عبر Cloud Function
  Future<void> initWallet() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      _setLoading(true);
      final result = await _functions.httpsCallable('createWallet')
          .call()
          .timeout(const Duration(seconds: 10));
      _titiBalance = result.data['balance'] ?? 0;
      notifyListeners();
      print("--- [Tini Wallet]: ${result.data['message']} ---");
    } on TimeoutException {
      print("--- [Tini Wallet Error]: انتهت مهلة إنشاء المحفظة ---");
    } catch (e) {
      print("--- [Tini Wallet Error]: فشل إنشاء المحفظة: $e ---");
      // Fallback: إنشاء مباشر لو فشل الـ Function
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'titiBalance': 0,
          'walletCreatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _titiBalance = 0;
        notifyListeners();
        print("--- [Tini Wallet]: تم إنشاء المحفظة محلياً بنجاح ---");
      } catch (fallbackError) {
        print("--- [Tini Wallet Error]: فشل الإنشاء المحلي: $fallbackError ---");
      }
    } finally {
      _setLoading(false);
    }
  }

  // [إضافة Tini]: جلب الرصيد يدوياً - للاحتياط
  Future<void> fetchBalance() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _setLoading(true);
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
         .collection('users')
         .doc(user.uid)
         .get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        _titiBalance = data['titiBalance']?? 0;
        notifyListeners();
      } else {
        await initWallet();
      }
    } catch (e) {
      print("--- [Tini Wallet Error]: فشل جلب الرصيد: $e ---");
    } finally {
      _setLoading(false);
    }
  }

  // [Tini: تعديل IAP] - شراء العملات عبر جوجل بلاي/آب ستور
  Future<void> purchaseCoins(String productId) async {
    if (!_iapAvailable) {
      print("--- [Tini Wallet Error]: المتجر غير متاح ---");
      return;
    }

    try {
      final ProductDetails productDetails = _products.firstWhere(
        (product) => product.id == productId,
        orElse: () => throw Exception('المنتج غير موجود'),
      );

      final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
      
      // هذا يفتح شاشة الدفع الرسمية تبع جوجل/آبل
      await _iap.buyConsumable(purchaseParam: purchaseParam);
      
    } catch (e) {
      print("--- [Tini Wallet Error]: فشل بدء عملية الشراء: $e ---");
    }
  }

  // [Tini: إضافة IAP] - استعادة المشتريات - مطلوب من آبل
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
      print("--- [Tini Wallet]: تم طلب استعادة المشتريات ---");
    } catch (e) {
      print("--- [Tini Wallet Error]: فشل استعادة المشتريات: $e ---");
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    stopWalletSync();
    super.dispose();
  }
}