import 'user_documents.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
import 'chat_provider.dart';
import 'tini_messaging_notice.dart';
import 'user_model.dart';
import 'share_search_sheet.dart';
import 'block_service.dart'; // [إضافة جديدة] منطق الحظر المنفصل

ChatFailureReason _shareErrorReason(Object error) {
  return error is FirebaseException && error.code == 'permission-denied'
      ? ChatFailureReason.permissionDenied
      : ChatFailureReason.technicalError;
}

class ShareProfileSheet extends StatefulWidget {
  final String? profileUserId;
  final bool showBlockButton;
  final BuildContext? rootContext;
  const ShareProfileSheet({super.key, this.profileUserId, this.showBlockButton = false, this.rootContext});

  @override
  State<ShareProfileSheet> createState() => _ShareProfileSheetState();
}

class _ShareProfileSheetState extends State<ShareProfileSheet> {
  final ValueNotifier<Set<String>> selectedNotifier = ValueNotifier({});
  bool _sharingInProgress = false;
  List<String>? _cachedFriendIds;
  Future<List<UserModel>>? _usersFuture;
  List<UserModel> _allUsersCache = [];

  @override
  void dispose() {
    selectedNotifier.dispose();
    super.dispose();
  }

  Future<List<UserModel>> _fetchUsersInBatches(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    final List<UserModel> result = [];
    for (var i = 0; i < userIds.length; i += 10) {
      final chunk = userIds.sublist(i, i + 10 > userIds.length ? userIds.length : i + 10);
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

    // نقرأ معلومات البروفايل قبل إغلاق النافذة؛ إذا فشلت القراءة لا نبدأ الإرسال.
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
    final cacheMap = <String, UserModel>{for (final user in _allUsersCache) user.uid: user};

    Navigator.pop(context);

    // كل مستلم يرجع نتيجته بنفسه: null = نجاح، وغير ذلك = سبب فشل محدد.
    // Future.wait يحافظ على نتائج المستلمين بالتوازي دون متغيرات حالة مشتركة.
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
        debugPrint('Error sending profile share to $friendUid: $error');
        return _shareErrorReason(error);
      }
    }));

    TiniMessagingNotice.showShareOutcome(messenger, results);
  }

  @override
  Widget build(BuildContext context) {
    const Color surfaceColor = Color(0xFF1A222C);
    const Color fieldFillColor = Color(0xFF1C1C1E);
    
    final String myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final String targetProfileId = widget.profileUserId ?? myUid;
    final String profileLink = "https://titistar.app/user/$targetProfileId";

    void copyLink() async {
      await Clipboard.setData(ClipboardData(text: profileLink));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم نسخ الرابط")));
      }
    }

    Future<void> shareWhatsApp() async {
      final uri = Uri.parse("https://wa.me/?text=${Uri.encodeComponent(profileLink)}");
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    Future<void> shareTelegram() async {
      final uri = Uri.parse("https://t.me/share/url?url=${Uri.encodeComponent(profileLink)}");
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    Future<void> shareFacebook() async {
      final uri = Uri.parse("https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(profileLink)}");
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    Future<void> shareMessenger() async {
      final uri = Uri.parse("fb-messenger://share?link=${Uri.encodeComponent(profileLink)}");
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final fallback = Uri.parse("https://www.facebook.com/dialog/send?link=${Uri.encodeComponent(profileLink)}&app_id=123456789&display=popup");
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
      }
    }

    Future<void> shareX() async {
      final uri = Uri.parse("https://twitter.com/intent/tweet?url=${Uri.encodeComponent(profileLink)}");
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    Future<void> shareSMS() async {
      final uri = Uri.parse("sms:?body=${Uri.encodeComponent(profileLink)}");
      await launchUrl(uri);
    }

    Future<void> shareEmail() async {
      final uri = Uri.parse("mailto:?body=${Uri.encodeComponent(profileLink)}");
      await launchUrl(uri);
    }

    return Container(
      decoration: const BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.white54, size: 22)),
                const Text("إرسال إلى", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => ShareSearchSheet(profileUserId: widget.profileUserId),
                    );
                  },
                  child: const Icon(Icons.search, color: Colors.white54, size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 100,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(myUid).collection('following').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("لا يوجد أصدقاء بعد", style: TextStyle(color: Colors.white54, fontSize: 12)));
                }
                final friendIds = snapshot.data!.docs.map((d) => d.id).toList();
                if (_cachedFriendIds == null || _cachedFriendIds!.length != friendIds.length) {
                  _cachedFriendIds = friendIds;
                  _usersFuture = _fetchUsersInBatches(friendIds);
                }
                return FutureBuilder<List<UserModel>>(
                  future: _usersFuture,
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 2));
                    }
                    if (!userSnapshot.hasData || userSnapshot.data!.isEmpty) {
                      return const Center(child: Text("لا يوجد أصدقاء بعد", style: TextStyle(color: Colors.white54, fontSize: 12)));
                    }
                    final users = userSnapshot.data!;
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (context, index) {
                        final userModel = users[index];
                        return ValueListenableBuilder<Set<String>>(
                          valueListenable: selectedNotifier,
                          builder: (context, selected, _) {
                            final isSelected = selected.contains(userModel.uid);
                            return GestureDetector(
                              onTap: () {
                                final newSet = Set<String>.from(selected);
                                if (isSelected) newSet.remove(userModel.uid);
                                else newSet.add(userModel.uid);
                                selectedNotifier.value = newSet;
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: isSelected ? Border.all(color: Colors.teal, width: 2.5) : null,
                                        ),
                                        child: CircleAvatar(
                                          radius: 30,
                                          backgroundColor: fieldFillColor,
                                          backgroundImage: userModel.profileImg != null && userModel.profileImg!.isNotEmpty
                                              ? CachedNetworkImageProvider(userModel.profileImg!)
                                              : null,
                                          child: (userModel.profileImg == null || userModel.profileImg!.isEmpty)
                                              ? const Icon(Iconsax.user, color: Colors.white70)
                                              : null,
                                        ),
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                                            child: const Icon(Icons.check, color: Colors.white, size: 12),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      userModel.fullName.split(' ').first,
                                      style: TextStyle(color: isSelected ? Colors.teal : Colors.white70, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
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
          const SizedBox(height: 12),
          ValueListenableBuilder<Set<String>>(
            valueListenable: selectedNotifier,
            builder: (context, selected, _) {
              return AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: selected.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: sendToSelectedFriends,
                            child: Text("إرسال إلى ${selected.length} صديق", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ),
              );
            },
          ),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 18),
          SizedBox(
            height: 85,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildRealAppItem(iconWidget: const Icon(Iconsax.link_1, color: Colors.white, size: 24), label: "نسخ الرابط", bgColor: const Color(0xFF2A3441), onTap: copyLink),
                _buildRealAppItem(iconWidget: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 26), label: "WhatsApp", bgColor: const Color(0xFF25D366), onTap: shareWhatsApp),
                _buildRealAppItem(iconWidget: const FaIcon(FontAwesomeIcons.facebookF, color: Colors.white, size: 24), label: "Facebook", bgColor: const Color(0xFF1877F2), onTap: shareFacebook),
                _buildRealAppItem(iconWidget: const FaIcon(FontAwesomeIcons.facebookMessenger, color: Colors.white, size: 26), label: "Messenger", bgColor: const Color(0xFF0084FF), onTap: shareMessenger),
                _buildRealAppItem(iconWidget: const FaIcon(FontAwesomeIcons.telegram, color: Colors.white, size: 24), label: "Telegram", bgColor: const Color(0xFF26A5E4), onTap: shareTelegram),
                _buildRealAppItem(iconWidget: const FaIcon(FontAwesomeIcons.xTwitter, color: Colors.white, size: 22), label: "X", bgColor: Colors.black, onTap: shareX),
                _buildRealAppItem(iconWidget: const FaIcon(FontAwesomeIcons.commentSms, color: Colors.white, size: 22), label: "SMS", bgColor: const Color(0xFF34B7F1), onTap: shareSMS),
                _buildRealAppItem(iconWidget: const FaIcon(FontAwesomeIcons.envelope, color: Colors.white, size: 22), label: "Email", bgColor: const Color(0xFFEA4335), onTap: shareEmail),
              ],
            ),
          ),
          if (widget.showBlockButton && targetProfileId != myUid) ...[
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 18),
            SizedBox(
              height: 85,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildRealAppItem(
                    iconWidget: const Icon(Icons.block, color: Colors.white, size: 24),
                    label: "حظر",
                    bgColor: const Color(0xFF2A3441),
                    onTap: () async {
                      final String targetToBlock = targetProfileId;
                      final BuildContext? parentCtx = widget.rootContext;
                      final BuildContext sheetCtx = context;
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      await Future.delayed(const Duration(milliseconds: 350));
                      if (parentCtx != null && parentCtx.mounted) {
                        await BlockService.blockUser(parentCtx, targetToBlock);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRealAppItem({required Widget iconWidget, required String label, required Color bgColor, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 4),
        child: Column(
          children: [
            Container(width: 54, height: 54, decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle), child: Center(child: iconWidget)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}