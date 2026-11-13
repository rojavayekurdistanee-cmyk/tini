import 'user_documents.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'chat_provider.dart';
import 'post_view_screen.dart'; // [أضيف - الخطوة 3]
import 'user_profile_sheet.dart'; // [Titi Update]: لفتح بروفايل اليوزر
import 'story.dart';
import 'story_ring.dart';
import 'auth_provider.dart' as custom;
import 'package:cached_network_image/cached_network_image.dart';
import 'profile_screen.dart';
import 'visits_screen.dart';
import 'chat_screen.dart';
import 'titi_single_engine.dart';
import 'activity_grouping.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final ValueNotifier<Set<String>> _selectedIds = ValueNotifier({});
  final ValueNotifier<bool> _isSelectionMode = ValueNotifier(false);
  final Set<String> _hiddenActivityIds = {};
  late final Stream<QuerySnapshot> _activitiesStream;
  final Map<String, Future<Map<String, dynamic>>> _profileFutures = {};
  final Map<String, Future<DocumentSnapshot>> _postFutures = {};

  Future<Map<String, dynamic>> _loadProfile(String uid) =>
      _profileFutures.putIfAbsent(uid, () async {
        try {
          final doc = await UserDocuments.readable(
            FirebaseFirestore.instance,
            uid,
          ).get();
          return doc.data() ?? <String, dynamic>{};
        } catch (_) {
          return <String, dynamic>{};
        }
      });

  Future<DocumentSnapshot> _loadPost(String id) => _postFutures.putIfAbsent(
    id,
    () => FirebaseFirestore.instance.collection('posts').doc(id).get(),
  );

  @override
  void dispose() {
    _selectedIds.dispose();
    _isSelectionMode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _activitiesStream = FirebaseFirestore.instance
        .collection('activities')
        .where('toUid', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
    timeago.setLocaleMessages('ar', timeago.ArMessages());
    // علّم الكل مقروء لما يفتح الصفحة
    Future.microtask(() {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        context.read<ChatProvider>().markAllActivitiesSeen(uid);
      }
    });
  }

  void _enterSelectionMode(Set<String> ids) {
    _isSelectionMode.value = true;
    final newSet = Set<String>.from(_selectedIds.value)..addAll(ids);
    _selectedIds.value = newSet;
  }

  void _toggleSelection(Set<String> ids) {
    final newSet = Set<String>.from(_selectedIds.value);
    if (ids.every(newSet.contains)) {
      newSet.removeAll(ids);
    } else {
      newSet.addAll(ids);
    }
    _selectedIds.value = newSet;
    if (newSet.isEmpty) {
      _isSelectionMode.value = false;
    }
  }

  void _clearSelection() {
    _selectedIds.value = {};
    _isSelectionMode.value = false;
  }

  Future<void> _openPost(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final type = data['type'] ?? 'like';
    final postId = data['postId'];
    final fromUid = data['fromUid'];

    // [FIX] اذا اشعار رسالة افتح الشات
    if (type == 'message' || type == 'chat') {
      if (fromUid != null && fromUid.toString().isNotEmpty) {
        final userDoc = await UserDocuments.readable(
          FirebaseFirestore.instance,
          fromUid,
        ).get();
        final u = userDoc.data() ?? {};
        final fullName = u['fullName'] ?? u['username'] ?? 'مستخدم';
        final profileImg = u['profileImg'] ?? '';

        // تأكد انك عامل import لـ chat_screen.dart فوق
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              viewedUid: fromUid,
              displayFullName: fullName,
              displayProfileImg: profileImg,
              isFriend: true,
            ),
          ),
        );
      }
      return;
    }

    // [Tini] ستوري جديد أو لايك/مشاهدة ستوري
    if (type.startsWith('story_')) {
      if (fromUid != null && fromUid.toString().isNotEmpty) {
        try {
          TitiSingleEngine().player.pause();
        } catch (_) {}
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => Story(userId: fromUid)),
        );
      }
      return;
    }

    if (type == 'view') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VisitsScreen()),
      );
      return;
    }
    if (type == 'follow') {
      if (fromUid != null && fromUid.toString().isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfileScreen(userId: fromUid)),
        );
      }
      return;
    }
    if (postId != null) {
      try {
        final postDoc = await FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .get();
        if (!postDoc.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'الفيديو محذوف',
                style: TextStyle(fontFamily: 'Tajawal'),
              ),
            ),
          );
          return;
        }
        final bool openComments = [
          'comment',
          'reply',
          'comment_like',
        ].contains(type);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostViewScreen(
              posts: [postDoc],
              initialIndex: 0,
              openComments: openComments,
              highlightCommentId: data['commentId'],
            ),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ: $e',
              style: const TextStyle(fontFamily: 'Tajawal'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleTap(BuildContext context, ActivityGroup group) async {
    if (_isSelectionMode.value) {
      _toggleSelection(group.ids);
    } else {
      await _openPost(context, group.latest.data);
    }
  }

  Future<void> _deleteWithUndo(ActivityGroup group) async {
    // Remove every source document represented by this row, and keep all of
    // their original fields for undo. Never write synthetic grouped documents.
    final ids = group.ids;
    setState(() => _hiddenActivityIds.addAll(ids));
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final entry in group.entries) {
        batch.delete(
          FirebaseFirestore.instance.collection('activities').doc(entry.id),
        );
      }
      await batch.commit();
    } catch (_) {
      if (!mounted) return;
      setState(() => _hiddenActivityIds.removeAll(ids));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('فشل الحذف')));
      return;
    }
    if (!mounted) return;
    _selectedIds.value = Set<String>.from(_selectedIds.value)..removeAll(ids);
    if (_selectedIds.value.isEmpty) _isSelectionMode.value = false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'تم حذف الإشعار',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
        backgroundColor: const Color(0xFF1A222C),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: Colors.teal,
          onPressed: () async {
            try {
              final batch = FirebaseFirestore.instance.batch();
              for (final entry in group.entries) {
                batch.set(
                  FirebaseFirestore.instance
                      .collection('activities')
                      .doc(entry.id),
                  entry.data,
                );
              }
              await batch.commit();
              if (mounted) setState(() => _hiddenActivityIds.removeAll(ids));
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تعذر التراجع عن الحذف')),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final idsToDelete = Set<String>.from(_selectedIds.value);
    if (idsToDelete.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in idsToDelete) {
        batch.delete(
          FirebaseFirestore.instance.collection('activities').doc(id),
        );
      }
      await batch.commit();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل الحذف',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          backgroundColor: const Color(0xFFE53935),
        ),
      );
      return;
    }

    _clearSelection();
  }

  Future<void> _deleteAllActivities() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection('activities')
        .where('toUid', isEqualTo: uid)
        .get();

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل حذف الكل',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }

    _clearSelection();
  }

  void _confirmDeleteAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A222C),
        title: const Text(
          'حذف كل الإشعارات',
          style: TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
        ),
        content: const Text(
          'هل أنت متأكد؟ لا يمكن التراجع.',
          style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'إلغاء',
              style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal'),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAllActivities();
            },
            child: const Text(
              'حذف',
              style: TextStyle(color: Color(0xFFE53935), fontFamily: 'Tajawal'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A222C),
        elevation: 0,
        title: ValueListenableBuilder<bool>(
          valueListenable: _isSelectionMode,
          builder: (context, isSelecting, _) {
            return ValueListenableBuilder<Set<String>>(
              valueListenable: _selectedIds,
              builder: (context, selected, _) {
                return isSelecting
                    ? Text(
                        '${selected.length} محدد',
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'النشاط',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          color: Colors.white,
                        ),
                      );
              },
            );
          },
        ),
        centerTitle: true,
        leading: ValueListenableBuilder<bool>(
          valueListenable: _isSelectionMode,
          builder: (context, isSelecting, _) {
            return isSelecting
                ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _clearSelection,
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  );
          },
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _isSelectionMode,
            builder: (context, isSelecting, _) {
              if (!isSelecting) {
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: const Color(0xFF1A222C),
                  onSelected: (v) {
                    if (v == 'delete_all') _confirmDeleteAll(context);
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'delete_all',
                      child: Text(
                        'حذف كل الإشعارات',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                    ),
                  ],
                );
              }
              return ValueListenableBuilder<Set<String>>(
                valueListenable: _selectedIds,
                builder: (context, selected, _) {
                  return IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    onPressed: selected.isEmpty ? null : _deleteSelected,
                  );
                },
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _activitiesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)),
            );
          }
          if (snapshot.hasData) {
            final visibleIds = snapshot.data!.docs.map((doc) => doc.id).toSet();
            // A confirmed removal must not hide a later event reusing the same ID.
            _hiddenActivityIds.removeWhere((id) => !visibleIds.contains(id));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'لا يوجد نشاط بعد',
                style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal'),
              ),
            );
          }

          final groups = groupActivities(
            snapshot.data!.docs
                .where((doc) => !_hiddenActivityIds.contains(doc.id))
                .map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return ActivityEntry(
                    id: doc.id,
                    data: data,
                    timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
                  );
                }),
          );
          if (groups.isEmpty) {
            return const Center(
              child: Text(
                'لا يوجد نشاط بعد',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final group = groups[i];
              final data = group.latest.data;
              final activityId = group.key;

              return ValueListenableBuilder<bool>(
                valueListenable: _isSelectionMode,
                builder: (context, isSelecting, _) {
                  return Dismissible(
                    key: ValueKey((activityId, group.ids.join('|'))),
                    direction: isSelecting
                        ? DismissDirection.none
                        : DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                    ),
                    onDismissed: (_) => _deleteWithUndo(group),
                    child: ValueListenableBuilder<Set<String>>(
                      valueListenable: _selectedIds,
                      builder: (context, selected, _) {
                        return _ActivityTile(
                          activityId: activityId,
                          data: data,
                          group: group,
                          loadProfile: _loadProfile,
                          loadPost: _loadPost,
                          isSelected: group.ids.every(selected.contains),
                          isSelectionMode: isSelecting,
                          onTap: () => _handleTap(context, group),
                          onLongPress: () => _enterSelectionMode(group.ids),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final String activityId;
  final Map<String, dynamic> data;
  final ActivityGroup group;
  final Future<Map<String, dynamic>> Function(String) loadProfile;
  final Future<DocumentSnapshot> Function(String) loadPost;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _ActivityTile({
    required this.group,
    required this.loadProfile,
    required this.loadPost,
    required this.activityId,
    required this.data,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  IconData _icon(String type) {
    switch (type) {
      case 'comment':
        return Icons.chat_bubble_outline;
      case 'reply':
        return Icons.reply;
      case 'comment_like':
        return Icons.favorite;
      case 'share':
        return Icons.reply_all_rounded;
      case 'download':
        return Icons.download_outlined;
      case 'follow':
        return Icons.person_add_alt_1;
      case 'favorite':
        return Icons.bookmark_border_rounded;
      case 'view':
        return Icons.visibility_outlined;
      case 'mention':
      case 'duet':
        return Icons.alternate_email;
      case 'story_new':
        return Icons.add_circle_outline;
      case 'story_view':
        return Icons.play_circle_outline;
      case 'story_like':
        return Icons.favorite;
      case 'like':
      default:
        return Icons.favorite_border_rounded;
    }
  }

  Color _iconColor(String type) {
    switch (type) {
      case 'like':
      case 'comment_like':
      case 'story_like':
        return const Color(0xFFE53935);
      case 'follow':
        return const Color(0xFF4CAF50);
      case 'comment':
      case 'reply':
        return const Color(0xFF29B6F6);
      case 'story_new':
        return const Color(0xFFFF9800);
      case 'story_view':
        return const Color(0xFF9C27B0);
      default:
        return Colors.white70;
    }
  }

  void _toggleFollow(BuildContext context, String targetUid) async {
    try {
      await context.read<custom.AuthProvider>().toggleFollow(targetUid);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ: $e',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fromUid = data['fromUid'] ?? '';
    final type = data['type'] ?? 'like';
    final text = group.text;
    final ts = (data['timestamp'] as Timestamp?)?.toDate();

    final actors = group.actorUids.take(2).toList();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Future.wait(actors.map(loadProfile)),
      builder: (context, userSnap) {
        String name = 'مستخدم';
        String? photoUrl;
        String username = '';
        String fullName = 'مستخدم';
        final profiles = userSnap.data ?? <Map<String, dynamic>>[];
        if (profiles.isNotEmpty && profiles.first.isNotEmpty) {
          final u = profiles.first;
          fullName = u['fullName'] ?? u['username'] ?? 'مستخدم';
          username = u['username'] ?? '';
          name = fullName;
          photoUrl = u['profileImg'];
        }
        final names = List.generate(actors.length, (index) {
          final profile = index < profiles.length ? profiles[index] : null;
          return (profile?['fullName'] ?? profile?['username'] ?? 'مستخدم')
              .toString();
        });
        final secondary = profiles.length > 1
            ? profiles[1]
            : <String, dynamic>{};
        final secondaryPhoto = (secondary['profileImg'] ?? '').toString();
        final title = group.hasMultipleActors ? group.title(names) : name;
        final initial = name.isNotEmpty ? name.characters.first : '؟';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1C2E3A)
                    : const Color(0xFF1A222C),
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(color: Colors.teal, width: 1.5)
                    : null,
              ),
              child: Row(
                children: [
                  if (isSelectionMode) ...[
                    Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected ? Colors.teal : Colors.white54,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                  ],
                  SizedBox(
                    width: group.hasMultipleActors ? 58 : 44,
                    height: group.hasMultipleActors ? 58 : 44,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          child: GestureDetector(
                            onTap: () {
                              if (fromUid.isNotEmpty) {
                                UserProfileSheet.show(
                                  context,
                                  fullName: fullName,
                                  username: username,
                                  profileImg: photoUrl ?? '',
                                  uid: fromUid,
                                  isFollowing: false,
                                  onFollowTap: () =>
                                      _toggleFollow(context, fromUid),
                                );
                              }
                            },
                            child: StreamBuilder<QuerySnapshot>(
                              stream: fromUid.toString().isEmpty
                                  ? null
                                  : FirebaseFirestore.instance
                                        .collection('stories')
                                        .doc(fromUid)
                                        .collection('items')
                                        .where(
                                          'expiresAt',
                                          isGreaterThan: Timestamp.now(),
                                        )
                                        .snapshots(),
                              builder: (context, snap) {
                                final docs = snap.data?.docs ?? [];
                                final currentUid =
                                    FirebaseAuth.instance.currentUser?.uid ??
                                    '';
                                final hasStories = docs.isNotEmpty;
                                final hasUnviewed = docs.any((d) {
                                  final viewedBy = List<String>.from(
                                    d['viewedBy'] ?? [],
                                  );
                                  return !viewedBy.contains(currentUid);
                                });

                                // [مُصحح] رجعنا منطق الحرف
                                final bool hasImage =
                                    photoUrl != null && photoUrl.isNotEmpty;

                                if (hasStories) {
                                  return StoryRing(
                                    imageUrl: photoUrl ?? '',
                                    size: 44,
                                    hasStories: true,
                                    hasUnviewed: hasUnviewed,
                                    heroTag:
                                        'activity-avatar-$activityId-$fromUid',
                                  );
                                } else if (hasImage) {
                                  return CachedNetworkImage(
                                    imageUrl: photoUrl,
                                    cacheKey: photoUrl,
                                    useOldImageOnUrlChange: false,
                                    imageBuilder: (context, imageProvider) =>
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundImage: imageProvider,
                                        ),
                                    placeholder: (context, url) => CircleAvatar(
                                      radius: 22,
                                      backgroundColor: const Color(0xFF0F1720),
                                      child: SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white24,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: const Color(
                                            0xFF0F1720,
                                          ),
                                          child: Text(
                                            initial,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                  );
                                } else {
                                  return CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFF0F1720),
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        if (group.hasMultipleActors && actors.length > 1)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: GestureDetector(
                              onTap: () {
                                if (profiles.length < 2) return;
                                final u = profiles[1];
                                UserProfileSheet.show(
                                  context,
                                  fullName: names[1],
                                  username: u['username'] ?? '',
                                  profileImg: u['profileImg'] ?? '',
                                  uid: actors[1],
                                  isFollowing: false,
                                  onFollowTap: () =>
                                      _toggleFollow(context, actors[1]),
                                );
                              },
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFF1A222C),
                                child: _ActivityActorAvatar(
                                  photoUrl: secondaryPhoto,
                                  name: names.length > 1 ? names[1] : 'مستخدم',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Tajawal',
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.right,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Tajawal',
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (ts != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            timeago.format(ts, locale: 'ar'),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontFamily: 'Tajawal',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (group.latest.postId.isNotEmpty &&
                      !type.startsWith('story_'))
                    _ActivityPostThumbnail(
                      post: loadPost(group.latest.postId),
                      fallback: Icon(
                        _icon(type),
                        color: _iconColor(type),
                        size: 18,
                      ),
                    )
                  else
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF0F1720),
                      child: Icon(
                        _icon(type),
                        color: _iconColor(type),
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActivityPostThumbnail extends StatelessWidget {
  final Future<DocumentSnapshot> post;
  final Widget fallback;
  const _ActivityPostThumbnail({required this.post, required this.fallback});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 54,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: FutureBuilder<DocumentSnapshot>(
        future: post,
        builder: (context, snapshot) {
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final url = (data?['thumbnailUrl'] ?? '').toString();
          final placeholder = ColoredBox(
            color: const Color(0xFF0F1720),
            child: Center(child: fallback),
          );
          if (url.isEmpty) return placeholder;
          return CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
        },
      ),
    ),
  );
}

class _ActivityActorAvatar extends StatelessWidget {
  final String photoUrl;
  final String name;
  const _ActivityActorAvatar({required this.photoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: 16,
      backgroundColor: const Color(0xFF0F1720),
      child: Text(
        name.isEmpty ? '؟' : name.characters.first,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
    if (photoUrl.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: photoUrl,
      width: 32,
      height: 32,
      imageBuilder: (_, image) =>
          CircleAvatar(radius: 16, backgroundImage: image),
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}
