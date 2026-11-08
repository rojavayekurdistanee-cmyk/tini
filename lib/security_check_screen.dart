import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:remixicon/remixicon.dart';
import 'account_details_screen.dart';
import 'password_management_screen.dart';
import 'security_alerts.dart';
import 'two_factor_setup_screen.dart';
import 'auth_provider.dart' as custom;

class SecurityCheckScreen extends StatelessWidget {
  const SecurityCheckScreen({super.key});

  static const Color bgColor = Color(0xFF0F1720);
  static const Color surfaceColor = Color(0xFF1A222C);
  static const Color errorRed = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, authSnap) {
        final authUser = authSnap.data;
        final uid = authUser?.uid;
        if (uid == null || authUser == null) {
          return const Scaffold(
            backgroundColor: bgColor,
            body: Center(child: Text("سجل دخول", style: TextStyle(color: Colors.white54))),
          );
        }

        // [FIX V8] فصل البريد عن جوجل - نفس حل account_details
        final User user = authUser;
        final bool hasGoogle = user.providerData.any((p) => p.providerId == 'google.com');
        final bool hasPassword = user.providerData.any((p) => p.providerId == 'password');
        final bool hasPhoneProvider = user.providerData.any((p) => p.providerId == 'phone');
        final String googleEmail = hasGoogle
            ? (user.providerData.firstWhere((p) => p.providerId == 'google.com').email ?? "مرتبط")
            : "";
        final String passwordEmail = hasPassword
            ? (user.providerData.firstWhere((p) => p.providerId == 'password').email ?? "")
            : "";
        final String phoneFromProvider = hasPhoneProvider
            ? (user.providerData.firstWhere((p) => p.providerId == 'phone').phoneNumber ?? "")
            : "";

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: bgColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
            builder: (context, userSnap) {
              if (!userSnap.hasData) {
                return const Center(child: CircularProgressIndicator(color: Colors.teal));
              }
              final userData = userSnap.data?.data() as Map<String, dynamic>?;
              final firestoreEmail = (userData?['email'] as String?)?.trim() ?? "";
              final firestorePhone = (userData?['phoneNumber'] as String?)?.trim() ?? (userData?['phone'] as String?)?.trim() ?? "";

              // الحل: البريد محسوب بس اذا في مزود باسورد، والهاتف بس اذا في مزود هاتف
              bool hasEmail = hasPassword && (passwordEmail.isNotEmpty || firestoreEmail.isNotEmpty);
              bool hasPhone = hasPhoneProvider && (phoneFromProvider.isNotEmpty || firestorePhone.isNotEmpty);
              bool has2FA = (userData?['twoFactorEnabled'] == true);
              bool hasPasskey = (userData?['passkeyEnabled'] == true);

              bool isPasswordOk = true;
              String passwordSub = "لقد حدّثت كلمة المرور.";
              if (userData?['passwordUpdatedAt'] is Timestamp) {
                final lastUpdate = (userData!['passwordUpdatedAt'] as Timestamp).toDate();
                final daysDiff = DateTime.now().difference(lastUpdate).inDays;
                if (daysDiff > 90) {
                  isPasswordOk = false;
                  passwordSub = "لم تقم بتحديث كلمة المرور منذ $daysDiff يوم، يُنصح بتحديثها.";
                }
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users').doc(uid).collection('securityAlerts')
                    .orderBy('date', descending: true).snapshots(),
                builder: (context, alertsSnap) {
                  bool hasSecurityIssues = false;
                  List<QueryDocumentSnapshot> filtered = [];
                  if (alertsSnap.hasData && !alertsSnap.hasError) {
                    final now = DateTime.now();
                    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
                    filtered = alertsSnap.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final ts = data['date'];
                      if (ts is Timestamp) return ts.toDate().isAfter(thirtyDaysAgo);
                      return false;
                    }).toList();
                    hasSecurityIssues = filtered.isNotEmpty;
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users').doc(uid).collection('activeSessions').snapshots(),
                    builder: (context, sessionsSnap) {
                      int sessionsCount = 0;
                      if (sessionsSnap.hasData) {
                        sessionsCount = sessionsSnap.data!.docs.length;
                      }
                      bool isDevicesOk = sessionsCount <= 3;
                      String devicesSub = isDevicesOk
                          ? (sessionsCount == 0 ? "إدارة أجهزتك." : "يوجد $sessionsCount جهاز نشط حالياً.")
                          : "يوجد $sessionsCount أجهزة مسجلة، راجع الأجهزة الغريبة.";

                      int totalChecks = 8;
                      int passedChecks = 0;
                      if (hasEmail) passedChecks++;
                      if (hasPhone) passedChecks++;
                      if (hasGoogle) passedChecks++;
                      if (has2FA) passedChecks++;
                      if (isPasswordOk) passedChecks++;
                      if (hasPasskey) passedChecks++;
                      if (isDevicesOk) passedChecks++;
                      if (!hasSecurityIssues) passedChecks++;

                      String headerTitle = passedChecks == totalChecks
                          ? "أحسنت، لقد راجعت نصائح الأمان للحفاظ على حسابك آمنًا."
                          : "أمان حسابك $passedChecks/$totalChecks - يحتاج لبعض التحسينات.";

                      return ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          const SizedBox(height: 10),
                          const Center(child: Text("فحص الأمان", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                          const SizedBox(height: 10),
                          Center(
                            child: Text(headerTitle,
                                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                          ),
                          const SizedBox(height: 30),
                          Container(
                            decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              children: [
                                _item(
                                  context: context,
                                  title: "البريد الإلكتروني",
                                  sub: hasEmail ? firestoreEmail : "أضف عنوان بريدك الإلكتروني لاستعادة حسابك بسهولة في حالة فقدان الوصول إليه.",
                                  ok: hasEmail,
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AccountDetailsScreen()));
                                  },
                                ),
                                _item(
                                  context: context,
                                  title: "حساب Google",
                                  sub: hasGoogle ? googleEmail : "اربط حساب Google لتسجيل دخول أسرع وأكثر أماناً.",
                                  ok: hasGoogle,
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AccountDetailsScreen()));
                                  },
                                ),
                                _item(
                                  context: context,
                                  title: "التحقق بخطوتين",
                                  sub: has2FA ? "التحقق بخطوتين مفعّل على حسابك." : "أضف التحقق الإضافي لتسجيل الدخول لمزيد من الأمان.",
                                  ok: has2FA,
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const TwoFactorSetupScreen()));
                                  },
                                ),
                                _item(
                                  context: context,
                                  title: "الهاتف",
                                  sub: hasPhone ? firestorePhone : "أضف رقم هاتفك",
                                  ok: hasPhone,
                                  extraSub: hasPhone ? "آخر تحديث: الآن" : null,
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AccountDetailsScreen()));
                                  },
                                ),
                                _item(
                                  context: context,
                                  title: "أجهزتك",
                                  sub: devicesSub,
                                  ok: isDevicesOk,
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const UserDevicesScreen()));
                                  },
                                ),
                                _item(
                                  context: context,
                                  title: "النشاط الأمني",
                                  sub: hasSecurityIssues ? "تم اكتشاف نشاط غير عادي" : "لم يتم اكتشاف أي نشاط غير عادي خلال آخر 30 يومًا.",
                                  ok: !hasSecurityIssues,
                                  onTap: () {
                                    if (hasSecurityIssues) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => SecurityAlertsDetailScreen(hasAlerts: true, docs: filtered)),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: const Color(0xFF1A222C),
                                          behavior: SnackBarBehavior.floating,
                                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            side: const BorderSide(color: Color(0xFF1C1C1E), width: 1),
                                          ),
                                          duration: const Duration(seconds: 3),
                                          content: Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              const Expanded(
                                                child: Text("لا يوجد أي نشاط أمني خلال الـ 30 يوم الماضية",
                                                    textAlign: TextAlign.right,
                                                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, height: 1.4)),
                                              ),
                                              const SizedBox(width: 12),
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                                                child: const Icon(Icons.verified_user, color: Colors.white, size: 16),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                _item(
                                  context: context,
                                  title: "مفتاح المرور",
                                  sub: hasPasskey
                                      ? "لقد أنشأت مفتاح مرور لتسجيل الدخول بشكل أسرع وأكثر أمانًا."
                                      : "أنشئ مفتاح مرور لتسجيل الدخول بشكل أسرع وأكثر أمانًا بدون كلمة مرور.",
                                  ok: hasPasskey,
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      backgroundColor: surfaceColor,
                                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                      builder: (ctx) {
                                        return Consumer<custom.AuthProvider>(
                                          builder: (context, authProv, _) {
                                            final bool isEnabled = authProv.passkeyEnabled || hasPasskey;
                                            return Padding(
                                              padding: const EdgeInsets.all(20),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
                                                  const SizedBox(height: 20),
                                                  const Icon(Remix.fingerprint_line, size: 50, color: Colors.teal),
                                                  const SizedBox(height: 15),
                                                  Text(isEnabled ? "مفتاح المرور مفعل" : "تفعيل مفتاح المرور", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 10),
                                                  Text(isEnabled ? "يمكنك الآن تسجيل الدخول بالبصمة" : "فعل الدخول السريع بالبصمة لهذا الجهاز بدون كلمة مرور", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                                  const SizedBox(height: 30),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    height: 50,
                                                    child: ElevatedButton(
                                                      style: ElevatedButton.styleFrom(backgroundColor: isEnabled ? errorRed : Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                                      onPressed: () async {
                                                        if (isEnabled) {
                                                          await authProv.disablePasskey();
                                                        } else {
                                                          bool ok = await authProv.enablePasskey();
                                                          if (!ok && ctx.mounted) {
                                                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("هذا الجهاز لا يدعم البصمة")));
                                                          }
                                                        }
                                                        if (ctx.mounted) Navigator.pop(ctx);
                                                      },
                                                      child: Text(isEnabled ? "إلغاء تفعيل البصمة" : "تفعيل الآن", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                                _item(
                                  context: context,
                                  title: "كلمة المرور",
                                  sub: passwordSub,
                                  ok: isPasswordOk,
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const PasswordManagementScreen()));
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _item({
    required BuildContext context,
    required String title,
    required String sub,
    required bool ok,
    String? extraSub,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.arrow_back_ios, size: 14, color: Colors.white24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: ok ? Colors.teal : errorRed,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(ok ? Icons.check : Icons.priority_high, size: 16, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(sub, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
                  if (extraSub != null) ...[
                    const SizedBox(height: 2),
                    Text(extraSub, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}