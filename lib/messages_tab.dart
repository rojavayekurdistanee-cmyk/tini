import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chat_provider.dart';
import 'auth_provider.dart' as custom;
import 'chat_screen.dart';
import 'new_followers_banner.dart';
import 'activity_banner.dart';
import 'stories_bar.dart';
import 'archived_chats_screen.dart';
import 'story_ring.dart'; // [Tini]: جديد عشان دائرة الستوري
import 'block_service.dart';
import 'system_notifications_banner.dart';
import 'group_create_details_screen.dart';
import 'group_chat_screen.dart';
import 'group_chat_provider.dart';
import 'tini_chat_message_pager.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final ScrollController _inboxScrollController = ScrollController();
  bool _isMessageRequestBannerBusy = false;

  Future<void> _handleMessageRequestBannerAction(
    BuildContext context, {
    required bool allow,
  }) async {
    if (_isMessageRequestBannerBusy) return;
    _isMessageRequestBannerBusy = true;
    try {
      final auth = Provider.of<custom.AuthProvider>(context, listen: false);
      final bool saved = allow
          ? await auth.updateMessageRequests(true)
          : await auth.dismissMessageRequestBanner();
      if (!saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر حفظ إعداد طلبات المراسلة. حاول مرة أخرى.'),
            backgroundColor: Color(0xFFE53935),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Tini] Message request banner action failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر حفظ إعداد طلبات المراسلة. حاول مرة أخرى.'),
            backgroundColor: Color(0xFFE53935),
          ),
        );
      }
    } finally {
      _isMessageRequestBannerBusy = false;
    }
  }

  TiniChatMessagePager? _privateRooms;
  TiniChatMessagePager? _groupRooms;
  Listenable? _inboxUpdates;
  Stream<QuerySnapshot>? _archivedRoomsStream;
  String? _pagerUserId;

  @override
  void initState() {
    super.initState();
    _inboxScrollController.addListener(_onInboxScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = Provider.of<custom.AuthProvider>(context).uid;
    if (_pagerUserId == uid) return;
    _privateRooms?.dispose();
    _groupRooms?.dispose();
    _pagerUserId = uid;
    _privateRooms = null;
    _groupRooms = null;
    _inboxUpdates = null;
    _archivedRoomsStream = null;
    if (uid.isEmpty) return;
    _archivedRoomsStream = Provider.of<ChatProvider>(context, listen: false)
        .getArchivedConversations(uid);

    _privateRooms = TiniChatMessagePager(
      query: FirebaseFirestore.instance
          .collection('chat_rooms')
          .where('participants', arrayContains: uid)
          .orderBy('lastMessageTime', descending: true),
      // The extra query keeps old pinned rooms visible even before paging.
      pinnedQuery: FirebaseFirestore.instance.collection('chat_rooms')
          .where('pinned.$uid', isEqualTo: true),
      timestampField: 'lastMessageTime',
      pageSize: 40,
    )..start();
    _groupRooms = TiniChatMessagePager(
      query: FirebaseFirestore.instance
          .collection('group_chats')
          .where('members', arrayContains: uid)
          .orderBy('lastMessageTime', descending: true),
      pinnedQuery: FirebaseFirestore.instance.collection('group_chats')
          .where('pinned.$uid', isEqualTo: true),
      timestampField: 'lastMessageTime',
      pageSize: 40,
    )..start();
    _inboxUpdates = Listenable.merge([_privateRooms!, _groupRooms!]);
  }

  void _loadMoreConversations() {
    final privates = _privateRooms;
    final groups = _groupRooms;
    if (privates != null && privates.hasMore) privates.loadOlder();
    if (groups != null && groups.hasMore) groups.loadOlder();
  }

  void _onInboxScroll() {
    if (_inboxScrollController.hasClients &&
        _inboxScrollController.position.extentAfter < 650) {
      _loadMoreConversations();
    }
  }

  @override
  void dispose() {
    _inboxScrollController.removeListener(_onInboxScroll);
    _inboxScrollController.dispose();
    _privateRooms?.dispose();
    _groupRooms?.dispose();
    super.dispose();
  }
  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('hh:mm a').format(dt);
    }
    return DateFormat('dd/MM').format(dt);
  }

    Future<List<String>> _getGroupMemberPhotos(List<String> memberIds) async {
    if (memberIds.isEmpty) return [];
    final ids = memberIds.length > 10? memberIds.sublist(memberIds.length - 10) : memberIds;
    final snap = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: ids).get();
    List<String> photos = snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      return (data['profileImg']?? '') as String;
    }).where((u) => u.trim().isNotEmpty).toList();
    if (photos.length > 2) photos = photos.sublist(photos.length - 2);
    return photos;
  }

  Widget _buildGroupAvatar(String? groupImage, List<String> memberPhotos) {
    final hasGroupImage = groupImage!= null && groupImage.trim().isNotEmpty;
    if (hasGroupImage) {
      return CircleAvatar(radius: 26, backgroundImage: CachedNetworkImageProvider(groupImage));
    }
    if (memberPhotos.length >= 2) {
      return SizedBox(
        width: 48,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: 0,
              top: 0,
              child: CircleAvatar(radius: 18, backgroundImage: CachedNetworkImageProvider(memberPhotos[0]), backgroundColor: const Color(0xFF1A222C)),
            ),
            Positioned(
              right: 18,
              top: 0,
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF0F1720), width: 2)),
                child: CircleAvatar(radius: 18, backgroundImage: CachedNetworkImageProvider(memberPhotos[1]), backgroundColor: const Color(0xFF1A222C)),
              ),
            ),
          ],
        ),
      );
    }
    if (memberPhotos.isNotEmpty) {
      return CircleAvatar(radius: 26, backgroundImage: CachedNetworkImageProvider(memberPhotos[0]));
    }
    return const CircleAvatar(radius: 26, backgroundColor: Color(0xFF009688), child: Icon(Icons.group, color: Colors.white));
  }

  Future<void> _showChatOptions({
    required BuildContext context,
    required String roomId,
    required String otherUid,
    required String name,
    required bool isPinned,
    required bool isMuted,
  }) async {
    const Color bgDark = Color(0xFF0F1720);
    const Color surfaceCard = Color(0xFF1A222C);
    const Color titiRed = Color(0xFFFF3B30);

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(isPinned? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white),
                title: Text(isPinned? 'إلغاء التثبيت' : 'تثبيت', style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await chatProvider.pinChat(roomId,!isPinned);
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined, color: Colors.white),
                title: const Text('أرشفة', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await chatProvider.archiveChat(roomId, true);
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(content: Text('تمت أرشفة الدردشة'), backgroundColor: Color(0xFF009688)),
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(isMuted? Icons.notifications_active_outlined : Icons.notifications_off_outlined, color: Colors.white),
                title: Text(isMuted? 'إلغاء الكتم' : 'كتم', style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await chatProvider.muteChat(roomId,!isMuted);
                },
              ),
              // [فحص هل محظور - Live مع تحذير قبل إلغاء الحظر]
              Builder(
                builder: (innerContext) {
                  final auth = Provider.of<custom.AuthProvider>(innerContext, listen: false);
                  final bool isBlocked = auth.blockedUsersSet.contains(otherUid) || auth.isBlocked(otherUid);
                  
                  return ListTile(
                    leading: Icon(isBlocked ? Icons.lock_open : Icons.block, color: Colors.white),
                    title: Text(isBlocked ? 'إلغاء الحظر' : 'حظر', style: const TextStyle(color: Colors.white)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await Future.delayed(const Duration(milliseconds: 200));
                      if (isBlocked) {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            backgroundColor: const Color(0xFF1A222C),
                            title: Text('إلغاء حظر $name؟', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            content: Text('هل أنت متأكد من إلغاء حظر $name؟', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext, false),
                                child: const Text('إلغاء', style: TextStyle(color: Color(0xFF9E9E9E))),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext, true),
                                child: const Text('تأكيد', style: TextStyle(color: Color(0xFF009688), fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        await BlockService.unblockUser(otherUid, context: context);
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text('تم إلغاء حظر $name'),
                            backgroundColor: const Color(0xFF009688),
                          ),
                        );
                      } else {
                        await BlockService.blockUser(context, otherUid);
                      }
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.white),
                title: const Text('إبلاغ', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  // TODO: فتح شاشة الإبلاغ
                },
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: titiRed),
                title: const Text('حذف', style: TextStyle(color: titiRed)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final rootContext = context;
                  final confirm = await showDialog<bool>(
                    context: rootContext,
                    builder: (dialogContext) => AlertDialog(
                      backgroundColor: const Color(0xFF1A222C),
                      title: const Text('هل تريد حذف هذه الدردشة؟', style: TextStyle(color: Colors.white)),
                      content: const Text(
                        'لا يمكن التراجع عن هذا الإجراء.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('إلغاء', style: TextStyle(color: Color(0xFF9E9E9E))),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('حذف', style: TextStyle(color: Color(0xFFFF3B30))),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await chatProvider.hideChatRooms([roomId]);
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('تم حذف الدردشة'), backgroundColor: Color(0xFF009688)),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showGroupChatOptions({
  required BuildContext context,
  required String groupId,
  required String groupName,
  required bool isPinned,
  required bool isMuted,
}) async {
  const Color surfaceCard = Color(0xFF1A222C);
  const Color titiRed = Color(0xFFFF3B30);

  final groupProvider = Provider.of<GroupChatProvider>(context, listen: false);
  final scaffoldMessenger = ScaffoldMessenger.of(context);

  showModalBottomSheet(
    context: context,
    backgroundColor: surfaceCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(isPinned? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white),
              title: Text(isPinned? 'إلغاء التثبيت' : 'تثبيت', style: const TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                await groupProvider.pinGroupChat(groupId,!isPinned);
              },
            ),
            ListTile(
              leading: Icon(isMuted? Icons.notifications_active_outlined : Icons.notifications_off_outlined, color: Colors.white),
              title: Text(isMuted? 'إلغاء الكتم' : 'كتم', style: const TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                await groupProvider.muteGroupChat(groupId,!isMuted);
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: titiRed),
              title: const Text('حذف', style: TextStyle(color: titiRed)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  barrierColor: Colors.black54,
                  builder: (dialogContext) => Dialog(
                    backgroundColor: const Color(0xFF2A2A2A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                          child: Column(
                            children: [
                              const Text(
                                'هل تريد إزالة هذه الدردشة من بريدك الوارد؟',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'سيؤدي هذا إلى إزالة الدردشة من بريدك الوارد ومسح سجل الدردشة. لإيقاف تلقي رسائل جديدة من هذه الدردشة، يمكنك مغادرة الدردشة.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        const Divider(color: Colors.white12, height: 1),
                        InkWell(
                          onTap: () => Navigator.pop(dialogContext, true),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: const Text('إزالة', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFFF3B30), fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const Divider(color: Colors.white12, height: 1),
                        InkWell(
                          onTap: () => Navigator.pop(dialogContext, false),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: const Text('إلغاء', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                if (confirm == true) {
                  await groupProvider.hideGroupChats([groupId]);
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(content: Text('تم حذف المجموعة'), backgroundColor: Color(0xFF009688)),
                    );
                  }
                }
              },
            ),
          ],
        ),
      );
    },
  );
}

  // [Tini]: ويدجت الأفاتار الجديد - صورة أو حرف + دائرة ستوري
  Widget _buildAvatarWithStory({
    required String uid,
    required String name,
    required String profileImg,
    required String currentUid,
    double size = 52,
  }) {
    final String initial = name.isNotEmpty? name.trim()[0].toUpperCase() : '?';
    final bool hasImage = profileImg.isNotEmpty && profileImg.startsWith('http');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
      .collection('stories')
      .doc(uid)
      .collection('items')
      .where('expiresAt', isGreaterThan: Timestamp.now())
      .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs?? [];
        final hasStories = docs.isNotEmpty;
        final hasUnviewed = docs.any((d) {
          final viewedBy = List<String>.from(d['viewedBy']?? []);
          return!viewedBy.contains(currentUid);
        });

        if (hasStories) {
          if (hasImage) {
            // عنده صورة + عنده ستوري
            return StoryRing(
              imageUrl: profileImg,
              size: size,
              hasStories: true,
              hasUnviewed: hasUnviewed,
              heroTag: 'messages-tab-$uid',
            );
          } else {
            // أول حرف + دائرة ستوري
            return Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasUnviewed
                ? const SweepGradient(
                        colors: [
                          Color(0xFF00E5FF),
                          Color(0xFF00BFFF),
                          Color(0xFF1E90FF),
                          Color(0xFF00E5FF),
                        ],
                        stops: [0.0, 0.33, 0.66, 1.0],
                      )
                    : null,
                border: hasUnviewed? null : Border.all(color: Colors.grey.shade700, width: 2.5),
              ),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0F1720),
                ),
                child: CircleAvatar(
                  radius: (size - 18) / 2,
                  backgroundColor: const Color(0xFF1A222C),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.35,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }
        } else {
          // ما عنده ستوري
          return Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF0F1720),
            ),
            child: CircleAvatar(
              radius: (size - 18) / 2,
              backgroundColor: const Color(0xFF1A222C),
              backgroundImage: hasImage? CachedNetworkImageProvider(profileImg) : null,
              child:!hasImage
              ? Text(
                      initial,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.35,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color bgDark = Color(0xFF0F1720);
    const Color surfaceCard = Color(0xFF1A222C);
    const Color titiTeal = Color(0xFF009688);
    const Color titiRed = Color(0xFFFF3B30);
    const Color textGrey = Color(0xFF9E9E9E);

    final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);
    final String? currentUid = authProvider.uid;

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.search, color: Colors.white, size: 26),
          onPressed: () {},
        ),
        title: const Text(
          "صندوق الوارد",
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const SizedBox(
              width: 26,
              height: 26,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // الدفتر / الكتاب تحت
                  Icon(Icons.menu_book_outlined, color: Colors.white, size: 26),
                  // القلم فوق الورقة بالنص ومبين
                  Positioned(
                    top: -3,
                    child: Icon(Icons.edit, color: Color(0xFF009688), size: 22),
                  ),
                ],
              ),
            ),
            tooltip: 'دردشة جماعية',
            onPressed: () {
               Navigator.push(context, MaterialPageRoute(builder: (_) =>  GroupCreateDetailsScreen()));
            },
          ),
        ],
      ),
      // [Tini]: الميزة الجديدة - كلشي يتحرك مع بعض متل تيك توك - بدون رمشة للخاص
      body: currentUid == null || currentUid.isEmpty
          ? const Center(child: Text("يرجى تسجيل الدخول", style: TextStyle(color: Colors.white)))
          : AnimatedBuilder(
              animation: _inboxUpdates!,
              builder: (context, _) {
                final privatePager = _privateRooms!;
                final groupPager = _groupRooms!;
                if (!privatePager.initialized || !groupPager.initialized) {
                  return const Center(child: CircularProgressIndicator(color: titiTeal));
                }
                // A failure in one source must not hide the other source.
                if (privatePager.error != null && groupPager.error != null &&
                    privatePager.documents.isEmpty && groupPager.documents.isEmpty) {
                  return const Center(child: Text('تعذر تحميل المحادثات والجروبات',
                      style: TextStyle(color: titiRed, fontSize: 12), textAlign: TextAlign.center));
                }

                final blockedIds = Provider.of<ChatProvider>(context).blockedIds;
                // Preserve the same hidden, archived and blocked-user filters.
                final privateDocs = privatePager.documents.where((doc) {
                  final data = doc.data();
                  final deletedFor = Map<String, dynamic>.from(data['deletedFor'] ?? {});
                  final archivedBy = List<String>.from(data['archivedBy'] ?? []);
                  if (deletedFor[currentUid] == true || archivedBy.contains(currentUid)) return false;
                  final participants = List.from(data['participants'] ?? []);
                  for (final otherId in participants) {
                    if (otherId != currentUid && blockedIds.contains(otherId.toString())) return false;
                  }
                  return true;
                }).toList();
                final groupDocsRaw = groupPager.documents;

                    // [Tini]: فلترة الجروبات المحذوفة - نفس الخاص - إخفاء مو حذف
                    final groupDocs = groupDocsRaw.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final deletedFor = Map<String, dynamic>.from(data['deletedFor'] ?? {});
                      final unreadMap = Map<String, dynamic>.from(data['unreadCount'] ?? {});
                      final unread = (unreadMap[currentUid] ?? 0) as int;
                      if (deletedFor[currentUid] == true && unread == 0) return false;
                      return true;
                    }).toList();

                    // دمج الخاص + الجروبات - [Tini]: حسب وقت التثبيت - آخر تثبيت فوق
                    final allDocs = [...privateDocs,...groupDocs];
                    allDocs.sort((a, b) {
                      final aData = a.data() as Map<String, dynamic>;
                      final bData = b.data() as Map<String, dynamic>;
                      final aPinned = Map<String, dynamic>.from(aData['pinned']?? {})[currentUid]?? false;
                      final bPinned = Map<String, dynamic>.from(bData['pinned']?? {})[currentUid]?? false;
                      if (aPinned &&!bPinned) return -1;
                      if (!aPinned && bPinned) return 1;
                      if (aPinned && bPinned) {
                        final aPinAt = (aData['pinnedAt'] as Map?)?[currentUid] as Timestamp?;
                        final bPinAt = (bData['pinnedAt'] as Map?)?[currentUid] as Timestamp?;
                        if (aPinAt!= null && bPinAt!= null) return bPinAt.compareTo(aPinAt);
                        if (aPinAt!= null) return -1;
                        if (bPinAt!= null) return 1;
                      }
                      final ta = aData['lastMessageTime'] as Timestamp?;
                      final tb = bData['lastMessageTime'] as Timestamp?;
                      if (ta == null) return 1;
                      if (tb == null) return -1;
                      return tb.compareTo(ta);
                    });

                    // Filtered results may be entirely archived or hidden.
                    // Fetch another page without requiring an empty-list scroll.
                    if (allDocs.length < 15 &&
                        (privatePager.hasMore || groupPager.hasMore) &&
                        !privatePager.isLoadingMore && !groupPager.isLoadingMore) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _loadMoreConversations();
                      });
                    }
                    return CustomScrollView(
                      controller: _inboxScrollController,
                      slivers: [
                        // بانر طلبات الرسائل
                        SliverToBoxAdapter(
                          child: Consumer<custom.AuthProvider>(
                            builder: (context, auth, _) {
                              if (auth.currentUser?.hideMessageRequestBanner == true) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                color: surfaceCard,
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.close, color: textGrey),
                                      onPressed: () {
                                        _handleMessageRequestBannerAction(context, allow: false);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        "السماح باستقبال طلبات المراسلة",
                                        style: TextStyle(color: Colors.white, fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton(
                                      onPressed: () {
                                        _handleMessageRequestBannerAction(context, allow: true);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: titiRed,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        "سماح",
                                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 1)),
                        const SliverToBoxAdapter(child: StoriesBar()),
                        const SliverToBoxAdapter(child: SystemNotificationsBanner()),
                        const SliverToBoxAdapter(child: ActivityBanner()),
                        const SliverToBoxAdapter(child: NewFollowersBanner()),
                        // [Tini]: زر الأرشيف معاينة أول 2 اسم + الباقي
                        SliverToBoxAdapter(
                          child: Consumer<ChatProvider>(
                            builder: (context, chat, _) {
                              if (currentUid == null) return const SizedBox.shrink();
                              return StreamBuilder<QuerySnapshot>(
                                stream: _archivedRoomsStream,
                                builder: (context, archivedSnap) {
                                  if (!archivedSnap.hasData || archivedSnap.data!.docs.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  final docs = archivedSnap.data!.docs;
                                  final totalCount = docs.length;
                                  final List<String> names = [];
                                  for (int i = 0; i < docs.length && i < 2; i++) {
                                    final data = docs[i].data() as Map<String, dynamic>;
                                    final participants = List<String>.from(data['participants'] ?? []);
                                    final otherUid = participants.firstWhere((id) => id != currentUid, orElse: () => '');
                                    final participantsInfo = Map<String, dynamic>.from(data['participantsInfo'] ?? {});
                                    final otherInfo = Map<String, dynamic>.from(participantsInfo[otherUid] ?? {});
                                    names.add(otherInfo['name'] ?? 'مستخدم');
                                  }
                                  String subtitle = names.join('، ');
                                  if (subtitle.isNotEmpty && totalCount > 2) {
                                    subtitle += ' + ${totalCount - 2} أخرى';
                                  }
                                  return ListTile(
                                        onTap: () {
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchivedChatsScreen()));
                                        },
                                        leading: Container(
                                          width: 52,
                                          height: 52,
                                          decoration: const BoxDecoration(color: Color(0xFF1E88E5), shape: BoxShape.circle),
                                          child: const Icon(Icons.archive_outlined, color: Colors.white, size: 28),
                                        ),
                                        title: const Text('الأرشيف', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                        subtitle: subtitle.isNotEmpty
                                            ? Text(subtitle, style: const TextStyle(color: textGrey, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)
                                            : null,
                                        trailing: const Icon(Icons.arrow_forward_ios, color: textGrey, size: 16),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      );
                                },
                              );
                            },
                          ),
                        ),
                        // ليست المحادثات
                        if (allDocs.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(top: 100),
                              child: Center(child: Text("لا توجد محادثات حالياً", style: TextStyle(color: textGrey))),
                            ),
                          )
                        else
                          SliverList.separated(
                            itemCount: allDocs.length,
                            separatorBuilder: (context, index) => const Divider(color: Colors.white12, height: 1),
                            itemBuilder: (context, index) {
                              final doc = allDocs[index];
                              final chatData = doc.data() as Map<String, dynamic>;
                              final bool isGroup = doc.reference.parent.id == 'group_chats';

                              // ====== اذا جروب - الجديد مع الضغط المطول بنفس منطق الخاص ======
                              if (isGroup) {
                                final groupName = chatData['groupName'] ?? 'مجموعة';
                                final groupImage = chatData['groupImage']?.toString() ?? '';
                                final lastMessage = chatData['lastMessage'] ?? '';
                                final lastMessageTime = chatData['lastMessageTime'] as Timestamp?;
                                final unreadMap = Map<String, dynamic>.from(chatData['unreadCount'] ?? {});
                                final unread = (unreadMap[currentUid] ?? 0) as int;
                                final members = List<String>.from(chatData['members'] ?? []);

                                final pinnedMap = Map<String, dynamic>.from(chatData['pinned'] ?? {});
                                final isPinned = (pinnedMap[currentUid] ?? false) as bool;

                                final mutedMap = Map<String, dynamic>.from(chatData['muted'] ?? {});
                                final isMuted = (mutedMap[currentUid] ?? false) as bool;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  leading: FutureBuilder<List<String>>(
                                    future: _getGroupMemberPhotos(members),
                                    builder: (context, photoSnap) {
                                      final photos = photoSnap.data?? [];
                                      return _buildGroupAvatar(groupImage, photos);
                                    },
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          groupName,
                                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isPinned) const Icon(Icons.push_pin, color: Colors.white54, size: 16),
                                      if (isMuted) const SizedBox(width: 4),
                                      if (isMuted) const Icon(Icons.notifications_off, color: Colors.white54, size: 16),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.group, color: Colors.white54, size: 16),
                                    ],
                                  ),
                                  subtitle: Text(
                                    members.length > 1 ? '${members.length} أعضاء • $lastMessage' : lastMessage,
                                    style: const TextStyle(color: textGrey, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_formatTime(lastMessageTime), style: const TextStyle(color: textGrey, fontSize: 12)),
                                      if (unread > 0) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: const BoxDecoration(color: titiRed, shape: BoxShape.circle),
                                          child: Text(
                                            '$unread',
                                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  onLongPress: () {
                                    _showGroupChatOptions(
                                      context: context,
                                      groupId: doc.id,
                                      groupName: groupName,
                                      isPinned: isPinned,
                                      isMuted: isMuted,
                                    );
                                  },
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => GroupChatScreen(groupId: doc.id),
                                      ),
                                    );
                                  },
                                );
                              }

                              // ====== اذا خاص - نفس كودك القديم 100% بدون تخريب ======
                              final participants = List<String>.from(chatData['participants'] ?? []);
                              final otherUid = participants.firstWhere(
                                (id) => id != currentUid,
                                orElse: () => '',
                              );

                              final participantsInfo = Map<String, dynamic>.from(chatData['participantsInfo'] ?? {});
                              final otherInfo = Map<String, dynamic>.from(participantsInfo[otherUid] ?? {});

                              final name = otherInfo['name'] ?? 'مستخدم';
                              final profileImg = otherInfo['profileImg'] ?? '';
                              final isFriend = otherInfo['isFriend'] ?? false;

                              final lastMessage = chatData['lastMessage'] ?? '';
                              final lastMessageSenderId = chatData['lastMessageSenderId'] ?? '';
                              final lastMessageTime = chatData['lastMessageTime'] as Timestamp?;

                              final unreadMap = Map<String, dynamic>.from(chatData['unreadCount'] ?? {});
                              final unread = (unreadMap[currentUid] ?? 0) as int;

                              final pinnedMap = Map<String, dynamic>.from(chatData['pinned'] ?? {});
                              final isPinned = (pinnedMap[currentUid] ?? false) as bool;

                              final mutedMap = Map<String, dynamic>.from(chatData['muted'] ?? {});
                              final isMuted = (mutedMap[currentUid] ?? false) as bool;

                              String subtitle = lastMessage;
                              if (lastMessageSenderId == currentUid && lastMessage.isNotEmpty) {
                                subtitle = 'أنت: $lastMessage';
                              }

                              return ListTile(
                                key: ValueKey(doc.id),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: _buildAvatarWithStory(
                                  uid: otherUid,
                                  name: name,
                                  profileImg: profileImg,
                                  currentUid: currentUid,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isPinned) const Icon(Icons.push_pin, color: Colors.white54, size: 16),
                                    if (isMuted) const SizedBox(width: 4),
                                    if (isMuted) const Icon(Icons.notifications_off, color: Colors.white54, size: 16),
                                  ],
                                ),
                                subtitle: Text(
                                  subtitle,
                                  style: const TextStyle(color: textGrey, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(_formatTime(lastMessageTime), style: const TextStyle(color: textGrey, fontSize: 12)),
                                    if (unread > 0) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: const BoxDecoration(color: titiRed, shape: BoxShape.circle),
                                        child: Text(
                                          '$unread',
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                onLongPress: () {
                                  _showChatOptions(
                                    context: context,
                                    roomId: doc.id,
                                    otherUid: otherUid,
                                    name: name,
                                    isPinned: isPinned,
                                    isMuted: isMuted,
                                  );
                                },
                                onTap: () {
                                  Provider.of<ChatProvider>(context, listen: false).markAsRead(doc.id, currentUid);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChatScreen(
                                        viewedUid: otherUid,
                                        displayFullName: name,
                                        displayProfileImg: profileImg,
                                        isFriend: isFriend,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        if (privatePager.error != null || groupPager.error != null)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('تعذر تحديث بعض المحادثات. اسحب للتحديث أو تحقق من الاتصال.',
                                  style: TextStyle(color: titiRed, fontSize: 12), textAlign: TextAlign.center),
                            ),
                          ),
                        if (privatePager.hasMore || groupPager.hasMore ||
                            privatePager.isLoadingMore || groupPager.isLoadingMore)
                          SliverToBoxAdapter(
                            child: Center(
                              child: (privatePager.isLoadingMore || groupPager.isLoadingMore)
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(color: titiTeal, strokeWidth: 2),
                                    )
                                  : TextButton(
                                      onPressed: _loadMoreConversations,
                                      child: const Text('تحميل محادثات أقدم', style: TextStyle(color: titiTeal)),
                                    ),
                            ),
                          ),
                      ],
                    );
              },
            ),
    );
  }

  Widget _buildStoryItem(bool isCreate, String name, Color iconColor, Color bgColor, Color surfaceColor,
      {bool hasLockIcon = false, bool hasStarRing = false, bool hasActiveStar = false}) {
    return Container(
      width: 85,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (hasStarRing)
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: iconColor, width: 2),
                  ),
                ),
              CircleAvatar(
                radius: 30,
                backgroundColor: isCreate? surfaceColor : Colors.white10,
                child: isCreate
                ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(Icons.add, color: iconColor, size: 28),
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: CircleAvatar(
                                radius: 8,
                                backgroundColor: iconColor,
                                child: const Icon(Icons.star_rounded, color: Colors.white, size: 10)),
                          ),
                        ],
                      )
                    : (hasActiveStar
                    ? Stack(
                            alignment: Alignment.center,
                            children: [
                              const Text("📸", style: TextStyle(fontSize: 26)),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(color: Color(0xFF009688), shape: BoxShape.circle),
                                  child: const Icon(Icons.star_rounded, color: Colors.white, size: 12),
                                ),
                              ),
                            ],
                          )
                        : (hasLockIcon
                        ? Icon(Icons.lock_outline, color: iconColor, size: 30)
                            : Text(name[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(color: Colors.white, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
