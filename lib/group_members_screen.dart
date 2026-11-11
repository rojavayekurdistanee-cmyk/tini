import 'user_documents.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'group_create_details_screen.dart';
import 'user_profile_sheet.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
// نفس ألوانك
const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);
const Color kFieldFill = Color(0xFF1C1C1E);
const Color kErrorRed = Color(0xFFE53935);

class GroupMembersScreen extends StatefulWidget {
  final String groupId;
  const GroupMembersScreen({super.key, required this.groupId});

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  bool _requireApproval = false;

  String _getRole(String uid, String createdBy, List<String> admins, List<String> moderators) {
    if (uid == createdBy) return 'المالك';
    if (admins.contains(uid)) return 'مسؤول';
    if (moderators.contains(uid)) return 'مشرف';
    return 'عضو';
  }

  void _showRestrictSheet(String memberId) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(2))),
            SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('مدة التقييد', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Divider(color: Colors.white12, height: 1),
            ListTile(
              title: Text('ساعة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
              onTap: () async {
                Navigator.pop(ctx);
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                  'restricted.$memberId': Timestamp.fromDate(DateTime.now().add(Duration(hours: 1))),
                  'restrictedBy.$memberId': myUid,
                });
              },
            ),
            ListTile(
              title: Text('يوم', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
              onTap: () async {
                Navigator.pop(ctx);
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                  'restricted.$memberId': Timestamp.fromDate(DateTime.now().add(Duration(days: 1))),
                  'restrictedBy.$memberId': myUid,
                });
              },
            ),
            ListTile(
              title: Text('3 أيام', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
              onTap: () async {
                Navigator.pop(ctx);
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                  'restricted.$memberId': Timestamp.fromDate(DateTime.now().add(Duration(days: 3))),
                  'restrictedBy.$memberId': myUid,
                });
              },
            ),
            ListTile(
              title: Text('أسبوع', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
              onTap: () async {
                Navigator.pop(ctx);
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                  'restricted.$memberId': Timestamp.fromDate(DateTime.now().add(Duration(days: 7))),
                  'restrictedBy.$memberId': myUid,
                });
              },
            ),
            ListTile(
              title: Text('شهر', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
              onTap: () async {
                Navigator.pop(ctx);
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                  'restricted.$memberId': Timestamp.fromDate(DateTime.now().add(Duration(days: 30))),
                  'restrictedBy.$memberId': myUid,
                });
              },
            ),
            ListTile(
              title: Text('دائم', style: TextStyle(color: kErrorRed, fontFamily: 'Tajawal')),
              onTap: () async {
                Navigator.pop(ctx);
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                  'restricted.$memberId': Timestamp.fromDate(DateTime.now().add(Duration(days: 365 * 10))),
                  'restrictedBy.$memberId': myUid,
                });
              },
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showMemberSheet(
    DocumentSnapshot userDoc,
    bool isCurrentUserAdmin,
    String memberId,
    List<String> admins, {
    required String createdBy,
    required List<String> moderators,
    required bool isCurrentUserOwner,
    required bool isCurrentUserModerator,
    required String myUid,
    required Map<String, dynamic> restricted,
    required Map<String, dynamic> restrictedBy,
  }) {
    final userData = userDoc.data() as Map<String, dynamic>?;
    final displayName = userData?['fullName']?? userData?['username']?? '';

    final bool targetIsOwner = memberId == createdBy;
    final bool targetIsAdmin = admins.contains(memberId);
    final bool targetIsModerator = moderators.contains(memberId);
    final bool targetIsMemberOnly =!targetIsOwner &&!targetIsAdmin &&!targetIsModerator;

    // منطق الحماية
    bool canRemove = false;
    if (!targetIsOwner) {
      if (isCurrentUserOwner) canRemove = true;
      else if (isCurrentUserAdmin &&!targetIsOwner &&!targetIsAdmin) canRemove = true;
      else if (isCurrentUserModerator && targetIsMemberOnly) canRemove = true;
    }

    bool canPromoteToModerator = targetIsMemberOnly && (isCurrentUserOwner || isCurrentUserAdmin);
    bool canDemoteModerator = targetIsModerator && (isCurrentUserOwner || isCurrentUserAdmin);
    bool canPromoteToAdmin = targetIsMemberOnly && isCurrentUserOwner;
    bool canDemoteAdmin = targetIsAdmin && isCurrentUserOwner;

    // ===== فحص التقييد =====
    bool isRestricted = false;
    if (restricted.containsKey(memberId)) {
      final ts = restricted[memberId];
      if (ts is Timestamp) {
        isRestricted = ts.toDate().isAfter(DateTime.now());
      }
    }
    final String? byUid = restrictedBy[memberId]?.toString();

    // هل انا اقدر افك تقييدو حسب الرتبة
    bool canUnrestrict = false;
    if (isRestricted) {
      if (isCurrentUserOwner) {
        canUnrestrict = true;
      } else if (isCurrentUserAdmin) {
        if (byUid == null || (byUid!= createdBy &&!admins.contains(byUid))) {
          if (canRemove) canUnrestrict = true;
        }
        if (targetIsMemberOnly || targetIsModerator) {
          if (byUid == null || (byUid!= createdBy)) {
             // المسؤول ما بيفك تقييد المالك
             if (byUid == null ||!admins.contains(byUid) || byUid == myUid) {
               canUnrestrict = true;
             }
             // استثناء: اذا الهدف عضو فقط يقدر
             if (targetIsMemberOnly) canUnrestrict = true;
             if (byUid == createdBy) canUnrestrict = false; // مالك قيد → مسؤول ما بيفك
          }
        }
      } else if (isCurrentUserModerator) {
        if (targetIsMemberOnly) {
          if (byUid == null || byUid == myUid || moderators.contains(byUid) || (!admins.contains(byUid!) && byUid!= createdBy)) {
            canUnrestrict = true;
          }
        }
      }
      // تصحيح نهائي: مسؤول ما بيفك تقييد المالك ابدا
      if (byUid == createdBy &&!isCurrentUserOwner) canUnrestrict = false;
      if (byUid!= null && admins.contains(byUid) && isCurrentUserModerator) canUnrestrict = false;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(2))),
            SizedBox(height: 16),
            ListTile(
              title: Text(displayName, style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text(_getRole(memberId, createdBy, admins, moderators) + (isRestricted? ' • مقيد' : ''), style: TextStyle(color: isRestricted? Colors.orange : Colors.white54, fontFamily: 'Tajawal')),
            ),
            Divider(color: Colors.white12, height: 1),
            // الخيارات حسب الرتبة
            if (canRemove)
              ListTile(
                onTap: () async {
                  Navigator.pop(c);
                  await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                    'members': FieldValue.arrayRemove([memberId]),
                    'admins': FieldValue.arrayRemove([memberId]),
                    'moderators': FieldValue.arrayRemove([memberId]),
                  });
                },
                title: Text('إزالة مستخدم', style: TextStyle(color: kErrorRed, fontFamily: 'Tajawal')),
              ),
            if (canPromoteToAdmin)
              ListTile(
                onTap: () async {
                  Navigator.pop(c);
                  await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                    'admins': FieldValue.arrayUnion([memberId]),
                  });
                },
                title: Text('تعيين كمسؤول', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
              ),
            if (canDemoteAdmin)
              ListTile(
                onTap: () async {
                  Navigator.pop(c);
                  await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                    'admins': FieldValue.arrayRemove([memberId]),
                  });
                },
                title: Text('إزالة من المسؤولين', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
              ),
            if (canPromoteToModerator)
              ListTile(
                onTap: () async {
                  Navigator.pop(c);
                  await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                    'moderators': FieldValue.arrayUnion([memberId]),
                  });
                },
                title: Text('تعيين كمشرف', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
              ),
            if (canDemoteModerator)
              ListTile(
                onTap: () async {
                  Navigator.pop(c);
                  await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                    'moderators': FieldValue.arrayRemove([memberId]),
                  });
                },
                title: Text('إزالة من الإشراف', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
              ),
            if (canRemove || canPromoteToModerator || canDemoteModerator || canPromoteToAdmin || canDemoteAdmin)...[
              if (isRestricted && canUnrestrict)
                ListTile(
                  onTap: () async {
                    Navigator.pop(c);
                    await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                      'restricted.$memberId': FieldValue.delete(),
                      'restrictedBy.$memberId': FieldValue.delete(),
                    });
                  },
                  title: Text('فك التقييد', style: TextStyle(color: Colors.green, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                  leading: Icon(Icons.lock_open, color: Colors.green),
                )
              else if (!isRestricted)
                ListTile(
                  onTap: () => _showRestrictSheet(memberId),
                  title: Text('تقييد', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
                  leading: Icon(Icons.lock_outline, color: Colors.orange),
                ),
              ListTile(
                onTap: () async {
                  Navigator.pop(c);
                  await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                    'members': FieldValue.arrayRemove([memberId]),
                    'admins': FieldValue.arrayRemove([memberId]),
                    'moderators': FieldValue.arrayRemove([memberId]),
                    'banned': FieldValue.arrayUnion([memberId]),
                  });
                },
                title: Text('حظر من المجموعة', style: TextStyle(color: kErrorRed, fontFamily: 'Tajawal')),
              ),
              Divider(color: Colors.white12, height: 1),
            ],
            // الإبلاغ يظهر للكل (عضو ومسؤول ومشرف)
            ListTile(
              onTap: () => Navigator.pop(c),
              title: Text('الإبلاغ عن دردشة', style: TextStyle(color: kErrorRed, fontFamily: 'Tajawal')),
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kBg,
          elevation: 0,
          leading: IconButton(icon: Icon(Icons.arrow_forward, color: Colors.white), onPressed: () => Navigator.pop(context)),
          title: Text('الأشخاص', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
          centerTitle: true,
          actions: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return SizedBox();
                final data = snap.data!.data() as Map<String, dynamic>? ?? {};
                final createdBy = data['createdBy'] ?? '';
                final admins = List<String>.from(data['admins'] ?? []);
                final moderators = List<String>.from(data['moderators'] ?? []);
                final bool isOwner = createdBy == myUid;
                final bool isAdmin = admins.contains(myUid);
                final bool isModerator = moderators.contains(myUid);
                final bool canAdd = isOwner || isAdmin || isModerator;
                if (!canAdd) return SizedBox();
                return IconButton(
                  icon: Icon(Icons.person_add_alt_1, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupCreateDetailsScreen(groupId: widget.groupId),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).snapshots(),
          builder: (context, groupSnap) {
            if (!groupSnap.hasData) return Center(child: CircularProgressIndicator());
            final groupData = groupSnap.data!.data() as Map<String, dynamic>;
            final members = List<String>.from(groupData['members']?? []);
            final admins = List<String>.from(groupData['admins']?? []);
            final moderators = List<String>.from(groupData['moderators']?? []);
            final createdBy = groupData['createdBy']?? '';
            final restricted = Map<String, dynamic>.from(groupData['restricted']?? {});
            final restrictedBy = Map<String, dynamic>.from(groupData['restrictedBy']?? {});
            final bool isCurrentUserOwner = createdBy == myUid;
            final bool isCurrentUserAdmin = admins.contains(myUid) || isCurrentUserOwner;
            final bool isCurrentUserModerator = moderators.contains(myUid);

            return ListView(
              children: [
                // يلزم الموافقة للانضمام
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: kBg,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Switch(
                        value: _requireApproval,
                        onChanged: (v) => setState(() => _requireApproval = v),
                        activeColor: Colors.white,
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: kFieldFill,
                      ),
                      Text('يلزم الموافقة للانضمام', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15)),
                    ],
                  ),
                ),
                SizedBox(height: 8),
                // أنت
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('أنت', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                // كارد الحالي - أنت - مصلح
                FutureBuilder<DocumentSnapshot>(
                  future: UserDocuments.readable(FirebaseFirestore.instance, myUid).get(),
                  builder: (c, snap) {
                    if (!snap.hasData) return SizedBox();
                    final u = snap.data!.data() as Map<String, dynamic>?;
                    return ListTile(
                      trailing: CircleAvatar(radius: 26, backgroundImage: NetworkImage(u?['profileImg']?? ''), backgroundColor: kFieldFill),
                      title: Text(u?['fullName']?? u?['username']?? 'Dilêmin', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                      subtitle: Text(_getRole(myUid, createdBy, admins, moderators), style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 13)),
                    );
                  },
                ),
                SizedBox(height: 16),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('أتابع (${members.length > 1? members.length - 1 : members.length})', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                ),
                SizedBox(height: 8),
                // لستة الأعضاء
         ...members.where((id) => id!= myUid).map((mId) {
                  return FutureBuilder<DocumentSnapshot>(
                    future: UserDocuments.readable(FirebaseFirestore.instance, mId).get(),
                    builder: (c, uSnap) {
                      if (!uSnap.hasData) return SizedBox();
                      final u = uSnap.data!.data() as Map<String, dynamic>?;
                      final fullName = u?['fullName']?? u?['username']?? '';
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            // زر أتابع على اليسار - حي
                            StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseFirestore.instance.collection('users').doc(myUid).collection('following').doc(mId).snapshots(),
                              builder: (c, fSnap) {
                                final isFollowing = fSnap.hasData && fSnap.data!.exists;
                                return Container(
                                  width: 110,
                                  height: 38,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isFollowing ? Colors.teal : kSurface,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      elevation: 0,
                                      side: isFollowing ? BorderSide.none : BorderSide(color: Colors.white24),
                                    ),
                                    onPressed: () async {
                                      await Provider.of<custom.AuthProvider>(context, listen: false).toggleFollow(mId);
                                    },
                                    child: Text(isFollowing ? 'تتابعه' : 'متابعة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 14, fontWeight: FontWeight.bold)),
                                  ),
                                );
                              },
                            ),
                            SizedBox(width: 12),
                            // 3 نقاط
                            IconButton(
                              icon: Icon(Icons.more_vert, color: Colors.white),
                              onPressed: () => _showMemberSheet(
                                uSnap.data!,
                                isCurrentUserAdmin,
                                mId,
                                admins,
                                createdBy: createdBy,
                                moderators: moderators,
                                isCurrentUserOwner: isCurrentUserOwner,
                                isCurrentUserModerator: isCurrentUserModerator,
                                myUid: myUid,
                                restricted: restricted,
                                restrictedBy: restrictedBy,
                              ),
                            ),
                            Spacer(),
                            // الاسم واليوزر
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(fullName, style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(_getRole(mId, createdBy, admins, moderators) + (restricted.containsKey(mId)? ' • مقيد' : ''), style: TextStyle(color: restricted.containsKey(mId)? Colors.orange : Colors.white54, fontFamily: 'Tajawal', fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            SizedBox(width: 10),
                            // الصورة على اليمين - تفتح الشيت
                            GestureDetector(
                              onTap: () {
                                UserProfileSheet.show(
                                  context,
                                  fullName: u?['fullName']?? '',
                                  username: u?['username']?? '',
                                  profileImg: u?['profileImg']?? '',
                                  uid: mId,
                                  isFollowing: false,
                                  onFollowTap: () {},
                                );
                              },
                              child: CircleAvatar(radius: 26, backgroundImage: NetworkImage(u?['profileImg']?? ''), backgroundColor: kFieldFill),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }),
                SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }
}