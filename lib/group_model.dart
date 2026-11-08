import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String groupId;
  final String groupName;
  final String groupImage;
  final String createdBy;
  final List<String> members;
  final List<String> admins;
  final List<String> moderators;
  final String lastMessage;
  final Timestamp? lastMessageTime;
  final String lastMessageSenderId;
  final Map<String, int> unreadCount;
  final Map<String, Timestamp> restricted; // <-- جديد

  GroupModel({
    required this.groupId,
    required this.groupName,
    required this.groupImage,
    required this.createdBy,
    required this.members,
    required this.admins,
    required this.moderators,
    required this.lastMessage,
    this.lastMessageTime,
    required this.lastMessageSenderId,
    required this.unreadCount,
    required this.restricted, // <-- جديد
  });

  factory GroupModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // قراءة التقييد - جديد
    final Map<String, Timestamp> parsedRestricted = {};
    final rawRestricted = data['restricted'] as Map<String, dynamic>?;
    if (rawRestricted!= null) {
      rawRestricted.forEach((k, v) {
        if (v is Timestamp) parsedRestricted[k] = v;
      });
    }

    return GroupModel(
      groupId: data['groupId']?? doc.id,
      groupName: data['groupName']?? 'مجموعة',
      groupImage: data['groupImage']?? '',
      createdBy: data['createdBy']?? '',
      members: List<String>.from(data['members']?? []),
      admins: List<String>.from(data['admins']?? []),
      moderators: List<String>.from(data['moderators']?? []),
      lastMessage: data['lastMessage']?? '',
      lastMessageTime: data['lastMessageTime'] as Timestamp?,
      lastMessageSenderId: data['lastMessageSenderId']?? '',
      unreadCount: Map<String, int>.from((data['unreadCount']?? {}).map((k, v) => MapEntry(k.toString(), (v as int?)?? 0))),
      restricted: parsedRestricted, // <-- جديد
    );
  }

  // ===== نظام الرتب الجديد =====
  // المالك هو صاحب الجروب - ما حدا بيقدر يشيله
  bool isOwner(String uid) => createdBy == uid;

  bool isAdmin(String uid) => admins.contains(uid) || isOwner(uid);

  bool isModerator(String uid) => moderators.contains(uid);

  bool isMemberOnly(String uid) => members.contains(uid) &&!isAdmin(uid) &&!isModerator(uid);

  String getRole(String uid) {
    if (isOwner(uid)) return 'المالك';
    if (admins.contains(uid)) return 'مسؤول';
    if (moderators.contains(uid)) return 'مشرف';
    return 'عضو';
  }

  // هل يقدر يشيل الثاني؟
  bool canRemove(String myUid, String targetUid) {
    if (targetUid == createdBy) return false; // ما حدا بيشيل المالك
    if (isOwner(myUid)) return true; // المالك بيشيل الكل
    if (isAdmin(myUid) &&!isOwner(targetUid) &&!isAdmin(targetUid)) return true; // المسؤول بيشيل المشرف والعضو
    if (isModerator(myUid) && isMemberOnly(targetUid)) return true; // المشرف بيشيل عضو بس
    return false;
  }

  // هل يقدر يعين مشرف؟
  bool canPromote(String myUid) {
    return isOwner(myUid) || isAdmin(myUid);
  }

  // ===== نظام التقييد المؤقت الجديد =====
  bool isRestricted(String uid) {
    if (!restricted.containsKey(uid)) return false;
    final until = restricted[uid]!;
    return until.toDate().isAfter(DateTime.now());
  }

  bool canRestrict(String myUid, String targetUid) {
    // نفس منطق الحذف
    return canRemove(myUid, targetUid);
  }
}