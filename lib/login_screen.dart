import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';
import 'package:remixicon/remixicon.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl_phone_field/intl_phone_field.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:titi_star/home_screen.dart'; 
import 'package:titi_star/auth_provider.dart' as custom;
import 'audience_policy.dart';
import 'dart:math'; 
import 'app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'two_factor_challenge_screen.dart';
import 'passkey_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

Future<String> getRealDeviceName() async {
  try {
    final d = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await d.androidInfo;
      return "${a.manufacturer} ${a.model}";
    }
  } catch (_) {}
  return "Android Device";
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int selectedTabIndex = 1;
  final FirebaseAuth _auth = FirebaseAuth.instance;


Future<void> _checkUserAndNavigate(String uid, String type) async {
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
    final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);

    bool twoFactorEnabled = false;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      twoFactorEnabled = doc.data()?['twoFactorEnabled'] == true;
    } catch (_) {}

    bool isNew = await isNewDevice(uid);

    if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
    if (isNew && twoFactorEnabled) {
      // [Tini Fix]: ابقاء currentUser موجود مشان TwoFactorChallengeScreen يقدر يعمل reauthenticate
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => TwoFactorChallengeScreen(uid: uid, firstLoginType: type)),
          (route) => false,
        );
      }
      return;
    }

    await saveActiveSession(uid, loginMethod: type);

    try {
      String city = '', country = '', loc = 'تسجيل دخول جديد';
      try {
      final r = await http.get(Uri.parse('https://ipwho.is/')).timeout(Duration(seconds: 5));
if (r.statusCode == 200) {
  final j = json.decode(r.body);
  city = j['city'] ?? '';
  country = j['country'] ?? '';
  loc = city.isNotEmpty && country.isNotEmpty ? '$city, $country' : (country.isNotEmpty ? country : loc);
}
      } catch (_) {}
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('login_history').add({
        'deviceName': await getRealDeviceName(),
        'city': city,
        'country': country,
        'location': loc,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    await authProvider.syncCurrentAccountToVault(uid, type);

    await authProvider.fetchUserData();

    if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
      if (authProvider.profileCompleted && authProvider.birthDate.isNotEmpty) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      } else {
        final hasDob = authProvider.birthDate.isNotEmpty;
        if (!hasDob) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => BirthdayScreen(isGoogleAuth: type == "google", existingUserId: uid)),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => NameSelectionScreen(userId: uid)),
          );
        }
      }
    }
  }
Future<void> _saveAccountLocally(String uid, String type) async {
  final prefs = await SharedPreferences.getInstance();
  // [ADDITION ONLY - saveLoginInfo Check]
  try {
    bool saveInfo = prefs.getBool('saveLoginInfo') ?? true;
    if (!saveInfo) return;
  } catch (_) {}
  List<String> savedUids = prefs.getStringList('saved_accounts')?? [];
  savedUids.remove(uid);
  savedUids.insert(0, uid);
  if (savedUids.length > 5) savedUids = savedUids.sublist(0, 5);
  await prefs.setStringList('saved_accounts', savedUids);
  await prefs.setString('account_type_$uid', type);

  // [إضافة V5.8 - حل حساب صديقك] بدون حذف: حفظ بيانات الحساب محليا للعرض بعد تسجيل الخروج
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      if (currentUser.email != null && currentUser.email!.isNotEmpty) {
        await prefs.setString('acc_${uid}_email', currentUser.email!);
      }
      if (currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
        await prefs.setString('acc_${uid}_fullName', currentUser.displayName!);
      }
      // حاول تجيب باقي البيانات من Firestore اذا مسموح
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['email'] != null) await prefs.setString('acc_${uid}_email', data['email']);
          if (data['fullName'] != null) await prefs.setString('acc_${uid}_fullName', data['fullName']);
          if (data['username'] != null) await prefs.setString('acc_${uid}_username', data['username']);
          if (data['profileImg'] != null) await prefs.setString('acc_${uid}_profileImg', data['profileImg']);
        }
      } catch (_) {}
    }
  } catch (_) {}
}

Future<List<String>> _getLocalSavedAccounts() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList('saved_accounts')?? [];
}

Future<void> _removeSavedAccount(String uid) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> savedUids = prefs.getStringList('saved_accounts')?? [];
  savedUids.remove(uid);
  await prefs.setStringList('saved_accounts', savedUids);
  await prefs.remove('account_type_$uid');
  await prefs.remove('acc_${uid}_email');
  await prefs.remove('acc_${uid}_fullName');
  await prefs.remove('acc_${uid}_username');
  await prefs.remove('acc_${uid}_profileImg');
  try {
    // [MULTI V6 - ADDITION ONLY] حذف بصمة هذا الحساب فقط
    await PasskeyService.disableForUid(uid);
  } catch (_) {}
  if (mounted) setState(() {});
}

