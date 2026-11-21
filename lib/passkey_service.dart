import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class PasskeyService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
      resetOnError: true,
      storageNamespace: 'TitiStar_V5_FinalSafe',
      preferencesKeyPrefix: 'titi_star_v5',
    ),
  );
  static final _auth = LocalAuthentication();
  static const _keyUid = 'titi_passkey_uid'; // للتوافق القديم
  static const _keyList = 'titi_passkey_list'; // الجديد: ليستة حسابات

  // يدعم البصمة أو بيانات اعتماد قفل الجهاز (PIN / pattern / password).
  static Future<bool> canCheck() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  // --- الجديد: شغلات تعدد الحسابات ---

  static Future<List<String>> _getEnabledUids() async {
    final jsonStr = await _storage.read(key: _keyList);
    if (jsonStr != null) {
      try {
        final List list = jsonDecode(jsonStr);
        return list.cast<String>();
      } catch (e) {}
    }
    // توافق قديم: اذا كان في uid واحد قديم حوله لليستة
    final oldUid = await _storage.read(key: _keyUid);
    if (oldUid != null) {
      return [oldUid];
    }
    return [];
  }

  static Future<void> _saveEnabledUids(List<String> uids) async {
    await _storage.write(key: _keyList, value: jsonEncode(uids));
    // نمسح القديم مشان ما يضل يعمل مشاكل
    await _storage.delete(key: _keyUid);
  }

  // هل هاد الحساب بالذات مفعل بصمة؟
  static Future<bool> isEnabledForUid(String uid) async {
    final list = await _getEnabledUids();
    return list.contains(uid);
  }

  // تفعيل بصمة لحساب معين - هاد يلي رح تستخدمه تحت كل حساب
  static Future<bool> enableForUid(String uid) async {
    if (uid.isEmpty || FirebaseAuth.instance.currentUser?.uid != uid) {
      return false;
    }
    if (!await canCheck()) return false;

    final didAuth = await _auth.authenticate(
      localizedReason: 'تأكيد هويتك لتفعيل الدخول السريع في Tini',
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
      ),
    );
    if (!didAuth || FirebaseAuth.instance.currentUser?.uid != uid) {
      return false;
    }

    final list = await _getEnabledUids();
    final alreadyEnabled = list.contains(uid);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'passkeyEnabled': true,
      }, SetOptions(merge: true));
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('تغير الحساب أثناء تفعيل الدخول السريع');
      }
      if (!alreadyEnabled) {
        list.add(uid);
        await _saveEnabledUids(list);
      }
      return true;
    } catch (_) {
      if (!alreadyEnabled) {
        list.remove(uid);
        try {
          await _saveEnabledUids(list);
        } catch (_) {}
      }
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'passkeyEnabled': false,
        }, SetOptions(merge: true));
      } catch (_) {}
      rethrow;
    }
  }

  // حذف بصمة لحساب معين
  static Future<void> disableForUid(String uid) async {
    if (uid.isEmpty || FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('لا يمكن تعطيل الدخول السريع لحساب غير نشط');
    }
    final list = await _getEnabledUids();
    final wasEnabled = list.contains(uid);
    list.remove(uid);
    await _saveEnabledUids(list);
    try {
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('تغير الحساب أثناء تعطيل الدخول السريع');
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'passkeyEnabled': false,
      }, SetOptions(merge: true));
    } catch (_) {
      if (wasEnabled) {
        final restored = await _getEnabledUids();
        if (!restored.contains(uid)) restored.add(uid);
        try {
          await _saveEnabledUids(restored);
        } catch (_) {}
      }
      rethrow;
    }
  }

  // دخول ببصمة لحساب معين - هاد يلي رح تستخدمه تحت كل حساب
  static Future<bool> authenticateForUid(String uid) async {
    try {
      if (!await isEnabledForUid(uid)) {
        print("DEBUG authenticateForUid: $uid مو مفعل");
        return false;
      }
      return await _auth.authenticate(
        localizedReason: 'تسجيل دخول سريع لـ Tini',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      print("authenticateForUid ERROR: $e");
      return false;
    }
  }

  // --- القديم: خليتو متل ما هو بس صار يشتغل على الليستة الجديدة ---

  static Future<bool> isEnabledLocal() async {
    final list = await _getEnabledUids();
    return list.isNotEmpty;
  }

  static Future<String?> getStoredUid() async {
    final list = await _getEnabledUids();
    if (list.isNotEmpty) return list.first;
    return _storage.read(key: _keyUid);
  }

  // تفعيل (قديم - للحساب الحالي)
  static Future<bool> enable() async {
    print("DEBUG enable() started");
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return await enableForUid(user.uid);
  }

  // حذف (قديم - للحساب الحالي)
  static Future<void> disable() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await disableForUid(user.uid);
    } else {
      final uid = await _storage.read(key: _keyUid);
      if (uid != null) await disableForUid(uid);
    }
  }

  // دخول (قديم)
  static Future<bool> authenticateForLogin() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'تسجيل دخول سريع لـ Tini',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      print("authenticateForLogin ERROR: $e");
      return false;
    }
  }
}