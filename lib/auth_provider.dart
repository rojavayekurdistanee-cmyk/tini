import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io'; 
import 'package:image_picker/image_picker.dart'; 
import 'r2_service.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'user_model.dart';
import 'audience_policy.dart';
import 'activity_status_service.dart'; // [حالة النشاط]
import 'package:firebase_messaging/firebase_messaging.dart';
import 'passkey_service.dart';
import 'device_service.dart';
/*
  [Tini Project Rules]:
    1. No line deletion.
    2. Addition only.
    3. Consistent naming with Firestore keys.
    4. Rules Followed: Return full code, professional status management.
    5. Fix: Removed all Deprecated code and stabilized the Vault with V5 Final.
    6. Final Safety: Silent Login now handles missing Firestore fields (Email/Phone).
    7. GLOBAL REPAIR [2026-04-16]: Forced Auto-Creation for new users and Auto-Sync for missing fields.
    8. UPDATE [2026-04-17]: Fixed Google Email Sync to show in Account Details immediately.
*/

class AuthProvider extends ChangeNotifier {
  StreamSubscription<User?>? _authStateSub;
  StreamSubscription<DocumentSnapshot>? _liveUserSub;
  StreamSubscription<QuerySnapshot>? _liveBlockedBySub; // [Two-Way Live]
  StreamSubscription<QuerySnapshot>? _liveBlockedSub;

