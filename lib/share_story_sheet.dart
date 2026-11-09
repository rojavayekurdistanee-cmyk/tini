import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'audience_message_gate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:provider/provider.dart';
import 'chat_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

void _showTiniShareOutcome(
  ScaffoldMessengerState? messenger,
  List<ChatFailureReason?> results, {
  String itemLabel = 'المشاركة',
}) {
  if (messenger == null || !messenger.mounted || results.isEmpty) return;

  final failureCounts = <ChatFailureReason, int>{};
  for (final reason in results) {
    if (reason != null) {
      failureCounts.update(reason, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  final successful = results.length - failureCounts.values.fold<int>(0, (sum, count) => sum + count);
  final failed = results.length - successful;
  final title = failed == 0
      ? 'تمت المشاركة مع $successful'
      : successful > 0
          ? 'تمت المشاركة مع $successful من أصل ${results.length}، وفشل $failed'
          : 'تعذّر إرسال $itemLabel إلى $failed';

  final details = failureCounts.entries.toList();
  final reasonText = details.isEmpty
      ? ''
      : details.length == 1
          ? details.first.key.userMessage
          : [
              ...details.take(2).map((entry) => '${entry.value}: ${entry.key.userMessage}'),
              if (details.length > 2) 'وأسباب أخرى لدى ${details.skip(2).fold<int>(0, (sum, entry) => sum + entry.value)} حسابات.',
            ].join('\n');
  final hasTechnicalError = failureCounts.keys.any((reason) => !reason.isPrivacyRestriction);
  final iconColor = failed == 0
      ? Colors.teal
      : hasTechnicalError
          ? const Color(0xFFE53935)
          : Colors.white54;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: const Color(0xFF1A222C),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    duration: Duration(seconds: failed == 0 ? 3 : 5),
    content: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          failed == 0 ? Icons.check_circle_outline : hasTechnicalError ? Icons.error_outline : Icons.info_outline,
          color: iconColor,
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              if (reasonText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(reasonText, style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 5, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ],
    ),
  ));
}

ChatFailureReason _shareErrorReason(Object error) {
  return error is FirebaseException && error.code == 'permission-denied'
      ? ChatFailureReason.permissionDenied
      : ChatFailureReason.technicalError;
}

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
    final selected = Set<String>.from(selectedIds);
    if (selected.isEmpty) return;

    final provider = Provider.of<ChatProvider>(context, listen: false);
    final story = widget.story;
    final uid = widget.currentUid;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final users = <String, UserModel>{for (final user in mutuals) user.uid: user};
    Navigator.pop(context); // سكر الشيت أول

    final results = <ChatFailureReason?>[];
    for (final targetUid in selected) {
      // منع استمرار مشاركة القصة إذا تغير الحساب أو صلاحية مشاهدتها أثناء الإرسال.
      final accountChanged = FirebaseAuth.instance.currentUser?.uid != uid;
      if (accountChanged || !AudienceMessagePolicy.canView(story)) {
        final reason = accountChanged ? ChatFailureReason.notAuthenticated : ChatFailureReason.permissionDenied;
        results.addAll(List<ChatFailureReason?>.filled(selected.length - results.length, reason));
        break;
      }

      try {
        final user = users[targetUid];
        if (user == null) {
          results.add(ChatFailureReason.accountUnavailable);
          continue;
        }
        final isFriend = await provider.checkIfFriend(uid, targetUid);
        if (FirebaseAuth.instance.currentUser?.uid != uid || !AudienceMessagePolicy.canView(story)) {
          results.add(FirebaseAuth.instance.currentUser?.uid != uid
              ? ChatFailureReason.notAuthenticated : ChatFailureReason.permissionDenied);
          continue;
        }
        // نستخدم معرف الغرفة الذي أعادته الدالة بعد فحص صلاحيات المراسلة.
        final opened = await provider.startChatWithReason(
          viewedUid: targetUid,
          displayFullName: user.name,
          displayProfileImg: user.img,
          isFriend: isFriend,
        );
        final roomId = opened.value;
        if (!opened.isSuccess || roomId == null || roomId.isEmpty) {
          results.add(opened.failureReason ?? ChatFailureReason.technicalError);
          continue;
        }
        if (FirebaseAuth.instance.currentUser?.uid != uid || !AudienceMessagePolicy.canView(story)) {
          results.add(FirebaseAuth.instance.currentUser?.uid != uid
              ? ChatFailureReason.notAuthenticated : ChatFailureReason.permissionDenied);
          continue;
        }
        final sent = await provider.sendMessageWithReason(
          roomId: roomId,
          senderId: uid,
          receiverId: targetUid,
          type: story['type'] == 'video' ? 'video' : 'image',
          text: '',
          mediaUrl: story['mediaUrl'],
          extraData: AudienceMessagePolicy.sourceFields(story),
          isFriend: isFriend,
        );
        results.add(sent.isSuccess && sent.value == true
            ? null
            : sent.failureReason ?? ChatFailureReason.technicalError);
      } catch (error) {
        debugPrint('Error sharing story to $targetUid: $error');
        results.add(_shareErrorReason(error));
      }
    }

    // لم نعتبر أي عملية ناجحة إلا إذا أكد ChatProvider حفظ الرسالة فعلياً.
    assert(results.length == selected.length);
    await Future.delayed(const Duration(milliseconds: 200));
    _showTiniShareOutcome(messenger, results, itemLabel: 'القصة');
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