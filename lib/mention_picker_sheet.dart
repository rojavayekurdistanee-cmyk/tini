// [Tini] ملف mention_picker_sheet.dart - ملف مستقل لاختيار المستخدمين للمنشن
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom; // [المركز]
import 'block_service.dart'; // [المركز]
import 'mention_privacy_service.dart';

class MentionPickerSheet extends StatefulWidget {
  final List<String> alreadySelected;

  const MentionPickerSheet({
    Key? key,
    this.alreadySelected = const [],
  }) : super(key: key);

  @override
  _MentionPickerSheetState createState() => _MentionPickerSheetState();
}

class _MentionPickerSheetState extends State<MentionPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _selectedUsers = [];
  String _searchQuery = "";

  final Color titiTeal = const Color(0xFF009688);
  final Color bgDark = const Color(0xFF0F1720);
  final Color surfaceDark = const Color(0xFF1A222C);

  @override
  void initState() {
    super.initState();
    _selectedUsers = List.from(widget.alreadySelected);
  }

  // [Tini - Mention Privacy]: لا تعيد أسماء لا تسمح إعداداتها بالذِكر.
  Future<void> _finishSelection() async {
    try {
      await MentionPrivacyService.validateMentions(selected: _selectedUsers);
      if (mounted) Navigator.pop(context, _selectedUsers);
    } on MentionNotAllowedException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFFE53935)),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر التحقق من خصوصية الذكر. حاول مجدداً.'),
          backgroundColor: Color(0xFFE53935)),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUsersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final docs = await Future.wait(
      ids.map((id) => FirebaseFirestore.instance.collection('users').doc(id).get()),
    );
    final users = docs.where((d) => d.exists).map((d) => {'uid': d.id,...d.data() as Map<String, dynamic>}).toList();
    return MentionPrivacyService.filterMentionableUsers(users);
  }

  Stream<List<Map<String, dynamic>>> _friendsStream() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid?? "";
    if (currentUid.isEmpty) return Stream.value([]);
    return FirebaseFirestore.instance
       .collection('users')
       .doc(currentUid)
       .collection('following')
       .snapshots()
       .asyncMap((followingSnap) async {
      if (followingSnap.docs.isEmpty) return [];
      final followingIds = followingSnap.docs.map((d) => d.id).toSet();

      final followersSnap = await FirebaseFirestore.instance
         .collection('users')
         .doc(currentUid)
         .collection('followers')
         .get();

      final followersIds = followersSnap.docs.map((d) => d.id).toSet();
      final mutual = followingIds.intersection(followersIds).toList();
      return _fetchUsersByIds(mutual);
    });
  }

  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];

    final usernameSnap = await FirebaseFirestore.instance
       .collection('users')
       .where('username_lowercase', isGreaterThanOrEqualTo: q)
       .where('username_lowercase', isLessThan: q + '\uf8ff')
       .limit(20)
       .get();

    final fullNameSnap = await FirebaseFirestore.instance
       .collection('users')
       .where('fullName_lowercase', isGreaterThanOrEqualTo: q)
       .where('fullName_lowercase', isLessThan: q + '\uf8ff')
       .limit(20)
       .get();

    final Map<String, Map<String, dynamic>> merged = {};
    for (var d in usernameSnap.docs) {
      merged[d.id] = {'uid': d.id,...d.data() as Map<String, dynamic>};
    }
    for (var d in fullNameSnap.docs) {
      merged[d.id] = {'uid': d.id,...d.data() as Map<String, dynamic>};
    }

    return MentionPrivacyService.filterMentionableUsers(merged.values.toList());
  }

  @override
  Widget build(BuildContext context) {
    final blockedSet = Provider.of<custom.AuthProvider>(context).blockedUsersSet; // [المركز Set]
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: bgDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 5),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _finishSelection,
                  child: Text("تم", style: TextStyle(color: titiTeal, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const Text("منشن أشخاص", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء", style: TextStyle(color: Colors.white54, fontSize: 14)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: surfaceDark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: "بحث عن مستخدم...",
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: Colors.white38),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
          ),
          Expanded(
            child: _searchQuery.isEmpty
               ? StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _friendsStream(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: titiTeal));
                      final rawDocs = snapshot.data!;
                      final docs = BlockService.filterBlockedMaps(rawDocs, blockedSet); // [HARD BLOCK - مركزي]
                      if (docs.isEmpty) {
                        return const Center(child: Text("لا يوجد أصدقاء بعد - الأصدقاء هم متابعة متبادلة", style: TextStyle(color: Colors.white54)));
                      }
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final userData = docs[index];
                          final String username = userData['username']?? "";
                          final String fullName = userData['fullName']?? "";
                          final String profileImg = userData['profileImg']?? "";
                          final bool isSelected = _selectedUsers.contains(username);

                          return ListTile(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedUsers.remove(username);
                                } else {
                                  _selectedUsers.add(username);
                                }
                              });
                            },
                                                        leading: profileImg.isNotEmpty
                             ? CachedNetworkImage(
                                  imageUrl: profileImg,
                                  cacheKey: profileImg,
                                  imageBuilder: (c, p) => CircleAvatar(backgroundColor: surfaceDark, backgroundImage: p),
                                  placeholder: (c, u) => CircleAvatar(backgroundColor: surfaceDark),
                                  errorWidget: (c, u, e) => CircleAvatar(backgroundColor: surfaceDark, child: const Icon(Icons.person, color: Colors.white54)),
                                )
                              : CircleAvatar(backgroundColor: surfaceDark, child: const Icon(Icons.person, color: Colors.white54)),
                            title: Text(fullName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            subtitle: Text("@$username", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            trailing: Icon(
                              isSelected? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isSelected? titiTeal : Colors.white24,
                            ),
                          );
                        },
                      );
                    },
                  )
                : FutureBuilder<List<Map<String, dynamic>>>(
                    future: _searchUsers(_searchQuery),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: titiTeal));
                      final rawDocs = snapshot.data!;
                      final docs = BlockService.filterBlockedMaps(rawDocs, blockedSet); // [HARD BLOCK - مركزي]
                      if (docs.isEmpty) {
                        return const Center(child: Text("لا توجد نتائج", style: TextStyle(color: Colors.white54)));
                      }
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final userData = docs[index];
                          final String username = userData['username']?? "";
                          final String fullName = userData['fullName']?? "";
                          final String profileImg = userData['profileImg']?? "";
                          final bool isSelected = _selectedUsers.contains(username);

                          return ListTile(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedUsers.remove(username);
                                } else {
                                  _selectedUsers.add(username);
                                }
                              });
                            },
                                                        leading: profileImg.isNotEmpty
                             ? CachedNetworkImage(
                                  imageUrl: profileImg,
                                  cacheKey: profileImg,
                                  imageBuilder: (c, p) => CircleAvatar(backgroundColor: surfaceDark, backgroundImage: p),
                                  placeholder: (c, u) => CircleAvatar(backgroundColor: surfaceDark),
                                  errorWidget: (c, u, e) => CircleAvatar(backgroundColor: surfaceDark, child: const Icon(Icons.person, color: Colors.white54)),
                                )
                              : CircleAvatar(backgroundColor: surfaceDark, child: const Icon(Icons.person, color: Colors.white54)),
                            title: Text(fullName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            subtitle: Text("@$username", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            trailing: Icon(
                              isSelected? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isSelected? titiTeal : Colors.white24,
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}