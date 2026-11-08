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
import 'post_provider.dart';
import 'chat_screen.dart';
import 'titi_single_engine.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final ValueNotifier<Set<String>> _selectedIds = ValueNotifier({});
  final ValueNotifier<bool> _isSelectionMode = ValueNotifier(false);

  @override
  void dispose() {
    _selectedIds.dispose();
    _isSelectionMode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('ar', timeago.ArMessages());
    // علّم الكل مقروء لما يفتح الصفحة
    Future.microtask(() {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid!= null) {
        context.read<ChatProvider>().markAllActivitiesSeen(uid);
      }
    });
  }

  void _enterSelectionMode(String id) {
    _isSelectionMode.value = true;
    final newSet = Set<String>.from(_selectedIds.value)..add(id);
    _selectedIds.value = newSet;
  }

  void _toggleSelection(String id) {
    final newSet = Set<String>.from(_selectedIds.value);
    if (newSet.contains(id)) {
      newSet.remove(id);
    } else {
      newSet.add(id);
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

    Future<void> _openPost(BuildContext context, Map<String, dynamic> data) async {
    final type = data['type']?? 'like';
    final postId = data['postId'];
    final fromUid = data['fromUid'];

    // [FIX] اذا اشعار رسالة افتح الشات
  if (type == 'message' || type == 'chat') {
    if (fromUid != null && fromUid.toString().isNotEmpty) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(fromUid).get();
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
      if (fromUid!= null && fromUid.toString().isNotEmpty) {
        try {
          TitiSingleEngine().player.pause();
        } catch (_) {}
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Story(userId: fromUid),
          ),
        );
      }
      return;
    }

    if (type == 'view') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const VisitsScreen(),
        ),
      );
      return;
    }
    if (type == 'follow') {
      if (fromUid!= null && fromUid.toString().isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(userId: fromUid),
          ),
        );
      }
      return;
    }
    if (postId!= null) {
      try {
        final postDoc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
        if (!postDoc.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الفيديو محذوف', style: TextStyle(fontFamily: 'Tajawal'))),
          );
          return;
        }
        final bool openComments = ['comment', 'reply', 'comment_like'].contains(type);
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
          SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Tajawal'))),
        );
      }
    }
  }

  Future<void> _handleTap(BuildContext context, String activityId, Map<String, dynamic> data) async {
    if (_isSelectionMode.value) {
      _toggleSelection(activityId);
    } else {
      await _openPost(context, data);
    }
  }

  void _deleteWithUndo(BuildContext context, String activityId, Map<String, dynamic> data, int index) async {
    final docRef = FirebaseFirestore.instance.collection('activities').doc(activityId);

    try {
      await docRef.delete();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحذف', style: const TextStyle(fontFamily: 'Tajawal')), backgroundColor: const Color(0xFFE53935)),
      );
      return;
    }

    if (_selectedIds.value.contains(activityId)) {
      final newSet = Set<String>.from(_selectedIds.value)..remove(activityId);
      _selectedIds.value = newSet;
      if (newSet.isEmpty) _isSelectionMode.value = false;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم حذف الإشعار', style: TextStyle(fontFamily: 'Tajawal')),
        backgroundColor: const Color(0xFF1A222C),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: Colors.teal,
          onPressed: () async {
            await docRef.set(data);
          },
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final idsToDelete = Set<String>.from(_selectedIds.value);
    if (idsToDelete.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in idsToDelete) {
        batch.delete(FirebaseFirestore.instance.collection('activities').doc(id));
      }
      await batch.commit();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحذف', style: const TextStyle(fontFamily: 'Tajawal')), backgroundColor: const Color(0xFFE53935)),
      );
      return;
    }

    _clearSelection();
  }

  Future<void> _deleteAllActivities() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance.collection('activities').where('toUid', isEqualTo: uid).get();

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل حذف الكل', style: const TextStyle(fontFamily: 'Tajawal'))),
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
        title: const Text('حذف كل الإشعارات', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
        content: const Text('هل أنت متأكد؟ لا يمكن التراجع.', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAllActivities();
            },
            child: const Text('حذف', style: TextStyle(color: Color(0xFFE53935), fontFamily: 'Tajawal')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

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
          ? Text('${selected.length} محدد', style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white))
                  : const Text('النشاط', style: TextStyle(fontFamily: 'Tajawal', color: Colors.white));
              },
            );
          },
        ),
        centerTitle: true,
        leading: ValueListenableBuilder<bool>(
          valueListenable: _isSelectionMode,
          builder: (context, isSelecting, _) {
            return isSelecting
      ? IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _clearSelection)
              : IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context));
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
                    const PopupMenuItem(value: 'delete_all', child: Text('حذف كل الإشعارات', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal'))),
                  ],
                );
              }
              return ValueListenableBuilder<Set<String>>(
                valueListenable: _selectedIds,
                builder: (context, selected, _) {
                  return IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white), onPressed: selected.isEmpty? null : _deleteSelected);
                },
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('activities').where('toUid', isEqualTo: uid).orderBy('timestamp', descending: true).limit(100).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('لا يوجد نشاط بعد', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal')));
          }

          final docs = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final activityId = doc.id;

              return ValueListenableBuilder<bool>(
                valueListenable: _isSelectionMode,
                builder: (context, isSelecting, _) {
                  return Dismissible(
                    key: ValueKey(activityId),
                    direction: isSelecting? DismissDirection.none : DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(color: const Color(0xFFE53935).withValues(alpha:0.9), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                    onDismissed: (_) => _deleteWithUndo(context, activityId, data, i),
                    child: ValueListenableBuilder<Set<String>>(
                      valueListenable: _selectedIds,
                      builder: (context, selected, _) {
                        return _ActivityTile(
                          activityId: activityId,
                          data: data,
                          isSelected: selected.contains(activityId),
                          isSelectionMode: isSelecting,
                          onTap: () => _handleTap(context, activityId, data),
                          onLongPress: () => _enterSelectionMode(activityId),
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
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _ActivityTile({required this.activityId, required this.data, required this.isSelected, required this.isSelectionMode, required this.onTap, required this.onLongPress});

    IconData _icon(String type) {
    switch (type) {
      case 'comment': return Icons.chat_bubble_outline;
      case 'reply': return Icons.reply;
      case 'comment_like': return Icons.favorite;
      case 'share': return Icons.reply_all_rounded;
      case 'follow': return Icons.person_add_alt_1;
      case 'favorite': return Icons.bookmark_border_rounded;
      case 'view': return Icons.visibility_outlined;
      case 'mention': return Icons.alternate_email;
      case 'story_new': return Icons.add_circle_outline;
      case 'story_view': return Icons.play_circle_outline;
      case 'story_like': return Icons.favorite;
      case 'like':
      default: return Icons.favorite_border_rounded;
    }
  }

    Color _iconColor(String type) {
    switch (type) {
      case 'like':
      case 'comment_like':
      case 'story_like': return const Color(0xFFE53935);
      case 'follow': return const Color(0xFF4CAF50);
      case 'comment':
      case 'reply': return const Color(0xFF29B6F6);
      case 'story_new': return const Color(0xFFFF9800);
      case 'story_view': return const Color(0xFF9C27B0);
      default: return Colors.white70;
    }
  }

    void _toggleFollow(BuildContext context, String targetUid) async {
    try {
      await context.read<custom.AuthProvider>().toggleFollow(targetUid);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Tajawal'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fromUid = data['fromUid']?? '';
    final type = data['type']?? 'like';
    final text = data['text']?? '';
    final ts = (data['timestamp'] as Timestamp?)?.toDate();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(fromUid).get(),
      builder: (context, userSnap) {
        String name = 'مستخدم';
        String? photoUrl;
        String username = '';
        String fullName = 'مستخدم';
        if (userSnap.hasData && userSnap.data!.exists) {
          final u = userSnap.data!.data() as Map<String, dynamic>;
          fullName = u['fullName']?? u['username']?? 'مستخدم';
          username = u['username']?? '';
          name = fullName;
          photoUrl = u['profileImg'];
        }
        final initial = name.isNotEmpty? name.characters.first : '؟';

        return Material(
  color: Colors.transparent,
  child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected? const Color(0xFF1C2E3A) : const Color(0xFF1A222C),
              borderRadius: BorderRadius.circular(12),
              border: isSelected? Border.all(color: Colors.teal, width: 1.5) : null,
            ),
            child: Row(
              children: [
                if (isSelectionMode)...[
                  Icon(isSelected? Icons.check_circle : Icons.circle_outlined, color: isSelected? Colors.teal : Colors.white54, size: 22),
                  const SizedBox(width: 12),
                ],
                GestureDetector(
                  onTap: () {
                    if (fromUid.isNotEmpty) {
                      UserProfileSheet.show(context, fullName: fullName, username: username, profileImg: photoUrl?? '', uid: fromUid, isFollowing: false, onFollowTap: () => _toggleFollow(context, fromUid));
                    }
                  },
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                     .collection('stories')
                     .doc(fromUid)
                     .collection('items')
                     .where('expiresAt', isGreaterThan: Timestamp.now())
                     .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs?? [];
                      final currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
                      final hasStories = docs.isNotEmpty;
                      final hasUnviewed = docs.any((d) {
                        final viewedBy = List<String>.from(d['viewedBy']?? []);
                        return!viewedBy.contains(currentUid);
                      });

                      // [مُصحح] رجعنا منطق الحرف
                      final bool hasImage = photoUrl!= null && photoUrl.isNotEmpty;

                      if (hasStories) {
                        return StoryRing(
                          imageUrl: photoUrl?? '',
                          size: 44,
                          hasStories: true,
                          hasUnviewed: hasUnviewed,
                          heroTag: 'activity-avatar-$fromUid',
                        );
                                            } else if (hasImage) {
                        return CachedNetworkImage(
                          imageUrl: photoUrl!,
                          cacheKey: photoUrl,
                          useOldImageOnUrlChange: false,
                          imageBuilder: (context, imageProvider) => CircleAvatar(
                            radius: 22,
                            backgroundImage: imageProvider,
                          ),
                          placeholder: (context, url) => CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFF0F1720),
                            child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)),
                          ),
                          errorWidget: (context, url, error) => CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFF0F1720),
                            child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        );
                      } else {
                        return CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFF0F1720),
                          child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Tajawal', fontSize: 14), textAlign: TextAlign.right),
                      const SizedBox(height: 2),
                      Text(text, style: const TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13), textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (ts!= null)...[
                        const SizedBox(height: 4),
                        Text(timeago.format(ts, locale: 'ar'), style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Tajawal')),
                      ]
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(radius: 18, backgroundColor: const Color(0xFF0F1720), child: Icon(_icon(type), color: _iconColor(type), size: 18)),
                             ],
              ),
            ),
          ),
        );
      },
    );
  }
}