import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
import 'audience_policy.dart';

/*
  [Tini Project Rules]:
    1. File Name: audience_control_screen.dart
    2. Concept: Grouped Sections (Exposed, not hidden).
    3. UI Style: Teal Accents, Dark Surface #1A222C, Clear Headers - Matched from notifications_settings_page.dart
    4. Anti-Flicker: Optimized for smooth navigation and fixed background.
*/

class AudienceControlScreen extends StatefulWidget {
  const AudienceControlScreen({super.key});

  @override
  State<AudienceControlScreen> createState() => _AudienceControlScreenState();
}

class _AudienceControlScreenState extends State<AudienceControlScreen> {
  bool is18Plus = false;
  bool isLoading = true;
  bool isSaving = false;
  String? _loadedUid;
  String? _requestedUid;
  int _loadVersion = 0;

  // --- نفس الألوان المأخوذة من الصفحة السابقة ---
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color fieldColor = const Color(0xFF1C1C1E);
  final Color titiTeal = Colors.teal;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = Provider.of<custom.AuthProvider>(context).uid;
    if (_requestedUid != uid) {
      _loadedUid = null;
      isLoading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _requestedUid = uid ?? '';
    final request = ++_loadVersion;
    try {
      if (uid == null) throw StateError('يجب تسجيل الدخول');
      // قراءة احتياطية من ملفك الرئيسي - هو الأساس
      final userDoc = await _userDoc(uid)
          .get(const GetOptions(source: Source.server));
      if (!userDoc.exists || userDoc.metadata.isFromCache ||
          userDoc.metadata.hasPendingWrites) throw StateError('تعذر قراءة إعداد الجمهور');
      if (!mounted || request != _loadVersion || FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() {
        is18Plus = AudiencePolicy.isAccountRestricted(userDoc.data()!);
        _loadedUid = uid;
      });
    } catch (_) {
      if (mounted && request == _loadVersion) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل إعداد الجمهور. أعد فتح الصفحة للمحاولة.')),
        );
      }
    } finally {
      if (mounted && request == _loadVersion) setState(() => isLoading = false);
    }
  }

  Future<void> _save(bool v) async {
    if (isSaving || _loadedUid == null ||
        FirebaseAuth.instance.currentUser?.uid != _loadedUid) return;
    final uid = _loadedUid;
    setState(() => isSaving = true);
    try {
      // [AUDIENCE CONTROL - FIXED] - كان يحفظ حقل واحد بس، هلا بيحفظ كل الحقول اللي نفلتر عليها
      // [AUDIENCE CONTROL] - تحديث فيديوهاتك الحالية الـ 100 الأخيرة لتكون 18+ ايضاً
      // أُلغي النسخ إلى الفيديوهات؛ يحفظ المزود إعداد الحساب وتفضيلاته معاً فقط.
      await Provider.of<custom.AuthProvider>(context, listen: false).updateAudienceControl(v);
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() => is18Plus = v);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ إعداد الجمهور. لم يتم تأكيد التغيير. حاول مجدداً.')),
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
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
        title: const Text("التحكم في الجمهور", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: isLoading 
      ? const Center(child: CircularProgressIndicator(color: Colors.teal))
      : ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _buildSectionHeader("المحتوى"),
          _buildSettingsGroup([
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Switch(
                        value: is18Plus,
                        onChanged: isSaving || _loadedUid == null ||
                            FirebaseAuth.instance.currentUser?.uid != _loadedUid ? null : (v) => _save(v),
                        activeThumbColor: Colors.white,
                        activeTrackColor: Colors.teal,
                        inactiveThumbColor: Colors.white54,
                        inactiveTrackColor: const Color(0xFF2A3542),
                      ),
                      const Row(
                        children: [
                          Icon(Iconsax.shield_tick, color: Colors.white70, size: 20),
                          SizedBox(width: 8),
                          Text("18 سنة وأكبر", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "اجعل ملفك الشخصي والفيديوهات المستقبلية وفيديوهات البث المباشر مقصورة على الأشخاص الذين تبلغ أعمارهم 18 عامًا أو أكبر. لن تتمكن من تغيير ذلك بالنسبة للمحتوى الفردي.",
                    style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.7),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // نفس دوال البناء المأخوذة من الصفحة السابقة
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 25, bottom: 10),
      child: Text(title, style: TextStyle(color: Colors.teal.shade300, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSettingsGroup(List<Widget> tiles) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(18)),
      child: Column(children: tiles),
    );
  }
}