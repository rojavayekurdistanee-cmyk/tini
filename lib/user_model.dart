import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'audience_policy.dart';

class UserModel {
  final String uid;
  final String fullName;
  final String username;
  final String? profileImg;
  final String? email;
  final String? phoneNumber;
  final String loginType; // google, phone, email
  final String bio;
  final String? birthDate;
  final Map<String, dynamic>? _ageSource;
  
  // Counters
  final int followers;
  final int following;
  final int likes;

  
  // Status
  final bool profileCompleted;
  final bool isAgeRestricted;
  final DateTime? createdAt;
  
  // Badge System
  final String? badge;
  final DateTime? badgeEndsAt;
  
  // Wallet
  final int tiniBalance;
  
  // Admin
  final bool isAdmin;
  
  // Crown - جديد من CrownProvider
  final String? crownNumber;

  // جديد: إعدادات طلبات الرسائل
  final bool allowMessageRequests;
  final bool hideMessageRequestBanner;

  // جديد: حالة النشاط V1 - اضافة فقط
  final bool isOnline;
  final DateTime? lastSeen;
  final bool showActivityStatus;

  UserModel({
    required this.uid,
    required this.fullName,
    required this.username,
    this.profileImg,
    this.email,
    this.phoneNumber,
    required this.loginType,
    this.bio = '',
    this.birthDate,
    Map<String, dynamic>? ageSource,
    this.followers = 0,
    this.following = 0,
    this.likes = 0,

    required this.profileCompleted,
    this.isAgeRestricted = false,
    this.createdAt,
    this.badge,
    this.badgeEndsAt,
    this.tiniBalance = 0,
    this.isAdmin = false,
    this.crownNumber, // جديد
    this.allowMessageRequests = false, // جديد: افتراضي مقفول
    this.hideMessageRequestBanner = false, // جديد: افتراضي البانر ظاهر
    this.isOnline = false, // جديد: اضافة فقط
    this.lastSeen, // جديد: اضافة فقط
    this.showActivityStatus = true, // جديد: اضافة فقط
  }) : _ageSource = ageSource == null ? null : Map.unmodifiable(ageSource);

  // Getters
  String get joinedDate => createdAt == null 
      ? "غير متوفر" 
      : DateFormat('yyyy/MM/dd').format(createdAt!);

  bool get hasActiveBadge {
    if (badge == null || badgeEndsAt == null) return false;
    return DateTime.now().isBefore(badgeEndsAt!);
  }

  bool get isUnder18 {
    return !AudiencePolicy.viewerIsAdult(_ageSource ?? {'birthDate': birthDate});
  }

  bool isFollowingSync(String targetUserId) => false;

