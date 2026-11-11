import 'user_documents.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
import 'chat_provider.dart';
import 'tini_messaging_notice.dart';
import 'user_model.dart';

ChatFailureReason _shareErrorReason(Object error) {
  return error is FirebaseException && error.code == 'permission-denied'
      ? ChatFailureReason.permissionDenied
      : ChatFailureReason.technicalError;
}

class ShareSearchSheet extends StatefulWidget {
  final String? profileUserId;
  const ShareSearchSheet({super.key, this.profileUserId});

  @override
  State<ShareSearchSheet> createState() => _ShareSearchSheetState();
}

class _ShareSearchSheetState extends State<ShareSearchSheet> {
  final TextEditingController searchController = TextEditingController();
  final ValueNotifier<Set<String>> selectedNotifier = ValueNotifier({});
  bool _sharingInProgress = false;
  final ValueNotifier<String> searchNotifier = ValueNotifier('');

  List<String>? _cachedFriendIds;
  Future<List<UserModel>>? _usersFuture;
  List<UserModel> _allUsersCache = [];

  @override
  void initState() {
    super.initState();
    searchController.addListener(() {
      searchNotifier.value = searchController.text.toLowerCase().trim();
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    selectedNotifier.dispose();
    searchNotifier.dispose();
    super.dispose();
  }

  Future<List<UserModel>> _fetchUsersInBatches(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    final List<UserModel> result = [];
    for (var i = 0; i < userIds.length; i += 10) {
      final chunk = userIds.sublist(i, i + 10 > userIds.length? userIds.length : i + 10);
      final query = await FirebaseFirestore.instance.collection('public_profiles').where(FieldPath.documentId, whereIn: chunk).get();
      result.addAll(query.docs.map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;
        return UserModel.fromJson(data);
      }));
    }
    _allUsersCache = result;
    return result;
  }

  Future<void> sendToSelectedFriends() async {
    if (_sharingInProgress) return;
    final selected = Set<String>.from(selectedNotifier.value);
    if (selected.isEmpty) return;
    _sharingInProgress = true;

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final targetProfileId = widget.profileUserId ?? myUid;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);
    // نخزن مرجع الإشعارات قبل أي await لأن الشيت قد يُغلق أثناء تحميل البيانات.
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (myUid.isEmpty || targetProfileId.isEmpty) {
      TiniMessagingNotice.showShareOutcome(messenger,
          List<ChatFailureReason?>.filled(selected.length, ChatFailureReason.notAuthenticated));
      _sharingInProgress = false;
      return;
    }

    // خذ بيانات البروفايل قبل ما تسكر
    late final String targetName;
    late final String targetImg;
    late final String targetUsername;
    try {
      final targetUserDoc = await UserDocuments.readable(FirebaseFirestore.instance, targetProfileId).get();
      final targetData = targetUserDoc.data() ?? <String, dynamic>{};
      targetName = (targetData['fullName'] ?? authProvider.fullName).toString();
      targetImg = (targetData['profileImg'] ?? authProvider.profileImg).toString();
      targetUsername = (targetData['username'] ?? authProvider.username).toString();
    } catch (error) {
      debugPrint('Error reading shared profile: $error');
      TiniMessagingNotice.showShareOutcome(messenger,
          List<ChatFailureReason?>.filled(selected.length, _shareErrorReason(error)));
      _sharingInProgress = false;
      return;
    }
    if (!mounted) return;
    final profileLink = 'https://titistar.app/user/$targetProfileId';

    // ماب للكاش عشان ما نجيب بيانات مرة تانية
    final cacheMap = <String, UserModel>{for (final user in _allUsersCache) user.uid: user};

    // 1. سكر فوراً - أهم خطوة
    Navigator.pop(context);

    // 2. الارسال بالخلفية وبالمتوازي
    final results = await Future.wait<ChatFailureReason?>(selected.map((friendUid) async {
      if (FirebaseAuth.instance.currentUser?.uid != myUid) return ChatFailureReason.notAuthenticated;
      try {
        final cachedUser = cacheMap[friendUid];
        final isFriend = await chatProvider.checkIfFriend(myUid, friendUid);
        if (FirebaseAuth.instance.currentUser?.uid != myUid) return ChatFailureReason.notAuthenticated;
        final opened = await chatProvider.startChatWithReason(
          viewedUid: friendUid,
          displayFullName: cachedUser?.fullName ?? 'صديق',
          displayProfileImg: cachedUser?.profileImg ?? '',
          isFriend: isFriend,
        );
        final roomId = opened.value;
        if (!opened.isSuccess || roomId == null || roomId.isEmpty) {
          return opened.failureReason ?? ChatFailureReason.technicalError;
        }
        if (FirebaseAuth.instance.currentUser?.uid != myUid) return ChatFailureReason.notAuthenticated;

        // مسار المراسلة الموحد يتحقق من السماح والخصوصية وحد الرسالة الأولى.
        // لا نكتب رسالة مباشرة إلى Firestore كي لا نتجاوز canSendMore.
        final sent = await chatProvider.sendMessageWithReason(
          roomId: roomId,
          senderId: myUid,
          receiverId: friendUid,
          type: 'profile_share',
          text: profileLink,
          isFriend: isFriend,
          extraData: {
            'receiverId': friendUid,
            'profileUid': targetProfileId,
            'profileName': targetName,
            'profileUsername': targetUsername,
            'profileImg': targetImg,
            'profileLink': profileLink,
          },
        );
        return sent.isSuccess && sent.value == true
            ? null
            : sent.failureReason ?? ChatFailureReason.technicalError;
      } catch (error) {
        debugPrint('Error sending search share to $friendUid: $error');
        return _shareErrorReason(error);
      }
    }));