  // [التعديل النهائي]: نظام الخزنة V5 - بدون أي خطوط مشطوبة وبأعلى استقرار للأندرويد
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
      resetOnError: true, 
      storageNamespace: 'TitiStar_V5_FinalSafe', 
      preferencesKeyPrefix: 'titi_star_v5',   
    ),
  );
  // [إضافة للتعريف لضمان عمل جوجل في المشروع الجديد]
  final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: ['email', 'profile'],
  serverClientId: '965066441230-tha018u6nondvcsmsrtdu4thoob7m854.apps.googleusercontent.com', // تبع Web بس
);

  AuthProvider() {
    loadSavedAccount();
    
    _authStateSub?.cancel();
    _authStateSub = FirebaseAuth.instance.authStateChanges().listen((User? user) {
  if (_authUid != user?.uid) {
    _authUid = user?.uid;
    _authSession++;
    _clearInternalData();
    notifyListeners();
  }
  final session = _authSession;
  if (user != null) {
    fetchUserData().then((_) async {
      if (!_isCurrentSession(user.uid, session)) return;
      startLiveCounterSync();
      // [حالة النشاط] نقرا الزر قبل ما نشغل
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (!_isCurrentSession(user.uid, session)) return;
        final bool show = doc.data()?['showActivityStatus'] ?? true;
        if (show) {
          await ActivityStatusService().init();
        } else {
          ActivityStatusService().disposeService();
        }
      } catch (_) {
        await ActivityStatusService().init();
      }
      if (!_isCurrentSession(user.uid, session)) return;
      _isAuthChecked = true; 
      notifyListeners();
    });
  } else {
    _clearInternalData();
    stopLiveCounterSync();
    ActivityStatusService().disposeService();
    _isAuthChecked = true; 
    notifyListeners();
  }
});
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  

  bool _isAuthChecked = false; 
  bool get isAuthChecked => _isAuthChecked;

  UserModel? _currentUser; // ← أضف هذا
  UserModel? get currentUser => _currentUser; // ← وأضف هذا 

  bool _profileCompleted = true;
  bool get profileCompleted => _profileCompleted;

  bool _isAgeRestricted = false; 
  bool get isAgeRestricted => _isAgeRestricted;

  // [ADDITION PRIVATE ACCOUNT]
  bool _isPrivate = false;
  bool get isPrivate => _isPrivate;

  String _defaultPrivacy = 'everyone';
  String get defaultPrivacy => _defaultPrivacy;

  String _commentPrivacy = 'comment_everyone';
  String get commentPrivacy => _commentPrivacy;

  // [Tini - Mention Privacy]: إعداد واحد للذِكر والإشارات.
  String _mentionPrivacy = 'everyone';
  String get mentionPrivacy => _mentionPrivacy;

  // [Tini - Liked Videos Privacy]: افتراضياً لا يرى قائمة الإعجابات إلا صاحب الحساب.
  String _likedVideosPrivacy = 'only_me';
  String get likedVideosPrivacy => _likedVideosPrivacy;

  // [Tini - Favorite Videos Privacy]: خاص افتراضياً، مثل إعداد الإعجابات.
  String _favoriteVideosPrivacy = 'only_me';
  String get favoriteVideosPrivacy => _favoriteVideosPrivacy;

  String _whoCanSeeFollowingList = 'follow_list_public';
  String get whoCanSeeFollowingList => _whoCanSeeFollowingList;

  bool _showActivityStatus = true;
  bool get showActivityStatus => _showActivityStatus;

  // ✅ NEW - إعدادات رسائل انستغرام
  String _messageRequestPrivacy = 'followers';
  String get messageRequestPrivacy => _messageRequestPrivacy;

  String _groupAddPrivacy = 'following';
  String get groupAddPrivacy => _groupAddPrivacy;

  String _storyReplyPrivacy = 'all_followers';
  String get storyReplyPrivacy => _storyReplyPrivacy;

  bool _showReadReceipts = true;
  bool get showReadReceipts => _showReadReceipts;

  bool _twoFactorEnabled = false;
  bool get twoFactorEnabled => _twoFactorEnabled;
  List<String> _twoFactorTypes = [];
  List<String> get twoFactorTypes => _twoFactorTypes;

  // [AUDIENCE CONTROL - ADDITION]
  bool _isAdultContent = false;
  bool get isAdultContent => _isAdultContent;

  bool _audience18Plus = false;
  bool get audience18Plus => _audience18Plus;

  bool _isUserAdult = false;
  bool get isUserAdult => _hasVerifiedAge && _isUserAdult;

  String? _ageVerifiedUid;
  String? _authUid;
  int _authSession = 0;
  int _ageVerifiedSession = -1;
  int _userFetchVersion = 0;

  bool get _hasVerifiedAge => uid.isNotEmpty &&
      _ageVerifiedUid == uid && _ageVerifiedSession == _authSession;

  bool _isCurrentSession(String userUid, int session) =>
      FirebaseAuth.instance.currentUser?.uid == userUid && session == _authSession;

  void _resetVerifiedAge() {
    _ageVerifiedUid = null;
    _ageVerifiedSession = -1;
    _isUserAdult = false;
    _age = 0;
  }

  void _applyVerifiedAge(Map<String, dynamic> data, String userUid, int session) {
    if (!_isCurrentSession(userUid, session)) return;
    final verifiedAge = AudiencePolicy.verifiedAge(data);
    _age = verifiedAge ?? 0;
    _isUserAdult = verifiedAge != null && verifiedAge >= 18;
    _ageVerifiedUid = userUid;
    _ageVerifiedSession = session;
    final primary = data['birthDate'];
    final raw = primary == null || (primary is String && primary.trim().isEmpty) ? data['dob'] : primary;
    _birthDate = raw is Timestamp ? raw.toDate().toIso8601String()
        : raw is DateTime ? raw.toIso8601String() : raw is String ? raw : '';
  }

  // تاريخ التسجيل المؤقت لا ينتقل إلى حساب قديم أو إلى جلسة تسجيل أخرى.
  static String? pendingRegistrationBirthDate(SharedPreferences prefs, User user) {
    final selectedAt = prefs.getInt('registration_dob_selected_at');
    final createdAt = user.metadata.creationTime?.millisecondsSinceEpoch;
    final now = DateTime.now().millisecondsSinceEpoch;
    final selectedUid = prefs.getString('registration_dob_uid') ?? '';
    if (selectedAt == null || selectedAt > now ||
        now - selectedAt > const Duration(minutes: 30).inMilliseconds ||
        (selectedUid.isNotEmpty && selectedUid != user.uid) ||
        (selectedUid.isEmpty && (createdAt == null ||
            createdAt < selectedAt - const Duration(minutes: 1).inMilliseconds))) return null;
    final raw = prefs.getString('user_dob');
    return AudiencePolicy.verifiedAge({'birthDate': raw}) == null ? null : raw;
  }

  int _age = 0;
  int get age => _hasVerifiedAge ? _age : 0;
  // [PASSKEY V5 - ADDITION ONLY]
  bool _passkeyEnabled = false;
  bool get passkeyEnabled => _passkeyEnabled;
    // [PASSKEY MULTI V6 - ADDITION ONLY - كل حساب الو بصمتو لحالو]
  Map<String, bool> _passkeyEnabledMap = {};
  bool isPasskeyEnabledForUidSync(String uidCheck) => _passkeyEnabledMap[uidCheck]?? false;
  bool get isAnyPasskeyEnabled => _passkeyEnabledMap.values.any((e) => e);

  String? _fullName;
  String? _username;
  String? _profileImg;
  String? _bio;
  String? _birthDate;
  String? _email;
  String? _phoneNumber;
  String? _authType; 
  String? _createdAt; // إضافة وقت الإنشاء للخزنة

  int _followers = 0;
  int _following = 0;
  int _likes = 0;
  // [Tini]: متغيرات الشارة
  String? _badge;
  Timestamp? _badgeEndsAt;

  String? get badge => _badge;
  Timestamp? get badgeEndsAt => _badgeEndsAt;

  bool get hasActiveBadge {
    if (_badge == null || _badgeEndsAt == null) return false;
    return DateTime.now().isBefore(_badgeEndsAt!.toDate());
  }
  // [Tini V6]: كاش المتابعة من subcollection فقط
  Set<String> _followingList = {};
  List<String> get followingList => _followingList.toList();
    // [Tini FIX - Comment Privacy]: كاش المتابعين للفحص المتبادل
  Set<String> _followersList = {};
  List<String> get followersList => _followersList.toList();

  // [Tini: نظام الحظر - مركزي Set - Two Way]
  Set<String> _blockedUsers = {};
  Set<String> _blockedByUsers = {}; // [Two-Way] ناس حاظريني - مشان فيديوهاتي ما تطلع عندهم
  Set<String> get blockedUsersSet => _blockedUsers; // المركزي الجديد - استخدم هاد بكل مكان
  Set<String> get blockedBySet => _blockedByUsers; // [Two-Way] للفيد - هاد اللي كان ناقص وعم يطلع خطأ بالصورة
  Set<String> get blockedList => _blockedUsers; // توافق قديم - بيضل Set
  List<String> get blockedUsers => _blockedUsers.toList(); // توافق قديم - للكتابة بـ Firestore بس
  bool isBlocked(String uid) => _blockedUsers.contains(uid);
  bool isUserBlocked(String uid) => _blockedUsers.contains(uid);

  // تحديث فوري بدون fetch
  void addToBlockedLocally(String uid) {
    if (!_blockedUsers.contains(uid)) {
      _blockedUsers.add(uid);
      notifyListeners();
    }
  }
  void removeFromBlockedLocally(String uid) {
    if (_blockedUsers.contains(uid)) {
      _blockedUsers.remove(uid);
      notifyListeners();
    }
    // [Two-Way] كمان شيل من blockedBy لو موجود
    if (_blockedByUsers.contains(uid)) {
      _blockedByUsers.remove(uid);
      notifyListeners();
    }
  }

  String get fullName => _fullName ?? "مستخدم جديد";
  // إضافة بوابة لجلب الـ UID من أي مكان في التطبيق
  String get uid => FirebaseAuth.instance.currentUser?.uid ?? "";
  String get username => _username ?? "user";
  String get profileImg => _profileImg ?? "";
  String get bio => _bio ?? "";
  String get birthDate => _birthDate ?? ""; 

  // [Titi Fix]: الـ Getters المحدثة لضمان استقرار شاشة النشر
  String get email => _email ?? FirebaseAuth.instance.currentUser?.email ?? "";
  String get phoneNumber => _phoneNumber ?? FirebaseAuth.instance.currentUser?.phoneNumber ?? "";
  String get authType => _authType ?? "email";
  String get authMethod => _authType ?? "email";

  int get followers => _followers;
  int get following => _following;
  int get likes => _likes;

  final ImagePicker _picker = ImagePicker();

  Future<void> loadSavedAccount() async {
    final session = _authSession;
    final prefs = await SharedPreferences.getInstance();
    final activeUid = FirebaseAuth.instance.currentUser?.uid;
    if (activeUid != null && prefs.getString('last_uid') == activeUid &&
        _isCurrentSession(activeUid, session) && !_hasVerifiedAge) {
      _fullName = prefs.getString('last_fullName');
      _username = prefs.getString('last_username');
      _profileImg = prefs.getString('last_profileImg');
      _bio = prefs.getString('last_bio');
      _email = prefs.getString('last_email');
      _phoneNumber = prefs.getString('last_phoneNumber');
      _authType = prefs.getString('last_authType');
      _createdAt = prefs.getString('last_createdAt');
      _profileCompleted = prefs.getBool('last_profileCompleted') ?? true;
      _isPrivate = prefs.getBool('last_isPrivate') ?? false;
      _defaultPrivacy = prefs.getString('last_defaultPrivacy') ?? 'everyone';
      _commentPrivacy = prefs.getString('last_commentPrivacy') ?? 'comment_everyone';
      _mentionPrivacy = prefs.getString('last_mentionPrivacy') ?? 'everyone';
      _likedVideosPrivacy = prefs.getString('last_likedVideosPrivacy') ?? 'only_me';
      _favoriteVideosPrivacy = prefs.getString('last_favoriteVideosPrivacy') ?? 'only_me';
      _whoCanSeeFollowingList = prefs.getString('last_whoCanSeeFollowingList') ?? 'follow_list_public';
      _messageRequestPrivacy = prefs.getString('last_messageRequestPrivacy') ?? 'followers';
      _groupAddPrivacy = prefs.getString('last_groupAddPrivacy') ?? 'following';
      _storyReplyPrivacy = prefs.getString('last_storyReplyPrivacy') ?? 'all_followers';
      _showReadReceipts = prefs.getBool('last_showReadReceipts') ?? true;
      _isAdultContent = prefs.getBool('last_isAdultContent') ?? false;
      _audience18Plus = prefs.getBool('last_audience18Plus') ?? false;
      // الكاش للعرض فقط؛ صلاحية مشاهدة +18 تنتظر قراءة الخادم للحساب الحالي.
      _birthDate = prefs.getString('last_birthDate');
      _resetVerifiedAge();
      _twoFactorEnabled = prefs.getBool('last_twoFactorEnabled') ?? false;
      _twoFactorTypes = prefs.getStringList('last_twoFactorTypes') ?? [];
      
      notifyListeners();
    }
  }

  Future<void> _saveAccountLocally() async {
    final currentUid = uid;
    final session = _authSession;
    if (currentUid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentSession(currentUid, session)) return;
    await prefs.setString('last_fullName', _fullName ?? "");
    await prefs.setString('last_username', _username ?? "");
    await prefs.setString('last_profileImg', _profileImg ?? "");
    await prefs.setString('last_bio', _bio ?? "");
    await prefs.setString('last_email', _email ?? "");
    await prefs.setString('last_phoneNumber', _phoneNumber ?? "");
    await prefs.setString('last_authType', _authType ?? "email");
    await prefs.setString('last_createdAt', _createdAt ?? "");
    await prefs.setBool('last_profileCompleted', _profileCompleted);
    await prefs.setString('last_badge', _badge ?? "");
    await prefs.setBool('last_isPrivate', _isPrivate);
    await prefs.setString('last_defaultPrivacy', _defaultPrivacy);
    await prefs.setString('last_commentPrivacy', _commentPrivacy);
    await prefs.setString('last_mentionPrivacy', _mentionPrivacy);
    await prefs.setString('last_likedVideosPrivacy', _likedVideosPrivacy);
    await prefs.setString('last_favoriteVideosPrivacy', _favoriteVideosPrivacy);
    await prefs.setString('last_whoCanSeeFollowingList', _whoCanSeeFollowingList);
    await prefs.setString('last_messageRequestPrivacy', _messageRequestPrivacy);
    await prefs.setString('last_groupAddPrivacy', _groupAddPrivacy);
    await prefs.setString('last_storyReplyPrivacy', _storyReplyPrivacy);
    await prefs.setBool('last_showReadReceipts', _showReadReceipts);
    await prefs.setBool('last_isAdultContent', _isAdultContent);
    await prefs.setBool('last_audience18Plus', _audience18Plus);
    await prefs.setString('last_birthDate', _birthDate ?? '');
    await prefs.setBool('last_isUserAdult', isUserAdult);
    await prefs.setInt('last_age', _age);
    await prefs.setBool('last_twoFactorEnabled', _twoFactorEnabled);
    await prefs.setStringList('last_twoFactorTypes', _twoFactorTypes);
    if (!_isCurrentSession(currentUid, session)) return;
    await prefs.setString('last_uid', currentUid);
  }

    Future<void> saveFcmTokenToFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null || token.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {

    }
  }

  Future<void> _savePasswordSecurely(String uid, String password) async {
    await _secureStorage.write(key: 'auth_pass_$uid', value: password.trim());

  }

