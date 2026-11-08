import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

Future<void> saveActiveSession(String uid, {String loginMethod = 'email'}) async {
  try {
    final deviceInfo = DeviceInfoPlugin();
    String deviceName = "جهاز غير معروف";
    String deviceId = "unknown_device";

    if (kIsWeb) {
      final webInfo = await deviceInfo.webBrowserInfo;
      deviceName = "${webInfo.browserName} - Web";
      deviceId = "${webInfo.browserName}_${webInfo.userAgent}".hashCode.toString();
    } else {
      final androidInfo = await deviceInfo.androidInfo;
      deviceName = "${androidInfo.manufacturer} ${androidInfo.model}".trim();
      if (deviceName.isEmpty) deviceName = androidInfo.model ?? "Android Device";
      deviceId = androidInfo.id;
      if (deviceId.isEmpty) {
        deviceId = androidInfo.fingerprint;
      }
    }
    
    deviceName = deviceName.replaceAll(RegExp(r'[/*?[\]#]'), '_');
    deviceId = deviceId.replaceAll(RegExp(r'[/*?[\]#]'), '_');

    String methodText = 'تسجيل دخول بالإيميل';
    if (loginMethod == 'google') methodText = 'تسجيل دخول عبر Google';
    if (loginMethod == 'phone') methodText = 'تسجيل دخول عبر الهاتف';
    if (loginMethod == 'email') methodText = 'تسجيل دخول بالإيميل';
    if (loginMethod == 'passkey') methodText = 'تسجيل دخول بمفتاح المرور 🔑';

    final userSessionsRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('activeSessions');
    final docRef = userSessionsRef.doc(deviceId);

    await docRef.set({
      'deviceId': deviceId,
      'deviceName': deviceName,
      'app': 'Tini تطبيق',
      'loginMethod': methodText,
      'date': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'isWeb': kIsWeb,
      'rawMethod': loginMethod,
    }, SetOptions(merge: true));
    
  } catch(e, st){
    print("❌ خطأ saveActiveSession: $e");
  }
}

Future<bool> isNewDevice(String uid) async {
  try {
    String deviceId = await getCurrentDeviceId();
    final userSessionsRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('activeSessions');
    final doc = await userSessionsRef.doc(deviceId).get();
    final allSessions = await userSessionsRef.get();
    if (allSessions.docs.isEmpty) return false;
    return !doc.exists;
  } catch (e) {
    return false;
  }
}

Future<String> getCurrentDeviceId() async {
  try {
    final deviceInfo = DeviceInfoPlugin();
    if (kIsWeb) {
      final webInfo = await deviceInfo.webBrowserInfo;
      return "${webInfo.browserName}_${webInfo.userAgent}".hashCode.toString();
    } else {
      final androidInfo = await deviceInfo.androidInfo;
      String id = androidInfo.id;
      if (id.isEmpty) id = androidInfo.fingerprint;
      return id.replaceAll(RegExp(r'[/*?[\]#]'), '_');
    }
  } catch (e) {
    return "unknown_device";
  }
}