    TiniMessagingNotice.showShareOutcome(messenger, results);
  }

  @override
  Widget build(BuildContext context) {
    const Color surfaceColor = Color(0xFF1A222C);
    const Color fieldFillColor = Color(0xFF2C2C2E);
    final String myUid = FirebaseAuth.instance.currentUser?.uid?? '';

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.white, size: 24)),
                const Text("إرسال إلى", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(width: 24),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(color: fieldFillColor, borderRadius: BorderRadius.circular(12)),
              child: TextField(
                controller: searchController,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: "بحث",
                  hintStyle: TextStyle(color: Colors.white54),
                  prefixIcon: Icon(Icons.search, color: Colors.white54),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text("أحدث دردشة", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(myUid).collection('following').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.teal));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("لا يوجد أصدقاء بعد", style: TextStyle(color: Colors.white54)));
                }

                final friendIds = snapshot.data!.docs.map((d) => d.id).toList();
                if (_cachedFriendIds == null || _cachedFriendIds!.length!= friendIds.length) {
                  _cachedFriendIds = friendIds;
                  _usersFuture = _fetchUsersInBatches(friendIds);
                }

                return FutureBuilder<List<UserModel>>(
                  future: _usersFuture,
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.teal));
                    }
                    if (!userSnapshot.hasData || userSnapshot.data!.isEmpty) {
                      return const Center(child: Text("لا يوجد أصدقاء بعد", style: TextStyle(color: Colors.white54)));
                    }

                    return ValueListenableBuilder<String>(
                      valueListenable: searchNotifier,
                      builder: (context, query, _) {
                        var users = userSnapshot.data!;
                        if (query.isNotEmpty) {
                          users = users.where((u) => u.fullName.toLowerCase().contains(query) || u.username.toLowerCase().contains(query)).toList();
                        }
                        if (users.isEmpty) return const Center(child: Text("لا يوجد نتائج", style: TextStyle(color: Colors.white54)));

                        return ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: users.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (context, index) {
                            final user = users[index];
                            return ValueListenableBuilder<Set<String>>(
                              valueListenable: selectedNotifier,
                              builder: (context, selected, _) {
                                final isSelected = selected.contains(user.uid);
                                return ListTile(
                                  key: ValueKey(user.uid),
                                  onTap: () {
                                    final newSet = Set<String>.from(selected);
                                    if (isSelected) newSet.remove(user.uid);
                                    else newSet.add(user.uid);
                                    selectedNotifier.value = newSet;
                                  },
                                  leading: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: isSelected? Colors.teal : Colors.white38, width: 2),
                                      color: isSelected? Colors.teal : Colors.transparent,
                                    ),
                                    child: isSelected? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                                  ),
                                  trailing: CircleAvatar(
                                    radius: 28,
                                    backgroundColor: const Color(0xFF1C1C1E),
                                    backgroundImage: (user.profileImg!= null && user.profileImg!.isNotEmpty)? CachedNetworkImageProvider(user.profileImg!) : null,
                                    child: (user.profileImg == null || user.profileImg!.isEmpty)? Text(user.fullName.isNotEmpty? user.fullName[0].toUpperCase() : "B", style: const TextStyle(color: Colors.white, fontSize: 20)) : null,
                                  ),
                                  title: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Flexible(child: Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
                                      const SizedBox(width: 6),
                                      const Text("· الأصدقاء", style: TextStyle(color: Colors.white54, fontSize: 12)),
                                    ],
                                  ),
                                  subtitle: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(user.username, style: const TextStyle(color: Colors.white54, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          ValueListenableBuilder<Set<String>>(
            valueListenable: selectedNotifier,
            builder: (context, selected, _) {
              return AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: selected.isEmpty
                   ? const SizedBox(height: 0, width: double.infinity)
                    : Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            onPressed: sendToSelectedFriends,
                            child: Text("إرسال إلى ${selected.length} صديق", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}