// [تعديل ذهبي]: دالة الدخول الصامت V5.7 - الإصلاح النهائي لمشكلة (جوجل وهاتف) عند التبديل
Future<bool> silentLogin(String uid) async {
    try {
      // [ADDITION ONLY - saveLoginInfo Check]
      try {
        final prefs = await SharedPreferences.getInstance();
        bool saveInfo = prefs.getBool('saveLoginInfo') ?? true;
        if (!saveInfo) return false;
      } catch (_) {}

      String? loginType = await _secureStorage.read(key: 'auth_type_$uid');
      String? savedPassword = await _secureStorage.read(key: 'auth_pass_$uid');
      final currentUser = FirebaseAuth.instance.currentUser;

      bool isFromPasskey = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        isFromPasskey = prefs.getBool('is_from_passkey_$uid') ?? false;
        if (isFromPasskey) await prefs.remove('is_from_passkey_$uid');
      } catch (_) {}

      // 1. إذا كان المستخدم هو نفسه المسجل حالياً في Firebase
      if (currentUser!= null && currentUser.uid == uid) {
        await fetchUserData();
        if (_fullName!= null && _fullName!= "مستخدم جديد") {

            return true;
        }
      }

      // 2. [FIX V7 - Hidden Password] معالجة الباسورد المخفي لجوجل وهاتف وبريد
      if (savedPassword!= null) {
        String? userEmail;
        try {
          final prefs = await SharedPreferences.getInstance();
          String? accEmail = prefs.getString('acc_${uid}_email');
          if (accEmail!= null && accEmail.isNotEmpty) {
            userEmail = accEmail;
          }
        } catch (_) {}

        if (userEmail == null) {
          try {
            DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
            if (userDoc.exists) {
              final data = userDoc.data() as Map<String, dynamic>;
              userEmail = data['email'];
            }
          } catch (_) {}
        }

        if (userEmail == null && currentUser?.email!= null && currentUser!.uid == uid) {
          userEmail = currentUser.email;
        }

        if (userEmail!= null) {
          try {
            await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: userEmail.trim(),
              password: savedPassword.trim(),
            );
            await fetchUserData();

            return true;
          } catch (_) {

          }
        }
      }

      // 3. معالجة حسابات جوجل والهاتف بدون باسورد مخفي
      if (loginType == 'google' || loginType == 'phone') {
        if (currentUser?.uid == uid) {
           await fetchUserData();
           if (_fullName!= null && _fullName!= "مستخدم جديد") {
               return true;
           }
        } else {
           if (isFromPasskey) {
             // [FIX REAL] بصمة لحساب جوجل/هاتف بدون باسورد مخفي بعد - حمل محلي مشان الحارس
             try {
               final prefs = await SharedPreferences.getInstance();
               String? localName = prefs.getString('acc_${uid}_fullName');
               String? localUser = prefs.getString('acc_${uid}_username');
               String? localImg = prefs.getString('acc_${uid}_profileImg');
               String? localEmail = prefs.getString('acc_${uid}_email');
               if (localName!= null) _fullName = localName;
               if (localUser!= null) _username = localUser;
               if (localImg!= null) _profileImg = localImg;
               if (localEmail!= null) _email = localEmail;
               _profileCompleted = true;
               _authType = loginType;
               await _saveAccountLocally();
               return true;
             } catch (_) {
               return true;
             }
           }

           return false;
        }
      }

      // 4. محاولة أخيرة جبرية
      try {
        DocumentSnapshot finalCheck = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (finalCheck.exists) {
            _profileCompleted = true;
            notifyListeners();
            if (FirebaseAuth.instance.currentUser?.uid == uid) {
              await fetchUserData();
              return true;
            }
            if (isFromPasskey) {
              return true;
            }
        }
      } catch (_) {}


      return false;
    } catch (e) {

      return false;
    }
  }

  Future<void> switchAccount(String email, String password) async {
    _setLoading(true);
    try {
      await FirebaseAuth.instance.signOut();
      _clearInternalData();

      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      if (userCredential.user != null) {
        final String currentUid = userCredential.user!.uid;
        await _savePasswordSecurely(currentUid, password);
        await syncCurrentAccountToVault(currentUid, "email");
        
        // [إضافة]: التأكد من وجود الإيميل في الحساب الجديد عند التبديل
        await FirebaseFirestore.instance.collection('users').doc(currentUid).set({
          'email': email.trim(),
          'authMethod': 'email',
          'profileCompleted': true, // بما أنه تبديل حساب بريد، فهو قديم ومكتمل
        }, SetOptions(merge: true));

        await fetchUserData();
      }
    } catch (e) {

      rethrow;
    } finally {
      _setLoading(false);
    }
  }
  void _clearInternalData() {
    _liveUserSub?.cancel();
    _liveUserSub = null;
    _liveBlockedBySub?.cancel();
    _liveBlockedBySub = null;
    _liveBlockedSub?.cancel();
    _liveBlockedSub = null;
    stopLiveCounterSync();
    _userFetchVersion++;
    _resetVerifiedAge();
    _birthDate = null;
    _currentUser = null; // ← أضف هذا
    _fullName = null;
    _username = null;
    _profileImg = null;
    _bio = null;
    _email = null;
    _phoneNumber = null;
    _authType = null;
    _createdAt = null;
    _followers = 0;
    _following = 0;
    _likes = 0;
  _followingList = {};
  _followersList = {};
  _blockedUsers = {};
  _blockedByUsers = {}; // [Two-Way]
    _isPrivate = false;
    _defaultPrivacy = 'everyone';
    _commentPrivacy = 'comment_everyone';
    _mentionPrivacy = 'everyone';
    _likedVideosPrivacy = 'only_me';
    _favoriteVideosPrivacy = 'only_me';
    _whoCanSeeFollowingList = 'follow_list_public';
    _messageRequestPrivacy = 'followers';
    _groupAddPrivacy = 'following';
    _storyReplyPrivacy = 'all_followers';
    _showReadReceipts = true;
    _isAdultContent = false;
    _audience18Plus = false;
    _isUserAdult = false;
    _age = 0;
  }

  // [تعديل ذهبي]: جلب البيانات V5.8 - الإصلاح النهائي لظهور شاشة الميلاد والقيود اللحظية
Future<void> fetchUserData() async {
  try { await FirebaseAuth.instance.currentUser?.reload(); } catch (_) {}
  final User? user = FirebaseAuth.instance.currentUser;
  final session = _authSession;
  final request = ++_userFetchVersion;
  _liveUserSub?.cancel();
  _liveUserSub = null;
  _resetVerifiedAge();
  notifyListeners();
  if (user == null) {
    _clearInternalData();
    _isAuthChecked = true;
    notifyListeners();
    return;
  }

  bool isCurrentFetch() => _isCurrentSession(user.uid, session) && request == _userFetchVersion;

  try {
    DocumentSnapshot doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server)); 
    if (!isCurrentFetch()) return;

    if (doc.exists) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      _currentUser = UserModel.fromJson(data); // ← أضف هذا السطر
      
      _fullName = (data['fullName'] == null || data['fullName'] == "" || data['fullName'] == "مستخدم جديد")
          ? (user.displayName ?? (_fullName ?? "مستخدم جديد")) 
          : data['fullName'];
          
      _username = (data['username'] == null || data['username'] == "" || data['username'] == "user")
          ? "user_${user.uid.substring(0, 5)}"
          : data['username'];

      _profileImg = data['profileImg'] ?? ""; 
      _bio = data['bio'] ?? "";
      // [إصلاح التوحيد] قراءة birthDate من الحقلين dob و birthDate
      if (!doc.metadata.isFromCache && !doc.metadata.hasPendingWrites) {
        _applyVerifiedAge(data, user.uid, session); // جلب التاريخ الموجود بعد التحقق من تعارضاته
      } else {
        _resetVerifiedAge();
      }
      _isAgeRestricted = data['isAgeRestricted'] ?? false;
      _followers = data['followers'] ?? 0;
      _following = data['following'] ?? 0;
      _likes = data['likes'] ?? 0;
      _badge = data['badge'];
      _badgeEndsAt = data['badgeEndsAt'];
