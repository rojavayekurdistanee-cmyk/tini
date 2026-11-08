import 'package:cloud_firestore/cloud_firestore.dart';

enum BoxStatus { available, onHold, sold }
enum BoxRarity { bronze, silver, gold, diamond }

class BoxModel {
  final String id;
  final BoxStatus status;
  final BoxRarity rarity;
  final String? ownedByUid;
  final String? ownedByName;
  final Timestamp? reservedAt;
  final Timestamp? boxExpiresAt; // ← جديد: وقت انتهاء الحجز
  final Timestamp? soldAt;
  final Timestamp? boxOpenedAt; // ← جديد: وقت فتح الصندوق
  final bool isMysteryBox; // ← جديد: للتأكد انه صندوق مش بوست عادي
  final int price;
  final int reserveMinutes;
  
  final String thumbnailUrl;
  final String videoUrl;
  final String userId;
  final String username;
  final String fullName;
  final String userProfileImg;
  final String caption;
  final String boxTitle; // [Tini]: العنوان التسويقي للصندوق
  final Timestamp createdAt;
  final List likes;
  final int commentsCount;

  BoxModel({
    required this.id,
    required this.status,
    required this.rarity,
    this.ownedByUid,
    this.ownedByName,
    this.reservedAt,
    this.boxExpiresAt, // ← جديد
    this.soldAt,
    this.boxOpenedAt, // ← جديد
    required this.isMysteryBox, // ← جديد
    required this.price,
    this.reserveMinutes = 10,
    required this.thumbnailUrl,
    required this.videoUrl,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.userProfileImg,
    required this.caption,
    required this.boxTitle, // [Tini]: إضافة للـ Constructor
    required this.createdAt,
    required this.likes,
    required this.commentsCount,
  });

  factory BoxModel.fromPostDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // شلت getRarityByPrice وحطيت هاي
    BoxRarity _parseRarity(String? rarityStr) {
      switch (rarityStr) {
        case 'silver': return BoxRarity.silver;
        case 'gold': return BoxRarity.gold;
        case 'diamond': return BoxRarity.diamond;
        case 'bronze':
        default: return BoxRarity.bronze;
      }
    }

    BoxStatus getStatus(Map<String, dynamic> data) {
      if (data['boxSold'] == true) return BoxStatus.sold;
      if (data['boxOwnedByUid'] != null) return BoxStatus.onHold;
      return BoxStatus.available;
    }

    return BoxModel(
      id: doc.id,
      status: getStatus(data),
      rarity: _parseRarity(data['boxRarity']),
      ownedByUid: data['boxOwnedByUid'],
      ownedByName: data['boxOwnedByName'],
      reservedAt: data['boxReservedAt'],
      boxExpiresAt: data['boxExpiresAt'], // ← جديد
      soldAt: data['boxSoldAt'],
      boxOpenedAt: data['boxOpenedAt'], // ← جديد: نقرأه من Firestore
      isMysteryBox: data['isMysteryBox'] ?? false, // ← جديد: default false للداتا القديمة
      price: data['boxPrice'] ?? 0,
      reserveMinutes: 10,
      thumbnailUrl: data['thumbnailUrl'] ?? data['videoUrl'] ?? '',
      videoUrl: data['videoUrl'] ?? '',
      userId: data['uid'] ?? '',
      username: data['username'] ?? '',
      fullName: data['fullName'] ?? '',
      userProfileImg: data['profileImg'] ?? '',
      caption: data['description'] ?? '',
      boxTitle: data['boxTitle'] ?? '', // [Tini]: نقرأه من Firestore
      createdAt: data['createdAt'] ?? Timestamp.now(),
      likes: data['likes'] ?? [],
      commentsCount: data['comments'] ?? 0,
    );
  }

  Map<String, dynamic> toPostMap() {
    // مهم: هاي الميثود لازم ترجع كل حقول الصندوق عشان update ما يمسح اشي
    return {
      'boxOwnedByUid': ownedByUid,
      'boxOwnedByName': ownedByName,
      'boxReservedAt': reservedAt,
      'boxExpiresAt': boxExpiresAt, // ← جديد
      'boxSoldAt': soldAt,
      'boxSold': status == BoxStatus.sold,
      'boxOpenedAt': boxOpenedAt, // ← جديد
      'isMysteryBox': isMysteryBox, // ← جديد
      'boxRarity': rarity.name, // ← جديد: نحول enum لـ String
      'boxPrice': price, // ← جديد: نضمن ان السعر ما ينحذف
      'boxTitle': boxTitle, // [Tini]: نضمن ان العنوان ما ينحذف
    };
  }

  Map<String, dynamic> toPostModel() {
    return {
      'id': id,
      'uid': userId,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'description': caption,
      'boxTitle': boxTitle, // [Tini]: إضافة للحفظ
      'username': username,
      'fullName': fullName,
      'profileImg': userProfileImg,
      'likes': likes,
      'comments': commentsCount,
      'createdAt': createdAt,
      'views': 0,
      'shares': 0,
      'allowComments': true,
      'allowDownload': true,
      'allowDuet': true,
      'isAgeRestricted': false,
    };
  }

  bool get isExpired {
    if (status != BoxStatus.onHold) return false;
    // الجديد يفضل - القديم للتوافق
    if (boxExpiresAt != null) {
      return DateTime.now().isAfter(boxExpiresAt!.toDate());
    }
    if (reservedAt == null) return false;
    final expiry = reservedAt!.toDate().add(Duration(minutes: reserveMinutes));
    return DateTime.now().isAfter(expiry);
  }

  // ← Helpers جديدة عشان الفلترة في BoxProvider
  bool get isOpened => boxOpenedAt != null;

  bool get isExpiredAfterOpen {
    if (boxOpenedAt == null) return false;
    final expiry = boxOpenedAt!.toDate().add(const Duration(hours: 24));
    return DateTime.now().isAfter(expiry);
  }
}