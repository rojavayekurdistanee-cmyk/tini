import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/*
  [Tini Project Rules]:
  1. File Name: close_account_screen.dart
  2. UI Style: Matched with your colors (0xFF1A222C Surface, 0xFF0F1720 BG).
  3. Logic: Server-managed closure with retryable owned-content cleanup.
*/

class CloseAccountScreen extends StatefulWidget {
  const CloseAccountScreen({super.key});

  @override
  State<CloseAccountScreen> createState() => _CloseAccountScreenState();
}

class _CloseAccountScreenState extends State<CloseAccountScreen> {
  bool _isLoading = false;

  // 🎨 الألوان المأخوذة من الكود اللي أرسلته أنت حرفياً
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;
  final Color errorRed = const Color(0xFFE53935);

  Future<void> _removeClosedAccountFromDevice(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = List<String>.from(prefs.getStringList('saved_accounts') ?? []);
    accounts.remove(uid);
    await prefs.setStringList('saved_accounts', accounts);
    for (final key in ['account_type_$uid', 'acc_${uid}_email',
      'acc_${uid}_fullName', 'acc_${uid}_username', 'acc_${uid}_profileImg']) {
      await prefs.remove(key);
    }
    if (prefs.getString('last_uid') == uid) await prefs.remove('last_uid');
    const storage = FlutterSecureStorage(aOptions: AndroidOptions(
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
      resetOnError: true,
      storageNamespace: 'TitiStar_V5_FinalSafe',
      preferencesKeyPrefix: 'titi_star_v5',
    ));
    for (final key in ['auth_type_$uid', 'auth_pass_$uid', 'auth_phone_$uid']) {
      await storage.delete(key: key);
    }
    // Local-only cleanup: disableForUid also writes users/{uid}, which must
    // never be recreated after closure. Preserve all other saved passkeys.
    final raw = await storage.read(key: 'titi_passkey_list');
    final oldUid = await storage.read(key: 'titi_passkey_uid');
    final accountsWithPasskeys = raw == null
        ? <String>[?oldUid]
        : (jsonDecode(raw) as List).cast<String>();
    accountsWithPasskeys.remove(uid);
    await storage.write(key: 'titi_passkey_list', value: jsonEncode(accountsWithPasskeys));
    if (oldUid == uid) await storage.delete(key: 'titi_passkey_uid');
  }

  Future<void> _permanentlyDeleteAccount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _isLoading) return;
    setState(() => _isLoading = true);
    var accepted = false;
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('requestAccountDeletion')
          .call(<String, dynamic>{'uid': uid});
      if (result.data is! Map || result.data['accepted'] != true) {
        throw StateError('Account closure was not accepted');
      }
      accepted = true;
      // A response for an old session must not sign out a newly switched user.
      if (FirebaseAuth.instance.currentUser?.uid == uid) {
        // AuthProvider's existing authStateChanges listener clears the session
        // and activity service. Do not await another account's offline writes.
        await FirebaseAuth.instance.signOut();
      }
      await _removeClosedAccountFromDevice(uid);
      if (mounted && FirebaseAuth.instance.currentUser == null) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) _showErrorSnackBar(e.message ?? 'تعذر إرسال طلب الإغلاق. حاول مجدداً.');
    } catch (_) {
      if (mounted) {
        _showErrorSnackBar(accepted
            ? 'تم قبول إغلاق الحساب. تعذر تنظيف بعض بياناته المحفوظة على هذا الجهاز.'
            : 'تعذر تأكيد طلب الإغلاق. تحقق من الاتصال وحاول مجدداً.');
        if (accepted && FirebaseAuth.instance.currentUser == null) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: errorRed),
    );
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("تأكيد إغلاق الحساب", 
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          "هل أنت متأكد؟ سيُغلق حسابك نهائياً ويبدأ حذف بياناتك ومنشوراتك وملفاتك ورسائلك في الخلفية. لا يمكن التراجع بعد قبول الطلب.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: errorRed),
            onPressed: () {
              Navigator.pop(context);
              _permanentlyDeleteAccount();
            },
            child: const Text("حذف نهائي", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
        title: const Text("إغلاق الحساب", 
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          children: [
            const SizedBox(height: 30),
            // الأيقونة بنفس لون Teal (0xFF009688) اللي في كود الأرشيف
            Icon(Icons.person_off_outlined, color: titiTeal, size: 80),
            const SizedBox(height: 20),
            const Text(
              "مغادرة تطبيق Tini",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            const Text(
              "عند قبول الطلب يُغلق حسابك، ويتولى السيرفر حذف بياناتك ومنشوراتك وملفاتك ورسائلك في الخلفية.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 30),
            
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: titiTeal, size: 40),
                    const SizedBox(height: 15),
                    const Text(
                      "سياسة حذف البيانات",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "يشمل الحذف بيانات حسابك ومحتواك ورسائلك وتفاعلاتك. تبقى رسائل الآخرين والمجموعات المشتركة والسجلات المالية اللازمة لحماية المعاملات. لا يُقبل الإغلاق مع وجود رصيد أو التزامات مالية.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

            // الزر بنفس لون الـ Teal المعتمد في الأرشيف
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: titiTeal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isLoading ? null : _showConfirmDialog,
                child: _isLoading 
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        "تأكيد إغلاق الحساب", 
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}