Widget _buildAccountTileFromUid(String uid) {
  return FutureBuilder<SharedPreferences>(
    future: SharedPreferences.getInstance(),
    builder: (context, prefsSnap) {
      if (prefsSnap.hasData) {
        final prefs = prefsSnap.data!;
        final localFullName = prefs.getString('acc_${uid}_fullName');
        final localUsername = prefs.getString('acc_${uid}_username');
        final localImg = prefs.getString('acc_${uid}_profileImg');
        if (localFullName != null || localUsername != null) {
          return _accountTile(
            fullName: localFullName ?? 'مستخدم',
            username: localUsername ?? 'user',
            profileImg: localImg,
            uid: uid,
          );
        }
      }
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData ||!snapshot.data!.exists) {
            if (prefsSnap.hasData) {
              final prefs = prefsSnap.data!;
              return _accountTile(
                fullName: prefs.getString('acc_${uid}_fullName') ?? 'مستخدم',
                username: prefs.getString('acc_${uid}_username') ?? 'user',
                profileImg: prefs.getString('acc_${uid}_profileImg'),
                uid: uid,
              );
            }
            return const SizedBox.shrink();
          }
          var data = snapshot.data!.data() as Map<String, dynamic>;
          SharedPreferences.getInstance().then((prefs) {
            if (data['fullName'] != null) prefs.setString('acc_${uid}_fullName', data['fullName']);
            if (data['username'] != null) prefs.setString('acc_${uid}_username', data['username']);
            if (data['profileImg'] != null) prefs.setString('acc_${uid}_profileImg', data['profileImg']);
            if (data['email'] != null) prefs.setString('acc_${uid}_email', data['email']);
          });
          return _accountTile(
            fullName: data['fullName']?? 'مستخدم',
            username: data['username']?? 'user',
            profileImg: data['profileImg'],
            uid: uid,
          );
        },
      );
    },
  );
}

  Future<void> _handleGoogleSignIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await GoogleSignIn().signOut();
      final GoogleSignInAccount? googleUser = await GoogleSignIn(scopes: ['email']).signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);
      final auth = Provider.of<custom.AuthProvider>(context, listen: false);

      // [Tini V7 - Hidden Password for Google - ADDITION ONLY]
      try {
        String uid = userCredential.user!.uid;
        String hiddenPass = "Titi_G_${uid}_${DateTime.now().millisecondsSinceEpoch}@2026";
        String emailForLink = googleUser.email;
        final emailCred = EmailAuthProvider.credential(email: emailForLink, password: hiddenPass);
        await userCredential.user!.linkWithCredential(emailCred);
        await auth.savePasswordToVault(uid, hiddenPass);
        await prefs.setString('acc_${uid}_email', emailForLink);
        print("--- [Tini]: تم انشاء باسورد مخفي لجوجل $emailForLink ---");
      } catch (e) {
        print("--- [Tini]: باسورد مخفي جوجل موجود قبل او خطأ: $e ---");
      }

      auth.setGoogleData(
        email: googleUser.email,
        name: googleUser.displayName?? "مستخدم جديد",
      );
      
      await _checkUserAndNavigate(userCredential.user!.uid, "google");
      await _saveAccountLocally(userCredential.user!.uid, "google");

    } catch (e) {
      debugPrint("Error Google Sign In: $e");
    }
  }

  Future<void> _handlePhoneSignIn({String? customPhoneNumber}) async {
    final String phoneToUse = customPhoneNumber ?? ""; 
    if (phoneToUse.isEmpty) return;

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneToUse,
        verificationCompleted: (PhoneAuthCredential credential) async {
          UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
          
          if (mounted) await _checkUserAndNavigate(userCredential.user!.uid, "phone");
          await _saveAccountLocally(userCredential.user!.uid, "phone");
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: ${e.message}")));
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VerificationScreen(verificationId: verificationId),
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      debugPrint("Phone Error: $e");
    }
  }

  void _showSocialLoginModal(String platform, IconData icon, Color color) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: const Color(0xFF1A222C), // Surface Color
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 20),
                Icon(icon, size: 50, color: color),
                const SizedBox(height: 15),
                Text("المتابعة باستخدام $platform", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 10),
                Text("سيتمكن Tini من الوصول إلى اسمك وصورتك الشخصية.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () {
                      Navigator.pop(context);
                      if (platform == "Google") {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const BirthdayScreen(isGoogleAuth: true)));
                      }
                    },
                    child: const Text("تأكيد المتابعة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // Oil Dark Base
      resizeToAvoidBottomInset: false, 
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    children: [
                      SizedBox(height: constraints.maxHeight * 0.08),
                      FadeInDown(
                        key: ValueKey<int>(selectedTabIndex),
                        duration: const Duration(milliseconds: 400),
                        child: Text(
                          selectedTabIndex == 1 ? 'يسعدنا رؤيتك مجدداً' : 'إنشاء حساب على Tini',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        selectedTabIndex == 1 ? 'قم بإدارة حسابك، وتفاعل مع النجوم' : 'انضم إلى مجتمع Tini اليوم',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 40),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: selectedTabIndex == 1 ? _buildSavedAccountsColumn() : _buildAuthOptionsList(),
                        ),
                      ),
                      const Spacer(), 
                      const Divider(height: 1, color: Colors.white12),
                      Container(
                        color: const Color(0xFF1A222C), // Surface Color
                        child: Row(
                          children: [
                            _buildBottomTab(label: 'إنشاء حساب', index: 0, isSelected: selectedTabIndex == 0),
                            _buildBottomTab(label: 'لديك حساب بالفعل', index: 1, isSelected: selectedTabIndex == 1),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomTab({required String label, required int index, required bool isSelected}) {
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
        ),
      ),
    );
  }

  Future<void> _handlePasskeyLogin() async {
    final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);
    bool ok = await authProvider.loginWithPasskey();
    if (ok && mounted) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid!= null) await _checkUserAndNavigate(uid, "email");
    }
  }

  Widget _buildSavedAccountsColumn() {
  return FutureBuilder<List<String>>(
    key: const ValueKey('saved_accounts_column'),
    future: _getLocalSavedAccounts(),
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.data!.isEmpty) {
        return _addAccountTile();
      }
      List<String> uids = snapshot.data!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
        ...uids.map((uid) => _buildAccountTileFromUid(uid)).toList(),
          const SizedBox(height: 10),
          _addAccountTile(),
        ],
      );
    },
  );
}

  Widget _buildAuthOptionsList() {
    return Padding(
      key: const ValueKey(0),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _authOptionTile(
            icon: Remix.user_line, label: 'استخدام الهاتف / البريد الإلكتروني',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BirthdayScreen())),
            backgroundColor: Colors.teal, textColor: Colors.white, iconColor: Colors.white,
          ),
          const SizedBox(height: 16),
          _authOptionTile(icon: Remix.facebook_circle_fill, label: 'المتابعة باستخدام Facebook', onTap: () => _showSocialLoginModal("Facebook", Remix.facebook_circle_fill, AppColors.facebookBlue), iconColor: AppColors.facebookBlue),
          const SizedBox(height: 16),
          _authOptionTile(icon: Remix.google_fill, label: 'المتابعة باستخدام Google', onTap: () => _showSocialLoginModal("Google", Remix.google_fill, AppColors.googleRed), iconColor: AppColors.googleRed),
        ],
      ),
    );
  }