// تعبئة قائمة المتابعة من subcollection
      try {
        final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('following').get();
        if (!isCurrentFetch()) return;
        _followingList = snap.docs.map((d) => d.id).toSet();
      } catch (_) {
        if (!isCurrentFetch()) return;
        _followingList = {};
      }
      // [FIX] تعبئة قائمة المتابعين
      try {
        final snapFollowers = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('followers').get();
        if (!isCurrentFetch()) return;
        _followersList = snapFollowers.docs.map((d) => d.id).toSet();
      } catch (_) {
        if (!isCurrentFetch()) return;
        _followersList = {};
      }
      // [Tini: نظام الحظر - مركزي - تحميل - Two Way]
      try {
        final List blockedFromField = data['blockedUsers']?? data['blocked']?? [];
        _blockedUsers = blockedFromField.map((e) => e.toString()).toSet();
        final blockedSnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('blocked').get();
        if (!isCurrentFetch()) return;
        for (var d in blockedSnap.docs) {
          _blockedUsers.add(d.id);
        }
        // [Two-Way] حمل مين حاظرني
        try {
          final blockedBySnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('blockedBy').get();
          if (!isCurrentFetch()) return;
          _blockedByUsers = blockedBySnap.docs.map((e) => e.id).toSet();
        } catch (_) {
          if (!isCurrentFetch()) return;
          _blockedByUsers = {};
        }
        // [Two-Way Live] اشتراك لحظي - اذا حدا حظرك هلا فورا تختفي فيديوهاتو
        _liveBlockedBySub?.cancel();
        _liveBlockedBySub = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('blockedBy').snapshots().listen((snap) {
          if (!isCurrentFetch()) return;
          _blockedByUsers = snap.docs.map((e) => e.id).toSet();
          notifyListeners();
        });
        // [Two-Way Live] اشتراك لحظي للـ blocked - مشان فك الحظر يرجع الفيد فورا
        _liveBlockedSub?.cancel();
        _liveBlockedSub = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('blocked').snapshots().listen((snap) {
          if (!isCurrentFetch()) return;
          _blockedUsers = snap.docs.map((e) => e.id).toSet();
          notifyListeners();
        });
      } catch (_) {}
      if (!isCurrentFetch()) return;
      _isPrivate = data['isPrivate'] ?? false;
      _defaultPrivacy = data['defaultPrivacy'] ?? 'everyone';
      _commentPrivacy = data['commentPrivacy'] ?? 'comment_everyone';
      _mentionPrivacy = data['mentionPrivacy'] ?? 'everyone';
      _likedVideosPrivacy = data['likedVideosPrivacy'] ?? 'only_me';
      _favoriteVideosPrivacy = data['favoriteVideosPrivacy'] ?? 'only_me';
      _whoCanSeeFollowingList = data['whoCanSeeFollowingList'] ?? 'follow_list_public';
      _showActivityStatus = data['showActivityStatus'] ?? true;
      _messageRequestPrivacy = data['messageRequestPrivacy'] ?? 'followers';
      _groupAddPrivacy = data['groupAddPrivacy'] ?? 'following';
      _storyReplyPrivacy = data['storyReplyPrivacy'] ?? 'all_followers';
      _showReadReceipts = data['showReadReceipts'] ?? true;
      _twoFactorEnabled = data['twoFactorEnabled'] ?? false;
      _twoFactorTypes = List<String>.from(data['twoFactorTypes'] ?? []);
      _isAdultContent = AudiencePolicy.isAccountRestricted(data);
      _audience18Plus = _isAdultContent;
      // [إصلاح العمر] اذا age = 0 بس عنا تاريخ، احسبه
      // تاريخ الميلاد المتحقق منه هو المصدر؛ age و isUserAdult القديمان لا يمنحان صلاحية.
      if (!doc.metadata.isFromCache && !doc.metadata.hasPendingWrites) {
        _applyVerifiedAge(data, user.uid, session);
      } else {
        _resetVerifiedAge();
      }
      
      final passwordProviders = user.providerData.where((p) => p.providerId == 'password').toList();
      final googleProviders = user.providerData.where((p) => p.providerId == 'google.com').toList();
      final phoneProviders = user.providerData.where((p) => p.providerId == 'phone').toList();
      final resolvedEmail = passwordProviders.isNotEmpty
          ? (passwordProviders.first.email ?? user.email)
          : (googleProviders.isNotEmpty ? (googleProviders.first.email ?? user.email) : null);
      final resolvedPhone = phoneProviders.isNotEmpty
          ? (phoneProviders.first.phoneNumber ?? user.phoneNumber)
          : null;

      // بيانات الاتصال تُقرأ من المزوّد المرتبط فعلياً، وليس من قيم Firestore القديمة.
      _email = resolvedEmail ?? "";
      _phoneNumber = resolvedPhone ?? "";

      final contactRepairs = <String, dynamic>{};
      if (resolvedEmail != null && resolvedEmail.isNotEmpty) {
        if (data['email'] != resolvedEmail) contactRepairs['email'] = resolvedEmail;
        if (data['email_lowercase'] != resolvedEmail.toLowerCase()) {
          contactRepairs['email_lowercase'] = resolvedEmail.toLowerCase();
        }
      } else {
        if (data.containsKey('email')) contactRepairs['email'] = FieldValue.delete();
        if (data.containsKey('email_lowercase')) contactRepairs['email_lowercase'] = FieldValue.delete();
      }
      if (resolvedPhone != null && resolvedPhone.isNotEmpty) {
        if (data['phoneNumber'] != resolvedPhone) contactRepairs['phoneNumber'] = resolvedPhone;
        if (data['phone'] != resolvedPhone) contactRepairs['phone'] = resolvedPhone;
      } else {
        if (data.containsKey('phoneNumber')) contactRepairs['phoneNumber'] = FieldValue.delete();
        if (data.containsKey('phone')) contactRepairs['phone'] = FieldValue.delete();
      }
      if (passwordProviders.isNotEmpty && data['emailVerified'] != user.emailVerified) {
        contactRepairs['emailVerified'] = user.emailVerified;
      }
      if (contactRepairs.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            contactRepairs,
            SetOptions(merge: true),
          );
        } catch (_) {
          // فشل إصلاح حقول الاتصال لا يمنع تحميل بقية بيانات الحساب.
        }
      }

      if (data.containsKey('createdAt') && data['createdAt'] != null) {
        _createdAt = (data['createdAt'] as Timestamp).toDate().toString();
      }

      _profileCompleted = (_fullName != "مستخدم جديد"); 

      Map<String, dynamic> repairs = {};
      if (data['fullName'] == null || data['fullName'] == "" || data['fullName'] == "مستخدم جديد") repairs['fullName'] = _fullName;
      if (data['username'] == null || data['username'] == "") repairs['username'] = _username;
      if ((data['email'] == null || data['email'] == "") && _email != null && _email!.isNotEmpty && (user.email != null && user.email!.isNotEmpty)) repairs['email'] = _email;
      if (!data.containsKey('profileCompleted')) repairs['profileCompleted'] = _profileCompleted;
      // [إضافة البحث]: إصلاح الحقول الصغيرة للمستخدمين القدامى
      if (!data.containsKey('username_lowercase') && _username != null) repairs['username_lowercase'] = _username!.toLowerCase();
      if (!data.containsKey('fullName_lowercase') && _fullName != null) repairs['fullName_lowercase'] = _fullName!.toLowerCase();
      // [إضافة إجبارية V6]: مزامنة دائمة للبحث - تتجاوز القيم القديمة من جوجل
      if (_username != null) repairs['username_lowercase'] = _username!.toLowerCase().trim();
      if (_fullName != null) repairs['fullName_lowercase'] = _fullName!.toLowerCase().trim();
      if (!data.containsKey('isPrivate')) repairs['isPrivate'] = false;
      if (!data.containsKey('isAdultContent')) repairs['isAdultContent'] = AudiencePolicy.isAccountRestricted(data);
      if (!data.containsKey('audience_18plus')) repairs['audience_18plus'] = AudiencePolicy.isAccountRestricted(data);
      if (!data.containsKey('isUserAdult')) repairs['isUserAdult'] = false;
      if (!data.containsKey('age')) repairs['age'] = 0;
      
      if (repairs.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(repairs, SetOptions(merge: true));
      }

      if (!isCurrentFetch()) return;
      String? checkType = await _secureStorage.read(key: 'auth_type_${user.uid}');
      if (!isCurrentFetch()) return;
      if (checkType != null) {
        _authType = checkType;
      } else {
        String detectedType = "email";
        if (user.providerData.any((p) => p.providerId == 'google.com')) detectedType = "google";
        else if (user.providerData.any((p) => p.providerId == 'phone')) detectedType = "phone";
        _authType = detectedType;
        await syncCurrentAccountToVault(user.uid, detectedType);
      }

      await _saveAccountLocally();

      if (!isCurrentFetch()) return;
      // --- [تصحيح محرك التحديث اللحظي للعدادات والقيود] ---
      _liveUserSub?.cancel();
      _liveUserSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(includeMetadataChanges: true)
          .listen((snapshot) {
        if (!isCurrentFetch()) return;
        if (snapshot.exists) {
          final liveData = snapshot.data() as Map<String, dynamic>;
          _followers = liveData['followers'] ?? 0;
          _following = liveData['following'] ?? 0;
          _likes = liveData['likes'] ?? 0;
                    // _followingList صار من subcollection
          _isAgeRestricted = liveData['isAgeRestricted'] ?? false;
          _isPrivate = liveData['isPrivate'] ?? false;
          _defaultPrivacy = liveData['defaultPrivacy'] ?? _defaultPrivacy;
          _commentPrivacy = liveData['commentPrivacy'] ?? _commentPrivacy;
          _mentionPrivacy = liveData['mentionPrivacy'] ?? _mentionPrivacy;
          _likedVideosPrivacy = liveData['likedVideosPrivacy'] ?? 'only_me';
          _favoriteVideosPrivacy = liveData['favoriteVideosPrivacy'] ?? 'only_me';
          _whoCanSeeFollowingList = liveData['whoCanSeeFollowingList'] ?? _whoCanSeeFollowingList;
          _messageRequestPrivacy = liveData['messageRequestPrivacy'] ?? _messageRequestPrivacy;
          _groupAddPrivacy = liveData['groupAddPrivacy'] ?? _groupAddPrivacy;
          _storyReplyPrivacy = liveData['storyReplyPrivacy'] ?? _storyReplyPrivacy;
          _showReadReceipts = liveData['showReadReceipts'] ?? _showReadReceipts;
          _showActivityStatus = liveData['showActivityStatus'] ?? true;
          _profileImg = liveData['profileImg'] ?? _profileImg;
          _isAdultContent = AudiencePolicy.isAccountRestricted(liveData);
          _audience18Plus = _isAdultContent;
          if (!snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites) {
            _applyVerifiedAge(liveData, user.uid, session);
          } else {
            _resetVerifiedAge();
          }

          // [Tini: نظام الحظر - Two Way] - تحديث لحظي + من subcollection
          try {
            final List bLive = liveData['blockedUsers'] ?? liveData['blocked'] ?? [];
            if (liveData.containsKey('blockedUsers') || liveData.containsKey('blocked')) {
              _blockedUsers = bLive.map((e) => e.toString()).toSet();
              // ادمج مع الـ subcollection كمان بالـ live
              FirebaseFirestore.instance.collection('users').doc(user.uid).collection('blocked').get().then((snap) {
                if (!isCurrentFetch()) return;
                for (var d in snap.docs) _blockedUsers.add(d.id);
                notifyListeners();
              });
            }
            // [Two-Way Live] - تحديث مين حاظرني لحظيا
            FirebaseFirestore.instance.collection('users').doc(user.uid).collection('blockedBy').get().then((snap) {
              if (!isCurrentFetch()) return;
              _blockedByUsers = snap.docs.map((e) => e.id).toSet();
              notifyListeners();
            });
          } catch (_) {}

          notifyListeners();
        } else {
          _resetVerifiedAge();
          notifyListeners();
        }
      }, onError: (_) {
        if (!isCurrentFetch()) return;
        _resetVerifiedAge();
        notifyListeners();
      });
    } else {
      if (user.displayName == null && user.email == null && user.phoneNumber == null) {

          await signOut(); 
          return;
      }

     
      String detectedType = "email";
      if (user.providerData.any((p) => p.providerId == 'google.com')) detectedType = "google";
      else if (user.providerData.any((p) => p.providerId == 'phone')) detectedType = "phone";

      // [إضافة جديدة] قراءة تاريخ الميلاد وحساب العمر مباشرة من التاريخ
      final prefs = await SharedPreferences.getInstance();
      if (!isCurrentFetch()) return;
      final String? savedDob = pendingRegistrationBirthDate(prefs, user);
      int savedAge = 0;
      bool savedAdult = false;
      if (savedDob != null) {
        try {
          final b = DateTime.parse(savedDob);
          final now = DateTime.now();
          savedAge = now.year - b.year;
          if (now.month < b.month || (now.month == b.month && now.day < b.day)) savedAge--;
          savedAdult = savedAge >= 18;
        } catch (_) {}
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fullName': user.displayName ?? (_fullName ?? "مستخدم جديد"),
        'username': "user_${user.uid.substring(0, 5)}",
        'username_lowercase': "user_${user.uid.substring(0, 5)}".toLowerCase(),
        'fullName_lowercase': (user.displayName ?? (_fullName ?? "مستخدم جديد")).toLowerCase(),
        'email': user.email ?? _email,
        'phoneNumber': user.phoneNumber ?? _phoneNumber,
        'authMethod': detectedType,
        'bio': "",
        'isAgeRestricted': false,
        'profileImg': "",
        'birthDate': savedDob ?? "",
        'dob': savedDob != null ? Timestamp.fromDate(DateTime.parse(savedDob)) : null,
        'age': savedAge,
        'isUserAdult': savedAdult,
        'followers': 0,
        'following': 0,
        'likes': 0,
        
        'isPrivate': false,
        'showActivityStatus': true,
        'isVisitsEnabled': true,
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'uid': user.uid,
        'profileCompleted': false, 
      }, SetOptions(merge: true));
      
      _fullName = user.displayName ?? (_fullName ?? "مستخدم جديد");
      _username = "user_${user.uid.substring(0, 5)}";
      _email = user.email ?? _email;
      if (!isCurrentFetch()) return;
      _birthDate = savedDob ?? '';
      _isAgeRestricted = false;
      _profileCompleted = false; 
      _followingList = {};
    }
  } catch (_) {
    if (isCurrentFetch()) _resetVerifiedAge();
  } finally {
    if (isCurrentFetch()) {
      await saveFcmTokenToFirestore();
      if (isCurrentFetch()) {
        _isAuthChecked = true;
        notifyListeners();
      }
    }
  }
}

        Future<void> pickAndUploadImage() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return;

      _setLoading(true);
      File file = File(image.path);
      
      final r2 = R2Service();
      final String oldUrl = _profileImg ?? "";

      String objectName = 'profile_images/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      String downloadUrl = await r2.uploadFile(file, objectName);

      if (oldUrl.isNotEmpty) {
        try {
          await r2.deleteByUrl(oldUrl);
          await CachedNetworkImage.evictFromCache(oldUrl);
        } catch (_) {}
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'profileImg': downloadUrl,
      });

      try {
        final batch = FirebaseFirestore.instance.batch();
        final posts = await FirebaseFirestore.instance.collection('posts').where('uid', isEqualTo: user.uid).get();
        for (var doc in posts.docs) {
          batch.update(doc.reference, {'profileImg': downloadUrl});
        }
        await batch.commit();
      } catch (_) {}

      _profileImg = downloadUrl;
      await _saveAccountLocally();
      notifyListeners();
    } catch (_) {

    } finally {
      _setLoading(false);
    }
  }

