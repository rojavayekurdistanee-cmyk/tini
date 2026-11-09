import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'audience_message_gate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'chat_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ألوان Tini
const Color kSurface = Color(0xFF1A222C);
const Color kTeal = Colors.teal;

class UserModel {
  final String uid;
  final String name;
  final String username;
  final String img;
  UserModel({required this.uid, required this.name, required this.username, required this.img});
}

class ShareStorySheet extends StatefulWidget {
  final Map<String, dynamic> story;
  final String currentUid;

  const ShareStorySheet({super.key, required this.story, required this.currentUid});

  @override
  State<ShareStorySheet> createState() => _ShareStorySheetState();
}

class _ShareStorySheetState extends State<ShareStorySheet> {
  List<UserModel> mutuals = [];
  final Set<String> selectedIds = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadMutuals();
  }

  Future<void> _loadMutuals() async {
    final followingSnap = await FirebaseFirestore.instance.collection('users').doc(widget.currentUid).collection('following').get();
    final followersSnap = await FirebaseFirestore.instance.collection('users').doc(widget.currentUid).collection('followers').get();

    final following = followingSnap.docs.map((d) => d.id).toList();
    final followers = followersSnap.docs.map((d) => d.id).toList();
    final mutualIds = following.where((id) => followers.contains(id)).toList();

    // ✅ جيب كل اليوزرز مرة وحدة بدل FutureBuilder
    final users = await Future.wait(
      mutualIds.map((id) => FirebaseFirestore.instance.collection('users').doc(id).get())
    );

    if (!mounted || FirebaseAuth.instance.currentUser?.uid != widget.currentUid) return;
    setState(() {
      mutuals = users.map((doc) {
        final u = doc.data()?? {};
        return UserModel(
          uid: doc.id,
          name: u['fullName']?? u['username']?? 'مستخدم',
          username: u['username']?? '',
          img: u['profileImg']?? '',
        );
      }).toList();
      loading = false;
    });
  }

  Future<void> _send() async {
    if (FirebaseAuth.instance.currentUser?.uid != widget.currentUid ||
        !AudienceMessagePolicy.canView(widget.story)) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final story = widget.story;
    final uid = widget.currentUid;
    final selected = Set<String>.from(selectedIds);
    final messenger = ScaffoldMessenger.maybeOf(context);

    Navigator.pop(context); // سكر الشيت أول
    var sentCount = 0;

    for (String targetUid in selected) {
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          !AudienceMessagePolicy.canView(story)) return;
      try {
        final user = mutuals.firstWhere((u) => u.uid == targetUid);
        // نستخدم معرف الغرفة الذي أعادته الدالة بعد فحص صلاحيات المراسلة.
        final roomId = await provider.startChat(
          viewedUid: targetUid,
          displayFullName: user.name,
          displayProfileImg: user.img,
          isFriend: true,
        );
        if (roomId.isEmpty) continue;
        if (FirebaseAuth.instance.currentUser?.uid != uid ||
            !AudienceMessagePolicy.canView(story)) return;
        final sent = await provider.sendMessage(
          roomId: roomId,
          senderId: uid,
          receiverId: targetUid,
          type: story['type'] == 'video'? 'video' : 'image',
          text: '',
          mediaUrl: story['mediaUrl'],
          extraData: AudienceMessagePolicy.sourceFields(story),
          isFriend: true,
        );
        if (sent) sentCount++;
      } catch (e) {
        debugPrint('Error sharing story to $targetUid: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 200));
    if (messenger != null && messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            sentCount == selected.length
                ? 'تمت المشاركة مع $sentCount'
                : sentCount > 0
                    ? 'تمت المشاركة مع $sentCount من أصل ${selected.length}'
                    : 'تعذر إرسال القصة. تحقق من إعدادات المراسلة',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: sentCount > 0 ? kTeal : const Color(0xFFE53935),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('مشاركة الستوري', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('${selectedIds.length} محدد', style: const TextStyle(color: kTeal)),
                ],
              ),
            ),
            Expanded(
              child: loading
                 ? const Center(child: CircularProgressIndicator(color: kTeal))
                  : mutuals.isEmpty
                     ? const Center(child: Text('لا يوجد متابعون متبادلون', style: TextStyle(color: Colors.white70)))
                      : ListView.builder(
                          itemCount: mutuals.length,
                          itemBuilder: (context, i) {
                            final user = mutuals[i];
                            final isSelected = selectedIds.contains(user.uid);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: kTeal,
                                backgroundImage: user.img.isNotEmpty? CachedNetworkImageProvider(user.img) : null,
                                child: user.img.isEmpty
                                   ? Text(user.name.isNotEmpty? user.name[0].toUpperCase() : '?',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                    : null,
                              ),
                              title: Text(user.name, style: const TextStyle(color: Colors.white)),
                              subtitle: Text('@${user.username}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              trailing: Checkbox(
                                value: isSelected,
                                activeColor: kTeal,
                                checkColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) selectedIds.add(user.uid); else selectedIds.remove(user.uid);
                                  });
                                },
                              ),
                              onTap: () {
                                setState(() {
                                  if (isSelected) selectedIds.remove(user.uid); else selectedIds.add(user.uid);
                                });
                              },
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTeal,
                  disabledBackgroundColor: Colors.white24,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: selectedIds.isEmpty? null : _send,
                child: Text('إرسال إلى ${selectedIds.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}