Widget _accountTile({required String fullName, required String username, String? profileImg, String? uid}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: const Color(0xFF1A222C), borderRadius: BorderRadius.circular(12)),
      child: FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (context, prefsSnap) {
          final bool saveLoginInfo = prefsSnap.data?.getBool('saveLoginInfo')?? true;
          return FutureBuilder<bool>(
            future: uid!= null && saveLoginInfo? Provider.of<custom.AuthProvider>(context, listen: false).isPasskeyEnabledForUid(uid) : Future.value(false),
            builder: (context, passSnap) {
              final bool hasPasskey = saveLoginInfo && (passSnap.data == true);
              return ListTile(
                leading: (profileImg!= null && profileImg.isNotEmpty)
                   ? CachedNetworkImage(
                        imageUrl: profileImg,
                        cacheKey: profileImg,
                        useOldImageOnUrlChange: false,
                        imageBuilder: (context, imageProvider) => CircleAvatar(radius: 26, backgroundColor: Colors.white10, backgroundImage: imageProvider),
                        placeholder: (context, url) => const CircleAvatar(radius: 26, backgroundColor: Colors.white10),
                        errorWidget: (context, url, error) => CircleAvatar(radius: 26, backgroundColor: Colors.white10, child: Text(fullName.isNotEmpty? fullName[0].toUpperCase() : "?", style: const TextStyle(color: Colors.white))),
                      )
                    : CircleAvatar(radius: 26, backgroundColor: Colors.white10, child: Text(fullName.isNotEmpty? fullName[0].toUpperCase() : "?", style: const TextStyle(color: Colors.white))),
                title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text('@$username', style: const TextStyle(color: Colors.white54)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () async {
                        if (uid == null) return;
                        final authProv = Provider.of<custom.AuthProvider>(context, listen: false);
                        if (hasPasskey) {
                          try {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('is_from_passkey_$uid', true);
                          } catch (_) {}
                          bool ok = await authProv.loginWithPasskeyForUid(uid);
                          if (ok && mounted) {
                            String type = await authProv.getLoginTypeFromVault(uid);
                            if (FirebaseAuth.instance.currentUser?.uid == uid) {
                              await _checkUserAndNavigate(uid, type);
                            } else {
                              if (type == "google") {
                                await _handleGoogleSignIn();
                              } else if (type == "phone") {
                                String? storedPhone = await authProv.getPhoneNumberFromVault(uid);
                                if (storedPhone!= null) {
                                  await _handlePhoneSignIn(customPhoneNumber: storedPhone);
                                } else {
                                  bool success = await authProv.silentLogin(uid);
                                  if (success && mounted) await _checkUserAndNavigate(uid, type);
                                }
                              } else {
                                await _checkUserAndNavigate(uid, type);
                              }
                            }
                          }
                        } else {
                          if (!saveLoginInfo) return;
                          bool ok = await authProv.enablePasskeyForUid(uid);
                          if (ok && mounted) setState(() {});
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: hasPasskey? Colors.teal.withValues(alpha: 0.15) : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(color: hasPasskey? Colors.teal : Colors.white24, width: 1),
                        ),
                        child: Icon(
                          hasPasskey? Icons.fingerprint : Remix.fingerprint_line,
                          size: 18,
                          color: hasPasskey? Colors.teal : Colors.white38,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.close, size: 20, color: Colors.white38),
                      onPressed: () {
                        if (uid!= null) {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A222C),
                              title: const Text("حذف الحساب؟", style: TextStyle(color: Colors.white)),
                              content: Text("هل تريد حذف $fullName من الحسابات المحفوظة؟", style: const TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء", style: TextStyle(color: Colors.white54))),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _removeSavedAccount(uid);
                                  },
                                  child: const Text("حذف", style: TextStyle(color: Color(0xFFFF3B30))),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                onTap: () async {
                  if (uid!= null) {
                    final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);
                    String loginType = await authProvider.getLoginTypeFromVault(uid);
                    if (mounted) {
                      if (loginType == "google") {
                        _handleGoogleSignIn();
                      } else if (loginType == "phone") {
                        bool isNew = await isNewDevice(uid);
                        if (!isNew) {
                          bool success = await authProvider.silentLogin(uid);
                          if (success && mounted) {
                            await _checkUserAndNavigate(uid, "phone");
                            await _saveAccountLocally(uid, "phone");
                            return;
                          }
                        }
                        String? storedPhone = await authProvider.getPhoneNumberFromVault(uid);
                        if (storedPhone!= null) {
                          _handlePhoneSignIn(customPhoneNumber: storedPhone);
                        } else {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const PhoneEmailScreen()));
                        }
                      } else {
                        bool success = await authProvider.silentLogin(uid);
                        if (success && mounted) {
                          await _checkUserAndNavigate(uid, "email");
                        }
                        await _saveAccountLocally(uid, "email");
                      }
                    }
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _addAccountTile() => Container(
    decoration: BoxDecoration(color: const Color(0xFF1A222C), borderRadius: BorderRadius.circular(12)),
    child: ListTile(
      onTap: () => setState(() => selectedTabIndex = 0), 
      leading: const CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.add, color: Colors.white)), 
      title: const Text('إضافة حساب آخر', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))
    ),
  );

  Widget _authOptionTile({required IconData icon, required String label, required VoidCallback onTap, Color backgroundColor = const Color(0xFF1A222C), Color textColor = Colors.white, Color iconColor = Colors.white}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 54, decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(4), border: backgroundColor == const Color(0xFF1A222C) ? Border.all(color: Colors.white10) : null),
        child: Row(children: [const SizedBox(width: 15), Icon(icon, color: iconColor, size: 22), Expanded(child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 15))), const SizedBox(width: 37)]),
      ),
    );
  }
}