Future<bool> updateUserProfile(String newFullName, String newUsername, String newBio, {String? newBirthDate}) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final session = _authSession;
    if (newBirthDate != null &&
        AudiencePolicy.verifiedAge({'birthDate': newBirthDate}) == null) return false;
    _setLoading(true);
    try {
      // [1] التحديث في Firestore (قاعدة البيانات)
      if (newBirthDate != null) _resetVerifiedAge();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'fullName': newFullName,
        'username': newUsername,
        'username_lowercase': newUsername.toLowerCase().trim(),
        'fullName_lowercase': newFullName.toLowerCase().trim(),
        'bio': newBio,
        if (newBirthDate != null) ...{
          'birthDate': newBirthDate,
          'dob': Timestamp.fromDate(DateTime.parse(newBirthDate)),
          'age': AudiencePolicy.verifiedAge({'birthDate': newBirthDate}) ?? 0,
          'isUserAdult': AudiencePolicy.viewerIsAdult({'birthDate': newBirthDate}),
        },
        'profileCompleted': true,
      });

      // [2] التحديث في Provider (الذاكرة والواجهة)
      if (!_isCurrentSession(user.uid, session)) return false;
      _fullName = newFullName;
      _username = newUsername;
      _bio = newBio;
      if (newBirthDate!= null) {
        _birthDate = newBirthDate;
      }

      _profileCompleted = true;
      await _saveAccountLocally();

      // [FIX V5.9 - تحديث الحسابات المحفوظة بعد تغيير الاسم من البروفايل]
      if (!_isCurrentSession(user.uid, session)) return false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('acc_${user.uid}_fullName', newFullName);
        await prefs.setString('acc_${user.uid}_username', newUsername);
        await prefs.setString('last_fullName', newFullName);
        await prefs.setString('last_username', newUsername);
        await user.updateDisplayName(newFullName);
      } catch (_) {}

      notifyListeners();
      return true;
    } catch (e) {

      return false;
    } finally {
      _setLoading(false);
    }
  }
    Future<bool> deleteProfileImage() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  
  _setLoading(true);
  try {
    final String oldUrl = _profileImg ?? "";
    if (oldUrl.isNotEmpty) {
      try {
        final r2 = R2Service();
        await r2.deleteByUrl(oldUrl);
        await CachedNetworkImage.evictFromCache(oldUrl);
      } catch (_) {}
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'profileImg': '',
    });
    _profileImg = '';
    await _saveAccountLocally();
    notifyListeners();
    return true;
  } catch (e) {

    return false;
  } finally {
    _setLoading(false);
  }
}

  // [تعديل ذهبي]: الإرسال التلقائي للإيميل إلى الموقع عند الدخول أو التسجيل
  Future<void> loginWithEmail(String email, String password) async {
    _setLoading(true);
    try {
      await FirebaseAuth.instance.signOut();

      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final String? currentUid = userCredential.user?.uid;

      if (currentUid != null) {
        await _savePasswordSecurely(currentUid, password.trim());
        await syncCurrentAccountToVault(currentUid, "email");

        // [الإضافة المطلوبة]: إرسال الإيميل للموقع تلقائياً مع الحماية (Merge)
        await FirebaseFirestore.instance.collection('users').doc(currentUid).set({
          'email': email.trim(),
          'authMethod': 'email',
        }, SetOptions(merge: true));

        // مزامنة جميع وسائل الدخول من Firebase بعد نجاح تسجيل الدخول.
        await syncAccountProvidersFromFirebase();
      }
      
      await fetchUserData();
      await saveFcmTokenToFirestore();
    } catch (e) {

      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // [تعديل ذهبي]: الإرسال التلقائي لرقم الهاتف والنوع للموقع والخزنة V5.2
  Future<void> loginWithPhone(String phoneNumber) async {
    _setLoading(true);
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _authType = "phone"; 
        await syncCurrentAccountToVault(user.uid, "phone");

        // التحقق مما إذا كان الحساب موجوداً لتجنب شاشة التسجيل
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          _profileCompleted = true;
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'phoneNumber': phoneNumber.trim(),
          'uid': user.uid,
          'authMethod': 'phone', 
        }, SetOptions(merge: true));
      }
      await fetchUserData();
      await saveFcmTokenToFirestore();
    } catch (_) {

    } finally {
      _setLoading(false);
    }
  }

  // [تعديل ذهبي]: الإرسال التلقائي لإيميل جوجل والنوع إلى الموقع V5.2 - تم تحديثها بربط clientId
  Future<void> loginWithGoogle() async {
    _setLoading(true);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false);
        return;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);

      final User? user = FirebaseAuth.instance.currentUser;
      
      if (user != null) {
        _authType = "google"; 
        _email = user.email;
        await syncCurrentAccountToVault(user.uid, "google");

        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
           _profileCompleted = true;
        }

        final prefs = await SharedPreferences.getInstance();
        final String? savedDob = !doc.exists ? pendingRegistrationBirthDate(prefs, user) : null;
        int calcAge = 0;
        bool calcAdult = false;
        if (savedDob != null) {
          try {
            final b = DateTime.parse(savedDob);
            final now = DateTime.now();
            calcAge = now.year - b.year;
            if (now.month < b.month || (now.month == b.month && now.day < b.day)) calcAge--;
            calcAdult = calcAge >= 18;
          } catch (_) {}
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': user.email,
          'uid': user.uid,
          'authMethod': 'google',
          if (!doc.exists && savedDob != null) ...{
            'birthDate': savedDob,
            'dob': Timestamp.fromDate(DateTime.parse(savedDob)),
            'age': calcAge,
            'isUserAdult': calcAdult,
          },
        }, SetOptions(merge: true));


        
        await fetchUserData();
        await saveFcmTokenToFirestore();
      }
    } catch (_) {

    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateEmailWithVerification(String newEmail) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    _setLoading(true);
    try {
      await user.verifyBeforeUpdateEmail(newEmail);
      // تم الحذف حسب قاعدة Tini V6: لا نحدث Firestore هنا
      // التحديث سيتم تلقائياً بعد تأكيد الرابط عبر fetchUserData
      return true; 
    } catch (e) {

      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> verifyPhoneNumber(String phone, {required Function(String) onCodeSent}) async {
    _setLoading(true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          final String? currentUid = FirebaseAuth.instance.currentUser?.uid;
          
          if (currentUid != null) {
            _authType = "phone"; 
            await syncCurrentAccountToVault(currentUid, "phone");

            await FirebaseFirestore.instance.collection('users').doc(currentUid).set({
              'phoneNumber': phone.trim(),
              'uid': currentUid,
              'authMethod': 'phone',
            }, SetOptions(merge: true));
          }
          await fetchUserData();
        },
        verificationFailed: (FirebaseAuthException e) {
          _setLoading(false);
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId);
          _setLoading(false);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      _setLoading(false);
    }
  }

    Future<void> signOut() async {
try {
  try {
    await ActivityStatusService().setOffline();
  } catch (_) {}
  ActivityStatusService().disposeService();
  ActivityStatusService().stopHeartbeat();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_uid'); 
      
      await FirebaseAuth.instance.signOut();
      _clearInternalData();
      notifyListeners(); 
    } catch (_) {

    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // تعديل دالة المزامنة لحفظ النوع ورقم الهاتف (اختياري)
  Future<void> syncCurrentAccountToVault(String uid, String type, {String? phoneNumber}) async {
    try {
      // 1. حفظ نوع الحساب (google, phone, email)
      await _secureStorage.write(key: 'auth_type_$uid', value: type);

      // 2. إذا كان الحساب هاتف، نحفظ الرقم أيضاً لنستخدمه في الدخول التلقائي
      if (type == "phone" && phoneNumber != null) {
        await _secureStorage.write(key: 'auth_phone_$uid', value: phoneNumber);
      }
    } catch (_) {

    }
  }

  // مزامنة وسائل الدخول من Firebase بوصفها المصدر الفعلي للحساب.
  // تُستخدم بعد unlink وعند فتح تفاصيل الحساب لإصلاح أي اختلاف سابق.
  Future<void> syncAccountProvidersFromFirebase() async {
    final initialUser = FirebaseAuth.instance.currentUser;
    if (initialUser == null) return;
    final uid = initialUser.uid;

    await initialUser.reload();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError("تغير الحساب أثناء مزامنة وسائل الدخول");
    }

    final providers = user.providerData
        .where((provider) => provider.providerId != 'firebase')
        .toList();
    final providerIds = providers.map((provider) => provider.providerId).toSet();
    if (providerIds.isEmpty) {
      throw StateError("لم يتم العثور على وسيلة دخول مرتبطة بالحساب");
    }

    final passwordProviders = providers.where((p) => p.providerId == 'password').toList();
    final googleProviders = providers.where((p) => p.providerId == 'google.com').toList();
    final phoneProviders = providers.where((p) => p.providerId == 'phone').toList();
    final hasPassword = passwordProviders.isNotEmpty;
    final hasGoogle = googleProviders.isNotEmpty;
    final hasPhone = phoneProviders.isNotEmpty;

    final email = hasPassword
        ? (passwordProviders.first.email ?? user.email)
        : (hasGoogle ? (googleProviders.first.email ?? user.email) : null);
    final googleEmail = hasGoogle ? googleProviders.first.email : null;
    final phoneNumber = (hasPhone ? phoneProviders.first.phoneNumber : null) ?? user.phoneNumber;
    final loginType = hasGoogle ? 'google' : (hasPhone ? 'phone' : 'email');
    final normalizedProviders = providerIds.toList()..sort();

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    String? firestoreSyncError;
    try {
      final snapshot = await userRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};
      final updates = <String, dynamic>{};

      void syncField(String key, dynamic value) {
        if (value == null || (value is String && value.isEmpty)) {
          if (data.containsKey(key)) updates[key] = FieldValue.delete();
        } else {
          final existing = data[key];
          final bool same = value is List && existing is List
              ? existing.length == value.length &&
                  List.generate(value.length, (index) => existing[index] == value[index]).every((match) => match)
              : existing == value;
          if (!same) updates[key] = value;
        }
      }

      syncField('email', email);
      syncField('email_lowercase', email?.toLowerCase());
      syncField('phoneNumber', hasPhone ? phoneNumber : null);
      syncField('phone', hasPhone ? phoneNumber : null);
      syncField('googleEmail', googleEmail);
      syncField('isGoogleLinked', hasGoogle);
      syncField('authMethod', loginType);
      syncField('authProviders', normalizedProviders);
      syncField('emailVerified', hasPassword ? user.emailVerified : null);

      final pendingEmail = data['pendingEmail'];
      if (!hasPassword || (user.emailVerified && pendingEmail is String && pendingEmail.isNotEmpty &&
          email != null && pendingEmail.toLowerCase() == email.toLowerCase())) {
        if (data.containsKey('pendingEmail')) updates['pendingEmail'] = FieldValue.delete();
        if (data.containsKey('pendingEmailRequestedAt')) updates['pendingEmailRequestedAt'] = FieldValue.delete();
      }

      if (updates.isNotEmpty) {
        await userRef.set(updates, SetOptions(merge: true));
      }
    } catch (error) {
      firestoreSyncError = error.toString();
    }

    // حدّث الخزنة حتى لو تعذر الاتصال بـ Firestore؛ لكل مخزن نتيجة مستقلة.
    String? vaultSyncError;
    try {
      await _secureStorage.write(key: 'auth_type_$uid', value: loginType);
      if (hasPhone && phoneNumber != null && phoneNumber.isNotEmpty) {
        await _secureStorage.write(key: 'auth_phone_$uid', value: phoneNumber);
      } else {
        await _secureStorage.delete(key: 'auth_phone_$uid');
      }
      if (!hasPassword) {
        await _secureStorage.delete(key: 'auth_pass_$uid');
      }
    } catch (error) {
      vaultSyncError = error.toString();
    }

    _email = email ?? '';
    _phoneNumber = hasPhone ? (phoneNumber ?? '') : '';
    _authType = loginType;
    try {
      await _saveAccountLocally();
    } catch (error) {
      vaultSyncError = vaultSyncError == null
          ? error.toString()
          : "$vaultSyncError; local cache: $error";
    }
    notifyListeners();
    if (firestoreSyncError != null || vaultSyncError != null) {
      final errors = <String>[];
      if (firestoreSyncError != null) errors.add("Firestore: $firestoreSyncError");
      if (vaultSyncError != null) errors.add("Vault: $vaultSyncError");
      throw StateError(errors.join("\n"));
    }
  }
  // [PASSKEY V5 - عبر PasskeyService يلي انت انشأتو]
  Future<void> loadPasskeyStatus() async {
    _passkeyEnabled = await PasskeyService.isEnabledLocal();
    notifyListeners();
  }

  Future<bool> enablePasskey() async {
    try {
      final String curUid = FirebaseAuth.instance.currentUser?.uid?? uid;
      if (curUid.isEmpty) return false;
      final bool ok = await PasskeyService.enableForUid(curUid);
      if (ok) {
        _passkeyEnabled = true;
        _passkeyEnabledMap[curUid] = true;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disablePasskey() async {
    try {
      final String curUid = FirebaseAuth.instance.currentUser?.uid?? uid;
      if (curUid.isEmpty) {
        await PasskeyService.disable();
      } else {
        await PasskeyService.disableForUid(curUid);
      }
      _passkeyEnabled = false;
      if (curUid.isNotEmpty) _passkeyEnabledMap[curUid] = false;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> loginWithPasskey() async {
    try {
      if (!await PasskeyService.canCheck()) return false;
      final String? storedUid = await PasskeyService.getStoredUid();
      if (storedUid == null) return false;
      final bool didAuth = await PasskeyService.authenticateForLogin();
      if (!didAuth) return false;
      final bool ok = await silentLogin(storedUid);
      if (ok) {
        await saveActiveSession(storedUid, loginMethod: 'passkey');
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  // [PASSKEY MULTI V6 - ADDITION ONLY - كل حساب الو بصمتو لحالو]
  Future<bool> isPasskeyEnabledForUid(String uidCheck) async {
    try {
      final bool enabled = await PasskeyService.isEnabledForUid(uidCheck);
      _passkeyEnabledMap[uidCheck] = enabled;
      return enabled;
    } catch (_) {
      return false;
    }
  }

  Future<bool> enablePasskeyForUid(String uidTarget) async {
    try {
      final bool ok = await PasskeyService.enableForUid(uidTarget);
      if (ok) {
        _passkeyEnabledMap[uidTarget] = true;
        if (uidTarget == uid) _passkeyEnabled = true;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disablePasskeyForUid(String uidTarget) async {
    try {
      await PasskeyService.disableForUid(uidTarget);
      _passkeyEnabledMap[uidTarget] = false;
      if (uidTarget == uid) _passkeyEnabled = false;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> loginWithPasskeyForUid(String uidTarget) async {
    try {
      if (!await PasskeyService.canCheck()) return false;
      if (!await PasskeyService.isEnabledForUid(uidTarget)) return false;
      final bool didAuth = await PasskeyService.authenticateForUid(uidTarget);
      if (!didAuth) return false;
      final bool ok = await silentLogin(uidTarget);
      if (ok) {
        await saveActiveSession(uidTarget, loginMethod: 'passkey');
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  // دالة إضافية لجلب الرقم المخزن عند الحاجة
  Future<String?> getPhoneNumberFromVault(String uid) async {
    return await _secureStorage.read(key: 'auth_phone_$uid');
  }

  // 2. إضافة دالة الجلب النهائية (التي كانت تظهر باللون الأحمر)
  Future<String> getLoginTypeFromVault(String uid) async {
    try {
      // قراءة النوع - تأكد أن هذا المفتاح هو نفسه المستخدم في دالة syncCurrentAccountToVault
      String? type = await _secureStorage.read(key: 'auth_type_$uid');
      
      // إذا لم يجد بيانات، يعيد "email" كخيار افتراضي لمنع تعطل التطبيق
      return type ?? "email";
    } catch (e) {

      return "email";
    }
  }
  void setGoogleData({required String email, required String name}) {

  _email = email;
  _fullName = name;
  notifyListeners(); // هذا السطر هو الذي سيجعل الشاشة "تقفز" وتظهر البريد فوراً
}

  Future<void> savePasswordToVault(String uid, String password) async {
    try {
      await _secureStorage.write(key: 'auth_pass_$uid', value: password.trim());
    } catch (_) {

    }
  }

  // نسخة صارمة لمسارات تغيير كلمة السر: لا تبتلع أخطاء التخزين المحلي.
  Future<void> savePasswordToVaultStrict(String uid, String password) async {
    await _secureStorage.write(key: 'auth_pass_$uid', value: password.trim());
  }
  // [Tini - Live Sync Engine]
  StreamSubscription<DocumentSnapshot>? _counterSubscription;

  void startLiveCounterSync() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final session = _authSession;
    _counterSubscription?.cancel();
    _counterSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (!_isCurrentSession(user.uid, session)) return;
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        _followers = data['followers'] ?? 0;
        _following = data['following'] ?? 0;
        _likes = data['likes'] ?? 0;

        _isPrivate = data['isPrivate'] ?? false;
        _defaultPrivacy = data['defaultPrivacy'] ?? _defaultPrivacy;
        _commentPrivacy = data['commentPrivacy'] ?? _commentPrivacy;
        _mentionPrivacy = data['mentionPrivacy'] ?? _mentionPrivacy;
        _likedVideosPrivacy = data['likedVideosPrivacy'] ?? 'only_me';
        _favoriteVideosPrivacy = data['favoriteVideosPrivacy'] ?? 'only_me';
        _whoCanSeeFollowingList = data['whoCanSeeFollowingList'] ?? _whoCanSeeFollowingList;
        _isAdultContent = AudiencePolicy.isAccountRestricted(data);
        _audience18Plus = _isAdultContent;
        notifyListeners(); // هذا السطر هو الذي يحدث الأرقام في الشاشة فوراً
       
      }
    });
  }

    void stopLiveCounterSync() {
    _counterSubscription?.cancel();
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    _liveUserSub?.cancel();
    _liveBlockedBySub?.cancel(); // [Two-Way]
    _liveBlockedSub?.cancel(); // [Two-Way]
    _counterSubscription?.cancel();
    super.dispose();
  }

  // ==========================================
// [Tini]: فحص حالة المتابعة
// ==========================================
Future<bool> isFollowing(String targetUserId) async {
  final String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
  if (myUid.isEmpty || myUid == targetUserId) return false;
  if (_followingList.contains(targetUserId)) return true;
  try {
    final doc = await FirebaseFirestore.instance.collection('users').doc(myUid).collection('following').doc(targetUserId).get();
    return doc.exists;
  } catch (e) {
    return false;
  }
}
  // ==========================================
// [Tini]: دالة المتابعة وإلغاء المتابعة الذهبية V2.2 - Subcollections Only
// ==========================================
Future<void> toggleFollow(String targetUserId) async {
  final String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
  if (myUid.isEmpty || myUid == targetUserId) return;

  try {
    final myDocRef = FirebaseFirestore.instance.collection('users').doc(myUid);
    final targetDocRef = FirebaseFirestore.instance.collection('users').doc(targetUserId);
    final followingSubRef = myDocRef.collection('following').doc(targetUserId);
    final followersSubRef = targetDocRef.collection('followers').doc(myUid);

    final followingDoc = await followingSubRef.get();
    final isFollowing = followingDoc.exists;

    // 1- المتابعة - بدون batch عشان ما تفشل
    if (isFollowing) {
      await followingSubRef.delete();
      await followersSubRef.delete();
      _followingList.remove(targetUserId);
      _following = (_following > 0) ? _following - 1 : 0;
    } else {
      await followingSubRef.set({'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      await followersSubRef.set({'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      _followingList.add(targetUserId);
      _following++;
    }
    notifyListeners();

    // 2- العداد - لحاله
    try {
      if (isFollowing) {
        await myDocRef.update({'following': FieldValue.increment(-1)});
        await targetDocRef.update({'followers': FieldValue.increment(-1)});
      } else {
        await myDocRef.update({'following': FieldValue.increment(1)});
        await targetDocRef.update({'followers': FieldValue.increment(1)});
      }
    } catch (_) {

    }

    // 3- الاشعار - لحاله - مفصول مشان يشتغل حتى لو العداد فشل
    if (!isFollowing) {
      try {
        await FirebaseFirestore.instance.collection('activities').add({
          'toUid': targetUserId,
          'fromUid': myUid,
          'type': 'follow',
          'text': '$_fullName بدأ بمتابعتك',
          'timestamp': FieldValue.serverTimestamp(),
          'seen': false,
        });
      } catch (_) {

      }
    }

  } catch (_) {

  }
}

// [Tini]: إزالة متابع من قائمة المتابعين
Future<void> removeFollower(String followerUid) async {
  final String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
  if (myUid.isEmpty || myUid == followerUid) return;

  try {
    final myDocRef = FirebaseFirestore.instance.collection('users').doc(myUid);
    final followerDocRef = FirebaseFirestore.instance.collection('users').doc(followerUid);

    final followerFollowingRef = followerDocRef.collection('following').doc(myUid);
    final myFollowersRef = myDocRef.collection('followers').doc(followerUid);

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(followerFollowingRef);
    batch.delete(myFollowersRef);

    await batch.commit();

    // تحديث محلي اختياري
    notifyListeners();

  } catch (_) {

  }
}
  // [Tini]: 1. محرك فحص العمر (Logic)
  // تحسب العمر بناءً على التاريخ المخزن وتحدد إذا كان المستخدم تحت الـ 18
  bool get isUserUnder18 {
    // اذا isUserAdult موجود بالداتا نعتمد عليه أولا
    // إذا لا يوجد تاريخ، نعتبره تحت السن للحماية
    // تدقيق الشهور والأيام لحساب العمر بدقة متناهية
    // التحقق الحالي يعتمد على ميلاد صالح وقراءة خادم للحساب نفسه، وليس العلم القديم.
    return !isUserAdult;
  }

  // [Tini]: 2. دالة حفظ التاريخ في الذاكرة (Memory Update)
  // تُستخدم لتحديث التاريخ فوراً عند اختيار المستخدم له من الشاشة
  void setBirthDate(String date) {
    _birthDate = date;
    _resetVerifiedAge();
    _profileCompleted = true; // نعتبر الملف اكتمل بمجرد إدخال التاريخ
    _saveAccountLocally();    // حفظ التغيير في التخزين الآمن فوراً
    notifyListeners();        // تحديث الواجهة لإخفاء شاشة الميلاد
  }

  // [إضافة Tini]: فحص فوري لحالة المتابعة بدون await
  bool isFollowingSync(String targetUserId) {
    return _followingList.contains(targetUserId);
  }
    // [FIX] فحص فوري هل هو بيتابعني
  bool isFollowerSync(String targetUserId) {
    return _followersList.contains(targetUserId);
  }

  // [FIX] فحص الصداقة المتبادلة
  bool isFriendSync(String targetUserId) {
    return _followingList.contains(targetUserId) && _followersList.contains(targetUserId);
  }
  Future<bool> updateMessageRequests(bool allow) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentUser == null) return false;
    final session = _authSession;

    try {
      // لا تُخفِ الشريط ولا تُحدِّث الحالة المحلية قبل نجاح حفظ Firestore.
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'allowMessageRequests': allow,
        'hideMessageRequestBanner': true,
      });
      if (!_isCurrentSession(user.uid, session) || _currentUser == null) return false;

      _currentUser = _currentUser!.copyWith(
        allowMessageRequests: allow,
        hideMessageRequestBanner: true,
      );
      notifyListeners();
      try {
        await _saveAccountLocally();
      } catch (e) {
        // حفظ Firestore نجح؛ فشل التخزين المحلي لا يلغي الموافقة المحفوظة.
        debugPrint('[Tini] Failed to cache message request consent: $e');
      }
      return true;
    } catch (e) {
      debugPrint('[Tini] Failed to save message request consent: $e');
      return false;
    }
  }

  Future<bool> dismissMessageRequestBanner() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentUser == null) return false;
    final session = _authSession;

    try {
      // علامة الإغلاق تخفي الشريط فقط، ولا تغيّر سماح طلبات المراسلة.
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'hideMessageRequestBanner': true,
      });
      if (!_isCurrentSession(user.uid, session) || _currentUser == null) return false;

      _currentUser = _currentUser!.copyWith(hideMessageRequestBanner: true);
      notifyListeners();
      try {
        await _saveAccountLocally();
      } catch (e) {
        debugPrint('[Tini] Failed to cache message request banner dismissal: $e');
      }
      return true;
    } catch (e) {
      debugPrint('[Tini] Failed to dismiss message request banner: $e');
      return false;
    }
  }
  // [Tini]: Private Account Toggle - V1
  Future<void> updatePrivateAccount(bool value) async {
    try {
      _isPrivate = value;
      notifyListeners();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isPrivate': value,
      });
      await _saveAccountLocally();

    } catch (_) {

    }
  }

  // [Tini]: Default Privacy - Who Can See Posts
  Future<void> updateDefaultPrivacy(String value) async {
    try {
      _defaultPrivacy = value;
      notifyListeners();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'defaultPrivacy': value,
      }, SetOptions(merge: true));
      await _saveAccountLocally();
    } catch (_) {}
  }

    Future<void> updateCommentPrivacy(String value) async {
    try {
      _commentPrivacy = value;
      notifyListeners();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'commentPrivacy': value,
      }, SetOptions(merge: true));
      await _saveAccountLocally();
    } catch (_) {}
  }

  // [Tini - Liked Videos Privacy]: الحفظ يتم على Firebase أولاً دون تغيير نظام الإعجابات.
  Future<void> updateLikedVideosPrivacy(String value) async {
    if (value != 'everyone' && value != 'only_me') {
      throw ArgumentError.value(value, 'value', 'خيار خصوصية غير صالح');
    }
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) throw StateError('يجب تسجيل الدخول');
    await FirebaseFirestore.instance.collection('users').doc(currentUid).set(
      {'likedVideosPrivacy': value}, SetOptions(merge: true),
    );
    _likedVideosPrivacy = value;
    await _saveAccountLocally();
    notifyListeners();
  }

  // [Tini - Favorite Videos Privacy]: نفس منطق حفظ خصوصية الإعجابات، دون تغيير بيانات المفضلة.
  Future<void> updateFavoriteVideosPrivacy(String value) async {
    if (value != 'everyone' && value != 'only_me') {
      throw ArgumentError.value(value, 'value', 'خيار خصوصية غير صالح');
    }
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) throw StateError('يجب تسجيل الدخول');
    await FirebaseFirestore.instance.collection('users').doc(currentUid).set(
      {'favoriteVideosPrivacy': value}, SetOptions(merge: true),
    );
    _favoriteVideosPrivacy = value;
    await _saveAccountLocally();
    notifyListeners();
  }

  // [Tini - Mention Privacy]: حفظ مؤكد قبل تبديل حالة الواجهة.
  Future<void> updateMentionPrivacy(String value) async {
    if (!const {'everyone', 'following', 'friends', 'nobody'}.contains(value)) {
      throw ArgumentError.value(value, 'value', 'خيار خصوصية غير صالح');
    }
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) throw StateError('يجب تسجيل الدخول');
    await FirebaseFirestore.instance.collection('users').doc(currentUid).set(
      {'mentionPrivacy': value}, SetOptions(merge: true),
    );
    _mentionPrivacy = value;
    await _saveAccountLocally();
    notifyListeners();
  }

    Future<void> updateWhoCanSeeFollowingList(String value) async {
    try {
      _whoCanSeeFollowingList = value;
      notifyListeners();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'whoCanSeeFollowingList': value,
      }, SetOptions(merge: true));
      await _saveAccountLocally();
    } catch (_) {}
  }
  
  Future<void> updateMessageRequestPrivacy(String value) async {
    try {
      _messageRequestPrivacy = value;
      notifyListeners();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({'messageRequestPrivacy': value}, SetOptions(merge: true));
      await _saveAccountLocally();
    } catch (_) {}
  }

  Future<void> updateGroupAddPrivacy(String value) async {
    try {
      _groupAddPrivacy = value;
      notifyListeners();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({'groupAddPrivacy': value}, SetOptions(merge: true));
      await _saveAccountLocally();
    } catch (_) {}
  }

  Future<void> updateStoryReplyPrivacy(String value) async {
    try {
      _storyReplyPrivacy = value;
      notifyListeners();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({'storyReplyPrivacy': value}, SetOptions(merge: true));
      await _saveAccountLocally();
    } catch (_) {}
  }

  Future<void> updateReadReceipts(bool value) async {
    try {
      _showReadReceipts = value;
      notifyListeners();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({'showReadReceipts': value}, SetOptions(merge: true));
      await _saveAccountLocally();
    } catch (_) {}
  }

  Future<void> updateActivityStatus(bool value) async {
  try {
    _showActivityStatus = value;
    notifyListeners();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'showActivityStatus': value,
    });
    if (value) {
      await ActivityStatusService().init();
    } else {
      ActivityStatusService().disposeService();
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
    await _saveAccountLocally();
  } catch (_) {

  }
}
  // [Tini]: Audience Control Toggle - V1 - FIXED FOR POSTS
  Future<void> updateAudienceControl(bool value) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) throw StateError('يجب تسجيل الدخول');
    final session = _authSession;
    final batch = FirebaseFirestore.instance.batch();
    batch.set(FirebaseFirestore.instance.collection('users').doc(currentUid), {
      'isAdultContent': value,
      'audience_18plus': value,
    }, SetOptions(merge: true));
    batch.set(FirebaseFirestore.instance.doc('users/$currentUid/notificationSettings/preferences'), {
      'audience_18plus': value,
    }, SetOptions(merge: true));
    // [AUDIENCE CONTROL] - تحديث فيديوهاتك القديمة الـ 100 الأخيرة
    // أُلغي نسخ حالة الحساب إلى الفيديوهات: تصنيف فحص كل فيديو يبقى مستقلاً ومحفوظاً.
    await batch.commit();
    if (!_isCurrentSession(currentUid, session)) {
      throw StateError('تغير الحساب أثناء حفظ إعداد الجمهور');
    }
    _isAdultContent = value;
    _audience18Plus = value;
    notifyListeners();
    try {
      await _saveAccountLocally();
    } catch (_) {
      // تم تأكيد الحفظ على الخادم؛ فشل الكاش لا يعكس الإعداد المحفوظ.
    }
  }
}