  // توليد رقم تاج ثابت من UID - نفس دالة CrownProvider
  String generateCrownNumber() {
    final hash = uid.hashCode.abs().toString().padLeft(5, '0');
    return 'Tini-${hash.substring(0, 5)}';
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final primaryBirth = json['birthDate'];
    final rawBirth = primaryBirth == null ||
        (primaryBirth is String && primaryBirth.trim().isEmpty) ? json['dob'] : primaryBirth;
    return UserModel(
      uid: json['uid'] ?? '',
      fullName: json['fullName'] ?? 'مستخدم جديد',
      username: json['username'] ?? 'user',
      profileImg: json['profileImg'],
      email: json['email'],
      phoneNumber: json['phoneNumber'],
      loginType: json['authType'] ?? json['authMethod'] ?? 'email',
      bio: json['bio'] ?? '',
      birthDate: rawBirth is String ? rawBirth
          : rawBirth is Timestamp ? rawBirth.toDate().toIso8601String()
          : rawBirth is DateTime ? rawBirth.toIso8601String() : null,
      ageSource: {'birthDate': json['birthDate'], 'dob': json['dob']},
      followers: json['followers'] ?? 0,
      following: json['following'] ?? 0,
      likes: json['likes'] ?? 0,

      profileCompleted: json['profileCompleted'] ?? false,
      isAgeRestricted: json['isUserUnder18'] ?? json['isAgeRestricted'] ?? false,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      badge: json['badge'],
      badgeEndsAt: (json['badgeEndsAt'] as Timestamp?)?.toDate(),
      tiniBalance: json['tiniBalance'] ?? 0,
      isAdmin: json['isAdmin'] ?? false,
      crownNumber: json['crownNumber'], // جديد
      allowMessageRequests: json['allowMessageRequests'] ?? false, // جديد
      hideMessageRequestBanner: json['hideMessageRequestBanner'] ?? false, // جديد
      isOnline: json['isOnline'] ?? false, // جديد: اضافة فقط
      lastSeen: (json['lastSeen'] as Timestamp?)?.toDate(), // جديد: اضافة فقط
      showActivityStatus: json['showActivityStatus'] ?? true, // جديد: اضافة فقط
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'fullName': fullName,
      'username': username,
      'fullName_lowercase': fullName.toLowerCase(),
      'username_lowercase': username.toLowerCase(),
      'profileImg': profileImg,
      'email': email,
      'phoneNumber': phoneNumber,
      'authType': loginType,
      'authMethod': loginType,
      'bio': bio,
      'birthDate': birthDate,
      'followers': followers,
      'following': following,
      'likes': likes,

      'profileCompleted': profileCompleted,
      'isUserUnder18': isUnder18,
      'isAgeRestricted': isUnder18,
      'createdAt': createdAt != null 
          ? Timestamp.fromDate(createdAt!) 
          : FieldValue.serverTimestamp(),
      'badge': badge,
      'badgeEndsAt': badgeEndsAt != null 
          ? Timestamp.fromDate(badgeEndsAt!) 
          : null,
      'tiniBalance': tiniBalance,
      'isAdmin': isAdmin,
            'crownNumber': crownNumber ?? generateCrownNumber(),
      'allowMessageRequests': allowMessageRequests,
      'hideMessageRequestBanner': hideMessageRequestBanner,
      // تم حذف isOnline و lastSeen و showActivityStatus من هنا عشان ما يخربوا شغل ActivityStatusService
    };
  }

  UserModel copyWith({
    String? uid, String? fullName, String? username, String? profileImg,
    String? email, String? phoneNumber, String? loginType, String? bio,
    String? birthDate, int? followers, int? following, int? likes,
    bool? profileCompleted, bool? isAgeRestricted,
    DateTime? createdAt, String? badge, DateTime? badgeEndsAt,
    int? tiniBalance, bool? isAdmin, String? crownNumber, // جديد
    bool? allowMessageRequests, bool? hideMessageRequestBanner, // جديد
    bool? isOnline, DateTime? lastSeen, bool? showActivityStatus, // جديد: اضافة فقط
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      profileImg: profileImg ?? this.profileImg,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      loginType: loginType ?? this.loginType,
      bio: bio ?? this.bio,
      birthDate: birthDate ?? this.birthDate,
      ageSource: birthDate != null ? {'birthDate': birthDate} : _ageSource,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      likes: likes ?? this.likes,

      profileCompleted: profileCompleted ?? this.profileCompleted,
      isAgeRestricted: isAgeRestricted ?? this.isAgeRestricted,
      createdAt: createdAt ?? this.createdAt,
      badge: badge ?? this.badge,
      badgeEndsAt: badgeEndsAt ?? this.badgeEndsAt,
      tiniBalance: tiniBalance ?? this.tiniBalance,
      isAdmin: isAdmin ?? this.isAdmin,
      crownNumber: crownNumber ?? this.crownNumber, // جديد
      allowMessageRequests: allowMessageRequests ?? this.allowMessageRequests, // جديد
      hideMessageRequestBanner: hideMessageRequestBanner ?? this.hideMessageRequestBanner, // جديد
      isOnline: isOnline ?? this.isOnline, // جديد: اضافة فقط
      lastSeen: lastSeen ?? this.lastSeen, // جديد: اضافة فقط
      showActivityStatus: showActivityStatus ?? this.showActivityStatus, // جديد: اضافة فقط
    );
  }
}