class BirthdayScreen extends StatefulWidget {
  final bool isGoogleAuth;
  final String? existingUserId;
  const BirthdayScreen({super.key, this.isGoogleAuth = false, this.existingUserId});
  @override
  State<BirthdayScreen> createState() => _BirthdayScreenState();
}

class _BirthdayScreenState extends State<BirthdayScreen> {
  DateTime selectedDate = DateTime.now();
  bool isDateValid = false;

  void _validateBirthday(DateTime date) {
    final now = DateTime.now();
    int age = now.year - date.year;
    if (now.month < date.month || (now.month == date.month && now.day < date.day)) age--;
    setState(() { selectedDate = date; isDateValid = age >= 13; });
  }

  int _calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
    return age;
  }

  Future<void> _onContinue() async {
    if (widget.existingUserId != null &&
        FirebaseAuth.instance.currentUser?.uid != widget.existingUserId) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('registration_dob_selected_at', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString('registration_dob_uid', widget.existingUserId ?? '');
    await prefs.setString('user_dob', selectedDate.toIso8601String());
    await prefs.setInt('user_age', _calculateAge(selectedDate));
    await prefs.setBool('isUserAdult', _calculateAge(selectedDate) >= 18);
    if (widget.existingUserId != null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != widget.existingUserId || !mounted) return;
      try {
        final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(ref);
          final data = snapshot.data();
          // اختيار جديد لحساب محدد يملأ الميلاد الناقص ولا يستبدل بيانات حساب قديم.
          if ((data?['birthDate'] == null || data?['birthDate'] == '') && data?['dob'] == null) {
            transaction.set(ref, {
              'birthDate': selectedDate.toIso8601String(),
              'dob': Timestamp.fromDate(selectedDate),
              'age': _calculateAge(selectedDate),
              'isUserAdult': _calculateAge(selectedDate) >= 18,
            }, SetOptions(merge: true));
          }
        });
        if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
        final auth = Provider.of<custom.AuthProvider>(context, listen: false);
        await auth.fetchUserData();
        if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
        if (auth.profileCompleted) {
          await prefs.remove('registration_dob_selected_at');
          await prefs.remove('registration_dob_uid');
          await prefs.remove('user_dob');
          await prefs.remove('user_age');
          await prefs.remove('isUserAdult');
          if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (route) => false);
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => NameSelectionScreen(userId: user.uid)));
        }
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ تاريخ الميلاد. حاول مجدداً.')),
        );
      }
      return;
    }
    if (widget.isGoogleAuth) {
      _handleGoogleSignInFromBirthday();
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const PhoneEmailScreen()));
    }
  }
