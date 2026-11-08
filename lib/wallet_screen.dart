import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'wallet_provider.dart';

/*
  [Tini Project - Wallet UI V2]
    1. Addition only.
    2. Uses bgColor: 0xFF0F1720, surfaceColor: 0xFF1A222C, titiTeal: Colors.teal
    3. Live balance sync with WalletProvider.
    4. Auto createWallet on first open.
    5. IAP Integration: Google Play + App Store.
*/

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  // [Tini: تعديل IAP] - لازم الـ id يكون نفس اللي في جوجل وآبل بالضبط
  final List<Map<String, dynamic>> _packages = [
    {'id': 'coins_100', 'amount': 100, 'price': '4.99', 'bonus': 0},
    {'id': 'coins_500', 'amount': 500, 'price': '19.99', 'bonus': 50},
    {'id': 'coins_1200', 'amount': 1200, 'price': '39.99', 'bonus': 200},
    {'id': 'coins_2500', 'amount': 2500, 'price': '179.99', 'bonus': 500},
  ];

  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final wallet = Provider.of<WalletProvider>(context, listen: false);
      await wallet.initWallet(); // استدعاء createWallet - ينشئ المحفظة لو مش موجودة
      wallet.startWalletSync(); // يبدأ الـ sync بعدها
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    });
  }

  @override
  void dispose() {
    // لا نوقف الـ sync هنا عشان يظل شغال لو رجع للبروفايل
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "محفظة Titi",
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        // [Tini: إضافة IAP] - زر استعادة المشتريات مطلوب من آبل
        actions: [
          Consumer<WalletProvider>(
            builder: (context, wallet, child) {
              return IconButton(
                icon: const Icon(Iconsax.refresh, color: Colors.white70, size: 22),
                tooltip: 'استعادة المشتريات',
                onPressed: () {
                  wallet.restorePurchases();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text("جاري البحث عن مشترياتك السابقة...", textAlign: TextAlign.center),
                      backgroundColor: titiTeal,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Consumer<WalletProvider>(
        builder: (context, wallet, child) {
          if (_isInitializing) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: titiTeal),
                  const SizedBox(height: 15),
                  Text(
                    "جاري تجهيز المحفظة...",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            children: [
              _buildBalanceCard(wallet),
              const SizedBox(height: 25),
              _buildSectionTitle("شراء عملات Titi"),
              const SizedBox(height: 15),
              // [Tini: تعديل IAP] - عرض حالة تحميل المنتجات
              wallet.iapAvailable && wallet.products.isEmpty
               ? Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(15)),
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: titiTeal, strokeWidth: 2),
                          const SizedBox(height: 10),
                          const Text("جاري جلب أسعار المتجر...", style: TextStyle(color: Colors.white38, fontSize: 14)),
                        ],
                      ),
                    )
                  : _buildPackagesGrid(wallet),
              const SizedBox(height: 25),
              _buildSectionTitle("آخر العمليات"),
              const SizedBox(height: 15),
              _buildTransactionsList(wallet),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(WalletProvider wallet) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: titiTeal.withValues(alpha:0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Iconsax.wallet_3, color: Colors.amber, size: 28),
              const SizedBox(width: 10),
              const Text(
                "رصيدك الحالي",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 15),
          wallet.isLoading
           ? const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 3),
                )
              : Text(
                  "${NumberFormat('#,###').format(wallet.titiBalance)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          const SizedBox(height: 5),
          Text(
            "عملة Titi",
            style: TextStyle(color: titiTeal, fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(width: 4, height: 20, decoration: BoxDecoration(color: titiTeal, borderRadius: BorderRadius.circular(10))),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPackagesGrid(WalletProvider wallet) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: _packages.length,
      itemBuilder: (context, index) {
        final package = _packages[index];
        final int totalAmount = package['amount'] + package['bonus'];

        // [Tini: إضافة IAP] - جلب السعر الحقيقي من جوجل/آبل
        final productDetails = wallet.products.where((p) => p.id == package['id']).firstOrNull;

        final String displayPrice = productDetails!= null? productDetails.price : "\$${package['price']}";

        return GestureDetector(
          onTap: () => _handlePurchase(wallet, package),
          child: Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: titiTeal.withValues(alpha:0.3), width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.coin_1, color: Colors.amber, size: 32),
                const SizedBox(height: 10),
                Text(
                  NumberFormat('#,###').format(totalAmount),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text("عملة", style: TextStyle(color: Colors.white70, fontSize: 12)),
                if (package['bonus'] > 0)...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: titiTeal.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "+${package['bonus']} هدية",
                      style: TextStyle(color: titiTeal, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                  decoration: BoxDecoration(
                    color: titiTeal,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    displayPrice, // [Tini: تعديل IAP] - عرض السعر من المتجر
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransactionsList(WalletProvider wallet) {
    if (wallet.transactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(15)),
        child: Column(
          children: [
            Icon(Iconsax.receipt_1, color: Colors.white24, size: 50),
            const SizedBox(height: 10),
            const Text("لا توجد عمليات بعد", style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(15)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: wallet.transactions.length,
        separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha:0.05), height: 1, indent: 15, endIndent: 15),
        itemBuilder: (context, index) {
          final tx = wallet.transactions[index];
          final bool isPurchase = tx.type == 'purchase';
          final String dateStr = DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(tx.createdAt);
          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isPurchase? titiTeal.withValues(alpha:0.15) : Colors.redAccent.withValues(alpha:0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPurchase? Iconsax.arrow_down_2 : Iconsax.arrow_up_1,
                color: isPurchase? titiTeal : Colors.redAccent,
                size: 20,
              ),
            ),
            title: Text(
              isPurchase? "شراء عملات" : "صرف عملات",
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(dateStr, style: TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: Text(
              "${isPurchase? '+' : '-'}${NumberFormat('#,###').format(tx.amount)}",
              style: TextStyle(
                color: isPurchase? titiTeal : Colors.redAccent,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    );
  }

  void _handlePurchase(WalletProvider wallet, Map<String, dynamic> package) async {
    // [Tini: تعديل IAP] - التأكد إن المتجر جاهز
    if (!wallet.iapAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("المتجر غير متاح على هذا الجهاز حالياً", textAlign: TextAlign.center),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    // عرض Dialog تأكيد قبل الدفع
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "تأكيد الشراء",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.coin_1, color: Colors.amber, size: 50),
            const SizedBox(height: 15),
            Text(
              "شراء ${NumberFormat('#,###').format(package['amount'] + package['bonus'])} عملة",
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "سيتم الدفع عبر ${Theme.of(context).platform == TargetPlatform.iOS? 'App Store' : 'Google Play'}",
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("إلغاء", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: titiTeal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text("متابعة للدفع", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm!= true) return;

    // [Tini: تعديل IAP] - استدعاء الشراء من Provider
    // هذا السطر يفتح شاشة الدفع الرسمية تبع جوجل/آبل
    await wallet.purchaseCoins(package['id']);
  }
}