Future<void> _saveAccountLocally(String uid, String type) async {
  final prefs = await SharedPreferences.getInstance();
  // [ADDITION ONLY - saveLoginInfo Check]
  try {
    bool saveInfo = prefs.getBool('saveLoginInfo') ?? true;
    if (!saveInfo) return;
  } catch (_) {}
  List<String> savedUids = prefs.getStringList('saved_accounts')?? [];
  savedUids.remove(uid);
  savedUids.insert(0, uid);
  if (savedUids.length > 5) savedUids = savedUids.sublist(0, 5);
  await prefs.setStringList('saved_accounts', savedUids);
  await prefs.setString('account_type_$uid', type);

  // [إضافة V5.8 - حل حساب صديقك] بدون حذف: حفظ بيانات الحساب محليا للعرض بعد تسجيل الخروج
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      if (currentUser.email != null && currentUser.email!.isNotEmpty) {
        await prefs.setString('acc_${uid}_email', currentUser.email!);
      }
      if (currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
        await prefs.setString('acc_${uid}_fullName', currentUser.displayName!);
      }
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['email'] != null) await prefs.setString('acc_${uid}_email', data['email']);
          if (data['fullName'] != null) await prefs.setString('acc_${uid}_fullName', data['fullName']);
          if (data['username'] != null) await prefs.setString('acc_${uid}_username', data['username']);
          if (data['profileImg'] != null) await prefs.setString('acc_${uid}_profileImg', data['profileImg']);
        }
      } catch (_) {}
    }
  } catch (_) {}
}

  Future<void> _handleGoogleSignInFromBirthday() async {
    try {
      await GoogleSignIn().signOut(); 
      final GoogleSignInAccount? googleUser = await GoogleSignIn(scopes: ['email']).signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final auth = Provider.of<custom.AuthProvider>(context, listen: false);
      
      auth.setGoogleData(
        email: googleUser.email, 
        name: googleUser.displayName ?? "مستخدم جديد",
      );

      final uid = userCredential.user!.uid;

      // [Tini V7 - Hidden Password for Google Birthday - ADDITION ONLY]
      try {
        String hiddenPass = "Titi_G_${uid}_${DateTime.now().millisecondsSinceEpoch}@2026";
        String emailForLink = googleUser.email;
        final emailCred = EmailAuthProvider.credential(email: emailForLink, password: hiddenPass);
        await userCredential.user!.linkWithCredential(emailCred);
        await auth.savePasswordToVault(uid, hiddenPass);
        final prefs2 = await SharedPreferences.getInstance();
        await prefs2.setString('acc_${uid}_email', emailForLink);
      } catch (e) {
        print("Hidden pass birthday: $e");
      }

      final prefs = await SharedPreferences.getInstance();
      final existingUser = await FirebaseFirestore.instance.collection('users').doc(uid)
          .get(const GetOptions(source: Source.server));
      final existingBirth = existingUser.data();
      final String? savedDob = custom.AuthProvider.pendingRegistrationBirthDate(prefs, userCredential.user!);
      final int savedAge = AudiencePolicy.verifiedAge({'birthDate': savedDob}) ?? 0;
      final bool savedAdult = savedDob != null && savedAge >= 18;
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      if (savedDob != null &&
          (existingBirth?['birthDate'] == null || existingBirth?['birthDate'] == '') &&
          existingBirth?['dob'] == null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'birthDate': savedDob,
          'dob': Timestamp.fromDate(DateTime.parse(savedDob)),
          'age': savedAge,
          'isUserAdult': savedAdult,
        }, SetOptions(merge: true));
      }

      bool isNew = await isNewDevice(uid);
      bool twoFactorEnabled = false;
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        twoFactorEnabled = doc.data()?['twoFactorEnabled'] == true;
      } catch (_) {}
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
    if (isNew && twoFactorEnabled) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => TwoFactorChallengeScreen(uid: uid, firstLoginType: 'google')), (route) => false);
        }
        return;
      }
      await saveActiveSession(uid, loginMethod: 'google');
      try {
        String city = '', country = '', loc = 'تسجيل دخول جديد';
        try {
        final r = await http.get(Uri.parse('https://ipwho.is/')).timeout(Duration(seconds: 5));
if (r.statusCode == 200) {
  final j = json.decode(r.body);
  city = j['city'] ?? '';
  country = j['country'] ?? '';
  loc = city.isNotEmpty && country.isNotEmpty ? '$city, $country' : (country.isNotEmpty ? country : loc);
}
        } catch (_) {}
        await FirebaseFirestore.instance.collection('users').doc(uid).collection('login_history').add({
          'deviceName': await getRealDeviceName(),
          'city': city,
          'country': country,
          'location': loc,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      await auth.syncCurrentAccountToVault(uid, "google");
      await auth.fetchUserData();
      await _saveAccountLocally(uid, "google");

      if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
        if (auth.profileCompleted) {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (route) => false);
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => NameSelectionScreen(userId: uid)));
        }
      }
    } catch (e) {
      debugPrint("Error Google Sign In from Birthday: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("ما هو تاريخ\nميلادك؟", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                          Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle), child: const Icon(Remix.refresh_line, color: Colors.teal, size: 45)),
                        ],
                      ),
                      const SizedBox(height: 40),
                      Text("${selectedDate.day} ${_getMonthName(selectedDate.month)} ${selectedDate.year}", style: TextStyle(fontSize: 20, color: isDateValid ? Colors.white : Colors.white24, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity, height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDateValid ? Colors.teal : Colors.teal.withValues(alpha: 0.4), 
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))
                          ),
                          onPressed: isDateValid ? _onContinue : null,
                          child: const Text("متابعة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: constraints.maxHeight * 0.3, 
                        child: Theme(
                          data: ThemeData.dark(),
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.date, 
                            initialDateTime: DateTime.now(), 
                            maximumDate: DateTime.now(), 
                            onDateTimeChanged: _validateBirthday
                          ),
                        )
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }
  String _getMonthName(int month) => ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"][month - 1];
}

class PhoneEmailScreen extends StatefulWidget {
  const PhoneEmailScreen({super.key});
  @override
  State<PhoneEmailScreen> createState() => _PhoneEmailScreenState();
}

class _PhoneEmailScreenState extends State<PhoneEmailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String fullPhoneNumber = "";
  bool _isPasswordVisible = false;

  @override
  void initState() { 
    super.initState(); 
    _tabController = TabController(length: 2, vsync: this); 
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _checkUserAndNavigate(String uid, String type) async {
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    bool isNew = await isNewDevice(uid);
    bool twoFactorEnabled = false;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      twoFactorEnabled = doc.data()?['twoFactorEnabled'] == true;
    } catch (_) {}
    if (isNew && twoFactorEnabled) {
      // [Tini Fix]: ابقاء الجلسة
      if (mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => TwoFactorChallengeScreen(uid: uid, firstLoginType: type)), (route) => false);
      }
      return;
    }
    await saveActiveSession(uid, loginMethod: type);
    try {
      String city = '', country = '', loc = 'تسجيل دخول جديد';
      try {
      final r = await http.get(Uri.parse('https://ipwho.is/')).timeout(Duration(seconds: 5));
if (r.statusCode == 200) {
  final j = json.decode(r.body);
  city = j['city'] ?? '';
  country = j['country'] ?? '';
  loc = city.isNotEmpty && country.isNotEmpty ? '$city, $country' : (country.isNotEmpty ? country : loc);
}
      } catch (_) {}
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('login_history').add({
        'deviceName': await getRealDeviceName(),
        'city': city,
        'country': country,
        'location': loc,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    await auth.syncCurrentAccountToVault(uid, type);
    await auth.fetchUserData();
    if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
      if (auth.profileCompleted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (route) => false);
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => NameSelectionScreen(userId: uid)));
      }
    }
  }
Future<void> _saveAccountLocally(String uid, String type) async {
  final prefs = await SharedPreferences.getInstance();
  // [ADDITION ONLY - saveLoginInfo Check]
  try {
    bool saveInfo = prefs.getBool('saveLoginInfo') ?? true;
    if (!saveInfo) return;
  } catch (_) {}
  List<String> savedUids = prefs.getStringList('saved_accounts')?? [];
  savedUids.remove(uid);
  savedUids.insert(0, uid);
  if (savedUids.length > 5) savedUids = savedUids.sublist(0, 5);
  await prefs.setStringList('saved_accounts', savedUids);
  await prefs.setString('account_type_$uid', type);

  // [إضافة V5.8 - حل حساب صديقك] بدون حذف: حفظ بيانات الحساب محليا للعرض بعد تسجيل الخروج
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      if (currentUser.email != null && currentUser.email!.isNotEmpty) {
        await prefs.setString('acc_${uid}_email', currentUser.email!);
      }
      if (currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
        await prefs.setString('acc_${uid}_fullName', currentUser.displayName!);
      }
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['email'] != null) await prefs.setString('acc_${uid}_email', data['email']);
          if (data['fullName'] != null) await prefs.setString('acc_${uid}_fullName', data['fullName']);
          if (data['username'] != null) await prefs.setString('acc_${uid}_username', data['username']);
          if (data['profileImg'] != null) await prefs.setString('acc_${uid}_profileImg', data['profileImg']);
        }
      } catch (_) {}
    }
  } catch (_) {}
}

  Future<void> _handlePhoneSignIn() async {
    if (fullPhoneNumber.isEmpty) return;
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        verificationCompleted: (credential) async {
          UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
          if (mounted) await _checkUserAndNavigate(userCredential.user!.uid, "phone");
          await _saveAccountLocally(userCredential.user!.uid, "phone");
        },
        verificationFailed: (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? "")));
        },
        codeSent: (id, token) {
          if (mounted) Navigator.push(context, MaterialPageRoute(builder: (context) => VerificationScreen(verificationId: id)));
        },
        codeAutoRetrievalTimeout: (id) {},
      );
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _handleEmailSignUp() async {
  if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب الإيميل وكلمة السر')),
      );
    }
    return;
  }
  try {
    UserCredential userCredential;
    
    // حاول تسجيل دخول أولاً
    try {
      userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // [إضافة V5.8 - حل ضغطة حساب صديقك] بدون حذف: حفظ الباسورد للحسابات الموجودة
      try {
        final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);
        await authProvider.savePasswordToVault(userCredential.user!.uid, _passwordController.text.trim());
        await authProvider.syncCurrentAccountToVault(userCredential.user!.uid, "email");
      } catch (_) {}
    } on FirebaseAuthException catch (e) {
      // إذا الحساب مو موجود -> اعمل إنشاء
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
          final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);
          await authProvider.savePasswordToVault(userCredential.user!.uid, _passwordController.text.trim());
          await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
           'twoFactorEnabled': false,
           'twoFactorTypes': [],
          }, SetOptions(merge: true));
        } on FirebaseAuthException catch (createError) {
          if (createError.code == 'email-already-in-use') {
            // صارت حالة نادرة: الإيميل موجود بس الباسورد غلط
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('هذا الإيميل مسجل، كلمة السر غلط')),
              );
            }
            return;
          }
          rethrow;
        }
      } else if (e.code == 'wrong-password') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('كلمة السر غلط')),
          );
        }
        return;
      } else {
        rethrow;
      }
    }

    
    if (mounted) await _checkUserAndNavigate(userCredential.user!.uid, "email");
    await _saveAccountLocally(userCredential.user!.uid, "email");
    
  } on FirebaseAuthException catch (e) {
    if (mounted) {
      String msg = 'خطأ';
      if (e.code == 'weak-password') msg = 'كلمة السر ضعيفة';
      else if (e.code == 'invalid-email') msg = 'الإيميل غلط';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  } catch (e) { 
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: ${e.toString()}'))); 
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, elevation: 0, title: const Text("إنشاء حساب", style: TextStyle(color: Colors.white))),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabController, 
                      labelColor: Colors.teal, 
                      unselectedLabelColor: Colors.white54,
                      indicatorColor: Colors.teal, 
                      tabs: const [Tab(text: "الهاتف"), Tab(text: "البريد")]
                    ),
                    SizedBox(
                      height: 300, 
                      child: TabBarView(controller: _tabController, children: [
                        Padding(
                          padding: const EdgeInsets.all(30), 
                          child: Theme(
                            data: ThemeData.dark(),
                            child: IntlPhoneField(
                              initialCountryCode: 'IQ', 
                              onChanged: (p) => fullPhoneNumber = p.completeNumber,
                              style: const TextStyle(color: Colors.white),
                              dropdownTextStyle: const TextStyle(color: Colors.white),
                            ),
                          )
                        ),
                        Padding(padding: const EdgeInsets.all(30), child: Column(children: [
                          TextField(
                            controller: _emailController, 
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: "البريد", 
                              hintStyle: const TextStyle(color: Colors.white54),
                              filled: true,
                              fillColor: const Color(0xFF1C1C1E),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)
                            )
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _passwordController, 
                            obscureText: !_isPasswordVisible, 
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: "كلمة السر",
                              hintStyle: const TextStyle(color: Colors.white54),
                              filled: true,
                              fillColor: const Color(0xFF1C1C1E),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible ? Remix.eye_line : Remix.eye_off_line,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                            ),
                          ),
                        ])),
                      ]),
                    ),
                    const Spacer(),
                    Padding(padding: const EdgeInsets.all(30), child: SizedBox(width: double.infinity, height: 54, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () => _tabController.index == 0 ? _handlePhoneSignIn() : _handleEmailSignUp(), child: const Text("متابعة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
                  ],
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}

class VerificationScreen extends StatefulWidget {
  final String verificationId;
  const VerificationScreen({super.key, required this.verificationId});
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());

  @override
  void dispose() {
    for (var controller in _controllers) { controller.dispose(); }
    for (var node in _focusNodes) { node.dispose(); }
    super.dispose();
  }
Future<void> _saveAccountLocally(String uid, String type) async {
  final prefs = await SharedPreferences.getInstance();
  // [ADDITION ONLY - saveLoginInfo Check]
  try {
    bool saveInfo = prefs.getBool('saveLoginInfo') ?? true;
    if (!saveInfo) return;
  } catch (_) {}
  List<String> savedUids = prefs.getStringList('saved_accounts')?? [];
  savedUids.remove(uid);
  savedUids.insert(0, uid);
  if (savedUids.length > 5) savedUids = savedUids.sublist(0, 5);
  await prefs.setStringList('saved_accounts', savedUids);
  await prefs.setString('account_type_$uid', type);

  // [إضافة V5.8 - حل حساب صديقك] بدون حذف: حفظ بيانات الحساب محليا للعرض بعد تسجيل الخروج
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      if (currentUser.email != null && currentUser.email!.isNotEmpty) {
        await prefs.setString('acc_${uid}_email', currentUser.email!);
      }
      if (currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
        await prefs.setString('acc_${uid}_fullName', currentUser.displayName!);
      }
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['email'] != null) await prefs.setString('acc_${uid}_email', data['email']);
          if (data['fullName'] != null) await prefs.setString('acc_${uid}_fullName', data['fullName']);
          if (data['username'] != null) await prefs.setString('acc_${uid}_username', data['username']);
          if (data['profileImg'] != null) await prefs.setString('acc_${uid}_profileImg', data['profileImg']);
        }
      } catch (_) {}
    }
  } catch (_) {}
}
  
  Future<void> _verifyOtp() async {
    String otp = _controllers.map((e) => e.text).join();
    try {
      AuthCredential credential = PhoneAuthProvider.credential(verificationId: widget.verificationId, smsCode: otp);
      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final auth = Provider.of<custom.AuthProvider>(context, listen: false);

      // [Tini V7 - Hidden Password for Phone - ADDITION ONLY]
      try {
        String uid = userCredential.user!.uid;
        String hiddenEmail = "phone_${uid}@titi-star.local";
        String hiddenPass = "Titi_P_${uid}_${DateTime.now().millisecondsSinceEpoch}@2026";
        final emailCred = EmailAuthProvider.credential(email: hiddenEmail, password: hiddenPass);
        await userCredential.user!.linkWithCredential(emailCred);
        await auth.savePasswordToVault(uid, hiddenPass);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('acc_${uid}_email', hiddenEmail);
        print("--- [Tini]: تم انشاء باسورد مخفي للهاتف $hiddenEmail ---");
      } catch (e) {
        print("Hidden pass phone: $e");
      }

      bool isNew = await isNewDevice(userCredential.user!.uid);
      bool twoFactorEnabled = false;
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).get();
        twoFactorEnabled = doc.data()?['twoFactorEnabled'] == true;
      } catch (_) {}
      if (isNew && twoFactorEnabled) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => TwoFactorChallengeScreen(uid: userCredential.user!.uid, firstLoginType: 'phone')), (route) => false);
        }
        return;
      }
      await saveActiveSession(userCredential.user!.uid, loginMethod: 'phone');
      try {
        String city = '', country = '', loc = 'تسجيل دخول جديد';
        try {
        final r = await http.get(Uri.parse('https://ipwho.is/')).timeout(Duration(seconds: 5));
if (r.statusCode == 200) {
  final j = json.decode(r.body);
  city = j['city'] ?? '';
  country = j['country'] ?? '';
  loc = city.isNotEmpty && country.isNotEmpty ? '$city, $country' : (country.isNotEmpty ? country : loc);
}
        } catch (_) {}
        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).collection('login_history').add({
          'deviceName': await getRealDeviceName(),
          'city': city,
          'country': country,
          'location': loc,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      await auth.syncCurrentAccountToVault(userCredential.user!.uid, "phone");
await auth.fetchUserData();
await _saveAccountLocally(userCredential.user!.uid, "phone");
if (mounted) {
  if (auth.profileCompleted) {
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (route) => false);
  } else {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => NameSelectionScreen(userId: userCredential.user!.uid)));
  }
}
    } catch (e) { 
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("كود خاطئ"))); 
    }
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(children: [
            const SizedBox(height: 60),
            const Text("أدخل رمز التحقق", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 40),
            Row(
              children: List.generate(6, (i) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(left: i == 0? 0 : 8),
                  child: TextField(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 20, height: 1),
                    onChanged: (value) {
                      if (value.isNotEmpty && i < 5) {
                        FocusScope.of(context).requestFocus(_focusNodes[i + 1]);
                      } else if (value.isEmpty && i > 0) {
                        FocusScope.of(context).requestFocus(_focusNodes[i - 1]);
                      }
                    },
                    decoration: InputDecoration(
                      counterText: "",
                      filled: true,
                      fillColor: const Color(0xFF1C1C1E),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.white12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.teal, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              )),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: _verifyOtp,
                child: const Text("تأكيد", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              ),
            )
          ]),
        ),
      ),
    ),
  );
}
}

class NameSelectionScreen extends StatefulWidget {
  final String userId;
  const NameSelectionScreen({super.key, required this.userId});
  @override
  State<NameSelectionScreen> createState() => _NameSelectionScreenState();
}

class _NameSelectionScreenState extends State<NameSelectionScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
  
Future<void> _saveName() async {
  if (_nameController.text.isEmpty) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.uid != widget.userId) return;
  final prefs = await SharedPreferences.getInstance();
  final dobString = custom.AuthProvider.pendingRegistrationBirthDate(prefs, user);
  final int age = AudiencePolicy.verifiedAge({'birthDate': dobString}) ?? 0;
  final bool isAdult = dobString != null && age >= 18;

  final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId)
      .get(const GetOptions(source: Source.server));
  if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
  final existingData = userDoc.data();
  final initializeBirth = dobString != null &&
      (existingData?['birthDate'] == null || existingData?['birthDate'] == '') &&
      existingData?['dob'] == null;

  // [FIX]: دائما خذ الاسم الجديد اللي كتبو المستخدم
  String finalFullName = _nameController.text.trim();
  String finalUsername;
  dynamic finalCreatedAt;

  if (userDoc.exists && existingData!= null && existingData['username']!= null) {
    finalUsername = existingData['username'];
    finalCreatedAt = existingData['createdAt']?? FieldValue.serverTimestamp();
  } else {
    finalUsername = _nameController.text.replaceAll(' ', '_').toLowerCase() + Random().nextInt(100).toString();
    finalCreatedAt = FieldValue.serverTimestamp();
  }

  await FirebaseFirestore.instance.collection('users').doc(widget.userId).set({
    'fullName': finalFullName,
    'username': finalUsername,
    'username_lowercase': finalUsername.toLowerCase(),
    'fullName_lowercase': finalFullName.toLowerCase(),
    'profileCompleted': true,
    'uid': widget.userId,
    'createdAt': finalCreatedAt,
    if (initializeBirth) ...{
      'dob': Timestamp.fromDate(DateTime.parse(dobString)),
      'birthDate': dobString,
      'age': age,
      'isUserAdult': isAdult,
    },
    if (!userDoc.exists) ...{
      'isAdultContent': false,
      'audience_18plus': false,
    },
    'twoFactorEnabled': false,
    'twoFactorTypes': [],
  }, SetOptions(merge: true));

  // [FIX]: حدث الاسم محليا مشان يظهر فورا بقائمة الحسابات المحفوظة
  if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
  try {
    await prefs.setString('acc_${widget.userId}_fullName', finalFullName);
    await prefs.setString('acc_${widget.userId}_username', finalUsername);
    await prefs.setString('last_fullName', finalFullName);
    await prefs.setString('last_username', finalUsername);
    await FirebaseAuth.instance.currentUser?.updateDisplayName(finalFullName);
  } catch (_) {}

  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token!= null) {
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
    }
  } catch (_) {}

  if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
  await saveActiveSession(widget.userId, loginMethod: 'email');
  if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
  await prefs.remove('registration_dob_selected_at');
  await prefs.remove('registration_dob_uid');
  await prefs.remove('user_dob');
  await prefs.remove('user_age');
  await prefs.remove('isUserAdult');

  if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (r) => false);
}

  Future<void> _skipName() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != widget.userId) return;
    String defaultName = user.displayName?? "مستخدم Titi";
    final prefs = await SharedPreferences.getInstance();
    final dobString = custom.AuthProvider.pendingRegistrationBirthDate(prefs, user);
    final int age = AudiencePolicy.verifiedAge({'birthDate': dobString}) ?? 0;
    final bool isAdult = dobString != null && age >= 18;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId)
        .get(const GetOptions(source: Source.server));
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
    final existingData = userDoc.data();
    final initializeBirth = dobString != null &&
        (existingData?['birthDate'] == null || existingData?['birthDate'] == '') &&
        existingData?['dob'] == null;

    await FirebaseFirestore.instance.collection('users').doc(widget.userId).set({
      'fullName': defaultName,
      'username': "user_${Random().nextInt(999999)}",
      'profileCompleted': true,
      'uid': widget.userId,
      'createdAt': FieldValue.serverTimestamp(),
      if (initializeBirth) ...{
        'dob': Timestamp.fromDate(DateTime.parse(dobString)),
        'birthDate': dobString,
        'age': age,
        'isUserAdult': isAdult,
      },
      if (!userDoc.exists) ...{
        'isAdultContent': false,
        'audience_18plus': false,
      },
      'twoFactorEnabled': false,
      'twoFactorTypes': [],
    }, SetOptions(merge: true));
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
    await saveActiveSession(widget.userId, loginMethod: 'email');
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
    await prefs.remove('registration_dob_selected_at');
    await prefs.remove('registration_dob_uid');
    await prefs.remove('user_dob');
    await prefs.remove('user_age');
    await prefs.remove('isUserAdult');

    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(elevation: 0, backgroundColor: AppColors.background, actions: [
        TextButton(onPressed: _skipName, child: const Text("تخطي", style: TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.bold)))
      ]),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: [
                      const SizedBox(height: 50),
                      const Text("ما هو الاسم الذي تفضله؟", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 15),
                      const Text("اختر اسماً يعبر عنك ليراك به الجميع", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 40),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "الاسم الكامل",
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xFF1C1C1E),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                          onPressed: _saveName,
                          child: const Text("حفظ ومتابعة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}